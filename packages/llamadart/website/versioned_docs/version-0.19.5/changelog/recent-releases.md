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

## 0.19.5

- Keep default WebGPU bridge assets at `v0.1.83` (unchanged from 0.19.4).
- Adopt native LiteRT-LM `v0.19.1-3`, whose `LiteRtLm` has the GPU accelerator built in: GPU generation is unchanged, the unused Metal accelerator no longer ships, the macOS hook bundle is 8.7 MB smaller and iOS apps 8.1 MB smaller, and the iOS LiteRT-LM frameworks no longer use the User Defaults required-reason API ([#1798](https://github.com/leehack/llamadart/issues/1798)).
- Native LiteRT-LM strict `responseFormat` now also runs on the macOS arm64 GPU, iOS arm64 CPU and GPU, and the Android arm64, Linux x64/arm64 and Windows x64 CPU, and with Gemma 4 (bundle template), which can think before its constrained reply. It accepts the JSON Schema subset that both llama.cpp's GBNF converter and LiteRT-LM's LLGuidance enforce (nested objects, arrays, `$ref`, `anyOf`, anchored patterns, `uuid`/`date` formats, bounds). Other schemas, including `oneOf`, throw `LlamaUnsupportedException` naming the schema path, and other hosts, Android, Linux and Windows GPUs and NPU throw it before generation. Qwen3 with thinking is refused, and a reply cut off inside the JSON reports finish reason `length` ([#174](https://github.com/leehack/llamadart/issues/174)).
- `getPerformanceContext()` on native LiteRT-LM returns the counters of a generation cancelled mid-stream again, as before the 0.19 runtime, instead of null ([#1903](https://github.com/leehack/llamadart/issues/1903)).
- `engine.getContextSize()` on LiteRT-LM Web `withTextHistory()` loads returns the context size the runtime's executor enforces when its load probe finds one below the requested size, such as Qwen3 0.6B's 4096 on WASM CPU, instead of the requested `ModelParams.contextSize` ([#1861](https://github.com/leehack/llamadart/issues/1861)).
- Parse Qwen3-Coder XML tool calls as llama.cpp does: a call needs a line break after each tag and around each value (a CRLF or compact `<tool_call><function=` call is dropped), its required arguments come before its optional ones, and a string value keeps its whitespace and any `</parameter>` not followed by a line break. Nemotron 3 Nano now parses as Qwen3-Coder XML, so a `<tool_call>` also ends its thought, and the tool-call grammar of these templates requires that shape and starts at `<tool_call>` ([#1898](https://github.com/leehack/llamadart/issues/1898)).
- Parse Seed-OSS tool calls closer to llama.cpp: a finished reply whose last `<seed:tool_call>` scope is never closed keeps a call complete through `</function>` and drops one cut off before it, an argument declared as a string keeps its value as generated instead of being read as JSON (`\n42\n` stays a string), and with `ToolChoice.required` the grammar lets a thought and text come before the calls ([#1898](https://github.com/leehack/llamadart/issues/1898)).
- Parse a MiniMax M3 reply to a forced-open thought as llama.cpp does: the thought ends at the first `</mm:think>` and any later `<mm:think>` or `</mm:think>` is content, so a reply such as `</mm:think></mm:think><mm:think>` streams the same whole or split by character, with `ToolChoice.none` too ([#1905](https://github.com/leehack/llamadart/issues/1905)).
- Support the Ling 3.0 (Bailing V3) chat format as llama.cpp does: its `<tool_call>name` calls with `<arg_key>`/`<arg_value>` arguments no longer parse as Hermes JSON, a `<tool_call>` ends a forced-open thought, a Hermes JSON call stays content, and a trailing `<|role_end|>` is consumed. A string argument is the raw text up to `</arg_value>`; any other is JSON ([#1857](https://github.com/leehack/llamadart/issues/1857)).

Runtime baseline: native llama.cpp `v0.9.0` and Web use upstream `v0.9.0@cd959bae99ff4bed22bef2604f45241c09bbb8c8`; native LiteRT-LM uses `v0.19.1-3` and stable-diffusion uses `v0.3.0-3`. Web LiteRT-LM uses `@litert-lm/core@0.19.0`. Manifest SHA-256: `ae6f488408672f9ba28d8f9e664a2b85f4e12048f290e259e18dd0b750c038e5`.

## 0.19.4

- Keep default WebGPU bridge assets at `v0.1.83` (unchanged from 0.19.3).
- Add tool calling to LiteRT-LM Web through `LlamaBackend.withTextHistory()` on `@litert-lm/core@0.19.0`: `create` returns the model's tool calls and takes tool results in the next request, and `supportsToolCalling` reports whether the loaded runtime reads tool declarations; `ToolChoice.required` and `parallelToolCalls` still throw `LlamaUnsupportedException`. Replies cut off at `maxTokens` or the context size now end with finish reason `length`, and automatic tool loops (`sendWithTools`, `completeWithTools`) run when a load probe finds that the runtime reports per-turn token counts; a reply that ends exactly at `maxTokens` also reports `length` ([#1790](https://github.com/leehack/llamadart/issues/1790), [#919](https://github.com/leehack/llamadart/issues/919)).
- Document that LiteRT-LM Web `generate()` wraps the prompt in one user turn of the bundle's chat template, because `@litert-lm/core@0.19.0` has no raw streaming route ([#1863](https://github.com/leehack/llamadart/issues/1863)).
- Make native LiteRT-LM errors more specific: a failed chat send on the C API 1.0 runtime names the unadaptable bundle template or `ModelParams.chatTemplate`, as the legacy runtime does; an argument error from the worker isolate keeps `LlamaArgumentException.name`; and the raw-prompt refusal says whether the prompt is empty or holds only the model's start token ([#1868](https://github.com/leehack/llamadart/issues/1868), [#1861](https://github.com/leehack/llamadart/issues/1861)).
- When the prompt opened no thought, take a thought only at the start of the reply, as llama.cpp does: any other thinking tag, such as a `</think>` before any `<think>`, a later `<think>` or a second `</think>`, is now content in generic, Llama 3, GLM 4.5, Kimi K2, LFM2, Laguna, Granite, MiniCPM5, Mistral Nemo, Apertus, Hunyuan V3 and DeepSeek R1, V3.2 and V4 replies, and after the start of a Hermes or Qwen3-Coder XML reply. The stream used to depend on how the reply was chunked and could repeat text as both content and reasoning. MiniMax M3 does the same: a `<mm:think>` after leading whitespace or later in the reply, and a `</mm:think>` after text, stay content ([#1865](https://github.com/leehack/llamadart/issues/1865), [#1887](https://github.com/leehack/llamadart/issues/1887)).
- Parse Qwen3-Coder XML replies (Qwen3-Coder, Qwen3.5, StepFun3.5-Flash) as llama.cpp does: text from the first `<tool_call>` on that is not a valid call, such as an invalid call or text after the calls, is dropped instead of kept as content; only the first call counts without `parallelToolCalls`; Qwen3-Coder replies have no reasoning; and StepFun3.5-Flash with thinking off ends its thought at `</think>` or `<tool_call>`. With `ToolChoice.required`, these replies may think and write text before their calls instead of having to start with `<tool_call>`, so one that spends `maxTokens` first ends with `length` and no call, and a Qwen3-Coder call that leaves out the first `<tool_call>` is now a tool call ([#1531](https://github.com/leehack/llamadart/issues/1531)).
- Start Seed-OSS tool calls only at a `<seed:tool_call>` followed by a line break, as llama.cpp does, in both the parser and the tool-call grammar: a scope such as `<seed:tool_call><function=` is now content, and a call after it is still found. An unknown tool or a missing required argument still parses as a call; Seed-OSS requests refuse `ToolDefinition.fromJsonSchema` tools, so validate the tool name and arguments before running a call ([#1542](https://github.com/leehack/llamadart/pull/1542#issuecomment-6758592134)).

Runtime baseline: native llama.cpp `v0.9.0` and Web use upstream `v0.9.0@cd959bae99ff4bed22bef2604f45241c09bbb8c8`; native LiteRT-LM uses `v0.19.1-2` and stable-diffusion uses `v0.3.0-3`. Web LiteRT-LM uses `@litert-lm/core@0.19.0`. Manifest SHA-256: `ae6f488408672f9ba28d8f9e664a2b85f4e12048f290e259e18dd0b750c038e5`.

## 0.19.3

- Ship the 0.19.2 changes below, which never reached pub.dev: pub.dev rejected the 0.19.2 `CHANGELOG.md` as larger than 256 KiB, so notes for releases before 0.10.0 moved to the [changelog archive](https://github.com/leehack/llamadart/blob/main/doc/changelog_archive.md).
- Keep default WebGPU bridge assets at `v0.1.83` (unchanged from 0.19.1).
- Fix `dart run llamadart:doctor_native --runtime litert_lm` on macOS reporting `ASSET_NOT_DECLARED` for a working runtime: it now checks the runtime the build hook keeps in its cache and reports `target_source: build_hook_cache` ([#1855](https://github.com/leehack/llamadart/issues/1855)).
- Send the prompt unchanged from native LiteRT-LM `generate()`, like other backends, instead of wrapping it in the bundle's chat turn, so `create()` requests that fall back to a rendered prompt are no longer templated twice. A prompt that already starts with the model's start token, such as Gemma's `<bos>`, no longer gets a second one; an empty prompt throws `LlamaArgumentException`; and pre-1.0 runtime overrides without the conversation template setter refuse raw `generate()` with `LlamaUnsupportedException` ([#1853](https://github.com/leehack/llamadart/issues/1853)).
- Report the template native LiteRT-LM renders, such as the embedded Qwen3.5 or Gemma bundle template, in `getMetadata()['tokenizer.chat_template']` and `engine.chatTemplate(...)`, whose `tokenCount` matches the runtime's prefill for Gemma 4 and Qwen3.5. Format detection and parsing keep the file-name template, now reported as `llamadart.chat_template.parsing`, so code that detects the format from `tokenizer.chat_template` should read that key first. Native JSON Schema chat now refuses bundles whose text chats the runtime renders with its own template, matching generation ([#1836](https://github.com/leehack/llamadart/issues/1836)).
- Fix native LiteRT-LM chat failing with "Failed to apply template" on a bundle whose chat template concatenates message content as a string; llamadart now adapts such a template on the bundled C API 1.0 runtime too ([#1867](https://github.com/leehack/llamadart/issues/1867)).
- Keep the start of a tag a finished reply ends in, such as `</thi` when generation stops mid-tag, in an unended thought's reasoning, as llama.cpp `v0.9.0` does; it used to be dropped ([#1531](https://github.com/leehack/llamadart/issues/1531)).
- Keep a `</think>` that comes before any `<think>` in a Hermes, Qwen3-Coder XML or DeepSeek V3 reply as content, with every thinking tag after it, when the prompt opened no thought (such as Qwen3 with thinking on), as llama.cpp does. The result used to depend on how the stream was chunked and could repeat the text before the tag as both content and reasoning ([#1858](https://github.com/leehack/llamadart/issues/1858)).

Runtime baseline: native llama.cpp `v0.9.0` and Web use upstream `v0.9.0@cd959bae99ff4bed22bef2604f45241c09bbb8c8`; native LiteRT-LM uses `v0.19.1-2` and stable-diffusion uses `v0.3.0-3`. Web LiteRT-LM uses `@litert-lm/core@0.19.0`. Manifest SHA-256: `ae6f488408672f9ba28d8f9e664a2b85f4e12048f290e259e18dd0b750c038e5`.

## 0.19.2

Not published: pub.dev rejected the upload because `CHANGELOG.md` exceeded its 256 KiB limit. Its changes ship in 0.19.3.

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
