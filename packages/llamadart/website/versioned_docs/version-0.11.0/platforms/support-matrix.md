---
title: Platform and backend support matrix
sidebar_label: Support matrix
description: Check which runtimes, backends and features llamadart supports on each platform, the known limitations, and the pinned runtime versions.
---

Use this page to check whether a runtime or feature works on a platform.
`LlamaBackend()` picks the runtime from the model format: LiteRT-LM bundles run
on LiteRT-LM, and GGUF files run on llama.cpp natively or on the WebGPU bridge
in a browser. Native targets read the file header; web targets use the URL's
extension or `ModelSource.format`
([How routing works](../guides/backend-selection#how-routing-works)). To choose backend modules or leave a
runtime out of the app, see [Native runtime configuration](./native-build-hooks).

## At a glance

| Platform | GGUF backends | LiteRT-LM backends | Minimum OS | Speech to text | Text to speech | Decision models | Image generation (Preview) | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Android (arm64, x64) | CPU; Vulkan experimental, device-dependent; OpenCL opt-in | CPU, GPU, NPU | Not set by llamadart | Qwen3-ASR (GGUF); LiteRT-LM ASR | Qwen3-TTS | Untested | arm64 CPU; validated on Pixel 9 Pro, Galaxy S24 and A53 | Supported |
| iOS (arm64, arm64 simulator, x86_64 simulator) | CPU, Metal | CPU, GPU; none on the x86_64 simulator | iOS 16.4 deployment target; LiteRT-LM run on a device only on iOS 18.3.2 | Qwen3-ASR (GGUF); LiteRT-LM ASR | Qwen3-TTS | Untested | Metal, iOS 16.4; validated on iPhone 16 Pro and SE 3 | Supported |
| macOS (arm64, x86_64) | CPU, Metal | arm64: CPU, GPU; x86_64: CPU | macOS 14.0 (Flutter) | Qwen3-ASR (GGUF); LiteRT-LM ASR | Qwen3-TTS | Validated on Metal and CPU | Metal, macOS 13.3; validated on arm64 | Supported |
| Linux (arm64, x64) | CPU, Vulkan; BLAS opt-in; x64: CUDA, HIP opt-in | arm64: CPU; x64: CPU, explicit GPU | Not set by llamadart | Qwen3-ASR (GGUF); LiteRT-LM ASR | Qwen3-TTS | Untested | CPU or Vulkan; x64 needs AVX2; validated on x64 (CPU, NVIDIA L4) | Supported |
| Windows (arm64, x64) | CPU, Vulkan; BLAS opt-in; x64: CUDA opt-in | x64: CPU, explicit GPU; arm64: none | Not set by llamadart | Qwen3-ASR (GGUF); LiteRT-LM ASR on x64 | Qwen3-TTS | Untested | x64 CPU or Vulkan, needs AVX2 and the Visual C++ runtime; validated on Windows Server 2022 (CPU, NVIDIA L4) | Supported |
| Web | WebGPU, WebAssembly CPU | CPU, GPU through `@litert-lm/core` | Chrome 128, Firefox 129, Safari 17.4 | Qwen3-ASR, WAV, MP3 or FLAC bytes, bridge `v0.1.30+` | Qwen3-TTS, bridge `v0.1.33+`, memory64 | Bridge `v0.1.47+`; checked in headless Chromium on macOS | Not yet ([#780](https://github.com/leehack/llamadart/issues/780)) | Experimental |

On Windows, llama.cpp needs the latest Microsoft Visual C++ v14
Redistributable for the app's architecture (x64 or arm64), at least as new as
the build tools of the bundled DLLs, which the bundles do not ship. Stock Windows Server lacks it, and the load error names the DLLs
that failed to load.

Speech to text, text to speech and decision models are experimental. Image
generation is a Preview: its API is experimental and may change, and it needs
the opt-in `stable_diffusion` runtime,
built for iOS 16.4 and macOS 13.3; x64 Linux and Windows CPUs need AVX2, FMA,
F16C and BMI2, Windows needs the latest Microsoft Visual C++ v14
Redistributable (x64), and Android arm64 needs dot-product and fp16. The
desktop models (SDXL-Lightning, FLUX.1-schnell, SD 3.5 Large Turbo,
Z-Image-Turbo) need about 8 to 15 GiB and are validated on macOS Metal; NVIDIA
Vulkan figures come from the native CLI. See
[Image generation](../guides/image-generation#support). GGUF
Qwen3-ASR accepts WAV, MP3 and FLAC; real-model checks cover all three on
native macOS and in headless Chromium. LiteRT-LM ASR is CPU-only streaming
recognition. Decision models run on llama.cpp and WebGPU only; on LiteRT-LM
`DecisionEngine.load` and `attach` throw `LlamaUnsupportedException`. See
[Speech to text](../guides/speech-to-text#choose-an-approach),
[Text to speech](../guides/text-to-speech) and
[Decision models](../guides/decision-models).

## Compute device

`ModelParams.device` (`ComputeDevice`) applies to every runtime. `auto` keeps
each runtime's default; `cpu`, `gpu` and `npu` run there or throw
`LlamaUnsupportedException`, never on another device. See
[Choosing the device](../guides/backend-selection#choosing-the-device).

| Runtime | `auto` | `gpu` | `npu` |
| --- | --- | --- | --- |
| Native llama.cpp | Best GPU backend that loads, all layers; CPU without a GPU module or device, and on Android | Needs a GPU module and device; Vulkan on Android (experimental) | Throws |
| WebGPU (llama.cpp) | WebGPU when available, else the WebAssembly CPU runtime | Needs a WebGPU adapter and GPU layers after load; no CPU retry | Throws |
| Native LiteRT-LM | GPU on Android, iOS and macOS; CPU on Linux and Windows | GPU backend on Android, iOS, macOS arm64, Linux x64 (Vulkan) and Windows x64 (Direct3D 12); a delegate that fails to start throws on first use | Android only |
| LiteRT-LM Web | WebGPU, without a probe | Needs a WebGPU adapter | Throws |
| Image generation | First GPU reported, else CPU | Needs a GPU; Android and the CPU builds have none | Throws |
| LiteRT-LM ASR | CPU | Not selectable | Not selectable |

Under `auto`, `gpuLayers: 0` or a CPU or BLAS `preferredBackend` selects the
CPU on both llama.cpp and LiteRT-LM, and a GPU `preferredBackend` (Vulkan,
Metal, CUDA, OpenCL or HIP) selects the LiteRT-LM GPU backend. On Linux x64
and Windows x64, the LiteRT-LM GPU backend is not CUDA; use `device: cpu` on
hosts without a hardware Vulkan driver. Windows arm64 has no LiteRT-LM
runtime. The deprecated `liteRtLmBackend` selector works until 1.0; an
unavailable choice there throws `LlamaModelException`.

## Features by runtime

| Feature | Native llama.cpp | WebGPU | Native LiteRT-LM | LiteRT-LM Web |
| --- | --- | --- | --- | --- |
| LoRA | `ModelParams.loras` at load and `setLoraSource` at runtime, stacked and scaled; aLoRA rejected | Same, with bridge assets whose `getLoraAdapterCapabilities()` reports support ([llama-web-bridge#142](https://github.com/leehack/llama-web-bridge/pull/142)); otherwise rejected | One default-scale text adapter through `ModelParams.loras` at load | No |
| Thinking budget | Text-only generation, without speculative decoding | Text-only, with bridge assets whose `getCompletionCapabilities()` reports `thinkingBudget` ([llama-web-bridge#144](https://github.com/leehack/llama-web-bridge/pull/144)); otherwise rejected | No | No |
| Strict `responseFormat` | Yes | Yes, without tools | No | No |
| Lazy grammar | Yes | No: `grammar` applies from the first token, from `root` | No GBNF grammar | No GBNF grammar |
| Presence penalty | Yes | With bridge assets whose `getCompletionCapabilities()` reports `presencePenalty` ([llama-web-bridge#140](https://github.com/leehack/llama-web-bridge/pull/140)); otherwise rejects a non-zero value | No: rejects a non-zero value | No: rejects a non-zero value |
| Min-P | Yes | With bridge assets whose `getCompletionCapabilities()` reports `minP` ([llama-web-bridge#140](https://github.com/leehack/llama-web-bridge/pull/140)); otherwise rejects a non-zero value | No: rejects a non-zero value | No: rejects a non-zero value |
| Repetition `penalty` | Yes | Yes | No: rejects a value other than the default | No: rejects a value other than the default |
| Speculative decoding | Draft model, MTP, n-gram and DSpark strategies; recurrent/hybrid models reject nonzero rollback capacity | Same, with bridge assets whose `getCompletionCapabilities()` reports the strategy ([llama-web-bridge#153](https://github.com/leehack/llama-web-bridge/pull/153)); draft and n-gram cache paths are URLs, and MTP uses the model's own layers; otherwise rejected | Runtime default or MTP, for bundles with a speculative drafter; `capabilities` reports the bundle's declaration | No |
| State persistence | Yes | Bridge `v0.1.15+`; WASMFS paths, lost on page reload | No | No |
| Embeddings | Yes; one-pass attention and MEAN/CLS inputs must fit the physical micro-batch | Bridge `v0.1.7+` | No | No |
| Next-token scores | Yes | Bridge `v0.1.52+` | No | No |
| Generation-limit reporting | `length` for output or context limits | `length` with bridge usage probe (`v0.1.54+`); cap cause unspecified | No | No |
| Per-request usage | `usage` on the final `create` chunk | Bridge `v0.1.54+` | No | No ([#725](https://github.com/leehack/llamadart/issues/725)) |
| Operation observers | Yes; after a load, `runtime` is `llamaCpp` | Yes; after a load, `runtime` is `llamaCpp` | Yes; after a load, `runtime` is `liteRtLm` | Yes; after a load, `runtime` is `liteRtLm` |
| Multi-turn `ChatSession` | Yes | Yes | Yes | No: single-turn text prompts only |
| Tool calling | Yes | Yes | Yes | No: tools do not reach the model |
| Automatic `sendWithTools` / `completeWithTools` loop | Yes | Requires reliable runtime finish reporting | No: pinned runtime has no reliable termination cause; throws before generation | No: pinned runtime has no reliable termination cause; throws before generation |
| Multimodal | Image and audio with a projector | Image and audio with a projector URL | Image and audio files or bytes, when the bundle supports them | No |
| Video | No | No | No | No |

`LlamaEngine.supportsVideo` returns `false` on every runtime, and passing
`LlamaVideoContent` throws `LlamaUnsupportedException`. Web state paths point
into the bridge's WASMFS virtual filesystem; to keep state across reloads,
export and import it in app code. Bridge assets `v0.1.54+`, the default pin
among them, report the WebGPU LoRA, thinking-budget, presence-penalty, Min-P
and speculative decoding capabilities; older assets report none of them.
After a load, `LlamaEngine.runtime` names the runtime and
`LlamaEngine.capabilities` reports the rows of this table for the loaded model:
media input, embeddings, next-token scores, multi-turn chat, tools, structured
output and grammars, sampling controls and speculative decoding. Guides:
[LoRA adapters](../guides/lora-adapters),
[Tool calling](../guides/tool-calling#tool-choice-semantics),
[Performance tuning](../guides/performance-tuning),
[Multimodal](../guides/multimodal),
[Embeddings](../guides/embeddings),
[Observing operations](../guides/generation-and-streaming#observing-operations).

## Known limitations

- Native LiteRT-LM v0.17.0-8 iOS artifacts omit the Gemma FST constraint
  provider. Gemma 3/4 and FunctionGemma conversations must disable constrained
  decoding; Dart already does so. Ordinary generation, thinking and best-effort
  tool formatting remain available. Automatic tool loops and strict structured
  output remain unsupported.
- Native LiteRT-LM on iOS: iOS 16.4 is the declared deployment floor, not a
  tested one. The companion Swift package requires an iOS 16.4 app target and
  the v0.17.0-8 frameworks declare `MinimumOSVersion` 15.0, but nothing has
  been run on iOS 16.4. On a device, model load and generation have run only
  on an iPhone 16 Pro with iOS 18.3.2 (CPU and GPU); simulator evidence is
  iOS 26.4, CPU only. No other iOS version is device-verified
  ([#831](https://github.com/leehack/llamadart/issues/831)).
- iOS x86_64 simulator: no LiteRT-LM runtime is published. Apps that include
  LiteRT-LM must exclude the x86_64 simulator architecture; llama.cpp still
  builds for it.
- Linux x64 LiteRT-LM GPU needs a hardware Vulkan driver. On Mesa llvmpipe
  alone it answers a few prompts, then crashes the process; use `cpu` on such
  hosts ([#572](https://github.com/leehack/llamadart/issues/572)).
- Android LiteRT-LM on Adreno 750 (Galaxy S24): `ComputeDevice.auto`, the
  default, runs LiteRT-LM on the GPU, where Qwen3 0.6B loads without an error
  and generates wrong text. Load that model with
  `ModelParams(device: ComputeDevice.cpu)`, which answers correctly on the
  same device. The adapter's 128 MiB storage-buffer binding limit is smaller
  than one of the model's weight buffers, so expect the same from any model
  and adapter with that mismatch. The pinned `v0.17.0-8` does not fix it
  ([#553](https://github.com/leehack/llamadart/issues/553), upstream
  [LiteRT-LM#3866](https://github.com/google-ai-edge/LiteRT-LM/issues/3866)).
- Windows x64 LiteRT-LM GPU needs `litert-lm-native` `v0.17.0-6` or later,
  which bundles `dxil.dll` and `dxcompiler.dll`. The pinned runtime includes
  them.
- Android NPU depends on the device SoC, the `.litertlm` bundle and the LiteRT
  dispatch libraries (`ModelParams.liteRtLmDispatchLibDir`). If native
  LiteRT-LM cannot create an NPU engine, use `cpu` or `gpu`.
- Android llama.cpp Vulkan is experimental and device-dependent. `auto` runs
  llama.cpp on the CPU there; Vulkan runs only when the app asks for
  `ComputeDevice.gpu` or `GpuBackend.vulkan`. Known failures on the pinned
  runtime: on a Pixel 9 Pro (Mali-G715), a prompt longer than about 32 tokens
  evaluated in one batch returns wrong text, and a request with a grammar or
  tool call can then abort the process
  ([#948](https://github.com/leehack/llamadart/issues/948)); a Galaxy A53
  (Mali-G68) crashes while loading the model
  ([#782](https://github.com/leehack/llamadart/issues/782)); a Galaxy S24
  (Adreno 750) crashes on the first generation
  ([llamadart-native#79](https://github.com/leehack/llamadart-native/issues/79)).
  Keep `auto` or `cpu` on Android unless the app has validated Vulkan on its
  target devices.
- Some Vulkan drivers crash in the cooperative-matrix path; see
  [GPU crash or device loss](../troubleshooting/common-issues#gpu-crash-or-device-loss).
- WebGPU readiness depends on the browser, device, bridge assets and model
  size; see [WebGPU bridge](./webgpu-bridge).

## Pinned runtimes

| Runtime | Pinned release |
| --- | --- |
| llama.cpp native | `leehack/llamadart-native@v0.5.0-2` |
| LiteRT-LM native | `leehack/litert-lm-native@v0.17.0-8` |
| stable-diffusion.cpp native (opt-in, Preview) | `leehack/stable-diffusion-native@v0.2.0-1`, for [image generation](../guides/image-generation); see [Opt-in stable_diffusion runtime](./native-build-hooks#opt-in-stable_diffusion-runtime-experimental). Flutter iOS/macOS apps link its XCFramework through `llamadart_stable_diffusion_flutter` |
| WebGPU bridge assets | `leehack/llama-web-bridge-assets`; see [Pinned bridge assets](./webgpu-bridge#pinned-bridge-assets) |

The native-assets hook currently pins `llamadart-native` tag
`v0.5.0-2` and
`litert-lm-native` release `v0.17.0-8` (`lib/src/hook/native_release_pins.dart`).
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
