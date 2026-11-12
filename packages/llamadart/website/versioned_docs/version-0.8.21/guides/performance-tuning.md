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
  batchSize: 0, // Native decoder default: min(contextSize, 2048).
  microBatchSize: 0, // Native decoder default: min(resolved batch, 512).
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
- For native decoder/generative models, start with the llama.cpp-aligned logical
  batch cap of `2048` and physical micro-batch cap of `512`. Lower
  `microBatchSize` first (for example to `256` or `128`) when memory or GPU
  stability is tight. Bigger is not always faster if it increases allocation,
  driver, or scheduler pressure.
- WebGPU keeps full-context automatic batching because the bridge cannot expose
  model architecture before context creation. Decoder-focused web apps can set
  `2048` / `512` explicitly after validating their target model and browser.
- Encoder-only embedding models retain full-context native defaults for
  correctness. Set both batch values explicitly when tuning a known embedding
  workload.
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
- `loadMtp`: native llama.cpp opt-in for MTP tensors embedded in the target
  GGUF. Keep it `false` unless bundled MTP will be used, because loading the
  extra tensors increases model memory. External MTP draft models are enabled
  automatically when supplied through `draftModelPath`.
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
  presencePenalty: 0.0,
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
- `penalty` is a repetition penalty. `presencePenalty` is a separate
  llama.cpp-native control that penalizes any token already present in the
  recent window; do not substitute one for the other. WebGPU and LiteRT-LM
  reject a non-zero presence penalty until their runtimes expose an equivalent.
- `penalty`, `presencePenalty`, `topK`, `topP`, and `temp` usually do not fix a
  slow backend; they mainly shape output behavior.
- Native backends can tune stream transport overhead with
  `streamBatchTokenThreshold` and `streamBatchByteThreshold`.
- Lower stream thresholds improve token-by-token UI granularity, while higher
  values improve throughput by reducing isolate message overhead.
- Use speculative decoding only after benchmarking your target model/device; the
  default remains off because it is not a universal speedup. Native LiteRT-LM
  uses the legacy `speculativeDecoding` boolean. llama.cpp mirrors upstream
  `common_speculative`: `SpeculativeDecodingConfig.mtp(...)`,
  `draftSimple(...)`, `draftEagle3(...)`, `draftDflash(...)`,
  `draftDspark(...)`, `ngramSimple(...)`, `ngramMapK(...)`,
  `ngramMapK4v(...)`, `ngramMod(...)`, `ngramCache(...)`, and `mixed(...)` for
  draftless n-gram strategies plus one draft-model strategy. Draft-model
  strategies can load a separate GGUF through `draftModelPath`; draftless
  n-gram strategies are workload-dependent and can be slower than baseline on
  prompts with little repetition. For ngram-simple and ngram-map strategies,
  `ngramSizeM` is the effective draft length and mirrors upstream's draft
  m-gram window; `draftTokenMax` does not cap those pure n-gram map strategies.
  For ngram-mod, `ngramTokenMax` is the effective draft cap when set; otherwise
  it falls back to `draftTokenMax` or the llama.cpp default.
- DSpark is an experimental, opt-in native llama.cpp external draft-model
  strategy. Use `SpeculativeDecodingConfig.draftDspark(draftModelPath: ...)`;
  it is never selected automatically, maps to upstream `draft-dspark`, requires
  at least the `b10356-llamadart.1` wrapper fix; the package-pinned `v0.2.0-1`
  runtime satisfies that ABI, supports speculators-format checkpoints, and
  adds LFM2 target/draft support. DSpark remains subject to
  target/draft/backend compatibility.
  Compare deterministic output, acceptance, and warmed throughput against the
  same baseline before enabling it in production.
- DFlash draft models must use upstream-compatible GGUF metadata:
  `general.architecture=dflash` plus the `dflash.*` metadata block, including
  `dflash.target_layers`. A known-good public pair is target
  `unsloth/Qwen3.5-4B-GGUF` (`Qwen3.5-4B-Q4_K_M.gguf`) with draft
  `EntityDeletr/Qwen3.5-4B-DFlash-GGUF` (`Qwen3.5-4B-DFlash.gguf`). If a draft
  artifact reports `general.architecture=dflash-draft` or lacks
  `dflash.target_layers`, reconvert or replace the GGUF instead of trying to
  compensate in Dart code.
- `reusePromptPrefix` is enabled by default for native generation; keep it on
  for multi-turn chats and repeated prompts, and validate parity for your
  target model/workload.
- Native reuse is optimized for evolving prompts with shared prefixes. Exact
  prompt replays are re-ingested to preserve deterministic parity.

## Native LiteRT-LM runtime controls

Native `.litertlm` loads expose a small set of LiteRT-LM-specific
`ModelParams` fields:

- `liteRtLmActivationDataType`: override upstream activation data type
  (`float32`, `float16`, `int16`, or `int8`).
- `liteRtLmPrefillChunkSize`: positive CPU dynamic-model prefill chunk size.
- `liteRtLmParallelFileSectionLoading`: `null` keeps the native default,
  `false` disables parallel `.litertlm` file-section loading for diagnostics.
- `liteRtLmDispatchLibDir`: Android NPU LiteRT dispatch library directory.
- `numberOfThreads`: generation thread count; `0` keeps LiteRT-LM automatic
  selection.
- `loras`: one default-scale initial text LoRA adapter for native `.litertlm`
  loads. Runtime adapter updates, stacking, and scaling remain llama.cpp-only.

Leave these values unset unless you have a target-model reason to change them.
Benchmark load time, prefill throughput, decode throughput, and output quality
on the deployment device after changing activation type or prefill chunk size.
LiteRT-LM web rejects these native-only fields.

The real-model smoke tool accepts matching environment variables and reports
the selected values in its JSON result:

```bash
LITERT_LM_ACTIVATION_DATA_TYPE=float16 \
LITERT_LM_PREFILL_CHUNK_SIZE=128 \
LITERT_LM_PARALLEL_FILE_SECTION_LOADING=false \
dart run tool/litert_lm_engine_smoke.dart /models/model.litertlm cpu
```

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

# Benchmark native generate/create TTFT and throughput
dart run tool/testing/native_inference_benchmark.dart \
  --model path/to/model.gguf \
  --gpu-layers 0 \
  --mode all \
  --runs 3 \
  --max-tokens 128

# Benchmark llama.cpp speculative decoding strategies
dart run tool/testing/llama_cpp_speculative_benchmark.dart \
  --model path/to/model.gguf \
  --cases baseline,ngram-simple,ngram-map-k,ngram-map-k4v,ngram-mod,mixed-ngram \
  --backend cpu \
  --gpu-layers 0 \
  --max-tokens 128 \
  --runs 3 \
  --draft-token-max 1,2 \
  --ngram-size-m 8,16 \
  --warmups 1

# Benchmark the experimental DSpark path against the same target baseline
dart run tool/testing/llama_cpp_speculative_benchmark.dart \
  --model path/to/target.gguf \
  --draft-model path/to/dspark-draft.gguf \
  --cases baseline,draft-dspark \
  --backend metal \
  --gpu-layers 99 \
  --max-tokens 256 \
  --runs 3 \
  --warmups 1 \
  --include-output

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

For the speculative benchmark runner, external draft-model strategies require
`--draft-model`; use the `draft-dspark` case for DSpark. Bundled MTP omits the
draft path and automatically loads the target's MTP tensors. The n-gram cache
strategy requires cache paths. Current
measured llama.cpp n-gram parity results, including exact upstream comparison
commands, are recorded in [Backend Benchmarks](./backend-benchmarks).

Compare llama.cpp/GGUF and LiteRT-LM with the bundled fair benchmark scripts:

```bash
# macOS native, Gemma 4 E2B artifacts
DECODE_TOKENS=256 tool/macos_fair_litert_vs_llamadart.sh

# Native LiteRT-LM speculative decoding off/on comparison
SPECULATIVE=false DECODE_TOKENS=256 tool/macos_fair_litert_vs_llamadart.sh
SPECULATIVE=true  DECODE_TOKENS=256 tool/macos_fair_litert_vs_llamadart.sh

# Web LiteRT-LM; use TARGETS=llamadart to test GGUF WebGPU separately
DOWNLOAD_LITERT_WEB_MODEL=1 \
DECODE_TOKENS=256 \
WARMUPS=1 \
RUNS=3 \
TARGETS=litert_lm \
tool/web_fair_litert_vs_llamadart.sh

# Android / Pixel-style app benchmark
ADB=/path/to/adb
DEVICE=<adb-serial>
"$ADB" -s "$DEVICE" shell svc power stayon true
"$ADB" -s "$DEVICE" shell input keyevent KEYCODE_WAKEUP
DEVICE="$DEVICE" ADB="$ADB" OUTPUT_TOKENS=256 WARMUPS=1 RUNS=3 \
  TARGETS=litert_lm,llamadart tool/litert_lm_pixel_benchmark.sh

DEVICE="$DEVICE" ADB="$ADB" TARGETS=litert_lm BACKEND=gpu \
  SPECULATIVE=false OUTPUT_TOKENS=256 WARMUPS=1 RUNS=3 \
  tool/litert_lm_pixel_benchmark.sh
DEVICE="$DEVICE" ADB="$ADB" TARGETS=litert_lm BACKEND=gpu \
  SPECULATIVE=true OUTPUT_TOKENS=256 WARMUPS=1 RUNS=3 \
  tool/litert_lm_pixel_benchmark.sh
```

Current measured Gemma 4 E2B results are recorded in
[Backend Benchmarks](./backend-benchmarks).

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
