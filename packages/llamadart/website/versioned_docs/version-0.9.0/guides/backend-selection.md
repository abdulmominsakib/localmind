---
title: Choosing llama.cpp or LiteRT-LM
sidebar_label: llama.cpp or LiteRT-LM
description: Decide when to use GGUF with llama.cpp or .litertlm bundles with LiteRT-LM in llamadart.
---

## Quick answer

| Choose this | Best fit | Tradeoffs |
| --- | --- | --- |
| `llama.cpp` / GGUF | Broad model catalog, many quantizations, embeddings, LoRA, state persistence, grammar constraints, multimodal, and low-level runtime tuning. | Mobile GPU performance depends heavily on the device, driver, model size, and backend. It does not use LiteRT-LM NPU delegates. |
| LiteRT-LM / `.litertlm` | LiteRT-LM bundles, Gemma 4 LiteRT-LM variants, Android GPU/NPU delegate experiments, and app flows that only need text generation/chat. | Smaller model catalog and fewer exposed runtime features today. Unsupported llama.cpp-only options are rejected. |

- Start with GGUF / llama.cpp if you need the broadest model support or
  embeddings, dynamic LoRA adapters, grammar constraints, state persistence, or
  multimodal projectors.
- Start with LiteRT-LM if your model already ships as a `.litertlm` bundle and
  your app mainly needs text generation or chat on mobile or web.
- On desktop, GGUF / llama.cpp is usually the more complete production backend
  unless your product specifically ships LiteRT-LM bundles.
- On Android, benchmark LiteRT-LM `gpu` and `npu` separately when the model and
  device support them. NPU is a LiteRT-LM deployment path, not a general
  replacement for GGUF/Vulkan.
- If both formats exist for your model, [measure](#measure-before-choosing)
  before choosing.
- Log `engine.getBackendName()` so support reports name the actual runtime.

## How routing works

`LlamaBackend()` picks the runtime from the file extension: `.litertlm` runs on
LiteRT-LM; `.gguf` and any other file run on llama.cpp. The `LlamaEngine` API
is the same for both, including `ChatSession` on native.

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

`LiteRtLmBackendPreference.auto`, the default, follows `ModelParams`:
`gpuLayers: 0` or a CPU or BLAS `preferredBackend` selects CPU; a GPU
`preferredBackend` (Vulkan, Metal, CUDA, OpenCL or HIP) selects the LiteRT-LM
GPU backend; and `preferredBackend: auto` selects GPU on Android, iOS, macOS
and web, and CPU on Linux and Windows. Linux arm64 has no LiteRT-LM GPU
backend, so a GPU selection there fails the load with `LlamaModelException`;
set `liteRtLmBackend: cpu`. Windows arm64 has no LiteRT-LM runtime.
`npu` is Android-only; LiteRT-LM web rejects it.

Formats are not interchangeable: a GGUF file cannot run through LiteRT-LM, and
a `.litertlm` bundle cannot run through llama.cpp. Load and generation
parameters are validated against the selected runtime. `llamadart` rejects
unsupported options for `.litertlm` loads instead of ignoring them, so a GGUF
tuning profile cannot appear to work while doing something different under
LiteRT-LM.

Use `ModelSource` / `loadModelSource(...)` for download and cache flows. Native
targets cache remote GGUF and `.litertlm` sources before loading a local file.
Web targets pass simple unauthenticated `.litertlm` URLs to the LiteRT-LM
JavaScript runtime.

## What each runtime supports

| Capability | llama.cpp / GGUF | LiteRT-LM / `.litertlm` |
| --- | --- | --- |
| Native Android | CPU, Vulkan, optional OpenCL modules | CPU, GPU, Android-only NPU selector |
| Native iOS/macOS | Consolidated CPU + Metal runtime | CPU/GPU (macOS x64: CPU only) |
| Native Linux/Windows | CPU, Vulkan, and target-specific optional modules | CPU default; explicit GPU on Linux x64 (Vulkan) and Windows x64 (Direct3D 12), with compatible drivers. Linux arm64 remains CPU-only. |
| Web | llama.cpp WebGPU/CPU bridge for GGUF URLs | `@litert-lm/core` for web-compatible `.litertlm` URLs |
| Embeddings | Supported on native; supported on web bridge assets with embedding APIs | Not exposed by current LiteRT-LM APIs |
| Next-token log-probabilities | Supported on native and on WebGPU bridge assets `v0.1.52+` | Not exposed |
| KV-cache state persistence | Supported on native; supported on WebGPU bridge assets that expose state APIs | Not exposed |
| LoRA adapters | Supported on native GGUF flows, and at runtime on WebGPU bridge assets `v0.1.54+` | Native: one default-scale text LoRA adapter at model load. Web: not exposed. Runtime updates, stacking, and scaling are not exposed for `.litertlm`. |
| Thinking and tool-call parsing | Supported through template handlers | Native: supported through the high-level `LlamaEngine` parser for compatible templates; LiteRT-native constrained tool execution is not wired yet. Web: single-turn text only; no structured chat/tool forwarding yet. |
| Grammar / constrained decoding | Supported by llama.cpp-backed paths | llama.cpp GBNF is not supported; template-generated tool grammar is skipped, strict `responseFormat` requests fail early, and explicit grammar params are rejected |
| Multimodal input | Supported through llama.cpp `mtmd` paths where the model/projector supports it | No external projector. Native bundles accept `LlamaImageContent`/`LlamaAudioContent` path or bytes input through bundle-native processors (see [Multimodal](./multimodal)); web is text-only. |
| Tokenization APIs | Supported | Supported on native LiteRT-LM; not exposed on LiteRT-LM web |

Load-time controls differ by runtime:

- GGUF / llama.cpp: `preferredBackend`, `gpuLayers`, `contextSize`,
  `numberOfThreads` / `numberOfThreadsBatch`, `batchSize` / `microBatchSize`,
  `splitMode` / `mainGpu`, and the LoRA and state-persistence APIs.
- `.litertlm` / LiteRT-LM: `liteRtLmBackend` (`auto`, `cpu`, `gpu`, or
  Android-native `npu`), `contextSize`, `chatTemplate`, `numberOfThreads`, one
  default-scale text LoRA adapter through `ModelParams.loras`, and the native
  `liteRtLm*` fields in
  [LiteRT-LM runtime controls](../configuration/runtime-parameters#litert-lm-runtime-controls).
  Generation honors `maxTokens`, `temp`, `topK`, `topP`, `seed`, and
  `stopSequences` (enforced by `llamadart`); `speculativeDecoding` is native
  only.

Bundle keys, module availability and selector names are in
[Native runtime configuration](../platforms/native-build-hooks).

## LiteRT-LM on web

LiteRT-LM web is narrower than native LiteRT-LM: it forwards single-turn text
prompts to `@litert-lm/core` and does not yet preserve `ChatSession` history,
system prompts, or tool declarations. It rejects the native-only `liteRtLm*`
runtime fields because the browser API does not expose matching controls.

## Measure before choosing

If both formats exist for your model, treat the choice as a deployment
benchmark: measure the exact model artifact, device, prompt shape, and output
length your app will ship. The files may not be identical quantizations or
runtime graphs, so this compares deployments, not kernels.

- Keep the device awake, unlocked, foregrounded, and out of battery saver.
- Record thermal status and cooling state before and after the run.
- Use the same prompt, output-token cap, context size, stop rules, and sampling
  settings where both backends expose them.
- Separate cold-start numbers from warm steady-state numbers.
- Run enough repetitions to report median and outliers, not only the last run.
- Record early EOS separately from requested output length.
- Compare wall-clock latency and backend timing counters; they answer different
  questions.
- Treat `GenerationParams.speculativeDecoding` as a per-model, per-device
  tuning knob, not a guaranteed speedup; the `LlamaEngine` default is off.

[Backend benchmarks](./backend-benchmarks) has measured Gemma 4 E2B results on
Pixel 9 Pro, macOS, and web, including speculative decoding.

## Reduce app size

Native apps include every available runtime family by default, so one build can
load both GGUF and `.litertlm` models. To ship only one, set
`llamadart_native_runtimes` as described in
[Native Build Hooks](../platforms/native-build-hooks).
