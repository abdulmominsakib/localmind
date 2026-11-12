import '../models/inference/generation_params.dart';
import 'engine_observer.dart';

/// What an engine reports about its support: whether it can run, why not,
/// and the backend it runs on.
///
/// Every engine's `capabilities` is a `Future` of a subtype with its own
/// fields: [LlamaEngineCapabilities], `SpeechToTextCapabilities`,
/// `TextToSpeechCapabilities`, `ImageGenerationCapabilities` and
/// `DecisionCapabilities`. It reports an engine that cannot run, has no
/// model loaded or is disposed as unsupported, with the reason, instead of
/// throwing.
abstract interface class EngineCapabilities {
  /// Whether the engine can run requests now.
  bool get isSupported;

  /// Why [isSupported] is false, or null when it is true.
  String? get unsupportedReason;

  /// The backend the engine runs on, or null when it reports none.
  String? get backendName;
}

/// What a `LlamaEngine` and its loaded model support, as the loaded model's
/// runtime reports it.
///
/// Read it with `LlamaEngine.capabilities` after a model loads. A request that
/// uses an input or option reported `false` throws
/// `LlamaUnsupportedException`, except where a field says otherwise. A
/// `false` reported from a native LiteRT-LM bundle's declaration is
/// best-effort: the request is still sent, and fails with
/// `LlamaUnsupportedException` only if the runtime cannot run it. The
/// snapshot does not change when the engine later loads or unloads a model
/// or multimodal projector.
class LlamaEngineCapabilities implements EngineCapabilities {
  /// Whether a model is loaded. When false, every other field is false, empty
  /// or null.
  @override
  final bool isSupported;

  /// Why [isSupported] is false, or null when it is true.
  @override
  final String? unsupportedReason;

  /// The active backend's name, as `LlamaEngine.getBackendName` reports it,
  /// or null when the backend could not report one.
  @override
  final String? backendName;

  /// The runtime that runs the loaded model, or null when no model is loaded
  /// or a custom backend does not report it.
  ///
  /// GGUF models run on [LlamaRuntime.llamaCpp], natively or through the
  /// WebGPU bridge on the web.
  final LlamaRuntime? runtime;

  /// Whether chat requests can include image parts.
  ///
  /// llama.cpp needs a loaded multimodal projector that reports vision.
  /// Native LiteRT-LM needs no projector and reports the encoders the bundle
  /// declares. LiteRT-LM web takes no media.
  final bool supportsVision;

  /// Whether chat requests can include audio parts, under the same rules as
  /// [supportsVision].
  final bool supportsAudio;

  /// Whether `LlamaEngine.embed` and `embedBatch` are available.
  ///
  /// True on llama.cpp, natively and on WebGPU, and on a native LiteRT-LM
  /// embedding engine. False on LiteRT-LM conversation and Web engines. A
  /// rank-pooled or encoder-decoder model, or WebGPU bridge assets older than
  /// `v0.1.7`, still throw.
  final bool supportsEmbeddings;

  /// Whether `LlamaEngine.scoreNextToken` is available.
  final bool supportsNextTokenScoring;

  /// Whether the model sees the whole conversation passed to
  /// `LlamaEngine.create`.
  ///
  /// Explicit `withTextHistory` factories support
  /// LiteRT-LM system/user/assistant text only when their loaded
  /// runtime consumes a conversation preface and exposes a working history API.
  /// It requires a final user or tool result message. Media and user/system
  /// thinking parts are rejected; stored assistant reasoning is replayed only
  /// with an assistant tool call, as native LiteRT-LM does.
  /// The probe does not qualify a particular model's behavior.
  final bool supportsMultiTurnChat;

  /// Whether tools passed to `LlamaEngine.create` reach the model and its
  /// output is parsed for tool calls.
  ///
  /// On LiteRT-LM Web, true only for explicit `withTextHistory` factories
  /// whose loaded runtime reads `preface.tools` (`@litert-lm/core@0.19.0`);
  /// calls come from the runtime's `tool_calls`. Automatic tool loops run
  /// there only when the load-time token-count probes succeed, and
  /// `ToolChoice.required` and `parallelToolCalls` are rejected. Original
  /// constructors report false and refuse automatic tool loops.
  /// How well other models call tools still depends on their chat template. `ToolChoice.required` also
  /// needs [supportsGrammar] for Hermes-style templates, and
  /// [supportsLazyGrammar] for templates whose tool-call grammar waits for a
  /// trigger.
  final bool supportsToolCalling;

  /// Whether a strict `responseFormat` (`json_object` or `json_schema`) is
  /// enforced through grammar-constrained decoding.
  ///
  /// Native LiteRT-LM admits its provider for canonical Qwen3 text chat on
  /// macOS arm64 CPU. That bounded schema route requires thinking disabled
  /// and rejects tools, media, speculation, caller stops and wider schemas;
  /// [supportsGrammar] remains false. Probing may initialize the loaded model.
  /// LiteRT-LM Web remains unsupported. WebGPU lazy tool grammars require the
  /// loaded bridge core to report `lazyGrammar`.
  final bool supportsStructuredOutput;

  /// Whether [GenerationParams.grammar], [GenerationParams.grammarTriggers]
  /// and [GenerationParams.preservedTokens] are applied.
  ///
  /// False on LiteRT-LM. WebGPU custom roots require its loaded bridge core
  /// to report `lazyGrammar`.
  final bool supportsGrammar;

  /// Whether [GenerationParams.grammarLazy] is applied, so a grammar can wait
  /// for a trigger. False on LiteRT-LM; WebGPU follows the loaded core's
  /// `lazyGrammar` capability probe.
  final bool supportsLazyGrammar;

  /// Whether a [GenerationParams.penalty] other than its default is applied.
  /// False on LiteRT-LM.
  final bool supportsPenalty;

  /// Whether a non-zero [GenerationParams.presencePenalty] is applied.
  final bool supportsPresencePenalty;

  /// Whether a non-zero [GenerationParams.minP] is applied.
  final bool supportsMinP;

  /// Whether [GenerationParams.thinkingBudget] is applied.
  ///
  /// A runtime that applies it can still reject it for generation with media
  /// parts or speculative decoding.
  final bool supportsThinkingBudget;

  /// Whether [GenerationParams.streamBatchTokenThreshold] and
  /// [GenerationParams.streamBatchByteThreshold] are applied.
  ///
  /// LiteRT-LM web rejects values other than the defaults; WebGPU ignores
  /// them.
  final bool supportsStreamBatching;

  /// The strategies that [GenerationParams.speculativeDecodingConfig] can use.
  ///
  /// [SpeculativeDecodingStrategy.backendDefault] also stands for the
  /// [GenerationParams.speculativeDecoding] flag. Native LiteRT-LM reports
  /// [SpeculativeDecodingStrategy.backendDefault] and
  /// [SpeculativeDecodingStrategy.mtp] unless the bundle declares no
  /// speculative drafter. A runtime can still reject a
  /// request that uses only these strategies, such as one that combines
  /// strategies, sets a tuning field or draft model the runtime does not take,
  /// or has media parts, a grammar or a thinking budget.
  final Set<SpeculativeDecodingStrategy> speculativeDecodingStrategies;

  /// The media types `LlamaToolResultContent.content` can carry to the model;
  /// empty when it can carry none.
  ///
  /// [LlamaToolResultMedia.image] is reported by native llama.cpp with a
  /// loaded projector that reports vision, for a model whose chat template
  /// (`ModelParams.chatTemplate` or the model's own) is in a format
  /// qualified for tool-result content: Hermes-style `<tool_call>`
  /// templates, smoke-tested with the Qwen3-VL template and Qwen3.5-0.8B
  /// weights. A request that renders through
  /// another format, such as a per-call `customTemplate` or a response
  /// schema with tools, still throws `LlamaUnsupportedException`, as does a
  /// template that does not render each media part once in the prompt.
  /// No runtime reports [LlamaToolResultMedia.audio] yet.
  final Set<LlamaToolResultMedia> toolResultMedia;

  /// Creates a capability snapshot.
  const LlamaEngineCapabilities({
    required this.isSupported,
    this.unsupportedReason,
    this.backendName,
    this.runtime,
    this.supportsVision = false,
    this.supportsAudio = false,
    this.supportsEmbeddings = false,
    this.supportsNextTokenScoring = false,
    this.supportsMultiTurnChat = false,
    this.supportsToolCalling = false,
    this.supportsStructuredOutput = false,
    this.supportsGrammar = false,
    this.supportsLazyGrammar = false,
    this.supportsPenalty = false,
    this.supportsPresencePenalty = false,
    this.supportsMinP = false,
    this.supportsThinkingBudget = false,
    this.supportsStreamBatching = false,
    this.speculativeDecodingStrategies = const <SpeculativeDecodingStrategy>{},
    this.toolResultMedia = const <LlamaToolResultMedia>{},
  });
}

/// A media type that `LlamaToolResultContent.content` can carry, as
/// `LlamaEngineCapabilities.toolResultMedia` reports it.
enum LlamaToolResultMedia {
  /// `LlamaImageContent` parts.
  image,

  /// `LlamaAudioContent` parts.
  audio,
}
