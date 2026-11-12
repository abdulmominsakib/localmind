---
title: Runtime Parameters
---

Runtime behavior is primarily controlled by:

- `ModelParams` at model load time.
- `GenerationParams` per generation call.

## ModelParams essentials

```dart
await engine.loadModel(
  '/path/to/model.gguf',
  modelParams: const ModelParams(
    contextSize: 4096,
    gpuLayers: ModelParams.maxGpuLayers,
    preferredBackend: GpuBackend.vulkan,
    numberOfThreads: 0,
    numberOfThreadsBatch: 0,
  ),
);
```

Important fields:

- `contextSize`: total context window.
- `gpuLayers`: number of layers offloaded to GPU.
- `preferredBackend`: backend preference (`auto`, `vulkan`, `metal`, etc).
- `chatTemplate`: optional template override.

For runtime LoRA control (`setLora`, `removeLora`, `clearLoras`), see
[LoRA Adapters](../guides/lora-adapters).

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
);
```

Important fields:

- `maxTokens`: generation length cap.
- `temp`: randomness.
- `topK`, `topP`, `minP`: token filtering controls.
- `penalty`: repeat penalty.
- `seed`: deterministic replay when set.
- `grammar`: constrained decoding with GBNF.

## Practical tuning defaults

- Deterministic extraction: lower `temp` (`0.1-0.3`) + explicit stops.
- General chat: `temp` around `0.6-0.9`, `topP` around `0.9-0.95`.
- Tool calling: stable `temp` and sufficient `maxTokens` for call payload.
