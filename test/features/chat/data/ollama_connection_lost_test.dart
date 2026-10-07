import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/data/chat_service.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/data/models/message.dart' as msg;
import 'package:localmind/features/servers/data/models/server.dart';

/// Streams one reasoning chunk, then fails the body the way dart:io does
/// when the socket closes mid-reply.
class _DroppingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final controller = StreamController<Uint8List>();
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: ResponseBody(controller.stream, 200),
      ),
    );
    Future.microtask(() async {
      final chunk = jsonEncode({
        'message': {'content': '', 'thinking': 'Let me think'},
        'done': false,
      });
      controller.add(Uint8List.fromList(utf8.encode('$chunk\n')));
      controller.addError(
        const HttpException(
          'Connection closed while receiving data',
          uri: null,
        ),
      );
      await controller.close();
    });
  }
}

void main() {
  test('a connection dropped mid-reply yields a readable error', () async {
    final server = Server(
      id: 'test-ollama',
      name: 'Test',
      type: ServerType.ollama,
      host: 'localhost',
      port: 11434,
      createdAt: DateTime.utc(2026, 10, 6),
      lastConnectedAt: DateTime.utc(2026, 10, 6),
    );

    final responses =
        await OllamaChatService(Dio()..interceptors.add(_DroppingInterceptor()))
            .sendMessage(
              server: server,
              modelId: 'qwen3.5:4b',
              messages: [
                msg.Message(
                  id: 'm1',
                  conversationId: 'c1',
                  role: MessageRole.user,
                  content: 'Hi',
                  createdAt: DateTime.utc(2026, 10, 6),
                ),
              ],
              params: ChatParameters.defaults(),
            )
            .toList();

    expect(responses.first.type, ChatResponseType.reasoning);
    final error = responses.last;
    expect(error.type, ChatResponseType.error);
    final decoded = jsonDecode(error.content!) as Map<String, dynamic>;
    expect(decoded['type'], 'connection_lost');
    expect(decoded['message'], isNot(contains('HttpException')));
  });
}
