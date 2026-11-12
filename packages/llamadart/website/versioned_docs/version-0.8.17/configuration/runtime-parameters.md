---
title: Runtime Parameters
---

Runtime behavior is primarily controlled by:

- `ModelParams` at model load time.
- `GenerationParams` per generation call.

For a strategy-focused walkthrough on how to change these knobs and what to
measure, see [Performance Tuning](../guides/performance-tuning).

## ModelParams essentials

```dart
await engine.loadModel(
  '/path/to/model.gguf',
  modelParams: const ModelParams(
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
- `gpuLayers`: number of layers offloaded to GPU.
- `preferredBackend`: backend preference (`auto`, `vulkan`, `metal`, etc).
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
  smaller.
- `microBatchSize`: context physical micro-batch size (`n_ubatch`). On native,
  decoder/generative models use `min(n_batch, 512)` when this is `0`, while
  encoder-only models retain the resolved logical batch. WebGPU follows its
  resolved logical batch unless a safety preset applies. Explicit positive
  values are preserved within `n_ubatch <= n_batch <= n_ctx`.
- `maxParallelSequences`: max sequence slots (`n_seq_max`) for parallel
  sequence workloads (for example, batched embeddings).
- `chatTemplate`: optional template override.
- `preferMemory64` (web/WebGPU only): prefer the 64-bit (wasm64/mem64) bridge
  core. The default 32-bit core has a 4 GiB address-space limit, but large
  models need room for KV cache and intermediate buffers. `null` (default) lets
  llamadart decide from `modelBytesHint` using the current wasm32-safe ceiling
  (about 2 GiB of model bytes); `true` forces mem64; `false` forces wasm32.
  Ignored on non-web backends.
- `modelBytesHint` (web/WebGPU only): approximate model size in bytes, used to
  select the mem64 core up front instead of waiting for an out-of-memory retry.
  Ignored on non-web backends.
- `liteRtLmActivationDataType`, `liteRtLmPrefillChunkSize`,
  `liteRtLmParallelFileSectionLoading`, and `liteRtLmDispatchLibDir`: opt-in
  native LiteRT-LM `.litertlm` engine settings. Leave them unset to preserve
  runtime defaults; LiteRT-LM web rejects them as native-only.
- `numberOfThreads`: honored by native LiteRT-LM; `0` keeps automatic
  selection.
- `loras`: native LiteRT-LM accepts one default-scale initial text adapter at
  model load. Runtime LoRA control APIs, adapter stacking, and custom scales
  remain llama.cpp-only.

For runtime LoRA control (`setLora`, `removeLora`, `clearLoras`), see
[LoRA Adapters](../guides/lora-adapters).

## Embedding-oriented model params

For high-throughput `embedBatch(...)`, tune context batch fields together:

- Keep `batchSize` large enough for total tokens across your average batch.
- Set `microBatchSize` close to `batchSize` unless you need tighter memory
  bounds.
- Set both values explicitly when a fixed embedding workload needs larger
  batches; the decoder defaults prioritize safe prompt processing and do not
  replace workload-specific embedding tuning.
- Increase `maxParallelSequences` above `1` (for example `2`, `4`, `8`) to
  enable true multi-sequence embedding batching.

See [Embeddings](../guides/embeddings) for API usage and benchmark scripts.

## GenerationParams essentials

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
- `topK`, `topP`, `minP`: token filtering controls.
- `penalty`: repeat penalty.
- `presencePenalty`: llama.cpp-native presence penalty; `0.0` preserves the
  existing behavior. WebGPU and LiteRT-LM reject non-zero values rather than
  silently ignoring them.
- `thinkingBudget`: native llama.cpp-only reasoning-token cap. Use
  `ThinkingBudget(maxTokens: ...)` with `engine.create(...)` to use template
  delimiters automatically, or specify `startTag` and `endTag` for raw
  generation. `0` forces the end delimiter immediately; it is incompatible
  with speculative decoding and unsupported backends reject it explicitly.
- `speculativeDecoding` / `speculativeDecodingConfig`: opt-in backend-native
  speculative decoding. Native LiteRT-LM honors the legacy boolean flag.
  llama.cpp supports the upstream strategy surface:
  `SpeculativeDecodingConfig.mtp(...)`, `draftSimple(...)`,
  `draftEagle3(...)`, `draftDflash(...)`, `ngramSimple(...)`,
  `ngramMapK(...)`, `ngramMapK4v(...)`, `ngramMod(...)`,
  `ngramCache(...)`, and `mixed(...)` for draftless n-gram strategies plus one
  draft-model strategy. Draft-model strategies can load a separate GGUF through
  `draftModelPath`; draftless n-gram strategies use token history or n-gram
  caches without a draft model. WebGPU and LiteRT-LM web reject speculative
  decoding until their speculative paths are implemented.
- `seed`: deterministic replay when set.
- `grammar`: constrained decoding with GBNF.

## Practical tuning defaults

- Deterministic extraction: lower `temp` (`0.1-0.3`) + explicit stops.
- General chat: `temp` around `0.6-0.9`, `topP` around `0.9-0.95`.
- Tool calling: stable `temp` and sufficient `maxTokens` for call payload.
