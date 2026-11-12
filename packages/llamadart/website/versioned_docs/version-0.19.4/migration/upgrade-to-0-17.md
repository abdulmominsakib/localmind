---
title: Upgrade to 0.17
description: "Migration steps for upgrading llamadart from 0.16.x to 0.17.x: optional backend capabilities, ImageModelRole.controlNet, thinking defaults and native runtime pins."
---

This page covers the 0.16.x to 0.17.x upgrade. The full history of earlier
upgrades is in
[`MIGRATION.md`](https://github.com/leehack/llamadart/blob/main/MIGRATION.md),
which stays the canonical copy. Pair it with the
[upgrade checklist](./upgrade-checklist).

## `0.17.0` -> `0.17.1`: llama.cpp native runtime `v0.8.0-1`

The hook and the llama.cpp Apple companion source pin `v0.8.0-1`. Flutter iOS and
macOS apps get it with `llamadart_llama_cpp_flutter` `0.17.1`, which requires
core `0.17.1`. A locked companion `0.17.0` keeps `v0.7.0-3` and builds with an
upgrade warning. Web moves to llama.cpp `v0.8.0` too. The LiteRT-LM and
stable_diffusion companions also release at `0.17.1` with unchanged pins, and
their `0.17.0` releases keep working. No Dart API changes.

Behavior to recheck after upgrading:

- A hand-written `grammar` nested or chained more than 256 levels deep throws
  `LlamaInferenceException`.
- `ModelSplitMode.row` on a native llama.cpp device without split buffers throws
  `LlamaUnsupportedException` before the load; use `ModelSplitMode.layer`.
- `GpuBackend.auto` on macOS x86_64 runs on the CPU. Explicit `GpuBackend.metal`
  still uses Metal.
- Opt-in `GpuBackend.blas` at the default thread count uses at most 4 threads;
  set an explicit count to raise it.
- LFM2 and LFM2.5 with `parallelToolCalls: true` can need a higher `maxTokens`: a
  call list cut off before it closes returns no calls.

## `0.16.x` -> `0.17.0`: upgrade guide

Upgrade core and every Apple companion used by the app to `0.17.x` together.
Companions now constrain core to `'>=0.17.0 <0.18.0'`. The llama.cpp and
stable_diffusion companions move to `v0.7.0-3` and `v0.3.0-1`; LiteRT-LM keeps
`v0.18.1-4`.

### Optional LoRA and multimodal backend capabilities

Custom backends and backend test fakes only. `LlamaBackend` no longer
declares `setLoraAdapter`, `removeLoraAdapter`, `clearLoraAdapters`,
`multimodalContextCreate`, `multimodalContextFree`, `supportsVision` or
`supportsAudio`. They move to two optional interfaces in
`package:llamadart/backend.dart`:

- `BackendLoraSupport`: the three LoRA members.
- `BackendMultimodalSupport`: the four projector members.

A backend that supports either implements it next to `LlamaBackend`
(`implements LlamaBackend, BackendLoraSupport, BackendMultimodalSupport`);
its `@override` annotations stay valid. A backend that only threw from
these members deletes them. On a backend without the interface,
`LlamaEngine` LoRA calls and projector loads throw
`LlamaUnsupportedException` naming the missing interface, before
`setLoraSource`, `loadMultimodalProjectorSource` or `setModel` downloads
anything; `removeLoraSource` of an adapter never applied does nothing, and
vision and audio input come from `BackendDirectMediaInput` alone. Code that
called these members through a `LlamaBackend`-typed value checks
`backend is BackendLoraSupport` or `backend is BackendMultimodalSupport`
first.

The built-in routers (`LlamaBackend()` on native and the Web) implement both.
When the selected runtime, such as LiteRT-LM, lacks one, they throw
`LlamaUnsupportedException` naming the runtime instead ("LoRA adapters are
not supported by the active Web runtime."). `LiteRtLmBackend` implements
neither.

### `ImageModelRole.controlNet`

`ImageModelRole` gains `controlNet`. A `switch` over `ImageModelRole` without
a default case no longer compiles; add the case or a default. A file whose
header shows ControlNet tensor names is now assigned this role instead of
failing classification: outside the bounded SD 1.x macOS CPU recipe,
`ImageGenerationEngine.load` throws `LlamaUnsupportedException` instead of
`LlamaModelException`. A ControlNet loaded with no file holding diffusion
weights (for example, alone) still throws `LlamaModelException`.

### Thinking follows llama-server on more templates

`enableThinking`, which defaults to `true`, now reaches every chat template as
`enable_thinking`, including `responseFormat` and tool-call requests, so
templates such as GLM-4.6, Apertus and DeepSeek-R1 distills render thinking
as llama-server does: Apertus now deliberates and DeepSeek-R1 distills open a
thought unless the request passes `enableThinking: false`. A boolean
`enable_thinking` or `thinking` in `chatTemplateKwargs` now overrides
`enableThinking`. With thinking off, `<think>` blocks that DeepSeek V3.1,
Qwen3, QwQ and Qwen3.5 write stay in the content instead of being dropped.

### llama.cpp native runtime `v0.7.0-3`

The hook and the llama.cpp Apple companion source pin `v0.7.0-3`. A Flutter
iOS or macOS build needs companion `0.17.0`, which pins it; a companion
pinning `v0.7.0-2` or earlier fails with `Incompatible Apple llama.cpp
companion`. Apps that depend on a published companion hit pub resolution
first, because companions before `0.17.0` constrain `llamadart` below
`0.17.0`.

### stable_diffusion native runtime `v0.3.0-1`

The hook and the stable_diffusion Apple companion source pin `v0.3.0-1`. A
Flutter iOS or macOS build needs companion `0.17.0`, which pins it; a
companion pinning `v0.3.0` fails with `Incompatible Apple stable_diffusion
companion`, because that runtime aborts on FP8 weights on Metal, which this
core now loads there. Upgrade core and companion together.
