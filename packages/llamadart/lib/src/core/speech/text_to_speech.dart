import 'dart:async';
import 'dart:typed_data';

import '../../backends/backend.dart';
import '../engine/engine.dart';
import '../engine/engine_capabilities.dart';
import '../engine/llamadart_engine.dart';
import '../exceptions.dart';
import '../models/download/model_download_manager.dart';
import '../models/inference/model_params.dart';
import '../models/model_file_store.dart';
import '../models/model_load_options.dart';
import '../models/model_source.dart';
import 'speech_engine_lease.dart';
import 'speech_to_text.dart';
import 'text_to_speech_model.dart';
import 'text_to_speech_platform_stub.dart'
    if (dart.library.js_interop) 'text_to_speech_platform_web.dart';

/// Model-specific adapter selected by [TextToSpeechEngine].
@Deprecated(
  'Use a TextToSpeechAdapter such as Qwen3TtsAdapter. This enum will be '
  'removed in a future release.',
)
enum TextToSpeechModelProfile {
  /// Qwen3-TTS with its matching llama.cpp audio-generation projector.
  qwen3Tts,
}

/// How the active backend implements text-to-speech.
enum TextToSpeechImplementation {
  /// No usable synthesis path is available.
  unavailable,

  /// Dedicated native audio generation through llama.cpp mtmd.
  nativeAudioGeneration,

  /// Complete audio generation through the WebGPU bridge.
  webAudioGeneration,
}

/// A request to synthesize one complete utterance.
class TextToSpeechRequest {
  /// Text to synthesize.
  final String text;

  /// Optional language name or code accepted by the loaded model.
  ///
  /// The adapter maps it to a code the model takes, see
  /// [TextToSpeechAdapter.normalizeLanguage]. [Qwen3TtsAdapter] accepts the
  /// two-letter codes reported by [TextToSpeechCapabilities.supportedLanguages]
  /// and their English names, such as `English` for `en` and `Korean` for
  /// `ko`.
  final String? language;

  /// Optional encoded speaker-reference audio.
  ///
  /// Native backends accept files and bytes. Web accepts encoded bytes only.
  /// It cannot be combined with [voice].
  final SpeechAudioInput? speakerReference;

  /// Optional predefined voice of the loaded model, such as `male` for
  /// LFM3-Audio, or null for the model's default voice.
  ///
  /// Needs [TextToSpeechCapabilities.supportsVoice]. A name matches in any
  /// case; one the model does not list throws [LlamaTextToSpeechException]
  /// instead of falling back to the default. It cannot be combined with
  /// [speakerReference].
  final String? voice;

  /// Maximum number of audio-codec frames to generate.
  final int maxFrames;

  /// Prompt evaluation batch size.
  final int promptBatchSize;

  /// Top-k sampling cutoff.
  final int topK;

  /// Top-p sampling cutoff.
  final double topP;

  /// Minimum probability sampling cutoff.
  final double minP;

  /// Sampling temperature.
  ///
  /// Some models sample with their own settings and only validate [topK],
  /// [topP], [minP] and this value; see their adapter.
  final double temperature;

  /// Random seed. `0xffffffff` requests the runtime's random default.
  final int seed;

  /// Creates a text-to-speech request using Qwen3-TTS defaults.
  const TextToSpeechRequest({
    required this.text,
    this.language,
    this.speakerReference,
    this.voice,
    this.maxFrames = 512,
    this.promptBatchSize = 512,
    this.topK = 40,
    this.topP = 0.95,
    this.minP = 0,
    this.temperature = 0.8,
    this.seed = 0xffffffff,
  });
}

/// Runtime text-to-speech capabilities for the loaded engine.
class TextToSpeechCapabilities implements EngineCapabilities {
  /// Whether [TextToSpeechEngine.synthesize] can be used now.
  @override
  final bool isSupported;

  /// Actionable reason when [isSupported] is false.
  @override
  final String? unsupportedReason;

  /// Active runtime backend label.
  @override
  final String? backendName;

  /// Backend implementation used for synthesis.
  final TextToSpeechImplementation implementation;

  /// Output sample rate in Hertz.
  final int? sampleRateHz;

  /// Number of interleaved output channels.
  final int? channelCount;

  /// Speaker-reference representations accepted by this runtime.
  final Set<SpeechAudioInputKind> speakerReferenceInputKinds;

  /// Whether a language can be supplied with the request.
  final bool supportsLanguage;

  /// Canonical language codes accepted by the adapter, see
  /// [TextToSpeechAdapter.supportedLanguages].
  final Set<String> supportedLanguages;

  /// Whether speaker-reference audio can be supplied.
  final bool supportsSpeakerReference;

  /// Whether [TextToSpeechRequest.voice] can name a predefined voice.
  final bool supportsVoice;

  /// The model's predefined voices in its own order; the first one speaks
  /// when a request names none.
  ///
  /// Empty when the model has no voices, or when [supportsVoice] is true but
  /// the runtime cannot list them (llamadart-native before v0.9.0); the
  /// runtime then checks the name when synthesis starts.
  final List<String> voices;

  /// Whether PCM can be emitted while synthesis is still running.
  final bool supportsIncrementalAudio;

  /// Whether an active task can be cancelled cooperatively.
  final bool supportsCancellation;

  /// Whether pausing the event subscription throttles synthesis.
  final bool supportsOutputBackpressure;

  /// Maximum number of typed speech tasks per underlying engine.
  final int maxConcurrentTasks;

  /// Creates a capability snapshot.
  const TextToSpeechCapabilities({
    required this.isSupported,
    this.unsupportedReason,
    this.backendName,
    this.implementation = TextToSpeechImplementation.unavailable,
    this.sampleRateHz,
    this.channelCount,
    this.speakerReferenceInputKinds = const <SpeechAudioInputKind>{},
    this.supportsLanguage = false,
    this.supportedLanguages = const <String>{},
    this.supportsSpeakerReference = false,
    this.supportsVoice = false,
    this.voices = const <String>[],
    this.supportsIncrementalAudio = false,
    this.supportsCancellation = false,
    this.supportsOutputBackpressure = false,
    this.maxConcurrentTasks = 0,
  });
}

/// Complete synthesized PCM audio.
class TextToSpeechResult {
  /// Interleaved normalized float32 PCM samples.
  final Float32List samples;

  /// Output sample rate in Hertz.
  final int sampleRateHz;

  /// Number of interleaved output channels.
  final int channelCount;

  /// Number of audio-codec frames generated by the model.
  final int framesGenerated;

  /// Whether generation reached [TextToSpeechRequest.maxFrames].
  final bool truncated;

  /// Creates a final synthesis result.
  const TextToSpeechResult({
    required this.samples,
    required this.sampleRateHz,
    required this.channelCount,
    required this.framesGenerated,
    required this.truncated,
  });

  /// Duration derived from the PCM metadata.
  Duration get duration {
    if (sampleRateHz <= 0 || channelCount <= 0) {
      return Duration.zero;
    }
    final frames = samples.length / channelCount;
    return Duration(
      microseconds: (frames * Duration.microsecondsPerSecond / sampleRateHz)
          .round(),
    );
  }

  /// Encodes the float PCM as a conventional signed 16-bit WAV file.
  Uint8List toWavBytes() {
    if (sampleRateHz <= 0 || channelCount <= 0) {
      throw LlamaTextToSpeechException(
        'Cannot encode WAV with invalid output audio metadata.',
      );
    }
    const bytesPerSample = 2;
    final dataLength = samples.length * bytesPerSample;
    final bytes = Uint8List(44 + dataLength);
    final data = ByteData.sublistView(bytes);

    void writeAscii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        data.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    writeAscii(0, 'RIFF');
    data.setUint32(4, 36 + dataLength, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, channelCount, Endian.little);
    data.setUint32(24, sampleRateHz, Endian.little);
    data.setUint32(
      28,
      sampleRateHz * channelCount * bytesPerSample,
      Endian.little,
    );
    data.setUint16(32, channelCount * bytesPerSample, Endian.little);
    data.setUint16(34, bytesPerSample * 8, Endian.little);
    writeAscii(36, 'data');
    data.setUint32(40, dataLength, Endian.little);

    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index].clamp(-1.0, 1.0);
      final pcm = sample < 0
          ? (sample * 32768).round()
          : (sample * 32767).round();
      data.setInt16(44 + index * bytesPerSample, pcm, Endian.little);
    }
    return bytes;
  }
}

/// Current stage of a synthesis task.
enum TextToSpeechProgressPhase {
  /// The model is processing text and optional reference audio.
  processingPrompt,

  /// The model is generating audio-codec frames.
  generating,
}

/// Base class for synthesis events.
sealed class TextToSpeechEvent {
  /// Creates a synthesis event.
  const TextToSpeechEvent();
}

/// Progress emitted before the final PCM becomes available.
class TextToSpeechProgressEvent extends TextToSpeechEvent {
  /// Current synthesis phase.
  final TextToSpeechProgressPhase phase;

  /// Prompt tokens that have not yet been evaluated.
  final int promptTokensRemaining;

  /// Audio-codec frames generated so far.
  final int framesGenerated;

  /// Whether the configured frame limit was reached.
  final bool truncated;

  /// Creates a progress event.
  const TextToSpeechProgressEvent({
    required this.phase,
    required this.promptTokensRemaining,
    required this.framesGenerated,
    required this.truncated,
  });
}

/// Final PCM event emitted after generation completes.
class TextToSpeechFinalEvent extends TextToSpeechEvent {
  /// Complete synthesis result.
  final TextToSpeechResult result;

  /// Creates a final audio event.
  const TextToSpeechFinalEvent(this.result);
}

/// Terminal state of a synthesis task.
enum TextToSpeechCompletionState {
  /// Synthesis produced PCM output.
  completed,

  /// Synthesis was cancelled.
  cancelled,

  /// Synthesis failed.
  failed,
}

/// Terminal details for a synthesis task.
class TextToSpeechCompletion {
  /// Terminal state.
  final TextToSpeechCompletionState state;

  /// Final output when [state] is [TextToSpeechCompletionState.completed].
  final TextToSpeechResult? result;

  /// Failure when [state] is [TextToSpeechCompletionState.failed].
  final LlamaException? error;

  const TextToSpeechCompletion._({
    required this.state,
    this.result,
    this.error,
  });

  /// Creates a successful completion.
  factory TextToSpeechCompletion.completed(TextToSpeechResult result) =>
      TextToSpeechCompletion._(
        state: TextToSpeechCompletionState.completed,
        result: result,
      );

  /// Creates a cancelled completion.
  const factory TextToSpeechCompletion.cancelled() =
      _CancelledTextToSpeechCompletion;

  /// Creates a failed completion.
  factory TextToSpeechCompletion.failed(LlamaException error) =>
      TextToSpeechCompletion._(
        state: TextToSpeechCompletionState.failed,
        error: error,
      );
}

class _CancelledTextToSpeechCompletion extends TextToSpeechCompletion {
  const _CancelledTextToSpeechCompletion()
    : super._(state: TextToSpeechCompletionState.cancelled);
}

/// A cancellable text-to-speech operation.
class TextToSpeechTask {
  final StreamController<TextToSpeechEvent> _eventsController;
  final Completer<TextToSpeechCompletion> _doneCompleter;
  final void Function() _onCancel;
  bool _cancelled = false;

  TextToSpeechTask._({required void Function() onCancel})
    : _onCancel = onCancel,
      _eventsController = StreamController<TextToSpeechEvent>(),
      _doneCompleter = Completer<TextToSpeechCompletion>();

  /// Progress followed by one final PCM event.
  ///
  /// This is a single-subscription stream. It carries progress only and
  /// never emits an error: a failed or cancelled task closes it without a
  /// final event, and [done] and [result] report why. Current synthesis
  /// exposes PCM only after generation completes; progress is not live
  /// audio.
  Stream<TextToSpeechEvent> get events => _eventsController.stream;

  /// Completes once the task succeeds, is cancelled, or fails. It never
  /// completes with an error.
  Future<TextToSpeechCompletion> get done => _doneCompleter.future;

  /// The complete synthesized audio.
  ///
  /// Throws the task's [LlamaException] when it fails, and
  /// [LlamaStateException] when it is cancelled. Await this future or attach
  /// an error handler as soon as you read it: a stored future that fails
  /// before it has a handler reports an uncaught async error.
  Future<TextToSpeechResult> get result => _result;

  late final Future<TextToSpeechResult> _result = done.then(
    (completion) => switch (completion.state) {
      TextToSpeechCompletionState.completed => completion.result!,
      TextToSpeechCompletionState.failed => throw completion.error!,
      TextToSpeechCompletionState.cancelled => throw LlamaStateException(
        'Speech synthesis was cancelled.',
      ),
    },
  );

  /// Whether cancellation has been requested.
  bool get isCancellationRequested => _cancelled;

  /// Requests cooperative cancellation of this task. Calling this more than
  /// once is safe.
  void cancel() {
    if (_cancelled || _doneCompleter.isCompleted) {
      return;
    }
    _cancelled = true;
    _onCancel();
  }
}

/// Typed text-to-speech API backed by a [LlamaEngine].
///
/// [load] loads a [TextToSpeechModel] and owns the engine it creates;
/// [attach] runs a [TextToSpeechAdapter] on a `LlamaEngine` the caller loaded
/// and keeps owning. The runtime generates audio natively on llama.cpp and
/// through compatible WebGPU bridge runtimes, with the model's
/// audio-generation projector. It reports progress and cancellation, but PCM
/// becomes available only after generation has completed.
///
/// ```dart
/// final synthesizer = await TextToSpeechEngine.load(
///   TextToSpeechModel(
///     ModelSource.parse('hf://owner/repo/tts-model.gguf'),
///     projector: ModelSource.parse('hf://owner/repo/mmproj-tts-model.gguf'),
///     adapter: const Qwen3TtsAdapter(),
///   ),
/// );
/// try {
///   final result = await synthesizer.synthesizeOnce(
///     const TextToSpeechRequest(text: 'Hello.', language: 'en'),
///   );
///   final wav = result.toWavBytes();
/// } finally {
///   await synthesizer.dispose();
/// }
/// ```
class TextToSpeechEngine implements LlamadartEngine<TextToSpeechCapabilities> {
  static const String _leaseOwner = 'text-to-speech';

  final LlamaEngine _engine;
  final bool _ownsEngine;
  final SpeechEngineLease _engineLease;
  TextToSpeechTask? _activeTask;
  Future<void>? _disposal;

  /// What drives the model.
  final TextToSpeechAdapter adapter;

  TextToSpeechEngine._(this._engine, this.adapter, {required bool ownsEngine})
    : _ownsEngine = ownsEngine,
      _engineLease = SpeechEngineLease.forEngine(_engine);

  /// Creates a synthesizer over an existing loaded engine.
  ///
  /// Only one typed speech task may use the underlying [LlamaEngine] at a time.
  @Deprecated(
    'Use TextToSpeechEngine.attach(engine, adapter: const Qwen3TtsAdapter()), '
    'or TextToSpeechEngine.load. This constructor will be removed in a future '
    'release.',
  )
  TextToSpeechEngine(
    LlamaEngine engine, {
    required TextToSpeechModelProfile modelProfile,
  }) : this._(engine, const Qwen3TtsAdapter(), ownsEngine: false);

  /// Loads [model] into a new [LlamaEngine] and returns a synthesizer that
  /// owns it.
  ///
  /// [load] creates the engine on [backend] (by default `LlamaBackend()`),
  /// loads [TextToSpeechModel.source] with [params] and then
  /// [TextToSpeechModel.projector], and checks [capabilities]. Each file
  /// comes from its `ModelSource`, resolved by [store]'s resolver and
  /// download manager (by default [DefaultModelResolver] and
  /// [DefaultModelDownloadManager]), main file first, before anything loads.
  /// [download] applies to every remote file: cache policy and directory,
  /// authentication, resume, retries and the cancel token. A local file
  /// takes only the cancel token. The bearer token and headers are never
  /// sent across hosts: when they are set and the remote files, or the URLs
  /// the resolver returns for them, span more than one origin (scheme, host
  /// and port), [load] throws [LlamaArgumentException] naming the origins
  /// before downloading from another host. [onProgress] reports the files
  /// together: `receivedBytes` counts the files resolved so far plus the
  /// current download, and `totalBytes` is their combined size once every
  /// size is known. Adapters in [ModelParams.loras] given as sources
  /// download as [LlamaEngine.setModel] downloads them. A URL-loading
  /// backend, as on the web, fetches each file itself, as
  /// [LlamaEngine.setModel] describes. [onProgress] then reports a fraction
  /// from 0 to 1: with a projector, the main file's fetch fills the first
  /// half and the projector reports 1 once it has loaded.
  ///
  /// The synthesizer owns the engine and a [backend] passed in: [dispose],
  /// or a failed load, disposes both. The load is atomic: when it throws,
  /// nothing stays loaded. Downloaded files stay in the model cache.
  ///
  /// Throws:
  /// - [LlamaArgumentException] when [download] would send credentials to
  ///   more than one host.
  /// - [LlamaUnsupportedException] before any file loads when the runtime
  ///   drives none of the models [TextToSpeechModel.adapter] accepts, such as
  ///   LFM3-Audio on a llama.cpp runtime older than llamadart-native v0.8.0;
  ///   when the loaded model cannot synthesize speech with the adapter (see
  ///   [capabilities]); and when
  ///   [download] sets [ModelLoadOptions.sha256] for a model with a
  ///   projector.
  /// - [LlamaStateException] when [download]'s cancel token cancels the load.
  /// - What [LlamaEngine.setModel], the resolver and the download manager
  ///   throw for a file that fails to download or load.
  static Future<TextToSpeechEngine> load(
    TextToSpeechModel model, {
    ModelParams params = const ModelParams(),
    ModelLoadOptions download = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
    ModelFileStore? store,
    LlamaBackend? backend,
  }) async {
    final runtime = backend ?? LlamaBackend();
    final String? refusal;
    try {
      refusal = await _runtimeRefusal(runtime, model.adapter);
    } catch (_) {
      await runtime.dispose();
      rethrow;
    }
    if (refusal != null) {
      await runtime.dispose();
      throw LlamaUnsupportedException(refusal);
    }
    final (engine, _) = await loadLlamaEngine(
      LlamaModel(model.source, projector: model.projector),
      params: params,
      download: download,
      onProgress: onProgress,
      store: store,
      backend: runtime,
      operation: 'TextToSpeechEngine model loading',
    );
    try {
      final synthesizer = TextToSpeechEngine._(
        engine,
        model.adapter,
        ownsEngine: true,
      );
      final capabilities = await synthesizer.capabilities;
      if (!capabilities.isSupported) {
        throw LlamaUnsupportedException(
          capabilities.unsupportedReason ??
              'The loaded model cannot synthesize speech.',
        );
      }
      return synthesizer;
    } catch (_) {
      try {
        await engine.dispose();
      } catch (_) {
        // The load failure is the error the caller needs.
      }
      rethrow;
    }
  }

  /// Why [runtime] drives none of the models [adapter] accepts, or null when
  /// it drives one or cannot tell before a model loads.
  static Future<String?> _runtimeRefusal(
    LlamaBackend runtime,
    TextToSpeechAdapter adapter,
  ) async {
    if (runtime is! BackendTextToSpeechModelSupport) return null;
    final probe = runtime as BackendTextToSpeechModelSupport;
    String? refusal;
    for (final candidate in BackendTextToSpeechModel.values) {
      if (!adapter.supportsModel(candidate)) continue;
      final reason = await probe.textToSpeechModelUnsupportedReason(candidate);
      if (reason == null) return null;
      refusal ??= reason;
    }
    return refusal;
  }

  /// Runs [adapter] on [engine], which the caller loaded and keeps owning.
  ///
  /// The engine needs a loaded model and its audio-generation projector;
  /// read [capabilities] to check. [dispose] cancels this synthesizer's task
  /// but leaves [engine] loaded. Only one typed speech task may use the
  /// underlying engine at a time.
  static TextToSpeechEngine attach(
    LlamaEngine engine, {
    required TextToSpeechAdapter adapter,
  }) => TextToSpeechEngine._(engine, adapter, ownsEngine: false);

  /// Model-specific adapter selected by the caller.
  ///
  /// Throws [LlamaStateException] for an adapter other than
  /// [Qwen3TtsAdapter], which has no profile.
  @Deprecated('Read adapter instead.')
  TextToSpeechModelProfile get modelProfile => switch (adapter) {
    Qwen3TtsAdapter() => TextToSpeechModelProfile.qwen3Tts,
    _ => throw LlamaStateException(
      'This TextToSpeechEngine runs ${adapter.name}, which has no '
      'TextToSpeechModelProfile. Read adapter instead.',
    ),
  };

  /// Whether [dispose] has been called.
  @override
  bool get isDisposed => _disposal != null;

  /// Discovers synthesis support for the active runtime, model, and
  /// projector; unsupported once disposed.
  @override
  Future<TextToSpeechCapabilities> get capabilities async {
    if (_disposal != null) {
      return const TextToSpeechCapabilities(
        isSupported: false,
        unsupportedReason: 'The TextToSpeechEngine is disposed.',
      );
    }
    if (_engine.isDisposed) {
      return const TextToSpeechCapabilities(
        isSupported: false,
        unsupportedReason: _engineDisposedMessage,
      );
    }
    String? backendName;
    try {
      backendName = await _engine.getBackendName();
    } catch (_) {
      // The capability result remains actionable without this label.
    }

    BackendTextToSpeechCapabilities backendCapabilities;
    try {
      backendCapabilities = await _engine.backendTextToSpeechCapabilities;
    } catch (error) {
      return TextToSpeechCapabilities(
        isSupported: false,
        unsupportedReason: 'The text-to-speech capability probe failed: $error',
        backendName: backendName,
      );
    }
    if (!backendCapabilities.isSupported) {
      return TextToSpeechCapabilities(
        isSupported: false,
        unsupportedReason: backendCapabilities.unsupportedReason,
        backendName: backendName,
      );
    }
    if (!adapter.supportsModel(backendCapabilities.model)) {
      return TextToSpeechCapabilities(
        isSupported: false,
        unsupportedReason:
            'The loaded projector is not a supported ${adapter.name} '
            'projector.',
        backendName: backendName,
      );
    }

    return TextToSpeechCapabilities(
      isSupported: true,
      backendName: backendName,
      implementation: textToSpeechSupportsFileInput
          ? TextToSpeechImplementation.nativeAudioGeneration
          : TextToSpeechImplementation.webAudioGeneration,
      sampleRateHz: backendCapabilities.sampleRateHz,
      channelCount: backendCapabilities.channelCount,
      speakerReferenceInputKinds: backendCapabilities.supportsSpeakerReference
          ? const <SpeechAudioInputKind>{
              if (textToSpeechSupportsFileInput) SpeechAudioInputKind.file,
              SpeechAudioInputKind.encodedBytes,
            }
          : const <SpeechAudioInputKind>{},
      supportsLanguage: backendCapabilities.supportsLanguage,
      supportedLanguages: backendCapabilities.supportsLanguage
          ? adapter.supportedLanguages
          : const <String>{},
      supportsSpeakerReference: backendCapabilities.supportsSpeakerReference,
      supportsVoice: backendCapabilities.supportsVoice,
      voices: backendCapabilities.supportsVoice
          ? backendCapabilities.voices
          : const <String>[],
      supportsIncrementalAudio: false,
      supportsCancellation: backendCapabilities.supportsCancellation,
      supportsOutputBackpressure: false,
      maxConcurrentTasks: 1,
    );
  }

  /// Starts one complete synthesis and returns the running task.
  ///
  /// The task's [TextToSpeechTask.events] report prompt processing and
  /// generated frames; the PCM arrives only on completion, in one
  /// [TextToSpeechFinalEvent] and in [TextToSpeechTask.result].
  /// [TextToSpeechTask.cancel] stops only this synthesis.
  ///
  /// Invalid input and unsupported preflight checks throw before the task is
  /// returned. Failures after backend startup are reported by
  /// [TextToSpeechTask.done] and [TextToSpeechTask.result]. Throws
  /// [LlamaStateException] after [dispose] and after [LlamaEngine.dispose]
  /// of an attached engine; [dispose],
  /// [LlamaEngine.unloadModel] and [LlamaEngine.dispose] cancel a running
  /// task.
  Future<TextToSpeechTask> synthesize(TextToSpeechRequest request) async {
    _throwIfDisposed();
    _validateRequest(request);
    if (!_engineLease.acquire(_leaseOwner)) {
      throw LlamaStateException(
        'This LlamaEngine already has an active typed speech task '
        '(${_engineLease.activeOwner}).',
      );
    }

    try {
      final currentCapabilities = await capabilities;
      _throwIfDisposed();
      if (_engine.isDisposed) {
        throw LlamaStateException(_engineDisposedMessage);
      }
      if (!currentCapabilities.isSupported) {
        throw LlamaUnsupportedException(
          currentCapabilities.unsupportedReason ??
              'Text-to-speech is not supported by the active runtime.',
        );
      }
      final normalizedLanguage = _normalizeLanguage(request.language);
      if (normalizedLanguage != null) {
        if (!currentCapabilities.supportsLanguage) {
          throw LlamaUnsupportedException(
            'The active text-to-speech model does not accept a language.',
          );
        }
      }
      if (request.speakerReference != null &&
          !currentCapabilities.supportsSpeakerReference) {
        throw LlamaUnsupportedException(
          'The active text-to-speech model does not accept speaker reference '
          'audio.',
        );
      }
      final voice = request.voice;
      if (voice != null) {
        if (!currentCapabilities.supportsVoice) {
          throw LlamaUnsupportedException(
            'The active text-to-speech model has no predefined voices.',
          );
        }
        final voices = currentCapabilities.voices;
        final lowerVoice = voice.toLowerCase();
        if (voices.isNotEmpty &&
            !voices.any((name) => name.toLowerCase() == lowerVoice)) {
          throw LlamaTextToSpeechException(
            'Unknown ${adapter.name} voice `$voice`. Use one of: '
            '${voices.join(', ')}.',
          );
        }
      }

      final task = TextToSpeechTask._(
        onCancel: _engine.cancelTextToSpeechBackend,
      );
      _engineLease.onUnload(_leaseOwner, task.cancel);
      _activeTask = task;
      unawaited(_runTask(task, request, normalizedLanguage));
      return task;
    } catch (_) {
      _engineLease.release(_leaseOwner);
      rethrow;
    }
  }

  /// Synthesizes [request] and returns the complete audio.
  ///
  /// Throws what [synthesize] throws, the failure of the task, or
  /// [LlamaStateException] when the task is cancelled, as [dispose] and
  /// [LlamaEngine.unloadModel] do.
  Future<TextToSpeechResult> synthesizeOnce(
    TextToSpeechRequest request,
  ) async => (await synthesize(request)).result;

  /// Cancels a running task, waits for it to stop, and disposes the
  /// [LlamaEngine] that [load] created. An engine passed to [attach] stays
  /// loaded. Calling this more than once is safe.
  @override
  Future<void> dispose() {
    final existing = _disposal;
    if (existing != null) return existing;

    // Cleanup hooks can reenter before an async body's first suspension.
    final disposal = Completer<void>();
    _disposal = disposal.future;
    disposal.complete(_dispose());
    return disposal.future;
  }

  Future<void> _dispose() async {
    final task = _activeTask;
    if (task != null) {
      task.cancel();
      await task.done;
    }
    if (_ownsEngine) {
      await _engine.dispose();
    }
  }

  void _throwIfDisposed() {
    if (_disposal != null) {
      throw LlamaStateException('The TextToSpeechEngine is disposed.');
    }
  }

  static const String _engineDisposedMessage =
      'The attached LlamaEngine is disposed. Create a new LlamaEngine and '
      'attach a new TextToSpeechEngine.';

  void _validateRequest(TextToSpeechRequest request) {
    if (request.text.trim().isEmpty) {
      throw LlamaTextToSpeechException('Text to synthesize must not be empty.');
    }
    if (request.maxFrames <= 0) {
      throw LlamaTextToSpeechException('maxFrames must be greater than 0.');
    }
    if (request.promptBatchSize <= 0) {
      throw LlamaTextToSpeechException(
        'promptBatchSize must be greater than 0.',
      );
    }
    if (request.topK <= 0 ||
        !request.topP.isFinite ||
        request.topP <= 0 ||
        request.topP > 1 ||
        !request.minP.isFinite ||
        request.minP < 0 ||
        request.minP > 1 ||
        !request.temperature.isFinite ||
        request.temperature < 0 ||
        request.seed < 0 ||
        request.seed > 0xffffffff) {
      throw LlamaTextToSpeechException(
        'Invalid text-to-speech sampling parameters.',
      );
    }
    final voice = request.voice;
    if (voice != null) {
      if (voice.trim().isEmpty) {
        throw LlamaTextToSpeechException('voice must not be empty.');
      }
      if (request.speakerReference != null) {
        throw LlamaTextToSpeechException(
          'A voice and a speaker reference cannot be combined.',
        );
      }
    }
    switch (request.speakerReference) {
      case SpeechAudioFileInput(:final path):
        if (path.trim().isEmpty) {
          throw LlamaAudioFormatException(
            'Speaker reference file path must not be empty.',
          );
        }
        if (!textToSpeechSupportsFileInput) {
          throw LlamaUnsupportedException(
            'Web text-to-speech speaker references require encoded bytes; '
            'browser runtimes cannot read local file paths.',
          );
        }
      case SpeechAudioBytesInput(:final bytes):
        if (bytes.isEmpty) {
          throw LlamaAudioFormatException(
            'Speaker reference bytes must not be empty.',
          );
        }
      case SpeechAudioPcmInput():
        throw LlamaUnsupportedException(
          'Text-to-speech speaker references require encoded audio.',
        );
      case null:
        break;
    }
  }

  Future<void> _runTask(
    TextToSpeechTask task,
    TextToSpeechRequest request,
    String? normalizedLanguage,
  ) async {
    TextToSpeechCompletion? outcome;
    try {
      if (task.isCancellationRequested) {
        _closeCancelledEvents(task);
        outcome = const TextToSpeechCompletion.cancelled();
        return;
      }
      final speakerReference = request.speakerReference;
      final backendResult = await _engine.synthesizeTextToSpeechBackend(
        BackendTextToSpeechRequest(
          text: request.text.trim(),
          language: normalizedLanguage,
          speakerAudioPath: switch (speakerReference) {
            SpeechAudioFileInput(:final path) => path,
            _ => null,
          },
          speakerAudioBytes: switch (speakerReference) {
            SpeechAudioBytesInput(:final bytes) => bytes,
            _ => null,
          },
          voice: request.voice,
          maxFrames: request.maxFrames,
          promptBatchSize: request.promptBatchSize,
          topK: request.topK,
          topP: request.topP,
          minP: request.minP,
          temperature: request.temperature,
          seed: request.seed,
        ),
        onProgress: (progress) {
          if (task.isCancellationRequested || task._eventsController.isClosed) {
            return;
          }
          task._eventsController.add(
            TextToSpeechProgressEvent(
              phase: progress.phase == BackendTextToSpeechPhase.processingPrompt
                  ? TextToSpeechProgressPhase.processingPrompt
                  : TextToSpeechProgressPhase.generating,
              promptTokensRemaining: progress.promptTokensRemaining,
              framesGenerated: progress.framesGenerated,
              truncated: progress.truncated,
            ),
          );
        },
      );

      if (task.isCancellationRequested) {
        _closeCancelledEvents(task);
        outcome = const TextToSpeechCompletion.cancelled();
        return;
      }
      final result = TextToSpeechResult(
        samples: backendResult.samples,
        sampleRateHz: backendResult.sampleRateHz,
        channelCount: backendResult.channelCount,
        framesGenerated: backendResult.framesGenerated,
        truncated: backendResult.truncated,
      );
      task._eventsController.add(TextToSpeechFinalEvent(result));
      unawaited(task._eventsController.close());
      outcome = TextToSpeechCompletion.completed(result);
    } catch (error) {
      if (task.isCancellationRequested) {
        _closeCancelledEvents(task);
        outcome = const TextToSpeechCompletion.cancelled();
        return;
      }
      final speechError = error is LlamaException
          ? error
          : LlamaTextToSpeechException('Speech synthesis failed.', error);
      unawaited(task._eventsController.close());
      outcome = TextToSpeechCompletion.failed(speechError);
    } finally {
      // The lease must be free before `done` completes, otherwise a caller
      // that awaits it cannot start the next task.
      _engineLease.release(_leaseOwner);
      if (identical(_activeTask, task)) {
        _activeTask = null;
      }
      if (outcome != null && !task._doneCompleter.isCompleted) {
        task._doneCompleter.complete(outcome);
      }
    }
  }

  String? _normalizeLanguage(String? language) {
    final trimmed = language?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return adapter.normalizeLanguage(trimmed);
  }

  void _closeCancelledEvents(TextToSpeechTask task) {
    if (!task._eventsController.isClosed) {
      unawaited(task._eventsController.close());
    }
  }
}
