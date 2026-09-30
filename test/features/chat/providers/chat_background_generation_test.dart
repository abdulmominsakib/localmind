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
  late _TestChatBackgroundService bgService;
  late ProviderContainer container;
  late _BackgroundTestChatNotifier notifier;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    chatService = _ControllableChatService();
    bgService = _TestChatBackgroundService();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        activeServerProvider.overrideWith(_RemoteServerNotifier.new),
        activeChatTargetProvider.overrideWithValue(
          ActiveChatTarget(
            server: _remoteServer,
            selectedModel: null,
            effectiveModelId: 'model',
            modelLabel: 'Model',
          ),
        ),
        chatProvider.overrideWith(_BackgroundTestChatNotifier.new),
        chatServiceProvider.overrideWithValue(chatService),
        chatServiceFactoryProvider.overrideWithValue((_) => chatService),
        chatParamsProvider.overrideWithValue(ChatParameters.defaults()),
        chatMcpConfigProvider.overrideWith(_DisabledMcpNotifier.new),
        toolRegistryProvider.overrideWithValue(
          ToolRegistry(providers: const []),
        ),
        chatBackgroundServiceProvider.overrideWithValue(bgService),
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
    // The generation for conversation-a should still be tracked.
    final generations = container.read(activeGenerationsProvider);
    expect(generations, contains('conversation-a'));
    // isStreamingProvider is about the *open* chat (B), which is not streaming.
    expect(container.read(isStreamingProvider), isFalse);

    chatService.emit(' world');
    await chatService.finish();
    await _pump();

    final saved = notifier.saved.lastWhere((m) => m.id == 'a-assistant');
    expect(saved.content, contains('world'));
    expect(saved.conversationId, 'conversation-a');
    expect(saved.status, MessageStatus.complete);
    // Chat B's view is untouched by the background completion.
    expect(container.read(chatProvider).messages.first.id, 'b-user');
    expect(container.read(activeGenerationsProvider), isEmpty);
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

  test('remote: sending in another chat is allowed (not blocked)', () async {
    await startReplyInA();
    await notifier.loadConversation(_conversationB);

    // With a remote server, sending in chat B should NOT be blocked.
    await notifier.sendMessage('new question');

    // Should not set the on-device busy error.
    expect(
      container.read(chatProvider).errorMessage,
      isNot(onDeviceBusyMessage),
    );
    // Both streams run concurrently.
    expect(chatService.controllers, hasLength(2));
  });

  test('a second switch does not cancel the background reply', () async {
    await startReplyInA();
    await notifier.loadConversation(_conversationB);
    await notifier.startNewConversation();
    await _pump();

    expect(chatService.cancelCount, 0);
    final generations = container.read(activeGenerationsProvider);
    expect(generations, contains('conversation-a'));
  });

  test('cancelGenerationFor stops a background reply', () async {
    await startReplyInA();
    await notifier.loadConversation(_conversationB);

    await notifier.cancelGenerationFor('conversation-a');

    expect(chatService.cancelCount, 1);
    expect(container.read(activeGenerationsProvider), isEmpty);
    expect(container.read(isStreamingProvider), isFalse);
  });

  test('stopping one reply cancels only that service, not the other', () async {
    // Create two controllable services for two concurrent streams.
    final serviceA = _ControllableChatService();
    final serviceB = _ControllableChatService();
    var factoryCallCount = 0;
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        activeServerProvider.overrideWith(_RemoteServerNotifier.new),
        activeChatTargetProvider.overrideWithValue(
          ActiveChatTarget(
            server: _remoteServer,
            selectedModel: null,
            effectiveModelId: 'model',
            modelLabel: 'Model',
          ),
        ),
        chatProvider.overrideWith(_BackgroundTestChatNotifier.new),
        chatServiceProvider.overrideWithValue(serviceA),
        chatServiceFactoryProvider.overrideWithValue((_) {
          factoryCallCount++;
          return factoryCallCount == 1 ? serviceA : serviceB;
        }),
        chatParamsProvider.overrideWithValue(ChatParameters.defaults()),
        chatMcpConfigProvider.overrideWith(_DisabledMcpNotifier.new),
        toolRegistryProvider.overrideWithValue(
          ToolRegistry(providers: const []),
        ),
        chatBackgroundServiceProvider.overrideWithValue(bgService),
        settingsProvider.overrideWith(_TestSettingsNotifier.new),
        voiceModeProvider.overrideWith(_IdleVoiceModeNotifier.new),
        conv.conversationsProvider.overrideWith(_FakeConversationsNotifier.new),
      ],
    );
    await container.read(conv.conversationsProvider.future);
    final n =
        container.read(chatProvider.notifier) as _BackgroundTestChatNotifier;

    // Start reply in A, switch to B, send.
    await n.loadConversation(_conversationA);
    await n.continueFromMessage('a-assistant');
    await _pump();
    serviceA.emit('Hello from A');
    await _pump();

    await n.loadConversation(_conversationB);
    await n.continueFromMessage('b-assistant');
    await _pump();
    serviceB.emit('Hello from B');
    await _pump();

    expect(container.read(activeGenerationsProvider).length, 2);

    // Cancel only B (the open chat).
    await n.cancelStream();
    await _pump();

    expect(serviceB.cancelCount, 1, reason: 'B should be cancelled');
    expect(serviceA.cancelCount, 0, reason: 'A should still run');
    expect(container.read(activeGenerationsProvider).length, 1);
    expect(
      container.read(activeGenerationsProvider),
      contains('conversation-a'),
    );
  });

  ProviderContainer buildContainer({
    required Server server,
    required ChatService Function(Server) factory,
  }) {
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          container.read(sharedPreferencesProvider),
        ),
        activeServerProvider.overrideWith(_RemoteServerNotifier.new),
        activeChatTargetProvider.overrideWithValue(
          ActiveChatTarget(
            server: server,
            selectedModel: null,
            effectiveModelId: 'model',
            modelLabel: 'Model',
          ),
        ),
        chatProvider.overrideWith(_BackgroundTestChatNotifier.new),
        chatServiceProvider.overrideWithValue(chatService),
        chatServiceFactoryProvider.overrideWithValue(factory),
        chatParamsProvider.overrideWithValue(ChatParameters.defaults()),
        chatMcpConfigProvider.overrideWith(_DisabledMcpNotifier.new),
        toolRegistryProvider.overrideWithValue(
          ToolRegistry(providers: const []),
        ),
        chatBackgroundServiceProvider.overrideWithValue(bgService),
        settingsProvider.overrideWith(_TestSettingsNotifier.new),
        voiceModeProvider.overrideWith(_IdleVoiceModeNotifier.new),
        conv.conversationsProvider.overrideWith(_FakeConversationsNotifier.new),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('concurrent remote replies stream into their own chats', () async {
    final serviceA = _ControllableChatService();
    final serviceB = _ControllableChatService();
    var built = 0;
    final c = buildContainer(
      server: _remoteServer,
      factory: (_) => ++built == 1 ? serviceA : serviceB,
    );
    await c.read(conv.conversationsProvider.future);
    final n = c.read(chatProvider.notifier) as _BackgroundTestChatNotifier;

    await n.loadConversation(_conversationA);
    await n.continueFromMessage('a-assistant');
    await _pump();
    serviceA.emit(' one');

    await n.loadConversation(_conversationB);
    await n.continueFromMessage('b-assistant');
    await _pump();
    serviceB.emit(' two');
    await _pump();

    expect(c.read(activeGenerationsProvider).keys, [
      'conversation-a',
      'conversation-b',
    ]);
    expect(bgService.startCount, 1);

    // A finishes while B is the open chat; B keeps streaming.
    await serviceA.finish();
    await _pump();
    expect(c.read(activeGenerationsProvider).keys, ['conversation-b']);
    expect(c.read(chatProvider).isStreaming, isTrue);
    expect(bgService.stopCount, 0);

    await serviceB.finish();
    await _pump();

    final a = n.saved.lastWhere((m) => m.id == 'a-assistant');
    final b = n.saved.lastWhere((m) => m.id == 'b-assistant');
    expect(a.conversationId, 'conversation-a');
    expect(a.content, contains('one'));
    expect(a.content, isNot(contains('two')));
    expect(b.conversationId, 'conversation-b');
    expect(b.content, contains('two'));
    expect(b.content, isNot(contains('one')));
    expect(c.read(activeGenerationsProvider), isEmpty);
    expect(bgService.stopCount, 1);
  });

  test('on-device: a second chat cannot send while one is replying', () async {
    final onDeviceService = _ControllableChatService();
    final c = buildContainer(
      server: _onDeviceServer,
      factory: (_) => onDeviceService,
    );
    await c.read(conv.conversationsProvider.future);
    final n = c.read(chatProvider.notifier) as _BackgroundTestChatNotifier;

    await n.loadConversation(_conversationA);
    await n.continueFromMessage('a-assistant');
    await _pump();
    onDeviceService.emit(' hi');
    await n.loadConversation(_conversationB);
    await _pump();

    await n.sendMessage('blocked question');

    expect(c.read(chatProvider).errorMessage, onDeviceBusyMessage);
    expect(onDeviceService.controllers, hasLength(1));
    expect(
      c.read(activeGenerationsProvider).keys,
      ['conversation-a'],
      reason: 'the on-device reply in A keeps running',
    );
    expect(onDeviceService.cancelCount, 0);

    // Once it finishes, the other chat may send.
    await onDeviceService.finish();
    await _pump();
    await n.sendMessage('now allowed');
    expect(c.read(chatProvider).errorMessage, isNot(onDeviceBusyMessage));
    expect(onDeviceService.controllers, hasLength(2));
  });

  test('cancelAllGenerations clears every session', () async {
    await startReplyInA();

    await notifier.cancelAllGenerations();

    expect(chatService.cancelCount, 1);
    expect(container.read(activeGenerationsProvider), isEmpty);
  });

  test(
    'background service starts once and stops after the last session ends',
    () async {
      await startReplyInA();
      expect(bgService.startCount, 1);
      expect(bgService.stopCount, 0);

      await chatService.finish();
      await _pump();

      expect(bgService.startCount, 1);
      expect(bgService.stopCount, 1);
    },
  );
}

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final _remoteServer = Server(
  id: 'remote',
  name: 'Remote',
  type: ServerType.ollama,
  host: '127.0.0.1',
  port: 11434,
  createdAt: DateTime.utc(2026, 9, 28),
  lastConnectedAt: DateTime.utc(2026, 9, 28),
  status: ConnectionStatus.connected,
);

final _onDeviceServer = Server(
  id: 'on-device',
  name: 'On-device',
  type: ServerType.onDevice,
  host: 'localhost',
  port: 0,
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
  Server? build() => _remoteServer;
}

class _DisabledMcpNotifier extends ChatMcpConfigNotifier {
  @override
  ChatMcpConfig build() => const ChatMcpConfig(enabled: false);
}

class _TestChatBackgroundService extends ChatBackgroundService {
  int startCount = 0;
  int stopCount = 0;

  @override
  Future<void> start() async {
    startCount++;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
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
