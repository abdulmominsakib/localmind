import '../config/flash_attention.dart';
import '../config/gpu_backend.dart';
import '../config/kv_cache_type.dart';
import '../config/lora_config.dart';

/// Strategy for distributing model tensors across GPU devices.
///
/// Mirrors llama.cpp `llama_split_mode`. The default, [layer], preserves
/// upstream behavior.
enum ModelSplitMode {
  /// Use a single GPU selected by [ModelParams.mainGpu].
  none(0),

  /// Split layers and KV cache across GPUs.
  layer(1),

  /// Split layers and KV cache across GPUs, with row-level tensor splitting
  /// where supported by the backend.
  row(2),

  /// Use tensor parallelism where supported by the backend and model.
  tensor(3);

  /// Native llama.cpp enum value.
  final int llamaCppValue;

  const ModelSplitMode(this.llamaCppValue);
}

/// Preferred LiteRT-LM runtime backend for `.litertlm` models.
///
/// This is intentionally separate from [GpuBackend], which mirrors llama.cpp
/// backends. LiteRT-LM exposes a smaller runtime selector: CPU, GPU, or the
/// Android NPU delegate.
enum LiteRtLmBackendPreference {
  /// Let llamadart choose a platform default.
  auto(null),

  /// Run LiteRT-LM on CPU.
  cpu('cpu'),

  /// Run LiteRT-LM on the platform GPU delegate when available.
  gpu('gpu'),

  /// Run LiteRT-LM on Android NPU delegate when available.
  npu('npu');

  /// Native LiteRT-LM backend name, or null for automatic selection.
  final String? nativeName;

  const LiteRtLmBackendPreference(this.nativeName);
}

/// LiteRT-LM activation data type override for native `.litertlm` engines.
///
/// Values mirror upstream LiteRT-LM `ActivationDataType` integer values exposed
/// through `litert_lm_engine_settings_set_activation_data_type`.
enum LiteRtLmActivationDataType {
  /// Use float32 activations.
  float32(0, 'float32'),

  /// Use float16 activations.
  float16(1, 'float16'),

  /// Use int16 activations.
  int16(2, 'int16'),

  /// Use int8 activations.
  int8(3, 'int8');

  /// Native LiteRT-LM C ABI value.
  final int nativeValue;

  /// Stable CLI/docs name.
  final String optionName;

  const LiteRtLmActivationDataType(this.nativeValue, this.optionName);
}

/// Configuration parameters for loading a Llama model.
///
/// These parameters affect the initial model loading and context allocation.
/// Most of these cannot be changed once the model is loaded.
///
/// Context batching fields in this class mirror llama.cpp semantics:
/// `n_batch` is the logical max decode batch, and `n_ubatch` is the
/// physical micro-batch size.
///
/// Example:
/// ```dart
/// final params = ModelParams(
///   contextSize: 4096,
///   gpuLayers: 33, // Offload 33 layers to GPU
///   splitMode: ModelSplitMode.none,
///   mainGpu: 1, // Use the second GPU device for the full model
/// );
/// await engine.loadModel('path/to/model.gguf', modelParams: params);
/// ```
class ModelParams {
  /// Context size (n_ctx) in tokens.
  final int contextSize;

  /// Number of model layers to offload to the GPU (n_gpu_layers).
  final int gpuLayers;

  /// Preferred GPU backend for inference.
  final GpuBackend preferredBackend;

  /// Preferred LiteRT-LM runtime backend for `.litertlm` models.
  ///
  /// Defaults to [LiteRtLmBackendPreference.auto]. The llama.cpp
  /// [preferredBackend] field is still used for `.gguf` models and as an
  /// automatic LiteRT-LM hint, but NPU is only expressible through this field.
  final LiteRtLmBackendPreference liteRtLmBackend;

  /// Native LiteRT-LM activation data type override.
  ///
  /// `null` keeps the runtime/model default. This option is only applied by the
  /// native LiteRT-LM `.litertlm` backend.
  final LiteRtLmActivationDataType? liteRtLmActivationDataType;

  /// Native LiteRT-LM prefill chunk size for CPU dynamic models.
  ///
  /// `null` keeps the runtime default. Positive values are forwarded to
  /// `litert_lm_engine_settings_set_prefill_chunk_size`.
  final int? liteRtLmPrefillChunkSize;

  /// Native LiteRT-LM file-section loading override.
  ///
  /// `null` keeps the runtime default, which is parallel loading in the pinned
  /// LiteRT-LM runtime. Set `false` to disable it for diagnostics.
  final bool? liteRtLmParallelFileSectionLoading;

  /// Native LiteRT-LM dispatch library directory for Android NPU deployments.
  ///
  /// `null` keeps the runtime default. This path is forwarded to
  /// `litert_lm_engine_settings_set_litert_dispatch_lib_dir`.
  final String? liteRtLmDispatchLibDir;

  /// Model tensor distribution strategy across GPU devices.
  ///
  /// This is passed through to llama.cpp `llama_model_params.split_mode`.
  /// Defaults to [ModelSplitMode.layer] to preserve llama.cpp's default
  /// behavior.
  final ModelSplitMode splitMode;

  /// Primary GPU device index for model loading.
  ///
  /// This is passed through to llama.cpp `llama_model_params.main_gpu`.
  /// Backend-specific device ordering is defined by llama.cpp and the active
  /// backend. Upstream llama.cpp uses this value to select the single GPU when
  /// [splitMode] is [ModelSplitMode.none]. Defaults to 0 to preserve
  /// llama.cpp's default behavior.
  final int mainGpu;

  /// Initial LoRA adapters to load along with the model.
  ///
  /// llama.cpp backends support multiple adapters with custom scales. Native
  /// LiteRT-LM supports one default-scale text LoRA adapter at model load;
  /// runtime adapter updates, stacking, custom scales, and LiteRT-LM web LoRA
  /// are unsupported.
  final List<LoraAdapterConfig> loras;

  /// Optional chat template to override the model's default template.
  final String? chatTemplate;

  /// Number of threads to use for generation (n_threads).
  ///
  /// Set to 0 for automatic detection.
  final int numberOfThreads;

  /// Number of threads to use for batch processing (n_threads_batch).
  ///
  /// Set to 0 for automatic detection.
  final int numberOfThreadsBatch;

  /// Maximum prompt/eval tokens per decode call (n_batch).
  ///
  /// Mirrors llama.cpp `llama_context_params.n_batch` (logical max batch).
  /// See also upstream CLI flag `--batch-size`.
  ///
  /// Set to 0 (or negative) to use an automatic value. Native generative
  /// contexts default to the smaller of [contextSize] and
  /// [ModelParams.defaultBatchSize]. Native encoder-only models retain
  /// full-context batching for compatibility. Backends that cannot determine
  /// model architecture before context creation may also retain that policy.
  final int batchSize;

  /// Micro-batch size used by backend schedulers (n_ubatch).
  ///
  /// Mirrors llama.cpp `llama_context_params.n_ubatch` (physical max batch).
  /// See also upstream CLI flag `--ubatch-size`.
  ///
  /// Set to 0 (or negative) to use an automatic value. Native generative
  /// contexts default to the smaller of the resolved [batchSize] and
  /// [ModelParams.defaultMicroBatchSize]. Native encoder-only models retain
  /// the resolved logical batch size for compatibility. Other backends may
  /// preserve the same architecture-agnostic fallback.
  final int microBatchSize;

  /// Maximum parallel sequence slots in context memory (n_seq_max).
  ///
  /// Values greater than 1 allow true multi-sequence batching (for example,
  /// embedding batches with independent sequence IDs).
  ///
  /// Set to 1 to preserve single-sequence behavior.
  final int maxParallelSequences;

  /// llama.cpp recurrent-state rollback snapshots per sequence (`n_rs_seq`).
  ///
  /// Set this to at least the MTP draft token max when using llama.cpp MTP
  /// speculative decoding with architectures that need bounded rollback
  /// snapshots, such as Qwen3.5 MTP. The default `0` preserves legacy context
  /// memory use. llama.cpp may clamp this to zero for unsupported
  /// architectures.
  final int speculativeRollbackTokenMax;

  /// Whether llama.cpp should memory-map model weights. Default `true`.
  ///
  /// Combined with [useMlock] and mapped to `llama_model_params.load_mode`.
  final bool useMmap;

  /// Whether llama.cpp should lock model weights in memory. Default `false`.
  ///
  /// Combined with [useMmap] and mapped to `llama_model_params.load_mode`.
  final bool useMlock;

  /// Whether llama.cpp should load bundled multi-token prediction tensors.
  ///
  /// Defaults to `false` to avoid the additional memory cost for callers that
  /// do not use MTP speculative decoding. Set this before loading a model when
  /// `SpeculativeDecodingStrategy.mtp` will use MTP tensors embedded in the
  /// target GGUF. Explicit external MTP draft models are loaded as MTP
  /// automatically.
  final bool loadMtp;

  /// `llama_context_params.flash_attn_type`. User-explicit values override
  /// the platform/backend heuristic.
  final FlashAttention flashAttention;

  /// `llama_context_params.type_k`. Non-F16 requires [flashAttention] enabled.
  final KvCacheType cacheTypeK;

  /// `llama_context_params.type_v`. Non-F16 requires [flashAttention] enabled.
  final KvCacheType cacheTypeV;

  /// `llama_context_params.kv_unified`. `null` keeps the current heuristic
  /// (auto-enabled when [maxParallelSequences] > 1).
  final bool? kvUnified;

  /// `llama_context_params.rope_freq_base`. `null` keeps the model's
  /// trained value.
  final double? ropeFrequencyBase;

  /// `llama_context_params.rope_freq_scale`. `null` keeps the model's
  /// trained value.
  final double? ropeFrequencyScale;

  /// Web/WebGPU only: prefer the 64-bit (wasm64/mem64) bridge core.
  ///
  /// The default 32-bit core has a 4 GiB linear-memory limit, but large models
  /// need headroom for the KV cache and intermediate buffers. `null` (default)
  /// lets llamadart auto-decide from [modelBytesHint] using the current
  /// wasm32-safe ceiling; `true` forces the mem64 core; `false` forces wasm32.
  /// Ignored on every non-web backend (native llama.cpp uses the host address
  /// space).
  final bool? preferMemory64;

  /// Web/WebGPU only: approximate model size in bytes, used to decide whether
  /// to load the mem64 core up front (instead of waiting for an out-of-memory
  /// failure and retrying). Ignored on non-web backends. `null` when unknown.
  final int? modelBytesHint;

  /// Maximum number of GPU layers to safely offload all layers.
  static const int maxGpuLayers = 999;

  /// Automatic logical batch size for generative contexts.
  ///
  /// This matches llama.cpp's default `n_batch`.
  static const int defaultBatchSize = 2048;

  /// Automatic physical micro-batch size for generative contexts.
  ///
  /// This matches llama.cpp's default `n_ubatch`.
  static const int defaultMicroBatchSize = 512;

  /// Creates configuration for the model. Use [validate] to check for
  /// llama.cpp-incompatible combinations before passing to a load call.
  const ModelParams({
    this.contextSize = 4096,
    this.gpuLayers = maxGpuLayers,
    this.preferredBackend = GpuBackend.auto,
    this.liteRtLmBackend = LiteRtLmBackendPreference.auto,
    this.liteRtLmActivationDataType,
    this.liteRtLmPrefillChunkSize,
    this.liteRtLmParallelFileSectionLoading,
    this.liteRtLmDispatchLibDir,
    this.splitMode = ModelSplitMode.layer,
    this.mainGpu = 0,
    this.loras = const [],
    this.chatTemplate,
    this.numberOfThreads = 0,
    this.numberOfThreadsBatch = 0,
    this.batchSize = 0,
    this.microBatchSize = 0,
    this.maxParallelSequences = 1,
    this.speculativeRollbackTokenMax = 0,
    this.useMmap = true,
    this.useMlock = false,
    this.loadMtp = false,
    this.flashAttention = FlashAttention.auto,
    this.cacheTypeK = KvCacheType.f16,
    this.cacheTypeV = KvCacheType.f16,
    this.kvUnified,
    this.ropeFrequencyBase,
    this.ropeFrequencyScale,
    this.preferMemory64,
    this.modelBytesHint,
  });

  /// Validates the parameter combination. Throws [ArgumentError] when the
  /// combination is incompatible with llama.cpp (currently: non-F16 KV
  /// cache requires flashAttention != disabled). Called automatically by
  /// `LlamaCppService.loadModel` before the native call so callers don't
  /// have to remember it; exposed publicly so callers who construct
  /// `ModelParams` defensively can validate up-front.
  void validate() {
    if (liteRtLmPrefillChunkSize != null && liteRtLmPrefillChunkSize! <= 0) {
      throw ArgumentError.value(
        liteRtLmPrefillChunkSize,
        'liteRtLmPrefillChunkSize',
        'must be positive when provided',
      );
    }
    if (liteRtLmDispatchLibDir != null &&
        liteRtLmDispatchLibDir!.trim().isEmpty) {
      throw ArgumentError.value(
        liteRtLmDispatchLibDir,
        'liteRtLmDispatchLibDir',
        'must be non-empty when provided',
      );
    }
    if (speculativeRollbackTokenMax < 0) {
      throw ArgumentError.value(
        speculativeRollbackTokenMax,
        'speculativeRollbackTokenMax',
        'must be non-negative',
      );
    }
    if ((cacheTypeK != KvCacheType.f16 || cacheTypeV != KvCacheType.f16) &&
        flashAttention == FlashAttention.disabled) {
      throw ArgumentError(
        'Non-F16 KV cache (cacheTypeK=$cacheTypeK, cacheTypeV=$cacheTypeV) '
        'requires flashAttention != disabled. Either set flashAttention to '
        'auto/enabled or use KvCacheType.f16 for both.',
      );
    }
  }

  /// Creates a copy of this [ModelParams] with updated fields.
  ///
  /// Nullable fields ([chatTemplate], [kvUnified], [ropeFrequencyBase],
  /// [ropeFrequencyScale]) use a sentinel pattern so callers can
  /// **explicitly clear them back to null** by passing the corresponding
  /// `clear*: true` flag. Without the sentinel, `null` would be
  /// indistinguishable from "argument omitted, keep current value".
  ModelParams copyWith({
    int? contextSize,
    int? gpuLayers,
    GpuBackend? preferredBackend,
    LiteRtLmBackendPreference? liteRtLmBackend,
    LiteRtLmActivationDataType? liteRtLmActivationDataType,
    bool clearLiteRtLmActivationDataType = false,
    int? liteRtLmPrefillChunkSize,
    bool clearLiteRtLmPrefillChunkSize = false,
    bool? liteRtLmParallelFileSectionLoading,
    bool clearLiteRtLmParallelFileSectionLoading = false,
    String? liteRtLmDispatchLibDir,
    bool clearLiteRtLmDispatchLibDir = false,
    ModelSplitMode? splitMode,
    int? mainGpu,
    List<LoraAdapterConfig>? loras,
    String? chatTemplate,
    bool clearChatTemplate = false,
    int? numberOfThreads,
    int? numberOfThreadsBatch,
    int? batchSize,
    int? microBatchSize,
    int? maxParallelSequences,
    int? speculativeRollbackTokenMax,
    bool? useMmap,
    bool? useMlock,
    bool? loadMtp,
    FlashAttention? flashAttention,
    KvCacheType? cacheTypeK,
    KvCacheType? cacheTypeV,
    bool? kvUnified,
    bool clearKvUnified = false,
    double? ropeFrequencyBase,
    bool clearRopeFrequencyBase = false,
    double? ropeFrequencyScale,
    bool clearRopeFrequencyScale = false,
    bool? preferMemory64,
    bool clearPreferMemory64 = false,
    int? modelBytesHint,
    bool clearModelBytesHint = false,
  }) {
    return ModelParams(
      contextSize: contextSize ?? this.contextSize,
      gpuLayers: gpuLayers ?? this.gpuLayers,
      preferredBackend: preferredBackend ?? this.preferredBackend,
      liteRtLmBackend: liteRtLmBackend ?? this.liteRtLmBackend,
      liteRtLmActivationDataType: clearLiteRtLmActivationDataType
          ? null
          : (liteRtLmActivationDataType ?? this.liteRtLmActivationDataType),
      liteRtLmPrefillChunkSize: clearLiteRtLmPrefillChunkSize
          ? null
          : (liteRtLmPrefillChunkSize ?? this.liteRtLmPrefillChunkSize),
      liteRtLmParallelFileSectionLoading:
          clearLiteRtLmParallelFileSectionLoading
          ? null
          : (liteRtLmParallelFileSectionLoading ??
                this.liteRtLmParallelFileSectionLoading),
      liteRtLmDispatchLibDir: clearLiteRtLmDispatchLibDir
          ? null
          : (liteRtLmDispatchLibDir ?? this.liteRtLmDispatchLibDir),
      splitMode: splitMode ?? this.splitMode,
      mainGpu: mainGpu ?? this.mainGpu,
      loras: loras ?? this.loras,
      chatTemplate: clearChatTemplate
          ? null
          : (chatTemplate ?? this.chatTemplate),
      numberOfThreads: numberOfThreads ?? this.numberOfThreads,
      numberOfThreadsBatch: numberOfThreadsBatch ?? this.numberOfThreadsBatch,
      batchSize: batchSize ?? this.batchSize,
      microBatchSize: microBatchSize ?? this.microBatchSize,
      maxParallelSequences: maxParallelSequences ?? this.maxParallelSequences,
      speculativeRollbackTokenMax:
          speculativeRollbackTokenMax ?? this.speculativeRollbackTokenMax,
      useMmap: useMmap ?? this.useMmap,
      useMlock: useMlock ?? this.useMlock,
      loadMtp: loadMtp ?? this.loadMtp,
      flashAttention: flashAttention ?? this.flashAttention,
      cacheTypeK: cacheTypeK ?? this.cacheTypeK,
      cacheTypeV: cacheTypeV ?? this.cacheTypeV,
      kvUnified: clearKvUnified ? null : (kvUnified ?? this.kvUnified),
      ropeFrequencyBase: clearRopeFrequencyBase
          ? null
          : (ropeFrequencyBase ?? this.ropeFrequencyBase),
      ropeFrequencyScale: clearRopeFrequencyScale
          ? null
          : (ropeFrequencyScale ?? this.ropeFrequencyScale),
      preferMemory64: clearPreferMemory64
          ? null
          : (preferMemory64 ?? this.preferMemory64),
      modelBytesHint: clearModelBytesHint
          ? null
          : (modelBytesHint ?? this.modelBytesHint),
    );
  }
}

/// Resolves llama.cpp-compatible context batch parameters.
///
/// When [ModelParams.batchSize] and [ModelParams.microBatchSize] are unset,
/// generative contexts use llama.cpp's standard defaults:
///
/// - `n_batch = min(n_ctx, 2048)`
/// - `n_ubatch = min(n_batch, 512)`
///
/// Set [useFullContextDefaults] for a detected encoder-only model that needs
/// the legacy `n_batch = n_ctx`, `n_ubatch = n_batch` cascade. Explicit
/// positive values always take precedence over either default policy.
///
/// Values are clamped to safe bounds so `n_ubatch <= n_batch <= n_ctx`.
({int batchSize, int microBatchSize}) resolveModelContextBatchSizes(
  ModelParams modelParams,
  int contextSize, {
  bool useFullContextDefaults = false,
}) {
  final effectiveContextSize = contextSize > 0 ? contextSize : 1;
  final automaticBatchSize = useFullContextDefaults
      ? effectiveContextSize
      : ModelParams.defaultBatchSize;

  final configuredBatchSize = modelParams.batchSize > 0
      ? modelParams.batchSize
      : automaticBatchSize;
  final cappedBatchSize = configuredBatchSize > effectiveContextSize
      ? effectiveContextSize
      : configuredBatchSize;
  final batchSize = cappedBatchSize > 0 ? cappedBatchSize : 1;
  final automaticMicroBatchSize = useFullContextDefaults
      ? batchSize
      : ModelParams.defaultMicroBatchSize;

  final configuredMicroBatchSize = modelParams.microBatchSize > 0
      ? modelParams.microBatchSize
      : automaticMicroBatchSize;
  final cappedMicroBatchSize = configuredMicroBatchSize > batchSize
      ? batchSize
      : configuredMicroBatchSize;
  final microBatchSize = cappedMicroBatchSize > 0 ? cappedMicroBatchSize : 1;

  return (batchSize: batchSize, microBatchSize: microBatchSize);
}
