import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers/app_providers.dart';
import '../utils/tts_text_processor.dart';
import 'tts_model_providers.dart';
import '../data/piper_tts_model.dart';
import 'tts_worker.dart';
import '../utils/wav_merge.dart';

final ttsProvider = NotifierProvider<TtsNotifier, TtsState>(() {
  return TtsNotifier();
});

class TtsState {
  final bool isSpeaking;
  final bool isPaused;
  final bool isInitializing;
  final String? error;
  final EngineId? activeEngine;
  final String? playingContent;
  final String? playingMessageId;
  final String? playingConversationId;
  final bool isPreview;
  final Duration position;
  final Duration duration;
  final bool canSeek;
  final bool isSeekPending;
  final double playbackSpeed;

  const TtsState({
    this.isSpeaking = false,
    this.isPaused = false,
    this.isInitializing = false,
    this.error,
    this.activeEngine,
    this.playingContent,
    this.playingMessageId,
    this.playingConversationId,
    this.isPreview = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.canSeek = false,
    this.isSeekPending = false,
    this.playbackSpeed = 1.0,
  });

  TtsState copyWith({
    bool? isSpeaking,
    bool? isPaused,
    bool? isInitializing,
    String? error,
    EngineId? activeEngine,
    String? playingContent,
    String? playingMessageId,
    String? playingConversationId,
    bool? isPreview,
    Duration? position,
    Duration? duration,
    bool? canSeek,
    bool? isSeekPending,
    double? playbackSpeed,
    bool clearPlayingTarget = false,
    bool resetProgress = false,
  }) {
    return TtsState(
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isPaused: isPaused ?? this.isPaused,
      isInitializing: isInitializing ?? this.isInitializing,
      error: error,
      activeEngine: activeEngine ?? this.activeEngine,
      playingContent: playingContent,
      playingMessageId:
          clearPlayingTarget ? null : (playingMessageId ?? this.playingMessageId),
      playingConversationId: clearPlayingTarget
          ? null
          : (playingConversationId ?? this.playingConversationId),
      isPreview: isPreview ?? this.isPreview,
      position: resetProgress ? Duration.zero : (position ?? this.position),
      duration: resetProgress ? Duration.zero : (duration ?? this.duration),
      canSeek: canSeek ?? this.canSeek,
      isSeekPending: isSeekPending ?? this.isSeekPending,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    );
  }
}

class TtsNotifier extends Notifier<TtsState> {
  FlutterTts? _flutterTts;
  final AudioPlayer _player = AudioPlayer();
  bool _isPlayerDisposed = false;
  bool _isStopping = false;
  List<String> _chunks = [];
  int _currentChunkIndex = 0;
  EngineId? _currentEngine;
  String? _currentVoice;
  String? _currentModelPath;
  String? _currentVoicesPath;
  String? _currentTokensPath;
  String? _currentDataDir;
  String? _currentLexicon;

  // Isolate worker fields
  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  final ReceivePort _mainReceivePort = ReceivePort();
  final Map<int, Uint8List> _synthesizedChunks = {};
  int _lastEnqueuedChunk = -1;
  static const int _lookAheadCount = 2;
  Completer<void>? _initCompleter;
  bool _isWorkerInitializing = false;
  int _currentSessionId = 0;

  StreamSubscription<void>? _playerCompleteSubscription;
  int _playbackSessionId = 0;
  Completer<SendPort>? _workerPortCompleter;

  bool _isPreview = false;
  final Map<int, AudioSource> _playlistBuffer = {};
  int _nextPlaylistIndexToAdd = 0;
  StreamSubscription<int?>? _currentIndexSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  Timer? _systemProgressTimer;

  // Progress tracking
  final Map<int, Duration> _chunkDurations = {};
  Duration _totalDuration = Duration.zero;
  Duration _chunkOffset = Duration.zero;
  final StreamController<void> _onChunkChanged = StreamController<void>.broadcast();

  // System TTS approximate seek
  String? _systemFullText;
  Duration _systemSkippedOffset = Duration.zero;
  DateTime? _systemSpeakStart;
  int _systemSpeakGeneration = 0;

  _MessageAudioCache? _messageAudioCache;

  static const playbackSpeedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

  AudioPlayer get player => _player;
  Stream<Duration> get onPositionChanged => _player.positionStream;
  Duration get totalDuration => _totalDuration;
  Duration get chunkOffset => _chunkOffset;
  Stream<void> get onChunkChanged => _onChunkChanged.stream;

  @override
  TtsState build() {
    ref.keepAlive();

    ref.listen(settingsProvider, (previous, next) {
      if (previous?.ttsEngine != next.ttsEngine) {
        state = state.copyWith(activeEngine: next.ttsEngine);
      }
    });

    _player.setAudioSources([]);

    _playerCompleteSubscription = _player.playerStateStream.listen((playerState) {
      if (playerState.processingState != ProcessingState.completed) return;
      if (_isStopping || state.isInitializing) return;
      if (_currentSessionId != _playbackSessionId) return;
      if (_nextPlaylistIndexToAdd < _chunks.length) return;
      if (_lastEnqueuedChunk < _chunks.length - 1) return;
      _onPlaybackFinished();
    });

    _currentIndexSubscription = _player.currentIndexStream.listen((index) {
      if (index != null && index != _currentChunkIndex) {
        _currentChunkIndex = index;
        _updateChunkOffset();
        _onChunkChanged.add(null);
        _enqueueNextChunks();
        _updatePlaybackProgress();
      }
    });

    _positionSubscription = _player.positionStream.listen((_) {
      _updatePlaybackProgress();
    });

    _durationSubscription = _player.durationStream.listen((_) {
      _updatePlaybackProgress();
    });

    _setupWorkerListener();

    ref.onDispose(() {
      _workerPortCompleter?.completeError(StateError('Disposed'));
      _workerPortCompleter = null;
      _workerIsolate?.kill();
      _mainReceivePort.close();
      _playerCompleteSubscription?.cancel();
      _currentIndexSubscription?.cancel();
      _positionSubscription?.cancel();
      _durationSubscription?.cancel();
      _systemProgressTimer?.cancel();
      _onChunkChanged.close();
      if (!_isPlayerDisposed) {
        _isPlayerDisposed = true;
        try {
          _player.dispose();
        } catch (_) {}
      }
    });

    final settings = ref.read(settingsProvider);
    return TtsState(activeEngine: settings.ttsEngine);
  }

  void _setupWorkerListener() {
    _mainReceivePort.listen((message) async {
      if (message is SendPort) {
        _workerSendPort = message;
        _workerPortCompleter?.complete(message);
        _workerPortCompleter = null;
      } else if (message is TtsWorkerResponse) {
        if (message.isInitResponse) {
          _initCompleter?.complete();
          _initCompleter = null;
        } else if (message.chunkIndex != null) {
          if (message.sessionId != _currentSessionId) {
            Log.debug('Ignoring stale chunk ${message.chunkIndex}');
            return;
          }
          if (message.wavBytes != null) {
            _synthesizedChunks[message.chunkIndex!] = message.wavBytes!;
            _computeChunkDuration(message.chunkIndex!, message.wavBytes!);
            await _addChunkToPlaylist(message.chunkIndex!, message.wavBytes!);
            _updatePlaybackProgress();
          } else {
            Log.error(
              'Worker error for chunk ${message.chunkIndex}: ${message.error}',
            );
            _synthesizedChunks[message.chunkIndex!] = Uint8List(0);
            await _addChunkToPlaylist(message.chunkIndex!, Uint8List(0));
          }
        } else if (message.error != null) {
          Log.error('Worker general error: ${message.error}');
          _initCompleter?.completeError(message.error!);
          _initCompleter = null;
        }
      }
    });
  }

  Future<void> _ensureWorker() async {
    if (_workerIsolate != null) return;

    Log.info('Spawning TTS worker isolate...');
    _workerPortCompleter = Completer<SendPort>();
    _workerIsolate = await Isolate.spawn(
      ttsWorkerEntry,
      _mainReceivePort.sendPort,
    );

    await _workerPortCompleter!.future.timeout(
      const Duration(seconds: 10),
    );
  }

  void _computeChunkDuration(int index, Uint8List wavBytes) {
    if (wavBytes.length < 44) return;
    final data = ByteData.view(wavBytes.buffer, wavBytes.offsetInBytes, 44);
    final sampleRate = data.getUint32(24, Endian.little);
    final dataSize = data.getUint32(40, Endian.little);
    final sampleCount = dataSize ~/ 2;
    final durationMs = (sampleCount * 1000) ~/ sampleRate;
    _chunkDurations[index] = Duration(milliseconds: durationMs);
    _totalDuration = Duration.zero;
    for (final d in _chunkDurations.values) {
      _totalDuration += d;
    }
    _updatePlaybackProgress();
  }

  void _updateChunkOffset() {
    var offset = Duration.zero;
    for (var i = 0; i < _currentChunkIndex; i++) {
      offset += _chunkDurations[i] ?? Duration.zero;
    }
    _chunkOffset = offset;
  }

  Duration _averageChunkDuration() {
    if (_chunkDurations.isEmpty) return const Duration(seconds: 3);
    final totalMs = _chunkDurations.values.fold<int>(
      0,
      (sum, d) => sum + d.inMilliseconds,
    );
    return Duration(milliseconds: totalMs ~/ _chunkDurations.length);
  }

  Duration _estimatedTotalDuration() {
    if (_chunks.isEmpty) return Duration.zero;
    if (_chunkDurations.length >= _chunks.length) return _totalDuration;
    final avg = _averageChunkDuration();
    return Duration(
      milliseconds: avg.inMilliseconds * _chunks.length,
    );
  }

  Duration _computeGlobalPosition() {
    if (state.activeEngine == EngineId.system) {
      return _systemEstimatedPosition();
    }
    _updateChunkOffset();
    return _chunkOffset + _player.position;
  }

  void _updatePlaybackProgress() {
    if (!state.isSpeaking || state.isPreview) return;

    if (state.activeEngine == EngineId.system) {
      return;
    }

    final position = _computeGlobalPosition();
    final duration = _estimatedTotalDuration();
    state = state.copyWith(
      position: position,
      duration: duration,
      canSeek: !state.isInitializing &&
          duration > Duration.zero &&
          _nextPlaylistIndexToAdd >= _chunks.length,
    );
  }

  Duration _systemEstimatedDuration() {
    if (_systemFullText == null) return Duration.zero;
    final cps = 12.0 * ref.read(settingsProvider).ttsSpeed;
    return Duration(
      milliseconds: (_systemFullText!.length / cps * 1000).round(),
    );
  }

  Duration _systemEstimatedPosition() {
    if (_systemSpeakStart == null) return _systemSkippedOffset;
    final pos =
        _systemSkippedOffset + DateTime.now().difference(_systemSpeakStart!);
    final total = _systemEstimatedDuration();
    return pos > total ? total : pos;
  }

  void _stopSystemProgressTimer() {
    _systemProgressTimer?.cancel();
    _systemProgressTimer = null;
  }

  void _resetSystemSeekState() {
    _systemFullText = null;
    _systemSkippedOffset = Duration.zero;
    _systemSpeakStart = null;
    _stopSystemProgressTimer();
  }

  void _resetProgress() {
    _chunkDurations.clear();
    _totalDuration = Duration.zero;
    _chunkOffset = Duration.zero;
    _resetSystemSeekState();
  }

  void _deleteChunkFile(int sessionId, int chunkIndex) {
    if (chunkIndex < 0) return;
    try {
      final tempFile = File(
        '${Directory.systemTemp.path}/tts_chunk_${sessionId}_$chunkIndex.wav',
      );
      if (tempFile.existsSync()) tempFile.deleteSync();
    } catch (_) {}
  }

  void _cleanupSessionFiles(int sessionId, int chunkCount) {
    for (var i = 0; i < chunkCount; i++) {
      _deleteChunkFile(sessionId, i);
    }
  }

  void _onPlaybackFinished() {
    if (_isStopping) return;
    if (_currentSessionId != _playbackSessionId) return;
    _saveMessageAudioCache();
    _cleanupSessionFiles(_currentSessionId, _chunks.length);
    _resetProgress();
    state = state.copyWith(
      isSpeaking: false,
      isPaused: false,
      isInitializing: false,
      playingContent: null,
      isPreview: false,
      clearPlayingTarget: true,
      resetProgress: true,
      canSeek: false,
    );
  }

  List<String> _splitText(String text) {
    if (text.length <= 250) return [text];

    final regex = RegExp(r'(?<=[.!?])\s+');
    final sentences = text.split(regex);

    final List<String> chunks = [];
    String currentChunk = "";

    for (final sentence in sentences) {
      if ((currentChunk.length + sentence.length) > 250 &&
          currentChunk.isNotEmpty) {
        chunks.add(currentChunk.trim());
        currentChunk = "";
      }

      if (sentence.length > 250) {
        final subRegex = RegExp(r'(?<=[,;])\s+');
        final parts = sentence.split(subRegex);
        for (final part in parts) {
          if ((currentChunk.length + part.length) > 250 &&
              currentChunk.isNotEmpty) {
            chunks.add(currentChunk.trim());
            currentChunk = "";
          }
          currentChunk += "$part ";
        }
      } else {
        currentChunk += "$sentence ";
      }
    }

    if (currentChunk.trim().isNotEmpty) {
      chunks.add(currentChunk.trim());
    }

    return chunks;
  }

  Future<void> _initEngine(EngineId engineId, {String? voiceId}) async {
    await _ensureWorker();

    if (_isWorkerInitializing && _initCompleter != null) {
      await _initCompleter!.future.timeout(
        const Duration(seconds: 30),
      );
    }

    String modelPath = '';
    String voicesPath = '';
    String tokensPath = '';
    String dataDir = '';
    String lexicon = '';

    switch (engineId) {
      case EngineId.kitten:
        final variant = ref.read(settingsProvider).kittenTtsModelVariant;
        final kittenDl = ref.read(kittenTtsDownloaderProvider);
        final mPath = await kittenDl.getModelPath(variant);
        final vPath = await kittenDl.getVoicesPath(variant);
        final tPath = await kittenDl.getTokensPath(variant);
        final dDir = await kittenDl.getDataDir(variant);
        if (mPath == null || vPath == null || tPath == null) {
          throw StateError(
            'Kitten model files not found for ${variant.name}. Please download them in the Model Manager.',
          );
        }
        modelPath = mPath;
        voicesPath = vPath;
        tokensPath = tPath;
        dataDir = dDir.path;
        break;
      case EngineId.piper:
        final selectedVoiceId =
            voiceId ??
            ref.read(settingsProvider).ttsVoiceId ??
            piperVoices.first.id;
        final requestedVariant = PiperTtsModelVariant.values.firstWhere(
          (v) => v.id == selectedVoiceId,
          orElse: () => PiperTtsModelVariant.enUsLessacMedium,
        );
        final downloader = ref.read(piperTtsDownloaderProvider);
        final downloadedVariants = await downloader.getDownloadedVariants();
        final variant = downloadedVariants.contains(requestedVariant)
            ? requestedVariant
            : downloadedVariants.isNotEmpty
            ? downloadedVariants.first
            : requestedVariant;
        final mPath = await downloader.getModelPath(variant);
        final tPath = await downloader.getTokensPath(variant);
        final dDir = await downloader.getDataDir(variant);
        if (mPath == null || tPath == null) {
          throw StateError(
            'Piper voice files not found for ${variant.displayName}. Please download them in the Model Manager.',
          );
        }
        modelPath = mPath;
        tokensPath = tPath;
        dataDir = dDir.path;
        break;
      default:
        return;
    }

    if (_currentEngine == engineId &&
        !_isWorkerInitializing &&
        _currentModelPath == modelPath &&
        _currentVoicesPath == voicesPath &&
        _currentTokensPath == tokensPath &&
        _currentDataDir == dataDir &&
        _currentLexicon == lexicon) {
      return;
    }

    _isWorkerInitializing = true;

    try {
      _initCompleter = Completer<void>();
      _workerSendPort!.send(
        TtsInitRequest(
          engineId: engineId,
          modelPath: modelPath,
          voicesPath: voicesPath,
          tokensPath: tokensPath,
          dataDir: dataDir,
          lexicon: lexicon,
        ),
      );

      await _initCompleter!.future.timeout(
        const Duration(seconds: 30),
      );
      _currentEngine = engineId;
      _currentModelPath = modelPath;
      _currentVoicesPath = voicesPath;
      _currentTokensPath = tokensPath;
      _currentDataDir = dataDir;
      _currentLexicon = lexicon;
    } finally {
      _isWorkerInitializing = false;
    }
  }

  Future<void> speak(
    String text, {
    EngineId? engineId,
    String? voiceId,
    bool isPreview = false,
    String? messageId,
    String? conversationId,
  }) async {
    if (text.trim().isEmpty) return;

    final settings = ref.read(settingsProvider);
    if (settings.ttsProcessMarkdown) {
      text = TtsTextProcessor.process(text, stripMarkdown: true);
      if (text.trim().isEmpty) return;
    }

    engineId ??= settings.ttsEngine;
    final resolvedEngine = engineId;

    final availableVoices = voicesForEngine(resolvedEngine);
    final resolvedVoiceId =
        voiceId ??
        settings.ttsVoiceId ??
        (availableVoices.isNotEmpty ? availableVoices.first.id : null);

    Future<bool> tryPlayCached() async {
      if (isPreview ||
          messageId == null ||
          _messageAudioCache == null ||
          _messageAudioCache!.messageId != messageId ||
          _messageAudioCache!.text != text ||
          _messageAudioCache!.engine != resolvedEngine ||
          _messageAudioCache!.voice != resolvedVoiceId) {
        return false;
      }
      await _playFromCache(
        isPreview: isPreview,
        messageId: messageId,
        conversationId: conversationId,
        engineId: resolvedEngine,
        text: text,
      );
      return true;
    }

    if (await tryPlayCached()) return;

    _isStopping = false;
    if (state.isSpeaking) {
      await stop();
      await Future.delayed(const Duration(milliseconds: 100));
      _isStopping = false;
    }

    if (await tryPlayCached()) return;

    if (resolvedEngine == EngineId.system) {
      _flutterTts ??= FlutterTts();
      _resetSystemSeekState();
      final speakGeneration = ++_systemSpeakGeneration;
      _systemFullText = text;
      _systemSkippedOffset = Duration.zero;
      _systemSpeakStart = DateTime.now();
      state = state.copyWith(
        isSpeaking: true,
        isPaused: false,
        isInitializing: false,
        error: null,
        activeEngine: EngineId.system,
        playingContent: text,
        playingMessageId: isPreview ? null : messageId,
        playingConversationId: isPreview ? null : conversationId,
        isPreview: isPreview,
        canSeek: false,
        resetProgress: true,
      );
      try {
        await _flutterTts!.setLanguage('en-US');
        await _applySystemSpeechRate();
        _flutterTts!.setCompletionHandler(() {
          if (_isStopping || speakGeneration != _systemSpeakGeneration) return;
          _resetSystemSeekState();
          state = state.copyWith(
            isSpeaking: false,
            isPaused: false,
            playingContent: null,
            clearPlayingTarget: true,
            resetProgress: true,
            canSeek: false,
          );
        });
        _flutterTts!.setErrorHandler((msg) {
          if (_isStopping || speakGeneration != _systemSpeakGeneration) return;
          _resetSystemSeekState();
          state = state.copyWith(
            isSpeaking: false,
            isPaused: false,
            playingContent: null,
            error: msg.toString(),
            clearPlayingTarget: true,
            resetProgress: true,
            canSeek: false,
          );
        });
        _flutterTts!.setCancelHandler(() {
          if (_isStopping || speakGeneration != _systemSpeakGeneration) return;
        });
        await _flutterTts!.awaitSpeakCompletion(true);
        await _flutterTts!.speak(text);
      } catch (e) {
        _resetSystemSeekState();
        state = state.copyWith(
          isSpeaking: false,
          isPaused: false,
          error: 'System TTS unavailable',
          playingContent: null,
          clearPlayingTarget: true,
          resetProgress: true,
          canSeek: false,
        );
        rethrow;
      }
      return;
    }

    _resetProgress();
    _chunks = _splitText(text);
    _currentChunkIndex = 0;
    _currentVoice = resolvedVoiceId;
    _synthesizedChunks.clear();
    _lastEnqueuedChunk = -1;
    _currentSessionId++;
    _playbackSessionId = _currentSessionId;

    _isPreview = isPreview;
    _playlistBuffer.clear();
    _nextPlaylistIndexToAdd = 0;
    await _player.clearAudioSources();

    try {
      AudioSession.instance.then((session) {
        session.configure(const AudioSessionConfiguration.speech());
      });
    } catch (e) {
      Log.error('Error configuring audio session: $e');
    }

    state = state.copyWith(
      isSpeaking: true,
      isPaused: false,
      isInitializing: true,
      error: null,
      activeEngine: engineId,
      playingContent: text,
      playingMessageId: isPreview ? null : messageId,
      playingConversationId: isPreview ? null : conversationId,
      isPreview: isPreview,
    );

    try {
      await _initEngine(resolvedEngine, voiceId: resolvedVoiceId);
      await _player.setSpeed(state.playbackSpeed);
      state = state.copyWith(
        isInitializing: false,
        canSeek: false,
        duration: _estimatedTotalDuration(),
      );
      _enqueueNextChunks();
    } catch (e, st) {
      if (_isPlayerDisposed) return;
      Log.error('TTS speak error: $e\n$st');
      state = state.copyWith(
        isSpeaking: false,
        isInitializing: false,
        error: e.toString(),
        playingContent: null,
        clearPlayingTarget: true,
      );
    }
  }

  Future<void> _addChunkToPlaylist(int chunkIndex, Uint8List wavBytes) async {
    if (_isStopping || chunkIndex >= _chunks.length) return;

    final tempDir = Directory.systemTemp;
    final tempFile = File(
      '${tempDir.path}/tts_chunk_${_currentSessionId}_$chunkIndex.wav',
    );
    await tempFile.writeAsBytes(wavBytes);

    final source = AudioSource.file(
      tempFile.path,
      tag: _isPreview ? null : MediaItem(
        id: 'tts_chunk_${_currentSessionId}_$chunkIndex',
        album: 'LocalMind TTS',
        title: _chunks[chunkIndex],
        artist: _currentEngine == EngineId.kitten ? 'Kitten TTS' : 'Piper TTS',
      ),
    );

    _playlistBuffer[chunkIndex] = source;
    while (_playlistBuffer.containsKey(_nextPlaylistIndexToAdd)) {
      final indexBeingAdded = _nextPlaylistIndexToAdd;
      final src = _playlistBuffer.remove(indexBeingAdded)!;
      await _player.addAudioSource(src);

      if (indexBeingAdded == 0 && !state.isPaused) {
        await _player.setSpeed(state.playbackSpeed);
        _player.play();
      }

      _nextPlaylistIndexToAdd++;

      if (_nextPlaylistIndexToAdd >= _chunks.length) {
        state = state.copyWith(isInitializing: false, canSeek: true);
        _saveMessageAudioCache();
      } else {
        state = state.copyWith(isInitializing: false);
      }
    }
  }

  void _enqueueChunk(int chunkIndex) {
    if (_workerSendPort == null || _currentEngine == null) return;
    if (chunkIndex >= _chunks.length) return;

    final settings = ref.read(settingsProvider);
    final availableVoices = voicesForEngine(_currentEngine!);
    final voiceId =
        _currentVoice ??
        settings.ttsVoiceId ??
        (availableVoices.isNotEmpty ? availableVoices.first.id : null);

    while (_lastEnqueuedChunk < chunkIndex) {
      _lastEnqueuedChunk++;
      final index = _lastEnqueuedChunk;
      Log.debug('Enqueuing synthesis for chunk $index');
      _workerSendPort!.send(
        TtsSynthesizeRequest(
          text: _chunks[index],
          voiceId: voiceId ?? '',
          speed: settings.ttsSpeed,
          chunkIndex: index,
          sessionId: _currentSessionId,
        ),
      );
    }
  }

  Future<void> _ensurePlaylistThrough(int targetIndex) async {
    if (targetIndex < 0 || targetIndex >= _chunks.length) return;
    _enqueueChunk(targetIndex);

    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (_nextPlaylistIndexToAdd <= targetIndex &&
        DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (_lastEnqueuedChunk < targetIndex) {
        _enqueueChunk(targetIndex);
      }
    }
  }

  int _chunkIndexForPosition(Duration target) {
    var accumulated = Duration.zero;
    for (var i = 0; i < _chunks.length; i++) {
      final chunkDuration = _chunkDurations[i] ?? _averageChunkDuration();
      if (accumulated + chunkDuration > target) return i;
      accumulated += chunkDuration;
    }
    return _chunks.isEmpty ? 0 : _chunks.length - 1;
  }

  Future<void> seekTo(Duration target) async {
    if (!state.isSpeaking ||
        state.isPreview ||
        state.activeEngine == EngineId.system) {
      return;
    }

    state = state.copyWith(isSeekPending: true);
    try {
      final maxDuration = _estimatedTotalDuration();
      if (maxDuration <= Duration.zero) return;

      var clamped = target;
      if (clamped.isNegative) clamped = Duration.zero;
      if (clamped > maxDuration) clamped = maxDuration;

      final targetChunk = _chunkIndexForPosition(clamped);
      await _ensurePlaylistThrough(targetChunk);

      var chunkStart = Duration.zero;
      for (var i = 0; i < targetChunk; i++) {
        chunkStart += _chunkDurations[i] ?? _averageChunkDuration();
      }
      final localPosition = clamped - chunkStart;

      if (_player.currentIndex != targetChunk) {
        await _player.seek(Duration.zero, index: targetChunk);
      }
      if (localPosition > Duration.zero) {
        await _player.seek(localPosition);
      } else {
        await _player.seek(Duration.zero);
      }
      _currentChunkIndex = targetChunk;
      _updateChunkOffset();
      _updatePlaybackProgress();
    } finally {
      state = state.copyWith(isSeekPending: false);
    }
  }

  Future<void> skipForward() async {
    if (state.activeEngine == EngineId.system) return;
    if (!state.isSpeaking && !state.isPaused) return;
    final skip = Duration(
      seconds: ref.read(settingsProvider).ttsSkipSeconds,
    );
    await seekTo(_computeGlobalPosition() + skip);
  }

  Future<void> skipBackward() async {
    if (state.activeEngine == EngineId.system) return;
    if (!state.isSpeaking && !state.isPaused) return;
    final skip = Duration(
      seconds: ref.read(settingsProvider).ttsSkipSeconds,
    );
    await seekTo(_computeGlobalPosition() - skip);
  }

  void _enqueueNextChunks() {
    if (_workerSendPort == null || _currentEngine == null) return;

    final settings = ref.read(settingsProvider);
    final availableVoices = voicesForEngine(_currentEngine!);
    final voiceId =
        _currentVoice ??
        settings.ttsVoiceId ??
        (availableVoices.isNotEmpty ? availableVoices.first.id : null);

    while (_lastEnqueuedChunk < _chunks.length - 1 &&
        _lastEnqueuedChunk < _currentChunkIndex + _lookAheadCount) {
      _lastEnqueuedChunk++;
      final chunkIndex = _lastEnqueuedChunk;
      final text = _chunks[chunkIndex];

      Log.debug('Enqueuing synthesis for chunk $chunkIndex');
      _workerSendPort!.send(
        TtsSynthesizeRequest(
          text: text,
          voiceId: voiceId ?? '',
          speed: settings.ttsSpeed,
          chunkIndex: chunkIndex,
          sessionId: _currentSessionId,
        ),
      );
    }
  }

  void pause() {
    if (state.isPaused || !state.isSpeaking) return;
    if (state.activeEngine == EngineId.system) {
      _flutterTts?.pause();
    } else {
      _player.pause();
    }
    state = state.copyWith(isPaused: true);
  }

  void resume() {
    if (!state.isPaused) return;
    if (state.activeEngine == EngineId.system) {
      unawaited(_flutterTts?.speak(_systemFullText ?? state.playingContent ?? ''));
    } else {
      _player.play();
    }
    state = state.copyWith(isPaused: false);
  }

  void togglePauseResume() {
    if (state.isPaused) {
      resume();
    } else if (state.isSpeaking) {
      pause();
    }
  }

  Future<void> stop() async {
    _isStopping = true;
    _systemSpeakGeneration++;
    if (_isPlayerDisposed) {
      _isStopping = false;
      return;
    }
    try {
      await _player.stop();
      await _player.clearAudioSources();
    } catch (_) {}
    await _flutterTts?.stop();
    _cleanupSessionFiles(_currentSessionId, _chunks.length);
    _resetProgress();
    state = state.copyWith(
      isSpeaking: false,
      isPaused: false,
      isInitializing: false,
      playingContent: null,
      isPreview: false,
      clearPlayingTarget: true,
      resetProgress: true,
      canSeek: false,
    );
    _isStopping = false;
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (!playbackSpeedOptions.contains(speed)) return;
    state = state.copyWith(playbackSpeed: speed);
    if (state.activeEngine == EngineId.system) {
      await _applySystemSpeechRate();
      return;
    }
    if (!state.isSpeaking && !state.isPaused) return;
    try {
      await _player.setSpeed(speed);
    } catch (e) {
      Log.error('Failed to set playback speed: $e');
    }
  }

  void cyclePlaybackSpeed() {
    final options = playbackSpeedOptions;
    final currentIndex = options.indexOf(state.playbackSpeed);
    final nextIndex = currentIndex < 0 ? 2 : (currentIndex + 1) % options.length;
    unawaited(setPlaybackSpeed(options[nextIndex]));
  }

  Future<void> _applySystemSpeechRate() async {
    if (_flutterTts == null) return;
    final settings = ref.read(settingsProvider);
    await _flutterTts!.setSpeechRate(
      (settings.ttsSpeed * state.playbackSpeed * 0.5).clamp(0.0, 1.0),
    );
  }

  Future<void> _playFromCache({
    required bool isPreview,
    required String messageId,
    required String? conversationId,
    required EngineId engineId,
    required String text,
  }) async {
    final cache = _messageAudioCache!;
    _resetProgress();
    _chunks = List<String>.from(cache.chunks);
    _currentChunkIndex = 0;
    _currentVoice = cache.voice;
    _synthesizedChunks.clear();
    _synthesizedChunks.addAll(cache.synthesizedChunks);
    _chunkDurations.clear();
    _chunkDurations.addAll(cache.chunkDurations);
    _totalDuration = Duration.zero;
    for (final duration in _chunkDurations.values) {
      _totalDuration += duration;
    }
    _lastEnqueuedChunk = _chunks.length - 1;
    _currentSessionId++;
    _playbackSessionId = _currentSessionId;
    _isPreview = isPreview;
    _playlistBuffer.clear();
    _nextPlaylistIndexToAdd = 0;
    await _player.clearAudioSources();

    state = state.copyWith(
      isSpeaking: true,
      isPaused: false,
      isInitializing: true,
      error: null,
      activeEngine: engineId,
      playingContent: text,
      playingMessageId: messageId,
      playingConversationId: conversationId,
      isPreview: isPreview,
      duration: _totalDuration,
    );

    for (var i = 0; i < _chunks.length; i++) {
      final bytes = _synthesizedChunks[i];
      if (bytes != null && bytes.isNotEmpty) {
        await _addChunkToPlaylist(i, bytes);
      }
    }

    state = state.copyWith(
      isInitializing: false,
      canSeek: true,
    );
    if (!state.isPaused) {
      await _player.play();
    }
  }

  void _saveMessageAudioCache() {
    final messageId = state.playingMessageId;
    final text = state.playingContent;
    if (state.isPreview || messageId == null || text == null) return;
    if (_chunks.isEmpty) return;

    final settings = ref.read(settingsProvider);
    final availableVoices = voicesForEngine(
      state.activeEngine ?? _currentEngine ?? EngineId.kitten,
    );
    final resolvedVoice =
        _currentVoice ??
        settings.ttsVoiceId ??
        (availableVoices.isNotEmpty ? availableVoices.first.id : null);

    for (var i = 0; i < _chunks.length; i++) {
      final bytes = _synthesizedChunks[i];
      if (bytes == null || bytes.isEmpty) return;
    }

    _messageAudioCache = _MessageAudioCache(
      messageId: messageId,
      text: text,
      engine: state.activeEngine ?? _currentEngine ?? EngineId.kitten,
      voice: resolvedVoice,
      chunks: List<String>.from(_chunks),
      synthesizedChunks: Map<int, Uint8List>.from(_synthesizedChunks),
      chunkDurations: Map<int, Duration>.from(_chunkDurations),
    );
  }

  Future<bool> downloadCurrentAudio() async {
    if (state.activeEngine == EngineId.system || state.isPreview) {
      return false;
    }
    if (!state.isSpeaking && !state.isPaused) return false;

    final wavFiles = <Uint8List>[];
    for (var i = 0; i < _chunks.length; i++) {
      final cached = _synthesizedChunks[i];
      if (cached != null && cached.isNotEmpty) {
        wavFiles.add(cached);
        continue;
      }
      final tempFile = File(
        '${Directory.systemTemp.path}/tts_chunk_${_currentSessionId}_$i.wav',
      );
      if (tempFile.existsSync()) {
        wavFiles.add(await tempFile.readAsBytes());
      }
    }

    if (wavFiles.isEmpty) return false;

    final merged = mergeWavFiles(wavFiles);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Save TTS audio',
      fileName: 'localmind_tts_$timestamp.wav',
      type: FileType.custom,
      allowedExtensions: const ['wav'],
      bytes: merged,
    );
    return saved != null;
  }

  Future<void> previewVoice(Voice voice) async {
    await speak(ttsPreviewSample, engineId: voice.engine, voiceId: voice.id, isPreview: true);
  }
}

const ttsPreviewSample = "Hello, this is a preview of the selected voice";

class _MessageAudioCache {
  const _MessageAudioCache({
    required this.messageId,
    required this.text,
    required this.engine,
    required this.voice,
    required this.chunks,
    required this.synthesizedChunks,
    required this.chunkDurations,
  });

  final String messageId;
  final String text;
  final EngineId engine;
  final String? voice;
  final List<String> chunks;
  final Map<int, Uint8List> synthesizedChunks;
  final Map<int, Duration> chunkDurations;
}
