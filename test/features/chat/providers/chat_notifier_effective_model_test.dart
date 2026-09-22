import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/providers/chat_background_service_provider.dart';
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
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';
import 'package:localmind/features/voice_mode/providers/voice_mode_provider.dart';

void main() {
  test(
    'continues with the loaded model when selection metadata is unavailable',
    () async {
      final chatService = _RecordingChatService();
      final container = ProviderContainer(
        overrides: [
          activeServerProvider.overrideWith(_OnDeviceServerNotifier.new),
          onDeviceEngineProvider.overrideWith(_LoadedLlamaEngineNotifier.new),
          selectedModelProvider.overrideWith(_UnselectedModelNotifier.new),
          chatProvider.overrideWith(_FallbackChatNotifier.new),
          chatServiceProvider.overrideWithValue(chatService),
          chatParamsProvider.overrideWithValue(ChatParameters.defaults()),
          chatMcpConfigProvider.overrideWith(
            _DisabledChatMcpConfigNotifier.new,
          ),
          toolRegistryProvider.overrideWithValue(
            ToolRegistry(providers: const []),
          ),
          chatBackgroundServiceProvider.overrideWithValue(
            _TestChatBackgroundService(),
          ),
          settingsProvider.overrideWith(_TestSettingsNotifier.new),
          voiceModeProvider.overrideWith(_IdleVoiceModeNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(chatProvider.notifier)
          .continueFromMessage('assistant-1');

      expect(await chatService.requestedModelId.future, 'imported-gguf-model');
    },
  );
}

class _FallbackChatNotifier extends ChatNotifier {
  @override
  ChatState build() {
    final messages = [
      Message(
        id: 'user-1',
        conversationId: 'conversation-1',
        role: MessageRole.user,
        content: 'Hello',
        createdAt: DateTime.utc(2026, 9, 22),
      ),
      Message(
        id: 'assistant-1',
        conversationId: 'conversation-1',
        role: MessageRole.assistant,
        content: 'Hello there.',
        createdAt: DateTime.utc(2026, 9, 22),
      ),
    ];
    return ChatState(
      messages: messages,
      allMessages: messages,
      isTemporary: true,
    );
  }
}

class _RecordingChatService implements ChatService {
  final requestedModelId = Completer<String>();

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
    if (!requestedModelId.isCompleted) {
      requestedModelId.complete(modelId);
    }
    yield const ChatResponse(
      type: ChatResponseType.error,
      content: 'Expected test failure',
    );
  }

  @override
  void cancelStream() {}
}

class _DisabledChatMcpConfigNotifier extends ChatMcpConfigNotifier {
  @override
  ChatMcpConfig build() => const ChatMcpConfig(enabled: false);
}

class _TestChatBackgroundService extends ChatBackgroundService {
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

class _OnDeviceServerNotifier extends ActiveServerNotifier {
  @override
  Server? build() => Server(
    id: 'on-device',
    name: 'On-Device',
    type: ServerType.onDevice,
    host: '',
    port: 0,
    createdAt: DateTime.utc(2026, 9, 22),
    lastConnectedAt: DateTime.utc(2026, 9, 22),
    status: ConnectionStatus.connected,
  );
}

class _LoadedLlamaEngineNotifier extends OnDeviceEngineNotifier {
  @override
  OnDeviceEngineState build() => const OnDeviceEngineState(
    status: OnDeviceEngineStatus.loaded,
    loadedModelId: 'imported-gguf-model',
    loadedRuntime: OnDeviceModelRuntime.llamaCpp,
  );
}

class _UnselectedModelNotifier extends SelectedModelNotifier {
  @override
  ModelInfo? build() => null;
}

class _TestSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings(
    mcpEnabled: false,
    newChatMcpEnabled: false,
    resumeLastChat: false,
  );
}

class _IdleVoiceModeNotifier extends VoiceModeNotifier {
  @override
  VoiceModeState build() => const VoiceModeState();
}
