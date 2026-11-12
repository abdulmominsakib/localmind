import 'dart:typed_data';

import '../../core/models/model_source.dart';

/// LiteRT-LM ASR model families whose runtime metadata is versioned by the
/// native bridge.
enum LiteRtLmAsrModelPreset {
  /// NVIDIA Parakeet TDT 0.6B v3.
  parakeetTdt0_6bV3,

  /// NVIDIA Parakeet CTC 0.6B.
  parakeetCtc0_6b,

  /// Useful Sensors Moonshine Tiny.
  moonshineTiny,

  /// OpenAI Whisper Tiny.
  whisperTiny,

  /// Qwen3-ASR 0.6B.
  qwen3Asr0_6b,
}

/// LiteRT accelerator used for a dedicated ASR model.
///
/// Dedicated ASR is CPU-only in the currently validated runtime. GPU
/// and NPU values can be added after their model/runtime combinations pass the
/// same real-model correctness gates.
enum LiteRtLmAsrBackend {
  /// XNNPACK CPU execution.
  cpu,
}

/// Configuration for a dedicated LiteRT-LM ASR session.
class LiteRtLmAsrRuntimeConfig {
  final String? _modelPath;
  final String? _tokenizerPath;

  /// The `.tflite` speech-recognition model, or from native `v0.18.0-3` a
  /// dedicated ASR `.litertlm` container such as Whisper tiny: a local path,
  /// an HTTP(S) URL or a Hugging Face file.
  ///
  /// A container uses its embedded tokenizer, but [tokenizer] is still
  /// required. Flutter Apple apps run the `llamadart_litert_lm_flutter`
  /// runtime, so a companion pinning an earlier release rejects containers.
  ///
  /// The runtime opens local files only. `SpeechToTextEngine.load` with a
  /// `LiteRtLmAsrAdapter` downloads remote files into the model cache and
  /// builds this configuration from them. Null for a configuration made
  /// with the deprecated path constructor.
  final ModelSource? model;

  /// The tokenizer JSON matching [model], from the same kinds of source.
  ///
  /// Null for a configuration made with the deprecated path constructor.
  final ModelSource? tokenizer;

  /// Model-family metadata preset.
  final LiteRtLmAsrModelPreset modelPreset;

  /// Requested accelerator.
  final LiteRtLmAsrBackend backend;

  /// Native CPU worker count. Must fit a positive signed 32-bit integer.
  final int numberOfThreads;

  /// Maximum queued audio before native push backpressure is reported.
  ///
  /// This must fit a signed 32-bit millisecond value and be at least one
  /// inference window for [modelPreset].
  final Duration maxBufferedAudio;

  /// Fraction of each inference window retained for transcript reconciliation.
  final double overlapRatio;

  /// Creates a LiteRT-LM ASR runtime configuration from local file paths.
  @Deprecated(
    'Use LiteRtLmAsrRuntimeConfig.source with ModelSource.path(path); load '
    'remote files with SpeechToTextEngine.load and a LiteRtLmAsrAdapter. '
    'This constructor will be removed in a future release.',
  )
  const LiteRtLmAsrRuntimeConfig({
    required String modelPath,
    required String tokenizerPath,
    required this.modelPreset,
    this.backend = LiteRtLmAsrBackend.cpu,
    this.numberOfThreads = 4,
    this.maxBufferedAudio = const Duration(seconds: 30),
    this.overlapRatio = 0.4,
  }) : _modelPath = modelPath,
       _tokenizerPath = tokenizerPath,
       model = null,
       tokenizer = null;

  /// Creates a LiteRT-LM ASR runtime configuration for the [model] and
  /// [tokenizer] files.
  const LiteRtLmAsrRuntimeConfig.source({
    required ModelSource this.model,
    required ModelSource this.tokenizer,
    required this.modelPreset,
    this.backend = LiteRtLmAsrBackend.cpu,
    this.numberOfThreads = 4,
    this.maxBufferedAudio = const Duration(seconds: 30),
    this.overlapRatio = 0.4,
  }) : _modelPath = null,
       _tokenizerPath = null;

  /// The model file that the runtime opens: the path given to the deprecated
  /// constructor, the path of a local [model], or the URL of a remote one.
  ///
  /// The runtime opens local files only and rejects a remote [model]; load
  /// remote files with `SpeechToTextEngine.load`.
  String get modelPath => _modelPath ?? _location(model!);

  /// The tokenizer file that the runtime opens, as [modelPath] describes.
  String get tokenizerPath => _tokenizerPath ?? _location(tokenizer!);

  static String _location(ModelSource source) =>
      source.path ?? source.url.toString();
}

/// Result of pushing PCM into a bounded native ASR session.
class LiteRtLmAsrPushResult {
  /// Number of samples accepted from the beginning of the supplied buffer.
  final int acceptedSamples;

  /// Whether the unaccepted suffix must be retried after processing a window.
  final bool wouldBlock;

  /// Creates a push result.
  const LiteRtLmAsrPushResult({
    required this.acceptedSamples,
    required this.wouldBlock,
  });
}

/// Native ASR processing state.
enum LiteRtLmAsrProcessState {
  /// A transcript update is available.
  update,

  /// More PCM must be pushed before another inference window can run.
  needsMoreAudio,

  /// The final result was already returned.
  endOfStream,
}

/// One native ASR processing result.
class LiteRtLmAsrProcessResult {
  /// Flow-control state.
  final LiteRtLmAsrProcessState state;

  /// Newly confirmed text that will not be revised by later windows.
  final String confirmedText;

  /// Current tentative text that may be replaced by the next update.
  final String unconfirmedText;

  /// Whether this update completes the input stream.
  final bool isFinal;

  /// Creates a processing result.
  const LiteRtLmAsrProcessResult({
    required this.state,
    this.confirmedText = '',
    this.unconfirmedText = '',
    this.isFinal = false,
  });
}

/// Synchronous low-level session implemented by the native runtime.
///
/// Calls that run inference may block and should be owned by a worker isolate.
abstract interface class LiteRtLmAsrRuntimeSession {
  /// Pushes mono 16 kHz float PCM into the bounded native queue.
  LiteRtLmAsrPushResult pushAudio(Float32List samples);

  /// Marks the input complete so a partial final window can be processed.
  void finishAudio();

  /// Runs at most one inference window.
  LiteRtLmAsrProcessResult processNext();

  /// Requests cancellation between native inference windows.
  void cancel();

  /// Resets transcript and audio state for a new stream.
  void reset();

  /// Releases native session resources.
  void dispose();
}
