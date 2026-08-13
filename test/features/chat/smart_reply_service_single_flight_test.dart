import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/data/chat_service.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/data/models/mcp_integration.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/data/smart_reply_service.dart';
import 'package:localmind/features/chat/data/tools/tool_definition.dart';
import 'package:localmind/features/servers/data/models/server.dart';

void main() {
  test('does not treat hi inside Chicago as a greeting', () {
    final replies = SmartReplyService().getFallbackReplies(
      'The conference in Chicago is next month.',
    );

    expect(replies, isNot(contains('Hello! How are you?')));
  });

  test('still recognizes hi as a standalone greeting', () {
    final replies = SmartReplyService().getFallbackReplies('Hi there!');

    expect(replies, contains('Hello! How are you?'));
  });

  test(
    'shares an in-flight suggestion request for the same assistant message',
    () async {
      final chatService = _ControlledChatService();
      final service = SmartReplyService();
      final messages = [
        Message(
          id: 'assistant-1',
          conversationId: 'conversation-1',
          role: MessageRole.assistant,
          content: 'How can I help?',
          createdAt: DateTime.utc(2026, 8, 9),
        ),
      ];

      final first = service.suggestRepliesWithLLM(
        chatService: chatService,
        server: _server(),
        modelId: 'qwen3-0.6b',
        messages: messages,
        params: ChatParameters.defaults(),
      );
      final second = service.suggestRepliesWithLLM(
        chatService: chatService,
        server: _server(),
        modelId: 'qwen3-0.6b',
        messages: messages,
        params: ChatParameters.defaults(),
      );

      expect(chatService.sendCount, 1);
      chatService.controller.add(
        const ChatResponse(
          type: ChatResponseType.message,
          content: '["Yes", "No", "Tell me more"]',
        ),
      );
      chatService.controller.add(
        const ChatResponse(type: ChatResponseType.done),
      );

      final results = await Future.wait([first, second]);
      expect(results[0], ['Yes', 'No', 'Tell me more']);
      expect(results[1], results[0]);
      expect(chatService.sendCount, 1);
    },
  );
}

class _ControlledChatService implements ChatService {
  final StreamController<ChatResponse> controller = StreamController();
  int sendCount = 0;

  @override
  Stream<ChatResponse> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
    List<McpIntegration>? integrations,
    List<ToolDefinition>? tools,
    bool continueGeneration = false,
  }) {
    sendCount++;
    return controller.stream;
  }

  @override
  void cancelStream() {}
}

Server _server() => Server(
  id: 'on-device',
  name: 'On-Device',
  type: ServerType.onDevice,
  host: '',
  port: 0,
  createdAt: DateTime.utc(2026, 8, 9),
  lastConnectedAt: DateTime.utc(2026, 8, 9),
  status: ConnectionStatus.connected,
);
