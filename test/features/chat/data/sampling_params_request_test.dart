import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/data/chat_service.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/servers/data/models/server.dart';

/// Captures the request body and answers with an empty stream.
class _CapturingInterceptor extends Interceptor {
  _CapturingInterceptor(this.lines);

  final List<String> lines;
  Map<String, dynamic>? body;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final data = options.data;
    body = data is String
        ? jsonDecode(data) as Map<String, dynamic>
        : Map<String, dynamic>.from(data as Map);
    final controller = StreamController<Uint8List>();
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: ResponseBody(controller.stream, 200),
      ),
    );
    Future.microtask(() async {
      for (final line in lines) {
        controller.add(Uint8List.fromList(utf8.encode('$line\n')));
      }
      await controller.close();
    });
  }
}

Server _server(ServerType type) => Server(
  id: 'test-${type.name}',
  name: 'Test',
  type: type,
  host: 'localhost',
  port: 8080,
  createdAt: DateTime.utc(2026, 9, 28),
  lastConnectedAt: DateTime.utc(2026, 9, 28),
);

final _messages = [
  Message(
    id: 'm1',
    conversationId: 'c1',
    role: MessageRole.user,
    content: 'hi',
    createdAt: DateTime.utc(2026, 9, 28),
  ),
];

Future<Map<String, dynamic>> _captureBody(
  ChatService Function(Dio dio) build,
  ServerType type,
  ChatParameters params, {
  List<String> lines = const ['data: [DONE]'],
}) async {
  final interceptor = _CapturingInterceptor(lines);
  final service = build(Dio()..interceptors.add(interceptor));
  await service
      .sendMessage(
        server: _server(type),
        modelId: 'test-model',
        messages: _messages,
        params: params,
      )
      .toList();
  return interceptor.body!;
}

void main() {
  final omitBoth = ChatParameters.defaults().copyWith(
    sendTemperature: false,
    sendTopP: false,
  );

  test('OpenAI-compatible sends sampling params by default', () async {
    final body = await _captureBody(
      OpenAICompatibleChatService.new,
      ServerType.openAICompatible,
      ChatParameters.defaults(),
    );
    expect(body, containsPair('temperature', isA<num>()));
    expect(body, containsPair('top_p', isA<num>()));
  });

  test('OpenAI-compatible omits disabled sampling params (#81)', () async {
    final body = await _captureBody(
      OpenAICompatibleChatService.new,
      ServerType.openAICompatible,
      omitBoth,
    );
    expect(body.containsKey('temperature'), isFalse);
    expect(body.containsKey('top_p'), isFalse);
  });

  test('OpenRouter omits disabled sampling params (#81)', () async {
    final body = await _captureBody(
      OpenRouterChatService.new,
      ServerType.openRouter,
      ChatParameters.defaults().copyWith(sendTopP: false),
    );
    expect(body.containsKey('temperature'), isTrue);
    expect(body.containsKey('top_p'), isFalse);
  });

  test('Ollama omits disabled sampling params from options (#81)', () async {
    final body = await _captureBody(
      OllamaChatService.new,
      ServerType.ollama,
      omitBoth,
      lines: [
        jsonEncode({
          'message': {'content': ''},
          'done': true,
        }),
      ],
    );
    final options = body['options'] as Map<String, dynamic>;
    expect(options.containsKey('temperature'), isFalse);
    expect(options.containsKey('top_p'), isFalse);
    expect(options.containsKey('num_predict'), isTrue);
  });
}
