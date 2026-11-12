---
title: Model and generation parameters
sidebar_label: Runtime parameters
description: The ModelParams and GenerationParams settings that matter most, native LiteRT-LM runtime and cache controls, and practical defaults for chat and embedding workloads.
---

`ModelParams` apply at model load; `GenerationParams` apply per generation
call. To decide which knob to change and what to measure, see
[Performance tuning](../guides/performance-tuning).

## ModelParams essentials

```dart
await engine.setModel(
  LlamaModel(ModelSource.path('/path/to/model.gguf')),
  params: const ModelParams(
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
  `gpuLayers`; LiteRT-LM rejects a `gpuLayers` other than `0` or
  `ModelParams.maxGpuLayers` with any device. See
  [Choosing the device](../guides/backend-selection#choosing-the-device).
- `gpuLayers`: number of layers offloaded to GPU.
- `preferredBackend`: backend preference (`auto`, `vulkan`, `metal`, etc).
  On Linux and Windows, an explicit GPU backend whose module is missing loads
  the model on CPU with 0 GPU layers and logs a Dart warning;
  `getBackendName()` then reports `CPU`. With `device: ComputeDevice.gpu` the
  load throws `LlamaUnsupportedException` instead. See
  [When a requested backend is not bundled](../platforms/native-build-hooks#when-a-requested-backend-is-not-bundled).
- `splitMode`: model tensor distribution mode passed through to llama.cpp
  `split_mode`. Defaults to upstream `layer` behavior.
- `mainGpu`: primary GPU device index passed through to llama.cpp `main_gpu`.
  To select one GPU for the full model, use
  `splitMode: ModelSplitMode.none` with the desired `mainGpu` index.
- `batchSize`: context logical batch size (`n_batch`). On native,
  decoder/generative models use the llama.cpp-aligned `min(n_ctx, 2048)`
  default when this is `0`. Native encoder-only models retain a full-context
  logical batch so embedding inputs are not split incorrectly. WebGPU keeps
  full-context automatic batching because model architecture is not available
  before bridge context creation, though model-specific safety presets may be
  smaller. The Qwen3.5-0.8B URL preset uses native decoder defaults on
  CPU (`preferredBackend: GpuBackend.cpu` or `gpuLayers: 0`); other models
  keep full-context defaults.
- `microBatchSize`: context physical micro-batch size (`n_ubatch`). On native,
  decoder/generative models use `min(n_batch, 512)` when this is `0`, while
  encoder-only models retain the resolved logical batch. WebGPU follows its
  resolved logical batch unless a safety preset applies; the Qwen3.5-0.8B
  CPU preset uses `min(n_batch, 512)`. On Android, a llama.cpp context that
  runs on Vulkan keeps that `n_ubatch` but decodes a text prompt at most `8`
  tokens at a time when this is `0`, and an explicit value above `32` can
  return wrong text on some GPUs
  ([known limitations](../platforms/support-matrix#known-limitations)).
  The cap applies to text-prompt decoding only: it does not cover prompts
  with image or audio input, embeddings, decision models, text-to-speech, or
  speculative-decoding verification batches during generation, which can
  exceed `32` tokens, so speculative decoding can still produce wrong output
  on an affected GPU.
  Explicit positive values are preserved within
  `n_ubatch <= n_batch <= n_ctx`. Native
  encoder-only models, models without a KV cache (such as BERT and ModernBERT),
  non-causal attention models, and MEAN/CLS pooling embed each input in one
  micro-batch. `embed()` and `embedBatch()` throw `LlamaInferenceException`
  for longer input; raise `microBatchSize` and `batchSize` or shorten the input.
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
  [Chat templates](../guides/chat-template-and-parsing) for when native
  LiteRT-LM uses it. A per-call `customTemplate` wins. The value is Jinja
  source: names such as `chatml` are not mapped to llama.cpp's built-in
  templates. `engine.getMetadata()` still reports the GGUF template.
- `preferMemory64` / `modelBytesHint` (web/WebGPU only): select the 64-bit
  (mem64) bridge core; see
  [Model size and memory64](../platforms/webgpu-bridge#model-size-and-memory64).
  Ignored on native backends.
- `liteRtLm*` fields: native LiteRT-LM `.litertlm` loads only; see
  [LiteRT-LM runtime controls](#litert-lm-runtime-controls).

- `loras` (llama.cpp, native and WebGPU): LoRA adapters applied at their
  scales once the model loads; an adapter that cannot be applied fails the
  load. WebGPU needs bridge assets `v0.1.54+`.

For runtime LoRA control (`setLoraSource`, `removeLoraSource`, `clearLoras`), see
[LoRA Adapters](../guides/lora-adapters).

## LiteRT-LM runtime controls

Native `.litertlm` loads accept `contextSize`, `chatTemplate` and the fields
below. The `liteRtLm*` tuning fields default to `null`, which keeps the pinned
runtime default.

| Field | Effect |
| --- | --- |
| `device` | `ComputeDevice.auto` (default), `cpu`, `gpu`, or `npu` (Android). `auto` uses `cpu` when `gpuLayers` is `0`, otherwise it maps `preferredBackend`. |
| `liteRtLmBackend` | Deprecated until 1.0: use `device`. Under `device: auto` it still selects the LiteRT-LM backend alone. |
| `liteRtLmActivationDataType` | Activation type override: `float32`, `float16`, `int16`, or `int8`. Forwarded to `litert_lm_engine_settings_set_activation_data_type`. |
| `liteRtLmPrefillChunkSize` | Prefill chunk size for CPU dynamic models. Must be positive. |
| `liteRtLmParallelFileSectionLoading` | `false` disables parallel `.litertlm` file-section loading, for diagnostics. `null` keeps parallel loading. |
| `liteRtLmDispatchLibDir` | LiteRT dispatch library directory for Android NPU deployments. Must be non-empty. |
| `liteRtLmCacheDir`, `liteRtLmMaxProgramCacheBytes` | Runtime cache directory and GPU program cache size cap; see [LiteRT-LM cache directory](#litert-lm-cache-directory). |
| `numberOfThreads` | Generation thread count; `0` keeps automatic selection. |
| `loras` | At most one adapter, at the default scale of `1.0`, loaded with the model. Runtime LoRA APIs, stacking and custom scales are llama.cpp-only. |

`gpuLayers` must be `0` (CPU) or `ModelParams.maxGpuLayers`. Native
LiteRT-LM rejects llama.cpp-specific fields such as `batchSize`,
`numberOfThreadsBatch`, `splitMode`, `mainGpu` or KV-cache types: the load
throws `LlamaUnsupportedException` naming each rejected field, so a GGUF
tuning profile never appears to apply silently. LiteRT-LM web
accepts `device` or `liteRtLmBackend` for CPU or GPU selection and rejects
every other field in the table the same way.

Benchmark load time, prefill and decode throughput, and output quality on the
deployment device after changing the activation type or prefill chunk size.
The LiteRT-LM smoke tool for a repository checkout is in
[Backend benchmarks](../guides/backend-benchmarks#reproducing).

## LiteRT-LM cache directory

The native LiteRT-LM runtime writes cache files such as
`*_mldrift_program_cache.bin` (GPU programs), `*_mldrift_weight_cache.bin`
(GPU weights) and `*.xnnpack_cache`. llamadart only chooses the directory:

| `liteRtLmCacheDir` | macOS, Android | Other native platforms |
| --- | --- | --- |
| `null` (default) | `llamadart_litert_lm` under `Directory.systemTemp` | No directory is passed; the runtime caches next to the model file |
| A path | That directory, created when missing | That directory, created when missing |

`liteRtLmMaxProgramCacheBytes` caps GPU program cache files. `null` (default)
never deletes anything. Otherwise, before each engine create, llamadart
deletes regular files directly inside the effective cache directory whose name
ends with `_mldrift_program_cache.bin` and whose size exceeds the cap. Weight
and XNNPACK caches, subdirectories and symbolic links are left alone. When no
directory is passed to the runtime, nothing is pruned; set `liteRtLmCacheDir`
to enable pruning there. Each deletion, and each prune failure, logs a Dart
`warn` record and never fails the load (see [Logging](./logging)).

```dart
const params = ModelParams(
  liteRtLmCacheDir: '/data/app/litert-cache',
  liteRtLmMaxProgramCacheBytes: 1024 * 1024 * 1024,
);
```

The cap mitigates a known runtime issue
([#552](https://github.com/leehack/llamadart/issues/552)): with Qwen3.5-0.8B
on the macOS GPU backend, every engine create appended about 0.5 GB to
`*_mldrift_program_cache.bin`, later creates logged
`Deserialization failed: DATA_LOSS`, and deleting the file did not slow engine
create. llamadart can create an engine more than once per loaded model: on the
first generation or tokenization after each context create, and again when
speculative decoding, vision, audio or image-count settings change.

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
  and LiteRT-LM reject non-zero values rather than silently ignoring them.
- `thinkingBudget`: llama.cpp reasoning-token cap, native or WebGPU with
  bridge assets whose `getCompletionCapabilities()` reports `thinkingBudget`.
  Use `ThinkingBudget(maxTokens: ...)` with `engine.create(...)` to use
  template delimiters automatically, or specify `startTag` and `endTag` for
  raw generation. `0` forces the end delimiter immediately. Any `thinkingBudget`
  is incompatible with speculative decoding, and unsupported backends reject
  it explicitly.
- `speculativeDecoding` / `speculativeDecodingConfig`: opt-in speculative
  decoding. Native LiteRT-LM uses the boolean, or a
  `SpeculativeDecodingConfig.backendDefault()` or `.mtp()` config without
  draft tuning, on bundles that carry a speculative drafter; native llama.cpp takes any `SpeculativeDecodingConfig`
  strategy. `draftModel` is a `ModelSource` that native backends download
  and cache when a generation starts, with `draftModelDownload`. WebGPU takes
  the strategies its bridge assets report, with a remote `draftModel` whose
  URL the runtime fetches, and URLs for the n-gram cache paths. LiteRT-LM web rejects both.
  See [Speculative decoding](../guides/performance-tuning#speculative-decoding).
- `seed`: deterministic replay when set.
- `grammar`: constrained decoding with GBNF.

After a model loads, `engine.capabilities` reports which of these options the
runtime applies. A request that sets one it reports `false` to a value other
than the default throws `LlamaUnsupportedException`:

| Option | `LlamaEngineCapabilities` field | llama.cpp native | WebGPU | LiteRT-LM native | LiteRT-LM web |
| --- | --- | --- | --- | --- | --- |
| `penalty` | `supportsPenalty` | Yes | Yes | No | No |
| `presencePenalty` | `supportsPresencePenalty` | Yes | Bridge reports | No | No |
| `minP` | `supportsMinP` | Yes | Bridge reports | No | No |
| `thinkingBudget` | `supportsThinkingBudget` | Yes | Bridge reports | No | No |
| `grammar`, `grammarTriggers`, `preservedTokens` | `supportsGrammar` | Yes | Yes | No | No |
| `grammarLazy` | `supportsLazyGrammar` | Yes | No | No | No |
| Stream batching thresholds | `supportsStreamBatching` | Yes | Ignored | Yes | No |
| Speculative strategies | `speculativeDecodingStrategies` | All | Bridge reports | `backendDefault`, `mtp` unless the bundle declares no drafter | None |

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
Empty stops are ignored. Unfinished marker prefixes are emitted when generation
ends without a match. Template tokens listed in `preservedTokens` remain
available to the chat parser; identical stop entries are excluded from native
text matching. This applies to ordinary and speculative generation, and
WebGPU excludes the same stop entries.

## Practical tuning defaults

- Deterministic extraction: lower `temp` (`0.1-0.3`) + explicit stops.
- General chat: `temp` around `0.6-0.9`, `topP` around `0.9-0.95`.
- Tool calling: stable `temp` and sufficient `maxTokens` for call payload.
