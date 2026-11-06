import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../../core/inference/local_inference.dart';
import 'completion_request.dart';
import 'completion_response.dart';

class LocalApiServer {
  LocalApiServer({
    required this.inference,
    required this.coordinator,
    required String apiKey,
  }) : _key = apiKey;

  final LocalInference inference;
  final InferenceCoordinator coordinator;
  String _key;
  HttpServer? _server;
  _Completion? _active;
  final _connections = <_Completion>{};
  bool _lan = false;

  static const _maxBodyBytes = 512 * 1024;
  static const _generationTimeout = Duration(minutes: 2);
  static const _ioTimeout = Duration(seconds: 10);

  Future<int> start({required int port, required bool lan}) async {
    final address = lan
        ? InternetAddress.anyIPv4
        : InternetAddress.loopbackIPv4;
    final server = await HttpServer.bind(address, port);
    _lan = lan;
    _server = server;
    server.idleTimeout = _ioTimeout;
    server.listen((request) => unawaited(_handle(request)));
    return server.port;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    final connections = _connections.toList();
    for (final completion in connections) {
      completion.cancellation.cancel();
      completion.response?.abort();
    }
    try {
      await server?.close(force: true);
    } finally {
      await Future.wait(
        connections.map((completion) => completion.done.future),
      );
    }
  }

  void rotateKey(String key) {
    _key = key;
    _active?.cancellation.cancel();
  }

  static bool isLanAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    return address.type == InternetAddressType.IPv4 &&
        (bytes[0] == 10 ||
            (bytes[0] == 192 && bytes[1] == 168) ||
            (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
            (bytes[0] == 169 && bytes[1] == 254));
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    // Attach a handler even if the peer closes before we write a response.
    unawaited(response.done.then<void>((_) {}, onError: (Object _) {}));
    var detached = false;
    response.persistentConnection = false;
    try {
      final peer = request.connectionInfo?.remoteAddress;
      if (_server == null ||
          peer == null ||
          (!peer.isLoopback && (!_lan || !isLanAddress(peer)))) {
        throw const _ApiError(
          403,
          'Connection is outside the allowed network.',
          'forbidden',
        );
      }
      if (request.headers.value('origin') != null) {
        throw const _ApiError(
          403,
          'Browser origins are not supported.',
          'forbidden',
        );
      }
      if (!_authorized(request.headers[HttpHeaders.authorizationHeader])) {
        response.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Bearer');
        throw const _ApiError(
          401,
          'Invalid or missing API key.',
          'invalid_api_key',
        );
      }
      final path = request.uri.path;
      if (path == '/v1/models') {
        _requireMethod(request, 'GET');
        final model = inference.model;
        _json(response, {
          'object': 'list',
          'data': [
            if (model != null)
              {
                'id': model.id,
                'object': 'model',
                'created': 0,
                'owned_by': 'localmind',
              },
          ],
        });
      } else if (path == '/v1/chat/completions') {
        _requireMethod(request, 'POST');
        final completion = await _readRequest(request);
        if (_server == null) return;
        if (!_authorized(request.headers[HttpHeaders.authorizationHeader])) {
          throw const _ApiError(
            401,
            'Invalid or missing API key.',
            'invalid_api_key',
          );
        }
        await _complete(
          response,
          completion,
          onDetached: () => detached = true,
        );
      } else {
        throw const _ApiError(404, 'Endpoint not found.', 'not_found');
      }
    } on _ApiError catch (error) {
      _writeError(response, error);
    } on FormatException catch (error) {
      _writeError(response, _ApiError(400, error.message, 'invalid_request'));
    } on TimeoutException {
      _writeError(
        response,
        const _ApiError(408, 'Request timed out.', 'request_timeout'),
      );
    } catch (_) {
      _writeError(
        response,
        const _ApiError(500, 'Local inference failed.', 'inference_failed'),
      );
    } finally {
      try {
        if (!detached) await response.close().timeout(_ioTimeout);
      } catch (_) {
        // Clients may disconnect at any point.
      }
    }
  }

  bool _authorized(List<String>? values) {
    if (values == null || values.length != 1) return false;
    final expected = 'Bearer $_key'.codeUnits;
    final actual = values.single.codeUnits;
    if (actual.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < expected.length; i++) {
      difference |= expected[i] ^ actual[i];
    }
    return difference == 0;
  }

  static void _requireMethod(HttpRequest request, String method) {
    if (request.method != method) {
      request.response.headers.set(HttpHeaders.allowHeader, method);
      throw const _ApiError(405, 'Method not allowed.', 'method_not_allowed');
    }
  }

  static Future<CompletionRequest> _readRequest(HttpRequest request) async {
    if (request.headers.contentType?.mimeType != 'application/json') {
      throw const _ApiError(
        415,
        'Content-Type must be application/json.',
        'unsupported_media_type',
      );
    }
    if (request.contentLength > _maxBodyBytes) {
      throw const _ApiError(413, 'Request is too large.', 'request_too_large');
    }
    final bytes = BytesBuilder(copy: false);
    final stopwatch = Stopwatch()..start();
    await for (final chunk in request.timeout(_ioTimeout)) {
      if (stopwatch.elapsed > _ioTimeout) {
        throw TimeoutException('Request body');
      }
      if (bytes.length + chunk.length > _maxBodyBytes) {
        throw const _ApiError(
          413,
          'Request is too large.',
          'request_too_large',
        );
      }
      bytes.add(chunk);
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes.takeBytes()));
    } on FormatException {
      throw const FormatException('Invalid JSON.');
    }
    return CompletionRequest.parse(json);
  }

  Future<void> _complete(
    HttpResponse response,
    CompletionRequest completion, {
    required void Function() onDetached,
  }) async {
    final request = completion.inference;
    final model = inference.model;
    if (model == null) {
      throw const _ApiError(
        503,
        'Load a supported model in LocalMind first.',
        'model_unavailable',
      );
    }
    if (request.model != model.id) {
      throw const _ApiError(
        404,
        'The requested model is not loaded.',
        'model_not_found',
      );
    }
    if (!model.supportsTools &&
        (request.tools.isNotEmpty ||
            request.messages.any(
              (m) => m.calls.isNotEmpty || m.role == InferenceRole.tool,
            ))) {
      throw const _ApiError(
        400,
        'This model does not support tool calls.',
        'unsupported_tools',
      );
    }
    if (!model.supportsSampling &&
        (request.topP != null || request.maxTokens != null)) {
      throw const _ApiError(
        400,
        'This model uses its configured token budget and sampling settings.',
        'unsupported_sampling',
      );
    }
    final lease = coordinator.tryAcquire();
    if (lease == null) {
      response.headers.set('Retry-After', '1');
      throw const _ApiError(429, 'The on-device model is busy.', 'model_busy');
    }

    final active = _active = _Completion();
    _connections.add(active);
    final cancellation = active.cancellation;
    var timedOut = false;
    final deadline = Timer(_generationTimeout, () {
      timedOut = true;
      cancellation.cancel();
    });
    final id = 'chatcmpl-${_randomId()}';
    final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    Map<String, Object?> envelope(String object, Map<String, Object?> choice) =>
        {
          'id': id,
          'object': object,
          'created': created,
          'model': model.id,
          'choices': [
            {'index': 0, ...choice},
          ],
        };

    CompletionResponse? output;
    try {
      final socket = await response.detachSocket(writeHeaders: false);
      onDetached();
      output = active.response = CompletionResponse(
        socket,
        cancellation.cancel,
      );
      if (cancellation.isCancelled) {
        output.abort();
        return;
      }

      final writer = output;
      Future<void> chunk(Map<String, Object?> delta, {String? finish}) async {
        try {
          await writer.event(
            envelope('chat.completion.chunk', {
              'delta': delta,
              'finish_reason': finish,
            }),
          );
        } catch (_) {
          cancellation.cancel();
          rethrow;
        }
      }

      await coordinator.clearRetainedSessions();
      if (completion.stream && !cancellation.isCancelled) {
        writer.startStream();
        await chunk({'role': 'assistant', 'content': ''});
      }
      final text = StringBuffer();
      final calls = <Map<String, Object?>>[];
      var finish = 'stop';
      if (!cancellation.isCancelled) {
        await for (final event in inference.generate(request, cancellation)) {
          if (cancellation.isCancelled) continue;
          switch (event) {
            case InferenceText(text: final delta):
              if (completion.stream) {
                await chunk({'content': delta});
              } else {
                // The native context bounds output size.
                text.write(delta);
              }
            case InferenceCall(:final call):
              final index = calls.length;
              final tool = <String, Object?>{
                'id': call.id ?? 'call_${_randomId()}',
                'type': 'function',
                'function': {'name': call.name, 'arguments': call.arguments},
              };
              calls.add(tool);
              if (completion.stream) {
                await chunk({
                  'tool_calls': [
                    {'index': index, ...tool},
                  ],
                });
              }
            case InferenceFinished(:final length):
              if (length) finish = 'length';
          }
        }
      }
      if (timedOut) {
        throw const _ApiError(
          504,
          'Generation timed out.',
          'generation_timeout',
        );
      }
      if (cancellation.isCancelled) {
        throw const _ApiError(
          503,
          'Generation was cancelled.',
          'generation_cancelled',
        );
      }
      if (calls.isNotEmpty) finish = 'tool_calls';
      if (completion.stream) {
        await chunk({}, finish: finish);
        writer.endStream();
      } else {
        writer.json(
          envelope('chat.completion', {
            'message': {
              'role': 'assistant',
              'content': text.isEmpty && calls.isNotEmpty
                  ? null
                  : text.toString(),
              if (calls.isNotEmpty) 'tool_calls': calls,
            },
            'finish_reason': finish,
          }),
        );
      }
    } catch (error) {
      if (output == null) rethrow;
      final failure = error is _ApiError
          ? error
          : const _ApiError(500, 'Local inference failed.', 'inference_failed');
      try {
        await output.error(failure.status, failure.toJson());
      } catch (_) {
        // A disconnected peer cannot receive an error response.
      }
    } finally {
      deadline.cancel();
      // Release ownership after native cleanup, independently of final I/O.
      _active = null;
      lease.release();
      try {
        await output?.close();
      } catch (_) {
        // The client may have disconnected.
      } finally {
        _connections.remove(active);
        active.done.complete();
      }
    }
  }

  static void _json(HttpResponse response, Object body) {
    response.headers.contentType = ContentType.json;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.write(jsonEncode(body));
  }

  static void _writeError(HttpResponse response, _ApiError error) {
    try {
      response.statusCode = error.status;
      _json(response, error.toJson());
    } catch (_) {
      // The transport may already be closed.
    }
  }

  static String _randomId() {
    final rng = Random.secure();
    return base64Url.encode(List.generate(12, (_) => rng.nextInt(256)));
  }
}

class _ApiError implements Exception {
  const _ApiError(this.status, this.message, this.code);
  final int status;
  final String message;
  final String code;

  Map<String, Object> toJson() => {
    'error': {
      'message': message,
      'type': status >= 500 ? 'server_error' : 'invalid_request_error',
      'code': code,
    },
  };
}

class _Completion {
  final cancellation = InferenceCancellation();
  final done = Completer<void>();
  CompletionResponse? response;
}
