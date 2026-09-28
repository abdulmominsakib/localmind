import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/providers/chat_background_service_provider.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/services/chat_background_service.dart';
import 'package:localmind/features/chat/data/chat_service.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/data/tools/tool_definition.dart';
import 'package:localmind/features/chat/data/tools/tool_registry.dart';
import 'package:localmind/features/chat/providers/chat_mcp_providers.dart';
import 'package:localmind/features/chat/providers/chat_notifier.dart';
import 'package:localmind/features/chat/providers/chat_params_providers.dart';
import 'package:localmind/features/chat/providers/chat_service_providers.dart';
import 'package:localmind/features/chat/providers/model_selection_providers.dart';
import 'package:localmind/features/chat/providers/tooling_providers.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';
import 'package:localmind/features/voice_mode/providers/voice_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ControllableChatService chatService;
  late ProviderContainer container;
  late _BackgroundTestChatNotifier notifier;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    chatService = _ControllableChatService();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        activeServerProvider.overrideWith(_RemoteServerNotifier.new),
        activeChatTargetProvider.overrideWithValue(
          ActiveChatTarget(
            server: _server,
            selectedModel: null,
            effectiveModelId: 'model',
            modelLabel: 'Model',
          ),
        ),
        chatProvider.overrideWith(_BackgroundTestChatNotifier.new),
        chatServiceProvider.overrideWithValue(chatService),
        chatParamsProvider.overrideWithValue(ChatParameters.defaults()),
        chatMcpConfigProvider.overrideWith(_DisabledMcpNotifier.new),
        toolRegistryProvider.overrideWithValue(
          ToolRegistry(providers: const []),
        ),
        chatBackgroundServiceProvider.overrideWithValue(
          _TestChatBackgroundService(),
        ),
        settingsProvider.overrideWith(_TestSettingsNotifier.new),
        voiceModeProvider.overrideWith(_IdleVoiceModeNotifier.new),
        conv.conversationsProvider.overrideWith(_FakeConversationsNotifier.new),
      ],
    );
    await container.read(conv.conversationsProvider.future);
    notifier =
        container.read(chatProvider.notifier) as _BackgroundTestChatNotifier;
  });

  tearDown(() => container.dispose());

  Future<void> startReplyInA() async {
    await notifier.loadConversation(_conversationA);
    await notifier.continueFromMessage('a-assistant');
    await _pump();
    expect(chatService.controllers, hasLength(1));
    chatService.emit('Hello');
    await _pump();
  }

  test('switching chats keeps the reply generating (#94)', () async {
    await startReplyInA();

    await notifier.loadConversation(_conversationB);
    await _pump();

    expect(chatService.cancelCount, 0);
    expect(container.read(chatProvider).isStreaming, isFalse);
    expect(container.read(chatProvider).messages.first.id, 'b-user');
    expect(container.read(streamingConversationIdProvider), 'conversation-a');
    expect(container.read(isStreamingProvider), isTrue);

    chatService.emit(' world');
    await chatService.finish();
    await _pump();

    final saved = notifier.saved.lastWhere((m) => m.id == 'a-assistant');
    expect(saved.content, contains('world'));
    expect(saved.conversationId, 'conversation-a');
    expect(saved.status, MessageStatus.complete);
    // Chat B's view is untouched by the background completion.
    expect(container.read(chatProvider).messages.first.id, 'b-user');
    expect(container.read(streamingConversationIdProvider), isNull);
    expect(container.read(isStreamingProvider), isFalse);
  });

  test(
    'returning to the generating chat reattaches to the live reply',
    () async {
      await startReplyInA();
      await notifier.loadConversation(_conversationB);
      await notifier.loadConversation(_conversationA);
      await _pump();

      expect(chatService.cancelCount, 0);
      final state = container.read(chatProvider);
      expect(state.isStreaming, isTrue);
      expect(state.streamingMessage?.id, 'a-assistant');

      chatService.emit(' again');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(
        container.read(chatProvider).streamingMessage?.content,
        contains('again'),
      );

      await chatService.finish();
      await _pump();
      expect(container.read(chatProvider).isStreaming, isFalse);
    },
  );

  test('sending in another chat is blocked while a reply runs', () async {
    await startReplyInA();
    await notifier.loadConversation(_conversationB);

    await notifier.sendMessage('new question');

    expect(
      container.read(chatProvider).errorMessage,
      generatingElsewhereMessage,
    );
    expect(chatService.controllers, hasLength(1));
    expect(chatService.cancelCount, 0);
  });

  test('a second switch does not cancel the background reply', () async {
    await startReplyInA();
    await notifier.loadConversation(_conversationB);
    await notifier.startNewConversation();
    await _pump();

    expect(chatService.cancelCount, 0);
    expect(container.read(streamingConversationIdProvider), 'conversation-a');
  });

  test('cancelGenerationFor stops a background reply', () async {
    await startReplyInA();
    await notifier.loadConversation(_conversationB);

    await notifier.cancelGenerationFor('conversation-a');

    expect(chatService.cancelCount, 1);
    expect(container.read(streamingConversationIdProvider), isNull);
    expect(container.read(isStreamingProvider), isFalse);
  });
}

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final _server = Server(
  id: 'remote',
  name: 'Remote',
  type: ServerType.ollama,
  host: '127.0.0.1',
  port: 11434,
  createdAt: DateTime.utc(2026, 9, 28),
  lastConnectedAt: DateTime.utc(2026, 9, 28),
  status: ConnectionStatus.connected,
);

final _conversationA = Conversation(
  id: 'conversation-a',
  title: 'Chat A',
  createdAt: DateTime.utc(2026, 9, 28),
  updatedAt: DateTime.utc(2026, 9, 28),
);

final _conversationB = Conversation(
  id: 'conversation-b',
  title: 'Chat B',
  createdAt: DateTime.utc(2026, 9, 28),
  updatedAt: DateTime.utc(2026, 9, 28),
);

Message _message(
  String id,
  String conversationId,
  MessageRole role,
  String content, {
  String? parentId,
  int threadOrder = 0,
}) => Message(
  id: id,
  conversationId: conversationId,
  role: role,
  content: content,
  createdAt: DateTime.utc(2026, 9, 28),
  variantGroupId: id,
  threadOrder: threadOrder,
  isActiveVariant: true,
  parentMessageId: parentId,
);

final _messagesByConversation = {
  'conversation-a': [
    _message('a-user', 'conversation-a', MessageRole.user, 'Hi A'),
    _message(
      'a-assistant',
      'conversation-a',
      MessageRole.assistant,
      'Hey',
      parentId: 'a-user',
      threadOrder: 1,
    ),
  ],
  'conversation-b': [
    _message('b-user', 'conversation-b', MessageRole.user, 'Hi B'),
    _message(
      'b-assistant',
      'conversation-b',
      MessageRole.assistant,
      'Yo',
      parentId: 'b-user',
      threadOrder: 1,
    ),
  ],
};

class _BackgroundTestChatNotifier extends ChatNotifier {
  final List<Message> saved = [];

  @override
  ChatState build() => const ChatState();

  @override
  Future<List<Message>> loadConversationMessages(String conversationId) async {
    final base = _messagesByConversation[conversationId] ?? const [];
    // Later saves replace the seeded copy, like the database would.
    return base.map((message) {
      return saved.lastWhere((s) => s.id == message.id, orElse: () => message);
    }).toList();
  }

  @override
  Future<void> persistMessage(Message message) async {
    saved.add(message);
  }
}

class _ControllableChatService implements ChatService {
  final List<StreamController<ChatResponse>> controllers = [];
  int cancelCount = 0;

  void emit(String content) {
    controllers.last.add(
      ChatResponse(type: ChatResponseType.message, content: content),
    );
  }

  Future<void> finish() async {
    controllers.last.add(const ChatResponse(type: ChatResponseType.done));
    await controllers.last.close();
  }

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
    final controller = StreamController<ChatResponse>();
    controllers.add(controller);
    return controller.stream;
  }

  @override
  void cancelStream() {
    cancelCount++;
  }
}

class _FakeConversationsNotifier extends conv.ConversationsNotifier {
  @override
  Future<List<Conversation>> build() async => [_conversationA, _conversationB];

  @override
  Future<void> syncConversationStats(
    String id, {
    required int messageCount,
    required int characterCount,
    String? preview,
  }) async {}

  @override
  Future<void> updateTokenCount(String id, int totalTokenCount) async {}
}

class _RemoteServerNotifier extends ActiveServerNotifier {
  @override
  Server? build() => _server;
}

class _DisabledMcpNotifier extends ChatMcpConfigNotifier {
  @override
  ChatMcpConfig build() => const ChatMcpConfig(enabled: false);
}

class _TestChatBackgroundService extends ChatBackgroundService {
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

class _TestSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings(
    mcpEnabled: false,
    newChatMcpEnabled: false,
    resumeLastChat: false,
    autoGenerateTitle: false,
  );
}

class _IdleVoiceModeNotifier extends VoiceModeNotifier {
  @override
  VoiceModeState build() => const VoiceModeState();
}
