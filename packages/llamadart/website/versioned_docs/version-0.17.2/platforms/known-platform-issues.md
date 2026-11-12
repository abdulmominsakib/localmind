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
  `webgpu_dawn.dll`, which the hook bundles. Qwen3 0.6B ran on an NVIDIA L4
  (Direct3D 12) through `dart run` and a `dart build cli` bundle; a Flutter
  Windows app has not been run with it.

## Android

- Android LiteRT-LM on Adreno 750 (Galaxy S24): `ComputeDevice.auto`, the
  default, runs LiteRT-LM on the GPU, which cannot run Qwen3 0.6B. The
  adapter's 128 MiB storage-buffer binding limit is smaller than one of the
  model's weight buffers, so expect the same from any model and adapter with
  that mismatch. GPU engine creation fails: on a Galaxy S24 the
  first use throws `LlamaUnsupportedException` when `ComputeDevice.gpu` was
  requested; `auto` retries on the CPU with a warning
  ([#1034](https://github.com/leehack/llamadart/issues/1034)). Gemma 4 E2B
  runs on that GPU. `ModelParams(device: ComputeDevice.cpu)` skips the GPU
  attempt and answers correctly on the same device (upstream
  [LiteRT-LM#3866](https://github.com/google-ai-edge/LiteRT-LM/issues/3866)).
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
  The first of these is a llama.cpp defect at a Vulkan subgroup size of 16
  ([llama.cpp#28637](https://github.com/ggml-org/llama.cpp/issues/28637)),
  last observed on llama.cpp `v0.6.0` and not re-checked on `v0.7.0`. The
  affected code also mis-tiles subgroup sizes below 8, which no device run
  has confirmed. On Android, llamadart reads the
  subgroup size of the Vulkan GPUs when it creates a context: on such a GPU,
  and on any GPU whose subgroup size it cannot read, the context decodes a
  text prompt in micro-batches of at most 8 tokens by default (`n_ubatch`
  itself is unchanged); on other GPUs
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
