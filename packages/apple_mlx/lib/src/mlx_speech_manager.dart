import 'dart:async';
import 'package:mlx_audio/mlx_audio.dart' as mlx_native;
import 'package:speech_mlx/speech_mlx.dart';
import 'mlx_models.dart';

/// Manager for orchestrating MLX Audio STT, TTS, and Turn Completion.
class AppleMlxSpeechManager {
  final AppleMlxConfig config;
  MlxSpeechProvider? _provider;
  MlxSmartTurnScorer? _turnScorer;
  bool _isInitialized = false;

  AppleMlxSpeechManager({this.config = const AppleMlxConfig()});

  bool get isInitialized => _isInitialized;

  /// Initializes the provider with configured STT and TTS isolate workers.
  Future<void> initialize() async {
    if (_isInitialized) return;

    final sttWorker = config.sttModelId != null
        ? MlxIsolateBatchWorker(modelPath: config.sttModelId!)
        : null;

    final ttsWorker = config.ttsModelId != null
        ? MlxIsolateTtsWorker(modelPath: config.ttsModelId!)
        : null;

    _provider = MlxSpeechProvider(
      worker: sttWorker,
      modelId: config.sttModelId ?? 'default',
      ttsWorker: ttsWorker,
      ttsModelId: config.ttsModelId ?? 'pocket-tts',
      voiceIds: AppleMlxModelIds.defaultVoices,
    );

    _isInitialized = true;
  }

  /// Transcribes a WAV audio file directly using MLX Audio.
  Future<String> transcribeWavFile(String wavFilePath) async {
    final audio = await mlx_native.loadAudioMono16k(wavFilePath);
    final modelId = config.sttModelId ?? AppleMlxModelIds.parakeetTdt06b;
    final stt = await mlx_native.STT.loadModel(modelId);
    try {
      final output = stt.generate(audio);
      return output.text;
    } finally {
      stt.close();
    }
  }

  /// Synthesizes text to a WAV audio file using PocketTTS on MLX.
  Future<mlx_native.TtsOutput> synthesizeToWav({
    required String text,
    required String outputPath,
    String? voice,
    void Function(mlx_native.TtsAudioChunk chunk)? onAudioChunk,
  }) async {
    final modelId = config.ttsModelId ?? AppleMlxModelIds.pocketTts;
    final tts = await mlx_native.TTS.loadModel(modelId);
    try {
      final selectedVoice = voice ?? config.defaultVoice;
      final out = tts.generate(
        text,
        voice: selectedVoice,
        onAudioChunk: (chunk) {
          onAudioChunk?.call(chunk);
        },
      );
      mlx_native.writeWavFloat32(outputPath, out.samples, out.sampleRate);
      return out;
    } finally {
      tts.close();
    }
  }

  /// Initializes SmartTurn endpoint / turn-completion detector.
  Future<void> initializeTurnScorer({String? modelDirectory}) async {
    if (_turnScorer != null) return;
    _turnScorer = MlxSmartTurnScorer(
      worker: MlxIsolateTurnWorker(modelDirectory: modelDirectory),
    );
  }

  /// Evaluates whether user speech is complete using SmartTurn classifier.
  Future<mlx_native.SmartTurnEndpointOutput> scoreTurn(
    String pauseWavPath,
  ) async {
    final turn = await mlx_native.SmartTurn.load();
    try {
      final window = await mlx_native.loadAudioMono16k(pauseWavPath);
      return turn.predictEndpoint(window);
    } finally {
      turn.close();
    }
  }

  /// Disposes and cleans up MLX workers and isolates.
  Future<void> dispose() async {
    await _provider?.close();
    await _turnScorer?.close();
    _provider = null;
    _turnScorer = null;
    _isInitialized = false;
  }
}
