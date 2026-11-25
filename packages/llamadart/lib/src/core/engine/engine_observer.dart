import '../models/chat/chat_message.dart';
import '../models/chat/completion_chunk.dart';
import '../models/chat/content_part.dart';
import '../models/inference/embedding.dart';
import '../models/inference/generation_params.dart';
import '../models/inference/generation_usage.dart';
import '../models/inference/model_params.dart';
import '../models/inference/tool_choice.dart';
import '../models/tools/tool_definition.dart';

/// Observes the operations of a `LlamaEngine`, for tracing, metrics or
/// logging.
///
/// Pass observers to the `LlamaEngine` constructor. [onStart] runs in the
/// zone that called the engine method, so it can read the caller's trace
/// context. An exception an observer throws is reported to the library
/// logger as a warning and never reaches the caller.
///
/// Operations carry prompts and messages. An observer that exports telemetry
/// should record them only when its user opts in.
///
/// Extend this class; later versions may add methods with default bodies.
abstract base class LlamaEngineObserver {
  /// Creates a [LlamaEngineObserver].
  const LlamaEngineObserver();

  /// Called when [operation] starts. Returns the observer of the rest of the
  /// operation, or null to ignore it.
  ///
  /// A `create` or `generate` operation starts when its stream is listened
  /// to; the others start when their method is called.
  LlamaOperationObserver? onStart(LlamaOperation operation);
}

/// Observes one [LlamaOperation] after [LlamaEngineObserver.onStart].
///
/// Its methods run in the zone that called the engine method. Extend this
/// class; later versions may add methods with default bodies.
abstract base class LlamaOperationObserver {
  /// Creates a [LlamaOperationObserver].
  const LlamaOperationObserver();

  /// Called with each chunk of a [LlamaChatOperation], as the caller
  /// receives it.
  void onChunk(LlamaCompletionChunk chunk) {}

  /// Called with each text piece of a [LlamaTextCompletionOperation], as
  /// the caller receives it.
  void onText(String text) {}

  /// Called once when the operation ends: completed, failed or cancelled.
  ///
  /// A chat stream whose subscription is cancelled after its final chunk
  /// arrived ends completed, unless `LlamaEngine.cancelGeneration` stopped
  /// it before that chunk.
  void onEnd(LlamaOperationResult result);
}

/// The inference runtime that runs a loaded model.
enum LlamaRuntime {
  /// llama.cpp, for GGUF models, native or through the WebGPU bridge.
  llamaCpp,

  /// LiteRT-LM, for `.litertlm` bundles, native or web.
  liteRtLm,
}

/// An operation of a `LlamaEngine`.
///
/// Later versions may add operation types, so a `switch` over operations
/// needs a default case.
abstract final class LlamaOperation {
  /// The loaded model's `general.name` metadata, or else the last segment of
  /// the path or URL it was loaded from. For a [LlamaModelLoadOperation],
  /// that last segment of the model being loaded.
  ///
  /// Null when no model is loaded, when that segment is empty or contains
  /// one of `/ \ ? # @ ; & =` as written or percent-escaped, so the segment
  /// is never a directory path, URL query, fragment or userinfo, when a URL's
  /// segment does not percent-decode to UTF-8, and for `data:` and `blob:`
  /// URLs. A local file name is reported as written, `%` included.
  /// `general.name` is reported as the model file declares it.
  final String? model;

  /// The runtime of the loaded model, or null when the backend does not
  /// report it or no model is loaded yet.
  final LlamaRuntime? runtime;

  const LlamaOperation._({required this.model, required this.runtime});
}

/// A chat completion: `LlamaEngine.create`, `createStructuredJson` or
/// `ChatSession.create`.
final class LlamaChatOperation extends LlamaOperation {
  /// The request messages, as an unmodifiable copy of the list.
  final List<LlamaChatMessage> messages;

  /// The generation parameters the caller passed.
  final GenerationParams params;

  /// The tools offered to the model, if any, as an unmodifiable copy.
  final List<ToolDefinition>? tools;

  /// The requested tool choice, or null when the caller passed none.
  final ToolChoice? toolChoice;

  /// The requested structured-output format, if any, as an unmodifiable
  /// copy of the top-level map.
  final Map<String, dynamic>? responseFormat;

  /// Creates a [LlamaChatOperation].
  LlamaChatOperation({
    required super.model,
    required super.runtime,
    required List<LlamaChatMessage> messages,
    required this.params,
    List<ToolDefinition>? tools,
    this.toolChoice,
    Map<String, dynamic>? responseFormat,
  }) : messages = List<LlamaChatMessage>.unmodifiable(messages),
       tools = tools == null ? null : List<ToolDefinition>.unmodifiable(tools),
       responseFormat = responseFormat == null
           ? null
           : Map<String, dynamic>.unmodifiable(responseFormat),
       super._();
}

/// A raw-prompt text completion: `LlamaEngine.generate`.
final class LlamaTextCompletionOperation extends LlamaOperation {
  /// The raw prompt.
  final String prompt;

  /// The generation parameters.
  final GenerationParams params;

  /// The media parts of the prompt, if any, as an unmodifiable copy.
  final List<LlamaContentPart>? parts;

  /// Creates a [LlamaTextCompletionOperation].
  LlamaTextCompletionOperation({
    required super.model,
    required super.runtime,
    required this.prompt,
    required this.params,
    List<LlamaContentPart>? parts,
  }) : parts = parts == null
           ? null
           : List<LlamaContentPart>.unmodifiable(parts),
       super._();
}

/// A text or content embeddings request.
final class LlamaEmbeddingsOperation extends LlamaOperation {
  /// Legacy text inputs as an unmodifiable copy; empty for content calls.
  final List<String> inputs;

  /// Ordered part kinds per input, without text or media sources/payloads.
  ///
  /// For content embedding operations [inputs] is empty. Legacy text embedding
  /// operations keep their existing [inputs] and report one text part per input.
  final List<List<LlamaEmbeddingModality>> inputPartKinds;

  /// Number of requested vectors, including for redacted content inputs.
  int get inputCount => inputPartKinds.length;

  /// Whether the vectors are L2-normalized.
  final bool normalize;

  /// Creates a [LlamaEmbeddingsOperation].
  LlamaEmbeddingsOperation({
    required super.model,
    required super.runtime,
    required List<String> inputs,
    List<List<LlamaEmbeddingModality>>? inputPartKinds,
    required this.normalize,
  }) : inputs = List<String>.unmodifiable(inputs),
       inputPartKinds = List<List<LlamaEmbeddingModality>>.unmodifiable([
         for (final kinds
             in inputPartKinds ??
                 [
                   for (final _ in inputs) [LlamaEmbeddingModality.text],
                 ])
           List<LlamaEmbeddingModality>.unmodifiable(kinds),
       ]),
       super._();
}

/// A model load: a whole `LlamaEngine.load` or `setModel` call, with its
/// downloads and its projector, or the deprecated `loadModel` and
/// `loadModelFromUrl`, including the load that `loadModelSource` performs
/// after resolving its source.
final class LlamaModelLoadOperation extends LlamaOperation {
  /// The model parameters.
  final ModelParams modelParams;

  /// Creates a [LlamaModelLoadOperation].
  const LlamaModelLoadOperation({
    required super.model,
    required this.modelParams,
  }) : super._(runtime: null);
}

/// How a [LlamaOperation] ended.
final class LlamaOperationResult {
  /// The error the operation failed with, or null.
  final Object? error;

  /// The stack trace of [error], or null.
  final StackTrace? stackTrace;

  /// Whether the operation was cancelled, by `LlamaEngine.cancelGeneration`
  /// or by cancelling its stream subscription.
  final bool cancelled;

  /// Why generation stopped: `stop`, `length` or `tool_calls`, as on the
  /// final `create` chunk. Null for operations that do not generate, and for
  /// a failed or cancelled generation.
  final String? finishReason;

  /// The generation's token counts and timings, when the backend reports
  /// them.
  final LlamaGenerationUsage? usage;

  /// Creates a [LlamaOperationResult].
  const LlamaOperationResult({
    this.error,
    this.stackTrace,
    this.cancelled = false,
    this.finishReason,
    this.usage,
  });
}
