Releases before 0.10.0 are in the
[changelog archive](https://github.com/leehack/llamadart/blob/main/doc/changelog_archive.md).

## 0.19.7

- Keep the default WebGPU bridge assets at `v0.1.83` (unchanged from 0.19.6).
- Add `ChatTemplateEngine.resolveThinkingBudget`, which fills a `ThinkingBudget`'s omitted tags and the Qwen3-Coder XML line break before `</think>` as `LlamaEngine` does, so integrations that render the prompt themselves can match ([#1929](https://github.com/leehack/llamadart/issues/1929)).
- On macOS x86_64 (Intel Macs and Rosetta), image generation with `ComputeDevice.auto` now runs on the CPU instead of Metal, matching `GpuBackend.auto` for llama.cpp; an explicit `ComputeDevice.gpu` still loads on Metal and logs a warning, while `textEncoderOnCpu`, `vaeOnCpu`, `maxGpuMemoryGiB` or `autoFit: false` under `ComputeDevice.auto` now throw `LlamaUnsupportedException` ([#1600](https://github.com/leehack/llamadart/issues/1600), [#1936](https://github.com/leehack/llamadart/pull/1936)).
- A macOS app with `llamadart_litert_lm_flutter` 0.19.5 (pinned to LiteRT-LM `v0.19.1-3`) next to a core on a later `v0.19.1` build now gets the earlier-build warning instead of "does not link the complete macOS LiteRT-LM runtime"; 0.19.0 to 0.19.4 still get the latter ([#1934](https://github.com/leehack/llamadart/issues/1934)).
- Document the `BackendJsonSchemaThinkingChatGeneration` interface (exported from `lib/backend.dart` since 0.19.5), which custom backends implement to run schema-constrained chat after a reasoning channel ([#1907](https://github.com/leehack/llamadart/pull/1907)).

Runtime baseline: native llama.cpp `v0.9.0` and Web use upstream `v0.9.0@cd959bae99ff4bed22bef2604f45241c09bbb8c8`; native LiteRT-LM uses `v0.19.1-4` and stable-diffusion uses `v0.3.0-3`. Web LiteRT-LM uses `@litert-lm/core@0.19.0`. Manifest SHA-256: `ae6f488408672f9ba28d8f9e664a2b85f4e12048f290e259e18dd0b750c038e5`.

## 0.19.6

- Keep the default WebGPU bridge assets at `v0.1.83` (unchanged from 0.19.5).
- Adopt native LiteRT-LM `v0.19.1-4`, whose `LiteRtLm` embeds LiteRT and its GPU accelerator: generation on CPU and GPU is unchanged, the unused `LiteRt` and WebGPU accelerator libraries no longer ship on macOS and the unused loose `libLiteRt` no longer ships on iOS, the macOS hook bundle download is 6.2 MB smaller (16.9 MB installed), macOS apps using `llamadart_litert_lm_flutter` drop the same two libraries and 6.2 MB of XCFramework downloads, and the iOS hook download is 2.7 MB smaller ([#1911](https://github.com/leehack/llamadart/issues/1911)).
- A thinking budget on Qwen3-Coder XML templates (Qwen3.5, Nemotron 3 Nano, StepFun 3.5 Flash) now closes the thought with a line break before `</think>`, as llama.cpp does, so the reply no longer continues the thought or the raw tool call as content ([#1914](https://github.com/leehack/llamadart/issues/1914)).
- The Qwen3-Coder and Ling 3 tool-call grammars no longer define a rule twice, which rejected valid calls, when a nested argument property is named `at-value-end`; Seed-OSS replies with a closed call followed by unclosed `<seed:tool_call>` scopes no longer end their content with an added `</seed:tool_call>` ([#1861](https://github.com/leehack/llamadart/issues/1861)).
- LiteRT-LM unsupported-runtime errors name the pinned runtime tag (`v0.19.1-4`) instead of `v0.19.1-2` ([#1861](https://github.com/leehack/llamadart/issues/1861)).

Runtime baseline: native llama.cpp `v0.9.0` and Web use upstream `v0.9.0@cd959bae99ff4bed22bef2604f45241c09bbb8c8`; native LiteRT-LM uses `v0.19.1-4` and stable-diffusion uses `v0.3.0-3`. Web LiteRT-LM uses `@litert-lm/core@0.19.0`. Manifest SHA-256: `ae6f488408672f9ba28d8f9e664a2b85f4e12048f290e259e18dd0b750c038e5`.

## 0.19.5

- Keep the default WebGPU bridge assets at `v0.1.83` (unchanged from 0.19.4).
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

- Keep the default WebGPU bridge assets at `v0.1.83` (unchanged from 0.19.3).
- Add tool calling to LiteRT-LM Web through `LlamaBackend.withTextHistory()` on `@litert-lm/core@0.19.0`: `create` returns the model's tool calls and takes tool results in the next request, and `supportsToolCalling` reports whether the loaded runtime reads tool declarations; `ToolChoice.required` and `parallelToolCalls` still throw `LlamaUnsupportedException`. Replies cut off at `maxTokens` or the context size now end with finish reason `length`, and automatic tool loops (`sendWithTools`, `completeWithTools`) run when a load probe finds that the runtime reports per-turn token counts; a reply that ends exactly at `maxTokens` also reports `length` ([#1790](https://github.com/leehack/llamadart/issues/1790), [#919](https://github.com/leehack/llamadart/issues/919)).
- Document that LiteRT-LM Web `generate()` wraps the prompt in one user turn of the bundle's chat template, because `@litert-lm/core@0.19.0` has no raw streaming route ([#1863](https://github.com/leehack/llamadart/issues/1863)).
- Make native LiteRT-LM errors more specific: a failed chat send on the C API 1.0 runtime names the unadaptable bundle template or `ModelParams.chatTemplate`, as the legacy runtime does; an argument error from the worker isolate keeps `LlamaArgumentException.name`; and the raw-prompt refusal says whether the prompt is empty or holds only the model's start token ([#1868](https://github.com/leehack/llamadart/issues/1868), [#1861](https://github.com/leehack/llamadart/issues/1861)).
- When the prompt opened no thought, take a thought only at the start of the reply, as llama.cpp does: any other thinking tag, such as a `</think>` before any `<think>`, a later `<think>` or a second `</think>`, is now content in generic, Llama 3, GLM 4.5, Kimi K2, LFM2, Laguna, Granite, MiniCPM5, Mistral Nemo, Apertus, Hunyuan V3 and DeepSeek R1, V3.2 and V4 replies, and after the start of a Hermes or Qwen3-Coder XML reply. The stream used to depend on how the reply was chunked and could repeat text as both content and reasoning. MiniMax M3 does the same: a `<mm:think>` after leading whitespace or later in the reply, and a `</mm:think>` after text, stay content ([#1865](https://github.com/leehack/llamadart/issues/1865), [#1887](https://github.com/leehack/llamadart/issues/1887)).
- Parse Qwen3-Coder XML replies (Qwen3-Coder, Qwen3.5, StepFun3.5-Flash) as llama.cpp does: text from the first `<tool_call>` on that is not a valid call, such as an invalid call or text after the calls, is dropped instead of kept as content; only the first call counts without `parallelToolCalls`; Qwen3-Coder replies have no reasoning; and StepFun3.5-Flash with thinking off ends its thought at `</think>` or `<tool_call>`. With `ToolChoice.required`, these replies may think and write text before their calls instead of having to start with `<tool_call>`, so one that spends `maxTokens` first ends with `length` and no call, and a Qwen3-Coder call that leaves out the first `<tool_call>` is now a tool call ([#1531](https://github.com/leehack/llamadart/issues/1531)).
- Start Seed-OSS tool calls only at a `<seed:tool_call>` followed by a line break, as llama.cpp does, in both the parser and the tool-call grammar: a scope such as `<seed:tool_call><function=` is now content, and a call after it is still found. An unknown tool or a missing required argument still parses as a call; Seed-OSS requests refuse `ToolDefinition.fromJsonSchema` tools, so validate the tool name and arguments before running a call ([#1542](https://github.com/leehack/llamadart/pull/1542#issuecomment-6758592134)).

Runtime baseline: native llama.cpp `v0.9.0` and Web use upstream `v0.9.0@cd959bae99ff4bed22bef2604f45241c09bbb8c8`; native LiteRT-LM uses `v0.19.1-2` and stable-diffusion uses `v0.3.0-3`. Web LiteRT-LM uses `@litert-lm/core@0.19.0`. Manifest SHA-256: `ae6f488408672f9ba28d8f9e664a2b85f4e12048f290e259e18dd0b750c038e5`.

## 0.19.3

- Ship the 0.19.2 changes below, which never reached pub.dev: pub.dev rejected the 0.19.2 `CHANGELOG.md` as larger than 256 KiB, so notes for releases before 0.10.0 moved to the [changelog archive](https://github.com/leehack/llamadart/blob/main/doc/changelog_archive.md).
- Keep the default WebGPU bridge assets at `v0.1.83` (unchanged from 0.19.1).
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

- Keep the default WebGPU bridge assets at `v0.1.83` (unchanged from 0.19.0).
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
- Aligned the default WebGPU bridge assets to `v0.1.83` on the same upstream llama.cpp as native, so Web Qwen3-TTS also applies the GGUF's suppress tokens ([llama-web-bridge#211](https://github.com/leehack/llama-web-bridge/pull/211)).
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
- Aligned the default WebGPU bridge assets to `v0.1.82` with bounded preallocation for large wasm32 model writes.
- Pair all three Apple runtime companions at `0.18.0` with matching native binaries.

Runtime baseline: native llama.cpp `v0.8.0-3` and Web use upstream `v0.8.0@8642541b255bfb5dc39cd351a178be09013a55d6`; native LiteRT-LM uses `v0.19.0` and stable-diffusion uses `v0.3.0-3`. Web LiteRT-LM stays `@litert-lm/core@0.18.0`. Manifest SHA-256: `fda19e047aba5a511020854437cc89e2f53e2f67f5f6cf5fec336faef3a6c362`.

## 0.17.5

* Preserve quoted LFM2/LFM2.5 tool-end markers inside tool arguments during parsing and streaming.
* Preserve Solar Open text across repeated content channels in parsed and streamed replies.
* Release checks reject changed Apple companion package contents without a version bump, including README-only changes.
* Keep the default WebGPU bridge assets at `v0.1.79` (unchanged from 0.17.4).

Runtime baseline unchanged from `0.17.4`: native llama.cpp `v0.8.0-1` and Web use upstream `v0.8.0@8642541b255bfb5dc39cd351a178be09013a55d6`; native LiteRT-LM stays `v0.18.1-4` and stable-diffusion stays `v0.3.0-1`. Web LiteRT-LM stays `@litert-lm/core@0.18.0`. Manifest SHA-256: `66ffee7a1c2c54c187526ba6a27957141b77438fed9a0f2a5afcfa2736682e9c`.

## 0.17.4

* Restore documentation destinations linked from published package READMEs and protect retained release notes.
* Refresh Apple companion installation guidance in `0.17.2` with unchanged native runtimes.
* Keep the default WebGPU bridge assets at `v0.1.79` (unchanged from 0.17.3).

Runtime baseline unchanged from `0.17.3`: native llama.cpp `v0.8.0-1` and Web use upstream `v0.8.0@8642541b255bfb5dc39cd351a178be09013a55d6`; native LiteRT-LM stays `v0.18.1-4` and stable-diffusion stays `v0.3.0-1`. Web LiteRT-LM stays `@litert-lm/core@0.18.0`. Manifest SHA-256: `66ffee7a1c2c54c187526ba6a27957141b77438fed9a0f2a5afcfa2736682e9c`.

## 0.17.3

- Reject projector requests on fixed LiteRT-LM custom backends before resolving files, preserving the loaded model ([#1556](https://github.com/leehack/llamadart/issues/1556)).
- Fix native LiteRT-LM backend-SPI context recreation after automatic GPU-to-CPU fallback when reusing GPU preference hints.
- Keep the default WebGPU bridge assets at `v0.1.79` (unchanged from 0.17.2).

Runtime baseline unchanged from `0.17.2`: native llama.cpp `v0.8.0-1` and Web use upstream `v0.8.0@8642541b255bfb5dc39cd351a178be09013a55d6`; native LiteRT-LM stays `v0.18.1-4` and stable-diffusion stays `v0.3.0-1`. Web LiteRT-LM stays `@litert-lm/core@0.18.0`. Manifest SHA-256: `66ffee7a1c2c54c187526ba6a27957141b77438fed9a0f2a5afcfa2736682e9c`.

## 0.17.2

- Fix Windows native runtime overrides failing model loads with `no backends are loaded` ([#1649](https://github.com/leehack/llamadart/issues/1649)).
- Preserve assistant reasoning in LFM2.5 templates that read `message.thinking`, including turns with tool calls ([#1623](https://github.com/leehack/llamadart/issues/1623)).
- Reject non-finite `tensorSplit` sums in direct llama.cpp loads instead of silently selecting a free-memory split ([#1554](https://github.com/leehack/llamadart/issues/1554)).
- Keep the default WebGPU bridge assets at `v0.1.79` (unchanged from 0.17.1).

Runtime baseline unchanged from `0.17.1`: native llama.cpp `v0.8.0-1` and Web use upstream `v0.8.0@8642541b255bfb5dc39cd351a178be09013a55d6`; native LiteRT-LM stays `v0.18.1-4` and stable-diffusion stays `v0.3.0-1`. Web LiteRT-LM stays `@litert-lm/core@0.18.0`. Manifest SHA-256: `66ffee7a1c2c54c187526ba6a27957141b77438fed9a0f2a5afcfa2736682e9c`.

## 0.17.1

- Aligned the default WebGPU bridge assets to `v0.1.79`: Web now runs llama.cpp `v0.8.0` like native, and a media embedding batch that takes longer than two minutes on the CPU stays on the worker instead of moving to the main thread ([llama-web-bridge#165](https://github.com/leehack/llama-web-bridge/issues/165)). Upstream `v0.8.0@8642541b255bfb5dc39cd351a178be09013a55d6` matches native `v0.8.0`, which the manifest records; Web LiteRT-LM stays `@litert-lm/core@0.18.0`. Manifest SHA-256: `66ffee7a1c2c54c187526ba6a27957141b77438fed9a0f2a5afcfa2736682e9c`.
- Update the default llama.cpp native runtime to `leehack/llamadart-native@v0.8.0-1` (llama.cpp `v0.8.0`), restoring Metal model loading on Apple devices. Apple apps get it with `llamadart_llama_cpp_flutter` `0.17.1`; a locked companion `0.17.0` keeps `v0.7.0-3` and builds with an upgrade warning. llama.cpp `v0.8.0` refuses a hand-written `grammar` nested or chained more than 256 levels deep with `LlamaInferenceException`; generated schema grammars stay below that.
- With `numberOfThreads` or `numberOfThreadsBatch` at `0`, native llama.cpp now uses at most as many threads as `Platform.numberOfProcessors` reports, instead of always 4, which made inference tens of times slower on hosts with fewer than 4 cores; multimodal projectors and decision encoders follow the same cap. Hosts with 4 or more cores use 4, which lowers opt-in `GpuBackend.blas` on hosts above 4 cores from all cores to 4; set an explicit count to raise it ([#1612](https://github.com/leehack/llamadart/issues/1612)).
- With a bundled GPU backend module that fails to load or finds no device, such as the Windows CUDA sidecar without an NVIDIA driver, llama.cpp `getResolvedGpuLayers()` now reports 0, a warning names the requested backend, and `getAvailableBackends()` no longer lists a module that failed to load. `getResolvedGpuLayers()` also reports 0 for a `GpuBackend.auto` load on a host with no GPU device ([#1598](https://github.com/leehack/llamadart/issues/1598)).
- `ModelSplitMode.row` on native llama.cpp devices without split buffers, which include every bundled GPU backend whose module loads, BLAS and an explicitly selected or fallback CPU, now throws `LlamaUnsupportedException` naming the device before the model loads, instead of a generic load failure; use `ModelSplitMode.layer`. A bundled module that fails to load or finds no device loads row on the CPU instead ([#1576](https://github.com/leehack/llamadart/issues/1576)), and a speculative draft model now loads when its row target runs on the CPU of a host with no GPU backend, instead of failing with "Failed to load draft model" ([#1593](https://github.com/leehack/llamadart/issues/1593)).
- On macOS x86_64, including Rosetta on Apple silicon (an x86_64 process cannot tell the two apart), llama.cpp `GpuBackend.auto` now runs on the CPU with 0 GPU layers, because Metal returns garbled output on Intel Macs with AMD GPUs. An explicit `GpuBackend.metal` or `ComputeDevice.gpu` still uses Metal and logs a warning; arm64 macOS is unchanged ([#1597](https://github.com/leehack/llamadart/issues/1597)).
- On LFM2 and LFM2.5, `ToolChoice.required` with `parallelToolCalls: true` now returns every call instead of only the first; the flag also widens the grammar under `ToolChoice.auto` when the first system message carries the `Force JSON schema.` marker. A longer list needs more tokens: a reply `maxTokens` cuts off before the list closes finishes with `length` and returns no calls, including those already complete, so raise `maxTokens` and retry. Their tool-call parsing also no longer throws on malformed model output: a number too large to represent, a value nested too deeply or a lone quote ([#1606](https://github.com/leehack/llamadart/pull/1606)).
- On DeepSeek R1 templates that support parallel tool calls, such as DeepSeek-R1-Distill-Qwen-32B, `parallelToolCalls: true` now lets the model put whitespace between calls, as llama.cpp does, so it can write the newline its template uses instead of stopping after one call. Templates without parallel calls, such as the stock 1.5B and 8B distills, still allow one call ([#1581](https://github.com/leehack/llamadart/issues/1581)).
- Streamed thinking tags now match the final parse however a backend splits them: a `</think>` split across chunks no longer streams as content when the parse drops it, as in a DeepSeek R1 reply that starts with `</think>`, and TranslateGemma, Muse Glimmer without tools, and PEG-parsed templates without tools such as Ministral 3 Reasoning, Devstral and Nemotron 3 Nano stream thinking tags their parse keeps as text ([#1582](https://github.com/leehack/llamadart/issues/1582)).

## 0.17.0

- **Breaking (backend SPI):** LoRA and multimodal projector members move off `LlamaBackend` into the optional `BackendLoraSupport` and `BackendMultimodalSupport` interfaces. On a backend or routed runtime without one, `LlamaEngine` LoRA calls and projector loads throw `LlamaUnsupportedException`, before any download, and `removeLoraSource` of an adapter never applied does nothing. The built-in backends keep the same support and exception type; `LlamaEngine.loadMultimodalProjector` refuses a LiteRT-LM model with the same `LlamaUnsupportedException` message as `loadMultimodalProjectorSource` and `setModel`, including on a custom backend that reports the LiteRT-LM runtime and implements `BackendMultimodalSupport`, and through a router it no longer says the projector is unsupported by the active runtime ([#362](https://github.com/leehack/llamadart/issues/362), [#1541](https://github.com/leehack/llamadart/issues/1541)).
- Update the default llama.cpp native runtime to `leehack/llamadart-native@v0.7.0-3`, a wrapper rebuild of llama.cpp `v0.7.0`, read through llamadart-native hook contract 2: the hook downloads a backend sidecar archive, such as Windows x64 CUDA, only when that backend is selected, so Windows x64 apps that do not select `cuda` download 15 MiB instead of 703 MiB, and an overridden release that needs an unsupported contract fails the build with `NativeHookContractException` ([#812](https://github.com/leehack/llamadart/issues/812)). Linux arm64 bundles ship FP16 CPU variant modules, and every backend mode loads the best variant the CPU supports, falling back to the baseline, so mixed `auto` and explicit loads share one CPU backend. Apple apps get the runtime with `llamadart_llama_cpp_flutter` `0.17.0`.
- Pin stable-diffusion-native `v0.3.0-1` (stable-diffusion.cpp master-1017), which loads FP8 image weights as F16 on Metal: FP8 checkpoints now generate on Metal instead of being refused. The bounded image recipes are requalified on it, and Flutter iOS/macOS apps need `llamadart_stable_diffusion_flutter` `0.17.0` ([#1446](https://github.com/leehack/llamadart/issues/1446)).
- Aligned the default WebGPU bridge assets to `v0.1.76`: removes the retained projector copy behind the repeated Web media embedding batch abort on the wasm32 core, which stays unqualified ([#1189](https://github.com/leehack/llamadart/issues/1189)) and can still exhaust its heap on larger contexts ([llama-web-bridge#200](https://github.com/leehack/llama-web-bridge/pull/200)); a speculative draft that does not fit throws `LlamaUnsupportedException` instead of leaking until the runtime aborts, and a model whose context does not fit fails its load instead of aborting ([#198](https://github.com/leehack/llama-web-bridge/pull/198)); and uncached model loads report progress as they download ([#195](https://github.com/leehack/llama-web-bridge/pull/195)). Upstream `v0.7.0@620d2225cc436ab0b001e3200e590e3b286ef9ab` matches native `v0.7.0-2`, which the manifest records; Web LiteRT-LM stays `@litert-lm/core@0.18.0`. Manifest SHA-256: `90822656cef6eaf43a47eafc7fe32f2ef9c2ed56a74c6b3cae29115ba61f818a`.
- Check whether a model and `ModelParams` can load here before any download with `await engine.checkLoad(model, params: params)`: the `LlamaLoadCheckReport` is `unsupported` exactly when `setModel` would throw before downloading (LiteRT-LM on macOS x86_64, Windows arm64 or the x86_64 iOS simulator, an explicit device the platform lacks, or an option the runtime ignores), and names the runtime and device the load would use. Custom backends join through `BackendLoadCheck`. `setModel` now also rejects a LiteRT-LM model with `LlamaUnsupportedException` before any download, keeping the loaded model, for `ComputeDevice.npu` or `liteRtLmEmbeddingEngine` on the Web and for `liteRtLmEmbeddingEngine` on native platforms without qualified embeddings (Linux and Windows); these used to fail at load after the previous model was unloaded ([#861](https://github.com/leehack/llamadart/issues/861)).
- Load a GGUF model on chosen GPUs with `ModelParams.gpuDevices` (`listGpuDevices` indices of one backend) and set each GPU's share with `tensorSplit` on native llama.cpp, validated on one Metal GPU and on a Vulkan Tesla T4, with Mesa lavapipe as the second device for two-device lists and splits (two-GPU hardware has no evidence yet, and CUDA is not hardware-qualified); decision heads and multimodal projectors of the model run on a listed GPU ([#1517](https://github.com/leehack/llamadart/issues/1517)), and indices the host lacks, a split of another length, the Web and LiteRT-LM throw `LlamaUnsupportedException` ([#916](https://github.com/leehack/llamadart/issues/916)).
- Keep Mixture-of-Experts expert weights in host memory with `ModelParams.cpuMoeLayers` and cache recently used experts on the GPU with the experimental `moeCacheBytes` budget on native llama.cpp with Metal or CUDA, validated on Metal only (CUDA and multi-GPU hosts have no hardware evidence yet); a budget on Vulkan, other backends or tensor split, and either field on the Web or LiteRT-LM, throw `LlamaUnsupportedException` ([#1123](https://github.com/leehack/llamadart/issues/1123)).
- `LlamaEngine.stateIdentity()` reports the native runtime build, session format, context size and a digest of the context settings that shape the saved state (KV cache types, flash attention, sequences, SWA and RoPE), so an app can check a llama.cpp state file another process saved before loading it. It needs native llama.cpp with `llamadart-native` `v0.7.0-3`; Web, LiteRT-LM, custom backends and older runtimes throw `LlamaUnsupportedException` ([#1211](https://github.com/leehack/llamadart/issues/1211)).
- Return images from tools with `LlamaToolResultContent.content` or a handler's `LlamaToolOutput` on native llama.cpp with a vision projector and Hermes-style templates (smoke-tested on macOS CPU and Metal with Qwen3.5-0.8B weights, a `qwen3vl_merger` projector and the Qwen3-VL template), rendered as llama-server renders them; check `LlamaEngineCapabilities.toolResultMedia`. Other formats, runtimes, audio, video and URL-only images throw `LlamaUnsupportedException` ([#1008](https://github.com/leehack/llamadart/issues/1008)).
- Parse a reply as the engine does with `ChatTemplateEngine.parseRendered(rendered, output)`, which reads how its `render` or `engine.chatTemplate` result left the thought: after the stock Seed-OSS template, `Plan</seed:think>Sunny.` is content, as in llama-server, where `ChatTemplateEngine.parse` returns reasoning `Plan` ([#1565](https://github.com/leehack/llamadart/issues/1565)).
- Native LiteRT-LM under `ComputeDevice.auto` retries a GPU engine that fails to start on the CPU with a warning, and reports `LiteRT-LM cpu`; explicit `gpu` and `npu` still fail ([#1034](https://github.com/leehack/llamadart/issues/1034)).
- Refine text-to-image output in a second pass at up to twice the size with `HiresFixImageGenerationRequest` and `ImageHiresFix` (latent upscale, bounded to 1024x1024 and 4 images) on macOS CPU or Metal with SD 1.x or SD 2.x full-VAE checkpoints; check `ImageGenerationCapabilities.supportsHiresFix`, and other recipes throw `LlamaUnsupportedException` ([#1228](https://github.com/leehack/llamadart/issues/1228)).
- Edit images from a reference with FLUX.1 Kontext [dev] through `ReferenceImageEditingRequest` and `ImageReferenceEditingRecipe.fluxKontext` (one RGB reference at the output size, at most 1024x1024) on macOS Metal with the Kontext transformer, `ae`, CLIP-L and T5-XXL; check `ImageGenerationCapabilities.supportsReferenceImageEditing`, and other models, devices and reference counts throw `LlamaUnsupportedException` ([#1222](https://github.com/leehack/llamadart/issues/1222)).
- Load an SD 1.x ControlNet as `ImageModelRole.controlNet` and steer generation with `ControlNetImageGenerationRequest` on the bounded macOS CPU recipe; other ControlNet recipes are refused at load ([#1224](https://github.com/leehack/llamadart/issues/1224)).
- Keep an image model's text encoders or VAE on the CPU, cap the GPU memory stable-diffusion.cpp uses, or turn off its automatic fit with `ImageGenerationEngine.load(placement: ImageModelPlacement(...))` on Metal and Vulkan, validated with SD-Turbo on Metal and measured on one Vulkan Tesla T4 (multi-GPU hosts have no evidence yet); a placement on a CPU engine, Android, the CPU builds or the Web, and a GPU budget with the fit off or on Vulkan without a discrete GPU, throw `LlamaUnsupportedException` ([#806](https://github.com/leehack/llamadart/issues/806)).
- Chat templates now receive `enableThinking` as `enable_thinking` on every request, including `responseFormat` and generic tool-call routes, as in llama.cpp, so templates such as GLM-4.6, GLM-4.7-Flash, GLM-OCR, SmolLM3, Apertus and DeepSeek-R1 distills render thinking as llama-server does for the same flag. `enableThinking` still defaults to `true`, so Apertus now deliberates and DeepSeek-R1 distills open a thought unless you pass `false` ([#1465](https://github.com/leehack/llamadart/issues/1465)).
- A boolean `enable_thinking` or `thinking` chat template kwarg now overrides `enableThinking`, and a template's own thinking setting passed in `chatTemplateKwargs`, such as `reasoning_effort` for Hy3 and Cohere2 MoE or `thinking_mode` for MiniMax M3, is no longer replaced by the value llamadart derives from `enableThinking`, so both render as in llama-server; DeepSeek V3.1 forces its thought open from `enableThinking` alone ([#750](https://github.com/leehack/llamadart/issues/750)).
- A `responseFormat` or tool-call grammar after a thought the prompt leaves open now lets the model finish the thought first, as llama-server does, instead of returning the JSON as reasoning; a thought the template opens stays open with `enableThinking: false`, as in llama-server ([#1465](https://github.com/leehack/llamadart/issues/1465)). A required tool call after such a thought also lets Cohere2 MoE, Nemotron 3 Nano, MiniCPM5 and Hy3 models finish it first; MiniCPM5 previously wrote the call inside the thought and returned no tool call.
- A thought that Qwen3.5, QwQ and other Hermes-style templates open in the prompt, or that DeepSeek V3.1 forces open, is kept as llama-server does: an escaped `\n` and a repeated `<think>` stay in the reasoning as generated, thinking tags after the first `</think>` stay in the content instead of being parsed as more reasoning, a partial `</think>` that ends an unfinished thought is dropped, and a `<tool_call>` also ends a Qwen3.5 thought ([#750](https://github.com/leehack/llamadart/issues/750)).
- With thinking off, DeepSeek V3.1, Qwen3, QwQ and Qwen3.5 replies keep any `<think>` blocks the model writes in the content, as llama-server does, instead of dropping them as hidden reasoning ([#750](https://github.com/leehack/llamadart/issues/750)).
- With thinking off, StepFun3.5-Flash, DeepSeek R1 distills, MiniMax M2 and Nemotron Nano v2 replies no longer stream a thought the model writes before `</think>` as content: content waits for `</think>`, `<think>` or the end of the reply, matching the final message at any chunking ([#1532](https://github.com/leehack/llamadart/issues/1532)).
- With thinking off, Cohere2 MoE replies no longer stream a thought the model writes before `<|END_THINKING|>` as content: content waits for a thinking tag, `<|START_TEXT|>` or `<|START_ACTION|>`, where llama-server ends the thought. Command R7B and Seed-OSS templates that open the thought with thinking off hold their reply until a thinking tag, and Ministral and Solar Open replies, whose parse keeps such text as content, no longer wait ([#1553](https://github.com/leehack/llamadart/issues/1553), [#1557](https://github.com/leehack/llamadart/issues/1557)). With thinking off, a Cohere2 MoE thought that ends at `<|START_TEXT|>` or `<|START_ACTION|>` is reasoning instead of content, as in llama-server; thinking tags inside a Cohere2 MoE text or action stay text; and a response schema no longer leaves the thought open ([#1566](https://github.com/leehack/llamadart/issues/1566)).
- Cohere2 MoE and Command R7B models on native llama.cpp keep the thinking, action and response markers their GGUFs store as control tokens, as llama-server does, so their thoughts, tool calls and text parse instead of all landing in reasoning or showing up as raw JSON ([#1505](https://github.com/leehack/llamadart/issues/1505)).
- A Cohere2 MoE thought that the prompt opens ends at a `<|START_TEXT|>` or `<|START_ACTION|>` the model writes without `<|END_THINKING|>`, as in llama-server, so its text and tool calls no longer land in the reasoning; with `enableThinking: false` and a `reasoning: true` chat template kwarg, its prompt ends with the template's own empty thought, without a trailing newline ([#1523](https://github.com/leehack/llamadart/issues/1523)).
- A Seed-OSS reply to a prompt that opens no thought, as the stock template renders, has one only when it starts with `<seed:think>`, kept as generated up to the first `</seed:think>`, as in llama-server; other thinking tags stay in the content ([#1561](https://github.com/leehack/llamadart/issues/1561)). To a prompt that opens the thought, a repeated `<seed:think>`, and any text before it, stay in the reasoning up to the first `</seed:think>`, as in llama.cpp, instead of the tag being dropped, and a thinking tag inside a tool-call argument after that thought no longer drops the call.
- Replies with parallel tool calls return one call per block instead of none, and the tool-call grammar admits those blocks, or only one call when parallel tool calls are off, as llama.cpp does: `<tool_call>` blocks of Qwen3-Coder XML replies, as from Qwen3-Coder, Qwen3.5 and StepFun3.5 ([#1530](https://github.com/leehack/llamadart/issues/1530)), and `<seed:tool_call>` blocks of Seed-OSS replies ([#1540](https://github.com/leehack/llamadart/issues/1540)). Nemotron 3 Nano's parallel-call grammar admits them too, where it used to admit only replies that parsed to no calls.
- `ToolChoice.required` now returns the tool call on DeepSeek-R1 distills, LFM2 and Functionary v3.2 instead of running to the length limit or returning the call as text: their tool-call grammars match llama.cpp's call framing, without a literal `\n` or a free-text LFM2 `id`, and DeepSeek-R1 takes one call unless `parallelToolCalls` is set ([#1577](https://github.com/leehack/llamadart/issues/1577)). On Firefunction v2 it no longer makes the model write a free-text call `id`: its tool-call grammar, like llama.cpp's, takes only the call's `name` and `arguments` ([#1565](https://github.com/leehack/llamadart/issues/1565)).
- Requests with an image or audio part and tools honor `ToolChoice.auto` instead of forcing a tool call on templates such as Qwen3-VL and Qwen3.5, and use the same tool-call grammar, triggers, parser and stops as text requests ([#1463](https://github.com/leehack/llamadart/issues/1463)).
- A tool result whose first text is empty no longer renders a leading newline before the next text part on string-only chat templates, as llama-server does ([#1468](https://github.com/leehack/llamadart/issues/1468)).
- A failed native `stateLoadFile` no longer lets the next prompt-prefix reuse skip evaluating the prompt on the cache llama.cpp cleared, which returned wrong scores and text without an error ([#1491](https://github.com/leehack/llamadart/issues/1491)).
- Processes and isolates sharing a model cache root, such as `sharedCache()`, `userSelected(...)` or `appGroup(...)` directories, now download each entry once instead of returning a file another process is still writing, and never cache a file whose length differs from the one the server reported ([#1444](https://github.com/leehack/llamadart/issues/1444)). A cache hit on a read-only model cache root returns the cached entry instead of reporting that no cached model is available.
- `DefaultModelDownloadManager.remove`, `prune` and `clear` no longer delete a cache entry another isolate or process is downloading: `remove` and `clear` remove the rest and throw `ModelCacheEntryInUseException`, and `prune` skips it ([#1467](https://github.com/leehack/llamadart/issues/1467)). Overlapping `remove`, `prune` and `clear` calls on one cache root take turns instead of reporting each other's entries in use ([#1490](https://github.com/leehack/llamadart/issues/1490)), and no longer fail or over-remove when they overlap in one process; a stray `.REMOVAL` directory in a case-insensitive cache root no longer keeps an entry reported in use ([#1522](https://github.com/leehack/llamadart/issues/1522)); `clear` removes a stray `.removal` directory instead of reporting it in use forever ([#1507](https://github.com/leehack/llamadart/issues/1507)); and on Windows a model file that can never be deleted, such as a read-only one, throws its `FileSystemException` instead of `ModelCacheEntryInUseException` ([#1490](https://github.com/leehack/llamadart/issues/1490)).
- For an overridden native release, the `assets.json.absent` record, which notes that the release publishes no `assets.json`, is re-checked daily, or at once when it is dated in the future, and a record whose re-check fails or returns a page that is not JSON is kept and renewed instead of failing the build or retrying on every offline build; an `assets.json` that is truncated, empty, non-UTF-8 or not a manifest fails the build instead of being treated as unpublished; and a CUDA build that cannot reach its `assets.json` uses the cached CUDA sidecar instead of leaving CUDA out ([#1490](https://github.com/leehack/llamadart/issues/1490), [#1506](https://github.com/leehack/llamadart/issues/1506), [#1522](https://github.com/leehack/llamadart/issues/1522)).
- The build hook reuses a cached llama.cpp bundle only while its `extracted/` directory still holds what the cached archive beside it extracted to, and otherwise extracts that archive again, so a library replaced or added in the cache, such as a test stub, is no longer bundled ([#1558](https://github.com/leehack/llamadart/issues/1558)). A cache from an earlier release is extracted again once, without network access. A cached native archive that matches its digest but lacks runtime libraries fails the build instead of being downloaded again on every build ([#1490](https://github.com/leehack/llamadart/issues/1490)), and an incomplete cached core archive that matches its cached `SHA256SUMS` no longer tells an offline build to pre-seed `SHA256SUMS` ([#1506](https://github.com/leehack/llamadart/issues/1506)).
- The image runtime's "not bundled" and other load-failure reasons name the iOS simulators by the build hook's bundle names, `ios-arm64-sim` and `ios-x64-sim`, instead of `ios-arm64` and `ios-x64` ([#1565](https://github.com/leehack/llamadart/issues/1565)).
- The installation guide and support matrix now name `libCLiteRTLM_mac.dylib` as the library a sandboxed Flutter macOS app without the LiteRT-LM companion fails to load, instead of `libLiteRt.dylib` ([#1565](https://github.com/leehack/llamadart/issues/1565)).

## 0.16.5

- Reject unsupported tool-role image/audio content before chat rendering or generation instead of silently losing or relocating it.
- Refuse FP8 image weights on Metal before native loading can abort the process; explicit CPU loading remains available.
- Enforce bounded JSON Schema text output with native LiteRT-LM on macOS arm64 CPU and canonical Qwen3 models.
- Reduce startup compilation overhead for `llamadart:doctor` and add opt-in isolated desktop native diagnostics with privacy-safe loader and ABI observations.
- Add owned RGB image-to-image inputs and binary-mask editing for the bounded macOS CPU SD 2.x full-VAE recipe.
- Document and validate complete image checkpoint containers on macOS CPU, and add verified local Safetensors checkpoint sets with owned caching for the bounded SD-Turbo macOS CPU recipe.
- Add CPU state-persistence validation with cold KV restore, reduced-work controls, typed rejection and recovery checks; native restores reject token capacities outside 1..context size with `LlamaArgumentException`.

* Keep the default WebGPU bridge assets at `v0.1.73` (unchanged from 0.16.4).

Web runtime baseline (unchanged): upstream llama.cpp `v0.7.0@620d2225cc436ab0b001e3200e590e3b286ef9ab`, native `v0.7.0-2`; Web LiteRT-LM `@litert-lm/core@0.18.0`. Bridge manifest SHA-256: `f89c41d151b7df0cbe4f5e97f95563e31e0968c13e65a630e4e0dba28adb1d44`.

## 0.16.4

- Opt into ordered system/user/assistant text history on LiteRT-LM Web with `LlamaBackend.withTextHistory()`; the chat app adopts it, and unavailable controls fail explicitly ([#1152](https://github.com/leehack/llamadart/issues/1152)).

* Keep the default WebGPU bridge assets at `v0.1.73` (unchanged from 0.16.3).

Web runtime baseline (unchanged): upstream llama.cpp `v0.7.0@620d2225cc436ab0b001e3200e590e3b286ef9ab`, native `v0.7.0-2`; Web LiteRT-LM `@litert-lm/core@0.18.0`. Bridge manifest SHA-256: `f89c41d151b7df0cbe4f5e97f95563e31e0968c13e65a630e4e0dba28adb1d44`.

## 0.16.3

- Recommend the corrected Qwen3-0.6B LiteRT-LM model bundle for native CPU to preserve split-token emoji; replace the older model artifact rather than relying on a runtime upgrade.
- Inspect desktop setup with `collectLlamaRuntimeSetupReport()` and `dart run llamadart:doctor [--json]`. Reports separate pinned publication policy from unchecked native loading, GPU/backend selection and model behavior. Exit 0 means report generation, not runtime validation ([#124](https://github.com/leehack/llamadart/issues/124)).
- Set reproducible dates in Dart-rendered chat templates with `TemplateTimeChatSession` and explicit clocks for `strftime_now` ([#859](https://github.com/leehack/llamadart/issues/859)).
- Rerank documents with `LlamaReranker` on native rank-pooled GGUF models, preserving classifier scores, labels and document indices ([#323](https://github.com/leehack/llamadart/issues/323)).
- Generate repeating textures with independent X/Y axes through `SeamlessImageGenerationRequest`; the initial SDXS embedded-tiny-decoder recipe is qualified at 512×512 on CPU and Metal ([#1234](https://github.com/leehack/llamadart/issues/1234)).
- Add opt-in spatial VAE tiling with `TiledImageGenerationRequest` and `ImageVaeTiling`, qualified on SD-Turbo full VAE/TAESD with macOS CPU and Metal. Decoder buffers are about one quarter of untiled size, with longer decoding; other SD 2.x checkpoints remain unmeasured, and unsupported families, backends and circular-axis combinations are refused ([#1231](https://github.com/leehack/llamadart/issues/1231)).
- Control retained image prompt conditioning with `ImageConditioningCacheParams`; zero disables reuse, while ordinary settings preserve the runtime default.
- Add opt-in EmbeddingGemma-2 query/document/title helpers and normalized 768/512/256/128-dimensional outputs. Existing raw embedding calls are unchanged ([#1126](https://github.com/leehack/llamadart/issues/1126)).
- Fix explicit Web GGUF GPU placement with `splitMode: ModelSplitMode.none` and negative `mainGpu`; unavailable or inactive GPUs still throw ([#915](https://github.com/leehack/llamadart/issues/915)).
- Cancel queued Web generation, speech-to-text or speech-synthesis tasks without stopping another request running on the bridge ([#1371](https://github.com/leehack/llamadart/issues/1371)).

* Keep the default WebGPU bridge assets at `v0.1.73` (unchanged from 0.16.2).

Web runtime baseline (unchanged): upstream llama.cpp `v0.7.0@620d2225cc436ab0b001e3200e590e3b286ef9ab`, native `v0.7.0-2`; Web LiteRT-LM `@litert-lm/core@0.18.0`. Bridge manifest SHA-256: `f89c41d151b7df0cbe4f5e97f95563e31e0968c13e65a630e4e0dba28adb1d44`.

## 0.16.2

- Update the default LiteRT-LM native runtime to `leehack/litert-lm-native@v0.18.1-4`. Windows x64 apps no longer need the Visual C++ Redistributable for LiteRT-LM, which now ships its own Visual C++ runtime DLLs ([litert-lm-native#87](https://github.com/leehack/litert-lm-native/issues/87)); llama.cpp already did, so only the opt-in `stable_diffusion` runtime still needs it. On Linux and Windows, LiteRT-LM CPU inference uses the configured thread count instead of one thread: Qwen3 0.6B CPU decode is 3.3× faster on an 8-vCPU Linux arm64 host and 2.2× faster on a 4-vCPU Windows x64 host ([litert-lm-native#89](https://github.com/leehack/litert-lm-native/issues/89), [#1375](https://github.com/leehack/llamadart/issues/1375)). Flutter Apple apps get it with `llamadart_litert_lm_flutter` `0.16.2`.
- Linux and Windows apps built with `dart build cli`, `flutter build linux` or `flutter build windows` load LiteRT-LM from their own bundle, so a copied or installed app no longer fails with `Failed to load dynamic library 'package:llamadart/litert_lm_LiteRtLm'` once the project's hook cache is out of reach ([#1397](https://github.com/leehack/llamadart/issues/1397)).
- LiteRT-LM native embedding loads throw `LlamaUnsupportedException` on Linux, Windows and Android x86_64 instead of failing at engine creation or crashing the process; they stay available on macOS arm64, iOS arm64 and Android arm64 (verified on a Galaxy S24 without SME and on arm64 emulators) ([#1367](https://github.com/leehack/llamadart/issues/1367)).
- Native LiteRT-LM reports `length` instead of `stop` when a reply reaches `maxTokens` or fills the context, and automatic `sendWithTools`/`completeWithTools` loops now run on it, stopping `truncated` without running tools on a cut-off reply. This needs a runtime whose `stream_proxy_finish_reason_abi_version` export returns 1 (litert-lm-native `v0.18.0-3` or later, including the default pin); on older runtimes loops still throw `LlamaUnsupportedException`. `LiteRtLmRuntimeClient` adds `supportsFinishReasons` and `lastFinishReason`. Web LiteRT-LM is unchanged ([#919](https://github.com/leehack/llamadart/issues/919)).
* Aligned the default WebGPU bridge assets to `v0.1.73`: Web `embed()` and `embedBatch()` throw `LlamaUnsupportedException` for rank-pooled rerankers instead of returning an invalid vector built from classifier scores, and `LlamaEmbeddingInputTooLongException` for an input longer than the one micro-batch it must fit, instead of embedding only part of it or aborting the runtime, as native does ([llama-web-bridge#194](https://github.com/leehack/llama-web-bridge/pull/194)). Upstream `v0.7.0@620d2225cc436ab0b001e3200e590e3b286ef9ab` matches native `v0.7.0-2`, which the manifest records; Web LiteRT-LM stays `@litert-lm/core@0.18.0`. Manifest SHA-256: `f89c41d151b7df0cbe4f5e97f95563e31e0968c13e65a630e4e0dba28adb1d44`.
- Add `dart run llamadart:web_setup`: it downloads the Web bridge files this version pins into `web/webgpu_bridge/`, checks each against the pinned release manifest and adds the loader to `web/index.html`; reruns keep current files, and `--check` verifies offline. It refuses a page that already loads the bridge, so remove a hand-written loader first. With its loader, a page whose files are missing fails the first model load at once instead of after 12 seconds ([#855](https://github.com/leehack/llamadart/issues/855)).
- Native llama.cpp `usage.promptTokens` counts the tokens of an image or audio prompt, as llama-server does, instead of its positions, which M-RoPE vision models such as Qwen3.5 report far fewer of ([#696](https://github.com/leehack/llamadart/issues/696)).
- Native llama.cpp frees each context's token batch and sampler chain, and the sampler chain of a running generation, when its worker isolate is killed, instead of leaking about 0.1 MiB per kill plus 12 bytes per vocabulary token during generation (1.8 MiB for Qwen2.5) ([#1404](https://github.com/leehack/llamadart/issues/1404)).
- Correct the `LlamaVideoContent` rejection text: on desktop it points to a projector without a vision encoder instead of saying video support is built out, and it names Android and iOS as the platforms whose artifacts lack video ([#320](https://github.com/leehack/llamadart/issues/320)).

## 0.16.1

- Update the default LiteRT-LM native runtime to `leehack/litert-lm-native@v0.18.1-2`: on SME2 CPUs (verified on Apple M4 and iPhone 16 Pro), CPU chat and audio embeddings are deterministic again ([#1340](https://github.com/leehack/llamadart/issues/1340)) and Gemma 4 CPU decode is faster again ([litert-lm-native#84](https://github.com/leehack/litert-lm-native/issues/84); 1.56× on M4, 1.2× on iPhone 16 Pro), while its CPU prefill is 15–30% slower than `v0.18.1`. Output and speed on non-SME2 CPUs (Linux arm64, Windows x64) are unchanged. Image and audio embeddings shift slightly from core `0.16.0`, so re-embed stored vectors of image or audio content; text-only vectors are unchanged. Flutter Apple apps get it with `llamadart_litert_lm_flutter` `0.16.1`.
* Aligned the default WebGPU bridge assets to `v0.1.72`: Web repeat and presence penalties now count the prompt, as native does, so output for the same seed changes at the default `penalty` of 1.1, and tool chats (`ToolChoice.auto`) leave the prompt out, also as native does. In worker mode, Stop right after a generation starts now stops it, and a bare `cancel()` streams the text generated before the worker yields. Text containing U+0000 is no longer truncated in tokenize, embed, score and prompts; speech text containing it is rejected. Upstream `v0.7.0@620d2225cc436ab0b001e3200e590e3b286ef9ab` matches native `v0.7.0-2`, which the manifest records; Web LiteRT-LM stays `@litert-lm/core@0.18.0`. Manifest SHA-256: `85075d7d278bcacab706b79cda65c4a1bf8098a90f1e9fdbd504c198b8c8b03a`.
- llama.cpp `draftDflash` and `draftDspark` generation throws `LlamaArgumentException` instead of aborting the process when a LiliCorr draft block (`dflash.block_size`, 16 when absent) does not fit one draft micro-batch: `SpeculativeDecodingConfig.draftMicroBatchSize`, or the inherited `ModelParams.microBatchSize` when it is unset ([#1330](https://github.com/leehack/llamadart/issues/1330), [#1341](https://github.com/leehack/llamadart/issues/1341)).
- Fix hexadecimal string escapes in embedded and custom chat templates, including Flint's template ([#1335](https://github.com/leehack/llamadart/issues/1335)).
- Replace a stale embedded LiteRT-LM runtime in the macOS build phase after a core upgrade instead of keeping the old dylib until a clean build.

## 0.16.0

- Add `LlamaCppModelParams` and `LiteRtLmModelParams`, `ModelParams` that take only the fields their runtime applies; the `liteRtLm*` arguments of `ModelParams` are deprecated in favor of `LiteRtLmModelParams`. Loads reject `ModelParams` fields the model's runtime would ignore, such as `liteRtLm*` fields on a GGUF model or `preferMemory64` off the Web, and either type used for the other runtime, with `LlamaUnsupportedException` naming each field; `LlamaBackend()` also rejects these and LiteRT-LM platform gaps before any download when the model format is known ([#858](https://github.com/leehack/llamadart/issues/858), [#861](https://github.com/leehack/llamadart/issues/861)).
- Update the default LiteRT-LM native runtime to `leehack/litert-lm-native@v0.18.1`, built from upstream LiteRT-LM `v0.18.1` with the ASR and stream finish-reason fixes of `v0.18.0-3`. Flutter Apple apps get it with `llamadart_litert_lm_flutter` `0.16.0`. Native GPU embeddings still throw `LlamaUnsupportedException` because EmbeddingGemma 2 still crashes in the prebuilt WebGPU accelerator.
- Update the opt-in stable_diffusion runtime to `leehack/stable-diffusion-native@v0.3.0`, built from stable-diffusion.cpp `master-982-0518b34`: Windows opens model files with non-ASCII paths, and the legacy pickle reader no longer rejects checkpoints above 2 GiB ([stable-diffusion-native#23](https://github.com/leehack/stable-diffusion-native/issues/23)). Images keep the flash attention and direct convolution settings `ImageModelParams` selects instead of the runtime's new automatic per-module choice. Flutter Apple apps need `llamadart_stable_diffusion_flutter` `0.16.0`; this core rejects earlier SD companions, whose `sd_ctx_params_t` is smaller.
* Aligned the default WebGPU bridge assets to `v0.1.70`: a character split across tokens streams once complete instead of as a wrong one, and `detokenize` returns U+FFFD for invalid or incomplete bytes. Upstream `v0.7.0@620d2225cc436ab0b001e3200e590e3b286ef9ab` matches native `v0.7.0-2`, which the manifest records; Web LiteRT-LM stays `@litert-lm/core@0.18.0`. Manifest SHA-256: `7ac4e6e88205396f7221cd4e9e863bdf284df3498ced58cae2ffa1840996a8bf`.
- Native LiteRT-LM applies `GenerationParams.penalty` (other than the default), `presencePenalty` and, in chat on bundles with a thinking channel such as Gemma 4, `thinkingBudget`; penalties count only the tokens of the current send, `capabilities` reports each control, and a value it cannot apply throws `LlamaUnsupportedException` instead of `UnsupportedError` ([#1155](https://github.com/leehack/llamadart/issues/1155)).
- Add `SpeculativeDecodingConfig.draftMicroBatchSize` (llama.cpp `--spec-draft-n-ubatch`) to give native llama.cpp speculative draft contexts a smaller micro-batch and compute buffer than the target; unset keeps the target's, and WebGPU and LiteRT-LM reject it ([#1124](https://github.com/leehack/llamadart/issues/1124)).
- Templates that open a thought in the prompt: Seed-OSS, MiniMax M2, Apriel 1.5, Xiaomi MiMo and EXAONE MoE return it as reasoning until its end tag, as llama.cpp does, and stream it once instead of as content or twice; DeepSeek V3, Seed-OSS, MiniMax M2, Apriel 1.5 and EXAONE MoE also reason before a `ToolChoice.required` tool call and end the thought, so the call is no longer parsed as reasoning and lost ([#742](https://github.com/leehack/llamadart/issues/742)).
- Fix the EXAONE MoE tool-call grammar emitting the tool name unquoted, so constrained tool calls are valid JSON ([#1312](https://github.com/leehack/llamadart/issues/1312)).
- Tool schemas from `ToolDefinition.fromJsonSchema` may list in `required` a property that only `additionalProperties` describes, as JSON Schema allows; the tool-call grammar requires that key instead of rejecting the schema ([#1090](https://github.com/leehack/llamadart/issues/1090)).
- Fix tool-loop rollbacks on `ChatSession` subclasses whose `addMessage` stores a copy of a tool result, adds a note before it or keeps the history length fixed: the rollback could leave an orphaned tool result or note behind ([#1268](https://github.com/leehack/llamadart/issues/1268)).
- Remove the `WEBGPU_BRIDGE_PATCH_SAFARI_COMPAT` and `WEBGPU_BRIDGE_MIN_SAFARI_VERSION` options of `scripts/fetch_webgpu_bridge_assets.sh` and the chat app's Safari patching of the bridge: the default assets already contain both fixes, and overrides to older asset tags no longer get them.

## 0.15.6

- Update the default llama.cpp native runtime to `leehack/llamadart-native@v0.7.0-2`: a fixed `TextToSpeechRequest.seed` gives the same Qwen3-TTS audio on every synthesis of a loaded engine, including after a cancelled one ([#632](https://github.com/leehack/llamadart/issues/632)), and Windows arm64 bundles no longer ship `libomp140.aarch64.dll`, a Visual Studio debug DLL that apps may not redistribute. Apple apps get it with `llamadart_llama_cpp_flutter` `0.15.2`; companions `0.15.0` and `0.15.1` keep building with an upgrade warning.
- Update the default LiteRT-LM native runtime to `leehack/litert-lm-native@v0.18.0-3`: native speech-to-text loads dedicated ASR `.litertlm` containers such as Whisper tiny, which failed engine creation with `tf_lite_prefill_decode not found` ([litert-lm-native#77](https://github.com/leehack/litert-lm-native/issues/77)). Flutter Apple apps get it with `llamadart_litert_lm_flutter` `0.15.2`; companions `0.15.0` and `0.15.1` keep `v0.18.0-2`.
* Aligned the default WebGPU bridge assets to `v0.1.69`: loading a missing or
  truncated Web state file throws `LlamaStateException` instead of aborting the
  runtime, and chat image and audio URLs relative to the page load in worker
  mode. Upstream `v0.7.0@620d2225cc436ab0b001e3200e590e3b286ef9ab` matches
  native `v0.7.0-2`; the asset manifest records the byte-equivalent
  `v0.7.0-1`. Web LiteRT-LM stays `@litert-lm/core@0.18.0`.
  Manifest SHA-256:
  `994e798389d440a256f103f3789a1f56da2ab00dd6bb6e52f334ed4e58867c46`.
- Include the native LiteRT-LM error message and status code in errors from failed engine creation, conversation creation and message sends, on runtimes that report them (`v0.18.0` and later).
- `SpeechToTextEngine.capabilities` with `Qwen3AsrAdapter` reports a projector that is not Qwen3-ASR's, such as a Qwen3-TTS mmproj, as unsupported instead of failing later with an empty transcript; when the projector type cannot be read, an empty transcript's error details name a possible model mismatch ([#641](https://github.com/leehack/llamadart/issues/641)).
- Release a finished dedicated LiteRT-LM speech-to-text task when nobody listens to its events, as with `transcribeOnce`, instead of keeping it and its input audio until the next task.
- `setLoraSource` and `removeLoraSource` match a path adapter spelled with `./`, `../` or repeated separators instead of silently leaving it applied or applying it twice ([#907](https://github.com/leehack/llamadart/issues/907)).
- Reject `ModelParams.loras` that LiteRT-LM cannot take before any adapter downloads, also for extensionless native `.litertlm` files, on the Web and in embedding mode.
- Check and link the Apple companions a Flutter app reaches through another dependency, such as a shared app package or another pub workspace member, instead of bundling the hook's runtimes without them. Host `flutter test` on macOS for such an app no longer loads the bundled llama.cpp or stable_diffusion library. Such an app with `llamadart_litert_lm_flutter` must exclude the x86_64 iOS simulator, as direct dependents already must; the build error names the `EXCLUDED_ARCHS` setting.
- Report the GPU llama.cpp actually uses when an explicit `preferredBackend` has no device, such as `GpuBackend.vulkan` on Apple platforms: `getBackendName()` no longer reports `CPU` when layers are offloaded to another GPU ([#1281](https://github.com/leehack/llamadart/issues/1281)), and the `ComputeDevice.gpu` error names the registered backend, such as `GpuBackend.metal`, instead of suggesting `ComputeDevice.auto` ([#1017](https://github.com/leehack/llamadart/issues/1017)).
- `package:llamadart/backend.dart` exports `BackendRuntimeIdentity`, `BackendModelFormatRouting`, `BackendChatScope`, `BackendDirectMediaInput` and `BackendDeferredEngineCreation`, so custom backends can report their runtime and load an explicit `ModelSource.format` ([#917](https://github.com/leehack/llamadart/issues/917)).
- Report a disposed `LlamaEngine` consistently: deprecated loaders disposed as they finish throw `LlamaStateException`, `loadDecisionHeadBackend` and attached speech engines throw it instead of `LlamaUnsupportedException`, and `dispose()` no longer waits for a projector download that ignores cancellation.
- Fix tool-loop rollbacks on `ChatSession` subclasses and implementations whose `addMessage` moves or repeats messages, or whose `history` returns copies or hides messages; the turn could stay in the history while `rolledBack` was `true` ([#1287](https://github.com/leehack/llamadart/issues/1287)).
- Report `stop` instead of `length` when a llama.cpp speculative-decoding reply ends exactly at `maxTokens`, so `completeWithTools` no longer rolls it back as truncated.
- Let Hermes templates that open reasoning in the prompt, such as QwQ, reason before a `ToolChoice.required` tool call; the call was previously parsed as reasoning and lost.
- Handle deeply nested tool-call output: PEG-parsed formats such as Ministral throw `LlamaInferenceException` instead of overflowing the stack, and Command R7B and Cohere2 MoE replies parse in linear time instead of seconds.
- Structured output and tool schemas: accept annotation-only `allOf` components such as `{"description": "..."}`, matching llama.cpp; reject `\u`-escaped spellings of declared property names as extra keys in open-object grammars; and reject integer bounds at -2^63 on native platforms with `LlamaUnsupportedException`, as on Web, instead of an opaque error or a wrong constraint.
- Document that Windows x64 builds download the full native bundle, about 700 MiB with CUDA, even when CUDA is not selected, and how `llamadart_native_path` avoids it.

## 0.15.5

- Keep Llama 3 (JSON and builtin `<|python_tag|>`), FireFunction v2, Functionary v3.1/v3.2, FunctionGemma and Gemma tool calls out of streamed answer text, and LFM2 and Kimi K2 tool calls out of streamed answer text and reasoning.
- Stream literal thought tags as answer text for FireFunction v2, Functionary v3.1/v3.2, FunctionGemma and Gemma, matching the final reply, and drop the Functionary v3.2 `all` header when a malformed call falls back to raw text.
- Keep partial thought end tags out of streamed reasoning when thinking starts open, such as for GLM 4.5, Laguna and DeepSeek V3.2/V4.
- Stream GPT-OSS `final` and `analysis` frame text as it arrives instead of at the end of the reply.
- Keep Kimi K3 turn-end and think/response channel markers out of streamed answers and reasoning, and stream MiniMax M1 text after a leading tool call.
- Fix GLM 4.5/4.7 and Laguna tool calls stalling for minutes on native llama.cpp while generating string arguments, and GLM 4.7 and Laguna tool calls repeating or garbling arguments because the grammar required newlines between tags.
- Clarify image weight formats, explicit PyTorch roles and directory/shard loading limits.
* Aligned the default WebGPU bridge assets to `v0.1.66` (unchanged from 0.15.4).
  Runtime pins are unchanged: native `v0.7.0-1` uses upstream
  `v0.7.0@620d2225cc436ab0b001e3200e590e3b286ef9ab`; Web LiteRT-LM stays
  `@litert-lm/core@0.18.0`.
  Manifest SHA-256:
  `6a82e16cd850c79ebb8d5f5613dccc9adc42030bf5788bc3cffcda21f19f2f1d`.

## 0.15.4

- Keep GPT-OSS reasoning and tool frames out of answer text, including native header continuations.
- Keep GPT-OSS automatic tool choice optional for ordinary text replies.
- Preserve Gemma 4 answer text after tool calls across split token delivery.
* Aligned the default WebGPU bridge assets to `v0.1.66` (unchanged from 0.15.3).
  Runtime pins are unchanged: native `v0.7.0-1` uses upstream
  `v0.7.0@620d2225cc436ab0b001e3200e590e3b286ef9ab`; Web LiteRT-LM stays
  `@litert-lm/core@0.18.0`.
  Manifest SHA-256:
  `6a82e16cd850c79ebb8d5f5613dccc9adc42030bf5788bc3cffcda21f19f2f1d`.

## 0.15.3

- Refresh media-embedding examples, migration links and upgrade guidance.
- Keep the chat app and private validation harness together in repository checkouts, outside the core pub archive.
- Require validation coverage or tracked exemptions for public capabilities, and run tooling checks for Markdown changes.
* Aligned the default WebGPU bridge assets to `v0.1.66` (unchanged from 0.15.2).
  Runtime pins are unchanged: native `v0.7.0-1` uses upstream
  `v0.7.0@620d2225cc436ab0b001e3200e590e3b286ef9ab`; Web LiteRT-LM stays
  `@litert-lm/core@0.18.0`.
  Manifest SHA-256:
  `6a82e16cd850c79ebb8d5f5613dccc9adc42030bf5788bc3cffcda21f19f2f1d`.

## 0.15.2

* Aligned the default WebGPU bridge assets to `v0.1.66` to preserve worker
  timeouts and model-load tuning during CPU recovery.
  Upstream `v0.7.0@620d2225cc436ab0b001e3200e590e3b286ef9ab` matches native
  `v0.7.0-1`; Web LiteRT-LM stays `@litert-lm/core@0.18.0`.
  Manifest SHA-256:
  `6a82e16cd850c79ebb8d5f5613dccc9adc42030bf5788bc3cffcda21f19f2f1d`.
- Reject late Web content-embedding results after cancellation or disposal.
- Update the opt-in image runtime and Apple companion to `v0.2.0-4` and reject
  images after recorded Metal failures. Keep qualified older Apple companions
  working across patch upgrades with an upgrade warning.
- Add setup guides for Genkit and Flutter Edge AI integrations.

## 0.15.1

- Report native embedding overflow with typed limits and input counts.
* Aligned the default WebGPU bridge assets to `v0.1.65` (unchanged from 0.15.0) for image/audio
  embeddings (API floor v0.1.64+), qualified on Chrome CPU wasm memory64
  against native CPU/Metal `v0.7.0-1` with upstream
  `v0.7.0@620d2225cc436ab0b001e3200e590e3b286ef9ab`. Web LiteRT-LM remains
  `@litert-lm/core@0.18.0`. Immutable Web asset manifest:
  `185cfc060fb90b7c8d240b23e7eeb85ef402eb3ef52e8acb1a5590cd5da56328`.

## 0.15.0

- Embed ordered text, images and audio with typed inputs and modality probes on
  native llama.cpp, native CPU LiteRT-LM (opt in with
  `liteRtLmEmbeddingEngine`) and compatible Web llama.cpp assets.
- Fix vision/audio projector and media-embedding loading in Windows
  `dart build cli` bundles, which also affected 0.14.
- Update the native llama.cpp runtime and Apple companion to v0.7.0-1;
  upgrade core and all Apple companions to 0.15.x together.
* Aligned the default WebGPU bridge assets to `v0.1.65` for image/audio
  embeddings (API floor v0.1.64+), qualified on Chrome CPU wasm memory64
  against native CPU/Metal `v0.7.0-1` with upstream
  `v0.7.0@620d2225cc436ab0b001e3200e590e3b286ef9ab`. Web LiteRT-LM remains
  `@litert-lm/core@0.18.0`. Immutable Web asset manifest:
  `185cfc060fb90b7c8d240b23e7eeb85ef402eb3ef52e8acb1a5590cd5da56328`.
- **Behavior change:** Run decision heads on CPU and report CPU with zero GPU
  layers when native llama.cpp single-device placement selects no GPU.
- **Behavior change:** Reject embedding, scoring, generation and LoRA calls on a
  context during native text-to-speech with `LlamaStateException`.
- Keep performance counters accurate across cancellation, validation and
  dispatch failures, reloads, embeddings, scoring and speech requests.
- Preserve LiteRT-LM Web runtime failures that race generation cancellation.
- Correct chat-template error labels for empty model templates.
- Probe native thinking-budget support and report missing speculative draft
  models as typed argument errors.
- **Behavior change:** Report WebGPU argument rejections as typed argument
  errors instead of inference failures.

## 0.14.0

- **ABI break:** Update the native llama.cpp runtime to v0.7.0 with matching
  bindings and Apple companions; v0.6.0 and older native overrides are
  incompatible, and old companion pins are rejected. Upgrade core and all
  companions together.
- Update the LiteRT-LM native runtime to v0.18.0-2, which reduces duplicated
  words at untimed ASR window boundaries with the default overlap; other boundary
  and recognition errors can remain.
* Aligned the default WebGPU bridge assets to `v0.1.63`, embedding llama.cpp
  `v0.7.0` and qualified against native `v0.7.0`, preserving Web/native
  `v0.7.0@620d2225cc436ab0b001e3200e590e3b286ef9ab` parity. Web LiteRT-LM
  remains `@litert-lm/core@0.18.0`. Immutable Web asset manifest:
  `65d146539eaba034d2c42bfc88a8ff376b937254ea089772401e07cade79f0b9`.
- **Behavior change:** Raw `responseFormat` schemas with unsupported or shadowed
  assertions now throw `LlamaUnsupportedException` with a path before generation
  instead of being silently unconstrained; supported formats, bounds, `allOf`
  and tuples are now enforced.
- Bound tool-call argument nesting to report an inference error instead of
  overflowing the stack.
- Load progress callbacks now declare `void Function(double progress)?`;
  existing `Function(double progress)?` overrides still compile; prefer `void`.
- Hide stale performance counters after cancelling a queued llama.cpp generation.
- Free multimodal input buffers when native media initialization fails.
- Render user follow-ups after tool results on Gemma 2/3/3n and legacy Mistral
  templates.
- Expose `liteRtLmQwen3ChatTemplate` for stable thinking control on renamed
  native LiteRT-LM Qwen3 bundles; reject unsupported Web overrides explicitly.
- Qualify native EmbeddingGemma-2 text embeddings with 768-dimensional output.
- Document a fresh macOS SwiftPM bootstrap for generated deployment-target
  mismatches with Apple companions.

## 0.13.2

- Report recursive chat-template failures as `LlamaInferenceException`
  instead of `StackOverflowError` on VM and JavaScript
  ([#1112](https://github.com/leehack/llamadart/issues/1112)).
- Accept tool input schema string length and array item bounds of 2000,
  matching the shipped llama.cpp runtime
  ([#1116](https://github.com/leehack/llamadart/issues/1116)).
- Keep unfinished Ministral-format reasoning out of reply text when generation
  stops or is cancelled ([#886](https://github.com/leehack/llamadart/issues/886)).
- Cancelling inside a Hermes tool call keeps only preceding answer text;
  legacy tools preserve completed calls before an unfinished call with
  `finishReason: tool_calls`
  ([#887](https://github.com/leehack/llamadart/issues/887)).
- Honor `enableThinking: false` for renamed native LiteRT-LM Qwen 3 bundles
  with a canonical Qwen 3 `chatTemplate` override or identifying metadata
  ([#901](https://github.com/leehack/llamadart/issues/901)).

* Aligned the default WebGPU bridge assets to `v0.1.59`, unchanged from 0.13.1:
  they embed llama.cpp `v0.6.0`, are qualified against native `v0.6.0`, and
  keep Web/native llama.cpp `v0.6.0@d81235049384534c167caea52b85a694f6103d14`
  parity with native pin `v0.6.0-3`; Web LiteRT-LM is
  `@litert-lm/core@0.18.0`. Immutable Web asset manifest:
  `f823b10417b212ff1f66aa1c46bf78af7d9c393497dfcf0fa3a4f77adeb260eb`.

## 0.13.1

- With `llamadart_native_tag` or `llamadart_native_repository` set, the build
  hook keeps the release's `SHA256SUMS` beside the cached archive and verifies
  a cached archive against it without network access, so offline builds work
  again. When it cannot fetch `SHA256SUMS`, the build fails with
  `NativeArchiveDigestException` naming where to pre-seed it
  ([#1040](https://github.com/leehack/llamadart/issues/1040)).
- Apple builds in a pub workspace now find the member app that depends on the
  llama.cpp, LiteRT-LM or stable_diffusion companion, so they check and link
  it as outside a workspace instead of bundling the hook's Apple assets beside
  it; members with different companions get a build warning
  ([#1098](https://github.com/leehack/llamadart/issues/1098)).
- `cancelGeneration()` during a Web generation now ends the stream normally,
  as on native, instead of throwing `LlamaInferenceException`: on the WebGPU
  worker path, which rejects with an `AbortError`, and on LiteRT-LM Web, whose
  pending stream read rejects. Observers report the run as cancelled
  ([#875](https://github.com/leehack/llamadart/issues/875)).
- Fix `getPerformanceContext()` decode and prompt-eval times on a native
  runtime without the llamadart exit-teardown exports (`v0.5.0` or older),
  where an asynchronous GPU backend such as Metal counted its work as sampling
  time and decode speed read about 10x too high
  ([#671](https://github.com/leehack/llamadart/issues/671)).
- A negative `ModelParams.gpuLayers` now means all layers on every runtime,
  as in llama.cpp, exactly like `ModelParams.maxGpuLayers`. Native llama.cpp
  now also offloads the KV cache and reports the GPU backend instead of
  `CPU`, LiteRT-LM under `ComputeDevice.auto` uses its GPU backend instead
  of the CPU, and the Web applies its GPU safety caps and CPU fallback
  ([#920](https://github.com/leehack/llamadart/issues/920)).
- Report `responseFormat` JSON schemas the grammar converter cannot represent,
  such as an untyped property, a non-local `$ref` or one nested too deeply for
  the stack, as `LlamaUnsupportedException`, and cyclic or other non-JSON
  schemas as `LlamaArgumentException`, instead of `StateError` or a stack
  overflow. A combined tool or schema grammar that llama.cpp would refuse to
  load, such as about 2000 Hermes schema tools, is rejected with
  `LlamaUnsupportedException` before generation instead of a sampler
  initialization failure
  ([#584](https://github.com/leehack/llamadart/issues/584),
  [#1093](https://github.com/leehack/llamadart/issues/1093)).
- Send tool results back on Gemma 2/3/3n and legacy Mistral templates, which
  failed with `Conversation roles must alternate user/assistant/...`: when a
  template that rejects the `tool` role fails such a request, it is rendered
  again with each run of results as one user turn and the earlier calls as
  JSON in the model turn
  ([#885](https://github.com/leehack/llamadart/issues/885)).
- Start a LiteRT-LM generation requested right after a cancel, on native and
  Web, once the cancelled run stops, instead of failing with a wrapped
  `StateError` (`generation is already in progress`). An overlap with a
  running generation that was not cancelled now throws `LlamaStateException`
  ([#656](https://github.com/leehack/llamadart/issues/656)).

* Aligned the default WebGPU bridge assets to `v0.1.59`, unchanged from 0.13.0:
  they embed llama.cpp `v0.6.0`, are qualified against native `v0.6.0`, and
  keep Web/native llama.cpp `v0.6.0@d81235049384534c167caea52b85a694f6103d14`
  parity; Web LiteRT-LM is `@litert-lm/core@0.18.0`. Immutable Web asset
  manifest:
  `f823b10417b212ff1f66aa1c46bf78af7d9c393497dfcf0fa3a4f77adeb260eb`.

## 0.13.0

- Pair this release with Apple companions `llamadart_llama_cpp_flutter`,
  `llamadart_litert_lm_flutter` and `llamadart_stable_diffusion_flutter`
  `0.13.0`, which link native runtimes `v0.6.0-3`, `v0.18.0-1` and `v0.2.0-3`,
  respectively.

- **Behavior change:** Apple companion versions now share the core
  `MAJOR.MINOR`, starting at `0.13.0`, with independent patch versions. Each
  companion depends on `llamadart` within its core minor
  (`'>=0.13.0 <0.14.0'`), so pub refuses a mismatched companion and core
  instead of the iOS or macOS build failing, and the Apple build error or
  warning for a mismatched or older llama.cpp companion names that minor,
  such as `^0.13.0`. Apps that take `llamadart` from a path or git checkout
  add it under `dependency_overrides`
  ([#857](https://github.com/leehack/llamadart/issues/857)).
- **Behavior change:** LiteRT-LM caps each cache directory's GPU program cache
  files at 1 GiB by default
  (`ModelParams.defaultLiteRtLmMaxProgramCacheBytes`), pruning least recently
  modified files first before each engine create, so an existing oversized
  cache is pruned on the first create after upgrading. An explicit
  `liteRtLmMaxProgramCacheBytes` now bounds the directory total instead of
  each file; pass `ModelParams.unlimitedLiteRtLmProgramCacheBytes` (`-1`) to
  keep every file. Engines sharing a cache directory no longer delete the
  program caches of a model another one is running, and
  `liteRtLmCacheDir: ':nocache'` no longer creates a directory, which failed
  the load on Windows ([#552](https://github.com/leehack/llamadart/issues/552)).
- Add `ToolDefinition.fromJsonSchema` for owned, validated tool input schemas,
  with explicit errors for unsupported constraints, formats and runtimes
  ([#1007](https://github.com/leehack/llamadart/issues/1007)).
- **Behavior change:** `ToolParam` tool grammars are stricter: GLM-4.5, Laguna
  and Hunyuan V3 integer parameters reject fractions, `ToolParam.nullType`
  accepts only `null`, and Gemma 2/3 multi-tool grammars require the
  `{"tool_call": ...}` wrapper. Open JSON Schema objects, including
  `responseFormat` schemas, no longer accept a declared property through the
  extra-property slot unless the declared names exceed the grammar size budget.
- **Behavior change:** a `ToolChoice.required` reply cut short by a cancel or
  `maxTokens` ends with `stop` or `length` and no tool calls instead of
  throwing `StateError`; other output a PEG parser cannot parse, including in
  `ChatTemplateEngine.parse`, throws `LlamaInferenceException`
  ([#890](https://github.com/leehack/llamadart/issues/890)).
- **Behavior change:** on native llama.cpp, a runtime missing an mtmd function,
  with no complete fallback mtmd library, fails image and audio requests, and
  `supportsVision`, with `LlamaUnsupportedException` naming the function and
  pinned runtime
  ([#640](https://github.com/leehack/llamadart/issues/640)).
- **Behavior change:** on Web, `SpeechToTextEngine.load`,
  `TextToSpeechEngine.load` and `LlamaEngine.setModel` with a projector report
  progress from 0 to 1, as `DecisionEngine.load` does
  ([#903](https://github.com/leehack/llamadart/issues/903)).
- On macOS x86_64, LiteRT-LM GPU requests fail up front with
  `LlamaUnsupportedException`, and LiteRT-LM is no longer reported or selected
  as GPU there ([#711](https://github.com/leehack/llamadart/issues/711)).
- With `llamadart_litert_lm_flutter` `0.0.15`, the macOS build only warns to
  upgrade the companion instead of claiming the app needs the LiteRT-LM build
  phase ([#1064](https://github.com/leehack/llamadart/issues/1064)).
- `WebGpuLlamaBackend(bridgeScriptUrl: ...)` loads the bridge in dart2js
  builds ([#735](https://github.com/leehack/llamadart/issues/735)).
- The image model memory check treats a GPU reporting 0 bytes free, as Vulkan
  does over budget, as having no free GPU memory: loads warn and, on Linux,
  are refused above system memory
  ([#980](https://github.com/leehack/llamadart/issues/980)).
- `LlamaEngine.getPerformanceContext()` returns null after a generation
  cancelled before it reached the backend, instead of the previous request's
  counters ([#677](https://github.com/leehack/llamadart/issues/677)).
- Clearer errors: a chat template that fails to render names its source
  ([#820](https://github.com/leehack/llamadart/issues/820)), a
  `SpeechToTextEngine` attached to a disposed `LlamaEngine` reports the
  disposal ([#924](https://github.com/leehack/llamadart/issues/924)), and an
  `ImageGenerationEngine.load` SHA-256 mismatch names the main file by
  position, not its path or URL
  ([#907](https://github.com/leehack/llamadart/issues/907)).

* Aligned the default WebGPU bridge assets to `v0.1.59`, unchanged from 0.12.2:
  they embed llama.cpp `v0.6.0`, are qualified against native `v0.6.0`, and
  keep Web/native llama.cpp `v0.6.0@d81235049384534c167caea52b85a694f6103d14`
  parity; Web LiteRT-LM is `@litert-lm/core@0.18.0`. Immutable Web asset
  manifest:
  `f823b10417b212ff1f66aa1c46bf78af7d9c393497dfcf0fa3a4f77adeb260eb`.

## 0.12.2

- Pair this release with Apple companions `llamadart_llama_cpp_flutter`
  `0.0.23`, `llamadart_litert_lm_flutter` `0.0.16` and
  `llamadart_stable_diffusion_flutter` `0.0.3`, which link native runtimes
  `v0.6.0-3`, `v0.18.0-1` and `v0.2.0-3`, respectively.

- The default llama.cpp runtime is now `leehack/llamadart-native@v0.6.0-3`,
  whose Apple frameworks declare their minimum OS version (iOS 16.4, macOS
  13.3) ([#1037](https://github.com/leehack/llamadart/issues/1037)).
- Flutter iOS and macOS apps that keep `llamadart_llama_cpp_flutter` `0.0.22`
  (native `v0.6.0-2`, the same binaries) still build, with a warning to depend
  on `^0.0.23` for the frameworks' minimum OS version metadata. Any other
  mismatched companion still fails the build, and the error names the
  companion version to depend on
  ([#1063](https://github.com/leehack/llamadart/pull/1063)).
- The default LiteRT-LM runtime is now `leehack/litert-lm-native@v0.18.0-1`,
  whose macOS runtimes are arm64 only. Universal Flutter macOS apps with
  `llamadart_litert_lm_flutter` now launch on Intel Macs and under Rosetta
  instead of aborting; LiteRT-LM throws `LlamaUnsupportedException` on x86_64
  macOS ([litert-lm-native#72](https://github.com/leehack/litert-lm-native/issues/72)).
- The build hook verifies every llama.cpp archive it downloads or reuses from
  its cache against a pinned SHA-256, or the release's `SHA256SUMS` when
  `llamadart_native_tag` or `llamadart_native_repository` overrides the
  release. A mismatched cached archive is downloaded again; a fresh download
  that does not match fails the build with `NativeArchiveDigestException`
  ([#1015](https://github.com/leehack/llamadart/issues/1015)).
- A `.litertlm` bundle in a directory the process cannot write, such as an
  iOS app bundle, no longer fails GPU engine creation on iOS and Linux when
  `liteRtLmCacheDir` is unset: the GPU engine reuses caches already there or
  runs without them ([#976](https://github.com/leehack/llamadart/issues/976)).
- Image generation on Metal: `ImageModelParams.vaeDirectConvolution: true`
  throws `LlamaUnsupportedException` at load on iOS instead of returning
  corrupt images ([#1044](https://github.com/leehack/llamadart/issues/1044)),
  and after a failed command buffer generation says the model must be
  reloaded and fails later generations on that engine with the same message
  ([#1045](https://github.com/leehack/llamadart/issues/1045)).
- A model cache directory that cannot be created, such as an unwritable
  `ModelLoadOptions.cacheDirectory`, throws `LlamaModelException` naming the
  directory instead of a raw `FileSystemException`
  ([#894](https://github.com/leehack/llamadart/issues/894)). A download that
  fails TLS certificate verification says so in its `LlamaModelException`,
  and TLS certificate and handshake failures are no longer retried
  ([#978](https://github.com/leehack/llamadart/issues/978)).
- A `ModelResolver` that maps a remote source to a local mirror file now
  loads it when the download options set `cacheDirectory`, credentials or
  other download-only options, instead of throwing
  `LlamaUnsupportedException`
  ([#897](https://github.com/leehack/llamadart/issues/897)).
- `ModelParams.loras` with more than one adapter or a scale other than 1.0
  throws `LlamaUnsupportedException` before any adapter downloads when the
  model loads in LiteRT-LM, by backend, format or `.litertlm` extension
  ([#891](https://github.com/leehack/llamadart/issues/891)).
- The chat example no longer sends its stored Min-P to text to speech when
  the loaded runtime does not support Min-P
  ([#747](https://github.com/leehack/llamadart/issues/747)).

* Aligned the default WebGPU bridge assets to `v0.1.59`, unchanged from 0.12.1:
  they embed llama.cpp `v0.6.0`, are qualified against native `v0.6.0`, and
  keep Web/native llama.cpp `v0.6.0@d81235049384534c167caea52b85a694f6103d14`
  parity; Web LiteRT-LM is `@litert-lm/core@0.18.0`. Immutable Web asset
  manifest:
  `f823b10417b212ff1f66aa1c46bf78af7d9c393497dfcf0fa3a4f77adeb260eb`.

## 0.12.1

- Pair this release with Apple companions `llamadart_llama_cpp_flutter`
  `0.0.22`, `llamadart_litert_lm_flutter` `0.0.15` and
  `llamadart_stable_diffusion_flutter` `0.0.3`, which link native runtimes
  `v0.6.0-2`, `v0.18.0` and `v0.2.0-3`, respectively.

- Flutter macOS apps with `llamadart_litert_lm_flutter` now load LiteRT-LM on
  CPU and GPU from their own bundle, so sandboxed, copied and distributed apps
  work without a build phase; pair it with companion `0.0.15`, which embeds
  the macOS runtime
  ([#1029](https://github.com/leehack/llamadart/issues/1029)).

* Aligned the default WebGPU bridge assets to `v0.1.59`, unchanged from 0.12.0:
  they embed llama.cpp `v0.6.0`, are qualified against native `v0.6.0`, and
  keep Web/native llama.cpp `v0.6.0@d81235049384534c167caea52b85a694f6103d14`
  parity; Web LiteRT-LM is `@litert-lm/core@0.18.0`. Immutable Web asset
  manifest:
  `f823b10417b212ff1f66aa1c46bf78af7d9c393497dfcf0fa3a4f77adeb260eb`.

## 0.12.0

- Pair this release with Apple companions `llamadart_llama_cpp_flutter`
  `0.0.22`, `llamadart_litert_lm_flutter` `0.0.14` and
  `llamadart_stable_diffusion_flutter` `0.0.3`, which link native runtimes
  `v0.6.0-2`, `v0.18.0` and `v0.2.0-3`, respectively.

- **Behavior change:** when the app, or any member of its pub workspace,
  depends on llamadart together with `flutter_edge_ai_llama` or
  `flutter_edge_ai_litertlm`, the native build hook bundles llama.cpp only
  unless `llamadart_native_runtimes` names `litert_lm`, and fails the build
  when `litert_lm` is named next to `flutter_edge_ai_litertlm`, which ships the
  same libraries ([Alongside Flutter Edge AI](https://llamadart.leehack.com/docs/platforms/native-build-hooks#alongside-flutter-edge-ai)).

- On an iOS simulator, `GpuBackend.auto` now runs llama.cpp on the CPU, because Metal returns incorrect output there ([#950](https://github.com/leehack/llamadart/issues/950)). An explicit `GpuBackend.metal` or `ComputeDevice.gpu` still uses Metal and logs a warning; iOS devices and macOS are unchanged.

- Android validation builds can retain bounded, identity-checked reports in app-private storage.

- Clarify that native KV-state restoration does not guarantee identical next-token scores or continuation.

- Portable validation launchers can use captured native logs for required GPU qualification.

- Adopt native runtime `v0.6.0-2` and image runtime `v0.2.0-3` for cooperative application shutdown.

- Shut down the Linux chat app’s Flutter engines before process exit, including active model work.

- Wait for llama.cpp and image-generation workers to exit before disposal completes, including concurrent disposal calls.

- Exclude Android Adreno 750 driver `2150604839` from llama.cpp Vulkan loads: automatic selection falls back to CPU with a warning, and an explicit GPU request throws instead of crashing or producing incorrect text.

- Update the default LiteRT-LM runtime to
  `leehack/litert-lm-native@v0.18.0` (upstream LiteRT-LM `v0.18.0`). On the
  macOS GPU backend the program cache of Qwen3 0.6B and Gemma 4 E2B no longer
  grows on every engine create; Qwen3.5 0.8B's still does
  ([#552](https://github.com/leehack/llamadart/issues/552)), and on the GPU
  backend that bundle can still return the prompt instead of an answer on
  later requests to one engine, as in 0.11
  ([#672](https://github.com/leehack/llamadart/issues/672)). The Windows
  bundle adds `webgpu_dawn.dll`, which the GPU accelerator now loads.
- **Behavior change:** with LiteRT-LM `v0.18.0`, a `ModelParams.chatTemplate`
  on a Qwen 3 `.litertlm` text bundle receives each message's `content` as a
  list of `{"type": "text", "text": ...}` parts instead of a string. A
  template that concatenates `content` as a string fails the generation, and
  one that interpolates it renders the list into the prompt; read both shapes
  ([Chat templates](https://llamadart.leehack.com/docs/guides/chat-template-and-parsing#litert-lm-template-registry)).
  The built-in templates are unaffected.
- Qwen3 0.6B on the LiteRT-LM GPU of an Adreno 750 (Galaxy S24): with
  `v0.18.0` GPU engine creation fails there, where `v0.17.0-8` generated wrong
  text. The first use throws `LlamaUnsupportedException` under
  `ComputeDevice.gpu` and `LlamaModelException` under `auto`. Load that model
  with `ComputeDevice.cpu`, which works on the device; Gemma 4 E2B runs on
  that GPU ([#553](https://github.com/leehack/llamadart/issues/553)).
- **Behavior change:** a LiteRT-LM engine the runtime cannot create under
  `ComputeDevice.auto` or `ComputeDevice.cpu` now throws `LlamaModelException`
  on first use. `LlamaEngine.create`, `generate` and `complete` threw
  `LlamaInferenceException` there, so a `catch` of that type no longer sees
  this failure; `ChatSession`, `tokenize`, `detokenize`, `getTokenCount` and
  `chatTemplate` with a token count threw a `StateError`. With `v0.18.0` that
  includes a `liteRtLmCacheDir` the runtime cannot write, on the CPU backend
  too.
- Fix a LiteRT-LM bundle named without `.litertlm` failing engine creation
  when the process cannot write the bundle's directory and `liteRtLmCacheDir`
  is unset, as on Linux: it now runs without runtime caches
  ([#973](https://github.com/leehack/llamadart/issues/973)).
- LiteRT-LM release sync accepts runtimes built on upstream `v0.17.1` and
  `v0.18.0`, and names the upstream version when its prebuilt-override table
  is behind the runtime owner's
  ([#586](https://github.com/leehack/llamadart/issues/586)).
- Move the documented Web LiteRT-LM default from `@litert-lm/core@0.15.0` to
  `@litert-lm/core@0.18.0`. An app still chooses the module through
  `window.__llamadartLiteRtLmModuleUrl`; the chat app's `web/index.html` and
  the docs now name `0.18.0`.
- Adopt `leehack/stable-diffusion-native@v0.2.0-3` for the opt-in
  `stable_diffusion` image runtime.
- Check the memory of Vulkan GPUs before loading an image model
  ([stable-diffusion-native#9](https://github.com/leehack/stable-diffusion-native/issues/9)).
  On Linux `ImageGenerationEngine.load` refuses, with `LlamaModelException`,
  only a model that does not fit the discrete GPUs plus system memory. A
  model larger than the memory of the GPU that computes still loads, with
  one warning, and runs slower; on Windows it is warned about and never
  refused. Not validated on a physical Vulkan GPU yet;
  `ImageModelParams(checkMemory: false)` skips the check and the warning.
- Quote the errors stable-diffusion.cpp logged in the `LlamaModelException`
  of an image model it cannot load, with files named by role
  ([stable-diffusion-native#3](https://github.com/leehack/stable-diffusion-native/issues/3)).
- Send the image runtime's messages to the `LlamaLogging.configure` handler
  at the configured levels, after each load and generation. The runtime no
  longer prints ggml's device messages to stderr: at the default level
  `none` it logs nothing.
- Update the default llama.cpp runtime to
  `leehack/llamadart-native@v0.6.0-2` (llama.cpp `v0.6.0`), and the
  `llamadart_llama_cpp_flutter` Apple SwiftPM pin with it.
- **Behavior change:** a llama.cpp state file saved by llamadart 0.11.x or
  earlier no longer loads: llama.cpp `v0.6.0` changed the session format.
  On native, `stateLoadFile` throws `LlamaStateException` naming the file's
  format version and the one the runtime reads; evaluate the prompt again and
  save a new file ([Save and restore prompt state](https://llamadart.leehack.com/docs/guides/model-lifecycle#save-and-restore-prompt-state)).
- Fix a C++ exception inside llama.cpp ending the process on native. The
  failed call now throws the typed `LlamaException` of its operation with
  llama.cpp's message, such as `LlamaInferenceException` from `detokenize`
  for a token outside the vocabulary, or from a lazy-grammar trigger pattern
  that is not a regular expression. A context the failed call left undefined
  then throws `LlamaStateException` until its model is loaded again
  ([llamadart-native#102](https://github.com/leehack/llamadart-native/issues/102)).
- Android llama.cpp Vulkan: the 8-token text-prompt decode cap now applies
  only on a GPU whose subgroup size llama.cpp `v0.6.0` mis-tiles (16, or below
  8) or cannot be read. Other GPUs decode a text prompt in full micro-batches
  ([#948](https://github.com/leehack/llamadart/issues/948)).
- llama.cpp Vulkan needs Vulkan 1.2 from the loader and the GPU driver. When
  the Vulkan GPU a load would run on reports less, `ComputeDevice.gpu` now
  throws `LlamaUnsupportedException` naming the GPU and both versions, and
  `ComputeDevice.auto` loads the model on the CPU with a warning, instead of
  starting a driver llama.cpp cannot use; a load with other usable GPUs
  leaves that one out
  ([#782](https://github.com/leehack/llamadart/issues/782)).
* Aligned the default WebGPU bridge assets to `v0.1.59`: they embed llama.cpp
  `v0.6.0`, are qualified against native `v0.6.0`, and keep Web/native
  llama.cpp `v0.6.0@d81235049384534c167caea52b85a694f6103d14` parity; Web
  LiteRT-LM is `@litert-lm/core@0.18.0`. Immutable Web asset manifest:
  `f823b10417b212ff1f66aa1c46bf78af7d9c393497dfcf0fa3a4f77adeb260eb`.
- **Behavior change:** chat content keeps the whitespace that ends a reply,
  as llama.cpp's `llama-server` does. `LlamaEngine.create`, `ChatSession` and
  `ChatTemplateEngine.parse` trimmed it in every chat format except Gemma 4,
  so the text before a caller stop sequence lost a trailing space or newline:
  `alpha ` before the stop `cedar17` came back as `alpha`
  ([#951](https://github.com/leehack/llamadart/issues/951)). A reply the model
  ends with a newline now keeps it, as does a JSON-mode reply where the
  grammar allows whitespace after the value (`createStructuredJson` and
  `LlamaStructuredOutput.parse` still decode it); trim replies you compare
  exactly. `ChatSession` and its tool loop store assistant turns in `history`
  without that whitespace, so the next prompt is unchanged.
- Fix a process abort on an image with more tokens than the context's
  micro-batch when the projector's images are decoded with non-causal
  attention (Gemma 3 and Gemma 4 other than E2B and E4B, among others): the
  prompt now throws `LlamaInferenceException` naming the
  `ModelParams.microBatchSize` it needs. With default batch sizes that is an
  image above 512 tokens. A context whose batch equals its micro-batch still
  decodes such an image in several batches, and now logs a warning that this
  can reduce accuracy
  ([#958](https://github.com/leehack/llamadart/issues/958)).
- **Behavior change:** `all` in `llamadart_native_runtimes` now includes the
  opt-in `stable_diffusion` image runtime, so `llamadart_native_runtimes: all`
  ships GGUF, `.litertlm` and image generation together. An app that already
  sets `all`, or a list containing it, downloads 14.7 to 15.6 MB more per
  target, or 25.8 to 27.8 MB for the Vulkan build Linux and Windows use by
  default, and grows by about 37 MB as measured on macOS arm64 and Android
  arm64. android-x64 and Windows arm64 publish no image runtime and skip it
  with a warning. A Flutter iOS or macOS app skips it with a build warning
  unless `llamadart_stable_diffusion_flutter` is a dependency; a pub
  workspace member, whose user-defines live in the workspace root pubspec, is
  not recognised as one and bundles it. Leaving the key unset, or setting
  `both`, still bundles only `llama_cpp` and `litert_lm`
  ([#856](https://github.com/leehack/llamadart/issues/856)).
- **Behavior change:** an image or audio part of a chat request to a GGUF
  model takes the place it has in its message, as llama.cpp's `llama-server`
  renders it ([#964](https://github.com/leehack/llamadart/issues/964)). For
  Qwen3.5 and Qwen2.5-Omni it was attached before the whole prompt, and for
  GLM-OCR it was wrapped in the image start and end tokens twice, so prompts
  for media turns of these models change. A chat template no longer writes
  its own text for a media part: Qwen's `Picture N: ` under `add_vision_id`,
  the Kimi-K2 wrapper, Reka's run of image tokens and Cohere's
  `<|IMG_PATCH|>` are gone, as on `llama-server`. A placeholder string that
  a chat message quotes (`<img>`, `<image>`, `[IMG]`, `<__media__>`) is text
  instead of a part. Where the runtime would still read such a string as a
  part, it reaches the model with a zero-width space (U+200B) after its
  first character, which the model may repeat in its answer: a quoted
  `<__media__>` in `create` on native; every placeholder the bridge
  rewrites in `create` on Web; and every placeholder `generate` reads in the
  prompt `chatTemplate` returns for messages with media and in `create` on
  a custom backend without `BackendChatPromptGeneration`, which
  `package:llamadart/backend.dart` now exports. A prompt written for
  `generate` keeps its placeholders, and `chatTemplate` output for messages
  without media is unchanged.
- On native llama.cpp, image or audio input that the loaded projector has no
  encoder for throws `LlamaUnsupportedException` naming the encoder, where
  `create` and `generate` threw `LlamaInferenceException`. A chat template
  that raises or has invalid syntax throws `LlamaInferenceException` with the
  template's message instead of a raw `Exception`
  ([#963](https://github.com/leehack/llamadart/issues/963)).
- Fix LiteRT-LM bundles whose own chat template reads message content as a
  string, such as `Qwen3.5-0.8B_int8.litertlm` builds from before September
  2026. With LiteRT-LM `v0.18.0` a template that interpolates the content put
  a serialized `[{"text": ..., "type": "text"}]` list into every prompt, so
  repeated requests degraded sooner than with `v0.17.0-8`; one that
  concatenates it failed every request; one that only handles a string
  rendered empty messages. Native platforms now give such a template the text
  again. Not covered: Web, and templates in the runtime's single-turn
  `is_appending_to_prefill` form, for which a warning is logged
  ([#991](https://github.com/leehack/llamadart/issues/991), [Chat templates](https://llamadart.leehack.com/docs/guides/chat-template-and-parsing#litert-lm-template-registry)).

## 0.11.1

- Give a chat template that reads content part lists but rejects image and
  audio parts the media marker in its text instead of failing in the
  template, and render a video part in a `chatTemplate` prompt as the media
  marker on any template when the messages hold no image or audio part
  ([#959](https://github.com/leehack/llamadart/issues/959)). Beside an image
  or audio part, a template that is given typed content parts still receives
  the video part ([#963](https://github.com/leehack/llamadart/issues/963)).
- Fix a possible llama.cpp crash when an image or audio part of a multimodal
  request fails to load while later parts remain, and native memory leaked
  when a backend is disposed with a context still open or an embedding fails
  because the model reports no embedding size
  ([#947](https://github.com/leehack/llamadart/issues/947),
  [#610](https://github.com/leehack/llamadart/issues/610)).
- Fix Qwen 3 chat and tool-result history with LiteRT-LM runtimes that
  normalize message content to arrays.
- Work around wrong llama.cpp Vulkan output on some Android GPUs for prompts
  over 32 tokens (seen on a Pixel 9 Pro, Mali-G715): an Android Vulkan
  context now decodes a text prompt in micro-batches of at most 8 tokens
  unless `ModelParams.microBatchSize` is set
  ([#948](https://github.com/leehack/llamadart/issues/948)). Only text-prompt
  decoding is covered: prompts with image or audio input, embeddings, decision
  models, text-to-speech and speculative-decoding verification batches are
  not, so speculative decoding can still produce wrong output on an affected
  GPU.
- Document that a Flutter macOS app that quits without disposing its engines
  still exits cleanly, and why disposing them in `onExitRequested` is still
  recommended ([#826](https://github.com/leehack/llamadart/issues/826)).
* Aligned the default WebGPU bridge assets to `v0.1.54`, unchanged from 0.11.0:
  they embed llama.cpp `v0.5.0`, are qualified against native `v0.5.0`, and keep
  Web/native llama.cpp `v0.5.0@7fe450e19305b828c199d602c23a8337aaa1f03b` parity
  and Web `@litert-lm/core@0.15.0`. Immutable Web asset manifest:
  `8a9f83c15035eeb034a6563e6f753382d7d7f9be81503ef76902138da7841176`.

## 0.11.0

- Fix a Flutter macOS app aborting in ggml-metal when it quits while a
  llama.cpp model loads or after a hot restart during a load, and a Dart
  program aborting when it ends or kills an isolate during a load: the
  llama.cpp runtime now frees the models, contexts, projectors and decision
  heads still allocated at exit
  ([#813](https://github.com/leehack/llamadart/issues/813),
  [llamadart-native#96](https://github.com/leehack/llamadart-native/issues/96)).
  A native host's C `exit()` while a llama.cpp call is running is not covered.
- Update the default llama.cpp runtime to `leehack/llamadart-native@v0.5.0-2`,
  a rebuild of llama.cpp `v0.5.0` whose Apple XCFramework carries a privacy
  manifest (File Timestamp, reason `C617.1`). A runtime older than `v0.5.0-1`
  keeps the previous exit behavior and logs a warning at the first model load.
- Fix a process aborting when a Dart program dies of an error, or a Flutter
  macOS app quits or hot restarts, while an image model loads or generates,
  and a macOS Metal process aborting in ggml-metal when a native host exits
  with an image model loaded: the stable_diffusion runtime now records
  progress instead of calling back into Dart, and frees the image models
  still allocated at exit
  ([stable-diffusion-native#10](https://github.com/leehack/stable-diffusion-native/issues/10)).
  Image progress events now arrive up to about 50 ms after the runtime
  reports them. A quit during an image generation waits for the generation
  to finish; dispose the engine first to quit at once.
- Update the stable_diffusion runtime to
  `leehack/stable-diffusion-native@v0.2.0-1`, a rebuild of the same
  stable-diffusion.cpp commit whose Apple XCFramework carries a privacy
  manifest (File Timestamp, reasons `C617.1` and `3B52.1`). Image generation
  needs this runtime or a later one.
- Documented that LiteRT-LM on iOS has run on a device only on iOS 18.3.2;
  iOS 16.4 remains the declared, untested deployment floor
  ([#831](https://github.com/leehack/llamadart/issues/831)).
- Documented Apple privacy manifests: one reaches an app inside a companion
  package's XCFramework, never through the hook path, and an app whose
  llama.cpp or stable_diffusion runtime has none declares File Timestamp
  reason `C617.1` (plus `3B52.1` for stable_diffusion) itself.
- Flutter iOS and macOS apps pair core `0.11.0` with
  `llamadart_llama_cpp_flutter` `0.0.21`, `llamadart_litert_lm_flutter`
  `0.0.13` and `llamadart_stable_diffusion_flutter` `0.0.2`, which link the
  runtimes this release pins; an older llama.cpp or stable_diffusion companion
  fails the Apple build.

- Adopt LiteRT-LM `v0.17.0-7` with provider-free iOS artifacts; Gemma FST
  constrained decoding remains unavailable on iOS.
- Update the default LiteRT-LM runtime to `leehack/litert-lm-native@v0.17.0-8`.
  Its iOS SwiftPM frameworks carry Apple privacy manifests (File Timestamp
  `C617.1` and `3B52.1`, System Boot Time `35F9.1`, User Defaults `CA92.1`);
  an app that runs LiteRT-LM on the hook path declares them itself.
- Fix Android LiteRT-LM GPU engines keeping their graphics memory after
  deletion, which got an app killed after one or two model reloads on a
  Galaxy S24
  ([litert-lm-native#59](https://github.com/leehack/litert-lm-native/issues/59)).
- Documented that LiteRT-LM's default GPU selection on Android generates wrong
  text for Qwen3 0.6B on Adreno 750; load it with `ComputeDevice.cpu`
  ([#553](https://github.com/leehack/llamadart/issues/553)).
- Documented that llama.cpp Vulkan on Android is experimental and
  device-dependent, with known failures on Pixel 9 Pro, Galaxy A53 and Galaxy
  S24; `auto` stays on the CPU
  ([#948](https://github.com/leehack/llamadart/issues/948)).

- LiteRT-LM release sync can remove an obsolete iOS provider target from modern
  Swift packages while preserving required macOS runtime libraries.
- Reentrant engine disposal now shares one teardown and immediately reports
  disposed state, including calls from logging or backend cancellation hooks.
- Native requests, generation, and speech synthesis fail promptly when their
  worker exits unexpectedly, allowing disposal to finish.

- Native recurrent and hybrid models reject nonzero speculative rollback
  capacity before context creation, avoiding runtime graph-budget aborts.
- Native embeddings reject inputs that exceed a required one-pass micro-batch,
  avoiding non-causal attention aborts and incorrect MEAN/CLS pooled vectors.
- Disposal now cancels model and LoRA downloads started by deprecated
  `loadModelSource`, without waiting for resolution that ignores cancellation
  ([#895](https://github.com/leehack/llamadart/issues/895)).
- Prevented execution of incomplete parallel tool-call replies when generation
  reaches a reported limit; the tool loop rolls back the whole turn.
- Automatic tool loops now reject pinned LiteRT-LM native and Web runtimes
  before generation because they cannot report token-limit truncation reliably;
  manually managed completion remains available ([#919](https://github.com/leehack/llamadart/issues/919)).
- Web GGUF completions preserve runtime limits as `length`, so tool loops
  report `truncated` and roll back cut-off turns; typed Web speech recognition
  raises a runtime truncation error with the partial transcript.

- Redacted known URL secrets repeated in model filenames from download
  cancellation messages.
- Model unload, replacement, and disposal now report interrupted tool loops as
  cancelled, preserving partial answers and rolling back unfinished turns.
- Projector loads now reject model changes during loading instead of reporting
  success after the model has been unloaded.
- **Fixed:** URL-valued `ModelSource.path` diagnostics redact credentials and
  signed queries while preserving the loading path and cache identity
  ([#846](https://github.com/leehack/llamadart/issues/846)).
- Fixed LiteRT-LM speech recognition startup failures hanging indefinitely;
  failed workers now release their resources and allow another attempt.
- Kept cancelled replies out of reset chats and rolled back turns cancelled
  before any output; structured JSON cancellation now reports a state error.
  A model change during draft-model resolution also rolls back the turn;
  resets during context preparation preserve the replacement conversation.
- Redacted URL credentials and signed query strings from redirected download
  failures, download snapshots and invalid model-source errors, including
  slashless URLs; LiteRT-LM Web model names reject decoded URL delimiters.

- `LlamaEngine.load(LlamaModel(source, projector:), params:, download:,
  onProgress:, store:)` creates an engine and loads a model with its
  projector in one atomic call, and `setModel` loads or replaces the model of
  an engine: the loaded model keeps serving until every new file has
  downloaded, except on the Web, where the runtime unloads it before it
  fetches the new one. A class that `implements LlamaEngine` must add
  `setModel`, and an override of `loadMultimodalProjectorSource` its new
  `download` parameter
  ([#846](https://github.com/leehack/llamadart/issues/846)).
- **Deprecated:** `LlamaEngine.loadModel`, `loadModelSource`,
  `loadModelFromUrl` and `loadMultimodalProjector`; use `LlamaEngine.load` or
  `setModel`. `loadMultimodalProjectorSource(options:)` is now `download:`.
  They still work until 1.0
  ([#846](https://github.com/leehack/llamadart/issues/846)).
- **Fixed:** a load checks that it can proceed before it downloads:
  `LlamaEngine.load` and `setModel` reject a projector for a LiteRT-LM model
  and `ComputeDevice.npu` for a GGUF first, and the deprecated
  `loadModelSource` throws for an already loaded engine first
  ([#846](https://github.com/leehack/llamadart/issues/846)).
- **Fixed:** `LlamaEngine.dispose()` stops the downloads of a running
  `setModel` at once, and `unloadModel()` and `dispose()` stop a
  `loadMultimodalProjectorSource` download instead of waiting for it; the
  load throws `LlamaStateException`
  ([#895](https://github.com/leehack/llamadart/issues/895),
  [#896](https://github.com/leehack/llamadart/issues/896)).
- **Behavior change:** on the Web, a `ModelSource.path` loads as a URL
  relative to the document, or as a `blob:` URL, for models, projectors, LoRA
  adapters and draft models; it used to throw `LlamaUnsupportedException`
  ([#846](https://github.com/leehack/llamadart/issues/846)).
- **Fixed:** the llama.cpp WebGPU bridge resolves a relative model,
  projector, LoRA or draft model URL against the document, as LiteRT-LM Web
  does; its worker resolved one against `webgpu_bridge/`, so the fetch
  failed ([#846](https://github.com/leehack/llamadart/issues/846)).
- A local `ModelSource.path` whose file name holds `%2F` or `%5C`, or whose
  directory is named `%2e` or `%2e%2e`, loads through `LlamaEngine.load`,
  `setModel`, `loadMultimodalProjectorSource`, `setLoraSource`,
  `ModelParams.loras`, draft models and the image, decision and speech
  engines' `load` ([#846](https://github.com/leehack/llamadart/issues/846)).
- **Breaking (Preview):** `ImageGenerationEngine.generate` returns
  `Future<ImageGenerationTask>`; await it before reading `events` or calling
  `cancel` ([#850](https://github.com/leehack/llamadart/issues/850)).
- **Breaking:** `ImageGenerationTask`, `SpeechToTextTask` and
  `TextToSpeechTask` no longer report a failure as an error on `events`; read
  it from `done`, or from the new `result`, which returns the result or
  throws the failure, or `LlamaStateException` when the task is cancelled
  ([#850](https://github.com/leehack/llamadart/issues/850)).
- **Fixed:** `SpeechToTextTask.cancel()` stops only that recognition; it no
  longer cancels chat and other requests on the same `LlamaEngine`
  ([#850](https://github.com/leehack/llamadart/issues/850)).
- `ModelParams.device` (`ComputeDevice`) selects the device for every
  runtime: `auto` keeps each runtime's default, and an explicit `cpu`, `gpu`
  or `npu` runs there or throws `LlamaUnsupportedException` instead of
  falling back to another device
  ([#849](https://github.com/leehack/llamadart/issues/849)).
- **Deprecated:** `ModelParams.liteRtLmBackend`, `LiteRtLmBackendPreference`
  and `LiteRtLmBackend(preferredBackend:)`; use `ModelParams.device`. They
  still work until 1.0
  ([#849](https://github.com/leehack/llamadart/issues/849)).
- **Behavior change:** `DecisionModelParams(device: ComputeDevice.gpu)` runs
  the encoder on a GPU, Vulkan on Android, or throws
  `LlamaUnsupportedException` from the encoder load; it ran on the CPU on
  Android and threw before loading where GPU modules load with the model
  ([#849](https://github.com/leehack/llamadart/issues/849)).
- **Behavior change:** `LlamaEngine` loads run `ModelParams.validate()` before
  any download or native call, so an invalid combination throws
  `LlamaArgumentException` instead of `LlamaModelException`
  ([#849](https://github.com/leehack/llamadart/issues/849)).
- **Breaking:** `ModelParams.validate()` throws `LlamaArgumentException`,
  `ModelDownloadController` throws `LlamaArgumentException` or
  `LlamaStateException`, and Web backend calls before a model load throw
  `LlamaStateException`, instead of `ArgumentError` or `StateError`; a failed
  load's `details` is now the cause's message instead of a `{type, message}`
  map, and the not-ready error names `LlamaEngine.load` and `setModel`
  ([#843](https://github.com/leehack/llamadart/issues/843)).
- **Deprecated, behavior change:** `sourceLangCode` and `targetLangCode` on
  `LlamaEngine.create`, `createStructuredJson`, `chatTemplate` and
  `BackendNativeChatGeneration.generateChat`; pass
  `chatTemplateKwargs: {'source_lang_code': 'en', 'target_lang_code': 'ko'}`,
  which TranslateGemma templates now read, as llama.cpp does. A custom
  `BackendNativeChatGeneration` now gets the codes from `LlamaEngine` only in
  `chatTemplateKwargs`
  ([#853](https://github.com/leehack/llamadart/issues/853)).
- **Deprecated:** `LlamaLogging.configure(level:, nativeLevel:, handler:)`
  replaces `LlamaEngine.configureLogging` and the engine's `setLogLevel`,
  `setDartLogLevel` and `setNativeLogLevel`; levels are now library-wide, so
  the last call wins and reaches every running engine's worker, including the
  default native backend's ([#845](https://github.com/leehack/llamadart/issues/845)).
- **Deprecated:** speech engines follow the shared engine pattern:
  `SpeechToTextEngine.load(SpeechToTextModel(...))` and
  `TextToSpeechEngine.load(TextToSpeechModel(...))` download every
  `ModelSource` and own what they load, `attach(engine, adapter:)` borrows a
  loaded `LlamaEngine`, `dispose()` cancels the running task, and
  `transcribeOnce` and `synthesizeOnce` return the final result. Adapters
  (`Qwen3AsrAdapter`, `LiteRtLmAsrAdapter`, `Qwen3TtsAdapter`, or your own
  `SpeechToTextPromptAdapter`) replace `SpeechToTextModelProfile`,
  `TextToSpeechModelProfile`, the `modelProfile` constructors and
  `SpeechToTextEngine.liteRtLm`, which keep working until 1.0
  ([#848](https://github.com/leehack/llamadart/issues/848)).
- **Breaking:** `SpeechToTextEngine` gains `dispose()`, `isDisposed`,
  `adapter` and `transcribeOnce`, and `TextToSpeechEngine` gains `dispose()`,
  `isDisposed`, `adapter` and `synthesizeOnce`, so a class that `implements`
  either must add them
  ([#848](https://github.com/leehack/llamadart/issues/848)).
- **Breaking:** `DecisionEngine.load(DecisionModel(encoder:, head:,
  config:), params:, download:, onProgress:)` loads a decision model from
  `ModelSource`s into an engine it owns, atomically, and `dispose()` frees it
  all; `DecisionEngine.attach(engine, head:, config:)` adds a head to a loaded
  `LlamaEngine`; decision engines report an instance `capabilities`. The
  `String`-path `load(engine, headPath:, configPath:)` is removed; use
  `attach` ([#847](https://github.com/leehack/llamadart/issues/847)).
- **Breaking (Preview):** image generation follows the shared engine
  pattern: `ImageGenerationEngine.load(ImageGenerationModel(source,
  components: [...]), params:, download:, onProgress:)` downloads every
  `ModelSource` into the model cache, with combined progress, cancellation
  and cache reuse, and detects each file's role from its header. Generation
  settings move to `ImageGenerationRequest`. `download`'s bearer token and
  headers never reach more than one origin: such remote files throw
  `LlamaArgumentException`. The model presets, `ImageGenerationModelFamily`,
  `ImageGenerationModelFiles`, `ImageGenerationDefaults`,
  `ImageGenerationOptions` (now `ImageModelParams`, and the engine's `options`
  getter `params`), `ImageGenerationDevice` (now `ComputeDevice`) and `String`
  paths are removed; `MIGRATION.md` maps each former preset to its files and
  request settings
  ([#883](https://github.com/leehack/llamadart/issues/883)).
- **Breaking:** `LlamaEngine.dispose()` is idempotent and terminal, like
  every other engine's: each call returns the same future, and afterwards
  loads, requests and `DecisionEngine.attach` throw `LlamaStateException`
  while `capabilities` reports the engine as disposed. `getBackendName`,
  `getAvailableBackends`, `isGpuSupported`, `getVramInfo`, `listGpuDevices`
  and `getResolvedGpuLayers` used to answer after `dispose()` and now throw
  `LlamaStateException` too. A load running when it is called throws
  `LlamaStateException`, and its model is unloaded. `LlamaEngine` gains
  `isDisposed`, so a class that `implements` it must add it
  ([#851](https://github.com/leehack/llamadart/issues/851)).
- **Breaking (Preview):** `ImageGenerationEngine.capabilities` is async, and
  `ImageGenerationEngine.runtimeCapabilities()` is removed; use
  `checkRuntime()`. `ImageGenerationCapabilities` and `DecisionCapabilities`
  implement `EngineCapabilities`
  ([#851](https://github.com/leehack/llamadart/issues/851)).
- **Behavior change:** `LlamaEngine.supportsVision` and `supportsAudio` report
  what `capabilities` reports: true for a LiteRT-LM bundle that takes media
  directly, and false instead of throwing when the runtime cannot probe the
  projector ([#851](https://github.com/leehack/llamadart/issues/851)).
- **Behavior change:** `responseFormat` maps with an unknown `type` or
  key, such as `json_shema` or a misspelled `schma`, now throw
  `LlamaUnsupportedException` before generation instead of generating
  unconstrained output; a `null`-valued key counts as absent
  ([#836](https://github.com/leehack/llamadart/issues/836),
  [#864](https://github.com/leehack/llamadart/issues/864)).
- `ChatSession.create` takes `responseFormat`, and the new
  `ChatSession.createStructuredJson` decodes the reply. A turn that fails or
  is cancelled before its first chunk, such as a strict format on LiteRT-LM,
  removes its user message from the history, and one cancelled or failing
  mid-stream keeps the partial reply, so alternating-role templates keep
  working
  ([#836](https://github.com/leehack/llamadart/issues/836),
  [#864](https://github.com/leehack/llamadart/issues/864)).
- `LlamaCompletionChunk.model`, observer model names and load logs report
  `llama_model`, and web LiteRT-LM omits `general.name`, when a URL's last
  path segment repeats its userinfo credential; web LiteRT-LM
  `litert_lm.model_url` shows a relative URL as given and a `blob:` or `data:`
  URL as its scheme ([#822](https://github.com/leehack/llamadart/issues/822)).
- `loadModelSource` throws `LlamaUnsupportedException` instead of
  `ArgumentError` for a local path whose file name holds `%2F` or `%5C` or
  whose directory is named `%2e` or `%2e%2e`; `loadModel` still loads it
  ([#822](https://github.com/leehack/llamadart/issues/822)).
- **Behavior change:** on Android and iOS, the default model cache is now
  `llamadart/models` in the app's cache directory instead of the temporary
  directory, which Android empties on every app update and iOS purges; add
  `DefaultModelDownloadManager.globalCacheDirectory` to move every default
  download ([#838](https://github.com/leehack/llamadart/issues/838)).
- Native `LlamaBackend()` picks llama.cpp or LiteRT-LM from the model file's
  header, not its extension, so extensionless downloads load in the right
  runtime and mislabelled files throw `LlamaModelFormatException`; name a Web
  URL's format with `ModelSource.url(..., format: ModelFormat.liteRtLm)`
  ([#837](https://github.com/leehack/llamadart/issues/837)).
- Add `LlamaEngine.runtime` and `LlamaEngine.capabilities`, one snapshot of
  what the loaded model's runtime supports: image and audio input,
  embeddings, multi-turn chat, tools, structured output, grammars, every
  sampling control including `penalty`, stream batching and speculative
  strategies. Native LiteRT-LM reports the image, audio and speculative
  decoding support the bundle declares, best-effort ([litert-lm-native#60](https://github.com/leehack/litert-lm-native/issues/60)),
  and a request the runtime then fails for lack of one throws
  `LlamaUnsupportedException` naming it instead of an opaque error.
  `backendGenerationCapabilities` is deprecated; on native LiteRT-LM it now
  reports `streamBatching` and, for bundles without a declared drafter, no
  speculative strategy ([#841](https://github.com/leehack/llamadart/issues/841)).
- Read completions without `choices.first.delta`: `chunk.text`,
  `chunk.thinking`, `chunk.toolCalls` and a typed `chunk.finishReason`
  (`LlamaFinishReason`); `stream.text()`, `stream.textDeltas()` and
  `stream.collect()` (a `LlamaCompletion` with assembled tool calls and an
  assistant `message`); and the one-shot `engine.complete(messages)` and
  `session.send('...')`
  ([#840](https://github.com/leehack/llamadart/issues/840)).
- `session.sendWithTools(text, tools: ...)` and `completeWithTools(parts,
  ...)` run the model's tool calls with each `ToolDefinition.handler`,
  concurrently for parallel calls, until it answers, and return a
  `LlamaToolLoopResult` whose `stopReason` also reports `maxRounds`,
  unhandled calls, context overflow, a reply cut off at `maxTokens`
  (`truncated`, rolled back) and cancellation
  ([#842](https://github.com/leehack/llamadart/issues/842)).
- **Breaking:** `ChatSession` gains `createStructuredJson`, and `LlamaEngine`
  gains `runtime`, `capabilities`, `setLoraSource` and `removeLoraSource`, so
  a class that `implements` either must add them.
- **Breaking:** `ToolDefinition.handler` is nullable, so tools the app runs
  itself can leave it out; code that calls `tool.handler(params)` must check
  it for null first ([#842](https://github.com/leehack/llamadart/issues/842)).
- `GenerationGrammarTrigger.typed(type: GrammarTriggerType.word, ...)`
  replaces the raw-`int` constructor, now deprecated; an unknown raw trigger
  type throws `LlamaUnsupportedException` on llama.cpp instead of being
  ignored ([#844](https://github.com/leehack/llamadart/issues/844)).
- LoRA adapters (`setLoraSource`, `removeLoraSource`,
  `LoraAdapterConfig.source`), speculative draft models
  (`SpeculativeDecodingConfig.draftModel`, `withDraftModel`,
  `withDraftModelDownload`) take a `ModelSource`, so they download and cache
  like models, and `LiteRtLmAsrRuntimeConfig.source` takes local
  `ModelSource` files
  ([#852](https://github.com/leehack/llamadart/issues/852)).
- **Deprecated:** the `String` path forms of LoRA adapters, speculative draft
  models and LiteRT-LM ASR files
  ([#852](https://github.com/leehack/llamadart/issues/852)).
- **Breaking:** `package:llamadart/llamadart.dart` is the app API. The raw
  ffigen bindings move to `package:llamadart/llama_cpp_bindings.dart` (native
  only, outside semantic versioning), and the custom-backend SPI moves to the
  new `package:llamadart/backend.dart`: every `Backend*` type except
  `BackendPerfContextData` and `BackendTextToSpeechModel`, `LiteRtLmBackend`,
  `LiteRtLmRuntimeClient`, `LiteRtLmRuntimeMetrics`, `LiteRtLmRuntimeResult`,
  `LiteRtLmAsrRuntimeSession`, `LiteRtLmAsrPushResult`,
  `LiteRtLmAsrProcessResult` and `LiteRtLmAsrProcessState`. The app API now
  exports `TemplateToolCallSerialization`
  ([#355](https://github.com/leehack/llamadart/issues/355)).
- **Breaking:** the `LlamaEngine` text-to-speech and decision hooks,
  `modelHandle` and `contextHandle` move to the `LlamaEngineBackendHooks`
  extension in `package:llamadart/backend.dart`, so neither a subclass nor an
  `implements LlamaEngine` fake can override them; fake a backend that
  implements `BackendTextToSpeech` or `BackendDecision` instead
  ([#355](https://github.com/leehack/llamadart/issues/355)).
- **Breaking:** the deprecated `LiteRtLmBenchmarkClient`,
  `LiteRtLmBenchmarkMetrics`, `LiteRtLmBenchmarkResult`,
  `LiteRtLmRuntimeClient.conversationTokenCount` and
  `LiteRtLmRuntimeClient.replaceConversationWithClone` are removed
  ([#355](https://github.com/leehack/llamadart/issues/355)).
* Aligned the default WebGPU bridge assets to `v0.1.54`, unchanged from 0.10.0:
  they embed llama.cpp `v0.5.0`, are qualified against native `v0.5.0`, and keep
  Web/native llama.cpp `v0.5.0@7fe450e19305b828c199d602c23a8337aaa1f03b` parity
  and Web `@litert-lm/core@0.15.0`. Immutable Web asset manifest:
  `8a9f83c15035eeb034a6563e6f753382d7d7f9be81503ef76902138da7841176`.

## 0.10.0

- Add the `llamadart_stable_diffusion_flutter` `0.0.1` companion package:
  Flutter iOS and macOS apps that add it link the image generation runtime
  through Swift Package Manager, since App Store Connect rejects the iOS
  framework the build hook bundles. Without it the hook keeps bundling the
  runtime, and an iOS build reports an Xcode build warning (shown by Xcode and
  `xcodebuild`, not by plain `flutter build` or `flutter run` output).
- Image generation now runs on the x86_64 iOS simulator, with the runtime
  updated to `leehack/stable-diffusion-native@v0.2.0`.
- Label image generation a Preview in the README and docs, and list each
  image preset's model license.
- **Behavior change:** render and parse llama.cpp chat with
  `ModelParams.chatTemplate`, which `engine.create` and
  `engine.chatTemplate` ignored in favor of the GGUF template
  ([#710](https://github.com/leehack/llamadart/issues/710)).
- **Breaking:** WebGPU `LlamaBackend.applyChatTemplate` now throws
  `LlamaUnsupportedException` for a template override it cannot render
  ([#710](https://github.com/leehack/llamadart/issues/710)).
- **Behavior change:** report only the last path segment of the model
  source, such as `qwen.gguf`, in `LlamaCompletionChunk.model` instead of
  the full local path or redacted URL; compare it with the file name, not
  the path. Like `LlamaOperation.model`, it now reads local paths as paths
  and leaves out `data:` and `blob:` URLs
  ([#718](https://github.com/leehack/llamadart/issues/718)).
- Strip URL userinfo, query and fragment from the `litert_lm.model_url`
  metadata that web LiteRT-LM reports.
- **Behavior change:** load models whose local path contains `%`, such as
  `C:\models\qwen 100%.gguf`, or whose URL file name decodes to one, instead
  of throwing `ArgumentError`; `loadModelSource` and `ModelCacheEntry` keep
  `%` in local and cache paths literal instead of percent-decoding them into
  another file ([#819](https://github.com/leehack/llamadart/issues/819)).
- Fix Dart programs aborting on macOS Metal when `main` returns or throws
  with a model, decision head or image model still loaded; llamadart now
  frees them as the program ends, and an undisposed `ImageGenerationEngine`
  no longer keeps the program running
  ([#613](https://github.com/leehack/llamadart/issues/613)).
- Fix the Flutter chat example aborting on macOS when quit while an image or
  chat model was still being freed, such as right after leaving the image
  screen ([#796](https://github.com/leehack/llamadart/issues/796)).
- Document disposing engines from `AppLifecycleListener.onExitRequested`,
  since quitting a macOS app with a Metal model loaded aborts the process.
- Ship agent skills for coding agents covering setup, chat and streaming,
  tool calling, web, Flutter apps, multimodal input, embeddings, speech, LoRA
  adapters, decision models and image generation; install them with
  `dart run skills@ get`.
- Add an observability guide and tested optional OpenTelemetry example with Langfuse and Grafana recipes.
- **Behavior change:** apply `ModelParams.loras` at model load on native
  llama.cpp and WebGPU, where they were silently ignored; an adapter that
  cannot be applied, or WebGPU bridge assets before `v0.1.54`, fail the load
  instead ([#709](https://github.com/leehack/llamadart/issues/709)).
- **Breaking:** throw `LlamaUnsupportedException` instead of
  `LlamaModelException` when native or web LiteRT-LM rejects a `ModelParams`
  field, including more than one LoRA adapter or a non-default adapter
  scale.
- Add an experimental opt-in `stable_diffusion` native runtime
  (stable-diffusion.cpp) to `llamadart_native_runtimes` for image
  generation; it is never bundled by default or by `all`, and
  `llamadart_stable_diffusion_backends` picks its CPU or Vulkan build on Linux
  and Windows ([#777](https://github.com/leehack/llamadart/issues/777)).
- Add experimental on-device image generation, `ImageGenerationEngine`, on
  the opt-in `stable_diffusion` runtime: SDXS and SD-Turbo presets,
  phase-labelled progress, cancellation, PNG output, a memory check before
  loading, and an output size that defaults to the model's
  (`ImageGenerationDefaults.width` and `height`); not available on the web
  ([#778](https://github.com/leehack/llamadart/issues/778)).
- Add an experimental image-generation screen to the Flutter chat example,
  with SDXS and SD-Turbo downloads
  ([#776](https://github.com/leehack/llamadart/issues/776)).
- Add `ImageGenerationEngine.warmUp`, which compiles the GPU pipelines of
  the first image ahead of time, and document first-image latency per
  platform ([#790](https://github.com/leehack/llamadart/issues/790)).
- Add `ImageGenerationEngine.checkRuntime`, which probes the image runtime
  without blocking the calling isolate; `load` now probes the same way, and
  the chat example uses it, so the first probe's Metal library compile (about
  16 s with an empty shader cache) no longer freezes the UI
  ([#798](https://github.com/leehack/llamadart/issues/798)).
- **Breaking:** throw `LlamaUnsupportedException` for image or audio parts
  sent to a GGUF model with no projector loaded: native llama.cpp answered
  from the text alone, and WebGPU threw an untyped error surfaced as
  `LlamaInferenceException`. Native llama.cpp and LiteRT-LM also throw it
  for `LlamaImageContent.url`.
- Add `LlamaEngine.supportsEmbeddings`. Native llama.cpp embeddings of an
  encoder-decoder model now throw `LlamaUnsupportedException`, and input
  longer than the context throws `LlamaInferenceException`, instead of a
  plain `Exception`.
- Fix the example chat app failing every later turn after its projector is
  cleared or a text-only model is loaded in a conversation that already has
  images or audio; earlier media is now left out of the prompt, and
  unsupported-input errors are shown instead of generic reload advice.
- Fix the example chat app garbling a streaming reply when mmproj is loaded
  manually mid-reply; the reply is now stopped first, as with Stop.
- Name the missing Visual C++ runtime DLLs when native llama.cpp fails to
  load on Windows, and the missing Vulkan loader or NVIDIA driver when a
  Windows GPU module does not load; the docs now list the latest Visual C++
  v14 Redistributable as a Windows requirement
  ([#788](https://github.com/leehack/llamadart/issues/788)).
- Add desktop-model settings to experimental image generation: an `llm`
  text-encoder file for Z-Image and Qwen-Image, sampler, scheduler and flow
  shift on the request and model defaults, and flash attention and direct
  VAE convolutions, which now turn on automatically where measured faster or
  smaller, such as a 1024x1024 Vulkan decode in about 1 s instead of up to
  56 s in stable-diffusion.cpp's native CLI
  ([#802](https://github.com/leehack/llamadart/issues/802)).
- Name the missing VAE or text-encoder role when stable-diffusion.cpp
  rejects a split image checkpoint, instead of a generic load error
  ([#802](https://github.com/leehack/llamadart/issues/802)).
- Check image models against Metal's recommended GPU working set on macOS,
  skip the check on Vulkan instead of comparing with host memory, and raise
  the estimate's fixed allowance to 512 MiB so it covers measured CPU peaks
  ([#802](https://github.com/leehack/llamadart/issues/802)).
- Check image models on Android against the larger of `MemAvailable` and
  half of physical memory less the app's own memory, so SD-Turbo loads on
  8 GB phones whose `MemAvailable` leaves out memory the system frees on
  demand; 6 GB phones still refuse it in most cases
  ([#792](https://github.com/leehack/llamadart/issues/792)).
- Add experimental desktop image presets: SDXL-Lightning, FLUX.1-schnell,
  SD 3.5 Large Turbo and Z-Image-Turbo, which generate and warm up at
  1024x1024 when a request or `warmUp` leaves the size unset, and the basic
  example's image CLI downloads them
  ([#802](https://github.com/leehack/llamadart/issues/802)).
* Aligned the default WebGPU bridge assets to `v0.1.54`, unchanged from 0.9.0:
  they embed llama.cpp `v0.5.0`, are qualified against native `v0.5.0`, and keep
  Web/native llama.cpp `v0.5.0@7fe450e19305b828c199d602c23a8337aaa1f03b` parity
  and Web `@litert-lm/core@0.15.0`. Immutable Web asset manifest:
  `8a9f83c15035eeb034a6563e6f753382d7d7f9be81503ef76902138da7841176`.
