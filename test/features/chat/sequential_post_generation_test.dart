import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/features/chat/data/chat_service.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/data/models/mcp_integration.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/data/tools/tool_definition.dart';
import 'package:localmind/features/chat/providers/chat_notifier.dart';
import 'package:localmind/features/chat/providers/chat_service_providers.dart';
import 'package:localmind/features/chat/providers/model_selection_providers.dart';
import 'package:localmind/features/chat/providers/smart_reply_providers.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';
import 'package:localmind/features/voice_mode/providers/voice_mode_provider.dart';

void main() {
  test(
    'smartRepliesProvider waits for title generation on the conversation to complete before generating replies',
    () async {
      final titleCompleter = Completer<void>();
      final executionOrder = <String>[];

      final testChatNotifier = _MockChatNotifier(
        initialState: ChatState(
          isStreaming: false,
          messages: [
            Message(
              id: 'user-1',
              conversationId: 'conv-1',
              role: MessageRole.user,
              content: 'Tell me about stars',
              createdAt: DateTime.utc(2026, 8, 15),
            ),
            Message(
              id: 'assistant-1',
              conversationId: 'conv-1',
              role: MessageRole.assistant,
              content: 'Stars are massive celestial bodies made of plasma.',
              status: MessageStatus.complete,
              createdAt: DateTime.utc(2026, 8, 15),
            ),
          ],
        ),
        onWaitForTitle: (convId) async {
          executionOrder.add('waitForTitle:start');
          await titleCompleter.future;
          executionOrder.add('waitForTitle:done');
        },
      );

      final fakeChatService = _SequentialTrackingChatService(
        onSend: (prompt) {
          executionOrder.add('llm:smartReply');
        },
      );

      final conversation = Conversation(
        id: 'conv-1',
        title: 'New Chat',
        serverId: 'server-1',
        createdAt: DateTime.utc(2026, 8, 15),
        updatedAt: DateTime.utc(2026, 8, 15),
      );

      final container = ProviderContainer(
        overrides: [
          conversationsProvider.overrideWith(_TestConversationsNotifier.new),
          activeConversationProvider.overrideWith(
            () => _TestActiveConversationNotifier(conversation),
          ),
          activeConversationIdProvider.overrideWith(
            () => _TestActiveConversationIdNotifier('conv-1'),
          ),
          chatProvider.overrideWith(() => testChatNotifier),
          chatServiceProvider.overrideWithValue(fakeChatService),
          activeServerProvider.overrideWith(_TestServerNotifier.new),
          selectedModelProvider.overrideWith(_TestModelNotifier.new),
          voiceModeProvider.overrideWith(_TestVoiceModeNotifier.new),
          settingsProvider.overrideWith(_TestSettingsNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      // Read smartRepliesProvider
      final repliesFuture = container.read(smartRepliesProvider.future);

      // Allow microtasks to execute
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // waitForTitle should have been called, but LLM smart reply should NOT have run yet
      expect(executionOrder, contains('waitForTitle:start'));
      expect(executionOrder, isNot(contains('llm:smartReply')));

      // Now complete the title generation
      titleCompleter.complete();

      final replies = await repliesFuture;
      expect(executionOrder, [
        'waitForTitle:start',
        'waitForTitle:done',
        'llm:smartReply',
      ]);
      expect(replies, ['Tell me more', 'How do they form?']);
    },
  );

  test(
    'smartRepliesProvider does not delay if no title generation is pending',
    () async {
      final executionOrder = <String>[];

      final testChatNotifier = _MockChatNotifier(
        initialState: ChatState(
          isStreaming: false,
          messages: [
            Message(
              id: 'user-2',
              conversationId: 'conv-1',
              role: MessageRole.user,
              content: 'How big are they?',
              createdAt: DateTime.utc(2026, 8, 15),
            ),
            Message(
              id: 'assistant-2',
              conversationId: 'conv-1',
              role: MessageRole.assistant,
              content: 'They range from small dwarfs to giant supergiants.',
              status: MessageStatus.complete,
              createdAt: DateTime.utc(2026, 8, 15),
            ),
          ],
        ),
        onWaitForTitle: (convId) async {
          executionOrder.add('waitForTitle:instant');
        },
      );

      final fakeChatService = _SequentialTrackingChatService(
        onSend: (prompt) {
          executionOrder.add('llm:smartReply');
        },
      );

      final conversation = Conversation(
        id: 'conv-1',
        title: 'Stars and Galaxies',
        serverId: 'server-1',
        createdAt: DateTime.utc(2026, 8, 15),
        updatedAt: DateTime.utc(2026, 8, 15),
      );

      final container = ProviderContainer(
        overrides: [
          conversationsProvider.overrideWith(_TestConversationsNotifier.new),
          activeConversationProvider.overrideWith(
            () => _TestActiveConversationNotifier(conversation),
          ),
          activeConversationIdProvider.overrideWith(
            () => _TestActiveConversationIdNotifier('conv-1'),
          ),
          chatProvider.overrideWith(() => testChatNotifier),
          chatServiceProvider.overrideWithValue(fakeChatService),
          activeServerProvider.overrideWith(_TestServerNotifier.new),
          selectedModelProvider.overrideWith(_TestModelNotifier.new),
          voiceModeProvider.overrideWith(_TestVoiceModeNotifier.new),
          settingsProvider.overrideWith(_TestSettingsNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      final replies = await container.read(smartRepliesProvider.future);
      expect(executionOrder, ['waitForTitle:instant', 'llm:smartReply']);
      expect(replies, ['Tell me more', 'How do they form?']);
    },
  );
}

class _MockChatNotifier extends ChatNotifier {
  _MockChatNotifier({this.initialState = const ChatState(), this.onWaitForTitle});

  final ChatState initialState;
  final Future<void> Function(String convId)? onWaitForTitle;

  @override
  ChatState build() => initialState;

  @override
  Future<void> waitForTitleGeneration(String conversationId) async {
    if (onWaitForTitle != null) {
      await onWaitForTitle!(conversationId);
    }
  }
}

class _SequentialTrackingChatService implements ChatService {
  _SequentialTrackingChatService({required this.onSend});

  final void Function(String prompt) onSend;

  @override
  Stream<ChatResponse> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
    List<McpIntegration>? integrations,
    List<ToolDefinition>? tools,
    bool continueGeneration = false,
  }) async* {
    onSend(messages.last.content);
    yield const ChatResponse(
      type: ChatResponseType.message,
      content: '["Tell me more", "How do they form?"]',
    );
    yield const ChatResponse(type: ChatResponseType.done);
  }

  @override
  void cancelStream() {}
}

class _TestVoiceModeNotifier extends VoiceModeNotifier {
  @override
  VoiceModeState build() => const VoiceModeState();
}

class _TestConversationsNotifier extends ConversationsNotifier {
  @override
  Future<List<Conversation>> build() async => [];

  @override
  Future<void> updateSmartReplies(
    String id,
    List<String> replies,
    String lastMessageId,
  ) async {}
}

class _TestActiveConversationNotifier extends ActiveConversationNotifier {
  _TestActiveConversationNotifier(this._initial);
  final Conversation? _initial;

  @override
  Conversation? build() => _initial;
}

class _TestActiveConversationIdNotifier extends ActiveConversationIdNotifier {
  _TestActiveConversationIdNotifier(this._initial);
  final String? _initial;

  @override
  String? build() => _initial;
}

class _TestServerNotifier extends ActiveServerNotifier {
  @override
  Server? build() => Server(
    id: 'server-1',
    name: 'On-Device',
    type: ServerType.onDevice,
    host: '',
    port: 0,
    createdAt: DateTime.utc(2026, 8, 15),
    lastConnectedAt: DateTime.utc(2026, 8, 15),
    status: ConnectionStatus.connected,
  );
}

class _TestModelNotifier extends SelectedModelNotifier {
  @override
  ModelInfo? build() => ModelInfo(
    id: 'smollm2-135m-instruct',
    name: 'SmolLM2 135M',
    serverType: ServerType.onDevice,
    serverId: 'server-1',
  );
}

class _TestSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings(
    smartReplyEnabled: true,
    smartRepliesUsePersona: false,
    autoGenerateTitle: true,
  );
}
