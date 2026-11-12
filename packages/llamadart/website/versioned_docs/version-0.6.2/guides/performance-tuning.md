---
title: Performance Tuning
---

Performance tuning depends on model size, quantization, backend availability,
and context/generation settings.

## Model load tuning (`ModelParams`)

```dart
const modelParams = ModelParams(
  contextSize: 4096,
  gpuLayers: ModelParams.maxGpuLayers,
  preferredBackend: GpuBackend.vulkan,
  numberOfThreads: 0,
  numberOfThreadsBatch: 0,
);
```

Guidelines:

- Start with default `gpuLayers` and lower only if stability issues appear.
- Keep `contextSize` only as large as your use case needs.
- Use backend preference matching your target device/runtime.

## Generation tuning (`GenerationParams`)

```dart
const generationParams = GenerationParams(
  maxTokens: 256,
  temp: 0.7,
  topK: 40,
  topP: 0.9,
  minP: 0.0,
  penalty: 1.1,
  reusePromptPrefix: true,
  streamBatchTokenThreshold: 8,
  streamBatchByteThreshold: 512,
);
```

Guidelines:

- Lower `maxTokens` for latency-sensitive paths.
- Lower `temp` for deterministic/extraction tasks.
- Adjust `topP` and `topK` gradually; avoid drastic simultaneous changes.
- Native backends can tune stream transport overhead with
  `streamBatchTokenThreshold` and `streamBatchByteThreshold`.
- Lower stream thresholds improve token-by-token UI granularity, while higher
  values improve throughput by reducing isolate message overhead.
- `reusePromptPrefix` is enabled by default for native generation; keep it on
  for multi-turn chats and repeated prompts, and validate parity for your
  target model/workload.
- Native reuse is optimized for evolving prompts with shared prefixes. Exact
  prompt replays are re-ingested to preserve deterministic parity.

## Practical diagnostics

- Measure token throughput with representative prompts.
- Run prompt-reuse parity checks before relying on prefix reuse in production:

```bash
dart run tool/testing/native_prompt_reuse_parity.dart \
  --model path/to/model.gguf \
  --prompt-file tool/testing/prompts/native_prompt_reuse_parity_prompts.txt \
  --max-prompts 8 \
  --runs 3 \
  --fail-on-mismatch
```

- Validate memory behavior with your real context sizes.
- Check runtime backend and VRAM info where available:

```dart
final backendName = await engine.getBackendName();
final vram = await engine.getVramInfo();
print('$backendName total=${vram.total} free=${vram.free}');
```
