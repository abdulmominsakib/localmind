---
title: Tune on-device inference performance
sidebar_label: Performance tuning
description: Measure and tune backend choice, GPU offload, context and batch sizes, generation settings and speculative decoding for faster on-device inference.
---

Treat tuning as a measurement problem:

1. Pick a representative prompt or workload.
2. Record baseline timings.
3. Change one variable at a time.
4. Keep the fastest stable configuration.

## Pick a tuning goal

- First-token latency: tune load-time setup, prompt size and prompt evaluation
  cost.
- Sustained throughput: tune backend choice, the decode path and batching.
- Stability: lower GPU pressure, reduce context and keep multimodal inputs
  small.
- Multimodal responsiveness: reduce image and audio size first, then revisit
  backend and token budget.

If you do not know which goal matters most, start with latency and stability.

Work in this order:

1. Benchmark the exact prompt shape you care about.
2. Compare `cpu` and GPU backends before changing anything else.
3. Reduce `contextSize` and `maxTokens` to the smallest values that fit your
   use case.
4. Tune load-time knobs (`gpuLayers`, threads, batch sizes) one at a time.
5. Tune sampling (`temp`, `topK`, `topP`) last. It changes output style more
   than runtime cost.

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

- `preferredBackend`: the biggest choice. Small models on mobile can be faster
  on `cpu` than on `vulkan` or WebGPU; larger models and longer responses
  favor the GPU. Always measure both.
- `gpuLayers`: start with the default and lower it if stability or latency is
  worse than on CPU.
- `contextSize`: keep it only as large as the use case needs. Oversized
  context raises first-token latency and memory use.
- `numberOfThreads` / `numberOfThreadsBatch`: `0` (automatic) is a good
  baseline. Some mobile devices prefer fewer threads; set them only after
  measuring.
- `batchSize` / `microBatchSize`: native decoder models start at the
  llama.cpp-aligned caps of `2048` and `512`. Lower `microBatchSize` first
  (for example to `256` or `128`) when memory or GPU stability is tight;
  bigger is not always faster. Encoder-only embedding models keep
  full-context native defaults for correctness; set both values explicitly
  for a known embedding workload
  ([Embeddings](./embeddings#throughput-tuning-for-embedbatch)).
- `maxParallelSequences`: matters for batched embeddings and true
  multi-sequence workloads, not single-turn chat.

WebGPU keeps full-context automatic batching because the bridge cannot report
model architecture before context creation. Two presets apply when
`batchSize` is `0`:

- If the model URL contains `gemma-4` or `modelBytesHint` is at least 2 GiB,
  the batch is capped at `min(contextSize, 512)`. An explicit
  `microBatchSize` is kept up to that cap.
- If the model URL contains `qwen3.5-0.8b`, both batch sizes are unset, the
  backend is not `cpu` and `gpuLayers` is not `0`, the sizes are `32` / `8`.

URL matching ignores case.

For the existing Qwen3.5-0.8B URL preset, CPU loads
(`preferredBackend: GpuBackend.cpu` or `gpuLayers: 0`) resolve unset sizes as
native decoders do: a batch of `min(contextSize, 2048)` and a micro-batch of
at most `512`. This reduces temporary memory without reducing `contextSize`.
Other models keep full-context automatic batching on CPU too: applying a
512-token micro-batch to a non-causal embedding model can abort on longer
inputs, even with memory64. A renamed Qwen model URL does not select the
preset; set batch sizes explicitly in that case.

Decoder-focused web apps can set `2048` / `512` explicitly after validating
their model and browser.

Field reference: [Runtime parameters](../configuration/runtime-parameters).
Native LiteRT-LM `.litertlm` loads have their own opt-in fields, listed in
[LiteRT-LM runtime controls](../configuration/runtime-parameters#litert-lm-runtime-controls).
After changing the activation type or prefill chunk size, benchmark load time,
prefill and decode throughput, and output quality on the deployment device.

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

- `maxTokens` is a performance knob as much as a quality knob. Cap it
  aggressively on latency-sensitive paths.
- `temp`, `topK`, `topP`, `penalty` and `presencePenalty` shape output; they
  rarely fix a slow backend. Change them gradually, one at a time.
- `penalty` is a repetition penalty. `presencePenalty` is a separate
  llama.cpp-native control that penalizes any token already present in the
  recent window; one does not substitute for the other. WebGPU applies
  `presencePenalty` and `minP` only with bridge assets whose
  `getCompletionCapabilities()` reports them, and otherwise rejects a non-zero
  value, as LiteRT-LM does.
- `streamBatchTokenThreshold` / `streamBatchByteThreshold` (native): lower
  values give finer token-by-token UI updates; higher values raise throughput
  by reducing isolate message overhead.
- `reusePromptPrefix` is on by default for native generation. Keep it on for
  multi-turn chat and repeated prompts. Reuse targets evolving prompts with a
  shared prefix; an exact prompt replay is re-ingested to keep output
  deterministic. Validate parity for your model with the prompt-reuse parity
  tool ([Reproducing](./backend-benchmarks#reproducing)).

## Speculative decoding

Speculative decoding is off by default and is not a universal speedup.
Benchmark it on the target model and device, and compare deterministic output,
acceptance and warmed throughput against the same baseline before enabling it
in production.

- Native LiteRT-LM: set `GenerationParams(speculativeDecoding: true)`. It was
  slower for Gemma 4 E2B on both measured devices
  ([Backend benchmarks](./backend-benchmarks#speculative-decoding-check)).
- Native llama.cpp: pass `speculativeDecodingConfig`. The legacy
  `speculativeDecoding: true` flag without a config runs `ngram-mod`.
- WebGPU: the same configs, with bridge assets whose
  `getCompletionCapabilities()` reports the strategy: bridge assets
  `v0.1.54+`, the default pin among them. `draftModel` is a remote
  `ModelSource` whose URL the runtime fetches, the n-gram cache paths are
  URLs, and `mtp` uses
  only the model's own MTP layers. See
  [WebGPU bridge](../platforms/webgpu-bridge#what-differs-from-native).
- LiteRT-LM web rejects speculative decoding.
- On llama.cpp, native or WebGPU, speculative decoding is text-only and cannot
  be combined with `thinkingBudget` or `grammar`.

`(await engine.capabilities).speculativeDecodingStrategies` reports the
strategies the loaded runtime runs.

`SpeculativeDecodingConfig` constructors mirror upstream llama.cpp
`--spec-type` values:

| Constructor | Upstream type | Draft model |
| --- | --- | --- |
| `mtp(...)` | `draft-mtp` | Optional `draftModel`; without it, load the target with `ModelParams(loadMtp: true)` |
| `draftSimple(...)` | `draft-simple` | `draftModel`; generation throws without one |
| `draftEagle3(...)` | `draft-eagle3` | `draftModel`; generation throws without one |
| `draftDflash(...)` | `draft-dflash` | `draftModel`; generation throws without one |
| `draftDspark(draftModel: ...)` | `draft-dspark` | `draftModel`; generation throws without one |
| `ngramSimple(...)`, `ngramMapK(...)`, `ngramMapK4v(...)`, `ngramMod(...)`, `ngramCache(...)` | `ngram-simple`, `ngram-map-k`, `ngram-map-k4v`, `ngram-mod`, `ngram-cache` | None; uses token history or n-gram caches |
| `mixed(strategies: [...])` | comma-separated list | At most one draft-model strategy plus any n-gram strategies |

```dart
const generationParams = GenerationParams(
  maxTokens: 256,
  temp: 0,
  speculativeDecodingConfig: SpeculativeDecodingConfig.ngramMapK(
    ngramSizeN: 4,
    ngramSizeM: 8,
  ),
);
```

`draftModel` is a `ModelSource`: a local path, an HTTP(S) URL or a Hugging
Face file. The `draftModelPath:` parameter is deprecated. `LlamaEngine`
resolves the draft model when the first generation that uses it starts: on
native backends it checks a local file, or downloads a remote one into the
model cache with `draftModelDownload` (cache policy and directory,
authentication, checksum, retries and cancel token). Later generations on the
same loaded model reuse that file, so the download and any `sha256` check run
once per loaded model; unloading or reloading the model resolves it again.
`ModelCachePolicy.noCache` and `refresh` throw `LlamaUnsupportedException`.
Cancelling the generation, or unloading the model, stops the download.
LiteRT-LM, and a backend that does not support the configured strategies,
throw `LlamaUnsupportedException` before anything downloads. The download
reports no progress; to show progress, download the file first:

```dart
final draft = ModelSource.parse('hf://owner/repo/draft-model.gguf');
await engine.modelDownloadManager.ensureModel(
  draft,
  onProgress: (progress) => print('${progress.receivedBytes} bytes'),
);

final params = GenerationParams(
  maxTokens: 256,
  temp: 0,
  speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(
    draftModel: draft,
  ),
);
```

Pass the same options to `ensureModel` as `draftModelDownload` so the
generation finds the cached file.

Knobs:

- Draft-model strategies and `ngram-cache`: `draftTokenMax` caps the draft
  length per step.
- `ngram-simple`, `ngram-map-k`, `ngram-map-k4v`: `ngramSizeM` is the
  effective draft length, matching upstream's draft m-gram window;
  `draftTokenMax` does not cap them.
- `ngram-mod`: `ngramTokenMax` when set, otherwise `draftTokenMax`, otherwise
  the llama.cpp default.
- `loadMtp` (`ModelParams`): keep it `false` unless bundled MTP tensors will
  be used, because loading them costs memory. An external MTP draft model
  loads as MTP automatically.
- `speculativeRollbackTokenMax` (`ModelParams`): native llama.cpp rejects
  nonzero reservations for recurrent/hybrid models, including LFM2 and Qwen3.5,
  before creating a context. Its public API cannot establish a safe graph-node
  budget for rollback snapshots, and excessive reservations can abort the
  process. Keep the default `0` for ordinary generation. Speculative strategies
  requiring recurrent rollback remain unsupported until a native runtime can
  validate that budget; a small value measured on one model is not a safe bound
  for other models. Nonrecurrent targets retain native handling. WebGPU retains
  its separate bridge capability contract.

Draftless n-gram strategies depend on the workload. On prompts with little
repetition they can produce no drafts and run slower than baseline; measured
results are in
[Backend benchmarks](./backend-benchmarks#llamacpp-upstream-speculative-parity-check).

The speculative benchmark reserves the maximum effective draft length among
the selected cases. Draft-model cases do not inherit the default n-gram window
of 48, and an n-gram window does not inherit an unused draft or `ngramTokenMax`
setting. Selecting only `baseline` reserves no rollback snapshots. This removes
unrelated reservations; it does not make recurrent/hybrid reservations safe.

### DSpark

DSpark (`SpeculativeDecodingConfig.draftDspark(draftModel: ...)`) is an
experimental, opt-in llama.cpp external-draft strategy mapped to upstream
`draft-dspark`. The default `v0.5.0-2` runtime supports it, including
speculators-format checkpoints. Native recurrent/hybrid target pairs such as
LFM2 remain subject to the rollback restriction above. It is never
selected automatically, and support still depends on the target, draft and
backend. If speculative initialization fails, the `LlamaUnsupportedException`
names the minimum native tag, `b10356`.

### DFlash draft models

DFlash drafts must use upstream-compatible GGUF metadata:
`general.architecture=dflash` plus the `dflash.*` metadata block, including
`dflash.target_layers`. A known-good public pair is target
`unsloth/Qwen3.5-4B-GGUF` (`Qwen3.5-4B-Q4_K_M.gguf`) with draft
`EntityDeletr/Qwen3.5-4B-DFlash-GGUF` (`Qwen3.5-4B-DFlash.gguf`).

If the draft fails to load and native logs report
`unknown model architecture: 'dflash-draft'` or missing DFlash target-layer
metadata, the artifact uses `general.architecture=dflash-draft` or lacks
`dflash.target_layers`. Reconvert or replace the draft GGUF; llamadart does
not patch draft metadata at runtime.

## Multimodal tuning

- Reduce image size before anything else.
- Keep `contextSize` and `maxTokens` tighter than text-only defaults.
- If GPU multimodal is unstable, get a correct CPU baseline first, then
  revisit GPU and offload settings.
- Treat projector loading and multimodal generation as separate stages; one
  can be healthy while the other is slow or unstable.

## Read the diagnostics

- `first`: first-token latency. If high, look at model load, prompt size,
  context and prompt evaluation.
- `total`: end-to-end wall time.
- `avg`: throughput across the whole request.
- `decode`: steady-state generation speed once output starts.

Native llama.cpp timing fields:

- `p_eval`: prompt evaluation time. High values point to prompt and context
  overhead, not the sampler.
- `eval`: decode time for generated tokens. High values point to backend
  kernel or scheduler cost.
- `sample`: token selection overhead. Usually small; if large, check for
  unusual sampling settings.
- `reuse`: prompt-prefix reuse count. If it stays low in multi-turn chat,
  prefix reuse is not helping.

Check the active backend and VRAM where available:

```dart
final backendName = await engine.getBackendName();
final vram = await engine.getVramInfo();
print('$backendName total=${vram.total} free=${vram.free}');
```

## Heuristics by environment

- Mobile native: test CPU against GPU early; small models often favor CPU.
- Desktop native: the GPU pays off more as model size or response length
  grows.
- Browser: start with conservative GPU settings; browser GPU paths have
  tighter stability limits than native.
- Multimodal: expect stricter limits than text-only, especially on mobile and
  browser targets.

## Compare fairly

- Use the same model, prompt, `contextSize`, `maxTokens` and backend-specific
  limits across runs.
- Record latency and throughput; a setting that improves one can hurt the
  other.
- Validate memory behavior with your real context sizes.

Benchmark and parity scripts for a repository checkout, and measured
llama.cpp and LiteRT-LM results, are in
[Backend benchmarks](./backend-benchmarks#reproducing).
