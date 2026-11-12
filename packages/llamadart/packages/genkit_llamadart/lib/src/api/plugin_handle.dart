import 'package:genkit/plugin.dart';
import 'package:llamadart/llamadart.dart' as llama;

import '../integration/genkit/action_support.dart';
import '../integration/genkit/plugin.dart';
import 'embed_config.dart';
import 'generation_config.dart';
import 'model_preparation.dart';
import 'model_definition.dart';
import 'media_resolver.dart';
import 'prepared_model.dart';

/// Global handle used to configure and reference the `llamadart` plugin.
///
/// ```dart
/// final plugin = llamaDart(
///   models: const <LlamaModelDefinition>[
///     LlamaModelDefinition(
///       name: 'local-chat',
///       modelPath: '/models/chat.gguf',
///       supportsEmbeddings: false,
///     ),
///   ],
/// );
/// ```
const LlamaDartPluginHandle llamaDart = LlamaDartPluginHandle();

/// Configures local models and creates typed Genkit model and embedder refs.
///
/// Use the global [llamaDart] handle. [call] registers existing local files;
/// [prepareModel] resolves a source through llamadart's cache; [prepareModelTask]
/// additionally exposes preparation progress and cancellation.
class LlamaDartPluginHandle {
  /// Creates a plugin handle.
  const LlamaDartPluginHandle();

  /// Registers local model files without loading their runtimes.
  ///
  /// Each definition registers Genkit model and next-token scoring actions, plus an embedder action
  /// when `supportsEmbeddings` is enabled.
  /// [observers] observe every default engine in the caller's request zone.
  /// They may receive sensitive content; exporting it requires app opt-in.
  /// Observer failures are isolated by llamadart.
  /// [mediaResolver] optionally downloads native HTTP(S) image/audio input;
  /// it is application-owned and is not used for model downloads or on Web.
  ///
  /// Throws [ArgumentError] if model names are duplicated. The caller owns the
  /// returned plugin and must dispose it when finished.
  /// Generated reasoning remains in Genkit history; incoming reasoning parts
  /// are omitted from subsequent model prompts. See [LlamaModelDefinition].
  LlamaDartPlugin call({
    required List<LlamaModelDefinition> models,
    Iterable<llama.LlamaEngineObserver> observers = const [],
    LlamaDartMediaResolver? mediaResolver,
  }) {
    return LlamaDartPlugin(
      models: models,
      observers: observers,
      mediaResolver: mediaResolver,
    );
  }

  /// Resolves a `llamadart` [llama.ModelSource] into a Genkit-ready model.
  ///
  /// This helper uses `llamadart`'s package-managed [llama.ModelDownloadManager]
  /// instead of creating a separate cache layer. Remote HTTP(S) and Hugging Face
  /// sources are downloaded or read from cache according to [options]; local
  /// sources are validated by the manager and remain subject to `llamadart`'s
  /// local-source option checks. When [mmprojSource] is provided, it is resolved
  /// with [mmprojOptions] and wired into the produced [LlamaModelDefinition].
  ///
  /// [observers] are copied before preparation and attached to the engine.
  /// [mediaResolver] is retained by the plugin for native request media,
  /// separately from model preparation, without taking ownership of its client.
  /// Downloads finish before this future resolves; native model loading stays
  /// lazy until generation, embedding, [LlamaPreparedModel.warmUp],
  /// [LlamaPreparedModel.inspect] or raw-text tokenization/counting.
  ///
  /// Throws [ArgumentError] for an empty [name] and propagates download,
  /// checksum and source-option errors from llamadart. [onModelProgress] and
  /// [onMmprojProgress] report their respective sources independently.
  ///
  /// The returned [LlamaPreparedModel] exposes the normal plugin and typed refs,
  /// so generation still uses `Genkit.generate` with `llamaDart.model(name)`.
  Future<LlamaPreparedModel> prepareModel({
    required String name,
    required llama.ModelSource source,
    llama.ModelParams modelParams = const llama.ModelParams(),
    llama.ModelSource? mmprojSource,
    llama.ModelLoadOptions options = llama.ModelLoadOptions.defaults,
    llama.ModelLoadOptions mmprojOptions = llama.ModelLoadOptions.defaults,
    llama.ModelDownloadManager? downloadManager,
    llama.ModelDownloadProgressCallback? onModelProgress,
    llama.ModelDownloadProgressCallback? onMmprojProgress,
    bool supportsEmbeddings = true,
    bool supportsTools = true,
    bool supportsConstrainedOutput = true,
    ModelInfo? modelInfo,
    Iterable<llama.LlamaEngineObserver> observers = const [],
    LlamaDartMediaResolver? mediaResolver,
  }) async {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Model name must not be empty.');
    }

    final observerSnapshot = List<llama.LlamaEngineObserver>.unmodifiable(
      observers,
    );
    final manager = downloadManager ?? llama.DefaultModelDownloadManager();
    final modelEntry = await manager.ensureModel(
      source,
      options: options,
      onProgress: onModelProgress,
    );
    final mmprojEntry = mmprojSource == null
        ? null
        : await manager.ensureModel(
            mmprojSource,
            options: mmprojOptions,
            onProgress: onMmprojProgress,
          );

    return createLlamaPreparedModel(
      name: name,
      modelEntry: modelEntry,
      modelParams: modelParams,
      mmprojEntry: mmprojEntry,
      supportsEmbeddings: supportsEmbeddings,
      supportsTools: supportsTools,
      supportsConstrainedOutput: supportsConstrainedOutput,
      modelInfo: modelInfo,
      observers: observerSnapshot,
      mediaResolver: mediaResolver,
    );
  }

  /// Creates an observable task for source-backed model preparation.
  ///
  /// The task emits plain Dart snapshots for source resolution, cache checks,
  /// downloads, verification, Genkit plugin setup, success, failure, and
  /// cancellation. Use this in Flutter, CLI, and server apps that need
  /// deterministic progress UI without reaching into lower-level `llamadart`
  /// download controller internals.
  ///
  /// [observers] are copied and attached to the prepared engine for telemetry
  /// alongside download progress. [mediaResolver] is retained for native
  /// request media after preparation and remains application-owned.
  /// The task starts on the next microtask.
  /// Dispose both the task and its resulting [LlamaPreparedModel]; disposing
  /// the task alone does not dispose a successfully prepared plugin.
  /// Throws [ArgumentError] for an empty [name].
  LlamaModelPreparationTask prepareModelTask({
    required String name,
    required llama.ModelSource source,
    llama.ModelParams modelParams = const llama.ModelParams(),
    llama.ModelSource? mmprojSource,
    llama.ModelLoadOptions options = llama.ModelLoadOptions.defaults,
    llama.ModelLoadOptions mmprojOptions = llama.ModelLoadOptions.defaults,
    llama.ModelDownloadManager? downloadManager,
    bool supportsEmbeddings = true,
    bool supportsTools = true,
    bool supportsConstrainedOutput = true,
    ModelInfo? modelInfo,
    Iterable<llama.LlamaEngineObserver> observers = const [],
    LlamaDartMediaResolver? mediaResolver,
  }) {
    return createLlamaModelPreparationTask(
      name: name,
      source: source,
      modelParams: modelParams,
      mmprojSource: mmprojSource,
      options: options,
      mmprojOptions: mmprojOptions,
      downloadManager: downloadManager,
      supportsEmbeddings: supportsEmbeddings,
      supportsTools: supportsTools,
      supportsConstrainedOutput: supportsConstrainedOutput,
      modelInfo: modelInfo,
      observers: observers,
      mediaResolver: mediaResolver,
    );
  }

  /// Returns a typed Genkit model reference.
  ///
  /// The [name] must match a [LlamaModelDefinition.name] registered on the
  /// plugin instance.
  ModelRef<LlamaDartGenerationConfig> model(String name) {
    return modelRef<LlamaDartGenerationConfig>(actionNameFor(name));
  }

  /// Returns a typed Genkit embedder reference.
  ///
  /// The [name] must match a [LlamaModelDefinition.name] registered on the
  /// plugin instance with embeddings enabled. Creating a ref does not register
  /// an action or verify runtime support; the loaded model must be eligible for
  /// embeddings when used.
  EmbedderRef<LlamaDartEmbedConfig> embedder(String name) {
    return embedderRef<LlamaDartEmbedConfig>(actionNameFor(name));
  }
}
