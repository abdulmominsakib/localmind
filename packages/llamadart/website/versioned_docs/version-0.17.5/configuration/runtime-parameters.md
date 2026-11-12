---
title: Model and generation parameters
sidebar_label: Runtime parameters
description: The ModelParams and GenerationParams settings that matter most, native LiteRT-LM runtime and cache controls, and practical defaults for chat and embedding workloads.
---

`ModelParams` apply at model load; `GenerationParams` apply per generation
call. `LlamaCppModelParams` (GGUF) and `LiteRtLmModelParams` (`.litertlm`) are
`ModelParams` that take only the fields their runtime applies; prefer them
when you know the model's runtime. A load throws `LlamaUnsupportedException`
when one is used for the other runtime. To decide which knob to change and what to measure, see
[Performance tuning](../guides/performance-tuning).

## ModelParams essentials

```dart
await engine.setModel(
  LlamaModel(ModelSource.path('/path/to/model.gguf')),
  params: const LlamaCppModelParams(
    contextSize: 4096,
    gpuLayers: ModelParams.maxGpuLayers,
    preferredBackend: GpuBackend.vulkan,
    splitMode: ModelSplitMode.layer,
    mainGpu: 0,
    numberOfThreads: 0,
    numberOfThreadsBatch: 0,
    batchSize: 0,
    microBatchSize: 0,
    maxParallelSequences: 1,
  ),
);
```

Important fields:

- `contextSize`: total context window.
- `device`: `ComputeDevice.auto` (default), `cpu`, `gpu` or `npu`, for every
  runtime. `auto` keeps each runtime's default; an explicit device runs there
  or throws `LlamaUnsupportedException`. On llama.cpp, `cpu` ignores
  `gpuLayers`; LiteRT-LM rejects a positive `gpuLayers` other than
  `ModelParams.maxGpuLayers` with any device. See
  [Choosing the device](../guides/backend-selection#choosing-the-device).
- `gpuLayers`: number of layers offloaded to GPU. `0` keeps the model on
  CPU; a negative value means all layers, as in llama.cpp, and every runtime
  treats it like `ModelParams.maxGpuLayers`.
- `preferredBackend`: backend preference (`auto`, `vulkan`, `metal`, etc).
  On native llama.cpp, `auto` loads on the CPU with 0 GPU layers on Android,
  an iOS simulator and macOS x86_64, Rosetta included ([#1597](https://github.com/leehack/llamadart/issues/1597)); an
  explicit GPU backend or `device: ComputeDevice.gpu` still loads on the GPU.
  On Linux and Windows, an explicit GPU backend whose module is missing loads
  the model on CPU with 0 GPU layers and logs a Dart warning;
  `getBackendName()` then reports `CPU`. With `device: ComputeDevice.gpu` the
  load throws `LlamaUnsupportedException` instead. See
  [When a requested backend is not bundled](../platforms/native-build-hooks#when-a-requested-backend-is-not-bundled).
- `splitMode`: model tensor distribution mode passed through to llama.cpp
  `split_mode`. Defaults to upstream `layer` behavior.
  `ModelSplitMode.row` needs llama.cpp split buffer types on every model
  device, which llama.cpp `v0.7.0` provides only on backends llamadart does
  not bundle (SYCL, Hexagon). On native llama.cpp a row split load whose
  devices lack them, as on every bundled GPU backend whose module loads, with `GpuBackend.blas`
  or `GpuBackend.cpu`, with `auto` on Android, the iOS simulator and macOS
  x86_64 (which runs on the CPU), and when the load falls back to the CPU because the requested
  backend is missing or Vulkan is refused, throws `LlamaUnsupportedException`
  naming the device before the model loads; use `ModelSplitMode.layer`. A bundled
  module that fails to load or finds no device loads row on the CPU instead.
- `gpuDevices`: the GPUs to load on, as the `GpuDeviceInfo.mainGpu` indices
  `LlamaEngine.listGpuDevices` reports for `preferredBackend`
  (llama.cpp `--device`). The list order is the split order. Under
  `GpuBackend.auto` it needs a host with one GPU backend; otherwise set
  `preferredBackend`. Where `auto` loads on the CPU, such as macOS x86_64,
  set a GPU `preferredBackend` or `device: ComputeDevice.gpu`. `ModelSplitMode.none` uses `mainGpu` instead.
- `tensorSplit`: one proportion per device, in `gpuDevices` order or the
  backend's listing order (llama.cpp `--tensor-split`); llama.cpp
  normalizes them and stores them as float32. `validate()` rejects empty
  lists, negative, NaN or infinite values, values above float32 range or
  nonzero values float32 rounds to 0, a zero sum or one above float32 range,
  and a length other than that of `gpuDevices`. Direct llama.cpp backend
  loads also reject a non-finite sum with `LlamaArgumentException` before loading.
  Native llama.cpp throws `LlamaUnsupportedException` before the model loads
  for a device index the host lacks, a split for another number of devices,
  several GPU backends under `auto`, and a load that would fall back to the
  CPU; the Web and LiteRT-LM reject both fields. After a load with either
  field, `getBackendName()` names the devices, such as `CUDA (CUDA0, CUDA2)`.
  A speculative draft model loads on the same devices and split, and
  decision heads and multimodal projectors run on the listed GPU `mainGpu`
  counts within the list, or the first one when it is out of range. Only GPUs
  and integrated GPUs with usable native device handles count for these
  auxiliary models; if the list has none (for example, it contains only
  accelerators), decision heads and projectors run on the CPU. Validated
  on one Metal GPU and on a Vulkan Tesla T4, with Mesa lavapipe as the second
  device for two-device lists and splits; two-GPU hardware has no evidence
  yet ([#1528](https://github.com/leehack/llamadart/issues/1528)), and CUDA is not
  hardware-qualified.

```dart
final engine = LlamaEngine(LlamaBackend());
// mainGpu counts the devices of one backend, so keep only CUDA devices.
final gpus = [
  for (final gpu in await engine.listGpuDevices(
    probeBackends: [GpuBackend.cuda],
  ))
    if (gpu.backend == GpuBackend.cuda) gpu,
];
await engine.setModel(
  LlamaModel(ModelSource.path('/path/to/model.gguf')),
  params: LlamaCppModelParams(
    preferredBackend: GpuBackend.cuda,
    gpuDevices: [gpus[0].mainGpu, gpus[2].mainGpu],
    tensorSplit: const [3, 1], // three quarters of the layers on the first
  ),
);
```
- `mainGpu`: primary GPU device index passed through to llama.cpp `main_gpu`.
  To select one GPU for the full model, use
  `splitMode: ModelSplitMode.none` with the desired `mainGpu` index.
  On native llama.cpp with `device: ComputeDevice.auto`, a negative index
  in that mode selects no GPU: `getBackendName()` and `capabilities.backendName`
  report `CPU`, and `getResolvedGpuLayers()` reports `0`. Decision heads
  follow this CPU placement and report `CPU` in `DecisionModelInfo.deviceName`.
  Model context and draft-model settings are unchanged. Other split modes do
  not use a negative `mainGpu` to disable GPUs. Explicit `gpu` and
  `npu` requests still reject the single-device negative-index combination
  with `LlamaArgumentException`.
- `cpuMoeLayers`: keeps the Mixture-of-Experts expert weights of the first N
  layers in host memory, as llama.cpp's `--n-cpu-moe` does; a negative value
  keeps every layer's experts there, as `--cpu-moe` does. Other weights still
  follow `gpuLayers`. A model without experts throws
  `LlamaUnsupportedException` after it loads.
- `moeCacheBytes`: device memory budget in bytes for llama.cpp's
  experimental GPU cache of those host experts (`--moe-cache-mib`, which
  takes MiB). `0` disables it; it needs a nonzero `cpuMoeLayers`, and the
  load then disables CPU weight repacking so the experts stay cacheable. It
  runs on Metal and CUDA; with a budget, a load that offloads nothing,
  `ModelSplitMode.tensor`, Vulkan (llama.cpp aborts:
  [ggml-org/llama.cpp#30697](https://github.com/ggml-org/llama.cpp/issues/30697))
  and other backends throw `LlamaUnsupportedException` before the model
  loads; `cpuMoeLayers` alone runs on any backend. A budget the GPU cannot
  allocate, or too small for one token's experts, fails the load with
  `LlamaModelException` naming `moeCacheBytes`. Validated on Metal only,
  where the GPU shares system memory and the cache only adds copies; CUDA
  and multi-GPU hosts have no hardware evidence yet, and no speed-up is
  claimed.

```dart
const params = LlamaCppModelParams(
  cpuMoeLayers: -1, // every layer's experts stay in host memory
  moeCacheBytes: 4 << 30, // keep up to 4 GiB of recently used experts on the GPU
);
```
- `batchSize`: context logical batch size (`n_batch`). On native,
  decoder/generative models use the llama.cpp-aligned `min(n_ctx, 2048)`
  default when this is `0`. Native encoder-only models retain a full-context
  logical batch so embedding inputs are not split incorrectly. WebGPU keeps
  full-context automatic batching because model architecture is not available
  before bridge context creation, though model-specific safety presets may be
  smaller; the presets are in
  [Performance tuning](../guides/performance-tuning).
- `microBatchSize`: context physical micro-batch size (`n_ubatch`). On native,
  decoder/generative models use `min(n_batch, 512)` when this is `0`, while
  encoder-only models retain the resolved logical batch. WebGPU follows its
  resolved logical batch unless a safety preset applies. On Android, a context that runs on
  Vulkan keeps that `n_ubatch` but can decode a text prompt in smaller micro-batches when this is `0`, and an
  explicit value above `32` can
  return wrong text on some GPUs
  ([Android llama.cpp Vulkan](../platforms/known-platform-issues#android)).
  Explicit positive values are preserved within
  `n_ubatch <= n_batch <= n_ctx`. Native
  encoder-only models, models without a KV cache (such as BERT and ModernBERT),
  non-causal attention models, and MEAN/CLS pooling embed each input in one
  micro-batch. `embed()` and `embedBatch()` throw `LlamaInferenceException`
  for longer input; raise `microBatchSize` and `batchSize` or shorten the input.
  llama.cpp also decodes the images of some projectors with non-causal
  attention (Gemma 3 and Gemma 4 other than E2B and E4B, among others), and
  cannot split such an image across micro-batches: when the image has more
  tokens than `n_ubatch` and `n_batch` is larger than `n_ubatch`, as with the
  defaults, the prompt throws `LlamaInferenceException` before anything is
  decoded. With `n_batch` equal to `n_ubatch` the image is decoded in several
  batches instead, with a logged warning, which can reduce accuracy. The
  default of `512` does not hold the largest Gemma 4 images
  ([Image input exceeds `n_ubatch`](../troubleshooting/common-issues#image-input-exceeds-n_ubatch)).
- `maxParallelSequences`: max sequence slots (`n_seq_max`) for parallel
  sequence workloads (for example, batched embeddings).
- `loadMtp` (llama.cpp, native and WebGPU): load MTP tensors embedded in the
  target GGUF. Defaults to `false` because the tensors cost memory; set it to
  `true` when `SpeculativeDecodingConfig.mtp(...)` runs without a
  `draftModel`. WebGPU passes it, and `speculativeRollbackTokenMax`, to
  the bridge only when set; bridge assets without speculative decoding ignore
  both.
- `speculativeRollbackTokenMax` (llama.cpp): native recurrent or hybrid models
  reject a nonzero value with `LlamaUnsupportedException` before context
  creation. The pinned runtime cannot establish a safe rollback graph budget.
  Leave it at `0` for ordinary generation; strategies requiring rollback
  snapshots on those models remain unsupported. Non-recurrent native models
  and WebGPU retain their runtime behavior.
- `chatTemplate`: Jinja chat template that replaces the model's own. On GGUF
  models, like llama.cpp's `--chat-template-file`, `engine.create` and
  `engine.chatTemplate` render the prompt and parse tool calls and reasoning
  with it instead of the embedded template and its `tool_use` variant; null
  or empty keeps the embedded template. On `.litertlm` models it replaces the
  built-in template (an empty string included); see
  [Chat templates](../guides/chat-template-and-parsing#litert-lm-template-registry)
  for when native LiteRT-LM uses it and for the list-of-parts `content` it
  passes. A per-call `customTemplate` wins. The value is Jinja
  source: names such as `chatml` are not mapped to llama.cpp's built-in
  templates. `engine.getMetadata()` still reports the GGUF template.
- `preferMemory64` / `modelBytesHint` (web/WebGPU only): select the 64-bit
  (mem64) bridge core; see
  [Model size and memory64](../platforms/webgpu-bridge#model-size-and-memory64).
  Native loads reject them.
- LiteRT-LM options: set them with `LiteRtLmModelParams`; see
  [LiteRT-LM runtime controls](#litert-lm-runtime-controls). The matching
  `liteRtLm*` arguments of `ModelParams` are deprecated, and llama.cpp loads
  reject them.
- `useMmap` / `useMlock` (native llama.cpp only): the WebGPU bridge rejects
  `useMmap: false` and `useMlock: true`.

Apart from `gpuLayers` under `device: ComputeDevice.cpu` on llama.cpp, and
`loadMtp` and `speculativeRollbackTokenMax` on bridge assets without
speculative decoding, no runtime ignores a field you set. A load throws `LlamaUnsupportedException`
naming each field set away from its default that the model's runtime does
not apply. When `ModelSource.format` or the model's file name names the
format, `LlamaBackend()` rejects them before any file resolves or downloads;
otherwise the load rejects them before the runtime starts.

- `loras` (llama.cpp, native and WebGPU): LoRA adapters applied at their
  scales once the model loads; an adapter that cannot be applied fails the
  load. WebGPU needs assets whose LoRA probe reports support.

For runtime LoRA control (`setLoraSource`, `removeLoraSource`, `clearLoras`), see
[LoRA Adapters](../guides/lora-adapters).

## LiteRT-LM runtime controls

Native `.litertlm` loads accept `contextSize`, `chatTemplate` and the
`LiteRtLmModelParams` arguments below. The LiteRT-LM tuning options default to
`null`, which keeps the pinned runtime default. Each one sets the
`ModelParams` field with a `liteRtLm` prefix (`cacheDir` sets
`liteRtLmCacheDir`); the prefixed `ModelParams` and `copyWith` arguments are
deprecated until 1.0.

| Argument | Effect |
| --- | --- |
| `device` | `ComputeDevice.auto` (default), `cpu`, `gpu`, or `npu` (Android). `auto` uses `cpu` when `gpuLayers` is `0`, otherwise it maps `preferredBackend`. |
| `ModelParams.liteRtLmBackend` | Deprecated until 1.0: use `device`. Under `device: auto` it still selects the LiteRT-LM backend alone. |
| `activationDataType` | Activation type override: `float32`, `float16`, `int16`, or `int8`. Forwarded to `litert_lm_engine_settings_set_activation_data_type`. |
| `prefillChunkSize` | Prefill chunk size for CPU dynamic models. Must be positive. |
| `parallelFileSectionLoading` | `false` disables parallel `.litertlm` file-section loading, for diagnostics. `null` keeps parallel loading. |
| `dispatchLibDir` | LiteRT dispatch library directory for Android NPU deployments. Must be non-empty. |
| `cacheDir`, `maxProgramCacheBytes` | Runtime cache directory and GPU program cache size cap; see [LiteRT-LM cache directory](#litert-lm-cache-directory). |
| `numberOfThreads` | Generation thread count; `0` keeps automatic selection. |
| `embeddingEngine` | `true` selects the separate LiteRT-LM embedding engine, qualified on CPU on macOS, iOS and Android arm64; defaults to `false`, not `null`. See [Embeddings](../guides/embeddings). |
| `loras` | At most one adapter, at the default scale of `1.0`, loaded with the model. Runtime LoRA APIs, stacking and custom scales are llama.cpp-only. |

`gpuLayers` must be `0` (CPU), `ModelParams.maxGpuLayers` or a negative
value, which means all layers like `maxGpuLayers`. Native
LiteRT-LM rejects llama.cpp-specific fields such as `batchSize`,
`numberOfThreadsBatch`, `splitMode`, `mainGpu`, `gpuDevices`, `tensorSplit`
or KV-cache types: the load
throws `LlamaUnsupportedException` naming each rejected field, so a GGUF
tuning profile never appears to apply silently. That includes `loadMtp`,
`speculativeRollbackTokenMax`, `cpuMoeLayers`, `moeCacheBytes`,
`preferMemory64` and `modelBytesHint`.
LiteRT-LM web accepts `device` or `liteRtLmBackend` for CPU or GPU selection
and rejects every other field in the table the same way.

Benchmark load time, prefill and decode throughput, and output quality on the
deployment device after changing the activation type or prefill chunk size.

## LiteRT-LM cache directory

The native LiteRT-LM runtime writes cache files such as
`*_mldrift_program_cache.bin` (GPU programs), `*_mldrift_weight_cache.bin`
(GPU weights) and `*.xnnpack_cache`. llamadart only chooses the directory:

| `cacheDir` | macOS, Android | Other native platforms |
| --- | --- | --- |
| `null` (default) | `llamadart_litert_lm` under `Directory.systemTemp` | No directory is passed; the runtime caches next to the model file |
| A path | That directory, created when missing | That directory, created when missing |

On Linux and iOS, when the model file is in a directory the process cannot
write, such as an iOS app bundle, one named without `.litertlm` loads with the
runtime caches turned off, so each engine create rebuilds what they would
hold. One named `.litertlm` keeps the runtime default on the CPU backend,
which reads caches already next to the file and otherwise runs uncached. On
the GPU backend it reads the text model's weight and program caches already
there for that exact file, and runs uncached when they are missing, when the
runtime rejects them, or when the engine also runs vision, audio or
speculative decoding. Set `cacheDir` to a writable directory to keep
every cache. Windows has no such check: set `cacheDir` there when the
model's directory is read-only.

`maxProgramCacheBytes` caps the GPU program cache files of one cache
directory. `null` (default) applies
`ModelParams.defaultLiteRtLmMaxProgramCacheBytes`, 1 GiB. Before each engine
create, llamadart deletes regular files directly inside the effective cache
directory whose name ends with `_mldrift_program_cache.bin` until their total
size is at most the cap: files larger than the cap on their own first, then
the least recently modified ones. `0` deletes every non-empty program cache
file. Weight and XNNPACK caches, subdirectories and symbolic links are left
alone. When no directory is passed to the runtime, nothing is pruned; set
`cacheDir` to enable pruning there. A directory named `:nocache` is
never pruned either. Each deletion, and each prune failure, logs a Dart `warn`
record and never fails the load (see [Logging](./logging)).

| `maxProgramCacheBytes` | Before each engine create |
| --- | --- |
| `null` (default) | Prune to 1 GiB |
| `0` or more | Prune to that many bytes |
| `ModelParams.unlimitedLiteRtLmProgramCacheBytes` (`-1`) | Delete nothing |

```dart
const params = LiteRtLmModelParams(
  cacheDir: '/data/app/litert-cache',
  // Raise the cap, or pass ModelParams.unlimitedLiteRtLmProgramCacheBytes.
  maxProgramCacheBytes: 4 * 1024 * 1024 * 1024,
);
```

Engines that share a cache directory, in one process or several, do not
delete each other's program caches. While a native engine is alive, llamadart
keeps two `.llamadart_litert_lm_lease_*` files in its cache directory naming
the model file, and holds a file lock on one of them. Pruning keeps, and does
not count toward the cap, the program caches named after a model with a lease,
including the vision encoder's. A lease of another process counts while that
process holds its lock, so a process that ends releases it, and a later prune
deletes its files. A lease of the same process counts until its engine is
disposed, or until the process exits when the engine's worker was stopped
without disposing it. An engine prunes the caches of its own model, since it
disposes its previous native engine first, but while two engines use the same
model file with one directory neither deletes that model's program caches.
The native engine, and so its lease, starts at the first generation or
tokenization after `loadModel`, not at `loadModel` itself. Until then another
engine pruning the same directory may delete that model's program caches,
which costs a one-time recompile on the first generation.

A lease left by a process that crashed is taken for one of the pruning
process when the two share a process ID, as can happen when a container
restarts with the same PID. That lease never expires, so its model's program
caches stay unpruned until its two lease files are deleted while no engine of
that model is running.

The cap guards against runtime cache growth: with some models the GPU
backend appends to `*_mldrift_program_cache.bin` on every engine create
([LiteRT-LM#2503](https://github.com/google-ai-edge/LiteRT-LM/issues/2503)).
llamadart can create an engine more than once per loaded model: on the
first generation, tokenization or detokenization after each context create,
and again when speculative decoding, vision, audio or image-count settings
change.

The cache file names carry the model file's name, modification time and size,
so replacing a model file leaves its old caches in place. In a directory
llamadart prunes, the default cap deletes them once their total exceeds 1 GiB;
to reclaim the bytes sooner, delete the `*_mldrift_program_cache.bin` files or
run once with `maxProgramCacheBytes: 0`.

The runtime fails engine creation when it cannot write the cache directory,
on the CPU backend too. A missing `cacheDir` is created, so this affects a
directory that exists and is read-only. The first generation then throws
`LlamaModelException`, or `LlamaUnsupportedException` when
`ComputeDevice.gpu` or `ComputeDevice.npu` was requested.

## Embedding-oriented model params

For `embedBatch(...)`, set `batchSize` and `microBatchSize` explicitly for the
workload and raise `maxParallelSequences` above `1` for true multi-sequence
batching. The decoder defaults do not replace embedding tuning. See
[Embeddings](../guides/embeddings#throughput-tuning-for-embedbatch).

## GenerationParams essentials

For native LiteRT-LM CPU/GPU and LiteRT-LM Web generation, `temp: 0` selects
greedy decoding: llamadart uses `topK: 1` regardless of the requested top-k
value. Positive temperatures retain the requested sampling settings.

```dart
const params = GenerationParams(
  maxTokens: 512,
  temp: 0.7,
  topK: 40,
  topP: 0.9,
  minP: 0.0,
  penalty: 1.1,
  presencePenalty: 0.0,
  stopSequences: ['</s>'],
  thinkingBudget: null,
  speculativeDecoding: false,
  speculativeDecodingConfig: null,
);
```

Important fields:

- `maxTokens`: generation length cap.
- `temp`: randomness.
- `topK`, `topP`, `minP`: token filtering controls. WebGPU applies a
  non-zero `minP` only with bridge assets whose `getCompletionCapabilities()`
  reports `minP` and otherwise rejects it; LiteRT-LM rejects it.
- `penalty`: repeat penalty.
- `presencePenalty`: llama.cpp presence penalty; `0.0` preserves the
  existing behavior. WebGPU applies it only with bridge assets whose
  `getCompletionCapabilities()` reports `presencePenalty`. Other WebGPU assets
  and LiteRT-LM web reject non-zero values rather than silently ignoring them.
- Native LiteRT-LM applies `penalty` and `presencePenalty` through its
  per-send repetition penalty API. They
  count only the tokens the current send generates, not the prompt or
  earlier turns, so outputs differ from llama.cpp. The default `penalty` of
  `1.1` stays unapplied so default requests keep their output; a `penalty`
  below `1.0` or combined with speculative decoding throws
  `LlamaUnsupportedException`.
- `thinkingBudget`: llama.cpp reasoning-token cap, native with the
  reasoning-budget API exported, or WebGPU with bridge assets whose `getCompletionCapabilities()` reports `thinkingBudget`.
  Use `ThinkingBudget(maxTokens: ...)` with `engine.create(...)` to use
  template delimiters automatically, or specify `startTag` and `endTag` for
  raw generation. `0` forces the end delimiter immediately. Any `thinkingBudget`
  is incompatible with speculative decoding, and unsupported backends reject
  it explicitly. Native LiteRT-LM applies it to native chat generation on
  bundles whose first response channel is a thinking channel, such as Gemma
  4: it caps the tokens in that channel, then closes it with the bundle's own
  end marker, so `startTag` and `endTag` do not apply. It rejects `0`
  (LiteRT-LM reads a zero budget as none), `forcedMessage` and raw prompt
  generation. `maxTokens` still counts thinking tokens.
- `speculativeDecoding` / `speculativeDecodingConfig`: opt-in speculative
  decoding. Native LiteRT-LM uses the boolean, or a
  `SpeculativeDecodingConfig.backendDefault()` or `.mtp()` config without
  draft tuning, on bundles that carry a speculative drafter; native llama.cpp takes any `SpeculativeDecodingConfig`
  strategy, and `draftMicroBatchSize` sizes its draft context's micro-batch.
  `draftModel` is a `ModelSource` that native backends download
  and cache when a generation starts, with `draftModelDownload`. WebGPU takes
  the strategies its bridge assets report, with a remote `draftModel` whose
  URL the runtime fetches, and URLs for the n-gram cache paths, and rejects
  `draftMicroBatchSize`. LiteRT-LM web rejects both.
  See [Speculative decoding](../guides/performance-tuning#speculative-decoding).
- `seed`: deterministic replay when set.
- `grammar`: constrained decoding with GBNF.

After a model loads, `engine.capabilities` reports which of these options the
runtime applies. A request that sets one it reports `false` to a value other
than the default throws `LlamaUnsupportedException`:

| Option | `LlamaEngineCapabilities` field | llama.cpp native | WebGPU | LiteRT-LM native | LiteRT-LM web |
| --- | --- | --- | --- | --- | --- |
| `penalty` | `supportsPenalty` | Yes | Yes | Runtime export resolves | No |
| `presencePenalty` | `supportsPresencePenalty` | Yes | Bridge reports | Runtime export resolves | No |
| `minP` | `supportsMinP` | Yes | Bridge reports | No | No |
| `thinkingBudget` | `supportsThinkingBudget` | Runtime export resolves | Bridge reports | Runtime export resolves and the bundle declares a thinking channel | No |
| `grammar`, `grammarTriggers`, `preservedTokens` | `supportsGrammar` | Yes | Yes | No | No |
| `grammarLazy` | `supportsLazyGrammar` | Yes | No | No | No |
| Stream batching thresholds | `supportsStreamBatching` | Yes | Ignored | Yes | No |
| Speculative strategies | `speculativeDecodingStrategies` | All, subject to draft/model requirements | Bridge reports | `backendDefault`, `mtp` unless the bundle declares no drafter | None |

Native llama.cpp keeps `mtp` in the set because it accepts an external MTP
`draftModel`. In-file MTP instead needs a target model with an MTP head and
`loadMtp: true`. The `draftSimple`, `draftEagle3`, `draftDflash` and `draftDspark`
strategies require `draftModel`; a missing draft throws `LlamaArgumentException`
at generation start. Advertising a strategy does not waive these requirements.

Every field is `false`, and the strategy set empty, before a load. Native
LiteRT-LM reads speculative, image and audio support from the bundle's
declaration, which can under-report ([litert-lm-native#60](https://github.com/leehack/litert-lm-native/issues/60)); such a `false` does not
reject the request, and a runtime failure it explains throws
`LlamaUnsupportedException`. Use it to
send a control only where it applies:

```dart
final capabilities = await engine.capabilities;
final params = GenerationParams(
  minP: capabilities.supportsMinP ? 0.05 : 0.0,
  penalty: capabilities.supportsPenalty ? 1.1 : const GenerationParams().penalty,
);
```

`engine.backendGenerationCapabilities` is deprecated; `capabilities` reports
the same controls and the rest.

Native GGUF `stopSequences` suppress the first completed marker and any text
following it, including markers split across tokens or embedded inside a token.
Text before the marker is returned in full, and chat content keeps whitespace
that ends there. Empty stops are ignored. Unfinished marker prefixes are emitted when generation
ends without a match. Template tokens listed in `preservedTokens` remain
available to the chat parser; identical stop entries are excluded from native
text matching. This applies to ordinary and speculative generation, and
WebGPU excludes the same stop entries.

## Practical tuning defaults

- Deterministic extraction: lower `temp` (`0.1-0.3`) + explicit stops.
- General chat: `temp` around `0.6-0.9`, `topP` around `0.9-0.95`.
- Tool calling: stable `temp` and sufficient `maxTokens` for call payload.
