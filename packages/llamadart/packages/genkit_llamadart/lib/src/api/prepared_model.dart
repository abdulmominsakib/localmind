import 'package:genkit/genkit.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;

import '../integration/genkit/action_support.dart';
import '../integration/genkit/plugin.dart';
import 'embed_config.dart';
import 'generation_config.dart';
import 'model_definition.dart';
import 'media_resolver.dart';
import 'model_inspection.dart';

/// Result of preparing a `llamadart` model source for Genkit registration.
///
/// The handle contains the resolved local model/cache entries, the normal
/// `LlamaModelDefinition` produced from those entries, a ready-to-register
/// [plugin], and typed Genkit references for generation and embeddings.
class LlamaPreparedModel {
  /// Creates a prepared model handle.
  const LlamaPreparedModel({
    required this.definition,
    required this.plugin,
    required this.modelRef,
    required this.modelEntry,
    this.embedderRef,
    this.mmprojEntry,
    this.ownsPlugin = true,
  });

  /// Local-path model definition that was registered on [plugin].
  final LlamaModelDefinition definition;

  /// Genkit plugin exposing [definition] as model/scoring actions and, when enabled,
  /// an embedder action.
  final LlamaDartPlugin plugin;

  /// Typed Genkit model reference for [definition].
  final genkit.ModelRef<LlamaDartGenerationConfig> modelRef;

  /// Typed Genkit embedder reference, or null when embeddings were disabled.
  ///
  /// A non-null ref permits embedding requests; the loaded runtime and model
  /// must also support embeddings.
  final genkit.EmbedderRef<LlamaDartEmbedConfig>? embedderRef;

  /// Cache entry returned by the `llamadart` download/cache manager for the
  /// primary model source.
  final llama.ModelCacheEntry modelEntry;

  /// Cache entry returned for the optional multimodal projector source.
  final llama.ModelCacheEntry? mmprojEntry;

  /// Whether [dispose] should dispose runtimes owned by [plugin].
  ///
  /// This is true for handles returned by `llamaDart.prepareModel(...)` and
  /// `llamaDart.prepareModelTask(...)`. Set it to false only when constructing
  /// this handle around a caller-owned plugin that will be disposed elsewhere.
  final bool ownsPlugin;

  /// Creates a Genkit instance with [plugin] registered.
  ///
  /// The returned Genkit instance is still caller-owned. Call
  /// `ai.shutdown()` when the app is done with it, and call [dispose] to
  /// release this handle's plugin/runtime resources when [ownsPlugin] is true.
  genkit.Genkit createGenkit({bool? isDevEnv, int? reflectionPort}) {
    return genkit.Genkit(
      plugins: <LlamaDartPlugin>[plugin],
      model: modelRef,
      isDevEnv: isDevEnv,
      reflectionPort: reflectionPort,
    );
  }

  /// Runs a tiny generation request to initialize the native runtime.
  ///
  /// [systemPrompt] can prime an expensive instruction prefix before the first
  /// user-visible turn. Override [config] to control max tokens, temperature,
  /// thinking behavior, and other `llamadart` generation settings.
  /// This performs inference; it is not just a file/cache check. A system
  /// prompt requires system-message delivery support from the runtime.
  /// Failed or aborted Genkit responses throw their original cause when present,
  /// otherwise a [genkit.GenkitException].
  Future<genkit.GenerateResult<Output>> warmUp<Output>(
    genkit.Genkit ai, {
    String? systemPrompt,
    String prompt = 'Reply with one token: ready',
    LlamaDartGenerationConfig config = const LlamaDartGenerationConfig(
      maxTokens: 1,
      temperature: 0.0,
      enableThinking: false,
    ),
  }) async {
    final messages = systemPrompt == null
        ? null
        : <genkit.Message>[
            genkit.Message(
              role: genkit.Role.system,
              content: <genkit.Part>[genkit.TextPart(text: systemPrompt)],
            ),
            genkit.Message(
              role: genkit.Role.user,
              content: <genkit.Part>[genkit.TextPart(text: prompt)],
            ),
          ];

    final response = await ai.generate<Output, LlamaDartGenerationConfig>(
      model: modelRef,
      prompt: messages == null ? prompt : null,
      messages: messages,
      config: config,
    );
    if (response.finishReason == genkit.FinishReason.failed ||
        response.finishReason == genkit.FinishReason.aborted) {
      throw response.cause ??
          genkit.GenkitException(
            response.finishMessage ?? 'Model warm-up failed.',
          );
    }
    return response;
  }

  /// Loads this model if needed and returns a read-only runtime snapshot.
  ///
  /// Does not generate text. Shares the plugin's operation queue and disposal
  /// lifecycle; see [LlamaDartPlugin.inspectModel] for unavailable measurements.
  Future<LlamaModelInspection> inspect() =>
      plugin.inspectModel(definition.name);

  /// Tokenizes raw [text] without chat formatting or inference.
  ///
  /// Defaults to not adding tokenizer special tokens. Loads this model if needed; see
  /// [LlamaDartPlugin.tokenize] for queueing and unsupported-runtime errors.
  Future<List<int>> tokenize(String text, {bool addSpecial = false}) =>
      plugin.tokenize(definition.name, text, addSpecial: addSpecial);

  /// Counts raw-text tokens without added special tokens or chat formatting.
  ///
  /// Loads this model if needed without inference. This is not a conversation,
  /// tool or media budget; see [LlamaDartPlugin.countTokens].
  Future<int> countTokens(String text) =>
      plugin.countTokens(definition.name, text);

  /// Requests cancellation of this model's active generation or typed embedding.
  ///
  /// Typed embedding cancellation requires `LlamaRuntimeEmbeddingProvider`;
  /// legacy custom text embedding drains without interruption.
  ///
  /// Bypasses the request queue and leaves separately queued requests intact.
  /// No-op while loading or idle; it does not cancel model downloads.
  void cancelActiveGeneration() {
    plugin.cancelActiveGeneration(definition.name);
  }

  /// Disposes runtimes owned by [plugin] when [ownsPlugin] is true.
  ///
  /// Disposal is terminal for an owned plugin. Prepare a new model handle
  /// instead of reusing this handle afterward.
  Future<void> dispose() {
    if (!ownsPlugin) {
      return Future<void>.value();
    }
    return plugin.dispose();
  }
}

/// Builds the prepared-model handle shared by direct and observable preparation.
LlamaPreparedModel createLlamaPreparedModel({
  required String name,
  required llama.ModelCacheEntry modelEntry,
  required llama.ModelParams modelParams,
  llama.ModelCacheEntry? mmprojEntry,
  bool supportsEmbeddings = true,
  bool supportsTools = true,
  bool supportsConstrainedOutput = true,
  genkit.ModelInfo? modelInfo,
  Iterable<llama.LlamaEngineObserver> observers = const [],
  LlamaDartMediaResolver? mediaResolver,
}) {
  final definition = LlamaModelDefinition(
    name: name,
    modelPath: modelEntry.filePath,
    modelParams: modelParams,
    mmprojPath: mmprojEntry?.filePath,
    supportsEmbeddings: supportsEmbeddings,
    supportsTools: supportsTools,
    supportsConstrainedOutput: supportsConstrainedOutput,
    modelInfo: modelInfo,
  );
  final plugin = LlamaDartPlugin(
    models: <LlamaModelDefinition>[definition],
    observers: observers,
    mediaResolver: mediaResolver,
  );

  return LlamaPreparedModel(
    definition: definition,
    plugin: plugin,
    modelRef: genkit.modelRef<LlamaDartGenerationConfig>(actionNameFor(name)),
    embedderRef: supportsEmbeddings
        ? genkit.embedderRef<LlamaDartEmbedConfig>(actionNameFor(name))
        : null,
    modelEntry: modelEntry,
    mmprojEntry: mmprojEntry,
  );
}
