---
title: Choosing llama.cpp or LiteRT-LM
description: Decide when to use GGUF with llama.cpp or .litertlm bundles with LiteRT-LM in llamadart.
---

`llamadart` can route two model families through the same high-level
`LlamaEngine` APIs. Native targets can also use `ChatSession` for both formats:

- **GGUF models** run through `llama.cpp`.
- **`.litertlm` bundles** run through LiteRT-LM.

LiteRT-LM web is currently narrower than native LiteRT-LM: it forwards
single-turn text prompts to `@litert-lm/core` and does not yet preserve
`ChatSession` history, system prompts, or tool declarations.

The backend is selected from the model format when you use `LlamaBackend()`.
Use GGUF when you want the broad `llama.cpp` ecosystem and feature surface. Use
LiteRT-LM when you are deploying a LiteRT-LM model bundle, especially for
Google AI Edge / Gemma mobile paths where the LiteRT runtime and delegates are
the target.

## Quick Decision Table

| Choose this | Best fit | Tradeoffs |
| --- | --- | --- |
| `llama.cpp` / GGUF | Broad model catalog, many quantizations, embeddings, LoRA, state persistence, grammar constraints, multimodal, and low-level runtime tuning. | Mobile GPU performance depends heavily on the device, driver, model size, and backend. It does not use LiteRT-LM NPU delegates. |
| LiteRT-LM / `.litertlm` | LiteRT-LM bundles, Gemma 4 LiteRT-LM variants, Android GPU/NPU delegate experiments, and app flows that only need text generation/chat. | Smaller model catalog and fewer exposed runtime features today. Unsupported llama.cpp-only options are rejected. |

If both formats exist for the model you want, treat the choice as a deployment
benchmark, not only a file-format preference. Measure the exact model artifact,
device, prompt shape, and output length your app will ship.

See [Backend Benchmarks](./backend-benchmarks) for measured Gemma 4 E2B results
on Pixel 9 Pro, macOS, and web.

## Format Routing

```dart
final engine = LlamaEngine(LlamaBackend());

// GGUF routes to llama.cpp.
await engine.loadModel('models/model-Q4_K_M.gguf');

// .litertlm routes to LiteRT-LM.
await engine.loadModel(
  'models/gemma-4-E2B-it.litertlm',
  modelParams: const ModelParams(
    liteRtLmBackend: LiteRtLmBackendPreference.gpu,
  ),
);
```

Formats are not interchangeable:

- A GGUF file cannot run through LiteRT-LM.
- A `.litertlm` bundle cannot run through llama.cpp.
- The high-level Dart API can stay the same, but model-load and generation
  parameters are validated against the selected backend.

Use `ModelSource` / `loadModelSource(...)` for download and cache flows. Native
targets cache remote GGUF and `.litertlm` sources before loading a local file.
Web targets pass simple unauthenticated `.litertlm` URLs to the LiteRT-LM
JavaScript runtime.

## Capability Matrix

| Capability | llama.cpp / GGUF | LiteRT-LM / `.litertlm` |
| --- | --- | --- |
| Native Android | CPU, Vulkan, optional OpenCL modules | CPU, GPU, Android-only NPU selector |
| Native iOS/macOS | Consolidated CPU + Metal runtime | iOS CPU; macOS CPU/GPU |
| Native Linux/Windows | CPU, Vulkan, and target-specific optional modules | CPU in the current pinned runtime |
| Web | llama.cpp WebGPU/CPU bridge for GGUF URLs | `@litert-lm/core` for web-compatible `.litertlm` URLs |
| Embeddings | Supported on native; supported on web bridge assets with embedding APIs | Not exposed by current LiteRT-LM APIs |
| KV-cache state persistence | Supported on native; supported on WebGPU bridge assets that expose state APIs | Not exposed |
| LoRA adapters | Supported on native GGUF flows | Not exposed |
| Thinking and tool-call parsing | Supported through template handlers | Native: supported through the high-level `LlamaEngine` parser for compatible templates; LiteRT-native constrained tool execution is not wired yet. Web: single-turn text only; no structured chat/tool forwarding yet. |
| Grammar / constrained decoding | Supported by llama.cpp-backed paths | llama.cpp GBNF is not supported; template-generated grammar is skipped and explicit grammar params are rejected |
| Multimodal projectors | Supported through llama.cpp `mtmd` paths where the model/projector supports it | Not exposed through llamadart today |
| Tokenization APIs | Supported | Supported on native LiteRT-LM; not exposed on LiteRT-LM web |
| Low-level runtime tuning | `gpuLayers`, backend preference, thread/batch fields, split mode, main GPU, KV/cache fields, and more | `liteRtLmBackend`, context size, chat template, generation length/sampling fields that LiteRT-LM exposes |

See [Platform & Backend Matrix](../platforms/support-matrix) for the current
bundle keys, module availability, and selector names.

## Package Size Controls

Native apps include both runtime families by default where available, so one
build can load GGUF and `.litertlm` models. If your app only ships one model
format, opt into the matching runtime family with
`llamadart_native_runtimes`:

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_runtimes: [llama_cpp] # GGUF only
```

or:

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_runtimes: [litert_lm] # .litertlm only
```

`llamadart_native_backends` is a different switch: it filters llama.cpp module
files such as Vulkan, CUDA, OpenCL, BLAS, and HIP inside the `llama_cpp`
runtime. It does not enable or disable LiteRT-LM.

## Parameter Differences

For GGUF / llama.cpp, common load-time controls include:

- `preferredBackend`
- `gpuLayers`
- `contextSize`
- `numberOfThreads` / `numberOfThreadsBatch`
- `batchSize` / `microBatchSize`
- `splitMode` / `mainGpu`
- LoRA and state-persistence APIs

For `.litertlm` / LiteRT-LM, use:

- `liteRtLmBackend`: `auto`, `cpu`, `gpu`, or Android-native `npu`
- `contextSize`
- `chatTemplate`
- `GenerationParams.maxTokens`, `temp`, `topK`, `topP`, and `seed`
- `GenerationParams.speculativeDecoding` on native LiteRT-LM only
- `stopSequences`, enforced by `llamadart`

`llamadart` rejects unsupported backend-specific options for `.litertlm` loads
instead of silently ignoring them. This is intentional: it prevents a GGUF tuning
profile from appearing to work while doing something different under LiteRT-LM.

## Benchmarking Fairly

For app-level benchmarks, compare the deployment choices users would actually
run. That means:

- Keep the device awake, unlocked, foregrounded, and out of battery saver.
- Record thermal status and cooling state before and after the run.
- Use the same prompt, output-token cap, context size, stop rules, and sampling
  settings where both backends expose them.
- Separate cold-start numbers from warm steady-state numbers.
- Run enough repetitions to report median and outliers, not only the last run.
- Record early EOS separately from requested output length.
- Compare wall-clock latency and backend timing counters; they answer different
  questions.

When comparing GGUF and LiteRT-LM artifacts, remember that the model files may
not be identical quantizations or runtime graphs. A GGUF-vs-LiteRT-LM benchmark
is usually the right comparison for product deployment, but it is not a pure
kernel benchmark.

## Practical Recommendations

- Start with GGUF / llama.cpp if you need the broadest model support or advanced
  features such as embeddings, LoRA, grammar constraints, state persistence, or
  multimodal flows.
- Start with LiteRT-LM if your target model is already distributed as a
  `.litertlm` bundle and your app mainly needs text generation/chat on mobile or
  web.
- For Gemma 4 E2B on Pixel 9 Pro, the measured LiteRT-LM GPU path was about 9x
  faster than the measured llama.cpp Vulkan GGUF path.
- For Gemma 4 E2B on an Apple M4 Max Mac, measured llama.cpp Metal and
  LiteRT-LM Metal throughput were close; choose based on model format and
  feature needs.
- For web Gemma 4 E2B, both LiteRT-LM WebGPU and GGUF WebGPU loaded and
  generated through the chat app. LiteRT-LM was about 2x faster on the measured
  web decode counter and loaded much faster, while GGUF kept the broader
  llama.cpp feature surface.
- Treat `GenerationParams.speculativeDecoding` as a per-model/per-device tuning
  knob, not a guaranteed speedup. For the measured Gemma 4 E2B LiteRT-LM runs,
  speculative decoding was slower on Pixel 9 Pro GPU and Apple M4 Max Metal, so
  the `LlamaEngine` default remains off.
- On Android, benchmark LiteRT-LM `gpu` and `npu` separately when the model and
  device support them. NPU is not a general replacement for GGUF/Vulkan; it is a
  LiteRT-LM deployment path.
- On desktop, GGUF / llama.cpp is usually the more complete production backend
  unless your product specifically ships LiteRT-LM bundles.
- Keep the backend choice visible in logs or diagnostics with
  `engine.getBackendName()` so support reports include the actual runtime path.
