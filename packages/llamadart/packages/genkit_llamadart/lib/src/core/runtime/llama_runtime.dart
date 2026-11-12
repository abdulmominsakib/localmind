import 'package:llamadart/llamadart.dart' as llama;

import '../../api/model_definition.dart';

/// Creates a fresh runtime owned by one registered model.
///
/// The plugin serializes its requests and disposes it after queued work settles.
/// Do not return the same mutable runtime for different model names.
typedef LlamaDartRuntimeFactory = LlamaDartRuntime Function();

// Preserve the internal spellings used by existing runtime implementations.
typedef LlamaRuntimeFactory = LlamaDartRuntimeFactory;
typedef LlamaRuntime = LlamaDartRuntime;

/// Optional capability probe for custom runtimes.
///
/// Read after initialization and before every request. Return a fresh snapshot
/// for the active model; returning unsupported or throwing prevents inference.
/// Runtimes without this interface can serve single-turn text, but cannot
/// confirm tools, structured output, media, embeddings or message history.
abstract interface class LlamaRuntimeCapabilityProvider {
  /// Capabilities of the currently loaded model and backend.
  Future<llama.LlamaEngineCapabilities> get capabilities;
}

/// Optional read-only measurements and tokenization for a loaded runtime.
///
/// The plugin calls these operations after initialization, inside the same queue
/// as generation and embeddings. Return null for unavailable measurements; never
/// substitute requested configuration or a model metadata limit. Backend labels
/// in [LlamaRuntimeCapabilityProvider] must not include paths or credentials.
abstract interface class LlamaRuntimeInspectionProvider {
  /// Actual loaded context capacity, or null when it cannot be measured.
  Future<int?> get contextSize;

  /// Encodes raw text without inference or chat-template formatting.
  ///
  /// [addSpecial] requests tokenizer-specific special tokens. Throw
  /// [llama.LlamaUnsupportedException] when tokenization is unavailable.
  Future<List<int>> tokenize(String text, {bool addSpecial = false});
}

/// Optional ordered text, image and audio embedding support for custom runtimes.
///
/// Embedding modalities are independent of chat vision/audio support. Probe the
/// loaded model and processors on every request; unknown modalities must be
/// false. Implement [LlamaRuntimeCapabilityProvider] for general runtime status.
/// Existing text-only runtimes can continue implementing only [LlamaDartRuntime.embedBatch].
abstract interface class LlamaRuntimeEmbeddingProvider {
  /// Available embedding modalities for the active model and backend.
  ///
  /// This runs inside the model queue, before resolving remote media or inference.
  Future<llama.LlamaEmbeddingCapabilities> get embeddingCapabilities;

  /// Embeds ordered parts, returning one vector per input in input order.
  ///
  /// Honor [normalize], preserve adjacent text verbatim, and reject unsupported
  /// inputs without truncation. Do not apply chat templates or task prefixes.
  /// The adapter retains buffers until this future settles. [LlamaDartRuntime.cancelGeneration]
  /// requests cancellation of this operation; cleanup must settle before the
  /// next queued request can start. Throw a typed [llama.LlamaException] on failure.
  Future<List<List<double>>> embedContentBatch(
    List<llama.LlamaEmbeddingInput> inputs, {
    bool normalize = true,
  });
}

/// Optional next-token scoring implementation for a loaded custom runtime.
///
/// Implement [LlamaRuntimeCapabilityProvider] too, and report
/// `supportsNextTokenScoring` only when the active model/backend can score.
/// The plugin serializes scoring with other operations on this model.
abstract interface class LlamaRuntimeScoringProvider {
  /// Scores raw [prompt] using the backend's unmodified next-token logits.
  ///
  /// Preserve candidate order/duplicates and return [topK] entries in descending
  /// probability order. Reject out-of-vocabulary IDs/counts before evaluating
  /// the prompt. No chat template or generation sampling parameters apply.
  Future<llama.LlamaNextTokenScores> scoreNextToken(
    String prompt, {
    List<int> candidates = const [],
    int topK = 0,
    bool reusePromptPrefix = true,
  });
}

/// Optional live-adapter controls for independently owned native contexts.
///
/// The owner checks [supportsLiveLora] inside its operation queue before adapter
/// resolution or download. Custom implementations must probe actual support;
/// method presence alone is insufficient. Mutations must invalidate prompt/KV
/// reuse, and failures may leave the context uncertain, requiring disposal.
abstract interface class LlamaRuntimeLoraProvider {
  /// Whether the loaded context can apply, rescale, remove and clear adapters.
  Future<bool> get supportsLiveLora;

  /// Applies or rescales [source], preserving its own download options/progress.
  Future<void> setLoraSource(
    llama.ModelSource source, {
    double scale = 1,
    llama.ModelLoadOptions download = llama.ModelLoadOptions.defaults,
    llama.ModelDownloadProgressCallback? onProgress,
  });

  /// Removes the adapter loaded from the same source identity.
  Future<void> removeLoraSource(llama.ModelSource source);

  /// Removes every active adapter and invalidates cached prompt state.
  Future<void> clearLoras();
}

/// Runtime operations used by the Genkit adapter.
///
/// Implement [LlamaRuntimeCapabilityProvider] to confirm advanced capabilities.
/// The plugin initializes a runtime once, then runs one operation at a time
/// for that model. Cancellation can arrive while an operation is active.
///
/// Implementations may import `package:llamadart/llamadart.dart` for the chat,
/// completion and tool types in this contract.
abstract class LlamaDartRuntime {
  /// Creates a runtime implementation for one model's serialized requests.
  LlamaDartRuntime();

  /// Loads the model and optional projector from [definition].
  Future<void> initialize(LlamaModelDefinition definition);

  /// Generates chat completions from the supplied conversation.
  ///
  /// Preserve [tools] via `ToolDefinition.toJsonSchema()`: owned rich schemas
  /// have an empty `parameters` list. Report grammar support only when these
  /// constraints can be enforced; reject unsupported templates or tool choices.
  Stream<llama.LlamaCompletionChunk> create(
    List<llama.LlamaChatMessage> messages, {
    llama.GenerationParams? params,
    List<llama.ToolDefinition>? tools,
    llama.ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = false,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
  });

  /// Formats chat input and returns decoding constraints for [generate].
  ///
  /// When [responseFormat] requests JSON, return the grammar, triggers, stops
  /// and preserved tokens required to enforce it. Reject unsupported constraints
  /// instead of returning a best-effort unconstrained prompt. Preserve tool
  /// inputs through `ToolDefinition.toJsonSchema()`, including owned schemas.
  Future<llama.LlamaChatTemplateResult> chatTemplate(
    List<llama.LlamaChatMessage> messages, {
    bool addAssistant = true,
    List<llama.ToolDefinition>? tools,
    llama.ToolChoice toolChoice = llama.ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = false,
    Map<String, dynamic>? responseFormat,
    String? sourceLangCode,
    String? targetLangCode,
    bool includeTokenCount = false,
    Map<String, dynamic>? chatTemplateKwargs,
  });

  /// Generates raw text using the supplied prompt and grammar settings.
  Stream<String> generate(
    String prompt, {
    llama.GenerationParams params = const llama.GenerationParams(),
    List<llama.LlamaContentPart>? parts,
  });

  /// Embeds texts in input order, returning one vector for each input.
  ///
  /// Honor [normalize] or reject it explicitly when unsupported.
  Future<List<List<double>>> embedBatch(
    List<String> texts, {
    bool normalize = true,
  });

  /// Requests cooperative cancellation of active generation or typed embedding.
  ///
  /// Implementations of [LlamaRuntimeEmbeddingProvider] must also signal an
  /// active [LlamaRuntimeEmbeddingProvider.embedContentBatch] operation.
  ///
  /// Returns immediately; the active [create] or [generate] stream must settle
  /// without requiring another request to enter the operation queue.
  void cancelGeneration();

  /// Releases runtime resources after queued requests finish.
  Future<void> dispose();
}
