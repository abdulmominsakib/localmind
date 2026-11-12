import 'dart:typed_data';

import '../../exceptions.dart';
import '../config/compute_device.dart';
import '../config/flash_attention.dart';
import '../config/gpu_backend.dart';
import '../config/kv_cache_type.dart';
import '../config/lora_config.dart';
import 'model_params_runtime_support.dart';

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
  ///
  /// Needs llama.cpp split buffer types on every model device.
  /// A native llama.cpp load whose devices lack them,
  /// such as a bundled GPU backend or a selected CPU, throws
  /// `LlamaUnsupportedException` before the model loads. Use [layer]
  /// instead.
  row(2),

  /// Use tensor parallelism where supported by the backend and model.
  tensor(3);

  /// Native llama.cpp enum value.
  final int llamaCppValue;

  const ModelSplitMode(this.llamaCppValue);
}

/// Preferred LiteRT-LM runtime backend for `.litertlm` models.
///
/// Use [ModelParams.device], which every runtime honours and which throws
/// `LlamaUnsupportedException` when the device is unavailable. This selector
/// keeps working until 1.0, so a load can still pick a LiteRT-LM device apart
/// from the llama.cpp one.
@Deprecated('Use ModelParams.device. This will be removed in 1.0.')
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
/// A load throws `LlamaUnsupportedException` naming each field set away
/// from its default that the model's runtime does not apply, such as a
/// `liteRtLm*` field for a GGUF model, instead of ignoring it. `LlamaBackend()`
/// checks this before any download when `ModelSource.format` or the file
/// name names the model format.
///
/// [LlamaCppModelParams] and [LiteRtLmModelParams] take only the fields
/// their runtime applies; prefer them when the model's runtime is known.
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
/// final engine = await LlamaEngine.load(
///   LlamaModel(ModelSource.path('path/to/model.gguf')),
///   params: params,
/// );
/// ```
class ModelParams {
  /// Selects LiteRT-LM's separate embedding engine for `.litertlm` bundles.
  ///
  /// Defaults to false, preserving conversation loading. A LiteRT-LM adapter
  /// without embedding-engine integration throws `LlamaUnsupportedException`
  /// for true instead of creating a conversation engine. This mode is never
  /// inferred from a filename.
  /// LiteRT-LM-only: llama.cpp GGUF loaders reject true with
  /// `LlamaUnsupportedException`; GGUF embeddings use the existing per-call mode.
  /// After loading, probe `LlamaEngine.embeddingCapabilities` for modalities.
  final bool liteRtLmEmbeddingEngine;

  /// Context size (n_ctx) in tokens.
  final int contextSize;

  /// Device to run the model on, for every runtime.
  ///
  /// [ComputeDevice.auto], the default, keeps each runtime's own default,
  /// which [gpuLayers], [preferredBackend] and the deprecated
  /// [liteRtLmBackend] narrow as before.
  ///
  /// An explicit device is honoured or the load throws
  /// `LlamaUnsupportedException`; it never runs elsewhere:
  /// - [ComputeDevice.cpu] loads no GPU layers. On llama.cpp it loads only
  ///   the CPU module, whatever [gpuLayers] and [preferredBackend] say;
  ///   LiteRT-LM still rejects a positive [gpuLayers] other than
  ///   [maxGpuLayers].
  /// - [ComputeDevice.gpu] on llama.cpp needs a GPU module and device for
  ///   [preferredBackend] (Vulkan on Android and Metal on an iOS simulator
  ///   when it is [GpuBackend.auto]), and on the Web an active WebGPU
  ///   runtime. LiteRT-LM needs its GPU backend on this platform, and on the
  ///   Web a WebGPU adapter.
  /// - [ComputeDevice.npu] is LiteRT-LM on Android only.
  ///
  /// Native LiteRT-LM starts its runtime on the first call that needs it, so
  /// a GPU or NPU that fails to start throws `LlamaUnsupportedException`
  /// there. Under [ComputeDevice.auto] with [liteRtLmBackend] also auto, it
  /// retries a GPU engine that fails to start on the CPU and logs a
  /// `LlamaLogLevel.warn` record, and throws the GPU error if the CPU fails
  /// too. [validate] rejects a device that contradicts [preferredBackend],
  /// [gpuLayers], [mainGpu] or [liteRtLmBackend].
  /// Android llama.cpp excludes the known unsafe Adreno 750 driver
  /// `2150604839`: [ComputeDevice.gpu] throws, while automatic selection
  /// with a Vulkan preference falls back to CPU with a warning.
  final ComputeDevice device;

  /// Number of model layers to offload to the GPU (n_gpu_layers).
  ///
  /// `0` keeps every layer on the CPU. A negative value means all layers, as
  /// llama.cpp defines `n_gpu_layers`, and every runtime treats it exactly
  /// like [maxGpuLayers].
  final int gpuLayers;

  /// Preferred GPU backend for inference.
  ///
  /// Under [ComputeDevice.auto], on Linux and Windows, an explicit GPU
  /// backend whose module is missing loads the model on CPU with 0 GPU layers
  /// and logs a `LlamaLogLevel.warn` record through the Dart logger. With
  /// [device] set to [ComputeDevice.gpu] the load throws instead.
  ///
  /// On an iOS simulator llama.cpp's Metal backend returns incorrect output
  /// (https://github.com/leehack/llamadart/issues/950), so [GpuBackend.auto]
  /// loads the model on the CPU with 0 GPU layers there. [GpuBackend.metal]
  /// and [ComputeDevice.gpu] still load it on Metal and log a
  /// `LlamaLogLevel.warn` record.
  final GpuBackend preferredBackend;

  /// Preferred LiteRT-LM runtime backend for `.litertlm` models.
  ///
  /// Defaults to [LiteRtLmBackendPreference.auto]. The llama.cpp
  /// [preferredBackend] field is still used for `.gguf` models and as an
  /// automatic LiteRT-LM hint. An unavailable choice throws as it did in
  /// 0.10.0, not `LlamaUnsupportedException`.
  @Deprecated(
    'Use device, which applies to every runtime. This will be removed in '
    '1.0.',
  )
  final LiteRtLmBackendPreference liteRtLmBackend;

  /// Native LiteRT-LM activation data type override.
  ///
  /// `null` keeps the runtime/model default. This option is only applied by the
  /// native LiteRT-LM `.litertlm` backend; other runtimes reject it.
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

  /// Native LiteRT-LM runtime cache directory.
  ///
  /// `null` keeps the default: `llamadart_litert_lm` under the system
  /// temporary directory on macOS and Android, and no directory on other
  /// platforms, where the runtime writes its caches next to the model file.
  /// On Linux and iOS, when the process cannot write that directory, an
  /// engine that would have to write its caches runs uncached; see the
  /// runtime parameters guide. A provided directory is created when
  /// missing and forwarded to `litert_lm_engine_settings_set_cache_dir`.
  final String? liteRtLmCacheDir;

  /// Size cap in bytes for the native LiteRT-LM GPU program cache files of
  /// one cache directory.
  ///
  /// `null` (default) applies [defaultLiteRtLmMaxProgramCacheBytes], 1 GiB.
  /// [unlimitedLiteRtLmProgramCacheBytes] (`-1`) never deletes anything.
  /// Before each native engine create, llamadart deletes files directly
  /// inside the effective cache directory whose name ends with
  /// `_mldrift_program_cache.bin` until their total size is at most the cap:
  /// a file larger than the cap first, then the least recently modified
  /// ones. Files of a model that another LiteRT-LM engine is using with the
  /// same directory, in this or another process, are neither deleted nor
  /// counted. `0` deletes every non-empty program cache file not in use.
  ///
  /// Nothing is deleted when no cache directory is passed to the runtime:
  /// when [liteRtLmCacheDir] is `null` on a platform without a default cache
  /// directory, or when the runtime runs uncached. Each deletion logs a Dart
  /// `warn` record. Values below `-1` are rejected by [validate].
  final int? liteRtLmMaxProgramCacheBytes;

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
  /// [splitMode] is [ModelSplitMode.none], where a negative value loads the
  /// model on the CPU on native platforms. The WebGPU bridge ignores negative
  /// values and keeps its default GPU index. Defaults to 0 to preserve
  /// llama.cpp's default behavior.
  final int mainGpu;

  /// The GPUs to load the model on, as the `GpuDeviceInfo.mainGpu` indices
  /// `LlamaEngine.listGpuDevices` reports for [preferredBackend]
  /// (`llama_model_params.devices`).
  ///
  /// `null`, the default, keeps llama.cpp's own device choice. The list sets
  /// both the devices and their order, which [tensorSplit] follows. Under
  /// [GpuBackend.auto] the indices count the devices of the only GPU backend
  /// with any; with several, set [preferredBackend]. On native llama.cpp,
  /// decision heads and multimodal projectors of the model run on the listed
  /// GPU [mainGpu] counts within the list, or on the first one when [mainGpu]
  /// is out of range. Only GPUs and integrated GPUs with a usable native
  /// device handle count for these auxiliary models; if the list has none
  /// (for example, it contains only accelerators), they run on the CPU.
  /// [validate] rejects an
  /// empty list, a negative or repeated index, and a list with
  /// [ModelSplitMode.none], which runs on the [mainGpu] device alone, with
  /// [gpuLayers] `0`, or with a CPU [device] or [preferredBackend]. Native
  /// llama.cpp throws `LlamaUnsupportedException` before the model loads
  /// for an index this host does not have and when the backend's module or
  /// devices are unavailable, instead of loading on other devices; the Web
  /// and LiteRT-LM reject any list.
  final List<int>? gpuDevices;

  /// The share of the model each GPU holds (`llama_model_params.tensor_split`),
  /// one proportion per device, in [gpuDevices] order, or in the order of
  /// [preferredBackend]'s `listGpuDevices` devices without [gpuDevices].
  ///
  /// `null`, the default, lets llama.cpp split by free memory. llama.cpp
  /// normalizes the proportions, so `[3, 1]` puts three quarters of the
  /// layers on the first device. llama.cpp stores and sums the proportions
  /// as float32. [validate] rejects an empty list, a value that is negative,
  /// infinite, NaN, above float32 range or a nonzero value float32 rounds to
  /// 0, a zero sum or one above float32 range, a length other than that of
  /// [gpuDevices], and a list with [ModelSplitMode.none] or a load that
  /// offloads nothing. Native llama.cpp throws `LlamaUnsupportedException`
  /// before the model loads when the length differs from the number of
  /// devices the load uses; the Web and LiteRT-LM reject any list.
  final List<double>? tensorSplit;

  /// Initial LoRA adapters to load along with the model.
  ///
  /// llama.cpp backends apply every adapter at its [LoraAdapterConfig.scale],
  /// in list order, once the model and its context are created, as
  /// `LlamaEngine.setLoraSource` would; `setLoraSource`, `removeLoraSource`
  /// and `clearLoras` can change them afterwards. Each load applies the list
  /// again.
  ///
  /// `LlamaEngine` resolves each [LoraAdapterConfig.source] before the model
  /// loads, as `setLoraSource` does, in list order, with the adapter's own
  /// [LoraAdapterConfig.download]. Without one, an adapter takes only the
  /// non-secret options of the load (the `download` of `LlamaEngine.load`
  /// and `setModel`): cache policy and directory, resume, retries and cancel
  /// token. The load's bearer token,
  /// headers and checksum never reach an adapter's host. Adapter downloads
  /// report no progress; a failed one fails the load before the model loads.
  ///
  /// On WebGPU this needs bridge assets `v0.1.54+` whose runtime LoRA API reports
  /// support. When an adapter cannot be applied the load fails, and a load
  /// through `LlamaEngine` leaves no model loaded. An unsupported adapter,
  /// such as an aLoRA adapter, or older bridge assets throw
  /// `LlamaUnsupportedException` naming the adapter; any other failure throws
  /// `LlamaModelException`, with the adapter and cause in its `details`.
  ///
  /// The legacy native LiteRT-LM adapter accepts one default-scale text LoRA
  /// path, but upstream v0.18.1 and v0.19.0 reject initial text adapters in
  /// their advanced engine. Path-setter success is not adapter application.
  /// The C API 1.0 client explicitly refuses this unsupported path. Runtime
  /// updates, stacking, custom scales, and LiteRT-LM web LoRA are unsupported.
  /// When the model's format, given or from a
  /// `.litertlm` extension, the native file header of a model without either,
  /// or the backend makes the load LiteRT-LM, adapters it cannot take throw
  /// `LlamaUnsupportedException` before any [LoraAdapterConfig.source]
  /// resolves or downloads: more than one, another scale, any with
  /// [liteRtLmEmbeddingEngine], and on the Web any at all.
  final List<LoraAdapterConfig> loras;

  /// Optional Jinja chat template that replaces the model's own template.
  ///
  /// The value is Jinja source; built-in llama.cpp template names such as
  /// `chatml` are not recognized.
  ///
  /// On llama.cpp (native and WebGPU), `LlamaEngine.create` and
  /// `LlamaEngine.chatTemplate` render prompts with it instead of the GGUF
  /// `tokenizer.chat_template` and its `tool_use` variant, as llama.cpp's
  /// `--chat-template-file` does, and detect the tool-call and reasoning
  /// format from it, so output parsing follows the same template. Null or
  /// empty keeps the GGUF template, and `LlamaEngine.getMetadata` still
  /// reports the GGUF template.
  ///
  /// On LiteRT-LM it replaces the built-in template chosen for the bundle,
  /// including an empty string, and drives output parsing and prompt
  /// rendering on LiteRT-LM web and for requests that cannot use the native
  /// Conversation API. Native `LlamaEngine.create`
  /// sends eligible chats, including images and audio, through that API,
  /// where the template shapes the prompt only for text-only requests to
  /// filename-matched or positively identified Qwen3 bundles. Unnamed Qwen3
  /// bundles need a Qwen3 model-type declaration or the complete canonical
  /// Qwen3 template in bundle metadata or this override. Legacy bundles with
  /// only generic ChatML metadata cannot be identified after renaming: keep
  /// Qwen3 in the filename or set this to `liteRtLmQwen3ChatTemplate`, the
  /// public accessor for the installed canonical template. Do not copy its
  /// bytes across package upgrades. Web `@litert-lm/core@0.19.0` cannot set a
  /// conversation template and rejects this Qwen3 override at model load with
  /// [LlamaUnsupportedException]; use native LiteRT-LM for this contract.
  /// Other families keep their native bundle template and content adapter;
  /// for those, native `LlamaEngine.getMetadata` reports the bundle template
  /// as `tokenizer.chat_template` and this one as
  /// `llamadart.chat_template.parsing`, and the `LlamaEngine.chatTemplate`
  /// prompt shows the bundle template. A native override receives
  /// `enable_thinking` and must implement it.
  ///
  /// A per-call `customTemplate` takes precedence on every runtime.
  final String? chatTemplate;

  /// Number of threads to use for generation (n_threads).
  ///
  /// Set to 0 for automatic selection. On native llama.cpp that is 4, or the
  /// `Platform.numberOfProcessors` count when lower. That count ignores
  /// container CPU limits and CPU affinity, so set this explicitly under them.
  final int numberOfThreads;

  /// Number of threads to use for batch processing (n_threads_batch).
  ///
  /// Set to 0 for automatic selection, as for [numberOfThreads].
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
  ///
  /// When this is unset, Android Vulkan evaluates text prompts eight tokens
  /// per call on GPUs with a subgroup size below 32 other than 8, or an
  /// unknown one: on the Mali-G715 measured, that was faster than larger
  /// batches. Set it to lift that cap.
  ///
  /// With a llama.cpp runtime older than ggml 0.28.0 (llamadart-native
  /// v0.8.0), native Qwen3.5 (`general.architecture=qwen35`) on those GPUs is
  /// restricted to ordinary text: a value above 8 throws
  /// `LlamaUnsupportedException` before context creation, and media,
  /// speculation and embeddings throw before evaluation
  /// ([#948](https://github.com/leehack/llamadart/issues/948)). The bundled
  /// runtime has no such restriction.
  ///
  /// Native encoder-only models and models whose context has no KV cache,
  /// such as BERT and ModernBERT, embed each input in one micro-batch, so a
  /// longer embedding input throws `LlamaInferenceException`.
  ///
  /// llama.cpp cannot split an image across micro-batches when the projector
  /// has it decoded with non-causal attention, as those of Gemma 3 and of
  /// Gemma 4 other than E2B and E4B do. Such an image with more tokens than
  /// the micro-batch throws `LlamaInferenceException` when [batchSize] is
  /// larger than the micro-batch, which the defaults are. With the two equal
  /// it is decoded in several batches, with a logged warning, and answers
  /// can be less accurate.
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
  /// The default `0` preserves ordinary context memory use. Native llama.cpp
  /// rejects nonzero values for recurrent or hybrid models, including LFM2
  /// and Qwen3.5, with [LlamaUnsupportedException] before context creation:
  /// the native API cannot establish a safe rollback graph-node budget.
  /// Speculative decoding that requires those snapshots is unsupported on
  /// these models until the native runtime can validate the graph capacity.
  /// Nonrecurrent models retain native handling; llama.cpp may clamp the
  /// value to zero for architectures without recurrent rollback.
  /// Other backends, including WebGPU, have their own capability contract.
  final int speculativeRollbackTokenMax;

  /// Whether llama.cpp should memory-map model weights. Default `true`.
  ///
  /// Combined with [useMlock] and mapped to `llama_model_params.load_mode`.
  /// The WebGPU bridge and LiteRT-LM reject `false`.
  final bool useMmap;

  /// Whether llama.cpp should lock model weights in memory. Default `false`.
  ///
  /// Combined with [useMmap] and mapped to `llama_model_params.load_mode`.
  /// The WebGPU bridge and LiteRT-LM reject `true`.
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

  /// Number of leading layers whose Mixture-of-Experts (MoE) expert weights
  /// llama.cpp keeps in host memory instead of offloading them, as
  /// llama.cpp's `--n-cpu-moe` does.
  ///
  /// `0`, the default, places expert weights like every other weight. A
  /// negative value keeps the experts of every layer in host memory, as
  /// `--cpu-moe` does. Only expert tensors move; the other weights of a layer
  /// still follow [gpuLayers]. Native llama.cpp only: a model without experts
  /// throws `LlamaUnsupportedException` after it loads, and the Web and
  /// LiteRT-LM reject a nonzero value.
  final int cpuMoeLayers;

  /// Device memory budget in bytes for llama.cpp's experimental GPU cache of
  /// the MoE experts [cpuMoeLayers] keeps in host memory
  /// (`llama_context_params.moe_cache_size`, `--moe-cache-mib`).
  ///
  /// `0`, the default, disables the cache. It keeps the most recently used
  /// host experts of the offloaded layers on the GPU and is split among
  /// several GPUs like the layers. [validate] rejects a negative budget and a
  /// budget with [cpuMoeLayers] `0`, which leaves no host expert to cache. A
  /// load with a budget disables llama.cpp's CPU weight repacking, whose
  /// layout the cache cannot copy.
  ///
  /// Native llama.cpp throws `LlamaUnsupportedException` before the model
  /// loads when nothing is offloaded, for [ModelSplitMode.tensor], and on GPU
  /// backends other than Metal and CUDA (llama.cpp's Vulkan backend aborts
  /// with the cache: ggml-org/llama.cpp#30697), and after it loads when no
  /// offloaded layer keeps its experts in host memory. A budget the GPU
  /// cannot allocate, or too small for the experts of one token, fails
  /// context creation, and the `LlamaModelException` of the load names
  /// `moeCacheBytes` in its details. The Web and LiteRT-LM
  /// reject a nonzero value. GPUs that share system memory, such as Apple
  /// silicon, gain nothing from it. Validated on Metal only; CUDA and
  /// multi-GPU hosts have no hardware evidence yet.
  final int moeCacheBytes;

  /// Web/WebGPU only: prefer the 64-bit (wasm64/mem64) bridge core.
  ///
  /// The default 32-bit core has a 4 GiB linear-memory limit, but large models
  /// need headroom for the KV cache and intermediate buffers. `null` (default)
  /// lets llamadart auto-decide from [modelBytesHint] using the current
  /// wasm32-safe ceiling; `true` forces the mem64 core; `false` forces wasm32.
  /// Native llama.cpp, which uses the host address space, and LiteRT-LM
  /// reject a non-null value.
  final bool? preferMemory64;

  /// Web/WebGPU only: approximate model size in bytes, used to decide whether
  /// to load the mem64 core up front (instead of waiting for an out-of-memory
  /// failure and retrying). `null` when unknown. Native llama.cpp and
  /// LiteRT-LM reject a non-null value.
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

  /// Program cache cap applied when [liteRtLmMaxProgramCacheBytes] is `null`:
  /// 1 GiB per cache directory.
  ///
  /// Some models append to their LiteRT-LM GPU program cache on every engine
  /// create without loading faster
  /// ([#552](https://github.com/leehack/llamadart/issues/552)).
  static const int defaultLiteRtLmMaxProgramCacheBytes = 1 << 30;

  /// [liteRtLmMaxProgramCacheBytes] value that never deletes program caches.
  static const int unlimitedLiteRtLmProgramCacheBytes = -1;

  /// Creates configuration for the model. Use [validate] to check for
  /// llama.cpp-incompatible combinations before passing to a load call.
  const ModelParams({
    @Deprecated(
      'Use LiteRtLmModelParams(embeddingEngine: ...). This will be removed in '
      '1.0.',
    )
    this.liteRtLmEmbeddingEngine = false,
    this.contextSize = 4096,
    this.device = ComputeDevice.auto,
    this.gpuLayers = maxGpuLayers,
    this.preferredBackend = GpuBackend.auto,
    @Deprecated(
      'Use device, which applies to every runtime. This will be removed in '
      '1.0.',
    )
    this.liteRtLmBackend = LiteRtLmBackendPreference.auto,
    @Deprecated(
      'Use LiteRtLmModelParams(activationDataType: ...). This will be removed in '
      '1.0.',
    )
    this.liteRtLmActivationDataType,
    @Deprecated(
      'Use LiteRtLmModelParams(prefillChunkSize: ...). This will be removed in '
      '1.0.',
    )
    this.liteRtLmPrefillChunkSize,
    @Deprecated(
      'Use LiteRtLmModelParams(parallelFileSectionLoading: ...). This will be removed in '
      '1.0.',
    )
    this.liteRtLmParallelFileSectionLoading,
    @Deprecated(
      'Use LiteRtLmModelParams(dispatchLibDir: ...). This will be removed in '
      '1.0.',
    )
    this.liteRtLmDispatchLibDir,
    @Deprecated(
      'Use LiteRtLmModelParams(cacheDir: ...). This will be removed in '
      '1.0.',
    )
    this.liteRtLmCacheDir,
    @Deprecated(
      'Use LiteRtLmModelParams(maxProgramCacheBytes: ...). This will be removed in '
      '1.0.',
    )
    this.liteRtLmMaxProgramCacheBytes,
    this.splitMode = ModelSplitMode.layer,
    this.mainGpu = 0,
    this.gpuDevices,
    this.tensorSplit,
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
    this.cpuMoeLayers = 0,
    this.moeCacheBytes = 0,
    this.preferMemory64,
    this.modelBytesHint,
  });

  ModelParams._copy(ModelParams other)
    : liteRtLmEmbeddingEngine = other.liteRtLmEmbeddingEngine,
      contextSize = other.contextSize,
      device = other.device,
      gpuLayers = other.gpuLayers,
      preferredBackend = other.preferredBackend,
      liteRtLmBackend = other.liteRtLmBackend,
      liteRtLmActivationDataType = other.liteRtLmActivationDataType,
      liteRtLmPrefillChunkSize = other.liteRtLmPrefillChunkSize,
      liteRtLmParallelFileSectionLoading =
          other.liteRtLmParallelFileSectionLoading,
      liteRtLmDispatchLibDir = other.liteRtLmDispatchLibDir,
      liteRtLmCacheDir = other.liteRtLmCacheDir,
      liteRtLmMaxProgramCacheBytes = other.liteRtLmMaxProgramCacheBytes,
      splitMode = other.splitMode,
      mainGpu = other.mainGpu,
      gpuDevices = other.gpuDevices,
      tensorSplit = other.tensorSplit,
      loras = other.loras,
      chatTemplate = other.chatTemplate,
      numberOfThreads = other.numberOfThreads,
      numberOfThreadsBatch = other.numberOfThreadsBatch,
      batchSize = other.batchSize,
      microBatchSize = other.microBatchSize,
      maxParallelSequences = other.maxParallelSequences,
      speculativeRollbackTokenMax = other.speculativeRollbackTokenMax,
      useMmap = other.useMmap,
      useMlock = other.useMlock,
      loadMtp = other.loadMtp,
      flashAttention = other.flashAttention,
      cacheTypeK = other.cacheTypeK,
      cacheTypeV = other.cacheTypeV,
      kvUnified = other.kvUnified,
      ropeFrequencyBase = other.ropeFrequencyBase,
      ropeFrequencyScale = other.ropeFrequencyScale,
      cpuMoeLayers = other.cpuMoeLayers,
      moeCacheBytes = other.moeCacheBytes,
      preferMemory64 = other.preferMemory64,
      modelBytesHint = other.modelBytesHint;

  /// Validates the parameter combination. Throws [LlamaArgumentException]
  /// when a value is out of range or the combination is incompatible with
  /// llama.cpp (a non-F16 KV cache requires flashAttention != disabled, and a
  /// [moeCacheBytes] budget a nonzero [cpuMoeLayers]), or when [device]
  /// contradicts another field:
  /// - an explicit [device] with a [liteRtLmBackend] other than auto;
  /// - [ComputeDevice.cpu] with a GPU [preferredBackend] (Vulkan, Metal,
  ///   CUDA, OpenCL or HIP);
  /// - [ComputeDevice.gpu] or [ComputeDevice.npu] with a CPU or BLAS
  ///   [preferredBackend], with [gpuLayers] set to 0, or, on native platforms,
  ///   with [splitMode] [ModelSplitMode.none] and a negative [mainGpu].
  ///
  /// It also checks [gpuDevices] and [tensorSplit] as their documentation
  /// describes.
  ///
  /// `LlamaEngine` model loads call it before any download or native call,
  /// so callers don't have to remember it; call it directly to validate a
  /// `ModelParams` up front.
  void validate() {
    _validateDevice();
    _validateGpuDevices();
    if (liteRtLmPrefillChunkSize != null && liteRtLmPrefillChunkSize! <= 0) {
      throw _invalid(
        'liteRtLmPrefillChunkSize',
        liteRtLmPrefillChunkSize,
        'must be positive when provided',
      );
    }
    if (liteRtLmDispatchLibDir != null &&
        liteRtLmDispatchLibDir!.trim().isEmpty) {
      throw _invalid(
        'liteRtLmDispatchLibDir',
        liteRtLmDispatchLibDir,
        'must be non-empty when provided',
      );
    }
    if (liteRtLmCacheDir != null && liteRtLmCacheDir!.trim().isEmpty) {
      throw _invalid(
        'liteRtLmCacheDir',
        liteRtLmCacheDir,
        'must be non-empty when provided',
      );
    }
    if (liteRtLmMaxProgramCacheBytes != null &&
        liteRtLmMaxProgramCacheBytes! < unlimitedLiteRtLmProgramCacheBytes) {
      throw _invalid(
        'liteRtLmMaxProgramCacheBytes',
        liteRtLmMaxProgramCacheBytes,
        'must be non-negative, or '
            'ModelParams.unlimitedLiteRtLmProgramCacheBytes (-1) to keep '
            'every program cache',
      );
    }
    if (speculativeRollbackTokenMax < 0) {
      throw _invalid(
        'speculativeRollbackTokenMax',
        speculativeRollbackTokenMax,
        'must be non-negative',
      );
    }
    if (moeCacheBytes < 0) {
      throw _invalid('moeCacheBytes', moeCacheBytes, 'must be non-negative');
    }
    if (moeCacheBytes > 0 && cpuMoeLayers == 0) {
      throw _invalid(
        'moeCacheBytes',
        moeCacheBytes,
        'caches the MoE experts kept in host memory, so it needs a nonzero '
            'cpuMoeLayers (negative for every layer)',
      );
    }
    if ((cacheTypeK != KvCacheType.f16 || cacheTypeV != KvCacheType.f16) &&
        flashAttention == FlashAttention.disabled) {
      throw LlamaArgumentException(
        'Non-F16 KV cache (cacheTypeK=$cacheTypeK, cacheTypeV=$cacheTypeV) '
        'requires flashAttention != disabled. Either set flashAttention to '
        'auto/enabled or use KvCacheType.f16 for both.',
      );
    }
  }

  void _validateDevice() {
    if (device == ComputeDevice.auto) {
      return;
    }
    if (liteRtLmBackend != LiteRtLmBackendPreference.auto) {
      throw LlamaArgumentException(
        'ModelParams.device ${device.name} cannot be combined with the '
        'deprecated liteRtLmBackend ${liteRtLmBackend.name}. Set only device.',
        name: 'liteRtLmBackend',
        invalidValue: liteRtLmBackend.name,
      );
    }
    final cpuBackend =
        preferredBackend == GpuBackend.cpu ||
        preferredBackend == GpuBackend.blas;
    if (device == ComputeDevice.cpu) {
      if (!cpuBackend && preferredBackend != GpuBackend.auto) {
        throw LlamaArgumentException(
          'ModelParams.device cpu cannot be combined with the GPU '
          'preferredBackend ${preferredBackend.name}. Use GpuBackend.auto, '
          'cpu or blas.',
          name: 'preferredBackend',
          invalidValue: preferredBackend.name,
        );
      }
      return;
    }
    if (cpuBackend) {
      throw LlamaArgumentException(
        'ModelParams.device ${device.name} cannot be combined with '
        'preferredBackend ${preferredBackend.name}, which runs on the CPU. '
        'Use GpuBackend.auto or a GPU backend.',
        name: 'preferredBackend',
        invalidValue: preferredBackend.name,
      );
    }
    if (gpuLayers == 0) {
      throw LlamaArgumentException(
        'ModelParams.device ${device.name} cannot be combined with '
        'gpuLayers 0, which runs on the CPU. Leave gpuLayers at '
        'ModelParams.maxGpuLayers or set a positive count.',
        name: 'gpuLayers',
        invalidValue: gpuLayers,
      );
    }
    // The WebGPU bridge ignores negative main_gpu values; native llama.cpp
    // instead drops every device under split_mode NONE and loads on the CPU.
    if (!const bool.fromEnvironment('dart.library.js_interop') &&
        splitMode == ModelSplitMode.none &&
        mainGpu < 0) {
      throw LlamaArgumentException(
        'ModelParams.device ${device.name} cannot be combined with splitMode '
        'none and mainGpu $mainGpu, which llama.cpp runs on the CPU. Set '
        'mainGpu to a GPU index (0 or more).',
        name: 'mainGpu',
        invalidValue: mainGpu,
      );
    }
  }

  void _validateGpuDevices() {
    final devices = gpuDevices;
    final split = tensorSplit;
    if (devices == null && split == null) return;
    final field = devices != null ? 'gpuDevices' : 'tensorSplit';
    if (devices != null) {
      if (devices.isEmpty) {
        throw _invalid('gpuDevices', devices, 'must list at least one device');
      }
      if (devices.any((index) => index < 0)) {
        throw _invalid('gpuDevices', devices, 'must hold non-negative indices');
      }
      if (devices.toSet().length != devices.length) {
        throw _invalid('gpuDevices', devices, 'must not repeat a device');
      }
    }
    if (split != null) {
      if (split.isEmpty) {
        throw _invalid('tensorSplit', split, 'must hold at least one value');
      }
      if (split.any((value) => !value.isFinite || value < 0)) {
        throw _invalid(
          'tensorSplit',
          split,
          'must hold finite, non-negative proportions',
        );
      }
      if (split.fold<double>(0, (sum, value) => sum + value) <= 0) {
        throw _invalid('tensorSplit', split, 'must have a positive sum');
      }
      // llama.cpp stores the split as float32 and sums it in float32.
      final float32 = Float32List(2);
      for (final value in split) {
        float32[0] = value;
        if (value > 0 && float32[0] == 0) {
          throw _invalid(
            'tensorSplit',
            split,
            'must not hold a nonzero proportion of at most 2^-150 '
                '($_float32RoundsToZeroMax), which float32 rounds to 0',
          );
        }
        float32[1] = float32[1] + float32[0];
      }
      if (float32[1].isInfinite) {
        throw _invalid(
          'tensorSplit',
          split,
          'must hold proportions whose float32 sum is at most $_float32Max',
        );
      }
      if (devices != null && split.length != devices.length) {
        throw _invalid(
          'tensorSplit',
          split,
          'must hold one proportion per gpuDevices entry (${devices.length})',
        );
      }
    }
    if (splitMode == ModelSplitMode.none) {
      throw _invalid(
        field,
        devices ?? split,
        'needs a multi-GPU splitMode: ModelSplitMode.none runs on the mainGpu '
        'device alone, so set mainGpu instead',
      );
    }
    final cpuBackend =
        preferredBackend == GpuBackend.cpu ||
        preferredBackend == GpuBackend.blas;
    if (gpuLayers == 0 || device == ComputeDevice.cpu || cpuBackend) {
      throw _invalid(
        field,
        devices ?? split,
        'places offloaded layers, and this load offloads none (gpuLayers '
        '$gpuLayers, device ${device.name}, preferredBackend '
        '${preferredBackend.name})',
      );
    }
  }

  static const double _float32Max = 3.4028234663852886e38;

  /// 2^-150, half the smallest float32 subnormal, which rounds to 0 (ties to
  /// even), as every smaller value does.
  static const double _float32RoundsToZeroMax = 7.006492321624085e-46;

  LlamaArgumentException _invalid(
    String name,
    Object? value,
    String requirement,
  ) {
    final option = name.startsWith('liteRtLm')
        ? liteRtLmOptionName(this, name)
        : name;
    return LlamaArgumentException(
      '${modelParamsTypeName(this)}.$option $requirement (got $value).',
      name: option,
      invalidValue: value,
    );
  }

  /// Creates a copy of this [ModelParams] with updated fields.
  ///
  /// Nullable fields ([gpuDevices], [tensorSplit], [chatTemplate],
  /// [kvUnified], [ropeFrequencyBase], [ropeFrequencyScale]) use a sentinel
  /// pattern so callers can
  /// **explicitly clear them back to null** by passing the corresponding
  /// `clear*: true` flag. Without the sentinel, `null` would be
  /// indistinguishable from "argument omitted, keep current value".
  ModelParams copyWith({
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(embeddingEngine: ...). This will be removed in '
      '1.0.',
    )
    bool? liteRtLmEmbeddingEngine,
    int? contextSize,
    ComputeDevice? device,
    int? gpuLayers,
    GpuBackend? preferredBackend,
    @Deprecated(
      'Use device, which applies to every runtime. This will be removed in '
      '1.0.',
    )
    LiteRtLmBackendPreference? liteRtLmBackend,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(activationDataType: ...). This will be removed in '
      '1.0.',
    )
    LiteRtLmActivationDataType? liteRtLmActivationDataType,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearActivationDataType: true). This will be removed in '
      '1.0.',
    )
    bool clearLiteRtLmActivationDataType = false,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(prefillChunkSize: ...). This will be removed in '
      '1.0.',
    )
    int? liteRtLmPrefillChunkSize,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearPrefillChunkSize: true). This will be removed in '
      '1.0.',
    )
    bool clearLiteRtLmPrefillChunkSize = false,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(parallelFileSectionLoading: ...). This will be removed in '
      '1.0.',
    )
    bool? liteRtLmParallelFileSectionLoading,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearParallelFileSectionLoading: true). This will be removed in '
      '1.0.',
    )
    bool clearLiteRtLmParallelFileSectionLoading = false,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(dispatchLibDir: ...). This will be removed in '
      '1.0.',
    )
    String? liteRtLmDispatchLibDir,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearDispatchLibDir: true). This will be removed in '
      '1.0.',
    )
    bool clearLiteRtLmDispatchLibDir = false,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(cacheDir: ...). This will be removed in '
      '1.0.',
    )
    String? liteRtLmCacheDir,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearCacheDir: true). This will be removed in '
      '1.0.',
    )
    bool clearLiteRtLmCacheDir = false,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(maxProgramCacheBytes: ...). This will be removed in '
      '1.0.',
    )
    int? liteRtLmMaxProgramCacheBytes,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearMaxProgramCacheBytes: true). This will be removed in '
      '1.0.',
    )
    bool clearLiteRtLmMaxProgramCacheBytes = false,
    ModelSplitMode? splitMode,
    int? mainGpu,
    List<int>? gpuDevices,
    bool clearGpuDevices = false,
    List<double>? tensorSplit,
    bool clearTensorSplit = false,
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
    int? cpuMoeLayers,
    int? moeCacheBytes,
    bool? preferMemory64,
    bool clearPreferMemory64 = false,
    int? modelBytesHint,
    bool clearModelBytesHint = false,
  }) {
    return ModelParams(
      liteRtLmEmbeddingEngine:
          liteRtLmEmbeddingEngine ?? this.liteRtLmEmbeddingEngine,
      contextSize: contextSize ?? this.contextSize,
      device: device ?? this.device,
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
      liteRtLmCacheDir: clearLiteRtLmCacheDir
          ? null
          : (liteRtLmCacheDir ?? this.liteRtLmCacheDir),
      liteRtLmMaxProgramCacheBytes: clearLiteRtLmMaxProgramCacheBytes
          ? null
          : (liteRtLmMaxProgramCacheBytes ?? this.liteRtLmMaxProgramCacheBytes),
      splitMode: splitMode ?? this.splitMode,
      mainGpu: mainGpu ?? this.mainGpu,
      gpuDevices: clearGpuDevices ? null : (gpuDevices ?? this.gpuDevices),
      tensorSplit: clearTensorSplit ? null : (tensorSplit ?? this.tensorSplit),
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
      cpuMoeLayers: cpuMoeLayers ?? this.cpuMoeLayers,
      moeCacheBytes: moeCacheBytes ?? this.moeCacheBytes,
      preferMemory64: clearPreferMemory64
          ? null
          : (preferMemory64 ?? this.preferMemory64),
      modelBytesHint: clearModelBytesHint
          ? null
          : (modelBytesHint ?? this.modelBytesHint),
    );
  }
}

/// [ModelParams] for a GGUF model, which llama.cpp runs natively and on the
/// Web through the WebGPU bridge.
///
/// It takes only the fields llama.cpp applies, so a LiteRT-LM option cannot
/// be set by mistake, and a load of a LiteRT-LM model with it throws
/// `LlamaUnsupportedException`. Each field means what it does on
/// [ModelParams]. [useMmap] and [useMlock] apply natively only, and
/// [preferMemory64] and [modelBytesHint] on the Web only; a load elsewhere
/// throws `LlamaUnsupportedException` naming them.
///
/// ```dart
/// final engine = await LlamaEngine.load(
///   LlamaModel(ModelSource.path('path/to/model.gguf')),
///   params: const LlamaCppModelParams(contextSize: 8192, batchSize: 512),
/// );
/// ```
class LlamaCppModelParams extends ModelParams {
  /// Creates llama.cpp load parameters with [ModelParams]' defaults.
  const LlamaCppModelParams({
    super.contextSize,
    super.device,
    super.gpuLayers,
    super.preferredBackend,
    super.splitMode,
    super.mainGpu,
    super.gpuDevices,
    super.tensorSplit,
    super.loras,
    super.chatTemplate,
    super.numberOfThreads,
    super.numberOfThreadsBatch,
    super.batchSize,
    super.microBatchSize,
    super.maxParallelSequences,
    super.speculativeRollbackTokenMax,
    super.useMmap,
    super.useMlock,
    super.loadMtp,
    super.flashAttention,
    super.cacheTypeK,
    super.cacheTypeV,
    super.kvUnified,
    super.ropeFrequencyBase,
    super.ropeFrequencyScale,
    super.cpuMoeLayers,
    super.moeCacheBytes,
    super.preferMemory64,
    super.modelBytesHint,
  });

  LlamaCppModelParams._copy(super.other) : super._copy();

  /// Creates a copy with updated fields, as [ModelParams.copyWith] does.
  ///
  /// The `liteRtLm*` arguments and `clearLiteRtLm*` flags exist only to
  /// override [ModelParams.copyWith]: passing any of them, or setting a flag
  /// to true, throws [LlamaArgumentException], since llama.cpp does not
  /// apply them.
  @override
  LlamaCppModelParams copyWith({
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(embeddingEngine: ...). This will be '
      'removed in 1.0.',
    )
    bool? liteRtLmEmbeddingEngine,
    int? contextSize,
    ComputeDevice? device,
    int? gpuLayers,
    GpuBackend? preferredBackend,
    @Deprecated(
      'Use device, which applies to every runtime. This will be removed in '
      '1.0.',
    )
    LiteRtLmBackendPreference? liteRtLmBackend,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(activationDataType: ...). This will '
      'be removed in 1.0.',
    )
    LiteRtLmActivationDataType? liteRtLmActivationDataType,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearActivationDataType: true). This '
      'will be removed in 1.0.',
    )
    bool clearLiteRtLmActivationDataType = false,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(prefillChunkSize: ...). This will be '
      'removed in 1.0.',
    )
    int? liteRtLmPrefillChunkSize,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearPrefillChunkSize: true). This '
      'will be removed in 1.0.',
    )
    bool clearLiteRtLmPrefillChunkSize = false,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(parallelFileSectionLoading: ...). '
      'This will be removed in 1.0.',
    )
    bool? liteRtLmParallelFileSectionLoading,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearParallelFileSectionLoading: '
      'true). This will be removed in 1.0.',
    )
    bool clearLiteRtLmParallelFileSectionLoading = false,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(dispatchLibDir: ...). This will be '
      'removed in 1.0.',
    )
    String? liteRtLmDispatchLibDir,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearDispatchLibDir: true). This '
      'will be removed in 1.0.',
    )
    bool clearLiteRtLmDispatchLibDir = false,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(cacheDir: ...). This will be removed '
      'in 1.0.',
    )
    String? liteRtLmCacheDir,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearCacheDir: true). This will be '
      'removed in 1.0.',
    )
    bool clearLiteRtLmCacheDir = false,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(maxProgramCacheBytes: ...). This '
      'will be removed in 1.0.',
    )
    int? liteRtLmMaxProgramCacheBytes,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearMaxProgramCacheBytes: true). '
      'This will be removed in 1.0.',
    )
    bool clearLiteRtLmMaxProgramCacheBytes = false,
    ModelSplitMode? splitMode,
    int? mainGpu,
    List<int>? gpuDevices,
    bool clearGpuDevices = false,
    List<double>? tensorSplit,
    bool clearTensorSplit = false,
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
    int? cpuMoeLayers,
    int? moeCacheBytes,
    bool? preferMemory64,
    bool clearPreferMemory64 = false,
    int? modelBytesHint,
    bool clearModelBytesHint = false,
  }) {
    _rejectCopyArguments('LlamaCppModelParams', 'LiteRtLmModelParams', {
      'liteRtLmEmbeddingEngine': liteRtLmEmbeddingEngine,
      'liteRtLmBackend': liteRtLmBackend,
      'liteRtLmActivationDataType': liteRtLmActivationDataType,
      'liteRtLmPrefillChunkSize': liteRtLmPrefillChunkSize,
      'liteRtLmParallelFileSectionLoading': liteRtLmParallelFileSectionLoading,
      'liteRtLmDispatchLibDir': liteRtLmDispatchLibDir,
      'liteRtLmCacheDir': liteRtLmCacheDir,
      'liteRtLmMaxProgramCacheBytes': liteRtLmMaxProgramCacheBytes,
      if (clearLiteRtLmActivationDataType)
        'clearLiteRtLmActivationDataType': true,
      if (clearLiteRtLmPrefillChunkSize) 'clearLiteRtLmPrefillChunkSize': true,
      if (clearLiteRtLmParallelFileSectionLoading)
        'clearLiteRtLmParallelFileSectionLoading': true,
      if (clearLiteRtLmDispatchLibDir) 'clearLiteRtLmDispatchLibDir': true,
      if (clearLiteRtLmCacheDir) 'clearLiteRtLmCacheDir': true,
      if (clearLiteRtLmMaxProgramCacheBytes)
        'clearLiteRtLmMaxProgramCacheBytes': true,
    });
    return LlamaCppModelParams._copy(
      super.copyWith(
        contextSize: contextSize,
        device: device,
        gpuLayers: gpuLayers,
        preferredBackend: preferredBackend,
        splitMode: splitMode,
        mainGpu: mainGpu,
        gpuDevices: gpuDevices,
        clearGpuDevices: clearGpuDevices,
        tensorSplit: tensorSplit,
        clearTensorSplit: clearTensorSplit,
        loras: loras,
        chatTemplate: chatTemplate,
        clearChatTemplate: clearChatTemplate,
        numberOfThreads: numberOfThreads,
        numberOfThreadsBatch: numberOfThreadsBatch,
        batchSize: batchSize,
        microBatchSize: microBatchSize,
        maxParallelSequences: maxParallelSequences,
        speculativeRollbackTokenMax: speculativeRollbackTokenMax,
        useMmap: useMmap,
        useMlock: useMlock,
        loadMtp: loadMtp,
        flashAttention: flashAttention,
        cacheTypeK: cacheTypeK,
        cacheTypeV: cacheTypeV,
        kvUnified: kvUnified,
        clearKvUnified: clearKvUnified,
        ropeFrequencyBase: ropeFrequencyBase,
        clearRopeFrequencyBase: clearRopeFrequencyBase,
        ropeFrequencyScale: ropeFrequencyScale,
        clearRopeFrequencyScale: clearRopeFrequencyScale,
        cpuMoeLayers: cpuMoeLayers,
        moeCacheBytes: moeCacheBytes,
        preferMemory64: preferMemory64,
        clearPreferMemory64: clearPreferMemory64,
        modelBytesHint: modelBytesHint,
        clearModelBytesHint: clearModelBytesHint,
      ),
    );
  }
}

/// [ModelParams] for a LiteRT-LM (`.litertlm`) model, native or on the Web.
///
/// It takes only the fields LiteRT-LM applies, with the LiteRT-LM options
/// named without the `liteRtLm` prefix they carry on [ModelParams], and a
/// load of a GGUF model with it throws `LlamaUnsupportedException`.
/// [gpuLayers] is an all-or-CPU hint: `0` or [ModelParams.maxGpuLayers].
/// LiteRT-LM Web takes only [contextSize], [device], [gpuLayers],
/// [preferredBackend] and [chatTemplate]; a Web load with any other field
/// set throws `LlamaUnsupportedException` naming it.
///
/// ```dart
/// final engine = await LlamaEngine.load(
///   LlamaModel(ModelSource.path('path/to/model.litertlm')),
///   params: const LiteRtLmModelParams(
///     device: ComputeDevice.gpu,
///     cacheDir: '/path/to/cache',
///   ),
/// );
/// ```
class LiteRtLmModelParams extends ModelParams {
  /// Creates LiteRT-LM load parameters with [ModelParams]' defaults.
  ///
  /// [embeddingEngine], [activationDataType], [prefillChunkSize],
  /// [parallelFileSectionLoading], [dispatchLibDir], [cacheDir] and
  /// [maxProgramCacheBytes] set the matching `liteRtLm*` field of
  /// [ModelParams].
  const LiteRtLmModelParams({
    super.contextSize,
    super.device,
    super.gpuLayers,
    super.preferredBackend,
    super.loras,
    super.chatTemplate,
    super.numberOfThreads,
    bool embeddingEngine = false,
    LiteRtLmActivationDataType? activationDataType,
    int? prefillChunkSize,
    bool? parallelFileSectionLoading,
    String? dispatchLibDir,
    String? cacheDir,
    int? maxProgramCacheBytes,
  }) : super(
         liteRtLmEmbeddingEngine: embeddingEngine,
         liteRtLmActivationDataType: activationDataType,
         liteRtLmPrefillChunkSize: prefillChunkSize,
         liteRtLmParallelFileSectionLoading: parallelFileSectionLoading,
         liteRtLmDispatchLibDir: dispatchLibDir,
         liteRtLmCacheDir: cacheDir,
         liteRtLmMaxProgramCacheBytes: maxProgramCacheBytes,
       );

  LiteRtLmModelParams._copy(super.other) : super._copy();

  /// Whether the load creates LiteRT-LM's embedding engine; see
  /// [ModelParams.liteRtLmEmbeddingEngine].
  bool get embeddingEngine => liteRtLmEmbeddingEngine;

  /// See [ModelParams.liteRtLmActivationDataType].
  LiteRtLmActivationDataType? get activationDataType =>
      liteRtLmActivationDataType;

  /// See [ModelParams.liteRtLmPrefillChunkSize].
  int? get prefillChunkSize => liteRtLmPrefillChunkSize;

  /// See [ModelParams.liteRtLmParallelFileSectionLoading].
  bool? get parallelFileSectionLoading => liteRtLmParallelFileSectionLoading;

  /// See [ModelParams.liteRtLmDispatchLibDir].
  String? get dispatchLibDir => liteRtLmDispatchLibDir;

  /// See [ModelParams.liteRtLmCacheDir].
  String? get cacheDir => liteRtLmCacheDir;

  /// See [ModelParams.liteRtLmMaxProgramCacheBytes].
  int? get maxProgramCacheBytes => liteRtLmMaxProgramCacheBytes;

  /// Creates a copy with updated fields, as [ModelParams.copyWith] does.
  ///
  /// Use the unprefixed arguments, such as `cacheDir` and `clearCacheDir`;
  /// the deprecated `liteRtLm*` ones set the same fields. An unprefixed
  /// value wins over its `liteRtLm*` twin, and a clear flag of either
  /// spelling wins over any value for its field, as on
  /// [ModelParams.copyWith]. The llama.cpp-only arguments and `clear*` flags
  /// exist only to override [ModelParams.copyWith]: passing any of them, or
  /// setting a flag to true, throws [LlamaArgumentException], since
  /// LiteRT-LM does not apply them.
  @override
  LiteRtLmModelParams copyWith({
    bool? embeddingEngine,
    LiteRtLmActivationDataType? activationDataType,
    bool clearActivationDataType = false,
    int? prefillChunkSize,
    bool clearPrefillChunkSize = false,
    bool? parallelFileSectionLoading,
    bool clearParallelFileSectionLoading = false,
    String? dispatchLibDir,
    bool clearDispatchLibDir = false,
    String? cacheDir,
    bool clearCacheDir = false,
    int? maxProgramCacheBytes,
    bool clearMaxProgramCacheBytes = false,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(embeddingEngine: ...). This will be '
      'removed in 1.0.',
    )
    bool? liteRtLmEmbeddingEngine,
    int? contextSize,
    ComputeDevice? device,
    int? gpuLayers,
    GpuBackend? preferredBackend,
    @Deprecated(
      'Use device, which applies to every runtime. This will be removed in '
      '1.0.',
    )
    LiteRtLmBackendPreference? liteRtLmBackend,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(activationDataType: ...). This will '
      'be removed in 1.0.',
    )
    LiteRtLmActivationDataType? liteRtLmActivationDataType,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearActivationDataType: true). This '
      'will be removed in 1.0.',
    )
    bool clearLiteRtLmActivationDataType = false,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(prefillChunkSize: ...). This will be '
      'removed in 1.0.',
    )
    int? liteRtLmPrefillChunkSize,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearPrefillChunkSize: true). This '
      'will be removed in 1.0.',
    )
    bool clearLiteRtLmPrefillChunkSize = false,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(parallelFileSectionLoading: ...). '
      'This will be removed in 1.0.',
    )
    bool? liteRtLmParallelFileSectionLoading,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearParallelFileSectionLoading: '
      'true). This will be removed in 1.0.',
    )
    bool clearLiteRtLmParallelFileSectionLoading = false,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(dispatchLibDir: ...). This will be '
      'removed in 1.0.',
    )
    String? liteRtLmDispatchLibDir,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearDispatchLibDir: true). This '
      'will be removed in 1.0.',
    )
    bool clearLiteRtLmDispatchLibDir = false,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(cacheDir: ...). This will be removed '
      'in 1.0.',
    )
    String? liteRtLmCacheDir,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearCacheDir: true). This will be '
      'removed in 1.0.',
    )
    bool clearLiteRtLmCacheDir = false,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(maxProgramCacheBytes: ...). This '
      'will be removed in 1.0.',
    )
    int? liteRtLmMaxProgramCacheBytes,
    @Deprecated(
      'Use LiteRtLmModelParams.copyWith(clearMaxProgramCacheBytes: true). '
      'This will be removed in 1.0.',
    )
    bool clearLiteRtLmMaxProgramCacheBytes = false,
    ModelSplitMode? splitMode,
    int? mainGpu,
    List<int>? gpuDevices,
    bool clearGpuDevices = false,
    List<double>? tensorSplit,
    bool clearTensorSplit = false,
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
    int? cpuMoeLayers,
    int? moeCacheBytes,
    bool? preferMemory64,
    bool clearPreferMemory64 = false,
    int? modelBytesHint,
    bool clearModelBytesHint = false,
  }) {
    _rejectCopyArguments('LiteRtLmModelParams', 'LlamaCppModelParams', {
      'splitMode': splitMode,
      'mainGpu': mainGpu,
      'gpuDevices': gpuDevices,
      'tensorSplit': tensorSplit,
      'numberOfThreadsBatch': numberOfThreadsBatch,
      'batchSize': batchSize,
      'microBatchSize': microBatchSize,
      'maxParallelSequences': maxParallelSequences,
      'speculativeRollbackTokenMax': speculativeRollbackTokenMax,
      'useMmap': useMmap,
      'useMlock': useMlock,
      'loadMtp': loadMtp,
      'flashAttention': flashAttention,
      'cacheTypeK': cacheTypeK,
      'cacheTypeV': cacheTypeV,
      'kvUnified': kvUnified,
      'ropeFrequencyBase': ropeFrequencyBase,
      'ropeFrequencyScale': ropeFrequencyScale,
      'cpuMoeLayers': cpuMoeLayers,
      'moeCacheBytes': moeCacheBytes,
      'preferMemory64': preferMemory64,
      'modelBytesHint': modelBytesHint,
      if (clearGpuDevices) 'clearGpuDevices': true,
      if (clearTensorSplit) 'clearTensorSplit': true,
      if (clearKvUnified) 'clearKvUnified': true,
      if (clearRopeFrequencyBase) 'clearRopeFrequencyBase': true,
      if (clearRopeFrequencyScale) 'clearRopeFrequencyScale': true,
      if (clearPreferMemory64) 'clearPreferMemory64': true,
      if (clearModelBytesHint) 'clearModelBytesHint': true,
    });
    return LiteRtLmModelParams._copy(
      super.copyWith(
        liteRtLmEmbeddingEngine: embeddingEngine ?? liteRtLmEmbeddingEngine,
        contextSize: contextSize,
        device: device,
        gpuLayers: gpuLayers,
        preferredBackend: preferredBackend,
        liteRtLmBackend: liteRtLmBackend,
        liteRtLmActivationDataType:
            activationDataType ?? liteRtLmActivationDataType,
        clearLiteRtLmActivationDataType:
            clearActivationDataType || clearLiteRtLmActivationDataType,
        liteRtLmPrefillChunkSize: prefillChunkSize ?? liteRtLmPrefillChunkSize,
        clearLiteRtLmPrefillChunkSize:
            clearPrefillChunkSize || clearLiteRtLmPrefillChunkSize,
        liteRtLmParallelFileSectionLoading:
            parallelFileSectionLoading ?? liteRtLmParallelFileSectionLoading,
        clearLiteRtLmParallelFileSectionLoading:
            clearParallelFileSectionLoading ||
            clearLiteRtLmParallelFileSectionLoading,
        liteRtLmDispatchLibDir: dispatchLibDir ?? liteRtLmDispatchLibDir,
        clearLiteRtLmDispatchLibDir:
            clearDispatchLibDir || clearLiteRtLmDispatchLibDir,
        liteRtLmCacheDir: cacheDir ?? liteRtLmCacheDir,
        clearLiteRtLmCacheDir: clearCacheDir || clearLiteRtLmCacheDir,
        liteRtLmMaxProgramCacheBytes:
            maxProgramCacheBytes ?? liteRtLmMaxProgramCacheBytes,
        clearLiteRtLmMaxProgramCacheBytes:
            clearMaxProgramCacheBytes || clearLiteRtLmMaxProgramCacheBytes,
        loras: loras,
        chatTemplate: chatTemplate,
        clearChatTemplate: clearChatTemplate,
        numberOfThreads: numberOfThreads,
      ),
    );
  }
}

void _rejectCopyArguments(
  String type,
  String alternative,
  Map<String, Object?> arguments,
) {
  final given = [
    for (final MapEntry(:key, :value) in arguments.entries)
      if (value != null) key,
  ];
  if (given.isEmpty) return;
  throw LlamaArgumentException(
    '$type.copyWith does not take ${given.join(', ')}: its runtime does not '
    'apply them. Use $alternative for the other runtime.',
    name: given.first,
    invalidValue: arguments[given.first],
  );
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
