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
- `batchSize`: context logical batch size (`n_batch`). When left at `0`,
  llamadart uses the effective context size (`n_ctx`) on native and WebGPU
  backends, except for model-specific WebGPU safety tuning such as the bundled
  Qwen3.5-0.8B small-model preset.
- `microBatchSize`: context micro-batch size (`n_ubatch`). When left at `0`,
  llamadart uses the resolved `batchSize`; explicit values are capped so
  `n_ubatch <= n_batch <= n_ctx`.
- `maxParallelSequences`: max sequence slots (`n_seq_max`) for parallel
  sequence workloads (for example, batched embeddings).
- `chatTemplate`: optional template override.
- `preferMemory64` (web/WebGPU only): prefer the 64-bit (wasm64/mem64) bridge
  core. Models larger than the ~4 GiB wasm32 address space (for example Gemma 4
  E2B) cannot load on the default 32-bit core. `null` (default) lets llamadart
  decide from `modelBytesHint`; `true` forces mem64; `false`
  forces wasm32. Ignored on non-web backends.
- `modelBytesHint` (web/WebGPU only): approximate model size in bytes, used to
  select the mem64 core up front instead of waiting for an out-of-memory retry.
  Ignored on non-web backends.

For runtime LoRA control (`setLora`, `removeLora`, `clearLoras`), see
[LoRA Adapters](../guides/lora-adapters).

## Embedding-oriented model params

For high-throughput `embedBatch(...)`, tune context batch fields together:

- Keep `batchSize` large enough for total tokens across your average batch.
- Set `microBatchSize` close to `batchSize` unless you need tighter memory
  bounds.
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
  stopSequences: ['</s>'],
  speculativeDecoding: false,
);
```

Important fields:

- `maxTokens`: generation length cap.
- `temp`: randomness.
- `topK`, `topP`, `minP`: token filtering controls.
- `penalty`: repeat penalty.
- `speculativeDecoding`: opt-in backend-native speculative decoding. Native
  LiteRT-LM honors this flag; llama.cpp, WebGPU, and LiteRT-LM web reject it
  until their speculative paths are implemented.
- `seed`: deterministic replay when set.
- `grammar`: constrained decoding with GBNF.

## Practical tuning defaults

- Deterministic extraction: lower `temp` (`0.1-0.3`) + explicit stops.
- General chat: `temp` around `0.6-0.9`, `topP` around `0.9-0.95`.
- Tool calling: stable `temp` and sufficient `maxTokens` for call payload.
