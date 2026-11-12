---
title: Performance Tuning
---

Performance tuning depends on model size, quantization, backend availability,
and context/generation settings.

The most reliable approach is to treat tuning as a measurement problem:

1. pick a representative prompt or workload
2. record baseline timings
3. change one variable at a time
4. keep the fastest stable configuration

## Pick a tuning goal

Different knobs help different problems:

- `first-token latency`: optimize load-time/runtime setup, prompt size, and
  prompt evaluation cost.
- `sustained throughput`: optimize decode path, backend choice, and batching.
- `stability`: lower GPU pressure, reduce context, and keep multimodal inputs
  smaller.
- `multimodal responsiveness`: reduce image/audio size first, then revisit
  backend and token budget.

If you do not know which goal matters most, start with latency and stability.

## Suggested workflow

1. Benchmark the exact prompt shape you care about.
2. Compare `cpu` and GPU backends before changing anything else.
3. Reduce `contextSize` and `maxTokens` to the smallest values that still fit
   your use case.
4. Tune load-time/runtime knobs (`gpuLayers`, threads, batch sizes) one at a
   time.
5. Only after runtime is stable, tune sampling (`temp`, `topK`, `topP`, etc.).

This order matters: sampling changes usually affect output style more than raw
runtime cost.

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

- Start with backend choice first. Small/mobile models can be faster on `cpu`
  than `vulkan`/`webgpu`, while larger or longer-running workloads may favor
  GPU acceleration.
- Start with default `gpuLayers`, then lower them if stability or latency is
  worse than CPU.
- Keep `contextSize` only as large as your use case needs. Oversized context is
  one of the easiest ways to hurt first-token latency.
- Use explicit `numberOfThreads` / `numberOfThreadsBatch` only after measuring.
  Auto-threading is often a good baseline, but some mobile devices prefer fewer
  threads for lower contention.
- Tune `batchSize` and `microBatchSize` conservatively on unstable GPU paths.
  Bigger is not always faster if it increases driver/scheduler overhead.
- Use backend preference that matches your actual target runtime, not just the
  hardware you hope to use.

### Highest-impact load-time knobs

- `preferredBackend`: biggest high-level choice; always measure CPU against GPU.
- `gpuLayers`: GPU offload depth; can help throughput but may hurt stability or
  even latency on small models.
- `contextSize`: affects prompt evaluation cost and memory footprint directly.
- `numberOfThreads`, `numberOfThreadsBatch`: mostly relevant for CPU and hybrid
  paths.
- `batchSize`, `microBatchSize`: scheduler/batching controls for native and web
  runtimes.
- `maxParallelSequences`: relevant for embedding or true multi-sequence
  workloads, not regular single-turn chat.

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
- Treat `maxTokens` as a performance knob as much as a quality knob. If you only
  need short answers, cap it aggressively.
- `penalty`, `topK`, `topP`, and `temp` usually do not fix a slow backend; they
  mainly shape output behavior.
- Native backends can tune stream transport overhead with
  `streamBatchTokenThreshold` and `streamBatchByteThreshold`.
- Lower stream thresholds improve token-by-token UI granularity, while higher
  values improve throughput by reducing isolate message overhead.
- `reusePromptPrefix` is enabled by default for native generation; keep it on
  for multi-turn chats and repeated prompts, and validate parity for your
  target model/workload.
- Native reuse is optimized for evolving prompts with shared prefixes. Exact
  prompt replays are re-ingested to preserve deterministic parity.

## Multimodal tuning

- Reduce image size before doing anything else.
- Keep `contextSize` and `maxTokens` tighter than your text-only defaults.
- If GPU multimodal is unstable, try CPU first to establish a correctness
  baseline.
- Once CPU multimodal works, revisit GPU/offload settings carefully.
- Treat projector loading and actual multimodal generation as separate stages;
  one can be healthy while the other is still too slow or unstable.

## Read the diagnostics you already have

Good tuning depends on reading the right signals.

- `first`: first-token latency; if this is high, focus on model load, prompt
  size, context, and prompt evaluation.
- `total`: end-to-end wall time.
- `avg`: overall throughput across the whole request.
- `decode`: steady-state generation speed once output starts.

If your app exposes native llama.cpp timing chips or logs:

- `p_eval`: prompt evaluation time. High values usually mean prompt/context
  overhead, not sampler overhead.
- `eval`: decode time for generated tokens. High values usually point to backend
  kernel/scheduler cost.
- `sample`: token selection overhead. Usually small; if large, inspect runtime
  overhead or unusual sampling settings.
- `reuse`: prompt-prefix reuse count. If reuse stays low in multi-turn chat,
  cached prefix optimization is not helping much.

These numbers help you decide whether to tune prompt size, decode path, or
sampling.

## General heuristics by environment

- `mobile native`: test CPU vs GPU early; small models often favor CPU.
- `desktop native`: GPU is more likely to pay off as model size or response
  length grows.
- `browser`: prefer conservative GPU settings first; browser GPU paths usually
  have tighter stability limits than native.
- `multimodal`: expect stricter limits than text-only, especially on mobile and
  browser targets.

## Practical diagnostics

- Measure token throughput with representative prompts.
- Keep comparisons fair: same model, same prompt, same `contextSize`, same
  `maxTokens`, same backend-specific limits.
- Record both latency and throughput; a setting that improves one can hurt the
  other.
- Run prompt-reuse parity checks before relying on prefix reuse in production:

```bash
dart run tool/testing/native_prompt_reuse_parity.dart \
  --model path/to/model.gguf \
  --prompt-file tool/testing/prompts/native_prompt_reuse_parity_prompts.txt \
  --max-prompts 8 \
  --runs 3 \
  --fail-on-mismatch

# Benchmark embeddings (sequential vs batch)
dart run tool/testing/native_embedding_benchmark.dart \
  --model path/to/model.gguf \
  --cpu \
  --mode both \
  --input-count 8 \
  --max-seq 8

# Sweep max-seq values and export CSV for plotting
dart run tool/testing/native_embedding_sweep.dart \
  --model path/to/model.gguf \
  --cpu \
  --max-seq-values 1,2,4,8 \
  --csv-out embedding_speedup.csv
```

- Validate memory behavior with your real context sizes.
- Check runtime backend and VRAM info where available:

```dart
final backendName = await engine.getBackendName();
final vram = await engine.getVramInfo();
print('$backendName total=${vram.total} free=${vram.free}');
```

## Keep the tuning guide model-agnostic

Specific models may need special-case defaults in applications, but the tuning
process should stay general:

- define the goal
- measure the baseline
- change one knob at a time
- keep the fastest stable result

That workflow transfers much better than any one model-specific recipe.
