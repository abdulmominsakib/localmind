import 'dart:async';
import 'dart:typed_data';

import '../../backends/backend.dart';
import '../../backends/litert_lm/litert_lm_asr_types.dart';
import '../engine/engine.dart';
import '../engine/engine_capabilities.dart';
import '../engine/llamadart_engine.dart';
import '../exceptions.dart';
import '../image/image_model_classifier.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/chat_role.dart';
import '../models/chat/content_part.dart';
import '../models/download/model_download_manager.dart';
import '../models/inference/generation_params.dart';
import '../models/inference/model_params.dart';
import '../models/model_file_store.dart';
import '../models/model_load_options.dart';
import '../models/model_source.dart';
import '../models/model_target_file.dart';
import 'litert_lm_speech_to_text_driver.dart';
import 'litert_lm_speech_to_text_driver_stub.dart'
    if (dart.library.io) 'litert_lm_speech_to_text_driver_io.dart';
import 'projector_file_reader_stub.dart'
    if (dart.library.io) '../../platform/io/projector_file_reader_io.dart';
import 'speech_engine_lease.dart';
import 'speech_to_text_model.dart';
import 'speech_platform_stub.dart'
    if (dart.library.js_interop) 'speech_platform_web.dart';

/// The kind of audio input accepted by a speech recognizer.
enum SpeechAudioInputKind {
  /// A local encoded audio file.
  file,

  /// Encoded audio held in memory.
  encodedBytes,

  /// Mono float PCM held in memory.
  pcmFloat32,
}

/// Model-specific adapter used by [SpeechToTextEngine].
///
/// A profile is an explicit caller declaration. Generic multimodal audio
/// support alone does not prove that a loaded model is an ASR model.
@Deprecated(
  'Use a SpeechToTextAdapter: Qwen3AsrAdapter or LiteRtLmAsrAdapter. '
  'This enum will be removed in a future release.',
)
enum SpeechToTextModelProfile {
  /// Qwen3-ASR with its matching llama.cpp multimodal projector.
  qwen3Asr,

  /// Dedicated LiteRT-LM ASR selected by [LiteRtLmAsrRuntimeConfig].
  liteRtLmDedicated,
}

/// How the active backend implements speech recognition.
enum SpeechToTextImplementation {
  /// No usable speech recognition path is available.
  unavailable,

  /// Audio is routed through multimodal chat with a model-specific adapter.
  multimodalPromptAdapter,

  /// A backend-native, dedicated speech recognition API.
  dedicatedBackend,
}

/// Audio metadata supplied with speech input.
class SpeechAudioFormat {
  /// Sample rate in Hertz, when known.
  final int? sampleRateHz;

  /// Number of interleaved audio channels, when known.
  final int? channelCount;

  /// Container, codec, or sample encoding such as `wav`, `flac`, or
  /// `pcm-f32le`.
  final String? encoding;

  /// MIME type supplied by the caller, when available.
  final String? mimeType;

  /// Creates audio metadata.
  const SpeechAudioFormat({
    this.sampleRateHz,
    this.channelCount,
    this.encoding,
    this.mimeType,
  });
}

/// Base class for audio accepted by [SpeechToTextEngine].
sealed class SpeechAudioInput {
  /// Optional source audio metadata.
  final SpeechAudioFormat? format;

  /// Creates a speech audio input.
  const SpeechAudioInput({this.format});

  /// The representation used by this input.
  SpeechAudioInputKind get kind;
}

/// A local encoded audio file.
class SpeechAudioFileInput extends SpeechAudioInput {
  /// Local filesystem path.
  final String path;

  /// Creates a local-file input.
  const SpeechAudioFileInput(this.path, {super.format});

  @override
  SpeechAudioInputKind get kind => SpeechAudioInputKind.file;
}

/// Encoded audio held in memory.
class SpeechAudioBytesInput extends SpeechAudioInput {
  /// Encoded audio bytes.
  final Uint8List bytes;

  /// Creates an encoded in-memory input.
  const SpeechAudioBytesInput(this.bytes, {super.format});

  @override
  SpeechAudioInputKind get kind => SpeechAudioInputKind.encodedBytes;
}

/// Mono float PCM held in memory.
class SpeechAudioPcmInput extends SpeechAudioInput {
  /// Normalized PCM samples in the range -1.0 to 1.0.
  final Float32List samples;

  /// Creates a float PCM input.
  ///
  /// Dedicated LiteRT-LM ASR currently requires mono 16 kHz input.
  SpeechAudioPcmInput(
    this.samples, {
    super.format = const SpeechAudioFormat(
      sampleRateHz: 16000,
      channelCount: 1,
      encoding: 'pcm-f32le',
    ),
  });

  @override
  SpeechAudioInputKind get kind => SpeechAudioInputKind.pcmFloat32;
}

/// A request to recognize speech from one complete audio input.
class SpeechToTextRequest {
  /// Audio to transcribe.
  final SpeechAudioInput audio;

  /// Optional BCP-47 language hint, such as `en` or `fr-CA`.
  ///
  /// Only a [SpeechToTextPromptAdapter] whose
  /// [SpeechToTextPromptAdapter.supportsLanguageHints] is true takes it; the
  /// engine rejects a nonempty hint otherwise. [Qwen3AsrAdapter] and
  /// [LiteRtLmAsrAdapter] take none.
  final String? languageHint;

  /// Optional vocabulary or surrounding-text guidance for the recognizer.
  final String? contextPrompt;

  /// Maximum number of generated transcript tokens.
  ///
  /// This applies to prompt-adapted recognition. Dedicated ASR backends ignore
  /// it after validating that it is positive.
  final int maxOutputTokens;

  /// Creates a speech recognition request.
  const SpeechToTextRequest({
    required this.audio,
    this.languageHint,
    this.contextPrompt,
    this.maxOutputTokens = 1024,
  });
}

/// Runtime speech-to-text capabilities for the loaded engine.
class SpeechToTextCapabilities implements EngineCapabilities {
  /// Whether recognition can be started with the configured engine.
  @override
  final bool isSupported;

  /// Actionable reason when [isSupported] is false.
  @override
  final String? unsupportedReason;

  /// Active runtime backend label.
  @override
  final String? backendName;

  /// Whether recognition uses a prompt adapter or a dedicated backend API.
  final SpeechToTextImplementation implementation;

  /// Accepted audio input representations.
  final Set<SpeechAudioInputKind> inputKinds;

  /// File/byte encodings decoded by the first native backend.
  final Set<String> encodedAudioFormats;

  /// Whether text deltas can be emitted before the final transcript.
  final bool supportsPartialResults;

  /// Whether audio can be pushed incrementally while recognition is running.
  final bool supportsStreamingInput;

  /// Whether word or segment timestamps can be returned.
  bool get supportsTimestamps =>
      supportsSegmentTimestamps || supportsWordTimestamps;

  /// Whether segment timestamps can be returned.
  final bool supportsSegmentTimestamps;

  /// Whether word timestamps can be returned.
  final bool supportsWordTimestamps;

  /// Whether confidence values can be returned.
  final bool supportsConfidence;

  /// Whether speaker labels can be returned.
  final bool supportsSpeakerDiarization;

  /// Whether the runtime can report the recognized language.
  final bool supportsLanguageDetection;

  /// Whether language hints can be passed to the model.
  final bool supportsLanguageHints;

  /// Whether an active task can be cancelled cooperatively.
  final bool supportsCancellation;

  /// Whether pausing the output subscription throttles native inference.
  final bool supportsOutputBackpressure;

  /// Whether awaiting an input push applies bounded native backpressure.
  final bool supportsInputBackpressure;

  /// Maximum number of concurrent tasks owned by one recognizer or engine.
  final int maxConcurrentTasks;

  /// Creates a capability snapshot.
  const SpeechToTextCapabilities({
    required this.isSupported,
    this.unsupportedReason,
    this.backendName,
    this.implementation = SpeechToTextImplementation.unavailable,
    this.inputKinds = const <SpeechAudioInputKind>{},
    this.encodedAudioFormats = const <String>{},
    this.supportsPartialResults = false,
    this.supportsStreamingInput = false,
    this.supportsSegmentTimestamps = false,
    this.supportsWordTimestamps = false,
    this.supportsConfidence = false,
    this.supportsSpeakerDiarization = false,
    this.supportsLanguageDetection = false,
    this.supportsLanguageHints = false,
    this.supportsCancellation = false,
    this.supportsOutputBackpressure = false,
    this.supportsInputBackpressure = false,
    this.maxConcurrentTasks = 0,
  });
}

/// A recognized word with optional backend-provided metadata.
class TranscriptWord {
  /// Recognized word or token text.
  final String text;

  /// Start time relative to the beginning of the input, when available.
  final Duration? start;

  /// End time relative to the beginning of the input, when available.
  final Duration? end;

  /// Confidence in the range 0.0 to 1.0, when available.
  final double? confidence;

  /// Speaker label, when diarization is available.
  final String? speaker;

  /// Creates a recognized word.
  const TranscriptWord({
    required this.text,
    this.start,
    this.end,
    this.confidence,
    this.speaker,
  });
}

/// A recognized transcript segment.
class TranscriptSegment {
  /// Segment text.
  final String text;

  /// Start time relative to the beginning of the input, when available.
  final Duration? start;

  /// End time relative to the beginning of the input, when available.
  final Duration? end;

  /// Confidence in the range 0.0 to 1.0, when available.
  final double? confidence;

  /// Speaker label, when diarization is available.
  final String? speaker;

  /// Word-level details, when available.
  final List<TranscriptWord> words;

  /// Creates a transcript segment.
  const TranscriptSegment({
    required this.text,
    this.start,
    this.end,
    this.confidence,
    this.speaker,
    this.words = const <TranscriptWord>[],
  });
}

/// Final speech recognition result.
class SpeechToTextResult {
  /// Complete normalized transcript text.
  final String text;

  /// Model-reported language, when available.
  final String? language;

  /// Structured transcript segments.
  ///
  /// The first backend returns one untimed segment for the complete transcript.
  final List<TranscriptSegment> segments;

  /// Metadata describing the supplied source audio, when available.
  final SpeechAudioFormat? sourceFormat;

  /// Audio duration accepted by the recognizer, when known.
  final Duration? audioDuration;

  /// Creates a final recognition result.
  const SpeechToTextResult({
    required this.text,
    this.language,
    this.segments = const <TranscriptSegment>[],
    this.sourceFormat,
    this.audioDuration,
  });
}

/// Base class for streamed speech recognition events.
sealed class SpeechToTextEvent {
  /// Creates a speech recognition event.
  const SpeechToTextEvent();
}

/// A replaceable, non-final transcript update.
class SpeechToTextPartialEvent extends SpeechToTextEvent {
  /// Current best transcript text.
  final String text;

  /// Stable transcript prefix that will not be revised.
  final String? confirmedText;

  /// Replaceable hypothesis for the current inference window.
  final String? pendingText;

  /// Audio duration accepted when this update was produced.
  final Duration? acceptedAudioDuration;

  /// Creates a partial transcript event.
  const SpeechToTextPartialEvent(
    this.text, {
    this.confirmedText,
    this.pendingText,
    this.acceptedAudioDuration,
  });
}

/// The final transcript event for a task.
class SpeechToTextFinalEvent extends SpeechToTextEvent {
  /// Final recognition result.
  final SpeechToTextResult result;

  /// Creates a final transcript event.
  const SpeechToTextFinalEvent(this.result);
}

/// Terminal state of a speech recognition task.
enum SpeechToTextCompletionState {
  /// Recognition produced a final result.
  completed,

  /// Recognition was cancelled.
  cancelled,

  /// Recognition failed.
  failed,
}

/// Terminal details for a speech recognition task.
class SpeechToTextCompletion {
  /// Terminal state.
  final SpeechToTextCompletionState state;

  /// Final result when [state] is [SpeechToTextCompletionState.completed].
  final SpeechToTextResult? result;

  /// Failure when [state] is [SpeechToTextCompletionState.failed].
  final LlamaException? error;

  const SpeechToTextCompletion._({
    required this.state,
    this.result,
    this.error,
  });

  /// Creates a successful completion.
  factory SpeechToTextCompletion.completed(SpeechToTextResult result) =>
      SpeechToTextCompletion._(
        state: SpeechToTextCompletionState.completed,
        result: result,
      );

  /// Creates a cancelled completion.
  const factory SpeechToTextCompletion.cancelled() =
      _CancelledSpeechToTextCompletion;

  /// Creates a failed completion.
  factory SpeechToTextCompletion.failed(LlamaException error) =>
      SpeechToTextCompletion._(
        state: SpeechToTextCompletionState.failed,
        error: error,
      );
}

class _CancelledSpeechToTextCompletion extends SpeechToTextCompletion {
  const _CancelledSpeechToTextCompletion()
    : super._(state: SpeechToTextCompletionState.cancelled);
}

/// A cancellable speech recognition operation.
class SpeechToTextTask {
  final StreamController<SpeechToTextEvent> _eventsController;
  final Completer<SpeechToTextCompletion> _doneCompleter;
  final void Function()? _onCancel;
  void Function()? _cancelTokenStream;
  bool _cancelled = false;

  SpeechToTextTask._({void Function()? onCancel})
    : _onCancel = onCancel,
      _eventsController = StreamController<SpeechToTextEvent>(),
      _doneCompleter = Completer<SpeechToTextCompletion>();

  /// Recognition events.
  ///
  /// This is a single-subscription stream. It carries recognition progress
  /// only and never emits an error: a failed or cancelled task closes it
  /// without a final event, and [done] and [result] report why.
  /// Prompt-adapted recognition emits one [SpeechToTextFinalEvent]. Dedicated
  /// backends can emit [SpeechToTextPartialEvent] updates first.
  Stream<SpeechToTextEvent> get events => _eventsController.stream;

  /// Completes once the task succeeds, is cancelled, or fails. It never
  /// completes with an error.
  Future<SpeechToTextCompletion> get done => _doneCompleter.future;

  /// The final transcript.
  ///
  /// Throws the task's [LlamaException] when it fails, and
  /// [LlamaStateException] when it is cancelled. Await this future or attach
  /// an error handler as soon as you read it: a stored future that fails
  /// before it has a handler reports an uncaught async error.
  Future<SpeechToTextResult> get result => _result;

  late final Future<SpeechToTextResult> _result = done.then(
    (completion) => switch (completion.state) {
      SpeechToTextCompletionState.completed => completion.result!,
      SpeechToTextCompletionState.failed => throw completion.error!,
      SpeechToTextCompletionState.cancelled => throw LlamaStateException(
        'Speech recognition was cancelled.',
      ),
    },
  );

  /// Whether cancellation has been requested.
  bool get isCancellationRequested => _cancelled;

  /// Requests cooperative cancellation of this task. It does not cancel
  /// other requests on the same `LlamaEngine`. Calling this more than once is
  /// safe.
  void cancel() {
    if (_cancelled || _doneCompleter.isCompleted) {
      return;
    }
    _cancelled = true;
    _onCancel?.call();
    _cancelTokenStream?.call();
  }
}

/// An active incremental speech-recognition session.
///
/// Callers must await each [addPcm] operation. This applies bounded input
/// backpressure while native inference runs in a worker isolate.
///
/// Unlike [SpeechToTextTask], a session has no single result to await: it
/// ends a live input stream, so [cancel] returns a future that completes
/// once the native recognizer is released, and [events] reports a runtime
/// failure as a stream error as well as through [done].
abstract interface class SpeechToTextStreamingSession {
  /// Partial and final transcript events.
  ///
  /// This is a single-subscription stream. Runtime failures are emitted as a
  /// stream error and are also reported by [done] as a failed completion.
  Stream<SpeechToTextEvent> get events;

  /// Terminal completion state.
  Future<SpeechToTextCompletion> get done;

  /// Adds mono 16 kHz normalized float PCM.
  ///
  /// The caller must not mutate [samples] until the returned future completes.
  Future<void> addPcm(Float32List samples);

  /// Marks input complete and flushes the final partial inference window.
  Future<void> finish();

  /// Requests cooperative cancellation and releases native resources.
  Future<void> cancel();
}

/// Typed speech-to-text API for prompt-adapted and dedicated ASR runtimes.
///
/// [load] loads a [SpeechToTextModel] and owns what it loads; [attach] runs
/// a [SpeechToTextPromptAdapter] on a `LlamaEngine` the caller loaded and
/// keeps owning. The model's adapter picks the runtime: a prompt adapter,
/// such as [Qwen3AsrAdapter], sends encoded audio through multimodal chat on
/// a `LlamaEngine`; [LiteRtLmAsrAdapter] runs a dedicated native LiteRT-LM
/// recognizer with incremental PCM input and partial transcripts.
///
/// ```dart
/// final recognizer = await SpeechToTextEngine.load(
///   SpeechToTextModel(
///     ModelSource.parse('hf://owner/repo/asr-model.gguf'),
///     projector: ModelSource.parse('hf://owner/repo/mmproj-asr-model.gguf'),
///     adapter: const Qwen3AsrAdapter(),
///   ),
/// );
/// try {
///   final result = await recognizer.transcribeOnce(
///     const SpeechToTextRequest(audio: SpeechAudioFileInput('speech.wav')),
///   );
///   print(result.text);
/// } finally {
///   await recognizer.dispose();
/// }
/// ```
class SpeechToTextEngine implements LlamadartEngine<SpeechToTextCapabilities> {
  static const String _leaseOwner = 'speech-to-text';
  static const SpeechAudioFormat _liteRtLmPcmFormat = SpeechAudioFormat(
    sampleRateHz: 16000,
    channelCount: 1,
    encoding: 'pcm-f32le',
  );

  final LlamaEngine? _engine;
  final bool _ownsEngine;
  final SpeechEngineLease? _engineLease;
  final LiteRtLmAsrRuntimeConfig? _liteRtLmConfig;
  final LiteRtLmSpeechToTextDriver? _liteRtLmDriver;
  final String? _liteRtLmLibraryPath;
  Future<LiteRtLmSpeechToTextSupport>? _liteRtLmSupportFuture;
  bool _liteRtLmTaskActive = false;
  SpeechToTextStreamingSession? _activeStream;
  SpeechToTextTask? _activeTask;
  Future<void>? _disposal;
  LoadedMultimodalProjector? _checkedProjector;
  Future<String?>? _checkedProjectorType;

  /// What drives the model: a [SpeechToTextPromptAdapter] or a
  /// [LiteRtLmAsrAdapter].
  final SpeechToTextAdapter adapter;

  SpeechToTextEngine._prompt(
    LlamaEngine engine,
    SpeechToTextPromptAdapter this.adapter, {
    required bool ownsEngine,
  }) : _engine = engine,
       _ownsEngine = ownsEngine,
       _engineLease = SpeechEngineLease.forEngine(engine),
       _liteRtLmConfig = null,
       _liteRtLmDriver = null,
       _liteRtLmLibraryPath = null;

  SpeechToTextEngine._liteRtLm(
    LiteRtLmAsrRuntimeConfig config,
    LiteRtLmSpeechToTextDriver driver,
    this.adapter, {
    String? libraryPath,
    Future<LiteRtLmSpeechToTextSupport>? support,
  }) : _engine = null,
       _ownsEngine = false,
       _engineLease = null,
       _liteRtLmConfig = config,
       _liteRtLmDriver = driver,
       _liteRtLmLibraryPath = libraryPath,
       _liteRtLmSupportFuture = support;

  /// Creates a Qwen3-ASR prompt adapter over an existing loaded engine.
  ///
  /// The engine must be used exclusively until [SpeechToTextTask.done]
  /// completes. Separate speech wrappers over the same engine share a lease,
  /// but direct [LlamaEngine.create] calls remain caller-owned.
  @Deprecated(
    'Use SpeechToTextEngine.attach(engine, adapter: const Qwen3AsrAdapter()), '
    'or SpeechToTextEngine.load. This constructor will be removed in a '
    'future release.',
  )
  SpeechToTextEngine(
    LlamaEngine engine, {
    required SpeechToTextModelProfile modelProfile,
  }) : this._prompt(
         engine,
         modelProfile == SpeechToTextModelProfile.liteRtLmDedicated
             ? throw ArgumentError.value(
                 modelProfile,
                 'modelProfile',
                 'Use SpeechToTextEngine.liteRtLm for dedicated LiteRT-LM ASR.',
               )
             : const Qwen3AsrAdapter(),
         ownsEngine: false,
       );

  /// Creates a dedicated native LiteRT-LM recognizer.
  ///
  /// The configured model and tokenizer are independent of any chat model
  /// loaded through [LlamaEngine]. The current runtime accepts mono 16 kHz
  /// float PCM and supports one active task per recognizer instance.
  /// [libraryPath] is an advanced local-validation override; packaged apps
  /// should omit it and use the runtime resolved by native assets.
  ///
  /// Throws [LlamaUnsupportedException] when [config] names a remote model
  /// or tokenizer: this constructor opens local files only, and [load]
  /// downloads remote ones.
  @Deprecated(
    'Use SpeechToTextEngine.load(SpeechToTextModel(model, tokenizer: '
    'tokenizer, adapter: LiteRtLmAsrAdapter(preset))). This constructor will '
    'be removed in a future release.',
  )
  SpeechToTextEngine.liteRtLm(
    LiteRtLmAsrRuntimeConfig config, {
    String? libraryPath,
  }) : this._liteRtLm(
         _localLiteRtLmConfig(config),
         debugLiteRtLmSpeechToTextDriverOverride ??
             createLiteRtLmSpeechToTextDriver(),
         LiteRtLmAsrAdapter(
           config.modelPreset,
           numberOfThreads: config.numberOfThreads,
           maxBufferedAudio: config.maxBufferedAudio,
           overlapRatio: config.overlapRatio,
           libraryPath: libraryPath,
         ),
         libraryPath: libraryPath,
       );

  /// Loads [model] and returns a recognizer that owns what it loaded.
  ///
  /// Every file of [model] comes from its `ModelSource`, resolved by
  /// [store]'s resolver and download manager (by default
  /// [DefaultModelResolver] and [DefaultModelDownloadManager]), one at a
  /// time, main file first, before anything loads. [download] applies to
  /// every remote file: cache policy and directory, authentication, resume,
  /// retries and the cancel token. A local file takes only the cancel token.
  /// The bearer token and headers are never sent across hosts: when they
  /// are set and the remote files, or the URLs the resolver returns for them,
  /// span more than one origin (scheme, host and port), [load] throws
  /// [LlamaArgumentException] naming the origins before downloading from
  /// another host.
  /// [onProgress] reports the files together: `receivedBytes` counts the
  /// files resolved so far plus the current download, and `totalBytes` is
  /// their combined size once every size is known.
  ///
  /// With a [SpeechToTextPromptAdapter], [load] creates a [LlamaEngine] on
  /// [backend] (by default `LlamaBackend()`), loads [SpeechToTextModel.source]
  /// with [params] (by default `ModelParams()`) and then
  /// [SpeechToTextModel.projector], and checks [capabilities]. The recognizer
  /// owns that engine and a [backend] passed in: [dispose], or a failed
  /// load, disposes both. Adapters in [ModelParams.loras] given as sources
  /// download as [LlamaEngine.setModel] downloads them. A URL-loading
  /// backend, as on the web, fetches each file itself, as
  /// [LlamaEngine.setModel] describes. [onProgress] then reports a fraction
  /// from 0 to 1: with a projector, the main file's fetch fills the first
  /// half and the projector reports 1 once it has loaded.
  ///
  /// With a [LiteRtLmAsrAdapter], [load] probes the LiteRT-LM ASR runtime
  /// before any download and then resolves [SpeechToTextModel.source] and
  /// [SpeechToTextModel.tokenizer] to local files. Each [transcribe] or
  /// [startStream] starts its own native session on them in a worker
  /// isolate. The adapter carries the runtime settings, so [params] and
  /// [backend] must be null; [load] disposes a [backend] passed in before it
  /// throws.
  ///
  /// The load is atomic: when it throws, nothing stays loaded. Downloaded
  /// files stay in the model cache.
  ///
  /// Throws:
  /// - [LlamaArgumentException] when [model] lacks a file its adapter needs
  ///   or has one it cannot use, when [params] or [backend] is set for a
  ///   [LiteRtLmAsrAdapter], or when [download] would send credentials to
  ///   more than one host.
  /// - [LlamaUnsupportedException] when the loaded model cannot recognize
  ///   speech (see [capabilities]), when the LiteRT-LM ASR runtime is
  ///   unavailable, including on the web, and when [download] sets
  ///   [ModelLoadOptions.sha256] for a model of more than one file.
  /// - [LlamaStateException] when [download]'s cancel token cancels the load.
  /// - What [LlamaEngine.setModel], the resolver and the download manager
  ///   throw for a file that fails to download or load.
  static Future<SpeechToTextEngine> load(
    SpeechToTextModel model, {
    ModelParams? params,
    ModelLoadOptions download = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
    ModelFileStore? store,
    LlamaBackend? backend,
  }) async {
    switch (model.adapter) {
      case final SpeechToTextPromptAdapter adapter:
        if (model.tokenizer != null) {
          await _rejectLoad(
            backend,
            LlamaArgumentException(
              'A ${adapter.name} model takes no tokenizer file; the tokenizer '
              'is part of the model. Leave SpeechToTextModel.tokenizer unset.',
              name: 'model.tokenizer',
            ),
          );
        }
        final (engine, _) = await loadLlamaEngine(
          LlamaModel(model.source, projector: model.projector),
          params: params ?? const ModelParams(),
          download: download,
          onProgress: onProgress,
          store: store,
          backend: backend,
          operation: 'SpeechToTextEngine model loading',
        );
        try {
          final recognizer = SpeechToTextEngine._prompt(
            engine,
            adapter,
            ownsEngine: true,
          );
          final capabilities = await recognizer.capabilities;
          if (!capabilities.isSupported) {
            throw LlamaUnsupportedException(
              capabilities.unsupportedReason ??
                  'The loaded model cannot recognize speech.',
            );
          }
          return recognizer;
        } catch (_) {
          try {
            await engine.dispose();
          } catch (_) {
            // The load failure is the error the caller needs.
          }
          rethrow;
        }
      case final LiteRtLmAsrAdapter adapter:
        final tokenizer = model.tokenizer;
        if (tokenizer == null) {
          await _rejectLoad(
            backend,
            LlamaArgumentException(
              'Dedicated LiteRT-LM ASR needs the model\'s tokenizer JSON. Set '
              'SpeechToTextModel.tokenizer.',
              name: 'model.tokenizer',
            ),
          );
        }
        if (model.projector != null) {
          await _rejectLoad(
            backend,
            LlamaArgumentException(
              'Dedicated LiteRT-LM ASR takes no multimodal projector. Leave '
              'SpeechToTextModel.projector unset.',
              name: 'model.projector',
            ),
          );
        }
        if (params != null || backend != null) {
          await _rejectLoad(
            backend,
            LlamaArgumentException(
              'params and backend apply to models that run on LlamaEngine. '
              'Set dedicated LiteRT-LM ASR settings on LiteRtLmAsrAdapter.',
              name: params != null ? 'params' : 'backend',
            ),
          );
        }
        final driver =
            debugLiteRtLmSpeechToTextDriverOverride ??
            createLiteRtLmSpeechToTextDriver();
        final support = await driver.probeSupport(
          libraryPath: adapter.libraryPath,
        );
        if (!support.isSupported) {
          throw LlamaUnsupportedException(
            support.unsupportedReason ??
                'Dedicated LiteRT-LM speech recognition is unavailable.',
          );
        }
        final paths = await resolveModelSourceFiles(
          [model.source, tokenizer],
          store: store ?? ModelFileStore(),
          download: download,
          operation: 'SpeechToTextEngine model loading',
          onProgress: onProgress,
          assetType: 'speech recognition model',
        );
        return SpeechToTextEngine._liteRtLm(
          LiteRtLmAsrRuntimeConfig.source(
            model: ModelSource.path(paths[0]),
            tokenizer: ModelSource.path(paths[1]),
            modelPreset: adapter.preset,
            numberOfThreads: adapter.numberOfThreads,
            maxBufferedAudio: adapter.maxBufferedAudio,
            overlapRatio: adapter.overlapRatio,
          ),
          driver,
          adapter,
          libraryPath: adapter.libraryPath,
          support: Future<LiteRtLmSpeechToTextSupport>.value(support),
        );
    }
  }

  /// Disposes the [backend] that [load] took ownership of, then throws
  /// [error].
  static Future<Never> _rejectLoad(
    LlamaBackend? backend,
    LlamaArgumentException error,
  ) async {
    try {
      await backend?.dispose();
    } catch (_) {
      // The argument error is the one the caller needs.
    }
    throw error;
  }

  /// Runs [adapter] on [engine], which the caller loaded and keeps owning.
  ///
  /// The engine needs a loaded model and, on llama.cpp, its audio projector;
  /// read [capabilities] to check. [dispose] cancels this recognizer's task
  /// but leaves [engine] loaded. Typed speech wrappers over the same engine
  /// share one task at a time; direct [LlamaEngine.create] calls stay
  /// caller-owned and must not run during a task.
  static SpeechToTextEngine attach(
    LlamaEngine engine, {
    required SpeechToTextPromptAdapter adapter,
  }) => SpeechToTextEngine._prompt(engine, adapter, ownsEngine: false);

  /// Model-specific adapter selected by the caller.
  ///
  /// Throws [LlamaStateException] for an adapter other than
  /// [Qwen3AsrAdapter] and [LiteRtLmAsrAdapter], which have no profile.
  @Deprecated('Read adapter instead.')
  SpeechToTextModelProfile get modelProfile => switch (adapter) {
    LiteRtLmAsrAdapter() => SpeechToTextModelProfile.liteRtLmDedicated,
    Qwen3AsrAdapter() => SpeechToTextModelProfile.qwen3Asr,
    _ => throw LlamaStateException(
      'This SpeechToTextEngine runs ${adapter.name}, which has no '
      'SpeechToTextModelProfile. Read adapter instead.',
    ),
  };

  static LiteRtLmAsrRuntimeConfig _localLiteRtLmConfig(
    LiteRtLmAsrRuntimeConfig config,
  ) {
    for (final (name, source) in [
      ('model', config.model),
      ('tokenizer', config.tokenizer),
    ]) {
      if (source != null && source.isRemote) {
        throw LlamaUnsupportedException(
          'SpeechToTextEngine.liteRtLm opens local files only, but the $name '
          'is the remote source ${source.displayName}. Load remote LiteRT-LM '
          'ASR files with SpeechToTextEngine.load and a LiteRtLmAsrAdapter.',
        );
      }
    }
    return config;
  }

  bool get _usesLiteRtLm => _liteRtLmConfig != null;

  SpeechToTextPromptAdapter get _promptAdapter =>
      adapter as SpeechToTextPromptAdapter;

  /// Whether [dispose] has been called.
  @override
  bool get isDisposed => _disposal != null;

  /// Discovers speech recognition support for the configured runtime and
  /// model; unsupported once disposed.
  ///
  /// With a [Qwen3AsrAdapter], it also reads the loaded projector's GGUF
  /// header and reports a projector whose audio projector type is not
  /// Qwen3-ASR's `qwen3a`, such as Qwen3-TTS's `qwen3tts_spkenc`, as
  /// unsupported. When the type cannot be read (on the web, or for a file
  /// that is unreadable or names no type) the model stays supported, and an
  /// empty transcript's [LlamaSpeechException.details] names a possible
  /// model mismatch.
  @override
  Future<SpeechToTextCapabilities> get capabilities async {
    if (_disposal != null) {
      return const SpeechToTextCapabilities(
        isSupported: false,
        unsupportedReason: 'The SpeechToTextEngine is disposed.',
      );
    }
    if (_usesLiteRtLm) {
      final support = await (_liteRtLmSupportFuture ??= _liteRtLmDriver!
          .probeSupport(libraryPath: _liteRtLmLibraryPath));
      if (!support.isSupported) {
        return SpeechToTextCapabilities(
          isSupported: false,
          unsupportedReason: support.unsupportedReason,
          backendName: 'LiteRT-LM ASR',
        );
      }
      return const SpeechToTextCapabilities(
        isSupported: true,
        backendName: 'LiteRT-LM ASR CPU',
        implementation: SpeechToTextImplementation.dedicatedBackend,
        inputKinds: <SpeechAudioInputKind>{SpeechAudioInputKind.pcmFloat32},
        supportsPartialResults: true,
        supportsStreamingInput: true,
        supportsCancellation: true,
        supportsInputBackpressure: true,
        maxConcurrentTasks: 1,
      );
    }

    final engine = _engine!;
    if (engine.isDisposed) {
      return const SpeechToTextCapabilities(
        isSupported: false,
        unsupportedReason: _engineDisposedMessage,
      );
    }
    if (speechToTextRequiresBackendCapability) {
      final backend = engine.backend;
      final speechBackend = backend is BackendPromptSpeechToTextSupport
          ? backend as BackendPromptSpeechToTextSupport
          : null;
      if (speechBackend == null || !speechBackend.supportsPromptSpeechToText) {
        return SpeechToTextCapabilities(
          isSupported: false,
          unsupportedReason: speechBackend != null
              ? speechBackend.promptSpeechToTextUnsupportedReason
              : 'The active Web runtime does not expose validated typed '
                    'speech-to-text support.',
        );
      }
    }
    if (!engine.isReady) {
      return const SpeechToTextCapabilities(
        isSupported: false,
        unsupportedReason:
            'Load a model and its audio-capable multimodal projector first.',
      );
    }

    String? backendName;
    try {
      backendName = await engine.getBackendName();
    } catch (_) {
      // Capability discovery can still use the explicit audio probe.
    }
    if (backendName?.toLowerCase().contains('litert-lm') ?? false) {
      return SpeechToTextCapabilities(
        isSupported: false,
        unsupportedReason:
            'A chat-model LiteRT-LM engine is not a dedicated ASR session. '
            'Use SpeechToTextEngine.load with a LiteRtLmAsrAdapter, an ASR '
            'model and its tokenizer.',
        backendName: backendName,
      );
    }

    bool supportsAudio;
    try {
      supportsAudio = await engine.supportsAudio;
    } catch (error) {
      return SpeechToTextCapabilities(
        isSupported: false,
        unsupportedReason: 'The audio capability probe failed: $error',
        backendName: backendName,
      );
    }
    if (!supportsAudio) {
      return SpeechToTextCapabilities(
        isSupported: false,
        unsupportedReason: engine.hasMultimodalProjector
            ? 'The loaded multimodal projector does not report audio support.'
            : 'No multimodal projector is loaded. Load the model with its '
                  'audio projector, as LlamaModel(source, projector: ...).',
        backendName: backendName,
      );
    }

    final promptAdapter = _promptAdapter;
    if (promptAdapter is Qwen3AsrAdapter) {
      final projectorType = await _loadedAudioProjectorType(engine);
      if (projectorType != null && projectorType != _qwen3AsrProjectorType) {
        return SpeechToTextCapabilities(
          isSupported: false,
          unsupportedReason:
              "The loaded audio projector's type is '$projectorType', not "
              "${promptAdapter.name}'s '$_qwen3AsrProjectorType'. Load a "
              '${promptAdapter.name} model with its own projector.',
          backendName: backendName,
        );
      }
    }
    return SpeechToTextCapabilities(
      isSupported: true,
      backendName: backendName,
      implementation: SpeechToTextImplementation.multimodalPromptAdapter,
      inputKinds: <SpeechAudioInputKind>{
        if (speechToTextSupportsFileInput) SpeechAudioInputKind.file,
        SpeechAudioInputKind.encodedBytes,
      },
      encodedAudioFormats: speechToTextEncodedAudioFormats,
      supportsLanguageDetection: promptAdapter.supportsLanguageDetection,
      supportsLanguageHints: promptAdapter.supportsLanguageHints,
      supportsCancellation: true,
      maxConcurrentTasks: 1,
    );
  }

  /// Starts recognition for one complete audio input and returns the running
  /// task.
  ///
  /// A [SpeechToTextPromptAdapter] accepts encoded files or bytes, and its
  /// task emits one [SpeechToTextFinalEvent]. Dedicated LiteRT-LM ASR
  /// accepts [SpeechAudioPcmInput] and emits any intermediate
  /// [SpeechToTextPartialEvent] updates before its final result. Invalid
  /// input and unsupported preflight checks throw before a task is returned;
  /// failures after startup are reported by [SpeechToTextTask.done] and
  /// [SpeechToTextTask.result]. Throws [LlamaStateException] after
  /// [dispose] and after [LlamaEngine.dispose] of an attached engine.
  ///
  /// On native llama.cpp, a prompt-adapted task that reaches the context
  /// size or [SpeechToTextRequest.maxOutputTokens] before the transcript ends
  /// fails with [LlamaSpeechTranscriptTruncatedException].
  ///
  /// [SpeechToTextTask.cancel] stops only this task's generation: it does
  /// not cancel chat or other requests on the same [LlamaEngine]. [dispose],
  /// [LlamaEngine.unloadModel] and [LlamaEngine.dispose] cancel an active
  /// prompt-adapted task, which then reports
  /// [SpeechToTextCompletionState.cancelled] with no result.
  Future<SpeechToTextTask> transcribe(SpeechToTextRequest request) async {
    _throwIfDisposed();
    _validateRequest(request);
    if (_usesLiteRtLm) {
      return _transcribeLiteRtLm(request);
    }

    final lease = _engineLease!;
    if (!lease.acquire(_leaseOwner)) {
      throw LlamaStateException(
        'This LlamaEngine already has an active typed speech task '
        '(${lease.activeOwner}).',
      );
    }

    try {
      final currentCapabilities = await capabilities;
      _throwIfDisposed();
      if (_engine!.isDisposed) {
        throw LlamaStateException(_engineDisposedMessage);
      }
      if (!currentCapabilities.isSupported) {
        throw LlamaUnsupportedException(
          currentCapabilities.unsupportedReason ??
              'Speech-to-text is not supported by the active runtime.',
        );
      }

      // Cancelling the task's own token subscription stops its generation;
      // LlamaEngine.cancelGeneration would also stop other requests.
      final task = SpeechToTextTask._();
      lease.onUnload(_leaseOwner, task.cancel);
      _activeTask = task;
      unawaited(_runPromptAdapterTask(task, request));
      return task;
    } catch (_) {
      lease.release(_leaseOwner);
      rethrow;
    }
  }

  /// Recognizes [request]'s audio and returns the final result.
  ///
  /// Throws what [transcribe] throws, the failure of the task, or
  /// [LlamaStateException] when the task is cancelled, as [dispose] and
  /// [LlamaEngine.unloadModel] do.
  Future<SpeechToTextResult> transcribeOnce(
    SpeechToTextRequest request,
  ) async => (await transcribe(request)).result;

  /// Starts an incremental dedicated-ASR session.
  ///
  /// This is available only with a [LiteRtLmAsrAdapter]. The accepted
  /// [format] is mono 16 kHz `pcm-f32le`. Await every
  /// [SpeechToTextStreamingSession.addPcm] call so bounded native
  /// backpressure can throttle the producer. [dispose] cancels the session.
  /// Throws [LlamaStateException] after [dispose].
  Future<SpeechToTextStreamingSession> startStream({
    SpeechAudioFormat format = _liteRtLmPcmFormat,
  }) async {
    _throwIfDisposed();
    if (!_usesLiteRtLm) {
      throw LlamaUnsupportedException(
        'The ${adapter.name} prompt adapter accepts complete encoded audio '
        'only.',
      );
    }
    _validateLiteRtLmPcmFormat(format);
    if (_liteRtLmTaskActive) {
      throw LlamaStateException(
        'This SpeechToTextEngine already has an active LiteRT-LM ASR task.',
      );
    }
    _liteRtLmTaskActive = true;
    try {
      final currentCapabilities = await capabilities;
      if (!currentCapabilities.isSupported) {
        throw LlamaUnsupportedException(
          currentCapabilities.unsupportedReason ??
              'Dedicated LiteRT-LM speech recognition is unavailable.',
        );
      }
      final worker = await _liteRtLmDriver!.start(
        _liteRtLmConfig!,
        libraryPath: _liteRtLmLibraryPath,
      );
      late final _LiteRtLmStreamingSession session;
      session = _LiteRtLmStreamingSession(
        worker: worker,
        sourceFormat: format,
        onClosed: () {
          _liteRtLmTaskActive = false;
          if (identical(_activeStream, session)) {
            _activeStream = null;
          }
        },
      );
      if (_disposal != null) {
        await session.cancel();
        _throwIfDisposed();
      }
      return _activeStream = session;
    } catch (_) {
      _liteRtLmTaskActive = false;
      rethrow;
    }
  }

  /// Cancels a running task or stream, waits for it to stop, and disposes
  /// the [LlamaEngine] that [load] created. An engine passed to [attach]
  /// stays loaded. Calling this more than once is safe.
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
    final stream = _activeStream;
    task?.cancel();
    if (stream != null) {
      try {
        await stream.cancel();
      } catch (_) {
        // The stream reports its own failure; disposal still completes.
      }
    }
    if (task != null) {
      await task.done;
    }
    if (_ownsEngine) {
      await _engine!.dispose();
    }
  }

  void _throwIfDisposed() {
    if (_disposal != null) {
      throw LlamaStateException('The SpeechToTextEngine is disposed.');
    }
  }

  static const String _engineDisposedMessage =
      'The attached LlamaEngine is disposed. Create a new LlamaEngine and '
      'attach a new SpeechToTextEngine.';

  static const String _qwen3AsrProjectorType = 'qwen3a';

  // The synchronous parse runs on the caller's isolate, so it is capped far
  // below the generic header limit; real projector metadata takes a few KiB.
  static const int _projectorMetadataByteCap = 1 << 20;

  /// The type llama.cpp gives the audio projector loaded on [engine], read
  /// once per loaded projector. Null when none is loaded, its file cannot be
  /// read here, or it names no type.
  Future<String?> _loadedAudioProjectorType(LlamaEngine engine) {
    final projector = loadedMultimodalProjector(engine);
    if (projector == null) {
      return Future<String?>.value();
    }
    if (!identical(projector, _checkedProjector)) {
      _checkedProjector = projector;
      _checkedProjectorType = _readAudioProjectorType(projector.location);
    }
    return _checkedProjectorType!;
  }

  /// The projector type in the GGUF header at [location], with llama.cpp's
  /// precedence: `clip.projector_type`, else `clip.audio.projector_type`.
  static Future<String?> _readAudioProjectorType(String location) async {
    try {
      final metadata = await readGgufMetadata(
        // Synchronous reads keep the check to microtasks: an asynchronous
        // read would put real event-loop turns between the capability check
        // and the task it gates.
        (offset, length) async =>
            readProjectorFileRange(location, offset, length),
        maxBytes: _projectorMetadataByteCap,
        stopAt: 'clip.projector_type',
      );
      final type =
          metadata['clip.projector_type'] ??
          metadata['clip.audio.projector_type'];
      return type is String ? type : null;
    } catch (_) {
      return null;
    }
  }

  Future<SpeechToTextTask> _transcribeLiteRtLm(
    SpeechToTextRequest request,
  ) async {
    final audio = request.audio as SpeechAudioPcmInput;
    final session = await startStream(format: audio.format!);
    late final SpeechToTextTask task;
    task = SpeechToTextTask._(onCancel: () => unawaited(session.cancel()));
    _activeTask = task;
    unawaited(_pipeLiteRtLmTask(task, session, audio.samples));
    return task;
  }

  Future<void> _pipeLiteRtLmTask(
    SpeechToTextTask task,
    SpeechToTextStreamingSession session,
    Float32List samples,
  ) async {
    final subscription = session.events.listen(
      task._eventsController.add,
      // session.done reports the failure.
      onError: (Object _) {},
    );
    try {
      await session.addPcm(samples);
      if (!task.isCancellationRequested) {
        await session.finish();
      }
      final completion = await session.done;
      if (!task._doneCompleter.isCompleted) {
        task._doneCompleter.complete(completion);
      }
    } catch (error) {
      try {
        await session.cancel();
      } catch (_) {
        // Preserve the first recognition failure.
      }
      if (task.isCancellationRequested) {
        _completeCancelled(task);
      } else {
        final speechError = _speechError(error);
        if (!task._doneCompleter.isCompleted) {
          task._doneCompleter.complete(
            SpeechToTextCompletion.failed(speechError),
          );
        }
      }
    } finally {
      await subscription.cancel();
      if (!task._eventsController.isClosed) {
        // close() completes only after a listener drains the stream, and
        // callers that await only `result` never listen.
        unawaited(task._eventsController.close());
      }
      if (identical(_activeTask, task)) {
        _activeTask = null;
      }
    }
  }

  void _validateRequest(SpeechToTextRequest request) {
    if (request.maxOutputTokens <= 0) {
      throw LlamaSpeechException('maxOutputTokens must be greater than 0.');
    }
    final languageHint = request.languageHint?.trim();
    final contextPrompt = request.contextPrompt?.trim();
    final promptAdapter = _usesLiteRtLm ? null : _promptAdapter;
    if (languageHint != null &&
        languageHint.isNotEmpty &&
        !(promptAdapter?.supportsLanguageHints ?? false)) {
      throw LlamaUnsupportedException(
        'The selected speech recognizer does not expose validated language hints.',
      );
    }
    if (_usesLiteRtLm) {
      if (contextPrompt != null && contextPrompt.isNotEmpty) {
        throw LlamaUnsupportedException(
          'Dedicated LiteRT-LM ASR does not expose context prompting.',
        );
      }
      final audio = request.audio;
      if (audio is! SpeechAudioPcmInput) {
        throw LlamaUnsupportedException(
          'Dedicated LiteRT-LM ASR accepts SpeechAudioPcmInput only.',
        );
      }
      if (audio.samples.isEmpty) {
        throw LlamaAudioFormatException('Float PCM samples must not be empty.');
      }
      final format = audio.format;
      if (format == null) {
        throw LlamaAudioFormatException(
          'Dedicated LiteRT-LM ASR requires explicit PCM metadata.',
        );
      }
      _validateLiteRtLmPcmFormat(format);
      return;
    }
    if (contextPrompt != null &&
        contextPrompt.isNotEmpty &&
        !promptAdapter!.supportsContextPrompt) {
      throw LlamaUnsupportedException(
        'The ${adapter.name} prompt adapter does not take a context prompt.',
      );
    }

    switch (request.audio) {
      case SpeechAudioFileInput(:final path):
        if (!speechToTextSupportsFileInput) {
          throw LlamaUnsupportedException(
            'Web speech-to-text accepts encoded audio bytes only; browser '
            'local filesystem paths are not available to the runtime.',
          );
        }
        if (path.trim().isEmpty) {
          throw LlamaAudioFormatException('Audio file path must not be empty.');
        }
        final encoding = request.audio.format?.encoding?.trim().toLowerCase();
        final extension = _fileExtension(path);
        if (encoding != null && encoding.isNotEmpty) {
          if (!speechToTextEncodedAudioFormats.contains(encoding)) {
            throw LlamaAudioFormatException(
              'Encoded audio files must use ${_encodedFormatList()}.',
              encoding,
            );
          }
        } else if (extension.isNotEmpty &&
            !speechToTextEncodedAudioFormats.contains(extension)) {
          throw LlamaAudioFormatException(
            'Encoded audio files must use ${_encodedFormatList()}.',
            extension,
          );
        }
      case SpeechAudioBytesInput(:final bytes):
        if (bytes.isEmpty) {
          throw LlamaAudioFormatException(
            'Encoded audio bytes must not be empty.',
          );
        }
        final encoding = request.audio.format?.encoding?.trim().toLowerCase();
        if (speechToTextRequiresEncodedAudioFormat &&
            (encoding == null || encoding.isEmpty)) {
          throw LlamaAudioFormatException(
            'Web encoded audio bytes require SpeechAudioFormat.encoding: '
            '${_encodedFormatList()}.',
          );
        }
        if (encoding != null &&
            encoding.isNotEmpty &&
            !speechToTextEncodedAudioFormats.contains(encoding)) {
          throw LlamaAudioFormatException(
            'Encoded audio bytes must use ${_encodedFormatList()}.',
            encoding,
          );
        }
      case SpeechAudioPcmInput():
        throw LlamaUnsupportedException(
          'The ${adapter.name} prompt adapter accepts encoded audio only.',
        );
    }
  }

  String _encodedFormatList() {
    final formats = speechToTextEncodedAudioFormats
        .map((format) => format.toUpperCase())
        .toList(growable: false);
    if (formats.length == 1) {
      return formats.single;
    }
    return '${formats.take(formats.length - 1).join(', ')}, or ${formats.last}';
  }

  void _validateLiteRtLmPcmFormat(SpeechAudioFormat format) {
    final encoding = format.encoding?.trim().toLowerCase();
    if (format.sampleRateHz != 16000 ||
        format.channelCount != 1 ||
        (encoding != null && encoding.isNotEmpty && encoding != 'pcm-f32le')) {
      throw LlamaAudioFormatException(
        'Dedicated LiteRT-LM ASR requires mono 16 kHz pcm-f32le audio.',
        'sampleRateHz=${format.sampleRateHz}, '
            'channelCount=${format.channelCount}, encoding=${format.encoding}',
      );
    }
  }

  Future<void> _runPromptAdapterTask(
    SpeechToTextTask task,
    SpeechToTextRequest request,
  ) async {
    try {
      if (task.isCancellationRequested) {
        _completeCancelled(task);
        return;
      }

      final output = StringBuffer();
      final tokenStreamDone = Completer<void>();
      StreamSubscription<String>? tokenSubscription;
      Future<void>? tokenStreamCancellation;
      void cancelTokenStream() {
        if (tokenStreamCancellation != null) {
          return;
        }
        final subscription = tokenSubscription;
        if (subscription == null) {
          return;
        }
        late final Future<void> cancellation;
        try {
          cancellation = subscription.cancel();
        } catch (error, stackTrace) {
          cancellation = Future<void>.error(error, stackTrace);
        }
        tokenStreamCancellation = cancellation;
        unawaited(cancellation.catchError((Object _, StackTrace _) {}));
        if (!tokenStreamDone.isCompleted) {
          tokenStreamDone.complete();
        }
      }

      Object? tokenStreamError;
      StackTrace? tokenStreamStackTrace;
      BackendGenerationLimit? generationLimit;
      try {
        final tokens = _promptAdapterTokens(
          request,
          onLimit: (limit) => generationLimit = limit,
        );
        tokenSubscription = tokens.listen(
          (token) {
            if (!task.isCancellationRequested && tokenStreamError == null) {
              output.write(token);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            tokenStreamError ??= error;
            tokenStreamStackTrace ??= stackTrace;
            if (!tokenStreamDone.isCompleted) {
              tokenStreamDone.complete();
            }
          },
          onDone: () {
            if (!tokenStreamDone.isCompleted) {
              tokenStreamDone.complete();
            }
          },
          cancelOnError: false,
        );
        task._cancelTokenStream = cancelTokenStream;
        if (task.isCancellationRequested) {
          cancelTokenStream();
        }
        await tokenStreamDone.future;
      } catch (error, stackTrace) {
        tokenStreamError ??= error;
        tokenStreamStackTrace ??= stackTrace;
      } finally {
        if (identical(task._cancelTokenStream, cancelTokenStream)) {
          task._cancelTokenStream = null;
        }
        try {
          cancelTokenStream();
          await tokenStreamCancellation;
        } catch (error, stackTrace) {
          tokenStreamError ??= error;
          tokenStreamStackTrace ??= stackTrace;
        }
      }
      final error = tokenStreamError;
      if (error != null) {
        Error.throwWithStackTrace(error, tokenStreamStackTrace!);
      }

      if (task.isCancellationRequested) {
        _completeCancelled(task);
        return;
      }

      final normalized = _promptAdapter.parseTranscript(output.toString());
      final limit = generationLimit;
      if (limit != null) {
        throw _truncatedTranscript(limit, normalized.text);
      }
      if (normalized.text.isEmpty) {
        throw LlamaSpeechException(
          'Speech recognition produced an empty transcript.',
          await _unverifiedModelHint(),
        );
      }
      final result = SpeechToTextResult(
        text: normalized.text,
        language: normalized.language,
        segments: <TranscriptSegment>[TranscriptSegment(text: normalized.text)],
        sourceFormat: request.audio.format,
      );
      task._eventsController.add(SpeechToTextFinalEvent(result));
      unawaited(task._eventsController.close());
      task._doneCompleter.complete(SpeechToTextCompletion.completed(result));
    } catch (error) {
      if (task.isCancellationRequested) {
        _completeCancelled(task);
        return;
      }
      final speechError = _speechError(error);
      unawaited(task._eventsController.close());
      task._doneCompleter.complete(SpeechToTextCompletion.failed(speechError));
    } finally {
      _engineLease!.release(_leaseOwner);
      if (identical(_activeTask, task)) {
        _activeTask = null;
      }
    }
  }

  /// Null once the loaded projector is known to be the adapter's; otherwise
  /// why an empty transcript may not mean silence.
  Future<String?> _unverifiedModelHint() async {
    final adapter = _promptAdapter;
    if (adapter is Qwen3AsrAdapter &&
        await _loadedAudioProjectorType(_engine!) == _qwen3AsrProjectorType) {
      return null;
    }
    return 'The audio may be silent, or the loaded model may not be a '
        '${adapter.name} model: its projector type could not be checked.';
  }

  void _completeCancelled(SpeechToTextTask task) {
    if (!task._eventsController.isClosed) {
      unawaited(task._eventsController.close());
    }
    if (!task._doneCompleter.isCompleted) {
      task._doneCompleter.complete(const SpeechToTextCompletion.cancelled());
    }
  }

  /// Streams transcript text for the prompt adapter.
  ///
  /// Native Qwen3-ASR needs the audio turn wrapped by the model chat template,
  /// so it goes through [LlamaEngine.create]. The Web bridge speech contract is
  /// validated against raw prompt generation with bytes-only audio parts.
  Stream<String> _promptAdapterTokens(
    SpeechToTextRequest request, {
    required void Function(BackendGenerationLimit limit) onLimit,
  }) {
    final engine = _engine!;
    final params = GenerationParams(
      maxTokens: request.maxOutputTokens,
      temp: 0,
      topK: 1,
      topP: 1,
      penalty: 1,
      seed: 1,
      streamBatchTokenThreshold: 1,
    );
    if (!speechToTextUsesChatTemplate) {
      final generation = engine.generate(
        _promptAdapter.promptFor(request),
        parts: <LlamaContentPart>[_contentFor(request.audio)],
        params: params,
      );
      return _rawPromptAdapterTokens(generation, onLimit);
    }
    return engine
        .create(
          <LlamaChatMessage>[
            LlamaChatMessage.withContent(
              role: LlamaChatRole.user,
              content: <LlamaContentPart>[
                LlamaTextContent(_promptAdapter.promptFor(request)),
                _contentFor(request.audio),
              ],
            ),
          ],
          params: params,
          enableThinking: false,
        )
        .expand((chunk) {
          final limit = completionGenerationLimit(chunk);
          if (limit != null) {
            onLimit(limit);
          }
          if (chunk.choices.isEmpty) {
            return const <String>[];
          }
          final text = chunk.choices.first.delta.content;
          return text == null ? const <String>[] : <String>[text];
        });
  }

  Stream<String> _rawPromptAdapterTokens(
    Stream<String> generation,
    void Function(BackendGenerationLimit limit) onLimit,
  ) async* {
    yield* generation;
    final limit = rawGenerationLimit(generation);
    if (limit != null) onLimit(limit);
  }

  LlamaSpeechTranscriptTruncatedException _truncatedTranscript(
    BackendGenerationLimit limit,
    String partialTranscript,
  ) {
    return switch (limit) {
      BackendGenerationLimit.maxTokens =>
        LlamaSpeechTranscriptTruncatedException(
          'Speech recognition reached maxOutputTokens before the transcript '
          'ended. Raise maxOutputTokens or send shorter audio.',
          limit: LlamaSpeechTranscriptLimit.maxOutputTokens,
          partialTranscript: partialTranscript,
        ),
      BackendGenerationLimit.contextSize =>
        LlamaSpeechTranscriptTruncatedException(
          'The audio prompt and transcript filled the model context before '
          'the transcript ended. Send shorter audio or load the model with a '
          'larger contextSize.',
          limit: LlamaSpeechTranscriptLimit.contextSize,
          partialTranscript: partialTranscript,
        ),
      BackendGenerationLimit.runtime => LlamaSpeechTranscriptTruncatedException(
        'Speech recognition reached a runtime generation limit before the '
        'transcript ended. Send shorter audio; the runtime does not identify '
        'whether an output-token, context, or media limit stopped recognition.',
        limit: LlamaSpeechTranscriptLimit.runtime,
        partialTranscript: partialTranscript,
      ),
    };
  }

  LlamaAudioContent _contentFor(SpeechAudioInput audio) {
    return switch (audio) {
      SpeechAudioFileInput(:final path) => LlamaAudioContent(path: path),
      SpeechAudioBytesInput(:final bytes) => LlamaAudioContent(bytes: bytes),
      SpeechAudioPcmInput() => throw LlamaUnsupportedException(
        'The ${adapter.name} prompt adapter accepts encoded audio only.',
      ),
    };
  }

  String _fileExtension(String path) {
    final cleanPath = path.split('?').first.split('#').first;
    final filename = cleanPath.replaceAll('\\', '/').split('/').last;
    final separator = filename.lastIndexOf('.');
    if (separator < 0 || separator == filename.length - 1) {
      return '';
    }
    return filename.substring(separator + 1).toLowerCase();
  }
}

class _LiteRtLmStreamingSession implements SpeechToTextStreamingSession {
  static const int _sampleRateHz = 16000;

  final LiteRtLmSpeechToTextWorker _worker;
  final SpeechAudioFormat _sourceFormat;
  final void Function() _onClosed;
  final StreamController<SpeechToTextEvent> _events =
      StreamController<SpeechToTextEvent>();
  final Completer<SpeechToTextCompletion> _done =
      Completer<SpeechToTextCompletion>();
  late final StreamSubscription<LiteRtLmSpeechToTextUpdate> _workerSubscription;

  Future<void> _operationTail = Future<void>.value();
  bool _finishing = false;
  bool _closed = false;
  int _acceptedSamples = 0;
  String _latestConfirmedText = '';

  _LiteRtLmStreamingSession({
    required LiteRtLmSpeechToTextWorker worker,
    required SpeechAudioFormat sourceFormat,
    required void Function() onClosed,
  }) : _worker = worker,
       _sourceFormat = sourceFormat,
       _onClosed = onClosed {
    _workerSubscription = _worker.updates.listen(
      _handleUpdate,
      onError: (Object error, StackTrace stackTrace) {
        unawaited(_fail(error, stackTrace));
      },
    );
  }

  @override
  Stream<SpeechToTextEvent> get events => _events.stream;

  @override
  Future<SpeechToTextCompletion> get done => _done.future;

  @override
  Future<void> addPcm(Float32List samples) {
    if (_finishing || _closed) {
      throw LlamaStateException(
        'Cannot add audio after the speech stream has finished.',
      );
    }
    if (samples.isEmpty) {
      return Future<void>.value();
    }
    final operation = _operationTail.then((_) async {
      if (_finishing || _closed) {
        throw LlamaStateException(
          'Cannot add audio after the speech stream has finished.',
        );
      }
      final accepted = await _worker.pushAudio(samples);
      if (accepted != samples.length) {
        throw LlamaSpeechException(
          'LiteRT-LM ASR did not accept the complete PCM input.',
          'acceptedSamples=$accepted, suppliedSamples=${samples.length}',
        );
      }
      _acceptedSamples += accepted;
    });
    final guarded = operation.catchError((
      Object error,
      StackTrace stackTrace,
    ) async {
      await _fail(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    });
    _operationTail = guarded;
    return guarded;
  }

  @override
  Future<void> finish() async {
    if (_finishing || _closed) {
      return;
    }
    _finishing = true;
    try {
      await _operationTail;
      final transcript = await _worker.finish();
      final normalized = transcript.trim().isEmpty
          ? _latestConfirmedText.trim()
          : transcript.trim();
      final result = SpeechToTextResult(
        text: normalized,
        segments: normalized.isEmpty
            ? const <TranscriptSegment>[]
            : <TranscriptSegment>[TranscriptSegment(text: normalized)],
        sourceFormat: _sourceFormat,
        audioDuration: _durationForSamples(_acceptedSamples),
      );
      if (!_events.isClosed) {
        _events.add(SpeechToTextFinalEvent(result));
      }
      await _close();
      if (!_done.isCompleted) {
        _done.complete(SpeechToTextCompletion.completed(result));
      }
    } catch (error, stackTrace) {
      await _fail(error, stackTrace);
    }
  }

  @override
  Future<void> cancel() async {
    if (_closed) {
      return;
    }
    _finishing = true;
    try {
      await _worker.cancel();
    } finally {
      await _close();
      if (!_done.isCompleted) {
        _done.complete(const SpeechToTextCompletion.cancelled());
      }
    }
  }

  void _handleUpdate(LiteRtLmSpeechToTextUpdate update) {
    if (_closed) {
      return;
    }
    _latestConfirmedText = update.confirmedText;
    _acceptedSamples = update.acceptedSamples;
    if (update.isFinal) {
      return;
    }
    final confirmed = update.confirmedText.trim();
    final pending = update.pendingText.trim();
    final text = <String>[
      confirmed,
      pending,
    ].where((part) => part.isNotEmpty).join(' ');
    _events.add(
      SpeechToTextPartialEvent(
        text,
        confirmedText: confirmed,
        pendingText: pending,
        acceptedAudioDuration: _durationForSamples(update.acceptedSamples),
      ),
    );
  }

  Duration _durationForSamples(int samples) => Duration(
    microseconds: (samples * Duration.microsecondsPerSecond) ~/ _sampleRateHz,
  );

  Future<void> _fail(Object error, StackTrace stackTrace) async {
    if (_closed) {
      return;
    }
    final speechError = _speechError(error);
    if (!_events.isClosed) {
      _events.addError(speechError, stackTrace);
    }
    await _close();
    if (!_done.isCompleted) {
      _done.complete(SpeechToTextCompletion.failed(speechError));
    }
  }

  Future<void> _close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      await _workerSubscription.cancel();
    } catch (_) {
      // Continue releasing the worker and public task lease.
    }
    try {
      await _worker.dispose();
    } catch (_) {
      // Native teardown is best effort after the task has reached a terminal
      // state. The original recognition error remains authoritative.
    }
    if (!_events.isClosed) {
      unawaited(_events.close());
    }
    _onClosed();
  }
}

LlamaException _speechError(Object error) => error is LlamaException
    ? error
    : LlamaSpeechException('Speech recognition failed.', error);
