---
title: Platform and backend support matrix
sidebar_label: Support matrix
description: Check which runtimes, backends and features llamadart supports on each platform, the known limitations, and the pinned runtime versions.
---

Use this page to check whether a runtime or feature works on a platform.
`LlamaBackend()` picks the runtime from the model file: `.litertlm` models run
on LiteRT-LM, and `.gguf` and every other extension run on llama.cpp natively
or on the WebGPU bridge in a browser. To choose backend modules or leave a
runtime out of the app, see [Native runtime configuration](./native-build-hooks).

## At a glance

| Platform | GGUF backends | LiteRT-LM backends | Minimum OS | Speech to text | Text to speech | Decision models | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Android (arm64, x64) | CPU, Vulkan; OpenCL opt-in | CPU, GPU, NPU | Not set by llamadart | Qwen3-ASR (GGUF); LiteRT-LM ASR | Qwen3-TTS | Untested | Supported |
| iOS (arm64, arm64 simulator, x86_64 simulator) | CPU, Metal | CPU, GPU; none on the x86_64 simulator | iOS 16.4 | Qwen3-ASR (GGUF); LiteRT-LM ASR | Qwen3-TTS | Untested | Supported |
| macOS (arm64, x86_64) | CPU, Metal | arm64: CPU, GPU; x86_64: CPU | macOS 14.0 (Flutter) | Qwen3-ASR (GGUF); LiteRT-LM ASR | Qwen3-TTS | Validated on Metal and CPU | Supported |
| Linux (arm64, x64) | CPU, Vulkan; BLAS opt-in; x64: CUDA, HIP opt-in | arm64: CPU; x64: CPU, explicit GPU | Not set by llamadart | Qwen3-ASR (GGUF); LiteRT-LM ASR | Qwen3-TTS | Untested | Supported |
| Windows (arm64, x64) | CPU, Vulkan; BLAS opt-in; x64: CUDA opt-in | x64: CPU, explicit GPU; arm64: none | Not set by llamadart | Qwen3-ASR (GGUF); LiteRT-LM ASR on x64 | Qwen3-TTS | Untested | Supported |
| Web | WebGPU, WebAssembly CPU | CPU, GPU through `@litert-lm/core` | Chrome 128, Firefox 129, Safari 17.4 | Qwen3-ASR, WAV, MP3 or FLAC bytes, bridge `v0.1.30+` | Qwen3-TTS, bridge `v0.1.33+`, memory64 | Bridge `v0.1.47+`; checked in headless Chromium on macOS | Experimental |

Speech to text, text to speech and decision models are experimental. GGUF
Qwen3-ASR accepts WAV, MP3 and FLAC; real-model checks cover all three on
native macOS and in headless Chromium. LiteRT-LM ASR is CPU-only streaming
recognition. Decision models run on llama.cpp and WebGPU only; on LiteRT-LM
`DecisionEngine.load` throws `LlamaUnsupportedException`. See
[Speech to text](../guides/speech-to-text#choose-an-approach),
[Text to speech](../guides/text-to-speech) and
[Decision models](../guides/decision-models).

`LiteRtLmBackendPreference.auto`, the default, follows `ModelParams`:
`gpuLayers: 0` or a CPU or BLAS `preferredBackend` selects CPU; a GPU
`preferredBackend` (Vulkan, Metal, CUDA, OpenCL or HIP) selects the LiteRT-LM
GPU backend; and `preferredBackend: auto` selects GPU on Android, iOS, macOS
and web, and CPU on Linux and Windows. Linux arm64 has no LiteRT-LM GPU
backend, so a GPU selection there fails the load with `LlamaModelException`;
set `liteRtLmBackend: cpu`. Windows arm64 has no LiteRT-LM runtime. On Linux x64
and Windows x64, GPU uses the LiteRT-LM GPU backend, not CUDA; set
`liteRtLmBackend: cpu` on hosts without a hardware Vulkan driver. NPU is
Android-only; web rejects it.

## Features by runtime

| Feature | Native llama.cpp | WebGPU | Native LiteRT-LM | LiteRT-LM Web |
| --- | --- | --- | --- | --- |
| LoRA | `setLora` at runtime, stacked and scaled; aLoRA rejected | Same, with bridge assets whose `getLoraAdapterCapabilities()` reports support ([llama-web-bridge#142](https://github.com/leehack/llama-web-bridge/pull/142)); otherwise rejected | One default-scale text adapter through `ModelParams.loras` at load | No |
| Thinking budget | Text-only generation, without speculative decoding | Text-only, with bridge assets whose `getCompletionCapabilities()` reports `thinkingBudget` ([llama-web-bridge#144](https://github.com/leehack/llama-web-bridge/pull/144)); otherwise rejected | No | No |
| Lazy grammar | Yes | No: `grammar` applies from the first token, from `root` | No GBNF grammar | No GBNF grammar |
| Presence penalty | Yes | With bridge assets whose `getCompletionCapabilities()` reports `presencePenalty` ([llama-web-bridge#140](https://github.com/leehack/llama-web-bridge/pull/140)); otherwise rejects a non-zero value | No: rejects a non-zero value | No: rejects a non-zero value |
| Min-P | Yes | With bridge assets whose `getCompletionCapabilities()` reports `minP` ([llama-web-bridge#140](https://github.com/leehack/llama-web-bridge/pull/140)); otherwise rejects a non-zero value | No: rejects a non-zero value | No: rejects a non-zero value |
| Speculative decoding | Draft model, MTP, n-gram and DSpark strategies | Same, with bridge assets whose `getCompletionCapabilities()` reports the strategy ([llama-web-bridge#153](https://github.com/leehack/llama-web-bridge/pull/153)); draft and n-gram cache paths are URLs, and MTP uses the model's own layers; otherwise rejected | Runtime default or MTP | No |
| State persistence | Yes | Bridge `v0.1.15+`; WASMFS paths, lost on page reload | No | No |
| Embeddings | Yes | Bridge `v0.1.7+` | No | No |
| Next-token scores | Yes | Bridge `v0.1.52+` | No | No |
| Per-request usage | `usage` on the final `create` chunk | Bridge `v0.1.54+` | No | No ([#725](https://github.com/leehack/llamadart/issues/725)) |
| Operation observers | Yes; after a load, `runtime` is `llamaCpp` | Yes; after a load, `runtime` is `llamaCpp` | Yes; after a load, `runtime` is `liteRtLm` | Yes; after a load, `runtime` is `liteRtLm` |
| Multi-turn `ChatSession` | Yes | Yes | Yes | No: single-turn text prompts only |
| Multimodal | Image and audio with a projector | Image and audio with a projector URL | Image and audio files or bytes, when the bundle supports them | No |
| Video | No | No | No | No |

`LlamaEngine.supportsVideo` returns `false` on every runtime, and passing
`LlamaVideoContent` throws `LlamaUnsupportedException`. Web state paths point
into the bridge's WASMFS virtual filesystem; to keep state across reloads,
export and import it in app code. Bridge assets `v0.1.54+`, the default pin
among them, report the WebGPU LoRA, thinking-budget, presence-penalty, Min-P
and speculative decoding capabilities; older assets report none of them.
`LlamaEngine.backendGenerationCapabilities` reports the presence-penalty, Min-P,
thinking-budget and speculative decoding rows for the loaded model. Guides:
[LoRA adapters](../guides/lora-adapters),
[Tool calling](../guides/tool-calling#tool-choice-semantics),
[Performance tuning](../guides/performance-tuning),
[Multimodal](../guides/multimodal),
[Embeddings](../guides/embeddings),
[Observing operations](../guides/generation-and-streaming#observing-operations).

## Known limitations

- iOS x86_64 simulator: no LiteRT-LM runtime is published. Apps that include
  LiteRT-LM must exclude the x86_64 simulator architecture; llama.cpp still
  builds for it.
- Linux x64 LiteRT-LM GPU needs a hardware Vulkan driver. On Mesa llvmpipe
  alone it answers a few prompts, then crashes the process; use `cpu` on such
  hosts ([#572](https://github.com/leehack/llamadart/issues/572)).
- Android LiteRT-LM GPU on adapters with a 128 MiB storage-buffer binding
  limit, such as Adreno 750: a model with a larger weight buffer loads without
  an error and generates incoherent text; use `cpu`
  ([#553](https://github.com/leehack/llamadart/issues/553)).
- Windows x64 LiteRT-LM GPU needs `litert-lm-native` `v0.17.0-6` or later,
  which bundles `dxil.dll` and `dxcompiler.dll`. The pinned runtime includes
  them.
- Android NPU depends on the device SoC, the `.litertlm` bundle and the LiteRT
  dispatch libraries (`ModelParams.liteRtLmDispatchLibDir`). If native
  LiteRT-LM cannot create an NPU engine, use `cpu` or `gpu`.
- Some Vulkan drivers crash in the cooperative-matrix path; see
  [GPU crash or device loss](../troubleshooting/common-issues#gpu-crash-or-device-loss).
- WebGPU readiness depends on the browser, device, bridge assets and model
  size; see [WebGPU bridge](./webgpu-bridge).

## Pinned runtimes

| Runtime | Pinned release |
| --- | --- |
| llama.cpp native | `leehack/llamadart-native@v0.5.0` |
| LiteRT-LM native | `leehack/litert-lm-native@v0.17.0-6` |
| WebGPU bridge assets | `leehack/llama-web-bridge-assets`; see [Pinned bridge assets](./webgpu-bridge#pinned-bridge-assets) |

The native-assets hook currently pins `llamadart-native` tag
`v0.5.0` and
`litert-lm-native` release `v0.17.0-6` (`lib/src/hook/native_release_pins.dart`).
Apps can override the llama.cpp release with `llamadart_native_tag`, which
takes a `vMAJOR.MINOR.PATCH`, `vMAJOR.MINOR.PATCH-N`, `bNNNN`, `bNNNN-N` or
`bNNNN-llamadart.N` tag; nightly cores and rebuild counters reject leading
zeros. Build-hook overrides must always name an explicit tag; `latest` is
limited to maintainer synchronization and header/binding regeneration. Keys,
backend modules and local bundles:
[Native runtime configuration](./native-build-hooks).

Apps load the bridge assets themselves; see
[Add the bridge to your app](./webgpu-bridge#add-the-bridge-to-your-app).
Linux system libraries: [Linux prerequisites](./linux-prerequisites).
