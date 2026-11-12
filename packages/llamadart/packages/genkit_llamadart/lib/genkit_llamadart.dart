/// Local model generation and embeddings for Genkit Dart applications.
///
/// Register local files with [llamaDart] and [LlamaModelDefinition], or resolve
/// downloads through [LlamaDartPluginHandle.prepareModel]. Use
/// [LlamaDartPluginHandle.prepareModelTask] for progress and cancellation UI.
///
/// Genkit owns tool execution and request orchestration. This adapter supplies
/// model calls through llamadart and checks the loaded runtime's capabilities.
/// Configure requests with [LlamaDartGenerationConfig] or [LlamaDartEmbedConfig].
/// Use [LlamaDartPlugin.scorer] for typed raw next-token probabilities.
/// [LlamaDartRuntimePool] provides dedicated native raw-prompt contexts and live
/// LoRA controls for application-authorized flows outside the shared registry.
///
/// Models load lazily. Dispose [LlamaDartPlugin] or [LlamaPreparedModel] when
/// finished, and shut down the caller-owned Genkit instance separately.
///
/// See the [getting-started guide](https://pub.dev/packages/genkit_llamadart)
/// and [runtime installation guide](https://llamadart.leehack.com/).
library;

export 'package:llamadart/llamadart.dart'
    show
        ComputeDevice,
        DefaultModelDownloadManager,
        FlashAttention,
        GpuBackend,
        GenerationParams,
        KvCacheType,
        LlamaEngineObserver,
        LlamaEngineCapabilities,
        LlamaOperationObserver,
        LlamaOperation,
        LlamaOperationResult,
        LlamaChatOperation,
        LlamaTextCompletionOperation,
        LlamaEmbeddingsOperation,
        LlamaEmbeddingCapabilities,
        LlamaEmbeddingInput,
        LlamaEmbeddingModality,
        LlamaModelLoadOperation,
        LlamaGenerationUsage,
        LlamaException,
        LlamaModelException,
        LlamaStateException,
        LlamaUnsupportedException,
        LlamaNextTokenScores,
        LlamaTokenLogprob,
        LiteRtLmActivationDataType,
        LiteRtLmModelParams,
        LlamaCppModelParams,
        LoraAdapterConfig,
        ModelCacheEntry,
        ModelCachePolicy,
        ModelDownloadCancelToken,
        ModelDownloadManager,
        ModelDownloadProgress,
        ModelDownloadProgressCallback,
        ModelLoadOptions,
        ModelFormat,
        ModelParams,
        ModelSplitMode,
        ModelSource,
        ModelSourceKind,
        SpeculativeDecodingConfig,
        SpeculativeDecodingStrategy,
        ThinkingBudget;

export 'src/api/embed_config.dart' show LlamaDartEmbedConfig;
export 'src/api/generation_config.dart' show LlamaDartGenerationConfig;
export 'src/api/model_preparation.dart'
    show
        LlamaModelPreparationSnapshot,
        LlamaModelPreparationSourceRole,
        LlamaModelPreparationStage,
        LlamaModelPreparationTask;
export 'src/api/media_resolver.dart'
    show LlamaDartMediaResolver, HttpLlamaDartMediaResolver;
export 'src/api/model_inspection.dart' show LlamaModelInspection;
export 'src/api/scoring.dart'
    show LlamaDartScoringRequest, LlamaDartTokenScores;
export 'src/api/model_definition.dart' show LlamaModelDefinition;
export 'src/api/plugin_handle.dart' show LlamaDartPluginHandle, llamaDart;
export 'src/api/prepared_model.dart' show LlamaPreparedModel;
export 'src/core/runtime/llama_runtime.dart'
    show
        LlamaDartRuntime,
        LlamaDartRuntimeFactory,
        LlamaRuntimeCapabilityProvider,
        LlamaRuntimeInspectionProvider,
        LlamaRuntimeEmbeddingProvider,
        LlamaRuntimeScoringProvider,
        LlamaRuntimeLoraProvider;
export 'src/integration/genkit/plugin.dart' show LlamaDartPlugin;

export 'src/api/media_model.dart'
    show
        LlamaDartMediaModel,
        LlamaDartSpeechToTextModel,
        LlamaDartTextToSpeechModel,
        LlamaDartImageModel;
export 'src/integration/genkit/media_plugin.dart' show LlamaDartMediaPlugin;

export 'src/api/runtime_owner.dart'
    show
        LlamaDartRuntimePool,
        LlamaDartRuntimeOwner,
        LlamaDartPromptCache,
        LlamaDartRuntimePromptCache;
