import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/data/mcp_client.dart';

const _toolList = {
  'tools': [
    {
      'name': 'search',
      'inputSchema': {'type': 'object'},
    },
  ],
};
const _toolResult = {
  'content': [
    {'type': 'text', 'text': 'Search result: café'},
  ],
};

void main() {
  test(
    'uses a Streamable HTTP session for tool discovery and calls',
    () async {
      final methods = <String>[];
      final streamCancelled = Completer<void>();
      final events = StreamController<Uint8List>(
        onCancel: streamCancelled.complete,
      );
      final dio = Dio()
        ..httpClientAdapter = _Adapter((request) {
          expect(request.uri.path, '/mcp');
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(
            request.headers['Accept'],
            'application/json, text/event-stream',
          );

          if (request.method == 'DELETE') {
            expect(request.headers['Mcp-Session-Id'], 'test-session');
            methods.add('DELETE');
            return ResponseBody.fromString('', 204);
          }

          expect(request.method, 'POST');
          final payload = request.data as Map<String, dynamic>;
          final method = payload['method'] as String;
          final id = payload['id'];
          methods.add(method);
          if (method == 'initialize') {
            expect(request.headers['Mcp-Session-Id'], isNull);
            expect(payload['params']['protocolVersion'], '2025-06-18');
            return ResponseBody.fromString(
              _event(
                _result(id, {
                  'protocolVersion': '2025-03-26',
                  'capabilities': {'tools': {}},
                }),
              ),
              200,
              headers: {
                Headers.contentTypeHeader: ['text/event-stream; charset=utf-8'],
                'Mcp-Session-Id': ['test-session'],
              },
            );
          }

          expect(request.headers['Mcp-Session-Id'], 'test-session');
          expect(request.headers['MCP-Protocol-Version'], '2025-03-26');
          switch (method) {
            case 'notifications/initialized':
              expect(id, isNull);
              return ResponseBody.fromString('', 202);
            case 'tools/list':
              return _json(_result(id, _toolList));
            case 'tools/call':
              expect(payload['params'], {
                'name': 'search',
                'arguments': {'query': 'coffee'},
              });
              final bytes = utf8.encode(_event(_result(id, _toolResult)));
              final split = bytes.indexOf(0xc3) + 1;
              events.add(
                Uint8List.fromList(utf8.encode(': keepalive\r\n\r\n')),
              );
              events.add(
                Uint8List.fromList(utf8.encode(_event(_result(999, {})))),
              );
              events.add(Uint8List.fromList(bytes.sublist(0, split)));
              events.add(Uint8List.fromList(bytes.sublist(split)));
              return ResponseBody(events.stream, 200, headers: _eventHeaders);
            default:
              throw StateError('Unexpected method: $method');
          }
        });
      final client = McpClient(
        serverUrl: 'http://localhost:8020/mcp',
        headers: {'Authorization': 'Bearer test-token'},
        dio: dio,
      );
      addTearDown(() async {
        await client.close();
        unawaited(events.close());
        dio.close(force: true);
      });

      expect((await client.initialize()).tools, isTrue);
      expect((await client.listTools()).single.name, 'search');
      expect(
        await client.callTool('search', {'query': 'coffee'}),
        'Search result: café',
      );
      await streamCancelled.future;
      await client.close();
      expect(methods, [
        'initialize',
        'notifications/initialized',
        'tools/list',
        'tools/call',
        'DELETE',
      ]);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  test(
    'opens a new HTTP session after the server expires the old one',
    () async {
      var sessionCount = 0;
      final dio = Dio()
        ..httpClientAdapter = _Adapter((request) {
          if (request.method == 'DELETE') {
            return ResponseBody.fromString('', 204);
          }
          final payload = request.data as Map<String, dynamic>;
          final session = request.headers['Mcp-Session-Id'];
          switch (payload['method']) {
            case 'initialize':
              expect(session, isNull);
              return _json(
                _result(payload['id'], {
                  'protocolVersion': '2025-06-18',
                  'capabilities': {'tools': {}},
                }),
                session: 'session-${++sessionCount}',
              );
            case 'notifications/initialized':
              return ResponseBody.fromString('', 202);
            case 'tools/list':
              expect(session, 'session-$sessionCount');
              return sessionCount == 1
                  ? ResponseBody.fromString('', 404)
                  : _json(_result(payload['id'], _toolList));
            default:
              throw StateError('Unexpected request: $payload');
          }
        });
      final client = McpClient(
        serverUrl: 'http://localhost:8020/mcp',
        dio: dio,
      );
      addTearDown(() async {
        await client.close();
        dio.close(force: true);
      });

      await expectLater(client.listTools(), throwsA(isA<McpException>()));
      expect(client.isInitialized, isFalse);
      expect((await client.listTools()).single.name, 'search');
      expect(sessionCount, 2);
    },
  );

  test('falls back to the legacy SSE handshake and message endpoint', () async {
    final events = StreamController<Uint8List>();
    final methods = <String>[];
    final dio = Dio()
      ..httpClientAdapter = _Adapter((request) {
        if (request.uri.path == '/sse' && request.method == 'POST') {
          methods.add('POST /sse');
          return ResponseBody.fromString('', 405);
        }
        if (request.uri.path == '/sse' && request.method == 'GET') {
          methods.add('GET /sse');
          final endpoint =
              'event: endpoint\r\ndata: /messages?session=test\r\n\r\n';
          events.add(Uint8List.fromList(utf8.encode(endpoint)));
          return ResponseBody(events.stream, 200, headers: _eventHeaders);
        }

        expect(request.method, 'POST');
        expect(request.uri.path, '/messages');
        expect(request.uri.queryParameters, {'session': 'test'});
        final payload = request.data as Map<String, dynamic>;
        final method = payload['method'] as String;
        methods.add(method);
        if (method == 'initialize') {
          expect(payload['params']['protocolVersion'], '2024-11-05');
        }
        final result = switch (method) {
          'initialize' => {
            'protocolVersion': '2024-11-05',
            'capabilities': {'tools': {}},
          },
          'notifications/initialized' => null,
          'tools/list' => _toolList,
          'tools/call' => _toolResult,
          _ => throw StateError('Unexpected method: $method'),
        };
        if (result != null) {
          events.add(
            Uint8List.fromList(
              utf8.encode(_event(_result(payload['id'], result))),
            ),
          );
        }
        return ResponseBody.fromString('', 202);
      });
    final client = McpClient(serverUrl: 'http://localhost:8020/sse', dio: dio);
    addTearDown(() async {
      await client.close();
      unawaited(events.close());
      dio.close(force: true);
    });

    expect((await client.listTools()).single.name, 'search');
    expect(await client.callTool('search', {}), 'Search result: café');
    expect(methods, [
      'POST /sse',
      'GET /sse',
      'initialize',
      'notifications/initialized',
      'tools/list',
      'tools/call',
    ]);
  });
}

const _eventHeaders = {
  Headers.contentTypeHeader: ['text/event-stream'],
};

Map<String, Object?> _result(Object? id, Map<String, Object?> result) => {
  'jsonrpc': '2.0',
  'id': id,
  'result': result,
};

String _event(Map<String, Object?> body) =>
    'event: message\r\ndata: ${jsonEncode(body)}\r\n\r\n';

ResponseBody _json(Map<String, Object?> body, {String? session}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        if (session != null) 'Mcp-Session-Id': [session],
      },
    );

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final ResponseBody Function(RequestOptions) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}
