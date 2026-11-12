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

## Linux and Windows

- Linux x64 LiteRT-LM GPU needs a hardware Vulkan driver. On Mesa llvmpipe
  alone it answers a few prompts, then crashes the process; use `cpu` on such
  hosts ([#572](https://github.com/leehack/llamadart/issues/572)).
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
  failures: on a Pixel 9 Pro (Mali-G715), a prompt longer than about 32 tokens
  evaluated in one batch returns wrong text, and a request with a grammar or
  tool call can then abort the process, confirmed so far with one model
  (Qwen3.5-0.8B Q4_0) on that one device
  ([#948](https://github.com/leehack/llamadart/issues/948)); a Galaxy A35
  (Mali-G68) is reported to time out in `llama_decode`
  ([#1092](https://github.com/leehack/llamadart/issues/1092)); a Galaxy S24
  (Adreno 750) crashes on the first generation
  ([llamadart-native#79](https://github.com/leehack/llamadart-native/issues/79)).
  The first failure is associated with llama.cpp's subgroup-16 small-matmul
  tile ([llama.cpp#28637](https://github.com/ggml-org/llama.cpp/issues/28637)).
  The pinned native `v0.8.0-3` includes upstream
  [#30106](https://github.com/ggml-org/llama.cpp/pull/30106), but matched
  final-artifact Pixel/Qwen correctness remains unqualified. The historical
  GPU history failure repeated `8`; the original CPU result `Cedar17` also
  failed the exact expected `cedar17`. Neither observation is normalized away.

  For a model actually loaded with Vulkan GPU layers on Android, native
  architecture `qwen35` (Qwen3.5) is restricted when device facts report subgroup
  16, below 8, or are unavailable, empty or inconsistent with the registry.
  Ordinary text retains the eight-token prompt cap with `microBatchSize`
  unset; explicit `1..8` is accepted. Values above `8` throw
  `LlamaUnsupportedException` before context creation. Media (image/audio),
  every speculative strategy and embeddings throw before evaluation; vision,
  audio and embedding modality probes report unavailable, and generation
  capabilities report no speculative strategies. A refused generation leaves
  the text context reusable. Load with `ComputeDevice.cpu` for these features.
  Missing native architecture metadata on this otherwise restricted GPU path
  also throws because required safety cannot be established.

  The family-wide rule and refusal of sizes `9..32` are conservative admission
  limits, not reproduced failures for every Qwen3.5 artifact or batch size.
  `qwen35moe` and other known architectures are outside this rule. CPU and
  zero-GPU-layer loads, non-Android/non-Vulkan backends, and complete subgroup
  `8` or `>=32` facts retain their behavior; these exemptions do not constitute
  new hardware qualification. Other architectures retain the existing default
  text-only cap on unsafe/unproven subgroup facts; that cap is not protection
  for media, speculative verification, embeddings, decision models or TTS.
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
