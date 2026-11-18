import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/services/app_haptics.dart';
import 'package:localmind/features/chat/data/models/live_generation.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/chat/views/components/chat_input_bar.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/os_widget/providers/os_widget_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';
import 'package:localmind/features/stt/providers/stt_providers.dart';
import 'package:localmind/features/tts/providers/tts_providers.dart';
import 'package:localmind/features/voice_mode/providers/voice_mode_provider.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:speech_to_text/speech_to_text.dart';

class _FixedChatNotifier extends ChatNotifier {
  _FixedChatNotifier(this._fixedState);
  final ChatState _fixedState;

  @override
  ChatState build() => _fixedState;
}

class _MockSettingsNotifier extends SettingsNotifier {
  _MockSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  AppSettings build() => _settings;
}

class _NoActiveConversation extends conv.ActiveConversationNotifier {
  @override
  Conversation? build() => null;
}

class _NoActiveConversationId extends conv.ActiveConversationIdNotifier {
  @override
  String? build() => null;
}

class _EmptyConversations extends conv.ConversationsNotifier {
  @override
  Future<List<Conversation>> build() async => [];
}

class _StubTtsNotifier extends TtsNotifier {
  @override
  TtsState build() => const TtsState();
}

class _StubSttNotifier extends SttNotifier {
  _StubSttNotifier() : super(speechFactory: SpeechToText.new);

  @override
  SttState build() => const SttState(isAvailable: false);
}

class _StubVoiceModeNotifier extends VoiceModeNotifier {
  @override
  VoiceModeState build() => VoiceModeState();
}

class _ConnectedStatus extends ConnectionStatusNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

class _ActiveServer extends ActiveServerNotifier {
  @override
  Server? build() => null;
}

class _Servers extends ServersNotifier {
  @override
  Future<List<Server>> build() async => const [];
}

class _SelectedModel extends SelectedModelNotifier {
  @override
  ModelInfo? build() => null;
}

class _ReasoningConfig extends ChatReasoningConfigNotifier {
  @override
  ChatReasoningConfig build() => const ChatReasoningConfig();
}

class _Streaming extends IsStreamingNotifier {
  @override
  bool build() => false;
}

class _ActiveGens extends ActiveGenerationsNotifier {
  @override
  Map<String, ActiveGeneration> build() => const {};
}

class _PendingPrompt extends WidgetPendingPromptNotifier {
  @override
  String? build() => null;
}

class _OnDeviceEngine extends OnDeviceEngineNotifier {
  @override
  OnDeviceEngineState build() =>
      const OnDeviceEngineState(status: OnDeviceEngineStatus.notLoaded);
}

Widget _inputHost({
  required ChatState chatState,
  bool showIndicator = true,
}) {
  final target = ActiveChatTarget(
    server: Server(
      id: 's1',
      name: 'Server',
      type: ServerType.ollama,
      host: 'localhost',
      port: 11434,
      createdAt: DateTime.utc(2026),
      lastConnectedAt: DateTime.utc(2026),
      status: ConnectionStatus.connected,
    ),
    selectedModel: null,
    effectiveModelId: 'm1',
    modelLabel: 'Model',
  );
  return ProviderScope(
    overrides: [
      chatProvider.overrideWith(() => _FixedChatNotifier(chatState)),
      settingsProvider.overrideWith(
        () => _MockSettingsNotifier(
          AppSettings(showPromptProcessingIndicator: showIndicator),
        ),
      ),
      conv.activeConversationProvider.overrideWith(_NoActiveConversation.new),
      conv.activeConversationIdProvider.overrideWith(
        () => _NoActiveConversationId(),
      ),
      conv.conversationsProvider.overrideWith(_EmptyConversations.new),
      ttsProvider.overrideWith(_StubTtsNotifier.new),
      sttProvider.overrideWith(_StubSttNotifier.new),
      voiceModeProvider.overrideWith(_StubVoiceModeNotifier.new),
      appHapticsProvider.overrideWith((ref) => AppHaptics(() => false)),
      connectionStatusProvider.overrideWith(_ConnectedStatus.new),
      activeServerProvider.overrideWith(_ActiveServer.new),
      serversProvider.overrideWith(_Servers.new),
      activeChatTargetProvider.overrideWithValue(target),
      selectedModelProvider.overrideWith(_SelectedModel.new),
      chatReasoningConfigProvider.overrideWith(_ReasoningConfig.new),
      isStreamingProvider.overrideWith(_Streaming.new),
      activeGenerationsProvider.overrideWith(_ActiveGens.new),
      widgetPendingPromptProvider.overrideWith(_PendingPrompt.new),
      onDeviceEngineProvider.overrideWith(_OnDeviceEngine.new),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ChatInputBar(onSend: (_, {attachments}) {}, onStop: () {}),
        ),
      ),
    ),
  );
}

void main() {
  group('ChatInputBar live status placement', () {
    testWidgets(
      'live + empty composer shows centered in-field status and no corner row',
      (tester) async {
        await tester.pumpWidget(
          _inputHost(
            chatState: ChatState(
              liveGeneration: LiveGeneration(
                phase: LiveGenerationPhase.processingPrompt,
                startedAt: DateTime.now(),
                estimatedPrefillMs: 3000,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byKey(const ValueKey('in-field-status')), findsOneWidget);
        expect(find.byKey(const ValueKey('corner-status')), findsNothing);
      },
    );

    testWidgets(
      'live + typed composer shows typed text in field and corner row above',
      (tester) async {
        await tester.pumpWidget(
          _inputHost(
            chatState: ChatState(
              liveGeneration: LiveGeneration(
                phase: LiveGenerationPhase.processingPrompt,
                startedAt: DateTime.now(),
                estimatedPrefillMs: 3000,
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.enterText(find.byKey(const ValueKey('chat_input')), 'hi');
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('corner-status')), findsOneWidget);
        expect(find.byKey(const ValueKey('in-field-status')), findsNothing);
        expect(find.text('hi'), findsOneWidget);
      },
    );

    testWidgets('empty->typed->empty flips placement both ways', (
      tester,
    ) async {
      await tester.pumpWidget(
        _inputHost(
          chatState: ChatState(
            liveGeneration: LiveGeneration(
              phase: LiveGenerationPhase.processingPrompt,
              startedAt: DateTime.now(),
              estimatedPrefillMs: 3000,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('in-field-status')), findsOneWidget);
      expect(find.byKey(const ValueKey('corner-status')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('chat_input')), 'hi');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('corner-status')), findsOneWidget);
      expect(find.byKey(const ValueKey('in-field-status')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('chat_input')), '');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('in-field-status')), findsOneWidget);
      expect(find.byKey(const ValueKey('corner-status')), findsNothing);
    });

    testWidgets(
      'disabled indicator keeps normal hint visible even while live',
      (tester) async {
        await tester.pumpWidget(
          _inputHost(
            chatState: ChatState(
              liveGeneration: LiveGeneration(
                phase: LiveGenerationPhase.processingPrompt,
                startedAt: DateTime.now(),
                estimatedPrefillMs: 3000,
              ),
            ),
            showIndicator: false,
          ),
        );
        await tester.pump();

        expect(find.byKey(const ValueKey('in-field-status')), findsNothing);
        expect(find.byKey(const ValueKey('chat_input')), findsOneWidget);
      },
    );
  });
}
