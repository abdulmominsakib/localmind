import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/chat_background_service_provider.dart';
import 'package:localmind/core/services/chat_background_service.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/stt/providers/stt_providers.dart';
import 'package:localmind/features/tts/providers/tts_providers.dart';
import 'package:localmind/features/voice_mode/providers/voice_mode_provider.dart';
import 'package:localmind/services/voice_feedback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingChatNotifier chat;
  late _RecordingSttNotifier stt;

  setUp(() {
    chat = _RecordingChatNotifier();
    stt = _RecordingSttNotifier();
  });

  ProviderContainer buildContainer(ModelInfo? targetModel) {
    final target = ActiveChatTarget(
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
      selectedModel: targetModel,
      effectiveModelId: targetModel?.id ?? 'default',
      modelLabel: targetModel?.name ?? 'Default model',
    );
    return ProviderContainer(
      overrides: [
        sttProvider.overrideWith(() => stt),
        chatProvider.overrideWith(() => chat),
        chatBackgroundServiceProvider.overrideWithValue(
          ChatBackgroundService(),
        ),
        activeChatTargetProvider.overrideWithValue(target),
        ttsProvider.overrideWith(_StubTtsNotifier.new),
        voiceFeedbackProvider.overrideWithValue(_NoopVoiceFeedbackService()),
      ],
    );
  }

  test(
    'the screenshot is deferred, not auto-submitted, at session start',
    () async {
      final container = buildContainer(_visionModel(supportsVision: true));
      addTearDown(container.dispose);

      container
          .read(voiceModeProvider.notifier)
          .startSession(assistantScreenshotPath: '/tmp/screen.png');
      await _flushAsyncWork();

      expect(chat.newConversationCount, 0);
      expect(chat.sentMessages, isEmpty);
      // Listening stays on top of the pending screenshot.
      expect(stt.startCount, 1);
    },
  );

  test(
    'sending without speech submits the screenshot alone in a new thread',
    () async {
      final container = buildContainer(_visionModel(supportsVision: true));
      addTearDown(container.dispose);

      container
          .read(voiceModeProvider.notifier)
          .startSession(assistantScreenshotPath: '/tmp/screen.png');
      await _flushAsyncWork();
      await container.read(voiceModeProvider.notifier).stopListeningAndSend();

      expect(chat.newConversationCount, 1);
      expect(chat.sentMessages, hasLength(1));
      expect(chat.sentMessages.single.$1, '');
      expect(chat.sentMessages.single.$2?.single.path, '/tmp/screen.png');
      expect(container.read(voiceModeProvider).phase, VoiceModePhase.sent);
    },
  );

  test(
    'a spoken question submits the transcript with the screenshot attached',
    () async {
      final container = buildContainer(_visionModel(supportsVision: true));
      addTearDown(container.dispose);

      container
          .read(voiceModeProvider.notifier)
          .startSession(assistantScreenshotPath: '/tmp/screen.png');
      await _flushAsyncWork();
      stt.speak('what is on this screen?');
      await _flushAsyncWork();
      await container.read(voiceModeProvider.notifier).stopListeningAndSend();

      expect(chat.newConversationCount, 1);
      expect(chat.sentMessages, hasLength(1));
      expect(chat.sentMessages.single.$1, 'what is on this screen?');
      expect(chat.sentMessages.single.$2?.single.path, '/tmp/screen.png');
      expect(container.read(voiceModeProvider).phase, VoiceModePhase.sent);
    },
  );

  test(
    'excluding the screenshot sends plain text and text-less sends are refused',
    () async {
      final container = buildContainer(_visionModel(supportsVision: true));
      addTearDown(container.dispose);

      container
          .read(voiceModeProvider.notifier)
          .startSession(assistantScreenshotPath: '/tmp/screen.png');
      await _flushAsyncWork();
      container.read(voiceModeProvider.notifier).toggleExcludeScreenshot();
      expect(container.read(voiceModeProvider).excludeScreenshot, isTrue);

      // Text-less send with the screenshot excluded is refused outright.
      await container.read(voiceModeProvider.notifier).stopListeningAndSend();
      expect(chat.sentMessages, isEmpty);
      expect(container.read(voiceModeProvider).phase, VoiceModePhase.error);

      // A spoken message still goes through as plain text.
      stt.speak('follow up please');
      await _flushAsyncWork();
      await container.read(voiceModeProvider.notifier).stopListeningAndSend();
      expect(chat.sentMessages, hasLength(1));
      expect(chat.sentMessages.single.$1, 'follow up please');
      expect(chat.sentMessages.single.$2, isNull);
    },
  );

  test('without a screenshot, an empty send remains refused', () async {
    final container = buildContainer(_visionModel(supportsVision: true));
    addTearDown(container.dispose);

    container.read(voiceModeProvider.notifier).startSession();
    await _flushAsyncWork();
    await container.read(voiceModeProvider.notifier).stopListeningAndSend();

    expect(chat.sentMessages, isEmpty);
    expect(container.read(voiceModeProvider).phase, VoiceModePhase.error);
  });

  test(
    'a screenshot silently degrades to plain text for non-vision models',
    () async {
      final container = buildContainer(_visionModel(supportsVision: false));
      addTearDown(container.dispose);

      container
          .read(voiceModeProvider.notifier)
          .startSession(assistantScreenshotPath: '/tmp/screen.png');
      await _flushAsyncWork();
      stt.speak('describe my battery usage');
      await _flushAsyncWork();
      await container.read(voiceModeProvider.notifier).stopListeningAndSend();

      expect(chat.newConversationCount, 0);
      expect(chat.sentMessages, hasLength(1));
      expect(chat.sentMessages.single.$1, 'describe my battery usage');
      expect(chat.sentMessages.single.$2, isNull);
    },
  );

  test(
    'ending the session deletes an unsent captured screenshot file',
    () async {
      Directory('/tmp/localmind_test_screenshots').createSync(recursive: true);
      final file = File('/tmp/localmind_test_screenshots/assistant_capture.png')
        ..writeAsBytesSync(utf8.encode('fake-png'));
      expect(file.existsSync(), isTrue);

      final container = buildContainer(_visionModel(supportsVision: true));
      addTearDown(container.dispose);

      container
          .read(voiceModeProvider.notifier)
          .startSession(assistantScreenshotPath: file.path);
      await _flushAsyncWork();
      await container.read(voiceModeProvider.notifier).endSession();

      expect(file.existsSync(), isFalse);
    },
  );
}

ModelInfo _visionModel({required bool supportsVision}) => ModelInfo(
  id: 'default',
  name: 'Vision Model',
  serverType: ServerType.ollama,
  serverId: 'remote',
  supportsVision: supportsVision,
);

Future<void> _flushAsyncWork() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _RecordingChatNotifier extends ChatNotifier {
  int newConversationCount = 0;
  final List<(String, List<File>?)> sentMessages = [];

  @override
  ChatState build() => const ChatState();

  @override
  Future<void> startNewConversation() async {
    newConversationCount++;
  }

  @override
  Future<void> sendMessage(String content, {List<File>? attachments}) async {
    sentMessages.add((
      content,
      attachments == null ? null : List.of(attachments),
    ));
  }
}

class _RecordingSttNotifier extends SttNotifier {
  int startCount = 0;
  void Function(String)? _onResultSink;

  @override
  SttState build() => const SttState(isAvailable: true);

  @override
  Future<bool> initSpeech() async => true;

  @override
  Future<void> startListening({
    required void Function(String) onResult,
    void Function(String)? onFinal,
    SoundLevelChange? onSoundLevelChange,
  }) async {
    startCount++;
    _onResultSink = onResult;
  }

  /// Simulates recognized words landing from the platform recognizer.
  void speak(String words) => _onResultSink?.call(words);

  @override
  Future<void> cancelListening() async {}
}

class _StubTtsNotifier extends TtsNotifier {
  @override
  TtsState build() => const TtsState();
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
