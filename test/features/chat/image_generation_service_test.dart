import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/data/image_generation_service.dart';
import 'package:localmind/features/servers/data/models/server.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC';

Server _server(ServerType type) => Server(
  id: 'image-server',
  name: 'Image server',
  type: type,
  host: 'https://example.com',
  port: 443,
  pathPrefix: '/proxy/v1',
  apiKey: 'test-key',
  createdAt: DateTime.utc(2026),
  lastConnectedAt: DateTime.utc(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (type, expectedUrl) in [
    (ServerType.openRouter, 'https://openrouter.ai/api/v1/images'),
    (
      ServerType.openAICompatible,
      'https://example.com/proxy/v1/images/generations',
    ),
  ]) {
    test('generates a base64 image with $type', () async {
      final adapter = _Adapter((request) {
        expect(request.method, 'POST');
        expect(request.uri.toString(), expectedUrl);
        expect(request.headers['Authorization'], 'Bearer test-key');
        expect(request.data, {
          'model': 'provider/image',
          'prompt': 'Draw a kite',
          'n': 1,
        });
        return _json({
          'data': [
            {'b64_json': _png, 'media_type': 'image/png'},
          ],
        });
      });
      final service = ImageGenerationService(
        Dio()..httpClientAdapter = adapter,
      );
      final result = await service.generate(
        endpoint: Uri.parse(_server(type).imageGenerationEndpoint!),
        authHeaders: _server(type).authHeaders,
        allowsUrlResults: type == ServerType.openAICompatible,
        modelId: 'provider/image',
        prompt: 'Draw a kite',
        cancelToken: CancelToken(),
      );
      expect(result.extension, 'png');
      expect(result.bytes, base64Decode(_png));
    });
  }

  test(
    'downloads compatible URL results without forwarding credentials',
    () async {
      final adapter = _Adapter((request) {
        if (request.method == 'POST') {
          return _json({
            'data': [
              {'url': 'https://cdn.example.com/image.png?token=fixture'},
            ],
          });
        }
        expect(request.uri.host, 'cdn.example.com');
        expect(
          request.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('authorization')),
        );
        expect(request.followRedirects, isFalse);
        return ResponseBody.fromBytes(base64Decode(_png), 200);
      });
      final service = ImageGenerationService(
        Dio()..httpClientAdapter = adapter,
      );
      final result = await service.generate(
        endpoint: Uri.parse(
          _server(ServerType.openAICompatible).imageGenerationEndpoint!,
        ),
        authHeaders: _server(ServerType.openAICompatible).authHeaders,
        allowsUrlResults: true,
        modelId: 'provider/image',
        prompt: 'Draw a kite',
        cancelToken: CancelToken(),
      );
      expect(result.bytes, base64Decode(_png));
      expect(adapter.requestCount, 2);
    },
  );

  for (final response in [
    {'data': []},
    {
      'data': [
        {'b64_json': '%%%'},
      ],
    },
    {
      'data': [
        {'b64_json': base64Encode(utf8.encode('<svg></svg>'))},
      ],
    },
    {
      'data': [
        {'url': 'ftp://example.com/image.png'},
      ],
    },
  ]) {
    test('rejects invalid image payload $response', () async {
      final adapter = _Adapter((_) => _json(response));
      final service = ImageGenerationService(
        Dio()..httpClientAdapter = adapter,
      );
      await expectLater(
        service.generate(
          endpoint: Uri.parse(
            _server(ServerType.openAICompatible).imageGenerationEndpoint!,
          ),
          authHeaders: _server(ServerType.openAICompatible).authHeaders,
          allowsUrlResults: true,
          modelId: 'provider/image',
          prompt: 'Draw a kite',
          cancelToken: CancelToken(),
        ),
        throwsA(ImageGenerationFailure.invalid),
      );
    });
  }

  for (final (status, failure) in [
    (401, ImageGenerationFailure.auth),
    (429, ImageGenerationFailure.quota),
    (404, ImageGenerationFailure.unavailable),
    (422, ImageGenerationFailure.rejected),
  ]) {
    test('maps provider status $status to $failure', () async {
      final service = ImageGenerationService(
        Dio()
          ..httpClientAdapter = _Adapter(
            (_) => ResponseBody.fromString('{}', status),
          ),
      );
      await expectLater(
        service.generate(
          endpoint: Uri.parse(
            _server(ServerType.openRouter).imageGenerationEndpoint!,
          ),
          authHeaders: _server(ServerType.openRouter).authHeaders,
          allowsUrlResults: false,
          modelId: 'provider/image',
          prompt: 'Draw a kite',
          cancelToken: CancelToken(),
        ),
        throwsA(failure),
      );
    });
  }

  test('the request deadline cancels a stalled provider', () async {
    final never = Completer<ResponseBody>();
    final service = ImageGenerationService(
      Dio()..httpClientAdapter = _Adapter((_) => never.future),
      timeout: const Duration(milliseconds: 30),
    );
    final token = CancelToken();
    await expectLater(
      service.generate(
        endpoint: Uri.parse(
          _server(ServerType.openRouter).imageGenerationEndpoint!,
        ),
        authHeaders: _server(ServerType.openRouter).authHeaders,
        allowsUrlResults: false,
        modelId: 'provider/image',
        prompt: 'Draw a kite',
        cancelToken: token,
      ),
      throwsA(ImageGenerationFailure.timeout),
    );
    expect(token.isCancelled, isTrue);
  });
}

ResponseBody _json(Map<String, Object?> body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}
