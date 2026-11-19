import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';
import 'package:localmind/features/tts/data/piper_tts_downloader.dart';
import 'package:localmind/features/tts/data/piper_tts_model.dart';
import 'package:localmind/features/tts/providers/tts_model_providers.dart';
import 'package:localmind/features/tts/providers/tts_providers.dart';
import 'package:localmind/features/tts/providers/tts_worker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const audioSession = MethodChannel('com.ryanheise.audio_session');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _TestAudioPlayer player;
  late ProviderContainer container;
  late TtsNotifier notifier;
  final multiChunkText =
      '${'First sentence. ' * 10}${'Second sentence. ' * 10}';

  setUp(() {
    messenger.setMockMethodCallHandler(audioSession, (_) async => null);
    player = _TestAudioPlayer();
    container = ProviderContainer.test(
      overrides: [
        ttsProvider.overrideWith(
          () => TtsNotifier(player: player, workerEntry: _fakeWorker),
        ),
        settingsProvider.overrideWith(_TestSettings.new),
        piperTtsDownloaderProvider.overrideWithValue(_TestPiperDownloader()),
      ],
    );
    notifier = container.read(ttsProvider.notifier);
  });

  tearDown(() => messenger.setMockMethodCallHandler(audioSession, null));

  test(
    'stop contains a native load abort and discards queued chunks',
    () async {
      await notifier.speak(multiChunkText);
      final load = await player.loadStarted.future;

      await notifier.stop();
      expect(load.isCompleted, isTrue);
      expect(container.read(ttsProvider).isSpeaking, isFalse);
      expect(container.read(ttsProvider).error, isNull);

      player.loadStarted = Completer();
      await notifier.speak('Try again.');
      final retry = await player.loadStarted.future;
      retry.complete(const Duration(milliseconds: 100));
      await player.playStarted.future;

      expect(player.appendCount, 0);
      expect(container.read(ttsProvider).isSpeaking, isTrue);
      expect(container.read(ttsProvider).error, isNull);
      await notifier.stop();
    },
  );

  test(
    'a failed active load resets playback and preserves the error',
    () async {
      final failed = Completer<TtsState>();
      container.listen(ttsProvider, (_, next) {
        if (next.error != null && !failed.isCompleted) failed.complete(next);
      });
      await notifier.speak(multiChunkText);
      final load = await player.loadStarted.future;
      load.completeError(PlayerException(1, 'Could not decode audio', 0));

      final state = await failed.future;
      expect(state.error, contains('Could not decode audio'));
      expect(state.isSpeaking, isFalse);
      expect(state.isInitializing, isFalse);
      expect(state.canSeek, isFalse);
      expect(player.appendCount, 0);
      expect(player.playStarted.isCompleted, isFalse);
    },
  );

  test(
    'appends worker chunks in order after the first load completes',
    () async {
      await notifier.speak(multiChunkText);
      final load = await player.loadStarted.future;
      expect(player.appendCount, 0);

      load.complete(const Duration(milliseconds: 100));
      await player.chunkAppended.future;
      expect(player.playStarted.isCompleted, isTrue);
      expect(player.loadCount, 1);
      await notifier.stop();
    },
  );
}

void _fakeWorker(SendPort responses) {
  final requests = ReceivePort();
  responses.send(requests.sendPort);
  requests.listen((request) {
    if (request is TtsInitRequest) {
      responses.send(TtsWorkerResponse(isInitResponse: true));
    } else if (request is TtsSynthesizeRequest) {
      final bytes = ByteData(44)
        ..setUint32(24, 16000, Endian.little)
        ..setUint32(40, 3200, Endian.little);
      responses.send(
        TtsWorkerResponse(
          chunkIndex: request.chunkIndex,
          sessionId: request.sessionId,
          wavBytes: bytes.buffer.asUint8List(),
        ),
      );
    }
  });
}

class _TestSettings extends SettingsNotifier {
  @override
  AppSettings build() =>
      AppSettings(ttsEngine: EngineId.piper, ttsProcessMarkdown: false);
}

class _TestPiperDownloader extends PiperTtsDownloader {
  @override
  Future<Set<PiperTtsModelVariant>> getDownloadedVariants() async => {};

  @override
  Future<String?> getModelPath(PiperTtsModelVariant variant) async => 'model';

  @override
  Future<String?> getTokensPath(PiperTtsModelVariant variant) async => 'tokens';

  @override
  Future<Directory> getDataDir(PiperTtsModelVariant variant) async =>
      Directory.systemTemp;
}

class _TestAudioPlayer extends Fake implements AudioPlayer {
  Completer<Completer<Duration?>> loadStarted = Completer();
  final playStarted = Completer<void>();
  final chunkAppended = Completer<void>();
  Completer<Duration?>? _load;
  int appendCount = 0;
  int loadCount = 0;

  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();
  @override
  Stream<PlaybackEvent> get playbackEventStream => const Stream.empty();
  @override
  Stream<int?> get currentIndexStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Duration get position => Duration.zero;

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) {
    loadCount++;
    final load = _load = Completer<Duration?>();
    if (!loadStarted.isCompleted) loadStarted.complete(load);
    return load.future;
  }

  @override
  Future<void> addAudioSource(AudioSource audioSource) async {
    appendCount++;
    if (!chunkAppended.isCompleted) chunkAppended.complete();
  }

  @override
  Future<void> play() async {
    if (!playStarted.isCompleted) playStarted.complete();
  }

  @override
  Future<void> stop() async {
    final load = _load;
    if (load != null && !load.isCompleted) {
      load.completeError(PlayerInterruptedException('Connection aborted'));
    }
  }

  @override
  Future<void> clearAudioSources() async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> dispose() async {}
}
