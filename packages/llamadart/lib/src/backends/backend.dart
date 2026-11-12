import 'dart:typed_data';

import '../core/decision/decision_question.dart';
import '../core/engine/engine_capabilities.dart';
import '../core/engine/engine_observer.dart';
import '../core/exceptions.dart';
import '../core/models/inference/embedding.dart';
import '../core/models/inference/reranking.dart';
import '../core/models/inference/model_params.dart';
import '../core/models/inference/generation_params.dart';
import '../core/models/inference/generation_usage.dart';
import '../core/models/inference/next_token_scores.dart';
import '../core/models/inference/state_identity.dart';
import '../core/models/inference/tool_choice.dart';
import '../core/models/chat/chat_message.dart';
import '../core/models/chat/completion_chunk.dart';
import '../core/models/chat/content_part.dart';
import '../core/models/config/gpu_backend.dart';
import '../core/models/config/gpu_device_info.dart';
import '../core/models/config/log_level.dart';
import '../core/models/diagnostics/model_file_type.dart';
import '../core/models/model_format.dart';
import '../core/models/tools/tool_definition.dart';

import 'web/web_backend.dart' if (dart.library.io) 'native/native_backend.dart';

/// Platform-agnostic interface for local model inference.
abstract class LlamaBackend {
  /// Factory to create the appropriate backend for the current platform.
  factory LlamaBackend() => createBackend();

  /// Opts into ordered LiteRT-LM Web text history, system prompts and tool
  /// calling.
  ///
  /// Web requires a runtime with the published conversation/preface APIs;
  /// tools need one that reads `preface.tools`, which
  /// `LlamaEngineCapabilities.supportsToolCalling` reports. Automatic tool
  /// loops also need the load-time token-count probes to succeed; otherwise
  /// they throw. Unsupported thinking, media and template controls throw
  /// explicitly.
  /// Native selection and behavior are the same as [LlamaBackend.new].
  /// The original default factory retains its existing Web behavior.
  factory LlamaBackend.withTextHistory() => createTextHistoryBackend();

  /// Whether the backend is currently initialized and ready for inference.
  bool get isReady;

  /// Initializes the model from a local file [path].
  Future<int> modelLoad(String path, ModelParams params);

  /// Initializes the model from a remote [url].
  ///
  /// [onProgress] receives load fractions as notifications. Its return value
  /// is ignored; it cannot cancel loading.
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    void Function(double progress)? onProgress,
  });

  /// Releases the allocated [modelHandle].
  Future<void> modelFree(int modelHandle);

  /// Creates a new inference context for the given [modelHandle].
  Future<int> contextCreate(int modelHandle, ModelParams params);

  /// Releases the allocated [contextHandle].
  Future<void> contextFree(int contextHandle);

  /// Returns the actual context size used by the given [contextHandle].
  Future<int> getContextSize(int contextHandle);

  /// Generates a stream of token bytes for a given prompt and context.
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  });

  /// Immediately cancels the current generation.
  void cancelGeneration();

  /// Encodes the given [text] into a list of token IDs.
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  });

  /// Decodes a list of [tokens] back into a human-readable string.
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  });

  /// Retrieves all available metadata from the loaded model.
  Future<Map<String, String>> modelMetadata(int modelHandle);

  /// Returns the name of the active runtime backend.
  Future<String> getBackendName();

  /// Whether this backend supports loading from URLs directly (e.g. WASM).
  ///
  /// Backends that support this (like Web) will handle URL-based model loading
  /// natively, while others may require the engine to download the file first.
  bool get supportsUrlLoading;

  /// Returns true if the hardware and backend support GPU acceleration.
  Future<bool> isGpuSupported();

  /// Updates the minimum log level for the backend.
  Future<void> setLogLevel(LlamaLogLevel level);

  /// Releases all allocated backend resources.
  Future<void> dispose();

  /// Returns the total and free VRAM in bytes.
  Future<({int total, int free})> getVramInfo();

  /// Applies the model's chat template to the given [messages].
  ///
  /// If [customTemplate] is provided, even empty, it will be used instead of
  /// the model's default template; otherwise [ModelParams.chatTemplate] from
  /// the load is used when non-empty on llama.cpp, and even when empty on
  /// native LiteRT-LM.
  ///
  /// The WebGPU backend cannot render either and throws
  /// `LlamaUnsupportedException`. LiteRT-LM Web's original constructor returns
  /// the last message's text, ignores its load template and an empty custom
  /// override, and rejects a non-empty override with `UnsupportedError`.
  /// Its explicit text-history factory accepts one user text message here and
  /// rejects overrides with `LlamaUnsupportedException`; use high-level chat
  /// for ordered structured history on that path.
  /// `LlamaEngine.chatTemplate` renders both on every backend.
  ///
  /// Returns the formatted prompt string.
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  });
}

/// Optional backend capability for runtime LoRA adapters.
///
/// `LlamaEngine` LoRA calls throw [LlamaUnsupportedException] on a backend
/// without it. A backend whose support depends on its runtime, such as the
/// loaded bridge assets or a routed delegate, implements it and throws
/// [LlamaUnsupportedException] or [UnsupportedError] from a call that runtime
/// cannot run.
abstract class BackendLoraSupport {
  /// Applies the LoRA adapter at [path] with [scale], or changes the scale of
  /// one already applied from [path].
  Future<void> setLoraAdapter(int contextHandle, String path, double scale);

  /// Stops applying the LoRA adapter at [path].
  Future<void> removeLoraAdapter(int contextHandle, String path);

  /// Stops applying every LoRA adapter of [contextHandle].
  Future<void> clearLoraAdapters(int contextHandle);
}

/// Optional backend capability for multimodal projectors.
///
/// `LlamaEngine` projector loads throw [LlamaUnsupportedException] on a
/// backend without it, and the engine reports vision and audio input from
/// [BackendDirectMediaInput] alone. A backend whose support depends on its
/// runtime implements it and throws [LlamaUnsupportedException] or
/// [UnsupportedError] from a call that runtime cannot run.
abstract class BackendMultimodalSupport {
  /// Loads the multimodal projector at [mmProjPath] for [modelHandle] and
  /// returns its handle.
  Future<int?> multimodalContextCreate(int modelHandle, String mmProjPath);

  /// Frees the projector [mmContextHandle].
  Future<void> multimodalContextFree(int mmContextHandle);

  /// Whether the projector [mmContextHandle] takes image input.
  ///
  /// Throws [LlamaUnsupportedException] when the runtime cannot run the probe,
  /// as for a native llama.cpp runtime without the mtmd functions.
  Future<bool> supportsVision(int mmContextHandle);

  /// Whether the projector [mmContextHandle] takes audio input.
  ///
  /// Throws [LlamaUnsupportedException] when the runtime cannot run the probe,
  /// as for a native llama.cpp runtime without the mtmd functions.
  Future<bool> supportsAudio(int mmContextHandle);
}

/// Optional backend capability for exposing selectable backend options.
abstract class BackendAvailability {
  /// Returns backend options available for user selection.
  Future<String> getAvailableBackends();
}

/// Optional backend capability for reporting grammar-constrained decoding.
///
/// Backends that do not support llama.cpp-style GBNF grammar constraints can
/// implement this so high-level chat rendering keeps prompt/parser behavior
/// while avoiding unsupported grammar parameters.
abstract class BackendGrammarConstraintsSupport {
  /// Whether [GenerationParams.grammar] and related grammar fields are supported.
  bool get supportsGrammarConstraints;
}

/// Optional backend capability for reporting lazy grammar activation.
///
/// A grammar-capable backend that implements this with `false` applies
/// [GenerationParams.grammar] from the first token and rejects
/// [GenerationParams.grammarLazy]. `LlamaEngine.create` then skips a lazy
/// template grammar for [ToolChoice.auto] and parses tool calls best-effort,
/// and throws `LlamaUnsupportedException` when a request needs that grammar.
abstract class BackendLazyGrammarSupport {
  /// Whether [GenerationParams.grammarLazy] and its triggers are supported.
  bool get supportsLazyGrammar;
}

/// Optional generation route that preserves prompt penalties under a grammar.
///
/// New LFM2 Python-auto grammars use this route to retain the sampling behavior
/// of the previously unconstrained prompt. Ordinary explicit grammars retain
/// [LlamaBackend.generate] semantics. A routed/runtime-dependent backend must
/// report its actual loaded delegate's support rather than interface presence.
/// High-level LFM2 auto uses this rendered route even when native chat is also
/// available; a backend requiring structured chat cannot admit that combination.
abstract class BackendPromptPenaltyGeneration {
  /// Whether [generateWithPromptPenalties] retains prompt tokens in the
  /// repetition/presence window, even with an attached grammar.
  bool get supportsPromptPenaltiesWithGrammar;

  /// Generates with prompt penalties without feeding the prompt to a grammar.
  ///
  /// [mediaMarker], when supplied, has [BackendChatPromptGeneration] semantics.
  /// An unsupported runtime throws [LlamaUnsupportedException] before inference.
  Stream<List<int>> generateWithPromptPenalties(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    String? mediaMarker,
    List<LlamaContentPart>? parts,
  });
}

final Expando<bool> _promptExcludedFromPenalties = Expando<bool>(
  'llamadart.promptExcludedFromPenalties',
);

/// Marks [params] of a request whose lazy grammar the engine dropped because
/// the backend cannot apply one.
///
/// llama.cpp keeps the prompt out of the repetition and presence penalty
/// window while a lazy grammar is set. A backend that would otherwise count
/// the prompt keeps it out for marked params, so its output matches native for
/// the same seed. Internal engine plumbing, not part of the backend SPI.
void markPromptExcludedFromPenalties(GenerationParams params) {
  _promptExcludedFromPenalties[params] = true;
}

/// Whether [markPromptExcludedFromPenalties] marked [params].
bool isPromptExcludedFromPenalties(GenerationParams params) =>
    _promptExcludedFromPenalties[params] ?? false;

/// Optional, bounded JSON-Schema text-chat capability, separate from GBNF.
///
/// Admission may initialize the loaded model and must construct its provider;
/// symbol presence alone is not model support. The route accepts the JSON
/// Schema subset that both the llama.cpp GBNF converter and the native
/// provider enforce, and refuses anything else before generation. Tools,
/// media, caller stops and speculative decoding are excluded; thinking is
/// excluded unless the backend also implements
/// [BackendJsonSchemaThinkingChatGeneration] and admits it for the model.
abstract class BackendJsonSchemaChatGeneration {
  /// True only after successful provider admission for the loaded model.
  bool get supportsJsonSchemaChatGeneration;

  /// Admits the loaded model or throws a typed unsupported/runtime error.
  Future<void> prepareJsonSchemaChat();

  /// Streams schema-constrained text chat with thinking explicitly disabled.
  Stream<List<int>> generateChatWithJsonSchema(
    int contextHandle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    required Map<String, dynamic> jsonSchema,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  });
}

/// Optional [BackendJsonSchemaChatGeneration] extension for models qualified
/// to reason before their schema-constrained reply.
///
/// The constraint applies after the reasoning channel closes. A model whose
/// family is not qualified keeps [supportsJsonSchemaChatThinking] false, and
/// a request with thinking is refused before generation.
abstract class BackendJsonSchemaThinkingChatGeneration
    implements BackendJsonSchemaChatGeneration {
  /// True only after [prepareJsonSchemaChat] admitted a model qualified to
  /// reason before its schema-constrained reply.
  bool get supportsJsonSchemaChatThinking;

  /// Streams the model's reasoning, then its schema-constrained reply.
  Stream<List<int>> generateChatWithJsonSchemaAndThinking(
    int contextHandle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    required Map<String, dynamic> jsonSchema,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  });
}

/// Optional backend capability for native structured chat generation.
///
/// Backends that implement this can receive chat messages and tools directly
/// instead of only receiving the already-rendered prompt string. Callers should
/// check [supportsNativeChatGeneration] before invoking [generateChat].
abstract class BackendNativeChatGeneration {
  /// Whether the active backend/runtime can use native structured chat input.
  bool get supportsNativeChatGeneration;

  /// Generates from structured chat state.
  ///
  /// The deprecated `sourceLangCode` and `targetLangCode` set the
  /// `source_lang_code` and `target_lang_code` keys of [chatTemplateKwargs].
  Stream<List<int>> generateChat(
    int contextHandle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    List<ToolDefinition>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? chatTemplateKwargs,
    @Deprecated("Use chatTemplateKwargs: {'source_lang_code': ...} instead.")
    String? sourceLangCode,
    @Deprecated("Use chatTemplateKwargs: {'target_lang_code': ...} instead.")
    String? targetLangCode,
    DateTime? templateNow,
  });
}

/// Internal validation before Dart template rendering reads message roles.
abstract class BackendChatMessageValidation {
  /// Whether this runtime must validate chat rather than fall back to a string.
  bool get requiresStructuredChatInput;

  /// Rejects messages the structured runtime cannot represent.
  void validateChatMessages(List<LlamaChatMessage> messages);
}

/// Optional backend capability for backends whose worker isolate keeps its
/// own Dart logger and forwards its records to the main isolate.
abstract class BackendDartLogLevel {
  /// Sets the level the worker's Dart logger forwards from.
  ///
  /// Does nothing while no worker is running; a worker takes the main
  /// isolate's logger level when it starts.
  Future<void> setDartLogLevel(LlamaLogLevel level);
}

/// Optional backend capability for exposing resolved runtime diagnostics.
abstract class BackendRuntimeDiagnostics {
  /// Returns resolved GPU layers used for the active model load.
  ///
  /// Meaning is backend-specific. For llama.cpp this is the final layer count
  /// after device selection and fallback, including 0 for forced CPU fallback;
  /// mainGpu and per-device layer allocation determine where offload occurs.
  /// LiteRT-LM reports 0 for CPU and the requested maximum for other backends,
  /// rather than a measured per-device allocation.
  Future<int?> getResolvedGpuLayers();
}

/// Optional backend capability for reporting deferred native engine creation.
///
/// A backend that defers creation returns from [LlamaBackend.modelLoad] and
/// [LlamaBackend.contextCreate] before the native engine exists and creates it
/// on the first operation that needs it, so engine creation failures surface
/// there instead of during load.
abstract class BackendDeferredEngineCreation {
  /// Whether native engine creation happens after model load and context
  /// creation.
  bool get defersEngineCreation;
}

/// Optional backend capability for prompt-adapted speech recognition.
///
/// Web runtimes use this explicit opt-in to distinguish a bridge release that
/// has passed the speech-to-text cancellation and audio-ingestion contract
/// from an older bridge that merely reports generic audio support.
abstract class BackendPromptSpeechToTextSupport {
  /// Whether the active runtime is validated for prompt-adapted speech-to-text.
  bool get supportsPromptSpeechToText;

  /// Actionable reason when [supportsPromptSpeechToText] is false.
  String? get promptSpeechToTextUnsupportedReason;
}

/// Internal backend probe for the loaded projector's native video runtime.
///
/// A true result only establishes that the native mtmd build and projector
/// report video support. It does not make video publicly consumable until the
/// Dart frame-ingestion and lifetime contract is implemented.
abstract class BackendVideoRuntimeSupport {
  /// Whether the loaded native mtmd context reports compiled video support.
  ///
  /// Returns null when the selected delegate does not expose a native mtmd
  /// video probe.
  Future<bool?> supportsVideoRuntime(int mmContextHandle);
}

/// Token limit that ended a generation before the model finished.
enum BackendGenerationLimit {
  /// The generation produced [GenerationParams.maxTokens] tokens.
  maxTokens,

  /// The prompt and generated tokens filled the context.
  contextSize,

  /// The runtime reported a limit without distinguishing its cause.
  ///
  /// This may be an output-token, context, or runtime-specific media limit.
  runtime,
}

/// Optional declaration that a runtime cannot reliably report generation limits.
///
/// Automatic tool loops reject runtimes that declare an unsupported reason,
/// because truncation must not execute an incomplete set of tool calls.
abstract class BackendGenerationLimitSupport {
  /// Why the active runtime cannot distinguish normal completion from a limit.
  ///
  /// Null means no unsupported declaration. Backends without this optional
  /// interface retain their existing behavior; absence does not prove support.
  String? get generationLimitUnsupportedReason;
}

/// Internal backend probe for the limit that ended a generation stream.
abstract class BackendGenerationLimitReporting {
  /// The limit that ended [generation], a stream this backend returned from
  /// `generate`.
  ///
  /// Returns null while [generation] is still open, when it ended at an
  /// end-of-generation token, a stop sequence, cancellation or an error, or
  /// when the backend cannot tell.
  BackendGenerationLimit? generationLimitOf(Stream<List<int>> generation);
}

final Expando<BackendGenerationLimitReporting> _generationLimitReporters =
    Expando<BackendGenerationLimitReporting>();

/// Makes [reporter] report the generation limits of [backend].
///
/// For an exported backend class, which must not expose the internal
/// [BackendGenerationLimitReporting] in its type.
void registerGenerationLimitReporter(
  Object backend,
  BackendGenerationLimitReporting reporter,
) {
  _generationLimitReporters[backend] = reporter;
}

/// The generation-limit reporter of [backend]: the backend itself when it
/// implements [BackendGenerationLimitReporting], otherwise one registered
/// with [registerGenerationLimitReporter], or null.
BackendGenerationLimitReporting? generationLimitReporterOf(Object? backend) =>
    backend == null
    ? null
    : backend is BackendGenerationLimitReporting
    ? backend
    : _generationLimitReporters[backend];

/// Internal backend probe for tool calls a runtime parsed itself.
///
/// The calls reach the engine beside the stream rather than as text, so the
/// reply text around them stays content and no output parser can drop them.
abstract class BackendRuntimeToolCalls {
  /// The calls the runtime parsed while it produced [generation], a stream
  /// this backend returned from `generateChat`, in order.
  ///
  /// Null while [generation] is open, or when the runtime parsed none.
  List<LlamaCompletionChunkToolCall>? runtimeToolCallsOf(
    Stream<List<int>> generation,
  );
}

final Expando<BackendRuntimeToolCalls> _runtimeToolCallReporters =
    Expando<BackendRuntimeToolCalls>();

/// Makes [reporter] report the runtime-parsed tool calls of [backend].
///
/// For an exported backend class, which must not expose the internal
/// [BackendRuntimeToolCalls] in its type.
void registerRuntimeToolCallReporter(
  Object backend,
  BackendRuntimeToolCalls reporter,
) {
  _runtimeToolCallReporters[backend] = reporter;
}

/// The runtime tool-call reporter of [backend]: the backend itself when it
/// implements [BackendRuntimeToolCalls], otherwise one registered with
/// [registerRuntimeToolCallReporter], or null.
BackendRuntimeToolCalls? runtimeToolCallReporterOf(Object? backend) =>
    backend == null
    ? null
    : backend is BackendRuntimeToolCalls
    ? backend
    : _runtimeToolCallReporters[backend];

/// Internal backend probe for the tokens a runtime prefills for a prompt it
/// renders from its own chat template.
abstract class BackendRuntimePromptTokenization {
  /// The tokens the runtime prefills for [prompt]. Unlike
  /// `tokenize(prompt, addSpecial: false)`, a start token the runtime adds
  /// before every prompt is counted once, also when [prompt] begins with its
  /// text.
  Future<List<int>> tokenizeRuntimePrompt(int modelHandle, String prompt);
}

final Expando<BackendRuntimePromptTokenization> _runtimePromptTokenizers =
    Expando<BackendRuntimePromptTokenization>();

/// Makes [tokenizer] tokenize the runtime prompts of [backend].
///
/// For an exported backend class, which must not expose the internal
/// [BackendRuntimePromptTokenization] in its type.
void registerRuntimePromptTokenizer(
  Object backend,
  BackendRuntimePromptTokenization tokenizer,
) {
  _runtimePromptTokenizers[backend] = tokenizer;
}

/// The runtime prompt tokenizer of [backend]: the backend itself when it
/// implements [BackendRuntimePromptTokenization], otherwise one registered
/// with [registerRuntimePromptTokenizer], or null.
BackendRuntimePromptTokenization? runtimePromptTokenizerOf(Object? backend) =>
    backend == null
    ? null
    : backend is BackendRuntimePromptTokenization
    ? backend
    : _runtimePromptTokenizers[backend];

/// Optional backend capability for naming the runtime that runs the loaded
/// model.
///
/// `LlamaEngine.runtime` reports [runtime], and the engine applies that
/// runtime's rules: a backend that reports [LlamaRuntime.liteRtLm] is held to
/// LiteRT-LM limits such as having no external speculative draft model. A
/// backend without this interface reports no runtime.
abstract class BackendRuntimeIdentity {
  /// The runtime that runs this backend's model, or null when the backend
  /// cannot tell, as for an auto backend with no model loaded.
  LlamaRuntime? get runtime;
}

/// Optional backend capability for a prompt that `LlamaEngine.create`
/// rendered from chat messages with media parts, as opposed to a prompt the
/// caller of `LlamaEngine.generate` wrote.
///
/// A backend that reads media placeholders in the prompt of
/// [LlamaBackend.generate] (`<__media__>`, `<image>`, `<img>` and the like)
/// would also read one that a chat message only quotes. With this interface
/// the engine hands such a backend the rendered prompt apart from a caller's.
/// Without it the engine passes the prompt to [LlamaBackend.generate] with
/// `<__media__>` where each part was and a zero-width space (U+200B) after
/// the first character of every other placeholder string.
abstract class BackendChatPromptGeneration {
  /// Generates like [LlamaBackend.generate] from the chat-rendered [prompt].
  ///
  /// [mediaMarker] stands in [prompt] once for each image or audio part of
  /// [parts], in order, where that part was in its message. It is a random
  /// string, drawn once for the isolate, that message text does not hold.
  /// Everything else in [prompt] is template or message text: the backend
  /// must not rewrite a placeholder in it or read it as media.
  Stream<List<int>> generateChatPrompt(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    required String mediaMarker,
    List<LlamaContentPart>? parts,
  });
}

/// Optional backend capability for media the loaded model takes directly,
/// without a multimodal projector.
///
/// `LlamaEngine.capabilities` reports vision or audio support when either
/// this interface or the loaded projector does.
abstract class BackendDirectMediaInput {
  /// Whether the loaded model takes image and audio content parts directly.
  ///
  /// Both are false when no model is loaded or the backend cannot tell.
  Future<({bool vision, bool audio})> directMediaInput();
}

/// Optional backend capability for media in `LlamaToolResultContent.content`.
///
/// The backend takes each such part at its marker in the prompt that
/// `LlamaEngine.create` renders, in the order the parts were passed, through
/// [BackendChatPromptGeneration] or [LlamaBackend.generate]. The engine
/// reports a type in `LlamaEngineCapabilities.toolResultMedia`, and accepts
/// a request carrying it, only when [toolResultMedia] has it and the loaded
/// projector takes that media. Without this interface, tool-result media
/// throw [LlamaUnsupportedException].
abstract class BackendToolResultMedia {
  /// The media types the backend places at a tool result's markers; empty
  /// when it places none, as when no model is loaded.
  Set<LlamaToolResultMedia> get toolResultMedia;
}

/// Optional backend capability for how much of a chat request the loaded
/// runtime passes to the model. A backend that does not implement this passes
/// all of it.
///
/// `LlamaEngine.capabilities` reports these values.
abstract class BackendChatScope {
  /// Whether the model sees the whole conversation, not only the latest
  /// message.
  bool get supportsMultiTurnChat;

  /// Whether the model sees the request's tools.
  bool get supportsToolCalling;
}

/// Optional backend capability for loading a model in an explicitly chosen
/// [ModelFormat] instead of the format the backend would detect.
///
/// The engine calls these methods to load a source whose `ModelSource.format`
/// is set. A backend without this interface loads only the format of the
/// runtime that [BackendRuntimeIdentity] reports; any other format throws
/// [LlamaUnsupportedException].
abstract class BackendModelFormatRouting {
  /// Loads the local model at [path] as [format].
  Future<int> modelLoadAs(String path, ModelParams params, ModelFormat format);

  /// Loads the model at [url] as [format].
  Future<int> modelLoadFromUrlAs(
    String url,
    ModelParams params,
    ModelFormat format, {
    void Function(double progress)? onProgress,
  });
}

/// Internal backend probe for the format a [BackendModelFormatRouting]
/// backend detects in a local model file, where the file rather than its
/// name or a declared format picks the runtime.
abstract class BackendModelFormatDetection {
  /// The format read from the local model file at [path], or null when the
  /// file cannot be read or matches no [ModelFormat].
  Future<ModelFormat?> detectModelFormat(String path);
}

/// Optional backend capability that checks a model load before any model
/// file resolves or downloads.
///
/// `LlamaEngine.setModel` throws what [checkLoad] throws before it resolves
/// a file, and `LlamaEngine.checkLoad` reports the same outcome without
/// loading. For a backend without this interface, `LlamaEngine.checkLoad`
/// reports `LlamaLoadCheckStatus.unknown` once it knows the format.
abstract class BackendLoadCheck {
  /// Throws [LlamaUnsupportedException] when loading a model in [format] with
  /// [params] would ignore an explicitly set field, or needs a runtime or
  /// device this platform lacks; the message names the missing capability
  /// and the platform or runtime condition.
  ///
  /// [format] is null when only the model file can tell it; the backend then
  /// checks again when it loads the file, and the engine ignores the result.
  /// Otherwise returns null when the backend checked the load, or why it
  /// cannot tell before loading, such as a runtime it did not build. Must not
  /// start a runtime or read a file.
  String? checkLoad(ModelParams params, ModelFormat? format);
}

/// Internal backend probe for the usage of a finished generation stream.
abstract class BackendGenerationUsageReporting {
  /// The usage of [generation], a stream this backend returned from
  /// `generate`.
  ///
  /// Returns null while [generation] is still open, when it ended with an
  /// error, or when the backend cannot report usage.
  LlamaGenerationUsage? generationUsageOf(Stream<List<int>> generation);
}

/// Model family reported by a backend text-to-speech implementation.
enum BackendTextToSpeechModel {
  /// Qwen3-TTS audio generation through llama.cpp mtmd.
  qwen3Tts,

  /// LFM3-Audio and LFM3-Omni speech output through llama.cpp mtmd.
  lfm3Audio,

  /// Soprano speech output through llama.cpp mtmd.
  soprano,

  /// Chatterbox Turbo and Chatterbox Multilingual through llama.cpp mtmd.
  chatterbox,

  /// Pocket TTS through llama.cpp mtmd.
  pocketTts,
}

/// Phase reported while a backend synthesizes speech.
enum BackendTextToSpeechPhase {
  /// The backend is processing the text and optional speaker prompt.
  processingPrompt,

  /// The backend is generating audio-codec frames.
  generating,
}

/// Runtime capabilities for an optional backend text-to-speech path.
class BackendTextToSpeechCapabilities {
  /// Whether synthesis is available for the loaded model and projector.
  final bool isSupported;

  /// Actionable reason when [isSupported] is false.
  final String? unsupportedReason;

  /// Model family recognized by the backend.
  final BackendTextToSpeechModel? model;

  /// Output sample rate in Hertz.
  final int? sampleRateHz;

  /// Number of interleaved output channels.
  final int? channelCount;

  /// Whether a language hint can be supplied.
  final bool supportsLanguage;

  /// Whether encoded reference-speaker audio can be supplied.
  final bool supportsSpeakerReference;

  /// Whether an active synthesis can be cancelled cooperatively.
  final bool supportsCancellation;

  /// Whether a predefined voice can be selected by name.
  final bool supportsVoice;

  /// The predefined voices, in the model's order; the first one speaks when
  /// a request names none.
  ///
  /// Empty when the model has no voices or the backend cannot list them.
  final List<String> voices;

  /// Creates a backend capability snapshot.
  const BackendTextToSpeechCapabilities({
    required this.isSupported,
    this.unsupportedReason,
    this.model,
    this.sampleRateHz,
    this.channelCount,
    this.supportsLanguage = false,
    this.supportsSpeakerReference = false,
    this.supportsCancellation = false,
    this.supportsVoice = false,
    this.voices = const <String>[],
  });
}

/// Sampling and input values passed to a backend TTS implementation.
class BackendTextToSpeechRequest {
  /// Text to synthesize.
  final String text;

  /// Optional language name or code accepted by the loaded model.
  final String? language;

  /// Optional local encoded reference-audio path.
  final String? speakerAudioPath;

  /// Optional encoded reference-audio bytes.
  final Uint8List? speakerAudioBytes;

  /// Optional predefined voice name, or null for the model's default.
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
  final double temperature;

  /// Random seed.
  final int seed;

  /// Creates a backend synthesis request.
  const BackendTextToSpeechRequest({
    required this.text,
    this.language,
    this.speakerAudioPath,
    this.speakerAudioBytes,
    this.voice,
    this.maxFrames = 512,
    this.promptBatchSize = 512,
    this.topK = 40,
    this.topP = 0.95,
    this.minP = 0.0,
    this.temperature = 0.8,
    this.seed = 0xffffffff,
  });
}

/// Progress reported by a backend TTS implementation.
class BackendTextToSpeechProgress {
  /// Current synthesis phase.
  final BackendTextToSpeechPhase phase;

  /// Prompt tokens that have not yet been evaluated.
  final int promptTokensRemaining;

  /// Audio-codec frames generated so far.
  final int framesGenerated;

  /// Whether generation reached the requested frame limit.
  final bool truncated;

  /// Creates a progress snapshot.
  const BackendTextToSpeechProgress({
    required this.phase,
    required this.promptTokensRemaining,
    required this.framesGenerated,
    required this.truncated,
  });
}

/// Complete PCM output returned by a backend TTS implementation.
class BackendTextToSpeechResult {
  /// Interleaved normalized float32 PCM samples.
  final Float32List samples;

  /// Output sample rate in Hertz.
  final int sampleRateHz;

  /// Number of interleaved output channels.
  final int channelCount;

  /// Number of audio-codec frames generated.
  final int framesGenerated;

  /// Whether generation reached the requested frame limit.
  final bool truncated;

  /// Creates a backend synthesis result.
  const BackendTextToSpeechResult({
    required this.samples,
    required this.sampleRateHz,
    required this.channelCount,
    required this.framesGenerated,
    required this.truncated,
  });
}

/// Optional backend probe for the text-to-speech models its runtime drives,
/// answered before a model loads.
///
/// `TextToSpeechEngine.load` asks it for the models its adapter accepts and
/// refuses the load when the runtime drives none of them, before downloading
/// or loading any file.
abstract class BackendTextToSpeechModelSupport {
  /// Why the runtime cannot drive [model], or null when it can or cannot tell
  /// without a loaded model. Must not load a model.
  Future<String?> textToSpeechModelUnsupportedReason(
    BackendTextToSpeechModel model,
  );
}

/// Optional backend capability for dedicated text-to-speech synthesis.
abstract class BackendTextToSpeech {
  /// Discovers support for the loaded context and multimodal projector.
  Future<BackendTextToSpeechCapabilities> textToSpeechCapabilities(
    int contextHandle,
    int mmContextHandle,
  );

  /// Synthesizes one complete utterance.
  ///
  /// Current implementations return PCM only after generation has completed.
  /// [onProgress] does not imply incremental audio output.
  Future<BackendTextToSpeechResult> synthesizeTextToSpeech(
    int contextHandle,
    int mmContextHandle,
    BackendTextToSpeechRequest request, {
    void Function(BackendTextToSpeechProgress progress)? onProgress,
  });

  /// Cooperatively cancels the active synthesis, if any.
  void cancelTextToSpeech();
}

/// Optional [GenerationParams] controls that the loaded model's runtime
/// applies.
///
/// Through `LlamaEngine`, the built-in runtimes reject a non-default value of
/// a control they report `false`, except [streamBatching], whose thresholds
/// WebGPU ignores.
class BackendGenerationCapabilities {
  /// Whether a [GenerationParams.penalty] other than its default is applied.
  ///
  /// Defaults to `false` so a backend that predates this field does not
  /// claim it.
  final bool penalty;

  /// Whether a non-zero [GenerationParams.presencePenalty] is applied.
  final bool presencePenalty;

  /// Whether a non-zero [GenerationParams.minP] is applied.
  final bool minP;

  /// Whether [GenerationParams.thinkingBudget] is applied.
  ///
  /// A runtime that applies it can still reject it for generation with media
  /// parts or speculative decoding.
  final bool thinkingBudget;

  /// The strategies that [GenerationParams.speculativeDecodingConfig] can use.
  ///
  /// [SpeculativeDecodingStrategy.backendDefault] also stands for the
  /// [GenerationParams.speculativeDecoding] flag. Speculative decoding with a
  /// strategy outside this set is rejected. A runtime can still reject a
  /// request that uses only these strategies, such as one that combines
  /// strategies, sets a tuning field or draft model the runtime does not take,
  /// names a draft model that does not fit the strategy, or has media parts, a
  /// grammar or a thinking budget.
  final Set<SpeculativeDecodingStrategy> speculativeDecodingStrategies;

  /// Whether [GenerationParams.streamBatchTokenThreshold] and
  /// [GenerationParams.streamBatchByteThreshold] are applied.
  ///
  /// Defaults to `false` so a backend that predates this field does not
  /// claim it.
  final bool streamBatching;

  /// Creates a capability snapshot.
  const BackendGenerationCapabilities({
    required this.presencePenalty,
    required this.minP,
    required this.thinkingBudget,
    this.speculativeDecodingStrategies = const <SpeculativeDecodingStrategy>{},
    this.penalty = false,
    this.streamBatching = false,
  });
}

/// Optional backend capability reporting [BackendGenerationCapabilities].
///
/// `LlamaEngine.backendGenerationCapabilities` reports no control as applied
/// for a backend that does not implement this.
abstract class BackendGenerationCapabilitiesSupport {
  /// Reports the controls that the loaded model's runtime applies.
  Future<BackendGenerationCapabilities> generationCapabilities();
}

/// Runtime support for an optional backend decision-model path.
class BackendDecisionCapabilities {
  /// Whether decision heads can run on the loaded model.
  final bool isSupported;

  /// Actionable reason when [isSupported] is false.
  final String? unsupportedReason;

  /// Creates a backend capability snapshot.
  const BackendDecisionCapabilities({
    required this.isSupported,
    this.unsupportedReason,
  });
}

/// A decision head loaded by a backend.
class BackendDecisionHeadInfo {
  /// Handle of the head, valid with the API that returned it.
  final int handle;

  /// Hidden size shared by the encoder and the head.
  final int hiddenSize;

  /// Token that starts every sequence.
  final int clsToken;

  /// Token that separates sequence parts.
  final int sepToken;

  /// Token placed before each option.
  final int maskToken;

  /// Text of [maskToken].
  final String maskText;

  /// The head's configuration as JSON text (Laya `rl_agent_config.json`).
  final String configJson;

  /// Name of the device the head runs on.
  final String deviceName;

  /// Creates a head description.
  const BackendDecisionHeadInfo({
    required this.handle,
    required this.hiddenSize,
    required this.clsToken,
    required this.sepToken,
    required this.maskToken,
    required this.maskText,
    required this.configJson,
    required this.deviceName,
  });
}

/// Encoder input for one question.
class BackendDecisionSequence {
  /// Token ids.
  final Int32List tokens;

  /// Position in [tokens] of each option's mask token.
  final Int32List markers;

  /// Type of the question the sequence asks.
  final DecisionQuestionType questionType;

  /// Creates an encoder input.
  const BackendDecisionSequence({
    required this.tokens,
    required this.markers,
    required this.questionType,
  });
}

/// Raw head outputs for one sequence.
class BackendDecisionOutput {
  /// One logit per marker, before temperature scaling.
  final Float32List logits;

  /// Action-head logits.
  final Float32List actLogits;

  /// Creates head outputs.
  const BackendDecisionOutput({required this.logits, required this.actLogits});
}

/// Optional backend capability for encoder-plus-head decision models.
abstract class BackendDecision {
  /// Reports whether the model [modelHandle] can run decision heads.
  Future<BackendDecisionCapabilities> decisionCapabilities(int modelHandle);

  /// Loads the head at [headPath] for the model [modelHandle].
  ///
  /// [configPath] names a JSON config for head files without `laya.config`
  /// metadata.
  Future<BackendDecisionHeadInfo> decisionHeadLoad(
    int modelHandle,
    String headPath, {
    String? configPath,
  });

  /// Runs [sequences] through the encoder and head, in order.
  Future<List<BackendDecisionOutput>> decisionRun(
    int headHandle,
    List<BackendDecisionSequence> sequences,
  );

  /// Frees the head [headHandle]; unknown handles are ignored.
  Future<void> decisionHeadFree(int headHandle);
}

/// Optional backend capability for exposing loaded model file type metadata.
///
/// Backends that can identify the loaded model's native file type or
/// quantization format return a [ModelFileType]. Backends that do not expose
/// this data should omit this capability so high-level APIs return null.
abstract class BackendModelFileTypeDiagnostics {
  /// Returns file type metadata for [modelHandle], or null when unavailable.
  Future<ModelFileType?> getModelFileType(int modelHandle);
}

/// Optional backend capability for enumerating GPU-class devices for offload
/// selection (e.g. pinning to the discrete GPU on a laptop, or surfacing which
/// device is in use).
abstract class BackendGpuEnumeration {
  /// Lists the GPU-class devices the backend exposes.
  ///
  /// With an empty [probeBackends] only already-registered backends are
  /// inspected — no backend module is loaded, so an unsupported GPU runtime
  /// cannot crash the process during enumeration. Pass specific backends in
  /// [probeBackends] to opt into loading just those modules (each guarded)
  /// before enumerating. Backends with no offload devices (and web/WebGPU)
  /// return an empty list.
  Future<List<GpuDeviceInfo>> listGpuDevices({
    List<GpuBackend> probeBackends = const [],
  });
}

/// Native performance timings reported by llama.cpp for the active context.
class BackendPerfContextData {
  /// Time spent loading the model in ms.
  final double loadMs;

  /// Time spent evaluating prompt tokens in ms.
  final double promptEvalMs;

  /// Time spent generating tokens in ms.
  final double evalMs;

  /// Time spent sampling generated tokens in ms.
  final double sampleMs;

  /// Time spent decoding generated tokens in ms, excluding prompt ingestion.
  ///
  /// Backends that do not expose a separate decode-only measurement leave this
  /// null. For llama.cpp, this is the Dart-side `llama_decode` time measured
  /// during generation.
  final double? decodeMs;

  /// Number of prompt tokens evaluated.
  final int promptEvalTokens;

  /// Number of generated tokens evaluated.
  final int evalTokens;

  /// Number of sampler steps recorded.
  final int sampleCount;

  /// Number of times compute graphs were reused.
  final int reusedGraphs;

  /// Number of speculative draft tokens proposed by the backend.
  final int? speculativeDraftTokens;

  /// Number of speculative draft tokens accepted by the backend.
  final int? speculativeAcceptedDraftTokens;

  /// Number of speculative draft attempts made by the backend.
  final int? speculativeDraftAttempts;

  /// Number of target-model tokens decoded to verify speculative drafts.
  final int? speculativeVerifyTokens;

  /// Number of target-model tokens decoded to replay accepted speculative work.
  final int? speculativeReplayTokens;

  /// Time spent generating speculative draft tokens in ms.
  final double? speculativeDraftMs;

  /// Time spent verifying speculative draft tokens in ms.
  final double? speculativeVerifyMs;

  /// Accepted speculative draft-token ratio, when available.
  double? get speculativeAcceptanceRate {
    final draftTokens = speculativeDraftTokens;
    final acceptedDraftTokens = speculativeAcceptedDraftTokens;
    if (draftTokens == null ||
        acceptedDraftTokens == null ||
        draftTokens <= 0) {
      return null;
    }
    return acceptedDraftTokens / draftTokens;
  }

  /// Creates a new [BackendPerfContextData].
  const BackendPerfContextData({
    required this.loadMs,
    required this.promptEvalMs,
    required this.evalMs,
    required this.sampleMs,
    this.decodeMs,
    required this.promptEvalTokens,
    required this.evalTokens,
    required this.sampleCount,
    required this.reusedGraphs,
    this.speculativeDraftTokens,
    this.speculativeAcceptedDraftTokens,
    this.speculativeDraftAttempts,
    this.speculativeVerifyTokens,
    this.speculativeReplayTokens,
    this.speculativeDraftMs,
    this.speculativeVerifyMs,
  });
}

/// Optional backend capability for exposing llama.cpp perf timings.
abstract class BackendPerformanceDiagnostics {
  /// Returns current native perf timings for [contextHandle] when available.
  Future<BackendPerfContextData?> getPerformanceContext(int contextHandle);
}

/// Optional backend capability for generating text embeddings.
abstract class BackendEmbeddings {
  /// Generates a single embedding vector for [text].
  ///
  /// When [normalize] is true, the backend returns an L2-normalized vector.
  Future<List<double>> embed(
    int contextHandle,
    String text, {
    bool normalize = true,
  });
}

/// Optional backend capability for reporting whether [BackendEmbeddings] is
/// actually available for the active runtime.
///
/// This is useful for delegating/router backends where the wrapper may expose
/// embedding methods but support depends on the selected concrete backend.
/// Backends that do not implement this interface fall back to the structural
/// `is BackendEmbeddings` check used by older versions.
abstract class BackendEmbeddingsSupport {
  /// Whether embedding calls are expected to be supported by this backend.
  bool get supportsEmbeddings;
}

/// Optional backend contract for ordered multimodal embeddings.
///
/// Implementations probe the loaded context explicitly. Merely implementing
/// this interface does not imply media support.
abstract class BackendMultimodalEmbeddings {
  /// Probes model, projector/processors and runtime support for this context.
  ///
  /// Unloaded contexts return all-false without I/O.
  /// Unknown or absent ABI/features must report false, or throw a typed
  /// unsupported exception. Generation's vision/audio flags are not evidence.
  Future<LlamaEmbeddingCapabilities> getEmbeddingCapabilities(
    int contextHandle,
  );

  /// Embeds ordered inputs, returning one vector per input in the same order.
  ///
  /// Preserve part order and media; never flatten a mixed request to text.
  /// Adjacent text parts form one verbatim-concatenated text segment on every
  /// backend, including within mixed inputs. LiteRT-LM adapters must merge
  /// adjacent text before building runtime inputs; no separators or templates are added.
  /// Validate modalities, part shapes and media sources/decoding across the
  /// entire batch before inference. Check expanded-token limits before inference
  /// when the runtime exposes counts (required for llama.cpp). Runtimes without
  /// a token-count API, such as LiteRT-LM, may detect overflow during the batch,
  /// but must fail the whole call with `LlamaInferenceException` and no vectors.
  /// Earlier items may consume wasted compute; never truncate or return partial results.
  /// Empty batches return no vectors. With [normalize], L2-normalize
  /// each pooled output. Otherwise return the full raw pooled vector.
  ///
  /// Cancellation uses [LlamaBackend.cancelGeneration], as for text embeddings.
  /// Keep native buffers alive until in-flight work settles, even on cancel.
  /// Unsupported combinations throw `LlamaUnsupportedException`; input/context
  /// capacity and execution failures throw `LlamaInferenceException`.
  Future<List<List<double>>> embedContentBatch(
    int contextHandle,
    List<LlamaEmbeddingInput> inputs, {
    bool normalize = true,
  });
}

/// Internal compatibility dispatch shared by the engine and runtime routers.
///
/// The public optional SPI is [BackendMultimodalEmbeddings]. Existing text
/// backends retain their historical support test, with media disabled.
extension BackendEmbeddingDispatch on LlamaBackend {
  /// Probes the active context or provides the legacy text-only default.
  Future<LlamaEmbeddingCapabilities> probeEmbeddingCapabilities(
    int contextHandle,
  ) async {
    final candidate = this;
    if (candidate is BackendMultimodalEmbeddings) {
      return (candidate as BackendMultimodalEmbeddings)
          .getEmbeddingCapabilities(contextHandle);
    }
    final text = candidate is BackendEmbeddingsSupport
        ? (candidate as BackendEmbeddingsSupport).supportsEmbeddings
        : candidate is BackendEmbeddings;
    return LlamaEmbeddingCapabilities(text: text);
  }

  /// Dispatches content without allowing a legacy backend to discard media.
  ///
  /// [onCompute] records context work only after preflight succeeds, so empty
  /// or unsupported requests cannot revive stale performance counters.
  Future<List<List<double>>> embedContentWithFallback(
    int contextHandle,
    List<LlamaEmbeddingInput> inputs, {
    bool normalize = true,
    Future<List<List<double>>> Function(
      Future<List<List<double>>> Function() compute,
    )?
    onCompute,
  }) async {
    if (inputs.isEmpty) return const <List<double>>[];
    final capabilities = await probeEmbeddingCapabilities(contextHandle);
    for (final input in inputs) {
      for (final kind in input.partKinds) {
        if (!capabilities.supports(kind)) {
          final runtime = this is BackendRuntimeIdentity
              ? (this as BackendRuntimeIdentity).runtime
              : null;
          if (kind != LlamaEmbeddingModality.text &&
              capabilities.mediaUnsupportedReason != null) {
            throw LlamaUnsupportedException(
              '${kind.name} embeddings are unavailable: ${capabilities.mediaUnsupportedReason!}',
            );
          }
          throw LlamaUnsupportedException(
            '${kind.name} embeddings are unavailable for the loaded model/runtime '
            '(${runtime?.name ?? 'unknown'}); the embedding capability probe '
            'did not enable ${kind.name}.',
          );
        }
      }
    }
    Future<List<List<double>>> compute() async {
      final candidate = this;
      if (candidate is BackendMultimodalEmbeddings) {
        return (candidate as BackendMultimodalEmbeddings).embedContentBatch(
          contextHandle,
          inputs,
          normalize: normalize,
        );
      }
      final texts = [
        for (final input in inputs)
          input.parts.cast<LlamaTextContent>().map((part) => part.text).join(),
      ];
      if (candidate is BackendBatchEmbeddings) {
        return (candidate as BackendBatchEmbeddings).embedBatch(
          contextHandle,
          texts,
          normalize: normalize,
        );
      }
      if (candidate is BackendEmbeddings) {
        return [
          for (final text in texts)
            await (candidate as BackendEmbeddings).embed(
              contextHandle,
              text,
              normalize: normalize,
            ),
        ];
      }
      throw LlamaUnsupportedException(
        'Text embeddings are unavailable: the loaded backend has no embedding implementation.',
      );
    }

    return onCompute == null ? compute() : onCompute(compute);
  }
}

/// Optional backend capability for batching text embedding requests.
abstract class BackendBatchEmbeddings extends BackendEmbeddings {
  /// Generates embedding vectors for all [texts] in order.
  ///
  /// When [normalize] is true, each returned vector is L2-normalized.
  Future<List<List<double>>> embedBatch(
    int contextHandle,
    List<String> texts, {
    bool normalize = true,
  });
}

/// Optional backend capability for scoring the token that would follow a
/// prompt, without sampling.
abstract class BackendNextTokenScoring {
  /// Evaluates [prompt] on [contextHandle] as generation would, then returns
  /// the log-probabilities of [candidates] and of the [topK] most probable
  /// tokens at the next position. [reusePromptPrefix] reuses a matching
  /// prompt prefix already in the context, as
  /// [GenerationParams.reusePromptPrefix] does.
  Future<LlamaNextTokenScores> scoreNextToken(
    int contextHandle,
    String prompt, {
    required List<int> candidates,
    required int topK,
    required bool reusePromptPrefix,
  });
}

/// Optional backend capability for reporting whether
/// [BackendNextTokenScoring] is actually available for the active runtime.
///
/// Delegating backends implement the scoring method whatever they delegate
/// to; this reports what the selected concrete backend supports.
abstract class BackendNextTokenScoringSupport {
  /// Whether next-token scoring calls are expected to be supported.
  bool get supportsNextTokenScoring;
}

/// Result of [BackendStatePersistence.stateLoadFile]. Contains the token
/// sequence saved alongside the native KV-cache state.
///
/// Loading restores the native KV cache only. Callers using higher-level
/// chat abstractions must persist and reconstruct their chat message
/// history separately; these raw token IDs are exposed mainly for
/// diagnostics and raw-prompt callers.
class StateLoadResult {
  /// The token IDs that the saved state was produced from.
  final List<int> tokens;

  /// Creates a new [StateLoadResult].
  const StateLoadResult({required this.tokens});
}

/// Optional backend capability for persisting the KV cache to disk and
/// restoring it later, mirroring `llama_state_save_file` /
/// `llama_state_load_file` in llama.cpp. Saving captures the native
/// runtime state of [contextHandle] together with the token sequence
/// that produced it. Loading restores the native KV cache and returns
/// the saved token sequence; subsequent inference can skip prompt
/// evaluation when callers re-issue a prompt with the restored token
/// prefix and prompt-prefix reuse enabled. This API does not guarantee an
/// exact logits, continuation or sampler/RNG checkpoint. Native
/// llama.cpp re-evaluates the final token for an exact saved-prompt match;
/// that batch shape can produce different scores from full-prompt evaluation.
abstract class BackendStatePersistence {
  /// Writes the KV cache state of [contextHandle] together with the
  /// token sequence in [tokens] to [path]. The file format is the one
  /// llama.cpp emits — opaque, version-tied, and not portable across
  /// llama.cpp builds.
  ///
  /// Returns true on success.
  Future<bool> stateSaveFile(int contextHandle, String path, List<int> tokens);

  /// Restores the KV cache of [contextHandle] from a file previously
  /// written by [stateSaveFile]. [tokenCapacity] caps how many tokens
  /// the caller is willing to receive — typically the context size of
  /// the loaded model. Throws if the file is corrupt or was produced
  /// by a different llama.cpp build.
  Future<StateLoadResult> stateLoadFile(
    int contextHandle,
    String path,
    int tokenCapacity,
  );
}

/// Optional backend capability for reporting whether
/// [BackendStatePersistence] is actually available for the active runtime.
///
/// This is useful for delegating/router backends where the wrapper may expose
/// the persistence methods but support depends on the selected concrete
/// backend. Backends that do not implement this interface fall back to the
/// structural `is BackendStatePersistence` check used by older versions.
abstract class BackendStatePersistenceSupport {
  /// Whether state save/load calls are expected to be supported by this backend.
  bool get supportsStatePersistence;
}

/// Optional backend capability for reporting the [LlamaStateIdentity] of the
/// state [BackendStatePersistence.stateSaveFile] writes.
///
/// Implement it only when the runtime can name its own build: an identity
/// without one cannot tell two runtimes apart. Throw [UnsupportedError] (or
/// [LlamaUnsupportedException]) when the active runtime cannot report one.
abstract class BackendStateIdentity {
  /// The identity of the state [contextHandle] saves and loads.
  Future<LlamaStateIdentity> stateIdentity(int contextHandle);
}

/// Optional native cross-encoder capability. Existing backends need not implement it.
abstract class BackendReranking {
  /// Creates a fresh explicit RANK context for the owning reranker loader.
  ///
  /// Verify a real classifier head and its output count first. Ordinary model
  /// loads retain their context configuration. The caller frees this context
  /// with [LlamaBackend.contextFree], including when preparation fails.
  Future<int> createRerankingContext(int modelHandle, ModelParams params);

  /// Probes the actual loaded context; interface presence is not evidence of support.
  Future<LlamaRerankingCapabilities> getRerankingCapabilities(
    int contextHandle,
  );

  /// Scores complete query/document pairs in input order, preserving all classes.
  ///
  /// Preflight the entire batch before inference, never truncate or return
  /// partial results, and use [LlamaBackend.cancelGeneration] for cancellation.
  /// Unsupported combinations throw [LlamaUnsupportedException]; overflow,
  /// cancellation and execution failures throw [LlamaInferenceException].
  Future<BackendRerankingOutput> rerank(
    int contextHandle,
    String query,
    List<String> documents,
  );
}

/// Native classifier outputs for one complete reranking request.
final class BackendRerankingOutput {
  /// Snapshots scores and labels; every row has one value per label.
  BackendRerankingOutput({
    required List<List<double>> scores,
    required List<String?> classifierLabels,
  }) : scores = List<List<double>>.unmodifiable(
         scores.map((row) => List<double>.unmodifiable(row)),
       ),
       classifierLabels = List<String?>.unmodifiable(classifierLabels);

  /// One complete classifier vector per input document, in input order.
  final List<List<double>> scores;

  /// Classifier labels in model order, null where absent.
  final List<String?> classifierLabels;
}
