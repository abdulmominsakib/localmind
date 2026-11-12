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

## Checking the loaded runtime

After a load, `engine.runtime` is `LlamaRuntime.llamaCpp` for GGUF, native or
WebGPU, and `LlamaRuntime.liteRtLm` for a bundle. `await engine.capabilities`
reports what that runtime supports for the loaded model, so an app can offer
only what works instead of checking the file extension:

```dart
final caps = await engine.capabilities;
final params = GenerationParams(
  minP: caps.supportsMinP ? 0.05 : 0.0,
  penalty: caps.supportsPenalty ? 1.1 : const GenerationParams().penalty,
);
final offerTools = caps.supportsToolCalling;
final offerImages = caps.supportsVision;
```

The [support matrix](../platforms/support-matrix#features-by-runtime) lists
what each runtime reports.

## How routing works

`LlamaBackend()` picks the runtime from the model format: LiteRT-LM bundles run
on LiteRT-LM, and GGUF files run on llama.cpp. The `LlamaEngine` API is the
same for both, including `ChatSession` on native.

Native targets read the file header (`GGUF` or `LITERTLM`), so a file named
without a model extension, such as a download cached as `download`, still
loads in the right runtime. Only when the header is unrecognized do they fall
back to the extension: `.litertlm` runs on LiteRT-LM and anything else on
llama.cpp. A header that contradicts the extension, such as a GGUF file named
`model.litertlm`, throws `LlamaModelFormatException` instead of loading in
either runtime.

Web targets hand the URL to the runtime, which fetches it, so nothing reads the
content first: a `.litertlm` URL path runs on LiteRT-LM and anything else on
the llama.cpp WebGPU bridge. For a URL without a model extension, name the
format:

```dart
await engine.setModel(
  LlamaModel(
    ModelSource.url(
      Uri.parse('https://example.com/download?id=42'),
      format: ModelFormat.liteRtLm,
    ),
  ),
);
```

On native targets, `format:` names the format of a file whose header is
unrecognized; a recognized header that contradicts it throws
`LlamaModelFormatException`. LiteRT-LM still picks its Gemma 4 and Qwen
chat-template defaults from the file name, so pass a `fileName:` such as
`gemma-4-E2B-it.litertlm` when the URL does not name the model.

```dart
final engine = LlamaEngine(LlamaBackend());

// GGUF routes to llama.cpp.
await engine.setModel(
  LlamaModel(ModelSource.path('models/model-Q4_K_M.gguf')),
);

// .litertlm routes to LiteRT-LM. setModel replaces the GGUF model.
await engine.setModel(
  LlamaModel(ModelSource.path('models/gemma-4-E2B-it.litertlm')),
  params: const ModelParams(device: ComputeDevice.gpu),
);
```

## Choosing the device

`ModelParams.device` picks the device for either runtime. `ComputeDevice.auto`,
the default, keeps each runtime's own default:

| Runtime | `ComputeDevice.auto` |
| --- | --- |
| llama.cpp native | Every layer on the best GPU backend that loads; the CPU when no GPU module or device is present, and on Android. |
| llama.cpp Web | The bridge's default: WebGPU when the browser has it, otherwise the WebAssembly CPU runtime. |
| LiteRT-LM native | GPU on Android, iOS and macOS; CPU on Linux and Windows. |
| LiteRT-LM Web | WebGPU, without a probe. |
| Image generation | The first GPU the stable-diffusion runtime reports, otherwise the CPU. |
| Decision models | As llama.cpp, through the encoder's `ModelParams`. |

Under `auto`, `preferredBackend` and `gpuLayers` still narrow the choice, as
before: `gpuLayers: 0` or a CPU or BLAS `preferredBackend` selects the CPU on
both runtimes, and a GPU `preferredBackend` (Vulkan, Metal, CUDA, OpenCL or
HIP) selects the LiteRT-LM GPU backend.

`cpu`, `gpu` and `npu` are requirements. The model runs there, or the load
throws `LlamaUnsupportedException` naming the device, runtime and platform; it
never falls back to another device:

- `cpu` loads no GPU layers and, on llama.cpp, only the CPU module.
- `gpu` on llama.cpp needs a GPU module and device for `preferredBackend`, and
  uses Vulkan on Android. Android Vulkan is experimental and fails on some
  devices; keep `auto` or `cpu` there unless you have validated your target
  devices
  ([known limitations](../platforms/support-matrix#known-limitations)). On
  the Web it needs a WebGPU adapter and a bridge that loads GPU layers. On
  LiteRT-LM it needs the GPU backend: Linux arm64 and macOS x64 have none.
- `npu` is LiteRT-LM on Android only.

Native LiteRT-LM starts its runtime on the first call that needs it, such as
the first generation or `tokenize`, so a GPU or NPU delegate that fails to
start throws `LlamaUnsupportedException` there rather than from the load. The
runtime does not say why it could not start, so under `gpu` or `npu` a
corrupt or truncated `.litertlm` file throws the same exception, whose
message names both causes. Windows arm64 has no LiteRT-LM runtime.

`ModelParams.validate()`, which every `LlamaEngine` load calls before any
download, throws `LlamaArgumentException` when `device` contradicts another
field: `cpu` with a GPU `preferredBackend`, `gpu` or `npu` with a CPU or BLAS
`preferredBackend`, `gpuLayers: 0`, or `splitMode: ModelSplitMode.none` with a
negative `mainGpu` (which llama.cpp runs on the CPU), or any explicit device
with the deprecated `liteRtLmBackend`.

`ModelParams.liteRtLmBackend` and `LiteRtLmBackendPreference` are deprecated
and keep working until 1.0. Under `device: auto` they still choose the
LiteRT-LM backend alone, for example to run llama.cpp on the CPU and LiteRT-LM
on the GPU from one `ModelParams`, and an unavailable choice still throws
`LlamaModelException`.

Formats are not interchangeable: a GGUF file cannot run through LiteRT-LM, and
a `.litertlm` bundle cannot run through llama.cpp. Load and generation
parameters are validated against the selected runtime. `llamadart` rejects
unsupported options for `.litertlm` loads instead of ignoring them, so a GGUF
tuning profile cannot appear to work while doing something different under
LiteRT-LM.

Pass a remote `ModelSource` to `LlamaEngine.load` or `setModel` for download
and cache flows. Native
targets cache remote GGUF and `.litertlm` sources before loading a local file.
Web targets pass simple unauthenticated `.litertlm` URLs to the LiteRT-LM
JavaScript runtime.

## What each runtime supports

| Capability | llama.cpp / GGUF | LiteRT-LM / `.litertlm` |
| --- | --- | --- |
| Native Android | CPU, experimental Vulkan, optional OpenCL modules | CPU, GPU, Android-only NPU selector |
| Native iOS/macOS | Consolidated CPU + Metal runtime | CPU/GPU (macOS x64: CPU only) |
| Native Linux/Windows | CPU, Vulkan, and target-specific optional modules | CPU default; explicit GPU on Linux x64 (Vulkan) and Windows x64 (Direct3D 12), with compatible drivers. Linux arm64 remains CPU-only. |
| Web | llama.cpp WebGPU/CPU bridge for GGUF URLs | `@litert-lm/core` for web-compatible `.litertlm` URLs |
| Embeddings | Supported on native; supported on web bridge assets with embedding APIs | Not exposed by current LiteRT-LM APIs |
| Next-token log-probabilities | Supported on native and on WebGPU bridge assets `v0.1.52+` | Not exposed |
| KV-cache state persistence | Supported on native; supported on WebGPU bridge assets that expose state APIs | Not exposed |
| LoRA adapters | Supported on native GGUF flows, and at load or runtime on WebGPU bridge assets `v0.1.54+` | Native: one default-scale text LoRA adapter at model load. Web: not exposed. Runtime updates, stacking, and scaling are not exposed for `.litertlm`. |
| Thinking and tool-call parsing | Supported through template handlers | Native: supported through the high-level `LlamaEngine` parser for compatible templates; LiteRT-native constrained tool execution is not wired yet. Web: single-turn text only; no structured chat/tool forwarding yet. |
| Grammar / constrained decoding | Supported by llama.cpp-backed paths | llama.cpp GBNF is not supported; template-generated tool grammar is skipped, strict `responseFormat` requests fail early, and explicit grammar params are rejected |
| Multimodal input | Supported through llama.cpp `mtmd` paths where the model/projector supports it | No external projector. Native bundles accept `LlamaImageContent`/`LlamaAudioContent` path or bytes input through bundle-native processors (see [Multimodal](./multimodal)); web is text-only. |
| Tokenization APIs | Supported | Supported on native LiteRT-LM; not exposed on LiteRT-LM web |

Load-time controls differ by runtime:

- Both: `device`.
- GGUF / llama.cpp: `preferredBackend`, `gpuLayers`, `contextSize`,
  `chatTemplate`, `numberOfThreads` / `numberOfThreadsBatch`, `batchSize` /
  `microBatchSize`, `splitMode` / `mainGpu`, and the LoRA and
  state-persistence APIs.
- `.litertlm` / LiteRT-LM: the deprecated `liteRtLmBackend`, `contextSize`,
  `chatTemplate`, `numberOfThreads`, one
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

Native apps include the llama.cpp and LiteRT-LM runtime families by default, so
one build can load both GGUF and `.litertlm` models. To ship only one, set
`llamadart_native_runtimes` as described in
[Native Build Hooks](../platforms/native-build-hooks). The experimental
`stable_diffusion` runtime, which [image generation](./image-generation)
needs, is never included unless named there.
