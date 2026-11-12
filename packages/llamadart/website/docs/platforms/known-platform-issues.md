---
title: Known platform issues
description: Device, OS and driver limits of the llama.cpp and LiteRT-LM runtimes on iOS, macOS, Android, Linux, Windows and the web, with their workarounds.
---

Limits that depend on the device, OS version or driver rather than on the
feature. For which runtime supports which feature, see the
[support matrix](./support-matrix#features-by-runtime).

## Apple platforms

- Native LiteRT-LM iOS artifacts omit the Gemma FST constraint
  provider. Gemma 3/4 and FunctionGemma conversations must disable constrained
  decoding; Dart already does so. Ordinary generation, thinking and best-effort
  tool formatting remain available. Automatic tool loops and strict structured
  output remain unsupported.
- Native LiteRT-LM on iOS: iOS 16.4 is the declared deployment floor, not a
  tested one. The companion Swift package requires an iOS 16.4 app target, but
  nothing has been run on iOS 16.4. On a device, model load and generation have run only
  on an iPhone 16 Pro with iOS 18.3.2 (CPU and GPU); simulator evidence is
  iOS 26.4, CPU only. No other iOS version is device-verified
  ([#514](https://github.com/leehack/llamadart/issues/514)).
- Flutter macOS LiteRT-LM needs `llamadart_litert_lm_flutter` to put the runtime
  in the app bundle. Without it, an unsandboxed app run on the build machine
  from the project loads the runtime from the hook cache, and a sandboxed (the
  `flutter create` default), copied or distributed app throws
  `Failed to load dynamic library 'libCLiteRTLM_mac.dylib'` on the first CPU or
  GPU generation. Add the companion, or the
  [LiteRT-LM build phase](./apple-setup#flutter-macos-litert-lm-build-phase).
- macOS x86_64: no LiteRT-LM runtime is published
  ([litert-lm-native#72](https://github.com/leehack/litert-lm-native/issues/72)).
  Universal apps launch on an Intel Mac and under Rosetta, and LiteRT-LM
  throws `LlamaUnsupportedException` there; llama.cpp still runs. See
  [Intel Macs](./apple-setup#intel-macs).
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
  Apple silicon macOS are unchanged: `auto` uses Metal, and on an iPhone 16
  Pro its output matches the CPU's. Intel macOS differs: see the next entry.
- macOS x86_64: upstream llama.cpp Metal returns garbled output on Intel Macs
  with AMD GPUs
  ([llama.cpp#30702](https://github.com/ggml-org/llama.cpp/issues/30702)),
  and upstream's own macOS x64 builds turn Metal off. In an x86_64 process,
  `auto` therefore runs llama.cpp on the CPU with 0 GPU layers ([#1597](https://github.com/leehack/llamadart/issues/1597)).
  An x86_64 process cannot tell an Intel Mac from Rosetta on Apple silicon,
  so a Rosetta process also uses the CPU. `GpuBackend.metal` and
  `ComputeDevice.gpu` still load on Metal, and the load logs a warning. Under
  `ComputeDevice.auto`, another explicit GPU backend, such as
  `GpuBackend.vulkan`, also loads its GPU layers on Metal and warns, since the
  Apple runtime has no other GPU backend. `gpuDevices` and `tensorSplit` need one of them there, since `auto` would
  load on the CPU. arm64 macOS is unchanged.
- macOS x86_64 image generation: stable-diffusion.cpp also runs on ggml-metal,
  so in an x86_64 process, Rosetta included, `ComputeDevice.auto` loads image
  models on the CPU ([#1600](https://github.com/leehack/llamadart/issues/1600)).
  `ComputeDevice.gpu` still loads on Metal and logs a warning. Placement
  options (`textEncoderOnCpu`, `vaeOnCpu`, `maxGpuMemoryGiB`,
  `autoFit: false`) need an explicit `ComputeDevice.gpu` there, and reference
  images for editing run on the CPU under `auto`. Whether Metal
  output is correct for stable-diffusion.cpp on Intel Macs with AMD GPUs is
  unchecked for lack of hardware.

## Linux and Windows

- A custom LiteRT-LM runtime (`LLAMADART_LITERT_LM_LIB_DIR`) on Linux or
  Windows must be litert-lm-native `v0.19.1-1` or later, and `v0.19.1-2` or
  later for embeddings. Earlier desktop runtimes link a prebuilt LiteRT built
  with a different C++ runtime: CPU embedding engine creation fails on Linux
  and crashes on Windows x64
  ([#1367](https://github.com/leehack/llamadart/issues/1367)), and `v0.19.0`
  and `v0.19.1` explicit GPU generation crashes at the first decode on Linux
  x64 and Windows x64 ([#1795](https://github.com/leehack/llamadart/issues/1795)).
  Embeddings need a runtime whose
  `litert_lm_native_in_process_litert_abi_version` export reports 1, first
  shipped in `v0.19.1-2`; any other runtime, including `v0.18.x`, `v0.19.0`,
  `v0.19.1` and `v0.19.1-1`, is refused before any native embedding call,
  though `checkLoad`, which opens no runtime, reports it as supported. GPU
  generation is not gated: the marker does not establish GPU support, and
  `v0.19.0` and `v0.19.1` expose the same C API 1.0 as later runtimes.
- Linux x64 LiteRT-LM GPU needs a hardware Vulkan driver. When every Vulkan
  device is a software rasterizer (Mesa llvmpipe/lavapipe, SwiftShader), an
  explicit GPU load throws `LlamaUnsupportedException` and a GPU hint under
  `auto` runs on the CPU with a warning, because small models can run there
  and return wrong text. `checkLoad`, which opens no driver, still reports
  such a GPU load as supported, and if the system Vulkan loader cannot be
  queried the load proceeds ([#572](https://github.com/leehack/llamadart/issues/572)).
- Windows x64 LiteRT-LM GPU needs `dxil.dll` and `dxcompiler.dll`, which the
  pinned runtime bundles. Its GPU accelerator and sampler load
  `webgpu_dawn.dll`, which the hook bundles. Windows Qwen3 0.6B GPU execution
  remains unqualified: the retained Windows Server 2022 / NVIDIA L4-vWS run
  on `v0.17.0-7` emitted 24 Dawn validation errors despite passing all 15
  functional checks. Conflicting storage usages and invalid command submissions
  remain unresolved; a new runtime regression has not been established
  ([litert-lm-native#64](https://github.com/leehack/litert-lm-native/issues/64)).
  Use `ComputeDevice.cpu` to avoid this GPU path. A Flutter Windows app has not
  been run with it.

## Android

- Android LiteRT-LM needs the app's optional vendor OpenCL manifest request
  when targeting API 31+ on Android 12+; see [Android setup](../getting-started/installation#android-litert-lm-setup).
  Without accessible OpenCL, the runtime can try WebGPU. On Adreno 750
  (Galaxy S24), WebGPU's 128 MiB storage-buffer binding limit rejects a
  larger Qwen3 weight buffer. `ComputeDevice.gpu` fails on GPU creation;
  `auto` retries on the CPU with a warning
  ([#1034](https://github.com/leehack/llamadart/issues/1034)). The legacy
  Qwen3 FP32 artifact's four semantic failures remain unqualified under
  [litert-lm-native#51](https://github.com/leehack/litert-lm-native/issues/51).
  Published native v0.19.0 has accepted corrected-model default-service OpenCL
  evidence only for SC-51E / API36 / DEBUG: all 20 cases, six closed lifetimes,
  final completion and eight full-graph placement proofs, including corrected
  C04, cancellation and reload. Fifteen exact sidecars were forensically
  extracted from the retained generation-bound journal; they were not
  independently downloaded, and the original collector FAIL is unchanged.
  This qualifies that scoped public route, not every Qwen artifact, device or
  release profile. Final source-adoption consumers remain
  [#1677](https://github.com/leehack/llamadart/issues/1677).
  `ModelParams(device: ComputeDevice.cpu)` skips the GPU attempt. Gemma 4
  E2B has separate GPU evidence; it does not qualify Qwen3.
- Android NPU depends on the device SoC, the `.litertlm` bundle and the LiteRT
  dispatch libraries (`LiteRtLmModelParams.dispatchLibDir`). If native
  LiteRT-LM cannot create an NPU engine, use `cpu` or `gpu`.
- Android llama.cpp Vulkan is experimental and device-dependent. `auto` runs
  llama.cpp on the CPU there; Vulkan runs only when the app asks for
  `ComputeDevice.gpu` or `GpuBackend.vulkan`. Previously observed runtime
  failures: a Galaxy A35 (Mali-G68) is reported to time out in `llama_decode`
  ([#1092](https://github.com/leehack/llamadart/issues/1092)); a Galaxy S24
  (Adreno 750) crashes on the first generation
  ([llamadart-native#79](https://github.com/leehack/llamadart-native/issues/79)).

  Before ggml `0.28.0` (llamadart-native `v0.8.0`), llama.cpp's Vulkan
  small-matmul tile gave wrong results for micro-batches above 32 tokens on
  GPUs with a subgroup size below 32 other than 8
  ([llama.cpp#28637](https://github.com/ggml-org/llama.cpp/issues/28637),
  fixed by [#30106](https://github.com/ggml-org/llama.cpp/pull/30106)). On a
  Pixel 9 Pro (Mali-G715), Qwen3.5-0.8B Q4_0 answered long prompts with
  repeated `8`, and a grammar or tool request could abort the process
  ([#948](https://github.com/leehack/llamadart/issues/948)). With the bundled
  runtime, the same model on Vulkan returned exactly the CPU's text on a Pixel
  9 Pro, a Pixel 9 (Mali-G715) and a Pixel 7 (Mali-G710): prompts at
  micro-batch 32 and 512, grammar and tool calls, image prompts, speculative
  verify batches above 32 tokens, and cancel, reuse and reload. Embeddings
  matched the CPU to a cosine similarity of at least 0.9997.
  Other GPUs and other Qwen3.5 sizes or quantizations were not measured, and
  Vulkan was slower than the CPU on all three phones. On those GPUs (subgroup
  size below 32 other than 8, or unknown facts), a Qwen3.5 projector, or one
  whose model architecture is unreadable, runs its image encoder on the CPU
  while the model stays on Vulkan: the encoder on Vulkan is not validated.
  Qwen3.5-0.8B files keep their projector on the CPU on every Android GPU.

  With `microBatchSize` unset, Android Vulkan evaluates text prompts eight
  tokens per call when the GPU reports a subgroup size below 32 other than 8,
  or its facts are unavailable, empty or inconsistent with the registry. This
  is a speed default: on the Pixel 9 Pro, prompt evaluation ran at about 44
  tokens/s capped and 27-29 tokens/s at 32 or 512. Set `microBatchSize` to
  lift it.

  A llama.cpp runtime older than ggml `0.28.0`, from a native release
  override or a custom build, keeps the earlier restriction. llamadart reads
  the version from `ggml_version()`; a runtime that does not export it counts
  as older. For a model actually loaded with Vulkan GPU layers on such a GPU
  whose native architecture is `qwen35`, `microBatchSize` above `8` throws
  `LlamaUnsupportedException` before context creation, and media, speculation
  and embeddings throw before evaluation. Vision, audio and embedding probes
  report them unavailable, generation capabilities report no speculative
  strategies, and missing architecture metadata also throws. Other models
  keep only the prompt cap there, which does not protect media, speculative
  verification, embeddings, decision models or TTS. Use the bundled runtime
  or `ComputeDevice.cpu`.
  llama.cpp's Vulkan backend also needs Vulkan 1.2 from the Vulkan loader and
  the GPU driver. When the Vulkan GPU a load would run on reports an older
  version, `ComputeDevice.gpu` throws `LlamaUnsupportedException` naming the
  GPU and both versions, and `ComputeDevice.auto` loads the model on the CPU
  and logs a warning. A device with a Vulkan 1.1 driver takes that path. When other GPUs of the load are usable, such as a
  discrete GPU beside an old one, the load leaves the old one out and logs a
  warning; a GPU llama.cpp would not select, like an integrated GPU beside a
  discrete one, changes nothing.
  On Android, the exact Qualcomm vendor `0x5143`, `Adreno (TM) 750`
  driver `2150604839` has shader-compiler crashes and incorrect quantized
  results, including common `Q4_K_M` models. When this device is registered,
  GPU loads are refused even if another GPU was selected: projector and
  decision-head GPU selection can independently choose the affected device.
  `ComputeDevice.auto` loads on CPU with a warning, including when
  `preferredBackend` requests Vulkan; `ComputeDevice.gpu` throws
  `LlamaUnsupportedException`. CPU loads do not probe Vulkan. Other driver
  versions are unchanged.
  A shader crash workaround alone does not qualify this driver; re-enabling
  a model requires qualification of the final native artifact on that exact
  driver.
  See [native issue #79](https://github.com/leehack/llamadart-native/issues/79).

  Keep `auto` or `cpu` on Android unless the app has validated Vulkan on its
  target devices.

## Vulkan and the web

- Some Vulkan drivers crash in the cooperative-matrix path; see
  [GPU crash or device loss](../troubleshooting/common-issues#gpu-crash-or-device-loss).
- WebGPU readiness depends on the browser, device, bridge assets and model
  size; see [WebGPU bridge](./webgpu-bridge).
- Safari terminates a hidden or background tab that exceeds its inactive
  memory limit. Loading Gemma 4 E2B through LiteRT-LM Web peaks near 7 GB, so
  keep the tab visible until the model finishes loading
  ([#1025](https://github.com/leehack/llamadart/issues/1025)).
- Browsers without WebAssembly relaxed SIMD, including Safari 27, run
  LiteRT-LM Web on CPU through the runtime's compat build, which can generate
  different tokens from Chrome's. With Qwen3 0.6B and default thinking, a
  multi-turn reply can spend the whole `maxTokens` budget thinking and return
  no text where Chrome answers
  ([#1802](https://github.com/leehack/llamadart/issues/1802)).
