import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/providers/chat_notifier.dart';
import 'package:localmind/features/chat/providers/model_selection_providers.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/stt/providers/stt_providers.dart';
import 'package:localmind/features/tts/providers/tts_providers.dart';
import 'package:localmind/features/voice_mode/providers/voice_mode_provider.dart';

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
  int startCount = 0;

  @override
  SttState build() => const SttState(isAvailable: true);

  @override
  Future<void> startListening({
    required void Function(String) onResult,
    void Function(String)? onFinal,
    SoundLevelChange? onSoundLevelChange,
  }) async {
    startCount++;
  }
}

class _StubTtsNotifier extends TtsNotifier {
  @override
  TtsState build() => const TtsState();
}

class _StubChatNotifier extends ChatNotifier {
  @override
  ChatState build() => const ChatState();
}
