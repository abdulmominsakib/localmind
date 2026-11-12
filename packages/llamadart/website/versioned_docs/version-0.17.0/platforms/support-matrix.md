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

Desktop source-CLI diagnostics can opt into
`dart run llamadart:doctor_native --runtime llama_cpp --json` (or
`litert_lm` / `stable_diffusion`) to check a declared artifact in an isolated
process. It checks selected symbols/static ABI markers, without device or model
initialization. This adds no runtime/platform/model capability: production loader
behavior, loaded release identity, emitted app assets and GPU/inference remain
unchecked. See [scope and limits](./native-build-hooks#isolated-native-check).

| Platform | GGUF backends | LiteRT-LM backends | Minimum OS | Speech to text | Text to speech | Decision models | Image generation (Preview) | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Android (arm64, x64) | CPU; Vulkan experimental, device-dependent; OpenCL opt-in | CPU, GPU, NPU | Not set by llamadart | Qwen3-ASR (GGUF); LiteRT-LM ASR | Qwen3-TTS | Untested | arm64 CPU; validated on Pixel 9 Pro, Galaxy S24 and A53 | Supported |
| iOS (arm64, arm64 simulator, x86_64 simulator) | CPU, Metal; on a simulator Metal returns incorrect output and `auto` uses the CPU ([#950](https://github.com/leehack/llamadart/issues/950)) | CPU, GPU; none on the x86_64 simulator | iOS 16.4 deployment target; LiteRT-LM run on a device only on iOS 18.3.2 | Qwen3-ASR (GGUF); LiteRT-LM ASR | Qwen3-TTS | Untested | Metal, iOS 16.4; validated on iPhone 16 Pro and SE 3; `vaeDirectConvolution: true` throws on Metal ([#1044](https://github.com/leehack/llamadart/issues/1044)) | Supported |
| macOS (arm64, x86_64) | CPU, Metal | arm64: CPU, GPU; x86_64: none ([litert-lm-native#72](https://github.com/leehack/litert-lm-native/issues/72)) | macOS 14.0 (Flutter) | Qwen3-ASR (GGUF); LiteRT-LM ASR | Qwen3-TTS | Validated on Metal and CPU | Metal, macOS 13.3; validated on arm64 | Supported |
| Linux (arm64, x64) | CPU, Vulkan; BLAS opt-in; x64: CUDA, HIP opt-in | arm64: CPU; x64: CPU, explicit GPU | Not set by llamadart | Qwen3-ASR (GGUF); LiteRT-LM ASR | Qwen3-TTS | Untested | CPU or Vulkan; x64 needs AVX2; validated on x64 (CPU, NVIDIA L4) | Supported |
| Windows (arm64, x64) | CPU, Vulkan; BLAS opt-in; x64: CUDA opt-in | x64: CPU, explicit GPU; arm64: none | Not set by llamadart | Qwen3-ASR (GGUF); LiteRT-LM ASR on x64 | Qwen3-TTS | Untested | x64 CPU or Vulkan, needs AVX2 and the Visual C++ runtime; validated on Windows Server 2022 (CPU, NVIDIA L4) | Supported |
| Web | WebGPU, WebAssembly CPU | CPU, GPU through `@litert-lm/core` | Chrome 128, Firefox 129, Safari 17.4 | Qwen3-ASR, WAV, MP3 or FLAC bytes, bridge `v0.1.30+` | Qwen3-TTS, bridge `v0.1.33+`, memory64 | Bridge `v0.1.47+`; checked in headless Chromium on macOS | Not yet ([#780](https://github.com/leehack/llamadart/issues/780)) | Experimental |

On Windows, the llama.cpp and LiteRT-LM bundles ship the Visual C++ runtime
DLLs they need, so they need no Visual C++ Redistributable. The opt-in
`stable_diffusion` runtime does not ship them: machines that run it need the
latest Microsoft Visual C++ v14 Redistributable (x64), which stock Windows
Server lacks, and its load error names the DLLs that failed to load.

With the pinned bridge assets, Web speech-to-text and text-to-speech
cancellation is request-scoped, including queued STT generation and TTS startup
awaiting a capability probe. The local `web-speech-task-cancel` validation row
keeps direct/worker and CPU/Wasm versus hardware WebGPU evidence separate.

Speech to text, text to speech and decision models are experimental. Image
generation is a Preview: its API is experimental and may change, and it needs
the opt-in `stable_diffusion` runtime,
built for iOS 16.4 and macOS 13.3; x64 Linux and Windows CPUs need AVX2, FMA,
F16C and BMI2, Windows needs the latest Microsoft Visual C++ v14
Redistributable (x64), and Android arm64 needs dot-product and fp16. The
desktop models (SDXL-Lightning, FLUX.1-schnell, SD 3.5 Large Turbo,
Z-Image-Turbo) need about 8 to 15 GiB and are validated on macOS Metal; NVIDIA
Vulkan figures come from the native CLI. Opt-in VAE tiling
(`TiledImageGenerationRequest`) accepts header-verified SD 2.x checkpoints
with an embedded full VAE or TAESD on CPU/Metal. SD-Turbo is measured on macOS
CPU and actual Metal; other accepted SD 2.x checkpoints and phones are unmeasured.
Other families/backends, unknown decoder proof and circular-axis combinations
throw `LlamaUnsupportedException`. See
[Image generation](../guides/image-generation#support). GGUF
Qwen3-ASR accepts WAV, MP3 and FLAC; real-model checks cover all three on
native macOS and in headless Chromium. LiteRT-LM ASR is CPU-only streaming
recognition. Decision models run on llama.cpp and WebGPU only; on LiteRT-LM
`DecisionEngine.load` and `attach` throw `LlamaUnsupportedException`. See
[Speech to text](../guides/speech-to-text#choose-an-approach),
[Text to speech](../guides/text-to-speech) and
[Decision models](../guides/decision-models).

Image generation accepts compatible GGUF and Safetensors files directly,
including mixed-format components. Selected complete SD-Turbo F16 GGUF,
Safetensors and tensor-only PyTorch ZIP/nested ZIP/legacy checkpoints have
exact native/public CPU output controls on macOS arm64. PyTorch needs explicit
roles; other producer layouts/platforms remain unqualified. The opt-in
`ImageGenerationModel.localSafetensorsSet` accepts only the bounded complete
SD-Turbo F16/F32 checkpoint-index recipe on macOS CPU; arbitrary directories
and Diffusers component layouts are unsupported. See [Image weight formats and layouts](../guides/image-generation#weight-formats-and-layouts).
Container support does not extend the model/device qualification above.

FP8 image weights (`F8_E4M3`/`F8_E5M2` in Safetensors, types 43/44 in
GGUF) load on Metal with the pinned stable-diffusion-native `v0.3.0-1`, which
converts them to F16 there: they need twice their file size in memory, which
`ImageModelParams.checkMemory` counts. A runtime without that fix, told apart
by its exports, aborts on them instead
([#1446](https://github.com/leehack/llamadart/issues/1446)): with it, FP8
weights, uninspectable GGUF/Safetensors headers and ordinary JSON shard
indexes are refused with `LlamaUnsupportedException` on Metal, including
`ComputeDevice.auto` when it selects Metal, before native context creation;
use `ComputeDevice.cpu` there. FP8 re-encodings of SD-Turbo are measured on
macOS arm64 CPU and Metal; arbitrary FP8 models are not qualified.

Image prompt-conditioning reuse can be disabled or limited by entry count
with `ImageConditioningCacheParams(capacity: ...)`; ordinary settings preserve
four entries.
This option is qualified with SDXS and SD-Turbo on macOS arm64 CPU/Metal;
other image platforms and families have not been measured for this control.
It adds no Web image runtime or approximate sampling cache. See
[Conditioning cache](../guides/image-generation#conditioning-cache).

Image module placement (`ImageModelPlacement`: text encoders or VAE on the
CPU, `maxGpuMemoryGiB`, `autoFit`) applies to Metal and Vulkan engines and is
measured with SD-Turbo on macOS arm64 Metal and on one Linux x64 Vulkan Tesla
T4; multi-GPU hosts have no evidence yet. A CPU engine (Android, the CPU builds,
`ComputeDevice.cpu`) and the Web throw `LlamaUnsupportedException`, as does
`maxGpuMemoryGiB` on Vulkan without a discrete GPU. See
[Module placement](../guides/image-generation#module-placement-and-gpu-memory).

Image editing uses `ImageEditingRequest` with copied decoded RGB and optional
binary masks (255 edits, 0 preserves the latent). It is bounded to a single
SD 2.x checkpoint with embedded full VAE on macOS CPU and the pinned SD v0.3.0-1
runtime, with flash attention/direct VAE convolution off and no components,
tilings or circular axes. SD-Turbo is measured; matching other SD 2.x
checkpoints remain unmeasured. Other recipes report
`supportsImageEditing: false` and throw on an editing request. This does not
extend editing support to the other text-to-image platforms in the table.
See [image editing](../guides/image-generation#image-editing).

ControlNet uses `ControlNetImageGenerationRequest` with a copied, finished RGB
control map and a strength from 0 to 2. A ControlNet loads only as an SD 1.x
checkpoint with embedded full VAE plus an original-layout SD 1.x ControlNet on
macOS CPU with the pinned SD v0.3.0-1 runtime, flash attention/direct VAE
convolution off and no other components; other recipes throw at load. Qualified
on SD 1.5 with `control_v11p_sd15_canny` (fp16 Safetensors), and no other platform, family or ControlNet
layout is supported. See [ControlNet](../guides/image-generation#controlnet).

A hires fix uses `HiresFixImageGenerationRequest` with an `ImageHiresFix`:
a latent upscale to at most twice each side and 1024x1024, then a second
sampling pass. It is bounded to an SD 1.x or SD 2.x checkpoint with embedded
full VAE and no components on macOS CPU or Metal with the pinned SD
v0.3.0-1 runtime; SD 1.5 and SD-Turbo are measured. Other recipes report
`supportsHiresFix: false` and throw on a hires-fix request. See
[hires fix](../guides/image-generation#hires-fix).

Reference image editing uses `ReferenceImageEditingRequest` with
`ImageReferenceEditingRecipe.fluxKontext`: one RGB reference at the output
size, at most 1024x1024. It is bounded to the FLUX.1 Kontext [dev]
transformer with `ae`, CLIP-L and T5-XXL on macOS Metal with the pinned SD
v0.3.0-1 runtime. Other models, components, devices, platforms and reference
counts report `supportsReferenceImageEditing: false` or throw on the
request. See [reference image editing](../guides/image-generation#reference-image-editing).

Seamless textures use `SeamlessImageGenerationRequest` with independent X/Y
flags. The initial qualified profile is SDXS (512-DS), embedded tiny decoder,
512×512, flash attention and direct VAE convolutions disabled; CPU and actual
Metal were measured on macOS arm64. Other platforms are unmeasured, other GPUs
and model/decoder recipes are refused. See
[seamless textures](../guides/image-generation#seamless-textures).

## Compute device

`ModelParams.device` (`ComputeDevice`) applies to every runtime. `auto` keeps
each runtime's default; `cpu`, `gpu` and `npu` run there or throw
`LlamaUnsupportedException`, never on another device. See
[Choosing the device](../guides/backend-selection#choosing-the-device).

| Runtime | `auto` | `gpu` | `npu` |
| --- | --- | --- | --- |
| Native llama.cpp | Best GPU backend that loads, all layers; CPU without a GPU module or device, on Android and on an iOS simulator | Needs a GPU module and device; Vulkan on Android (experimental); Metal on an iOS simulator, where its output is incorrect | Throws |
| WebGPU (llama.cpp) | WebGPU when available, else the WebAssembly CPU runtime | Needs a WebGPU adapter and GPU layers after load; no CPU retry | Throws |
| Native LiteRT-LM | GPU on Android, iOS and macOS; CPU on Linux and Windows; a GPU engine that fails to start retries on the CPU with a warning | GPU backend on Android, iOS, macOS arm64, Linux x64 (Vulkan) and Windows x64 (Direct3D 12); a delegate that fails to start throws on first use | Android only |
| LiteRT-LM Web | WebGPU, without a probe | Needs a WebGPU adapter | Throws |
| Image generation | First GPU reported, else CPU | Needs a GPU; Android and the CPU builds have none | Throws |
| LiteRT-LM ASR | CPU | Not selectable | Not selectable |

The WebGPU bridge ignores negative `mainGpu` values, including with
`splitMode: ModelSplitMode.none`; they do not select the CPU as they do in
native llama.cpp. Explicit `gpu` still requires WebGPU after load.

Under `auto`, `gpuLayers: 0` or a CPU or BLAS `preferredBackend` selects the
CPU on both llama.cpp and LiteRT-LM, and a GPU `preferredBackend` (Vulkan,
Metal, CUDA, OpenCL or HIP) selects the LiteRT-LM GPU backend. On Linux x64
and Windows x64, the LiteRT-LM GPU backend is not CUDA; use `device: cpu` on
hosts without a hardware Vulkan driver. Windows arm64 has no LiteRT-LM
runtime. The deprecated `liteRtLmBackend` selector works until 1.0; an
unavailable choice there throws `LlamaModelException`.

`LlamaBackend()` rejects a LiteRT-LM model with `LlamaUnsupportedException`
before any download on macOS x86_64, Windows arm64 and the x86_64 iOS
simulator, which have no LiteRT-LM runtime, and for an explicit `device` the
platform's LiteRT-LM lacks, such as `gpu` on Linux arm64. The message names
the ABI. This applies when `ModelSource.format` or the file name says
`.litertlm`; a model known only from its file header is rejected when it
loads.

`await engine.checkLoad(model, params: params)` returns the same verdict as a
`LlamaLoadCheckReport` without downloading, reading a file or starting a
runtime: `unsupported` with the exception the load would throw, `deferred`
when only the file header can tell the format, `unknown` when the backend
cannot tell, as with `LlamaEngine(LiteRtLmBackend())`, and otherwise
`supported`, with the format, runtime and device the load would use. Like the
setup report, it is policy: native libraries, browser assets, `auto` device
selection, LoRA limits, download options and the file are checked by the load
([backend selection](../guides/backend-selection#check-a-load-before-it-runs)).

Dart-side chat-template rendering accepts Jinja `\xHH` string escapes on
native and web. Model architecture support depends on the pinned runtime; see
[chat templates](../guides/chat-template-and-parsing).

## Features by runtime

| Feature | Native llama.cpp | WebGPU | Native LiteRT-LM | LiteRT-LM Web |
| --- | --- | --- | --- | --- |
| Model-free setup report | Desktop IO only; publication policy, no native/model probe | Typed unsupported; no live browser check | Desktop IO only; publication policy, no native/model probe | Typed unsupported |
| Pre-load check | `npu` and options llama.cpp ignores rejected; native library and GPU unchecked | Options the Web runtime ignores rejected; WebGPU and bridge assets unchecked | No runtime on macOS x86_64, Windows arm64 or the x86_64 iOS simulator, and explicit devices the ABI lacks (`gpu` on Linux arm64), and embeddings off macOS arm64, iOS arm64 and Android arm64, rejected; `LlamaEngine(LiteRtLmBackend())` reports `unknown` | Options the Web runtime ignores, `npu` and the embedding engine rejected; browser runtime unchecked |
| LoRA | `ModelParams.loras` at load and `setLoraSource` at runtime, stacked and scaled; aLoRA rejected | Same, with bridge assets whose `getLoraAdapterCapabilities()` reports support ([llama-web-bridge#142](https://github.com/leehack/llama-web-bridge/pull/142)); otherwise rejected | One default-scale text adapter through `ModelParams.loras` at load | No |
| GPU device list and split (`gpuDevices`, `tensorSplit`) | Devices of one backend by `listGpuDevices` index, with proportions; validated on one Metal GPU and a Vulkan Tesla T4 (two-device paths with Mesa lavapipe as the second device); two-GPU hardware has no evidence and CUDA is not hardware-qualified ([#916](https://github.com/leehack/llamadart/issues/916)) | No | No | No |
| Renamed legacy Qwen3 thinking switch | N/A: GGUF metadata | N/A: GGUF metadata | `chatTemplate: liteRtLmQwen3ChatTemplate`; requires native template setter | Canonical override throws at load: no template setter in `@litert-lm/core@0.18.0` |
| Thinking budget | Text-only, without speculative decoding, when the native reasoning-budget export resolves | Text-only, with bridge assets whose `getCompletionCapabilities()` reports `thinkingBudget` ([llama-web-bridge#144](https://github.com/leehack/llama-web-bridge/pull/144)); otherwise rejected | Native chat, without speculative decoding, on bundles whose first response channel is a thinking channel (Gemma 4); bounds that channel only; `0` and `forcedMessage` rejected | No |
| Strict `responseFormat` | Yes | Yes, without tools | macOS arm64 CPU, admitted canonical Qwen3 text model; scalar object schema subset, thinking disabled, no tools/media/speculation/caller stops | No |
| Lazy grammar | Yes | No: `grammar` applies from the first token, from `root` | No GBNF grammar | No GBNF grammar |
| Presence penalty | Yes | With bridge assets whose `getCompletionCapabilities()` reports `presencePenalty` ([llama-web-bridge#140](https://github.com/leehack/llama-web-bridge/pull/140)); otherwise rejects a non-zero value | Yes, without speculative decoding; counts only tokens of the current send | No: rejects a non-zero value |
| Min-P | Yes | With bridge assets whose `getCompletionCapabilities()` reports `minP` ([llama-web-bridge#140](https://github.com/leehack/llama-web-bridge/pull/140)); otherwise rejects a non-zero value | No: rejects a non-zero value | No: rejects a non-zero value |
| Repetition `penalty` | Yes | Yes | A value other than the default, at least `1.0`, without speculative decoding; counts only tokens of the current send | No: rejects a value other than the default |
| Speculative decoding | Draft model, MTP, n-gram and DSpark strategies; external drafts require `draftModel`, in-file MTP requires an MTP head and `loadMtp`; `draftMicroBatchSize` sizes the draft context; recurrent/hybrid models reject nonzero rollback capacity | Same, with bridge assets whose `getCompletionCapabilities()` reports the strategy ([llama-web-bridge#153](https://github.com/leehack/llama-web-bridge/pull/153)); draft and n-gram cache paths are URLs, MTP uses the model's own layers, and `draftMicroBatchSize` is rejected; otherwise rejected | Runtime default or MTP, for bundles with a speculative drafter; `capabilities` reports the bundle's declaration | No |
| MoE expert placement and cache | `cpuMoeLayers` keeps experts in host memory; `moeCacheBytes` caches them on Metal and CUDA GPUs (qualified on Metal with OLMoE; CUDA has no hardware evidence); only `moeCacheBytes` throws `LlamaUnsupportedException` on Vulkan, other backends and tensor split, while `cpuMoeLayers` alone runs there | No | No | No |
| State persistence | Yes | Bridge `v0.1.15+`; WASMFS paths, lost on page reload | No | No |
| State identity (`stateIdentity`) | `llamadart-native` `v0.7.0-3+` | No: the bridge reports no build identity | No | No |
| Embeddings | Yes; one-pass attention and MEAN/CLS inputs must fit the physical micro-batch | Bridge `v0.1.7+`; `v0.1.73+` rejects rerankers and over-long one-pass input as native does | CPU, explicit embedding engine; macOS arm64 and iOS arm64 qualified; Android arm64 verified on a Galaxy S24 without SME and on arm64 emulators; other platforms throw `LlamaUnsupportedException` at load ([#1367](https://github.com/leehack/llamadart/issues/1367)) | Unsupported (parity gate) |
| Reranking | Rank-pooled GGUF only; explicit loaded-context probe, complete-pair limits and independent sequence batching | No | No | No |
| Text task helpers and Matryoshka | Opt-in EG2 text profile; CPU BF16 retrieval reference | Same Dart helpers on an available embedding engine; no new Web qualification | Same Dart helpers on an available CPU embedding engine; bundle requires independent retrieval qualification | Unsupported with the underlying embedding engine |
| Image/audio embeddings (`embedContent`) | EmbeddingGemma-2 + compatible projector, native v0.7.0-1; one complete micro-batch (BF16 qualified on CPU on macOS arm64, Linux x64, Windows x64, Android and iOS, and on macOS Metal; other GPU backends unqualified) | Bridge `v0.1.64+`, explicit API-version-1 modality probe + compatible projector; EmbeddingGemma-2 qualified Chrome CPU wasm memory64 vs native CPU/Metal; repeated media batches qualified only on memory64 (assets `v0.1.76+` remove the projector copy behind the wasm32 abort, unqualified); hardware WebGPU unqualified (default pinned assets include the API) | CPU; bundle processors on macOS arm64, iOS arm64 and Android arm64 (Galaxy S24 and emulators) | Unsupported (parity gate) |
| Next-token scores | Yes | Bridge `v0.1.52+` | No | No |
| Generation-limit reporting | `length` for output or context limits | `length` with bridge usage probe (`v0.1.54+`); cap cause unspecified | `length` for output or context limits on runtimes whose finish-reason ABI is 1 (`v0.18.0-3`+, default pin included); older runtimes report `stop` | No |
| Per-request usage | `usage` on the final `create` chunk | Bridge `v0.1.54+` | No | No ([#725](https://github.com/leehack/llamadart/issues/725)) |
| Operation observers | Yes; after a load, `runtime` is `llamaCpp` | Yes; after a load, `runtime` is `llamaCpp` | Yes; after a load, `runtime` is `liteRtLm` | Yes; after a load, `runtime` is `liteRtLm` |
| Multi-turn `ChatSession` | Yes | Yes | Yes | `LlamaBackend.withTextHistory()` or `LiteRtLmBackend.withTextHistory()` (existing defaults retain single-user-text): system/user/assistant text when the loaded runtime consumes `preface` and exposes `getHistory()` (`@litert-lm/core@0.18.0`); final user message required; model/browser qualification is separate |
| Deterministic session template time | `TemplateTimeChatSession`, Dart-rendered templates | Same Dart template path | Dart-side rendering only; runtime-owned template clock unchanged | No: runtime-owned clock; explicit template time rejected |
| Tool calling | Yes | Yes | Yes | No: tool declarations and tool messages throw |
| Canonical JSON Schema tools | Supported subset and selected formats | Non-lazy grammars only; other combinations rejected | No | No |
| Automatic `sendWithTools` / `completeWithTools` loop | Yes | Requires reliable runtime finish reporting | Yes on runtimes whose finish-reason ABI is 1 (`v0.18.0-3`+, default pin included); older runtimes throw before generation | No: pinned runtime has no reliable termination cause; throws before generation |
| Multimodal | Image and audio with a projector | Image and audio with a projector URL | Image and audio files or bytes, when the bundle supports them | No |
| Video | No | No | No | No |
| Tool-result media | Images with a vision projector and a Hermes-style template (smoke-tested on macOS CPU and Metal with Qwen3.5-0.8B weights, a `qwen3vl_merger` projector and the Qwen3-VL template) | No | No | No |

Tool-result media are `LlamaToolResultContent.content` parts;
`LlamaEngineCapabilities.toolResultMedia` reports them. Other formats, audio,
video and URL-only images throw `LlamaUnsupportedException`, as do tool-role
image/audio parts and media alongside `LlamaToolResultContent` under any role
([tool-result media](../guides/tool-calling#tool-result-media)).

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

- Native LiteRT-LM v0.18.0 iOS artifacts omit the Gemma FST constraint
  provider. Gemma 3/4 and FunctionGemma conversations must disable constrained
  decoding; Dart already does so. Ordinary generation, thinking and best-effort
  tool formatting remain available. Automatic tool loops and strict structured
  output remain unsupported.
- Native LiteRT-LM on iOS: iOS 16.4 is the declared deployment floor, not a
  tested one. The companion Swift package requires an iOS 16.4 app target and
  the v0.18.0 frameworks declare `MinimumOSVersion` 15.0, but nothing has
  been run on iOS 16.4. On a device, model load and generation have run only
  on an iPhone 16 Pro with iOS 18.3.2 (CPU and GPU); simulator evidence is
  iOS 26.4, CPU only. No other iOS version is device-verified
  ([#831](https://github.com/leehack/llamadart/issues/831)).
- Flutter macOS LiteRT-LM needs a `llamadart_litert_lm_flutter` that matches
  the core to put the runtime in the app bundle. With llamadart `0.12.0` and
  earlier, with companion `0.0.14` or earlier, or without the companion, an
  unsandboxed app run on the build machine from the project loads the runtime
  from the hook cache, and a sandboxed (the `flutter create` default), copied
  or distributed app throws `Failed to load dynamic library 'libCLiteRTLM_mac.dylib'`
  (`'libLiteRtMetalAccelerator.dylib'` with llamadart `0.12.0` and a newer
  companion) on the first CPU or GPU generation. Add the companion, or the
  [LiteRT-LM build phase](../getting-started/installation#flutter-macos-litert-lm-build-phase)
  ([#1029](https://github.com/leehack/llamadart/issues/1029)).
- macOS x86_64: no LiteRT-LM runtime is published
  ([litert-lm-native#72](https://github.com/leehack/litert-lm-native/issues/72)).
  Universal apps launch on an Intel Mac and under Rosetta, and LiteRT-LM
  throws `LlamaUnsupportedException` there; llama.cpp still runs. See
  [Intel Macs](../getting-started/installation#intel-macs).
- iOS x86_64 simulator: no LiteRT-LM runtime is published. Apps that include
  LiteRT-LM must exclude the x86_64 simulator architecture; llama.cpp still
  builds for it. LiteRT-LM throws `LlamaUnsupportedException` there.
- iOS simulator: llama.cpp on Metal returns incorrect output. On an arm64
  simulator (iPhone 17 Pro, iOS 26.5, Apple silicon host) Qwen3.5 0.8B
  (`Q4_K_M`) generates garbage text on Metal and answers correctly on the
  CPU, and Qwen2.5 0.5B fails on Metal the same way
  ([#950](https://github.com/leehack/llamadart/issues/950)); the cause is
  not known. On an iOS simulator `auto` therefore runs llama.cpp on the CPU
  with 0 GPU layers. `GpuBackend.metal` and `ComputeDevice.gpu` still load on
  Metal there, and the load logs a warning: use them only to check a model
  on the simulator's Metal device. Under `ComputeDevice.auto`, another
  explicit GPU backend, such as `GpuBackend.vulkan`, also loads its GPU
  layers on Metal and warns, since the Apple runtime has no other GPU
  backend. The x86_64 (Rosetta) simulator behaves the same. iOS devices and
  macOS are unchanged: `auto` uses Metal, and on an iPhone 16 Pro its output
  matches the CPU's.
- Linux x64 LiteRT-LM GPU needs a hardware Vulkan driver. On Mesa llvmpipe
  alone it answers a few prompts, then crashes the process; use `cpu` on such
  hosts ([#572](https://github.com/leehack/llamadart/issues/572)).
- Android LiteRT-LM on Adreno 750 (Galaxy S24): `ComputeDevice.auto`, the
  default, runs LiteRT-LM on the GPU, which cannot run Qwen3 0.6B. The
  adapter's 128 MiB storage-buffer binding limit is smaller than one of the
  model's weight buffers, so expect the same from any model and adapter with
  that mismatch. `v0.17.0-8` and earlier generated wrong text there. With the
  native `v0.18.0` GPU engine creation fails instead: on a Galaxy S24 the
  first use throws `LlamaUnsupportedException` when `ComputeDevice.gpu` was
  requested; from 0.17.0 `auto` retries on the CPU with a warning instead of
  throwing `LlamaModelException`
  ([#1034](https://github.com/leehack/llamadart/issues/1034)). Gemma 4 E2B
  runs on that GPU. `ModelParams(device: ComputeDevice.cpu)` skips the GPU
  attempt and answers correctly on the same device
  ([#553](https://github.com/leehack/llamadart/issues/553), upstream
  [LiteRT-LM#3866](https://github.com/google-ai-edge/LiteRT-LM/issues/3866)).
- Windows x64 LiteRT-LM GPU needs `litert-lm-native` `v0.17.0-6` or later,
  which bundles `dxil.dll` and `dxcompiler.dll`. The pinned runtime includes
  them. The `v0.18.0` GPU accelerator and sampler load
  `webgpu_dawn.dll`, which the hook bundles. Qwen3 0.6B ran on an NVIDIA L4
  (Direct3D 12) through `dart run` and a `dart build cli` bundle; a Flutter
  Windows app has not been run with it.
- Android NPU depends on the device SoC, the `.litertlm` bundle and the LiteRT
  dispatch libraries (`LiteRtLmModelParams.dispatchLibDir`). If native
  LiteRT-LM cannot create an NPU engine, use `cpu` or `gpu`.
- Android llama.cpp Vulkan is experimental and device-dependent. `auto` runs
  llama.cpp on the CPU there; Vulkan runs only when the app asks for
  `ComputeDevice.gpu` or `GpuBackend.vulkan`. Previously observed runtime
  failures: on a Pixel 9 Pro (Mali-G715), a prompt longer than about 32 tokens
  evaluated in one batch returns wrong text, and a request with a grammar or
  tool call can then abort the process, confirmed so far with one model
  (Qwen3.5-0.8B Q4_0) on that one device
  ([#948](https://github.com/leehack/llamadart/issues/948)); a Galaxy A53
  (Mali-G68) crashes while loading the model
  ([#782](https://github.com/leehack/llamadart/issues/782)); a Galaxy S24
  (Adreno 750) crashes on the first generation
  ([llamadart-native#79](https://github.com/leehack/llamadart-native/issues/79)).
  The first of these is a llama.cpp defect at a Vulkan subgroup size of 16
  ([llama.cpp#28637](https://github.com/ggml-org/llama.cpp/issues/28637)),
  last observed on llama.cpp `v0.6.0` and not re-checked on `v0.7.0`. The
  affected code also mis-tiles subgroup sizes below 8, which no device run
  has confirmed. On Android, llamadart reads the
  subgroup size of the Vulkan GPUs when it creates a context: on such a GPU,
  and on any GPU whose subgroup size it cannot read, the context decodes a
  text prompt in micro-batches of at most 8 tokens by default; on other GPUs
  it decodes the prompt in full micro-batches. On a Pixel 9 Pro, prompt
  evaluation with 8-token micro-batches ran at about the speed uncapped
  decoding did (about 34 tokens/s against about 30 tokens/s for a 59-token
  prompt); other GPUs are not measured. An app that has validated Vulkan on
  its target devices can set
  `ModelParams.microBatchSize` to choose the micro-batch size itself: an
  explicit value is used as given, and one above 32 brings the wrong text
  back on affected GPUs. The cap applies to
  text-prompt decoding only: it does not cover prompts with image or audio
  input, embeddings, decision models, text-to-speech, or speculative-decoding
  verification batches during generation. Those batches can exceed 32 tokens,
  so speculative decoding can still produce wrong output on an affected GPU.
  llama.cpp's Vulkan backend also needs Vulkan 1.2 from the Vulkan loader and
  the GPU driver. When the Vulkan GPU a load would run on reports an older
  version, `ComputeDevice.gpu` throws `LlamaUnsupportedException` naming the
  GPU and both versions, and `ComputeDevice.auto` loads the model on the CPU
  and logs a warning. A device that used to run Vulkan on a 1.1 driver now
  takes that path. When other GPUs of the load are usable, such as a
  discrete GPU beside an old one, the load leaves the old one out and logs a
  warning; a GPU llama.cpp would not select, like an integrated GPU beside a
  discrete one, changes nothing. Whether this is what crashes the Galaxy A53
  is not confirmed.
  On Android, the exact Qualcomm vendor `0x5143`, `Adreno (TM) 750`
  driver `2150604839` has shader-compiler crashes and incorrect quantized
  results, including common `Q4_K_M` models. When this device is registered,
  GPU loads are refused even if another GPU was selected: projector and
  decision-head GPU selection can independently choose the affected device.
  `ComputeDevice.auto` loads on CPU with a warning, including when
  `preferredBackend` requests Vulkan; `ComputeDevice.gpu` throws
  `LlamaUnsupportedException`. CPU loads do not probe Vulkan. Detection needs
  the device-facts API in native `v0.6.0-1` or later; an overridden runtime
  without it cannot enforce this guard. Other driver versions are unchanged.
  A shader crash workaround alone does not qualify this driver; re-enabling
  a model requires qualification of the final native artifact on that exact
  driver.
  See [native issue #79](https://github.com/leehack/llamadart-native/issues/79).

  Keep `auto` or `cpu` on Android unless the app has validated Vulkan on its
  target devices.
- Some Vulkan drivers crash in the cooperative-matrix path; see
  [GPU crash or device loss](../troubleshooting/common-issues#gpu-crash-or-device-loss).
- WebGPU readiness depends on the browser, device, bridge assets and model
  size; see [WebGPU bridge](./webgpu-bridge).

## Pinned runtimes

| Runtime | Pinned release |
| --- | --- |
| llama.cpp native | `leehack/llamadart-native@v0.7.0-3` |
| LiteRT-LM native | `leehack/litert-lm-native@v0.18.1-4` |
| stable-diffusion.cpp native (opt-in, Preview) | `leehack/stable-diffusion-native@v0.3.0-1`, for [image generation](../guides/image-generation); see [Opt-in stable_diffusion runtime](./native-build-hooks#opt-in-stable_diffusion-runtime-experimental). Flutter iOS/macOS apps link its XCFramework through `llamadart_stable_diffusion_flutter` |
| WebGPU bridge assets | `leehack/llama-web-bridge-assets`; see [Pinned bridge assets](./webgpu-bridge#pinned-bridge-assets) |

The native-assets hook currently pins `llamadart-native` tag
`v0.7.0-3` and
`litert-lm-native` release `v0.18.1-2` (`lib/src/hook/native_release_pins.dart`).
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


Local checkpoint sets require per-file expected SHA-256 identities including
the index, an app-private owned cache, pinned SD v0.3.0-1, and explicit flash
attention/direct VAE convolution off. They report
`supportsLocalSafetensorsSets` after admission. This text-to-image recipe does
not enable editing, tiling or seamless combinations. See
[the set contract](../guides/image-generation#local-checkpoint-sets).
