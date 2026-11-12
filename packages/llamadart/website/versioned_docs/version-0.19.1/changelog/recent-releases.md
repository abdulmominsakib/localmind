---
title: Recent releases
description: Release notes for the unreleased changes and the current and previous llamadart minor, with a link to the full changelog for older releases.
---

This page keeps the unreleased changes and the current and previous minor
releases. Notes for every older release are in
[`CHANGELOG.md`](https://github.com/leehack/llamadart/blob/main/CHANGELOG.md).

For upgrade planning, combine this page with the
[Upgrade Checklist](../migration/upgrade-checklist). For breaking changes,
validate against the exact release tag notes.

## 0.19.1

- Keep default WebGPU bridge assets at `v0.1.83` (unchanged from 0.19.0).
- Adopt native LiteRT-LM `v0.19.1-2`, which reports LiteRT linked in process; the C API is unchanged. Linux and Windows native embeddings need `v0.19.1-2` or later, the bundled runtime: an explicit older `LLAMADART_LITERT_LM_LIB_DIR` runtime, including `v0.19.1-1`, is refused with `LlamaUnsupportedException`, where custom `v0.19.0` and `v0.19.1` runtimes used to crash ([#1367](https://github.com/leehack/llamadart/issues/1367)).
- Stop bundling and loading the unused prebuilt `libLiteRt` (about 7 to 9 MB) in Linux and Windows LiteRT-LM apps, whose runtime links LiteRT in; an older `LLAMADART_LITERT_LM_LIB_DIR` runtime still loads the `libLiteRt` it ships with ([#1815](https://github.com/leehack/llamadart/issues/1815)).
- Refuse LiteRT-LM GPU on Linux when every Vulkan device is a software rasterizer such as Mesa llvmpipe, where small models could return wrong text: `ComputeDevice.gpu` throws `LlamaUnsupportedException` at load, and a GPU hint under `ComputeDevice.auto` runs on the CPU with a warning ([#572](https://github.com/leehack/llamadart/issues/572)).
- Fix native LiteRT-LM `dispose` failing with "worker stopped before native cleanup was confirmed" when cleanup outlasts 5 s, such as releasing a freshly written CPU weight cache on Linux ext4; `freeTimeout` now bounds only the wait for native teardown to start ([#1814](https://github.com/leehack/llamadart/issues/1814)).
- Fix model cache `clear`, `remove` and `prune` on Windows failing with "Access is denied" when another process or isolate was deleting the same entry at that moment ([#1821](https://github.com/leehack/llamadart/issues/1821)).
- Release all three Apple runtime companions at `0.19.1` with a Flutter floor of `>=3.38.6`, the first Flutter whose Dart (3.10.7) satisfies their `sdk: ^3.10.7`; Flutter 3.38.0 to 3.38.5 could not resolve them ([#1834](https://github.com/leehack/llamadart/issues/1834)). The LiteRT-LM companion pins `v0.19.1-2` and requires core `0.19.1`.

Runtime baseline: native llama.cpp `v0.9.0` and Web use upstream `v0.9.0@cd959bae99ff4bed22bef2604f45241c09bbb8c8`; native LiteRT-LM uses `v0.19.1-2` and stable-diffusion uses `v0.3.0-3`. Web LiteRT-LM uses `@litert-lm/core@0.19.0`. Manifest SHA-256: `ae6f488408672f9ba28d8f9e664a2b85f4e12048f290e259e18dd0b750c038e5`.

## 0.19.0

- Add native llama.cpp speech output for LFM3-Audio, Soprano, Chatterbox Turbo, Chatterbox Multilingual and Pocket TTS (`Lfm3AudioTtsAdapter`, `SopranoTtsAdapter`, `ChatterboxTtsAdapter`, `PocketTtsAdapter`), with predefined voice selection (`TextToSpeechRequest.voice`, `TextToSpeechCapabilities.voices`) and Chatterbox and Pocket speaker-reference cloning. LFM3-Audio and Soprano need llamadart-native `v0.8.0` and Chatterbox and Pocket `v0.9.0`; older runtimes refuse them with `LlamaUnsupportedException` ([#1615](https://github.com/leehack/llamadart/issues/1615), [#1783](https://github.com/leehack/llamadart/issues/1783)).
- Adopt native llama.cpp `v0.9.0`: ARM64 CPU F16 dot products of large values no longer overflow to inf or NaN ([llamadart-native#174](https://github.com/leehack/llamadart-native/issues/174)), and Qwen3-TTS sampling applies the GGUF's suppress tokens.
- Aligned default WebGPU bridge assets to `v0.1.83` on the same upstream llama.cpp as native, so Web Qwen3-TTS also applies the GGUF's suppress tokens ([llama-web-bridge#211](https://github.com/leehack/llama-web-bridge/pull/211)).
- Adopt native LiteRT-LM `v0.19.1-1` (upstream LiteRT-LM `v0.19.1`); the C API is unchanged.
- Support LiteRT-LM native CPU embeddings on Linux x64, Linux arm64 and Windows x64 ([#1367](https://github.com/leehack/llamadart/issues/1367)), and fix the crash at the first LiteRT-LM GPU decode on Linux x64 and Windows x64 ([#1795](https://github.com/leehack/llamadart/issues/1795)).
- Fix LiteRT-LM text-only or audio-only turns that failed with "Image history requires a vision encoder." after an image turn on the same engine ([#1781](https://github.com/leehack/llamadart/issues/1781)).
- Move Web LiteRT-LM to `@litert-lm/core@0.19.0`; WebGPU loads keep the runtime's default backend, so standard `.litertlm` bundles load there. Web embeddings, tool loops, media and custom templates stay unsupported. In Safari 27, GPU text, history and the chat app pass; on CPU, the runtime's compat build can leave Qwen3 0.6B thinking through its whole token budget ([#1025](https://github.com/leehack/llamadart/issues/1025), [#1802](https://github.com/leehack/llamadart/issues/1802)).
- Support `microBatchSize` above 8, media (with the image encoder on the CPU), speculation and embeddings for native Qwen3.5 on Android Vulkan with the bundled runtime; runtimes older than ggml `0.28.0` (llamadart-native `v0.8.0`) keep the text-only restriction ([#948](https://github.com/leehack/llamadart/issues/948)).
- Pair all three Apple runtime companions at `0.19.0` with matching native binaries.

Runtime baseline: native llama.cpp `v0.9.0` and Web use upstream `v0.9.0@cd959bae99ff4bed22bef2604f45241c09bbb8c8`; native LiteRT-LM uses `v0.19.1-1` and stable-diffusion uses `v0.3.0-3`. Web LiteRT-LM uses `@litert-lm/core@0.19.0`. Manifest SHA-256: `ae6f488408672f9ba28d8f9e664a2b85f4e12048f290e259e18dd0b750c038e5`.

## 0.18.0

- Fix synthesized speech playback in the macOS chat example.
- Add shared `LlamadartEngine<C>` lifecycle management and eager text/chat and Decision tasks with events, completion and request-scoped cancellation.
- Parse LFM2 tool arguments against their schemas, preserve unescaped inner quotes in required JSON string arguments ([#1609](https://github.com/leehack/llamadart/issues/1609)), honor explicit parallel requests, keep reasoning non-executable and expose unfinished calls as separate diagnostics.
- Apply supported native/Web lazy tool grammars and Web prompt penalties with explicit capability checks and unchanged ordinary grammar defaults.
- Adopt native LiteRT-LM `v0.19.0` and C API 1.0 with legacy compatibility, tagged Android pointer support, validated settings and typed unsupported-path errors.
- Preserve LiteRT-LM workers and model caches after unsettled native cleanup; reject incomplete runtime overrides and document process-restart recovery and unsupported text LoRA.
- Keep cached models reusable, visible and removable after cache-root moves, including iOS app updates ([#1741](https://github.com/leehack/llamadart/issues/1741)).
- Adopt llama.cpp `v0.8.0-3` for speculative rollback and model-creation ownership fixes, retaining the genuine nextn query while retiring the unused embedding query; isolate native bundle caches from older apps, verify Apple framework identity and report missing Windows speculative helpers.
- Restrict unqualified Android Vulkan Qwen3.5 combinations to bounded ordinary text; refuse larger micro-batches, media, speculation and embeddings ([#948](https://github.com/leehack/llamadart/issues/948)).
- Adopt stable-diffusion `v0.3.0-3` for original SD checkpoint containers while retaining the SDXS tiny-decoder policy and iOS full-VAE Metal restrictions.
- Reinitialize native LiteRT-LM image-chat engines after cancellation before reusing them ([#1749](https://github.com/leehack/llamadart/issues/1749)).
- Keep future LiteRT-LM SwiftPM pin syncs aligned with macOS app-bundle runtime discovery.
- Request optional Android vendor OpenCL access in the chat example and document LiteRT-LM GPU setup and CPU fallback.
- Document Safari 27 LiteRT-LM Web GPU support, required `require-corp` isolation and hidden-tab termination during large model loads ([#1025](https://github.com/leehack/llamadart/issues/1025)).
- Aligned default WebGPU bridge assets to `v0.1.82` with bounded preallocation for large wasm32 model writes.
- Pair all three Apple runtime companions at `0.18.0` with matching native binaries.

Runtime baseline: native llama.cpp `v0.8.0-3` and Web use upstream `v0.8.0@8642541b255bfb5dc39cd351a178be09013a55d6`; native LiteRT-LM uses `v0.19.0` and stable-diffusion uses `v0.3.0-3`. Web LiteRT-LM stays `@litert-lm/core@0.18.0`. Manifest SHA-256: `fda19e047aba5a511020854437cc89e2f53e2f67f5f6cf5fec336faef3a6c362`.
