---
title: Glossary
description: The terms llamadart docs use for runtime, backend module, device, companion, engine and LlamaBackend, and how they relate.
---

The docs use these words in one sense each.

| Term | Meaning |
| --- | --- |
| Runtime | The inference library that runs a model: llama.cpp (GGUF), LiteRT-LM (`.litertlm`) or stable-diffusion.cpp (image generation). On the web, llama.cpp runs through the WebGPU bridge and LiteRT-LM through `@litert-lm/core`. `engine.runtime` reports `LlamaRuntime.llamaCpp` or `LlamaRuntime.liteRtLm` for a loaded model. |
| Backend module | A compute module inside a runtime, such as the llama.cpp ggml CPU, Metal, Vulkan, CUDA, OpenCL, HIP or BLAS modules. `ModelParams.preferredBackend` (`GpuBackend`) picks one, and the build hook's `llamadart_native_backends` key picks which modules an app bundles. |
| Device | The hardware class a model runs on: `ComputeDevice.auto`, `cpu`, `gpu` or `npu`. An explicit value is a requirement, not a hint. A GPU device is served by a backend module. |
| Companion | An Apple Swift Package Manager (SwiftPM) package, such as `llamadart_llama_cpp_flutter`, that links a runtime into Flutter iOS and macOS apps. Companions use the core's `MAJOR.MINOR`. See [Apple setup](../platforms/apple-setup). |
| Engine | A Dart class that loads a model and runs one kind of task: `LlamaEngine` (text), `ImageGenerationEngine`, `SpeechToTextEngine`, `TextToSpeechEngine` and `DecisionEngine`. `ChatSession`, `LlamaTextEmbedder` and `LlamaReranker` wrap a `LlamaEngine`. |
| `LlamaBackend` | The Dart interface an engine calls to reach a runtime. `LlamaBackend()` returns the implementation for the current platform. Apps rarely touch it; see [API levels](./api-levels). |

How they fit: an engine calls a `LlamaBackend`, which drives a runtime; a
runtime that supports it runs the model on a device through a backend module.
[How llamadart works](./architecture) shows the layers.
