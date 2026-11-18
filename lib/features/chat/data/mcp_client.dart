// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:localmind/core/logger/app_logger.dart';

class McpClient {
  static const _connectTimeout = Duration(seconds: 10);
  static const _requestTimeout = Duration(seconds: 30);

  final String serverUrl;
  final Map<String, String>? headers;
  final String _version;
  final Dio _dio;
  bool _initialized = false;
  McpCapabilities? _capabilities;
  Future<McpCapabilities>? _initializationFuture;

  String? _sessionId;
  String? _protocolVersion;
  CancelToken? _sseCancelToken;
  StreamSubscription<({String event, String data})>? _sseSubscription;
  String? _postUrl;
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};
  int _requestIdCounter = 1;

  McpClient({
    required this.serverUrl,
    this.headers,
    String version = '1.0.0',
    Dio? dio,
  }) : _version = version,
       _dio = dio ?? Dio(BaseOptions(connectTimeout: _connectTimeout));

  bool get isInitialized => _initialized;
  McpCapabilities? get capabilities => _capabilities;

  Future<void> _connectSse() async {
    final cancelToken = CancelToken();
    _sseCancelToken = cancelToken;
    try {
      final response = await _dio
          .get<ResponseBody>(
            serverUrl,
            options: Options(
              headers: {
                'Accept': 'text/event-stream',
                'Cache-Control': 'no-cache',
                ...?headers,
              },
              responseType: ResponseType.stream,
              receiveDataWhenStatusError: false,
            ),
            cancelToken: cancelToken,
          )
          .timeout(_connectTimeout);

      final stream = response.data!.stream;
      if (!_isEventStream(response.headers)) {
        await stream.listen(null).cancel();
        throw McpException('Expected an SSE stream from the legacy endpoint');
      }

      final handshakeCompleter = Completer<void>();
      _sseSubscription = _sseEvents(stream).listen(
        (message) =>
            _handleSseMessage(message.event, message.data, handshakeCompleter),
        onError: (e) {
          if (!handshakeCompleter.isCompleted) {
            handshakeCompleter.completeError(e);
          }
          _handleSseDisconnect(e);
        },
        onDone: () {
          if (!handshakeCompleter.isCompleted) {
            handshakeCompleter.completeError(
              McpException('SSE stream closed before handshake completed'),
            );
          }
          _handleSseDisconnect(null);
        },
      );

      // Wait for the endpoint event or timeout
      await handshakeCompleter.future.timeout(
        _connectTimeout,
        onTimeout: () {
          throw McpException(
            'Handshake timeout waiting for SSE endpoint event',
          );
        },
      );
    } catch (_) {
      await _closeSse();
      rethrow;
    }
  }

  void _handleSseMessage(
    String event,
    String data,
    Completer<void> initCompleter,
  ) {
    if (event == 'endpoint') {
      try {
        final baseUri = Uri.parse(serverUrl);
        final resolvedUri = baseUri.resolve(data.trim());
        _postUrl = resolvedUri.toString();
        Log.debug('MCP SSE Handshake completed. Message endpoint: $_postUrl');
        if (!initCompleter.isCompleted) {
          initCompleter.complete();
        }
      } catch (e) {
        if (!initCompleter.isCompleted) {
          initCompleter.completeError(e);
        }
      }
    } else {
      try {
        final json = jsonDecode(data);
        if (json is Map<String, dynamic>) {
          final id = json['id'];
          if (id != null) {
            final key = id.toString();
            final completer = _pendingRequests.remove(key);
            if (completer != null && !completer.isCompleted) {
              completer.complete(json);
            }
          }
        }
      } catch (_) {}
    }
  }

  void _handleSseDisconnect(dynamic error) {
    final ex = McpException(
      error != null ? 'SSE disconnected: $error' : 'SSE connection closed',
    );
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(ex);
      }
    }
    _pendingRequests.clear();
    _postUrl = null;
    _initialized = false;
  }

  Future<void> _closeSse() async {
    final cancellation = _sseSubscription?.cancel();
    _sseCancelToken?.cancel();
    _sseCancelToken = null;
    _sseSubscription = null;
    _postUrl = null;
    await cancellation;
  }

  Future<Map<String, dynamic>> _sendJsonRpc(
    String method,
    Map<String, dynamic> params,
  ) async {
    final id = _requestIdCounter++;
    final payload = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    final postUrl = _postUrl;
    final response = postUrl == null
        ? (await _postHttp(payload))!
        : await _sendLegacyRequest(postUrl, payload, id);
    if (response.containsKey('error')) {
      final error = response['error'];
      final message = error is Map ? error['message'] : null;
      throw McpException(
        'Server returned error: ${message ?? 'Unknown error'}',
      );
    }
    return response;
  }

  Future<Map<String, dynamic>> _sendLegacyRequest(
    String postUrl,
    Map<String, dynamic> payload,
    int id,
  ) async {
    final key = id.toString();
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[key] = completer;
    try {
      final responses = await Future.wait<Map<String, dynamic>?>([
        completer.future,
        _postLegacy(postUrl, payload).then((_) => null),
      ], eagerError: true).timeout(_requestTimeout);
      return responses.first!;
    } on TimeoutException {
      throw McpException('Timeout waiting for a legacy SSE response');
    } finally {
      _pendingRequests.remove(key);
    }
  }

  Future<Response<dynamic>> _postLegacy(
    String url,
    Map<String, dynamic> payload,
  ) => _dio.post(
    url,
    data: payload,
    options: Options(
      headers: {'Content-Type': 'application/json', ...?headers},
      sendTimeout: _connectTimeout,
      receiveTimeout: _requestTimeout,
    ),
  );

  Map<String, String> get _httpHeaders => {
    ...?headers,
    'Content-Type': 'application/json',
    'Accept': 'application/json, text/event-stream',
    'Mcp-Session-Id': ?_sessionId,
    'MCP-Protocol-Version': ?_protocolVersion,
  };

  Future<Map<String, dynamic>?> _postHttp(Map<String, dynamic> payload) async {
    final cancelToken = CancelToken();
    final sessionId = _sessionId;
    try {
      return await _readHttpResponse(
        payload,
        cancelToken,
      ).timeout(_requestTimeout);
    } on TimeoutException {
      throw McpException('Timeout waiting for an MCP HTTP response');
    } on DioException catch (error) {
      if (error.response?.statusCode == 404 &&
          sessionId != null &&
          _sessionId == sessionId) {
        // The next request will initialize a new session without this ID.
        _initialized = false;
        _sessionId = null;
        _protocolVersion = null;
      }
      rethrow;
    } finally {
      // Dio's response stream may remain open after the matching SSE event.
      cancelToken.cancel();
    }
  }

  Future<Map<String, dynamic>?> _readHttpResponse(
    Map<String, dynamic> payload,
    CancelToken cancelToken,
  ) async {
    final response = await _dio.post<ResponseBody>(
      serverUrl,
      data: payload,
      options: Options(
        headers: _httpHeaders,
        responseType: ResponseType.stream,
        receiveDataWhenStatusError: false,
      ),
      cancelToken: cancelToken,
    );
    final stream = response.data!.stream;
    final id = payload['id'];
    if (id == null) {
      await stream.listen(null).cancel();
      return null;
    }

    final Map<String, dynamic> message;
    if (_isEventStream(response.headers)) {
      Map<String, dynamic>? result;
      await for (final event in _sseEvents(stream)) {
        if (event.event != 'message' || event.data.isEmpty) continue;
        final data = jsonDecode(event.data);
        if (data is Map<String, dynamic> &&
            data['id'] == id &&
            (data.containsKey('result') || data.containsKey('error'))) {
          result = data;
          break;
        }
      }
      if (result == null) {
        throw McpException('MCP event stream closed before the response');
      }
      message = result;
    } else {
      final data = jsonDecode(await utf8.decoder.bind(stream).join());
      if (data is! Map<String, dynamic>) {
        throw McpException('Invalid JSON-RPC response payload format');
      }
      message = data;
    }
    if (payload['method'] == 'initialize') {
      _sessionId = response.headers.value('Mcp-Session-Id');
    }
    return message;
  }

  Future<McpCapabilities> initialize() async {
    if (_initialized && _capabilities != null) {
      return _capabilities!;
    }

    // If initialization is already in progress, wait for it.
    if (_initializationFuture != null) {
      return _initializationFuture!;
    }

    _initializationFuture = _doInitialize();
    try {
      return await _initializationFuture!;
    } finally {
      _initializationFuture = null;
    }
  }

  Future<McpCapabilities> _doInitialize() async {
    try {
      await _closeSse();
      _sessionId = null;
      _protocolVersion = null;

      Map<String, dynamic> response;
      try {
        response = await _requestInitialization('2025-06-18');
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        if (status != 400 && status != 404 && status != 405) rethrow;
        Log.debug(
          'MCP HTTP initialization returned $status. Trying legacy SSE.',
        );
        await _connectSse();
        response = await _requestInitialization('2024-11-05');
      }

      final result = response['result'] as Map<String, dynamic>;
      _protocolVersion = result['protocolVersion'] as String?;
      final capabilities = McpCapabilities.fromJson(
        result['capabilities'] as Map<String, dynamic>,
      );
      await _sendInitializedNotification();
      _capabilities = capabilities;
      _initialized = true;

      return capabilities;
    } catch (e) {
      throw McpException('Failed to initialize MCP client: $e');
    }
  }

  Future<Map<String, dynamic>> _requestInitialization(String protocolVersion) =>
      _sendJsonRpc('initialize', {
        'protocolVersion': protocolVersion,
        'capabilities': {},
        'clientInfo': {'name': 'localmind', 'version': _version},
      });

  Future<void> _sendInitializedNotification() async {
    final payload = {
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
      'params': {},
    };
    final postUrl = _postUrl;
    try {
      if (postUrl == null) {
        await _postHttp(payload);
      } else {
        await _postLegacy(postUrl, payload);
      }
    } on DioException catch (error) {
      // Some older servers reject notifications. A missing HTTP session
      // means initialization itself failed and needs to be retried.
      if (postUrl == null && error.response?.statusCode == 404) rethrow;
    }
  }

  Future<List<McpTool>> listTools() async {
    if (!_initialized) {
      await initialize();
    }

    try {
      final response = await _sendJsonRpc('tools/list', {});

      final tools = response['result']['tools'] as List?;
      if (tools == null) return [];

      return tools
          .map((t) => McpTool.fromJson(t as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw McpException('Failed to list tools: $e');
    }
  }

  Future<String> callTool(String name, Map<String, dynamic> arguments) async {
    if (!_initialized) {
      await initialize();
    }

    try {
      final response = await _sendJsonRpc('tools/call', {
        'name': name,
        'arguments': arguments,
      });

      final result = response['result'];
      if (result == null) {
        throw McpException('Tool call returned no result');
      }

      final content = result['content'] as List?;
      if (content == null || content.isEmpty) {
        return '';
      }

      return content.first['text'] as String? ?? '';
    } catch (e) {
      if (e is McpException) rethrow;
      throw McpException('Failed to call tool $name: $e');
    }
  }

  Future<List<McpResource>> listResources() async {
    if (!_initialized) {
      await initialize();
    }

    try {
      final response = await _sendJsonRpc('resources/list', {});

      final resources = response['result']['resources'] as List?;
      if (resources == null) return [];

      return resources
          .map((r) => McpResource.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw McpException('Failed to list resources: $e');
    }
  }

  Future<String> readResource(String uri) async {
    if (!_initialized) {
      await initialize();
    }

    try {
      final response = await _sendJsonRpc('resources/read', {'uri': uri});

      final contents = response['result']['contents'] as List?;
      if (contents == null || contents.isEmpty) {
        return '';
      }

      return contents.first['text'] as String? ?? '';
    } catch (e) {
      throw McpException('Failed to read resource $uri: $e');
    }
  }

  Future<void> close() async {
    await _closeSse();
    _handleSseDisconnect(null);
    final sessionHeaders = _sessionId == null ? null : _httpHeaders;
    _sessionId = null;
    _protocolVersion = null;
    _capabilities = null;
    if (sessionHeaders == null) return;

    final cancelToken = CancelToken();
    try {
      await _dio
          .delete<void>(
            serverUrl,
            options: Options(headers: sessionHeaders),
            cancelToken: cancelToken,
          )
          .timeout(const Duration(seconds: 2));
    } on TimeoutException {
      cancelToken.cancel();
    } on DioException {
      // The server may decline client-initiated session termination.
    }
  }
}

bool _isEventStream(Headers headers) =>
    headers.value(Headers.contentTypeHeader)?.split(';').first.trim() ==
    'text/event-stream';

Stream<({String event, String data})> _sseEvents(Stream<List<int>> stream) {
  var event = 'message';
  final data = <String>[];
  final lines = utf8.decoder.bind(stream).transform(const LineSplitter());
  return lines.transform(
    StreamTransformer<String, ({String event, String data})>.fromHandlers(
      handleData: (line, sink) {
        if (line.isEmpty) {
          if (data.isNotEmpty) sink.add((event: event, data: data.join('\n')));
          event = 'message';
          data.clear();
        } else if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          final value = line.substring(5);
          data.add(value.startsWith(' ') ? value.substring(1) : value);
        }
      },
      handleDone: (sink) {
        if (data.isNotEmpty) sink.add((event: event, data: data.join('\n')));
        sink.close();
      },
    ),
  );
}

class McpCapabilities {
  final bool tools;
  final bool resources;
  final bool prompts;

  const McpCapabilities({
    this.tools = false,
    this.resources = false,
    this.prompts = false,
  });

  factory McpCapabilities.fromJson(Map<String, dynamic> json) {
    return McpCapabilities(
      tools: json['tools'] is Map || json['tools'] == true,
      resources: json['resources'] is Map || json['resources'] == true,
      prompts: json['prompts'] is Map || json['prompts'] == true,
    );
  }
}

class McpTool {
  final String name;
  final String? description;
  final Map<String, dynamic> inputSchema;

  const McpTool({
    required this.name,
    this.description,
    this.inputSchema = const {},
  });

  factory McpTool.fromJson(Map<String, dynamic> json) {
    return McpTool(
      name: json['name'] as String,
      description: json['description'] as String?,
      inputSchema: json['inputSchema'] as Map<String, dynamic>? ?? {},
    );
  }
}

class McpResource {
  final String uri;
  final String? name;
  final String? description;
  final String? mimeType;

  McpResource({required this.uri, this.name, this.description, this.mimeType});

  factory McpResource.fromJson(Map<String, dynamic> json) {
    return McpResource(
      uri: json['uri'] as String,
      name: json['name'] as String?,
      description: json['description'] as String?,
      mimeType: json['mimeType'] as String?,
    );
  }
}

class McpException implements Exception {
  final String message;
  McpException(this.message);

  @override
  String toString() => 'McpException: $message';
}
