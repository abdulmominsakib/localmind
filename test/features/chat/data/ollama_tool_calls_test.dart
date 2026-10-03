import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/data/chat_service.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/data/models/message.dart' as msg;
import 'package:localmind/features/servers/data/models/server.dart';

/// Captures the request body and answers with the given NDJSON lines.
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

final _server = Server(
  id: 'test-ollama',
  name: 'Test',
  type: ServerType.ollama,
  host: 'localhost',
  port: 11434,
  createdAt: DateTime.utc(2026, 10, 2),
  lastConnectedAt: DateTime.utc(2026, 10, 2),
);

final _createdAt = DateTime.utc(2026, 10, 2);

Future<(List<ChatResponse>, Map<String, dynamic>)> _send(
  List<msg.Message> messages,
  List<String> lines,
) async {
  final interceptor = _CapturingInterceptor(lines);
  final responses =
      await OllamaChatService(Dio()..interceptors.add(interceptor))
          .sendMessage(
            server: _server,
            modelId: 'qwen3.5:4b',
            messages: messages,
            params: ChatParameters.defaults(),
          )
          .toList();
  return (responses, interceptor.body!);
}

void main() {
  // #107: Ollama streams tool calls with `arguments` as a JSON object. The
  // parsing error used to be swallowed, leaving an empty reply.
  test('streamed tool call with object arguments is surfaced', () async {
    final (responses, _) = await _send(
      [
        msg.Message(
          id: 'm1',
          conversationId: 'c1',
          role: MessageRole.user,
          content: 'What is 3847 x 729?',
          createdAt: _createdAt,
        ),
      ],
      [
        jsonEncode({
          'message': {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'id': 'call_1',
                'function': {
                  'index': 0,
                  'name': 'calc.multiply',
                  'arguments': {'a': 3847, 'b': 729},
                },
              },
            ],
          },
          'done': false,
        }),
        jsonEncode({
          'message': {'role': 'assistant', 'content': ''},
          'done': true,
          'done_reason': 'stop',
        }),
      ],
    );

    final toolCall = responses
        .singleWhere((r) => r.type == ChatResponseType.toolCall)
        .toolCall!;
    expect(toolCall.tool, 'calc.multiply');
    expect(toolCall.arguments, {'a': 3847, 'b': 729});
    expect(responses.last.type, ChatResponseType.done);
  });

  // Ollama rejects a JSON-encoded string here with HTTP 400, which broke the
  // follow-up request that carries the tool result back to the model.
  test('replayed assistant tool calls send arguments as an object', () async {
    final (_, body) = await _send(
      [
        msg.Message(
          id: 'm1',
          conversationId: 'c1',
          role: MessageRole.user,
          content: 'What is 3847 x 729?',
          createdAt: _createdAt,
        ),
        msg.Message(
          id: 'm2',
          conversationId: 'c1',
          role: MessageRole.assistant,
          content: '',
          createdAt: _createdAt,
          toolCalls: [
            msg.ToolCallData(
              id: 'call_1',
              toolName: 'calc.multiply',
              arguments: const {'a': 3847, 'b': 729},
              result: '2804463',
            ),
          ],
        ),
        msg.Message(
          id: 'm3',
          conversationId: 'c1',
          role: MessageRole.tool,
          content: '2804463',
          createdAt: _createdAt,
          toolCallId: 'call_1',
        ),
      ],
      [
        jsonEncode({
          'message': {'content': ''},
          'done': true,
        }),
      ],
    );

    final messages = (body['messages'] as List).cast<Map<String, dynamic>>();
    final replayed = (messages[1]['tool_calls'] as List).single as Map;
    final function = replayed['function'] as Map;
    expect(function['name'], 'calc.multiply');
    expect(function['arguments'], isA<Map>());
    expect(function['arguments'], {'a': 3847, 'b': 729});
    expect(messages[2]['role'], 'tool');
  });
}
