---
title: How llamadart works
sidebar_label: Architecture
description: How llamadart layers one Dart API over llama.cpp and LiteRT-LM, with FFI bindings and worker isolates on native and JavaScript runtimes on the web.
---

`llamadart` exposes one Dart API (`LlamaEngine`, `ChatSession` and the typed
speech and decision engines) over two inference runtimes:

- **llama.cpp** runs GGUF models. It is built on **GGML**, a tensor library
  with CPU kernels (NEON, AVX) and GPU backends (Metal, Vulkan, CUDA and more).
- **LiteRT-LM** runs `.litertlm` bundles. See
  [Choosing llama.cpp or LiteRT-LM](./backend-selection).

## Architecture overview

import ArchitectureDiagram from '@site/src/components/ArchitectureDiagram';

<ArchitectureDiagram />

## Native targets

1. **Prebuilt runtimes.** During `flutter build` or `dart run`, the package's
   build hook downloads the prebuilt runtime bundles for the target platform
   from `llamadart-native` (llama.cpp) and `litert-lm-native` (LiteRT-LM), so
   apps never compile C++. See [Native build hooks](../platforms/native-build-hooks).
2. **FFI bindings.** Dart FFI calls the llama.cpp C API (`llama.h`, `mtmd.h`
   for multimodal input, and a thin `llamadart-native` wrapper) and the
   LiteRT-LM C API. llamadart does not use llama.cpp's `common` helpers: model loading with memory
   mapping (`ModelParams.useMmap`), tokenization and sampler chains are all
   libllama calls.
3. **Worker isolates.** Each backend runs native calls in a background
   isolate, so inference never blocks the UI isolate. Results stream back as
   Dart streams.
4. **Explicit lifecycle.** Models and contexts are native memory. Release them
   with `await engine.unloadModel()` and `await engine.dispose()`, typically in
   `try/finally`, instead of relying on garbage collection. See
   [Model lifecycle](./model-lifecycle).

## Web

On the web, the same Dart API talks to JavaScript runtimes through interop:

- GGUF models run in the [WebGPU bridge](../platforms/webgpu-bridge), a
  llama.cpp build for WebGPU with a CPU (WebAssembly) path.
- `.litertlm` models run through the official `@litert-lm/core` browser API.

Capabilities differ by runtime; the
[support matrix](../platforms/support-matrix) lists what each one supports.

## Chat templates

Chat template detection, rendering and output parsing are reimplemented in
Dart, in line with llama.cpp, so tool calling and reasoning parsing behave the
same on native and web. See
[Chat templates and output parsing](./chat-template-and-parsing).
