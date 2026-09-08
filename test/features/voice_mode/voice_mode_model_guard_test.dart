import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/providers/chat_background_service_provider.dart';
import 'package:localmind/core/services/chat_background_service.dart';
import 'package:localmind/features/chat/providers/chat_notifier.dart';
import 'package:localmind/features/chat/providers/model_selection_providers.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/stt/providers/stt_providers.dart';
import 'package:localmind/features/tts/providers/tts_providers.dart';
import 'package:localmind/features/voice_mode/providers/voice_mode_provider.dart';
import 'package:localmind/services/voice_feedback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('voice mode does not listen when no model is selected', () async {
    final stt = _RecordingSttNotifier();
    final container = ProviderContainer(
      overrides: [
        sttProvider.overrideWith(() => stt),
        ttsProvider.overrideWith(_StubTtsNotifier.new),
        chatProvider.overrideWith(_StubChatNotifier.new),
        activeServerProvider.overrideWith(_ConnectedServerNotifier.new),
        onDeviceEngineProvider.overrideWith(_EmptyEngineNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(voiceModeProvider.notifier);
    notifier.startSession();

    expect(container.read(voiceModeProvider).phase, VoiceModePhase.error);
    expect(
      container.read(voiceModeProvider).error,
      modelSelectionRequiredMessage,
    );
    expect(stt.startCount, 0);

    await notifier.startListening();
    expect(stt.startCount, 0);
  });

  test(
    'voice mode initializes STT before starting the microphone service',
    () async {
      final events = <String>[];
      final stt = _RecordingSttNotifier(events: events);
      final background = _RecordingChatBackgroundService(events: events);
      final container = _readyVoiceContainer(stt, background);
      addTearDown(container.dispose);

      container.read(voiceModeProvider.notifier).startSession();
      await _flushAsyncWork();

      expect(events, ['initSpeech', 'startMic', 'startListening']);
    },
  );

  test(
    'voice mode does not start the microphone service when permission is denied',
    () async {
      final events = <String>[];
      final stt = _RecordingSttNotifier(events: events, initAvailable: false);
      final background = _RecordingChatBackgroundService(events: events);
      final container = _readyVoiceContainer(stt, background);
      addTearDown(container.dispose);

      container.read(voiceModeProvider.notifier).startSession();
      await _flushAsyncWork();

      expect(events, ['initSpeech']);
      expect(
        container.read(voiceModeProvider).error,
        'Microphone permission is required for voice mode.',
      );
    },
  );

  test(
    'voice mode cancels STT before stopping the microphone service',
    () async {
      final events = <String>[];
      final stt = _RecordingSttNotifier(events: events);
      final background = _RecordingChatBackgroundService(events: events);
      final container = _readyVoiceContainer(stt, background);
      addTearDown(container.dispose);

      final notifier = container.read(voiceModeProvider.notifier);
      notifier.startSession();
      await _flushAsyncWork();
      events.clear();

      await notifier.endSession();

      expect(events, ['cancelListening', 'stopMic']);
    },
  );

  test('voice mode reports a microphone service start failure', () async {
    final events = <String>[];
    final stt = _RecordingSttNotifier(events: events);
    final background = _RecordingChatBackgroundService(
      events: events,
      startResult: false,
    );
    final container = _readyVoiceContainer(stt, background);
    addTearDown(container.dispose);

    container.read(voiceModeProvider.notifier).startSession();
    await _flushAsyncWork();

    expect(events, ['initSpeech', 'startMic']);
    expect(container.read(voiceModeProvider).phase, VoiceModePhase.error);
  });
}

ProviderContainer _readyVoiceContainer(
  _RecordingSttNotifier stt,
  _RecordingChatBackgroundService background,
) {
  return ProviderContainer(
    overrides: [
      sttProvider.overrideWith(() => stt),
      chatBackgroundServiceProvider.overrideWithValue(background),
      activeChatTargetProvider.overrideWithValue(
        ActiveChatTarget(
          server: Server(
            id: 'remote',
            name: 'Remote',
            type: ServerType.ollama,
            host: '127.0.0.1',
            port: 11434,
            createdAt: DateTime.utc(2026, 8, 13),
            lastConnectedAt: DateTime.utc(2026, 8, 13),
            status: ConnectionStatus.connected,
          ),
          selectedModel: null,
          effectiveModelId: 'default',
          modelLabel: 'Default model',
        ),
      ),
      ttsProvider.overrideWith(_StubTtsNotifier.new),
      chatProvider.overrideWith(_StubChatNotifier.new),
      voiceFeedbackProvider.overrideWithValue(_NoopVoiceFeedbackService()),
    ],
  );
}

Future<void> _flushAsyncWork() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _ConnectedServerNotifier extends ActiveServerNotifier {
  @override
  Server? build() => Server(
    id: 'on-device',
    name: 'On-Device',
    type: ServerType.onDevice,
    host: '',
    port: 0,
    createdAt: DateTime.utc(2026, 8, 13),
    lastConnectedAt: DateTime.utc(2026, 8, 13),
    status: ConnectionStatus.connected,
  );
}

class _EmptyEngineNotifier extends OnDeviceEngineNotifier {
  @override
  OnDeviceEngineState build() => const OnDeviceEngineState();
}

class _RecordingSttNotifier extends SttNotifier {
  _RecordingSttNotifier({this.events = const [], this.initAvailable = true});

  final List<String> events;
  final bool initAvailable;
  int startCount = 0;

  @override
  SttState build() => SttState(isAvailable: initAvailable);

  @override
  Future<bool> initSpeech() async {
    events.add('initSpeech');
    return initAvailable;
  }

  @override
  Future<void> startListening({
    required void Function(String) onResult,
    void Function(String)? onFinal,
    SoundLevelChange? onSoundLevelChange,
  }) async {
    events.add('startListening');
    startCount++;
  }

  @override
  Future<void> cancelListening() async {
    events.add('cancelListening');
  }
}

class _RecordingChatBackgroundService extends ChatBackgroundService {
  _RecordingChatBackgroundService({
    required this.events,
    this.startResult = true,
  });

  final List<String> events;
  final bool startResult;

  @override
  Future<bool> startMic() async {
    events.add('startMic');
    return startResult;
  }

  @override
  Future<void> stopMic() async {
    events.add('stopMic');
  }
}

class _NoopVoiceFeedbackService implements VoiceFeedbackService {
  @override
  Future<void> dispose() async {}

  @override
  Future<void> playConnected() async {}

  @override
  Future<void> playDisconnected() async {}

  @override
  Future<void> playGenerating() async {}

  @override
  Future<void> playListening() async {}

  @override
  Future<void> preload() async {}
}

class _StubTtsNotifier extends TtsNotifier {
  @override
  TtsState build() => const TtsState();
}

class _StubChatNotifier extends ChatNotifier {
  @override
  ChatState build() => const ChatState();
}
