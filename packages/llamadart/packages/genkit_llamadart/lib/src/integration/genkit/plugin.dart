import 'package:genkit/plugin.dart';
import 'package:llamadart/llamadart.dart' as llama;

import '../../api/model_definition.dart';
import '../../api/media_resolver.dart';
import '../../api/model_inspection.dart';
import '../../api/scoring.dart';
import '../../core/runtime/engine_registry.dart';
import '../../core/runtime/llama_runtime.dart';
import 'action_support.dart';
import 'actions/embedder_action.dart';
import 'actions/model_action.dart';
import 'actions/scoring_action.dart';

/// `GenkitPlugin` implementation backed by local `llamadart` runtimes.
///
/// Reasoning is emitted separately in streamed/final responses and retained by
/// Genkit history. Incoming reasoning parts are omitted from model prompts;
/// replay is model/template-specific and is not advertised by this adapter.
/// Direct embedder actions observe Genkit cancellation: queued calls skip work,
/// while active embedding drains before cancellation is reported.
class LlamaDartPlugin extends GenkitPlugin {
  /// Registers model/scoring actions and, when enabled, an embedder per definition.
  ///
  /// [observers] are copied and attached to default engines. Callbacks inherit
  /// the request zone and observer errors do not fail inference. When supplying
  /// [runtimeFactory], the factory owns observer installation instead.
  ///
  /// [mediaResolver] explicitly enables native HTTP(S) image/audio downloads.
  /// It is application-owned, bypassed on Web and never disposed by the plugin.
  /// Without it, existing local/data inputs and browser image URLs are retained.
  ///
  /// Custom runtimes supplied through [runtimeFactory] must implement
  /// [LlamaRuntimeCapabilityProvider] to confirm advanced request support.
  /// Without a provider, only single-turn text requests are accepted.
  /// Model names must be unique within the plugin instance; duplicate names
  /// throw [ArgumentError]. Registration and listing do not load model files.
  LlamaDartPlugin({
    required List<LlamaModelDefinition> models,
    LlamaDartRuntimeFactory? runtimeFactory,
    this.mediaResolver,
    Iterable<llama.LlamaEngineObserver> observers = const [],
  }) : _models = List<LlamaModelDefinition>.unmodifiable(models),
       _registry = EngineRegistry(
         models: models,
         runtimeFactory: runtimeFactory,
         observers: observers,
       ) {
    final names = <String>{};
    for (final model in models) {
      if (!names.add(model.name)) {
        throw ArgumentError.value(
          model.name,
          'models',
          'Duplicate llamadart model names are not allowed.',
        );
      }
    }
  }

  /// Application-owned native remote-media resolver, or null for no downloads.
  final LlamaDartMediaResolver? mediaResolver;
  final List<LlamaModelDefinition> _models;
  final EngineRegistry _registry;
  List<Action>? _actions;
  List<ActionMetadata>? _listedActions;
  final _scorers =
      <
        String,
        Action<LlamaDartScoringRequest, LlamaDartTokenScores, void, void>
      >{};

  /// Custom Genkit action type used by [scorer], separate from model generation.
  static const ActionType scoringActionType = nextTokenScoringActionType;

  /// Returns this model's typed, registered next-token scoring action.
  ///
  /// Registration is lazy and does not confirm scoring support. Calls share the
  /// generation/embedding queue, probe live capabilities and fail with a Genkit
  /// `unimplemented` or `failedPrecondition` error when support is absent or
  /// unverified. Invalid requests/vocabulary IDs produce `invalidArgument`;
  /// malformed runtime results produce `dataLoss`. Models load on first use.
  ///
  /// Input is a raw prompt: chat templates are caller-supplied. Results are raw
  /// next-token log probabilities, independent of generation settings. Genkit
  /// instruments the custom action; ordinary model token/TTFT metrics do not
  /// apply. Application telemetry settings control content capture.
  ///
  /// Cancellation prevents queued work; once backend scoring starts it drains
  /// before cancellation is reported. It cannot interrupt native evaluation.
  /// Disposal drains accepted calls and prevents further runtime operations.
  /// Throws [StateError] for an unknown model name or calls after disposal.
  Action<LlamaDartScoringRequest, LlamaDartTokenScores, void, void> scorer(
    String modelName,
  ) => _scorers.putIfAbsent(modelName, () {
    final definition = _models
        .where((model) => model.name == modelName)
        .firstOrNull;
    if (definition == null) {
      throw StateError('Unknown llamadart model: $modelName');
    }
    return buildScoringAction(definition: definition, registry: _registry);
  });

  /// Plugin name used when registering actions in Genkit.
  @override
  String get name => llamaDartPluginName;

  /// Disposes all runtimes cached by this plugin instance.
  ///
  /// Queued runtime operations drain before disposal. Pending remote-media
  /// transfers remain caller-owned; cancel or await them before closing the client.
  ///
  /// Disposal is terminal. Create a new plugin instance instead of submitting
  /// model or embedding requests after this future has been requested.
  /// Multiple runtime disposal failures are retained in a `ParallelWaitError`.
  Future<void> dispose() {
    return _registry.dispose();
  }

  /// Loads [modelName] if needed and returns read-only runtime diagnostics.
  ///
  /// Serialized with generation and embeddings; performs no inference. Unknown
  /// custom-runtime measurements are null. Throws [StateError] for an unknown
  /// model or after disposal, and propagates loading/probe failures. Registration
  /// and [list] remain lazy. Snapshot fields contain no model paths or metadata.
  Future<LlamaModelInspection> inspectModel(String modelName) {
    return _registry.withRuntime(modelName, (runtime) async {
      final capabilities = _registry.capabilitiesFor(modelName);
      final provider =
          capabilities?.isSupported != false &&
              runtime is LlamaRuntimeInspectionProvider
          ? runtime as LlamaRuntimeInspectionProvider
          : null;
      final contextSize = await provider?.contextSize;
      final embeddingCapabilities = capabilities?.isSupported == false
          ? null
          : await _registry.probeEmbeddingCapabilities(modelName, runtime);
      return LlamaModelInspection(
        capabilities: capabilities,
        embeddingCapabilities: embeddingCapabilities,
        contextSize: contextSize != null && contextSize > 0
            ? contextSize
            : null,
      );
    });
  }

  /// Tokenizes raw [text] with [modelName], loading it if needed.
  ///
  /// Runs in the model's queue without inference. Defaults to not adding tokenizer
  /// special tokens. The returned IDs are immutable. This does not apply a chat
  /// template, tools or media, so it cannot predict complete request usage.
  /// Throws [llama.LlamaUnsupportedException] without tokenizer support;
  /// unknown models and disposed plugins throw [StateError].
  Future<List<int>> tokenize(
    String modelName,
    String text, {
    bool addSpecial = false,
  }) {
    return _registry.withRuntime(modelName, (runtime) async {
      if (_registry.capabilitiesFor(modelName)?.isSupported == false) {
        throw llama.LlamaUnsupportedException(
          'Raw-text tokenization requires a supported loaded runtime. '
          'The capability probe reports this runtime unavailable.',
        );
      }
      if (runtime is! LlamaRuntimeInspectionProvider) {
        throw llama.LlamaUnsupportedException(
          'Raw-text tokenization requires a runtime implementing '
          'LlamaRuntimeInspectionProvider. The custom runtime does not provide it.',
        );
      }
      return List<int>.unmodifiable(
        await (runtime as LlamaRuntimeInspectionProvider).tokenize(
          text,
          addSpecial: addSpecial,
        ),
      );
    });
  }

  /// Counts raw-text tokens without adding special tokens or running inference.
  ///
  /// Has the same loading, queueing and error behavior as [tokenize]. Use request
  /// usage/timings for observed inference; this is not a formatted chat budget.
  Future<int> countTokens(String modelName, String text) async =>
      (await tokenize(modelName, text)).length;

  /// Requests cancellation of [modelName]'s active generation or typed embedding.
  ///
  /// Bypasses the operation queue and requests cooperative backend cancellation.
  /// Typed embeddings require `LlamaRuntimeEmbeddingProvider`; legacy custom
  /// text embedding cannot be interrupted. No-op while loading or idle.
  /// Throws [StateError] for a name not registered on this plugin. Separately
  /// queued requests can still run afterward.
  void cancelActiveGeneration(String modelName) {
    _registry.cancelActiveGeneration(modelName);
  }

  /// Requests cancellation of active generations and typed embeddings.
  ///
  /// Uses the same runtime-dependent behavior as [cancelActiveGeneration].
  void cancelActiveGenerations() {
    _registry.cancelActiveGenerations();
  }

  /// Registers actions without loading models or probing capabilities.
  @override
  Future<List<Action>> init() async {
    if (_actions != null) {
      return _actions!;
    }

    _actions = _models
        .expand((definition) {
          return <Action>[
            buildModelAction(
              definition: definition,
              registry: _registry,
              mediaResolver: mediaResolver,
            ),
            if (definition.supportsEmbeddings)
              buildEmbedderAction(
                definition: definition,
                registry: _registry,
                mediaResolver: mediaResolver,
              ),
            scorer(definition.name),
          ];
        })
        .toList(growable: false);

    return _actions!;
  }

  /// Lists actions with the most recently checked runtime capabilities.
  ///
  /// Does not load models. Unknown support is false in `model.supports`; inspect
  /// `llamadartCapabilities.state` to distinguish unloaded or unverified state
  /// from a verified snapshot. Cached metadata updates after each request probe.
  @override
  Future<List<ActionMetadata>> list() async {
    // Genkit caches plugin listings; keep their metadata synchronized too.
    return _listedActions ??= _models
        .expand((definition) {
          final actionName = actionNameFor(definition.name);
          Map<String, dynamic> metadataFor({bool generation = true}) {
            final metadata = actionMetadataFor(
              definition,
              modelInfo: modelInfoFor(definition, generation: generation),
              generation: generation,
            );
            trackCapabilityMetadata(
              metadata,
              definition,
              _registry,
              generation: generation,
            );
            return metadata;
          }

          return <ActionMetadata>[
            ActionMetadata(
              name: actionName,
              description: definition.name,
              actionType: ActionType.model,
              metadata: metadataFor(),
            ),
            if (definition.supportsEmbeddings)
              ActionMetadata(
                name: actionName,
                description: definition.name,
                actionType: ActionType.embedder,
                metadata: metadataFor(generation: false),
              ),
            scorer(definition.name),
          ];
        })
        .toList(growable: false);
  }
}
