# Changelog archive

Releases of `llamadart` before 0.10.0, moved verbatim from
[`CHANGELOG.md`](../CHANGELOG.md) to keep the published changelog under
pub.dev's 256 KiB limit.

## 0.9.0

- Document generic JSON tool calling as an intentional fallback, including
  its prompt and model-reliability limits; runtime behavior is unchanged
  ([#755](https://github.com/leehack/llamadart/issues/755)).
- Load Qwen3.5-0.8B on the Web CPU (WebAssembly) backend at the default
  `contextSize` using smaller processing batches, while preserving
  full-context defaults for unknown models, including embedding models
  ([#752](https://github.com/leehack/llamadart/issues/752)).
- Report a failed Web model load on a page without cross-origin isolation as
  `LlamaModelException` with its real cause, not as a COOP/COEP
  worker-thread error; only a real worker-thread failure still names COOP/COEP
  ([#753](https://github.com/leehack/llamadart/issues/753)).
- Log a Dart warning when an explicit `preferredBackend` GPU module is not
  bundled and the model loads on CPU instead, as happens for `cuda` with the
  default Windows bundle; the native runtime docs now say when CUDA is bundled
  ([#756](https://github.com/leehack/llamadart/issues/756)).
- Fix the `llamadart_server` example exiting at startup on Windows; it stops
  on Ctrl+C there, and on SIGINT or SIGTERM elsewhere
  ([#757](https://github.com/leehack/llamadart/issues/757)).
- Accept MP3 and FLAC bytes, as well as WAV, for Qwen3-ASR speech to text on
  Web ([#723](https://github.com/leehack/llamadart/issues/723)).
- Apply `presencePenalty`, `minP` and `thinkingBudget`, and runtime LoRA
  adapters (`setLora`, `removeLora`, `clearLoras`), on WebGPU with bridge
  assets whose capability probes report them; other assets still reject them
  ([#722](https://github.com/leehack/llamadart/issues/722)).
- Run speculative decoding on WebGPU with bridge assets whose capability
  probe reports the strategy, and report each runtime's strategies in
  `backendGenerationCapabilities.speculativeDecodingStrategies`; other assets
  still reject it ([#722](https://github.com/leehack/llamadart/issues/722)).
- Reject a non-zero `GenerationParams.minP` on WebGPU when the bridge lacks
  Min-P, with `LlamaUnsupportedException` instead of ignoring it, and ignore a
  stop sequence equal to a `preservedTokens` entry there, as native llama.cpp
  does ([#661](https://github.com/leehack/llamadart/issues/661)).
- Add `LlamaEngine.backendGenerationCapabilities`, which reports whether the
  loaded runtime applies `presencePenalty`, `minP` and `thinkingBudget`; the
  example chat app uses it to send Min-P and enable its slider only where
  supported ([#661](https://github.com/leehack/llamadart/issues/661)).
- Return a DeepSeek V3 forced-open thought that never closes as reasoning, as
  llama.cpp does with the DeepSeek V3.1 template, instead of as content with
  its tool calls ([#743](https://github.com/leehack/llamadart/issues/743)).
- Keep escaped `\n` and `\r` in Qwen3-Coder XML reasoning, as llama.cpp does
  with the Qwen3.5 template; before, they became line breaks unless a tool
  call ended the thought
  ([#743](https://github.com/leehack/llamadart/issues/743)).
- Stream content and reasoning with the whitespace the non-streamed parse
  keeps, with or without tools, so streamed answers and `ChatSession` history
  no longer start with the blank lines after `</think>`. Only whitespace at
  either end, and text that may be a tag or tool-call opening, waits for more
  output, so reasoning still streams token by token. Without tools, Hermes,
  DeepSeek R1, Qwen3-Coder XML and the other formats the template engine
  guide lists also drop a start tag repeated at the start of a forced-open
  thought, as the parse does. The guide lists the exceptions
  ([#754](https://github.com/leehack/llamadart/issues/754)).
- Stream content that equals the non-streamed parse for Qwen3-Coder XML,
  Mistral Nemo and 15 more tool-call formats, and for output parsed with a PEG
  parser, so text before a tool call no longer carries the tool-call envelope
  into streamed content or `ChatSession` history. Content and reasoning are
  trimmed as for Hermes, and text after a call arrives at the end of the
  stream. See the template engine guide for the formats and exceptions
  ([#732](https://github.com/leehack/llamadart/issues/732)).
- Stream Hermes-format content that equals the non-streamed parse, so text
  before a tool call no longer carries the `<tool_call>` envelope into
  streamed content or `ChatSession` history; only a possible envelope opening
  and trailing whitespace wait for more output. With tools, streamed content
  is now trimmed as the parse trims it, and text the parse keeps after a tool
  call, including a malformed envelope, arrives at the end of the stream.
  Streamed reasoning, and so `ChatSession` thinking, is trimmed per thought as
  the parse trims it. The exception is a forced-open thought that never
  closes and starts with whitespace: the parse keeps it untrimmed, but it
  streams without its leading and trailing whitespace, so
  `"  \n Hello there.  \n\n"` streams as `"Hello there."`. Before, it streamed
  as the parse gives it, except for some thoughts containing a backslash,
  depending on chunking. After a forced-open
  thought, text after a tool call arrives at the end
  ([#701](https://github.com/leehack/llamadart/issues/701)).
- Throw `LlamaModelException` when a WebGPU model load fails with a bridge
  error that has no specific mapping, and `LlamaInferenceException` or
  `LlamaStateException` for such Web embedding, next-token scoring and state
  errors, with URL credentials and signed query values redacted from the
  details and the load-failure console log
  ([#704](https://github.com/leehack/llamadart/issues/704)).
- Keep URL credentials, signed query values and fragments out of
  `LlamaEngine` model and projector load errors and logs and the `model` field
  of completion chunks for every URL form, including scheme-relative
  `//user:pass@host/...` URLs and relative paths with a query, and out of
  native model download errors. A projector load error that is not a
  `LlamaException` now throws `LlamaModelException`. The `details` of a
  model or projector load failure is now a `{type, message}` map instead of
  the original error, and a native download that fails with a network error
  carries the error text as a `String` in `details`
  ([#704](https://github.com/leehack/llamadart/issues/704)).
- Keep the text after a U+0000 in native llama.cpp tokenization, embeddings
  and generation prompts instead of dropping it
  ([#608](https://github.com/leehack/llamadart/issues/608)).
- Make `DecisionEngine.load` throw `LlamaStateException` when another model is
  loaded while it runs, even under the same backend handle
  ([#626](https://github.com/leehack/llamadart/issues/626)).
- Bound speech validation pack memory by a footprint counter instead of the
  resident set: `phys_footprint` on macOS and iOS, `RssAnon` plus `RssShmem`
  plus `VmSwap` on Linux and Android, read after `malloc_trim(0)` where the C
  library provides it (glibc, not Android), and `PrivateUsage` plus
  `SharedCommitUsage` on Windows (`PrivateUsage` alone on builds without it).
  Evicting file-backed pages, such as the
  mmapped weights, compressing memory under pressure, or glibc keeping freed
  memory across reloads no longer fails `peak_memory_bound` without memory
  growth, and each report names its counter
  ([#633](https://github.com/leehack/llamadart/issues/633),
  [#762](https://github.com/leehack/llamadart/issues/762)).
- Fail speech validation `leak_slope_bound` when the least-squares footprint
  slope over cleanup cycles 1-8 exceeds 7 MiB per cycle; it failed only when
  every cycle grew by more than 7 MiB, and passed leaks of 16 MiB per reload
  ([#762](https://github.com/leehack/llamadart/issues/762)).
- Detect chat template capabilities with llama.cpp's probes, and give
  templates that read only typed content text parts, as llama.cpp does:
  SmolVLM prompts keep the message text, Ministral 3 renders an image
  followed by a reasoning-only turn as llama-server does, TranslateGemma 2B
  keeps the text next to an image, and Kimi-K2 tool results after an image
  are plain text
  ([#720](https://github.com/leehack/llamadart/issues/720)).
- Use the LFM2 format for LFM2.5 templates that list tools without
  `<|tool_list_start|>`, as llama.cpp does, so LFM2.5-1.2B-Instruct and
  LFM2.5-1.2B-Thinking tool prompts drop the stray "Respond in JSON format"
  instruction ([#716](https://github.com/leehack/llamadart/issues/716)).
- Report per-request usage on WebGPU with the newly pinned bridge assets
  `v0.1.54`, on the final `create` chunk and to observers
  ([#696](https://github.com/leehack/llamadart/issues/696)).
- Give assistant turns that hold only tool calls or only reasoning empty
  content instead of `null` in chat templates, as llama.cpp does: QwQ-32B
  renders them instead of throwing, and LFM2 and Devstral prompts drop a stray
  `null` or `<function text>`
  ([#715](https://github.com/leehack/llamadart/issues/715)).
- Pass Map and List tool results as compact JSON text to LFM2, gpt-oss, Solar
  Open, Ministral, DeepSeek V3 and TranslateGemma templates too, instead of
  Python-style or spaced text
  ([#717](https://github.com/leehack/llamadart/issues/717)).
- Pass earlier tool-call arguments as JSON objects to templates that read them
  as objects, as llama.cpp does, so Qwen3, Ministral, Devstral, gpt-oss and
  similar prompts format them with the template's own JSON spacing
  ([#702](https://github.com/leehack/llamadart/issues/702)).
- Require `dinja` 1.2.0, so more chat prompts match llama.cpp: `tojson`
  output such as tool declarations uses llama.cpp's spacing, number format
  and non-ASCII text; Qwen3-Coder, GLM-4.6, GLM-4.7-Flash, MiniMax-M2,
  Nemotron-3-Nano, Command R7B, Cohere2 MoE and Ling 3.0 prompts lose stray
  indentation; Functionary v3.1 adds no tool instructions without tools;
  Granite 3.3 spells out the month in its date; Hunyuan Hy3 keeps the system
  prompt first instead of merging it into the user turn; and Bielik 11B v3
  tool-call turns without text render instead of throwing.
- Count generated tokens with an empty text piece in llama.cpp
  `getPerformanceContext()` `evalTokens` and `sampleCount` without speculative
  decoding, as the speculative path already did
  ([#706](https://github.com/leehack/llamadart/issues/706)).
- Report per-request token usage and timings on the final `create` chunk as
  `LlamaCompletionChunk.usage` on native llama.cpp
  ([#696](https://github.com/leehack/llamadart/issues/696)).
- Add `LlamaEngine(observers: ...)`, which reports chat and text completions,
  embeddings and model loads, with their usage, to tracing and metrics code
  ([#696](https://github.com/leehack/llamadart/issues/696)).

* Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@v0.5.0` (llama.cpp `v0.5.0`) with Apple companion
  `0.0.20`, regenerated matching Dart FFI bindings, refreshed the `llamadart_llama_cpp_flutter` Apple SwiftPM
  checksum, and aligned current README/website native override docs.

- Add `LlamaEngine.scoreNextToken(...)` for next-token log-probabilities on
  native llama.cpp and WebGPU bridge assets `v0.1.52+`, matching llama-server
  `n_probs`; check
  `supportsNextTokenScoring` first
  ([#694](https://github.com/leehack/llamadart/issues/694)).
- Add `example/laya_command_bar`, a Flutter text field that reshapes into a
  reminder, message, calculation or other command as you type, read by a
  Laya decision model, by EmbeddingGemma and labelled examples, or by small
  LLMs' next-token scores, including the decision model decider-2b.

- Throw `LlamaModelException` when native llama.cpp cannot find or load a
  multimodal projector, and `LlamaUnsupportedException` when the runtime lacks
  the mtmd functions; `LlamaEngine.supportsAudio` also throws the latter.
  Speech-to-text capabilities now say when no projector is loaded, using the
  new `LlamaEngine.hasMultimodalProjector`
  ([#325](https://github.com/leehack/llamadart/issues/325)).

- Honour `LlamaEngine.cancelGeneration()` issued right after listening to a
  `create`, `generate` or `ChatSession.create` stream, before it reaches the
  backend, instead of running the whole generation
  ([#602](https://github.com/leehack/llamadart/issues/602)).
- Cancel an active text-to-speech synthesis on `LlamaEngine.unloadModel()` and
  `dispose()` instead of waiting for it to finish
  ([#628](https://github.com/leehack/llamadart/issues/628)).
- Cancel an active Qwen3-ASR transcription on `LlamaEngine.unloadModel()` and
  `dispose()` instead of completing it with the transcript cut at the unload
  ([#670](https://github.com/leehack/llamadart/issues/670)).
- Send LiteRT-LM tool calls and tool results in the runtime's own message
  format, so Gemma 4 reads tool output and Qwen3 tool histories no longer
  fail
  ([#681](https://github.com/leehack/llamadart/issues/681)).
- Start a native llama.cpp generation requested right after a cancel once the
  cancelled run stops, instead of failing with `generation is already in
  progress`. An overlap with a running generation that was not cancelled now
  throws `LlamaStateException`
  ([#655](https://github.com/leehack/llamadart/issues/655)).
- Render Qwen3 prompts as llama.cpp does: an earlier assistant tool-call
  turn without reasoning no longer gets an empty `<think>` block
  ([#691](https://github.com/leehack/llamadart/issues/691)).
- Require `dinja` 1.1.0. Its Jinja string comparison makes three more chat
  templates render as llama.cpp does: MiniMax-M1 adds no empty
  system block for an empty or whitespace-only system message; NVIDIA
  Nemotron Nano v2 drops the blank line before a tool call, the blank lines
  before its tool instructions when tools come with an empty or
  whitespace-only system message, and an empty final assistant turn without
  a generation prompt; and Functionary v3.2 tool declarations drop stray
  `// Format=<|NONE|>` lines and spell out nested object parameters
  ([#351](https://github.com/leehack/llamadart/issues/351)).
- Cancel a generation's backend run as soon as its stream subscription is
  cancelled, instead of at its next token, which during prompt evaluation
  meant after the whole prompt. A native llama.cpp generation requested right
  after such a cancel now waits for it instead of throwing
  `LlamaStateException`, and native llama.cpp sees a cancel between text
  prompt micro-batches (`ModelParams.microBatchSize`, 512 tokens by default)
  or, with speculative decoding, between batches (`ModelParams.batchSize`)
  ([#663](https://github.com/leehack/llamadart/issues/663),
  [#660](https://github.com/leehack/llamadart/issues/660)).
- Render every result of a tool message holding several
  `LlamaToolResultContent` parts, as one `tool` message per result like
  llama.cpp, instead of only the first; `LlamaChatMessage.toJson` lists them
  all ([#683](https://github.com/leehack/llamadart/issues/683)).
- Render Gemma 4 tool calls and tool results as llama.cpp does, so Gemma 4
  GGUF models can read tool output
  ([#669](https://github.com/leehack/llamadart/issues/669)).
- Stop a Qwen3-TTS audio decode at its next chunk boundary when native
  text-to-speech is cancelled, instead of finishing the native step in
  progress first. This needs llamadart-native v0.4.1-1 or later; older
  runtimes keep the previous behaviour
  ([llamadart-native#86](https://github.com/leehack/llamadart-native/issues/86),
  [#322](https://github.com/leehack/llamadart/issues/322)).
- Add an experimental `DecisionEngine` for Laya-style decision models (a
  ModernBERT encoder GGUF plus a safetensors head) on native llama.cpp, with
  typed `ChoiceKey`, `ScoreKey` and `NoulKey` questions
  ([#604](https://github.com/leehack/llamadart/issues/604)).
- Add `example/basic_app/bin/llamadart_decision_example.dart`, a console demo
  that triages a support ticket with `DecisionEngine`
  ([#604](https://github.com/leehack/llamadart/issues/604)).
- Add `example/laya_tetris`, a Flutter app in which a Laya decision model
  plays real-time Tetris through `DecisionEngine`
  ([#604](https://github.com/leehack/llamadart/issues/604)).
- Run `example/laya_tetris` on Web through the WebGPU bridge, with a live demo
  at https://leehack-flutter-laya-tetris.static.hf.space.
- Add a notebook in `example/laya_tetris/training/` that fine-tunes a Laya
  decision head for the Tetris example and exports it for `DecisionEngine`
  ([#604](https://github.com/leehack/llamadart/issues/604)).
- Run `DecisionEngine` on WebGPU through the bridge decision API
  (apiVersion 1), which bridge assets `v0.1.47+` include
  ([#604](https://github.com/leehack/llamadart/issues/604)).
- Stop native image and audio requests from seeding the repeat penalty with
  leftover memory, which made output depend on the previous request
  ([#603](https://github.com/leehack/llamadart/issues/603)).
- After a failed native prompt decode, the next `reusePromptPrefix` request no
  longer runs on the wrong KV cache or keeps failing
  ([#601](https://github.com/leehack/llamadart/issues/601)).
- Reject `embed()` and `embedBatch()` on rank-pooled reranker GGUFs with
  `LlamaUnsupportedException` on native, instead of returning memory read
  past llama.cpp's classifier-score buffer
  ([#583](https://github.com/leehack/llamadart/issues/583)).
- Throw `LlamaInferenceException` from native `embed()` and `embedBatch()`
  when input to an encoder-only model or a model without a KV cache (such as
  BERT-family and ModernBERT GGUFs) does not fit one `microBatchSize` pass,
  instead of aborting the process or embedding only the last chunk
  ([#607](https://github.com/leehack/llamadart/issues/607)).
* Aligned the default WebGPU bridge assets to `v0.1.54` for the decision API,
  next-token scoring, presence penalty, Min-P, thinking budgets, runtime LoRA
  adapters, speculative decoding and the Web runtime fixes below; the bridge
  also adds its `supportsCompletionUsage` flag, which llamadart does not use yet
  ([#729](https://github.com/leehack/llamadart/pull/729)). The assets embed llama.cpp `v0.5.0`, are
  qualified against native `v0.5.0`, and keep Web/native llama.cpp
  `v0.5.0@7fe450e19305b828c199d602c23a8337aaa1f03b` parity and Web
  `@litert-lm/core@0.15.0`. Immutable Web asset manifest:
  `8a9f83c15035eeb034a6563e6f753382d7d7f9be81503ef76902138da7841176`.
- On Web, an invalid GBNF grammar now fails generation with a
  `LlamaInferenceException` whose details contain `(invalid grammar)`, and the
  loaded model stays usable, instead of aborting the WebGPU bridge runtime
  ([llama-web-bridge#125](https://github.com/leehack/llama-web-bridge/pull/125)).
- On Web, when a bridge worker fails and the main-thread reload fails too, or
  a replacement worker cannot start, the bridge now forgets the model instead
  of being left broken with a `TypeError`. Later calls fail with
  `No model loaded. Call loadModelFromUrl first.`; call `unloadModel()`, then
  `loadModel()` and any projector again to recover
  ([llama-web-bridge#123](https://github.com/leehack/llama-web-bridge/pull/123),
  [llama-web-bridge#127](https://github.com/leehack/llama-web-bridge/pull/127)).
- On Web, a replacement bridge worker reloads the current model before its next
  request
  ([llama-web-bridge#126](https://github.com/leehack/llama-web-bridge/pull/126)).
- On Web, grammar-constrained generation no longer aborts the bridge runtime
  when top-k or top-p keeps only tokens the grammar rejects; it resamples as
  llama.cpp does, and fails with `Grammar rejected every candidate token` only
  when the grammar cannot continue
  ([llama-web-bridge#118](https://github.com/leehack/llama-web-bridge/pull/118)).
- On Web, an ordinary error from a healthy bridge worker, such as a prompt that
  overflows the context or empty embedding input, is now rethrown with the
  worker kept, instead of moving the session to the main thread for good and
  re-running the request
  ([llama-web-bridge#119](https://github.com/leehack/llama-web-bridge/pull/119),
  [llama-web-bridge#120](https://github.com/leehack/llama-web-bridge/pull/120)).
- Extend the GGUF speech-to-text validation pack with four synthetic edge
  fixtures built in-process, so no extra audio is stored: generated digital
  silence, plus a truncated RIFF, a stereo 44.1 kHz re-encode and a 33-second
  concatenation, the last three derived from the locked `jfk.wav`. Every GGUF
  STT pack run executes the four checks and each one gates `functional_pass`;
  the LiteRT-ASR and TTS packs pass no edge fixtures
  ([#325](https://github.com/leehack/llamadart/issues/325)).
- Raise every `stt`, `tts` and `litert-asr` speech validation pack run from 8
  to 15 lifecycle checks: an immediate cancel, three
  cancel/dispose/load/generate cycles, and bounds that fail the run when a
  cancellation takes over 500 ms to end its task or the peak resident set
  exceeds 1.10x the one sampled after the first generation
  ([#594](https://github.com/leehack/llamadart/pull/594)).
- Add cross-platform validation cases for a cancel issued right after
  listening, a generation requested right after a cancel, an overlapping
  generation, an invalid GBNF grammar and `ToolChoice.auto` on a prompt that
  needs no tool, and run the tool cases on the GGUF chat profiles
  ([#602](https://github.com/leehack/llamadart/issues/602),
  [#655](https://github.com/leehack/llamadart/issues/655),
  [#654](https://github.com/leehack/llamadart/issues/654)).
- Add `decision-gguf-{cpu,metal,vulkan,cuda,webgpu}` validation profiles that
  check `DecisionEngine` token ids, raw logits and answers against the Laya
  0.3.5 reference, plus batching, reload and typed rejections, on desktop,
  mobile, Web WebGPU and GCE CUDA
  ([#604](https://github.com/leehack/llamadart/issues/604)).
- Add a Web-only `chat-gguf-webgpu` validation profile, hash Web validation
  models while they stream so GGUFs over 2 GiB pass preparation, list every
  bundled profile in the validation app, and verify iOS GGUF GPU placement
  from the XCTest console log.
- Run eight cleanup cycles instead of three in every speech validation pack,
  and fail a run whose resident set grows by more than 7 MiB in each of seven
  warm cycles. The 1.10x peak ratio no longer applies on Linux CUDA, where reload
  overhead that levels off failed it without a leak
  ([#686](https://github.com/leehack/llamadart/issues/686)).
- Add GGUF speech validation pack checks: `tts` unloads and disposes the engine
  during a synthesis, cancels one during its audio decode and bounds the
  resident set those checks add, and `stt` must fail with
  `LlamaSpeechTranscriptTruncatedException` at `maxOutputTokens` and at the
  context size. `stt` runs now execute 28 checks and `tts` runs 25
  ([#628](https://github.com/leehack/llamadart/issues/628),
  [#636](https://github.com/leehack/llamadart/issues/636),
  [#322](https://github.com/leehack/llamadart/issues/322)).
- Force greedy `topK: 1` for zero-temperature LiteRT-LM Web generation, matching
  the native clamp
  ([#548](https://github.com/leehack/llamadart/issues/548)).
- Log `Model … loaded from …; native engine creation is deferred until the
  first generation or tokenizer call` instead of `loaded successfully` when
  the native LiteRT-LM backend finishes `loadModel`, since it creates the
  engine lazily
  ([#569](https://github.com/leehack/llamadart/issues/569)).
- Require `dxcompiler.dll` and `dxil.dll` in the Windows x64 LiteRT-LM runtime
  cache and desktop validation bundle checks, matching the hook's v0.17.0-6
  inventory. The runtime does not preload them: Dawn's D3D12 backend loads the
  pair at GPU engine creation
  ([#570](https://github.com/leehack/llamadart/issues/570)).
- Document that Linux llama.cpp loads need the OpenMP runtime
  (`libgomp.so.1`; `libgomp1` on Ubuntu/Debian, `libgomp` on Fedora and Arch)
  and that Linux LiteRT-LM GPU needs a hardware Vulkan ICD: with only Mesa
  llvmpipe the runtime segfaults after model load instead of failing cleanly
  ([llamadart-native#82](https://github.com/leehack/llamadart-native/issues/82),
  [#572](https://github.com/leehack/llamadart/issues/572)).
- Record one startup diagnostic when every candidate of a native backend
  module family fails to load, or when a `ggml`/wrapper symbol is missing from
  both the primary FFI asset and every fallback library. Candidates are named
  by asset URI or file name only and loader errors are classified, never
  quoted, so no directory or loader search path reaches the diagnostic
  ([#416](https://github.com/leehack/llamadart/issues/416)).
- Forward llama.cpp and LiteRT-LM worker-isolate log records to the
  `LlamaEngine.configureLogging` handler. A worker takes the Dart logger level
  when it starts and `LlamaEngine.setDartLogLevel`/`setLogLevel` update a
  running worker; the default `none` sends nothing and `debug` records are
  capped at 1000 per worker. The LiteRT-LM program-cache pruning warnings are
  now ordinary `warn` records gated by that level instead of the native log
  level. Adds `LlamaLogger.level` and the `BackendDartLogLevel` capability
  ([#567](https://github.com/leehack/llamadart/issues/567)).
- Replace the token in `Bearer <token>` and the value in `token=`, `key=`,
  `secret=`, `password=`, `api_key=` and `apikey=<value>` outside HTTP URLs in
  native startup diagnostics with `<redacted-secret>`; URL and
  control-character handling is unchanged
  ([#551](https://github.com/leehack/llamadart/issues/551)).
- Move native release pins (llama.cpp tag, LiteRT-LM tag and per-bundle
  checksums) from `hook/build.dart` into
  `lib/src/hook/native_release_pins.dart`, the only file the pin sync now
  rewrites.
- Add `ModelParams.liteRtLmCacheDir` to choose the native LiteRT-LM runtime
  cache directory and opt-in `ModelParams.liteRtLmMaxProgramCacheBytes`, which
  deletes `*_mldrift_program_cache.bin` files above the cap before each engine
  create and logs a warning per deleted file. Defaults are unchanged: the same
  per-platform directory and no pruning
  ([#552](https://github.com/leehack/llamadart/issues/552)).
- Force greedy `topK: 1` for zero-temperature
  `LiteRtLmRuntimeClient.createConversation` calls, which returned incoherent
  text on the LiteRT WebGPU sampler with the default top-k.
- Keep root-cause native startup diagnostics when the buffer or the rendered
  `startupDiagnostics=[...]` suffix overflows: teardown entries, now prefixed
  `teardown: `, are dropped first, duplicates are recorded once, entries are
  capped at 2048 characters, and each omitted run renders as `...`
  ([#415](https://github.com/leehack/llamadart/issues/415)).
- Skip the Windows altered-search-path preload for wrapper library candidates
  whose absolute path does not exist, so lazy wrapper API lookups no longer
  record a `Failed to preload Windows backend module` startup diagnostic per
  missing candidate
  ([#550](https://github.com/leehack/llamadart/issues/550)).
- Accept `promptTemplate` on the non-native
  `LiteRtLmRuntimeClient.createConversation` placeholder, so callers passing
  it compile for Web as they do on native
  ([#549](https://github.com/leehack/llamadart/issues/549)).
- Cache `TemplateCaps.detect` results in a per-isolate LRU keyed by exact
  template source and bounded at 16 entries, so repeated chat-template renders
  skip both Jinja parses and all four capability probes. Detections in which
  any analysis step failed are not cached and keep logging on every call
  ([#448](https://github.com/leehack/llamadart/issues/448)).
- Detect `supportsTools` and `supportsToolCalls` for chat templates that
  reject two tool calls in one assistant message (Llama 3.2) or a user turn
  directly after a tool call (Ministral 3). The tools capability probe now
  renders a single tool call, and a separate parallel probe clears only
  `supportsParallelToolCalls` when it throws
  ([#557](https://github.com/leehack/llamadart/issues/557)).
- Limit the Ministral tool-call grammar to a single `[TOOL_CALLS]` block unless
  parallel tool calls are enabled; it previously always allowed repeats while
  the parser kept only the first call
  ([#559](https://github.com/leehack/llamadart/issues/559)).
- Limit the Nemotron v3 tool-call grammar (Qwen3-Coder XML format) to a single
  tool call unless parallel tool calls are enabled; it previously always
  allowed repeats while the parser kept only one call
  ([#562](https://github.com/leehack/llamadart/issues/562)).
- Pin the WebGPU model-load retry ladder with browser tests for the ladder
  advance, the wasm64 BigInt restart on wasm32, the restart without the remote
  fetch backend, and forced remote-fetch chunk halving stopping on both its
  ten-restart cap and its 4 KiB minimum chunk, then collapse the duplicated
  attempt thread-count switch into one helper
  ([#361](https://github.com/leehack/llamadart/issues/361)).
- Apply the JSON Schema `pattern` keyword when generating GBNF, for anchored
  patterns built from literals, positive character classes, `(...)` groups
  nested at most 32 deep, grouped alternation and `*`/`+`/`?`/`{m,n}`
  repetition; any other pattern, including deeper nesting, falls back to the
  rule the schema would have produced without it, so `minLength` and
  `maxLength` still apply there. An applied pattern replaces
  `minLength`/`maxLength` as it does in llama.cpp, so a schema carrying both
  `pattern` and `maxLength` is no longer length-bounded. A schema carrying
  `pattern` but no explicit `type` now yields a string rule instead of
  throwing `Unrecognized schema`. Mistral Nemo and Magistral tool-call ids are
  now grammar-constrained to exactly nine alphanumerics
  ([#582](https://github.com/leehack/llamadart/issues/582)).
- Stop a cancelled llama.cpp image or audio prompt at the next prompt chunk,
  or between a media chunk's encode and its embedding decode, instead of after
  the whole prompt is ingested. The native call already running still
  finishes
  ([#599](https://github.com/leehack/llamadart/issues/599)).
- `SpeechToTextEngine` now fails a native Qwen3-ASR transcript that reaches
  the context size or `maxOutputTokens` with
  `LlamaSpeechTranscriptTruncatedException` instead of completing with
  truncated text, and `create()` reports `finishReason: 'length'` when native
  llama.cpp stops at either limit. The chat app caps Qwen3-ASR recordings at
  the validated 30 seconds
  ([#636](https://github.com/leehack/llamadart/issues/636)).
- Stop `ToolChoice.auto` on WebGPU from forcing a tool call: it now skips
  the lazy tool-call grammar and parses tool calls best-effort. WebGPU
  rejects `GenerationParams.grammarLazy` and a non-`root` `grammarRoot` with
  `LlamaUnsupportedException`; backends report this through the new
  `BackendLazyGrammarSupport`
  ([#654](https://github.com/leehack/llamadart/issues/654)).
- Name the CUDA 12 runtime libraries (`libcudart.so.12`, `libcublas.so.12`)
  that the Linux `cuda` backend needs on the default loader path; llamadart
  does not ship them, and validation bundles refuse `LD_LIBRARY_PATH`
  ([#587](https://github.com/leehack/llamadart/issues/587)).
- Remote validation runs resolve `packages/llamadart_validation` before
  building the report, instead of reporting `FAILED` with a null error on a
  fresh checkout. A failed report step is now the run's error, with its exit
  code and a redacted stderr tail
  ([#688](https://github.com/leehack/llamadart/issues/688)).
- Select the devices of an explicit `GpuBackend.metal` or `GpuBackend.hip`
  on llama.cpp: they looked up ggml registries named `Metal` and `HIP`, but
  ggml names them `MTL` and `ROCm`, so loading fell back to automatic device
  selection. A HIP load on a ROCm build now reports its backend as `HIP`
  instead of `CPU`
  ([#611](https://github.com/leehack/llamadart/issues/611)).
- Report a WebGPU model load that fails with `error 138` as the documented
  cross-origin isolation (COOP/COEP) `UnsupportedError`, as
  `thread constructor failed` already was, instead of rethrowing the raw
  bridge error
  ([#598](https://github.com/leehack/llamadart/issues/598)).
- Throw `LlamaModelException` when WebGPU cannot fetch or load a multimodal
  projector, instead of the raw JavaScript error. Its details drop these
  parts of the projector URL the app passed, as written, JSON-escaped,
  percent-encoded or percent-decoded: the userinfo and password, as whole
  tokens of any length; the `?query` and `#fragment`, where they directly
  follow a non-space character; the query and each `&`-separated part that
  contain `=`, as whole tokens; and bare query values and the fragment of 10
  or more characters, as whole tokens. A whole token has no ASCII letter or
  digit directly before or after it. Shorter bare values printed on their
  own, such as the `1` of `?v=1`, stay. Other URLs in the details lose
  userinfo, query and fragment on a best-effort basis
  ([#642](https://github.com/leehack/llamadart/issues/642)).
- Leave no envelope text in the parsed `content` when Qwen2.5 wraps a Hermes
  tool call in double braces (`<tool_call>{{"name": ...}}</tool_call>`, with
  any number of extra closing braces) without a grammar. Calls are extracted as
  before; a double-brace call with other malformed envelope text keeps that
  text. This deliberately differs from upstream llama.cpp, which rejects that
  output and extracts no call
  ([#662](https://github.com/leehack/llamadart/issues/662)).

## 0.8.24

- Align native `leehack/llamadart-native@v0.4.1` on upstream
  `b29c606e28a01b1bc8c1351026a0fa6e616bf6c4`, with matching Dart bindings
  and Apple companion `0.0.19`. This resolves the 0.8.23 grammar limitation:
  native `{2000}` repetitions are accepted again
  ([llamadart-native#76](https://github.com/leehack/llamadart-native/issues/76)).
* Aligned the default WebGPU bridge assets to `v0.1.44` for matching
  Web/native `v0.4.1@b29c606e28a01b1bc8c1351026a0fa6e616bf6c4` parity.
  Immutable Web asset manifest:
  `8d61f453753ac7a7d839ac12318b70986a814748d86029993118c19454293aa9`.
- Update native LiteRT-LM to `v0.17.0-6` with Apple companion `0.0.11`,
  Qwen3 tokenizer compatibility, corrected Linux loading, and explicit Linux
  and Windows GPU selection while retaining CPU defaults. The Windows x64
  runtime bundles `dxil.dll` and `dxcompiler.dll`, which D3D12 GPU engine
  creation requires
  ([litert-lm-native#47](https://github.com/leehack/litert-lm-native/issues/47)).
  Web LiteRT-LM stays at `@litert-lm/core@0.15.0`.
- Preserve required iOS LiteRT-LM provider and Metal plugins, handle dependency
  ordering in companion libraries, and exclude metadata/import archives from
  runtime library inventories.
- Respect greedy sampling for zero-temperature native LiteRT-LM generation.
- Restore native Qwen3 chat text when thinking is disabled and preserve plain
  system instructions when seeding LiteRT-LM conversation history.
- Settle pending LiteRT-LM requests when a worker stops, close response ports,
  and report unverified native cleanup as an error.
- Preserve Unicode when detokenizing native GGUF tokens and suppress caller
  stop markers across chunk boundaries and speculative decoding.
- Restore native Qwen3-ASR file/encoded-byte transcription parity by keeping
  encoded audio out of string chat-template prompts.
- Render typed tool results as JSON text while preserving string results,
  validate Qwen XML argument types against schemas, and reject malformed or
  undeclared tool calls without exposing executable tool deltas.
- Prevent split MiniMax M3 thinking delimiters from leaking into reasoning.
- Discover Windows backend libraries in compiled CLI bundles and provide
  bounded diagnostics for unavailable native thinking-budget helpers.
- Fix fresh macOS Flutter dependency scanning while retaining Apple ABI and
  local-override guards.
- Add locked Gemma 4/Qwen3.5 validation profiles, explicit NPU coverage, and
  opt-in speech and voice-pipeline diagnostics.
- Preserve physical iOS speech-test failure-phase diagnostics and keep
  repository writer checks independent of generated website output.
- Retain open LiteRT-LM qualification gaps: macOS Qwen3.5 GPU reload latency
  ([#521](https://github.com/leehack/llamadart/issues/521)), Gemma exact-history
  behavior ([#513](https://github.com/leehack/llamadart/issues/513)), and
  Qwen3-0.6B arithmetic on Android CPU and iOS CPU/GPU
  ([#509](https://github.com/leehack/llamadart/issues/509)). The affected cases
  remain unqualified; these changes do not resolve the failures or establish
  their remaining owning layer.

## 0.8.23

* Fail Apple builds before native symbol lookup when the resolved llama.cpp
  companion does not match the core native runtime, with an actionable upgrade
  diagnostic instead of allowing ABI-incompatible frameworks.

* Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@v0.4.0`, regenerated matching Dart FFI bindings, refreshed
  the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and
  aligned current README/website native override docs. Updated multimodal calls
  for the matching ABI. Saved native sessions from older runtimes must be
  regenerated. Apple companion `0.0.18` supplies the matching native runtime.

* Aligned the default WebGPU bridge assets to `v0.1.43` for Web/native
  llama.cpp `v0.4.0@5266f24da75dc449bd56cbed7addb9c8e4a6a73e` parity.
  Web `@litert-lm/core@0.15.0` and native LiteRT pins are unchanged. Immutable
  manifest: `111eefc3588842cebfe665b363378edca34924764610263e1eda5280dfcfaa27`.

* Known upstream limitation: llama.cpp v0.4.0 can reject large grammar
  repetitions, such as `root ::= "a"{2000}`. The post-v0.4.0 upstream
  correction is tracked in `llamadart-native#76` and is not part of this release.

## 0.8.22

* Updated `llamadart_llama_cpp_flutter` to `0.0.17` with the
  Apple SwiftPM `v0.3.0` runtime pin.

* Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@v0.3.0`, regenerated matching Dart FFI bindings, refreshed
  the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and
  aligned current README/website native override docs.

* Aligned the default WebGPU bridge assets to `v0.1.41` for corrected
  TypeScript declarations and TTS recovery guidance, retaining Web/native
  llama.cpp `v0.3.0@c1d0e7a004015f23bc0233470b747b596f29b264` parity and Web
  `@litert-lm/core@0.15.0`. Immutable manifest:
  `fe97604daabaad6aefa223a8637d5fd9dcac09dd4a61b2ef19cd6aabb39392b9`.

* Consolidated native release tag grammar across Dart, Python, Bash, workflows,
  and documentation via a machine-readable fixture contract (`#404`).

## 0.8.21

* Aligned the default WebGPU bridge assets to `v0.1.39` (immutable manifest
  `b355d01040604f6ae2c5c5fe5bb42b858101a96f03f67e4b27b32fe41ce3b2bf`),
  restoring Web/native llama.cpp upstream `v0.2.0@bb4caa7540188872173c44d161602d9271386413`
  parity with native anchor `llamadart-native@v0.2.0-1` while preserving
  approved Web `@litert-lm/core@0.15.0` packaging.

* Fixed native Qwen3-ASR transcription by applying the model chat template to
  audio turns, while preserving the validated raw-prompt Web bridge contract.
  Empty ASR output now fails explicitly instead of reporting an empty result.

* Fixed Qwen 2.5/3 LiteRT-LM `ToolChoice.required` requests silently running
  without their required-call grammar and finishing with no call. They now fail
  with an actionable `LlamaUnsupportedException` before generation when the
  backend cannot enforce the declared tool schema; Gemma 4 compatibility and
  `auto`/`none` tool routing are unchanged.

* Fixed Gemma 4 thinking-budget output so split channel controls and tool-call
  envelopes stay out of visible assistant content while preserving ordinary
  whitespace. The chat example now also validates custom tool declarations,
  executes declared host handlers exactly once, appends tool results, and
  performs a bounded continuation for both llama.cpp and LiteRT-LM backends.

* Patched the website's vulnerable `nanoid` and `uuid` dependency paths. Until
  Docusaurus replaces its unpatched image parser, automatic local Markdown
  images are rejected; website contributors should use static pathname URLs.

* Fixed `llamadart_native_runtimes` values `none`, `off`, and the string
  `false` selecting every runtime family instead of none;
  the build hook fails with its `No native runtimes selected` error again, as
  it did before 0.8.0. A YAML boolean `false` clears the selection too. Unset,
  empty, and all-unrecognised config still select every family.

* The published package no longer ships the `doc/` directory; that contributor
  and maintainer documentation is maintained on GitHub, and the packaged files
  that link to it now use absolute URLs.

* Fixed unanchored `docs/` and `website/` publish-exclusions that matched those
  directory names at any depth and dropped `tool/docs/` plus the
  `llamadart_server` example's OpenAPI spec and Swagger UI sources from the
  package, leaving the published example unable to analyze. Both patterns are
  now root-anchored.

* Narrowed the `dinja` dependency constraint to `>=1.0.0 <1.1.0` so chat
  template capability detection cannot silently resolve against an unverified
  Jinja parser minor. A 1.0.x patch can still reorganise the private sources
  the analyzer imports; a new coupling test turns that into a named failure.

* Fixed Command R7B, Hermes, and Hunyuan V3 tool grammars so distinct tool or
  parameter names cannot collide after conversion to internal GBNF rule names.

* Fixed DeepSeek V3.2 DSML tool calls using their upstream
  `<｜DSML｜function_calls>` envelope while preserving DeepSeek V4's distinct
  `<｜DSML｜tool_calls>` grammar and parser behavior.

* Fixed partial GLM 4.5, Poolside Laguna, and Muse Glimmer tool envelopes
  leaking into streamed assistant content, while preserving completed calls,
  malformed final output, and ordinary text surrounding Muse recipient
  channels.

* Fixed schema-constrained tool calls for Kimi K3, MiniMax M1/M3, DeepSeek
  V3.2/V4, and Muse Glimmer, including exact escaped names, required fields,
  declared value types, matching MiniMax M3 element tags, zero-argument calls,
  and strings containing delimiter characters. Required-tool mode now accepts
  each format's reasoning/content prefix while still requiring a call.
  MiniMax M3, DeepSeek DSML, Muse Glimmer, Poolside Laguna, and GLM 4.5 now
  reconstruct argument values from the declared tool schema instead of
  guessing from text. Added `ToolParam.nullType` for null-only JSON Schema
  properties.

* llama.cpp backend initialization failures now complete the worker startup
  handshake with a typed `LlamaBackendInitializationException` and collected
  native-loader diagnostics. A failed or incompatible worker is torn down
  instead of being reported ready and leaving later requests waiting forever.

* Added template-aware parsing for Kimi K3, MiniMax M1/M3, DeepSeek V3.2/V4,
  Muse Glimmer, and Poolside Laguna, preventing their native tool calls from
  silently falling back to plain content.

* Fixed XML-style tool-call parsing to honor raw-versus-JSON argument values
  and final-value delimiters. Apriel 1.5 and Xiaomi MiMo now parse nested JSON
  values without splitting on inner commas, while malformed payloads remain
  ordinary assistant content.

* Made native video-input capability truthful without claiming end-to-end
  support. `LlamaVideoContent` requests now fail with an actionable
  `LlamaUnsupportedException`, `LlamaEngine.supportsVideo` reports public
  consumability as false, and the llama.cpp worker uses the behavioral
  `mtmd_helper_support_video` result instead of exported helper symbols. The
  published `v0.2.0-1` archive has not been qualified for end-to-end video;
  full path/byte input remains blocked on cross-platform FFmpeg/ffprobe
  packaging and Dart frame lifecycle wiring.

* Native release synchronization and build-hook overrides now accept stable
  `vMAJOR.MINOR.PATCH` artifacts and ordered `vMAJOR.MINOR.PATCH-N` wrapper
  rebuilds plus nightly `bNNNN-N` rebuilds, while preserving historical
  `bNNNN` and `bNNNN-llamadart.N` artifacts. Sync rejects invalid tags,
  leading-zero nightly versions, rollback, wrapper/nightly `latest` results,
  incompatible manifest contracts, missing bundles, and release/manifest
  checksum or version skew without changing the default pin.

* Fixed Web/native backend API parity. `WebAutoBackend` now forwards grammar
  constraint support from its active runtime, so strict structured output fails
  early with an actionable error on unsupported Web backends, and the Web-safe
  `LiteRtLmRuntimeClient` stub now exposes the native client's thinking-tag
  configuration method.

* A failed llama.cpp model load now reports the startup diagnostics collected
  during native library discovery, so a missing or unloadable runtime library
  explains itself instead of surfacing as a bare load failure. Platforms that
  record no diagnostics keep their previous message unchanged.

* llama.cpp worker errors now keep their type. Every backend method routes an
  `ErrorResponse` through the file's own error mapper instead of rebuilding a
  bare `Exception`, `tokenize` and `detokenize` no longer discard the worker's
  error entirely, and a core `UnsupportedError` raised for an unavailable native
  capability is classified rather than flattened. State-file failures now throw
  `LlamaStateException`.

* Fixed multimodal media placeholders being normalized inconsistently. `<img>`,
  `<|img|>`, `<start_of_image>` and indexed markers such as `<|image_1|>` are now
  rewritten to the mtmd marker on every path, rather than depending on which
  layer rendered the prompt. MiniMax-M2 and MiniCPM-5 also now detect a
  forced-open thinking block using the same rule as every other handler.

* aLoRA adapters are now rejected with `LlamaUnsupportedException` instead of
  being applied like ordinary LoRA adapters. An aLoRA adapter must activate only
  after its invocation tokens appear in the prompt, so applying it from the
  start of generation silently changed output. Missing metadata-inspection
  symbols in custom native runtimes also fail closed with the same typed error,
  and rejected adapters are released when the cleanup ABI is available. LoRA
  errors from the worker keep their typed exception instead of arriving as a
  bare `Exception`, and a failed adapter load now throws
  `LlamaModelException`.

* Deprecated `LiteRtLmRuntimeClient.conversationTokenCount()` and
  `replaceConversationWithClone()`. Both are unused and are scheduled for
  removal in the next major release; open an issue if you depend on either.

* `NativeLlamaBackend.modelLoadFromUrl` now throws `LlamaUnsupportedException`
  instead of `UnimplementedError`, bringing it into the `LlamaException`
  hierarchy. It is the same exception type `LlamaEngine.loadModelFromUrl`
  already throws for this condition; each keeps its own message.

* Updated the default llama.cpp native runtime to the immutable
  `leehack/llamadart-native@v0.2.0-1` release (llama.cpp `v0.2.0`), adding LFM2
  DSpark support plus current upstream correctness and backend performance
  fixes. Matching Dart FFI bindings, including the new multimodal
  projector-device field, and the Apple SwiftPM artifact checksum were
  refreshed. Linux `libmtmd.so.0` now loads without the old
  `libmtmd.so.SOVERSION` compatibility alias.

* Removed the abandoned Dart-side MTP/n-gram speculative-decoding scaffolding
  from the llama.cpp backend. Speculative decoding is unchanged: it continues to
  run through the native wrapper, and `SpeculativeDecodingStrategy` keeps every
  existing option.

* Bumped `llamadart_llama_cpp_flutter` to `0.0.16` so the `v0.2.0-1` Apple
  SwiftPM pin actually publishes; `0.0.14` was already on pub.dev, so release
  automation skipped it and Apple builds would have kept the `b10514` runtime.

* Corrected the WebGPU bridge docs, which claimed the pinned `v0.1.37` bridge
  assets match the default native llama.cpp runtime. They embed `b10514` and now
  trail the native `v0.2.0-1` pin.

* Chat-template capability detection now logs a debug message naming the
  probe (`string-content`, `typed-content`, `system-role`, `tools`) when its
  render throws, so a template that fails to render is distinguishable from
  one that genuinely lacks the capability.

## 0.8.20

* Added `code_assets` 2.x compatibility while retaining support for 1.x native
  asset toolchains.

* Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b10514`, adding BailingMoE3,
  GraniteSWA/GraniteMoeSWA, speculators-format DSpark checkpoints, and current
  upstream multimodal/backend improvements. Matching Dart FFI bindings and the
  `llamadart_llama_cpp_flutter` Apple SwiftPM artifact were refreshed.

* Updated the default WebGPU bridge assets to `v0.1.37`, embedding llama.cpp
  `b10514` to restore native/Web parity. The bridge provisions an explicit 1 MiB
  Wasm stack for wasm32 and memory64, preventing Qwen3-ASR memory64 context
  construction from overflowing the default stack.

* Improved Web microphone transcription by warming up browser capture before
  showing the recording-ready state, trimming the warmup silence, and
  rejecting too-short, silent, or unsupported PCM WAV captures before
  inference.

* Added logical batch-size (`n_batch`) and micro-batch-size (`n_ubatch`)
  controls for llama.cpp/WebGPU models in the Flutter chat example.

* Improved Android Auto backend selection by probing the packaged Vulkan device
  before memory planning, avoiding unnecessary CPU fallback on capable models.

* Updated the native LiteRT-LM runtime to `v0.16.0-native.2`. The Apple companion
  packages the iOS Gemma constraint provider and Metal accelerator/sampler
  plugins required by the published runtime.

* Added an experimental `SpeechToTextEngine.liteRtLm` path with capability
  discovery, worker-isolated CPU inference, bounded mono 16 kHz float PCM,
  partial/final transcript events, finalization, and cancellation.

* Added experimental live dictation to the native Flutter chat example for
  chat models using selectable Moonshine Tiny and Parakeet TDT 0.6B sidecars.
  Live dictation is CPU-only, English-only, capped at five minutes, and
  unavailable on Linux and Web.

* Improved Flutter chat example model downloads with bounded retries for
  transient network failures, safe resume after truncated responses, and a
  distinct integrity-verification state after transfer reaches 100%.

* Redesigned the Flutter chat example onboarding and Lab surfaces, preserved a
  completed model card's viewport position when downloads reorder the catalog,
  and stopped streaming responses from pulling users away from chat history.

* Added an experimental typed `TextToSpeechEngine` for native llama.cpp and
  WebGPU with Qwen3-TTS models, including capability discovery, speaker
  references, cancellable progress, complete 24 kHz PCM output, and WAV
  encoding. The Flutter chat example adds synthesis, playback, replay, and WAV
  save controls. Apple apps discover the TTS ABI in the embedded llama
  framework; current LiteRT-LM artifacts fail explicitly as unsupported.

* Added an experimental typed `SpeechToTextEngine` with an explicit Qwen3-ASR
  adapter profile for whole-file llama.cpp transcription. The Flutter chat
  example includes a checksum-pinned Qwen3-ASR 0.6B preset plus file and
  microphone transcription on native and WebGPU. Web accepts WAV bytes only;
  native LiteRT-LM live dictation remains a separate implementation.

* Added **Ask with voice** to the native Flutter chat example for Gemma 4 E2B
  through LiteRT-LM direct media and audio-capable GGUF + projector paths. It
  sends a microphone recording through multimodal chat and remains separate
  from typed speech-to-text.

* Added experimental, opt-in native llama.cpp DSpark speculative decoding
  through `SpeculativeDecodingConfig.draftDspark(...)` with a compatible
  external draft model.

## 0.8.19

* Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b10333`, regenerated matching Dart FFI bindings,
  refreshed the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and aligned
  current README/website native override docs.

* Updated WebGPU bridge assets to `v0.1.27` (llama.cpp `b10333`), keeping the
  native and Web GGUF runtimes on the same upstream revision.

* Fixed corrupt Qwen3.5 output on Android Vulkan by preserving the KQV
  offload required for correct hybrid model inference while retaining the
  remaining conservative Android context settings.

## 0.8.18

* Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b10276`, picking up Qwen3-TTS model-loading
  primitives, explicit bundled-MTP loading, automatic model-specific token
  suppression, and recent model, multimodal, speculative-decoding, backend,
  and runtime fixes. Regenerated matching Dart FFI bindings, migrated model
  loading to llama.cpp's load-mode ABI and the penalty sampler to the new
  vocabulary-sized ABI, and refreshed the `llamadart_llama_cpp_flutter` Apple
  SwiftPM checksum. Speech generation is not yet exposed through the public
  Dart API.

* Updated the default LiteRT-LM runtimes to
  `leehack/litert-lm-native@v0.15.0-native.3` and
  `@litert-lm/core@0.15.0`. The native artifact includes a corrected v0.15
  streaming callback bridge and an Android Dawn rollback for Mali-G715 GPU
  device loss; incompatible callback runtimes now fail safely before
  generation, and concrete macOS app, framework, and cache libraries take
  precedence over process-linked assets.

* Disabled automatic WebGPU fetch-backed model loading by default. Streamed
  loading remains the safe default; controlled range-capable deployments can
  opt in explicitly.

* Updated WebGPU bridge assets to `v0.1.26` (llama.cpp `b10276`), refreshing
  both WebAssembly runtimes while preserving the existing bridge API.

## 0.8.17

* Updated the default llama.cpp native runtime to
  `leehack/llamadart-native@b10075` with matching bindings and Apple artifacts.

* Added Tencent Hunyuan V3 chat-template, reasoning, and tool-call support.

* Fixed Gemma 4 LiteRT-LM text generation in the Web chat app after model
  loading completed successfully.

* Restored GGUF loading in deployed Web chat apps by packaging the pinned
  WebGPU runtime assets with Flutter Web builds.

## 0.8.16

* Updated the default llama.cpp native runtime to
  `leehack/llamadart-native@b9982`, including regenerated bindings and safer
  multimodal UTF-8 prompt handling.

* Improved llama.cpp batching defaults and `ChatSession` context management for
  more predictable generation under constrained contexts.

* Added llama.cpp `presencePenalty` sampling and thinking-budget controls,
  including the server's `thinking_budget_tokens` extension. Unsupported
  WebGPU and LiteRT-LM paths now fail explicitly.

* Reworked the runnable TUI coding agent with a focused Pi-style workflow,
  Unsloth Qwen3.6 defaults, shared model-source loading, and clearer reasoning
  and final-answer presentation.

* Improved the OpenAI-compatible server with standard client-managed tool-call
  transcripts, named `tool_choice`, configurable thinking behavior, and shared
  model-source loading.

## 0.8.15

* Added clipboard media attachments to the runnable chat app. Desktop and web
  users can paste screenshots or copied image/audio files with `Cmd/Ctrl+V`,
  mobile users can choose **Paste attachment**, and ordinary text paste remains
  unchanged.

* Restored the runnable macOS chat app build phase that embeds and signs
  LiteRT-LM runtime libraries inside the sandboxed app bundle, and enabled
  LiteRT-LM Metal selection on iOS with the consolidated upstream runtime.
  Updated the default LiteRT-LM runtime to
  `leehack/litert-lm-native@v0.14.0-native.2`, which fixes Android GPU plugin
  symbol resolution and uses the checksum-pinned official Apple XCFrameworks.

* Fixed native LiteRT-LM generation incorrectly treating the requested maximum
  response length as a forced benchmark decode count. Short responses no longer
  wait for every allowed token before streaming, and LiteRT-LM chat flushes its
  first token immediately.

* Added an app-owned FIFO model-download queue to the runnable chat app. Only
  one model transfers at a time, queued cards show their position and can leave
  the queue independently, and a responsive shell progress pill keeps the
  active download visible after the settings panel closes.

* Replaced the runnable chat app's broad built-in model catalog with a focused
  Unsloth-first set. Added cross-platform Gemma 4 E4B plus native-desktop Gemma
  4 12B/26B-A4B/31B and Qwen3.6 35B-A3B presets. The model library now promotes
  downloaded models, supports name/capability search and Mobile & Web/Desktop
  filters, explains incompatible choices, and uses quieter cards with compact
  compatibility, capability, and recommended-setting summaries. Custom entries
  retain independent remove-from-library and downloaded-file actions.

* Enabled Gemma 4 audio attachments in the runnable chat app for the current
  native GGUF projector and LiteRT-LM bundle, while keeping LiteRT-LM Web
  correctly text-only. Model capability settings now distinguish direct media
  input from external `mmproj` input and persist that distinction across app
  launches.

* Redesigned the runnable chat app with a quieter responsive shell, compact
  runtime details, full-screen mobile settings, streamlined message/composer
  surfaces, accessible controls, protected conversation deletion, and
  copy/regenerate actions for assistant responses. Model downloads now remain
  active when settings closes or switches between drawer and pinned layouts.

* Hardened the runnable chat app for narrow windows, 200% text scaling, and
  macOS assistive technology; removed stale assistant placeholders after empty
  or failed generations; kept context accounting stable when regenerating a
  response; and redacted signed model URL parameters from labels and generation
  errors.

* Clarified the chat app's backend and GPU-layer controls, exposed the active
  loaded backend beside its preference, and restored GPU offload when switching
  from a zero-layer CPU configuration back to Auto or a GPU backend. Native
  **Max** now maps to full llama.cpp offload, while Auto uses model size,
  available device memory, safe system headroom, and requested context to choose
  full or partial offload and only reduces context when the model does not fit.
  Auto intent now persists separately from resolved layer/context values so
  device headroom is recalculated on every model load and after app restarts.

## 0.8.14

* Updated the runnable chat app's web runtimes to pinned WebGPU bridge assets
  `v0.1.18` (llama.cpp `b9915`) and `@litert-lm/core@0.14.0`, keeping hosted
  and local inference on reproducible runtime versions.

* Improved the runnable chat app's model-cache UX by reusing cached GGUF and
  LiteRT-LM web bundles for benign catalog URLs such as `?download=true`,
  preserving browser model caches during app cache cleanup, adding a text-only
  projector skip path, and polishing download/load progress states.

* Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b9935`, regenerated matching Dart FFI bindings, refreshed
  the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and
  aligned current README/website native override docs.

## 0.8.13

* Fixed load lifecycle guards so repeated model loads preserve the active
  model state, URL load unsupported-runtime diagnostics stay typed, and unload
  cancels active generation before freeing llama.cpp handles.

* Tightened LiteRT-LM runtime validation and local smoke coverage by requiring
  complete macOS arm64 runtime caches, requiring an explicit model path for the
  LiteRT-LM chat feature smoke scenario, normalizing the chat app's LiteRT-LM
  auto context size, and adding the missing iOS-compatible SwiftPM Gemma
  provider target. Flutter macOS LiteRT-LM companion-package builds now fall
  back to hook-managed native assets, and the companion package no longer links
  the incomplete macOS LiteRT-LM SwiftPM artifact set.

* Reworked the README into a shorter entry point, fixed stale docs/examples
  found during the documentation review, and aligned release, Android smoke,
  WebGPU mem64, native sync, and capability-support wording with the current
  workflows and runtime behavior. WebGPU runtime LoRA calls now throw an
  unsupported-operation error instead of reporting no-op success.

* Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b9873-llamadart.2`, keeping the `b9873` llama.cpp
  ABI/bindings while picking up wrapper fixes for native release
  provenance and backend-selected speculative sampler acceptance. Refreshed
  the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum and aligned current
  README/website native override docs.

* Aligned llama.cpp n-gram speculative rejected-tail rollback with upstream
  server behavior by trimming rejected target tokens before falling back to
  checkpoint replay, avoiding early token-count/EOG drift in accepted-draft
  `ngram-map-k` runs. The speculative benchmark can now emit full generated
  text with `--include-output` for parity investigations.

* Fixed llama.cpp n-gram speculative configuration mapping so
  `draftTokenMax` no longer implicitly overrides upstream `ngramSizeM`, and
  documented upstream comparison commands plus measured n-gram benchmark
  results.

* Added a durable flag-based llama.cpp speculative benchmark runner and wired
  it into the local E2E scenario list, testing matrix, README, and website
  performance guide. The runner can now generate a llama.cpp-compatible
  static n-gram cache file for `ngram-cache` E2E validation, and renders
  benchmark prompts with configured or loaded GGUF chat templates before the
  generic fallback instead of silently falling back to a hard-coded Gemma
  prompt.

* Documented compatible DFlash GGUF metadata, a known-good public target/draft
  model pair, and troubleshooting guidance for incompatible `dflash-draft` or
  missing `dflash.target_layers` artifacts.

* Hardened generic llama.cpp external draft-model speculative decoding so
  draft-context processing does not request unused logits, avoiding a
  `draft-simple` native abort while preserving target verification logits.

* Extended llama.cpp speculative performance diagnostics with draft-attempt,
  target-verification-token, and replay-token counters. Enabled speculative
  runs now preserve explicit zero counters instead of collapsing them to null,
  and local benchmark JSON includes the new fields.

* Hardened LiteRT-LM generation validation so llama.cpp-only speculative
  decoding knobs fail loudly instead of silently degrading to LiteRT-LM's
  boolean speculative toggle.

* Added llama.cpp upstream speculative decoding parity through
  `SpeculativeDecodingConfig` constructors for draft-simple, EAGLE3, MTP,
  DFlash, ngram-simple, ngram-map-k, ngram-map-k4v, ngram-mod, ngram-cache,
  and mixed n-gram plus one draft-model strategy, including generic native
  wrapper bindings, docs, and local benchmark matrix coverage.

* Added `LlamaStructuredOutput` and `LlamaEngine.createStructuredJson(...)`
  helpers for strict JSON-object / JSON-schema generation with final-output
  validation and typed decoding.

* Added `LlamaEngine.loadMultimodalProjectorSource(...)` so GGUF
  multimodal projector files can use the same `ModelSource` resolver,
  native download/cache manager, authentication, checksum, and progress
  options as `loadModelSource(...)`, while preserving the existing
  `loadMultimodalProjector(...)` path/string API.

* Improved the runnable chat app's Manage Models cache UX so model and mmproj
  asset cache states are shown separately, missing multimodal projectors can be
  re-cached without re-fetching already cached model assets, and runtime media
  capability mismatches surface as user-readable warnings. Custom signed or
  tokenized Hugging Face URLs now require confirmation before they are saved.

## 0.8.12

* Updated the default LiteRT-LM native runtime pin to
  `leehack/litert-lm-native@v0.14.0-native.1`, refreshed matching native-assets
  checksums, aligned the `llamadart_litert_lm_flutter` Apple SwiftPM checksums,
  and documented the newly exposed native LiteRT-LM load/generation controls:
  per-request max output tokens, native sampler params, thread count, one
  default-scale initial text LoRA adapter, activation data type, prefill chunk
  size, parallel file-section loading, and Android LiteRT dispatch library
  directory.

* Hardened LiteRT-LM runtime packaging and local runtime preparation for the
  0.14 line, including Linux/Windows runtime dependency resolution, Android
  Dawn companion libraries, Apple SwiftPM checksums, and macOS fallback app
  runtime copying.

* Hardened release automation by adding CODEOWNERS coverage for
  publication-sensitive files and making pub.dev/GitHub Release propagation
  waits configurable with longer defaults.

* Added post-merge release automation so a merged release-prep PR can publish
  missing companion package versions, push the core release tag, wait for
  pub.dev, and confirm the GitHub Release without a separate manual tag step.

* Added `LlamaEngine.getModelFileType()` for llama.cpp/GGUF models, exposing
  native model file type / quantization metadata from `llama_model_ftype` and
  `llama_ftype_name` when available.

* Refreshed llama.cpp `b9860` template parity for DeepSeek V4 and MiniCPM5,
  including MiniCPM5 XML tool-call detection, rendering, and parsing.

* Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b9860`, regenerated matching Dart FFI bindings, refreshed
  the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and
  aligned current README/website native override docs.

## 0.8.11

* Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b9829`, refreshed the
  `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and aligned current
  README/website native override docs for the release.

## 0.8.10

* **Potentially breaking behavior change:** native model cache defaults changed
  without breaking Dart source compatibility. `DefaultModelDownloadManager()` now
  prefers the platform shared cache on desktop/server instead of the process temp
  directory, and mobile `DefaultModelDownloadManager.auto()` without an explicit
  app-private directory now uses a best-effort temporary/cache fallback instead
  of throwing. Apps or tests that asserted the old temp path or mobile exception
  should pass an explicit cache directory or follow `MIGRATION.md`.

* Added optional `androidAppPrivateCacheDirectory` and
  `iosAppPrivateCacheDirectory` arguments to
  `DefaultModelDownloadManager.auto(...)` so apps can provide platform-specific
  mobile cache roots without constructor-level `Platform.isAndroid` /
  `Platform.isIOS` branching.
* Updated the default native `DefaultModelDownloadManager()` constructor to use
  the per-user shared model cache on desktop/server platforms and the mobile
  app-private cache fallback, so plain `LlamaEngine(...)` remote source loads use
  a platform-appropriate default while preserving a temporary fallback for hosts
  that cannot expose a desktop cache environment.

## 0.8.9

* Broadened the `hooks` dependency constraint to support both the existing
  build-hooks package family and the latest stable release, restoring the
  pub.dev dependency freshness score without breaking downstream packages that
  still resolve `hooks` 1.x.

* Made web-safe backend stubs the default conditional import/export targets,
  preserving native `dart:io` selection while avoiding false WASM compatibility
  deductions in pub.dev analysis.

## 0.8.8

* Added a CI release-doc version consistency check so current README/website
  install snippets and companion package READMEs stay aligned with package
  `pubspec.yaml` versions, and documented that companion/core package publishing
  happens only after release-prep merge with explicit maintainer approval for
  each tag.

* Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b9803`, regenerated matching Dart FFI bindings, refreshed
  the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and
  aligned current README/website native override docs.

* Added `DefaultModelDownloadManager.auto(...)` plus explicit model cache root
  constructors for shared desktop caches, app-private mobile caches,
  user-selected model libraries, and App Group containers. Implicit shared cache
  resolution now fails loudly on mobile and web where the OS cannot provide a
  hidden cross-developer model folder.

## 0.8.7

* Fixed multimodal chat-template rendering so templates that force-open
  reasoning (for example Qwen3.5 VLM prompts ending with `<think>`) preserve
  `enable_thinking` and stream generated reasoning through `delta.thinking`
  instead of `delta.content`.

## 0.8.6

* Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b9776`, regenerated matching Dart FFI bindings,
  refreshed the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and
  aligned current README/website native override docs.

## 0.8.5

* Fixed the split-library mtmd fallback ABI for image and byte-buffer
  multimodal inputs so Windows `mtmd.dll` and other split mtmd native bundles
  use the same bitmap helper signature as the generated native binding path.
  This avoids corrupting the first mtmd bitmap-helper call for Gemma 4/MMProj
  style multimodal loads and adds native symbol regression coverage for the
  fallback ABI.

## 0.8.4

* Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b9744`, regenerated matching Dart FFI bindings,
  refreshed the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and
  aligned current README/website native override docs.

* Expanded llama.cpp chat-template parity coverage for the latest upstream
  template fixtures, including Cohere2 MoE, LFM2.5 tool-call, and Granite 4.1
  templates. LFM2.5 templates that use plain `List of tools: [...]` prompts
  with `<|tool_call_start|>` / `<|tool_call_end|>` now route through the LFM2
  handler like upstream llama.cpp, and `ToolChoice.required` now uses
  grammar-constrained LFM2 tool-call generation.

* Fixed streaming tool-call parsing so partial North/Cohere bare action arrays
  are not emitted as content before the complete tool call is parsed.

* Expanded the local GGUF chat feature smoke to cover thinking, tool-call, and
  optional multimodal turns through the unified local E2E runner.

## 0.8.3

* Fixed Windows CUDA backend discovery when the native asset bundle directory is
  not on the app `PATH`. llama.cpp backend modules are now loaded from their
  resolved bundle path in a way that lets colocated CUDA redistributables such
  as `cudart64_12.dll`, `cublas64_12.dll`, and `cublasLt64_12.dll` resolve
  correctly.

## 0.8.2

* Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b9694`, regenerated matching Dart FFI bindings,
  refreshed the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and
  updated the default WebGPU bridge asset pin to
  `leehack/llama-web-bridge-assets@v0.1.17` (llama.cpp `b9699`). The WebGPU
  backend now caps unset large-model browser batches so Gemma 4 mem64 loads do
  not fall back to context-sized compute buffers.

* Added `BackendGpuEnumeration.listGpuDevices({probeBackends})` (exposed via
  `LlamaEngine.listGpuDevices`) to enumerate GPU-class devices for offload
  selection — backend, per-backend `mainGpu` index, name, description, device
  id, type, and free/total memory per device. With an empty `probeBackends`
  only already-registered backends are inspected, so an unsupported GPU runtime
  cannot crash the process during enumeration; pass specific backends to opt
  into loading just those modules first. Web/WebGPU return an empty list.

* Added Cohere2 MoE / North Code chat-template detection and parsing so
  `<|START_TEXT|>` responses and `<|START_ACTION|>` tool-call arrays are
  handled separately from older Command-R templates.

## 0.8.1

* Fixed docs references that still pointed at
  `llamadart_litert_lm_flutter` `0.0.1` and
  the pre-`native.1` LiteRT-LM release after the 0.8.0 native pin sync moved
  LiteRT-LM Apple/runtime artifacts to `v0.13.1-native.1`.
* Routed native `.litertlm` image/audio chat parts through LiteRT-LM
  Conversation message JSON so bundles with native media processors can accept
  `LlamaImageContent` / `LlamaAudioContent` path and encoded-byte inputs without
  a separate `mmproj` projector.

## 0.8.0

* **Flutter Apple runtime packaging**:
  * Split SwiftPM-linked Apple runtime packaging out of the core package into
    `llamadart_llama_cpp_flutter` for GGUF/llama.cpp and
    `llamadart_litert_lm_flutter` for `.litertlm`/LiteRT-LM. These companion
    packages live under `packages/` in this repository and publish as separate
    pub.dev packages.
  * Removed Flutter plugin metadata from `llamadart` so pure Dart/native-assets
    consumers can keep using the core package without taking a Flutter SDK
    constraint.
  * Started the companion packages at `0.0.1`; native pin sync bumps only the
    affected companion package patch version. Companion package publishing uses
    package-specific tags after the first manual pub.dev publish, and skips
    companion versions that already exist on pub.dev.
  * Changed unset or empty `llamadart_native_runtimes` to include all available
    runtime families. For Flutter iOS/macOS app builds, installed companion
    packages decide Apple SPM runtimes; for every other build,
    `llamadart_native_runtimes` remains the selector.
  * Updated the default llama.cpp native runtime pin to
    `leehack/llamadart-native@b9587`, regenerated matching Dart FFI bindings,
    and refreshed the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum.
* **MTP benchmarking diagnostics**:
  * Added llama.cpp speculative decoding perf diagnostics for decode timing,
    draft/accepted token counts, draft verification timing, and acceptance
    rate so MTP benchmarks can separate backend decode cost from drafting
    overhead.
  * Extended local macOS and chat app benchmark outputs with the new
    diagnostics and added focused llama.cpp MTP smoke/benchmark tools for
    baseline-vs-MTP comparisons.
* **llama.cpp MTP runtime support**:
  * Added `SpeculativeDecodingConfig.mtp(draftModelPath: ...)` for llama.cpp
    external draft-model MTP sessions, with draft model caching and cleanup
    tied to the target model lifetime.
  * Removed the Android Vulkan MTP allow-list dart define and the model-name
    based Android Vulkan acceleration shortcut; Vulkan MTP now runs only when
    callers explicitly request Vulkan plus MTP in runtime parameters.
* **Structured output**:
  * Added `responseFormat` routing to `LlamaEngine.create(...)` for
    grammar-capable backends, deprecated the legacy `chatTemplate(...)`
    `jsonSchema` shortcut, and made strict response-format requests fail early
    on LiteRT-LM instead of silently degrading to unconstrained generation.
* **LiteRT-LM chat parity**:
  * Routed eligible native `.litertlm` text chat through LiteRT-LM Conversation
    APIs so structured history, system messages, tool declarations, and
    template extra context reach the runtime without a Dart-rendered prompt.
    Unsupported cases still fall back to the existing Dart chat-template path.
* **LiteRT-LM runtime tuning controls**:
  * Added opt-in native `.litertlm` `ModelParams` for
    `liteRtLmActivationDataType`, `liteRtLmPrefillChunkSize`,
    `liteRtLmParallelFileSectionLoading`, and `liteRtLmDispatchLibDir`,
    forwarding the pinned LiteRT-LM `v0.13.1-native.1` engine-settings C APIs
    while keeping defaults unchanged.
  * Extended the LiteRT-LM engine smoke tool with matching environment
    variables so real-model runs can validate load time, prefill throughput,
    decode throughput, and selected runtime settings.
  * Documented support decisions for each candidate native knob and kept
    LiteRT-LM web rejecting these native-only settings explicitly.

## 0.7.2

* Added explicit pub.dev platform metadata for Android, iOS, Linux, macOS, web,
  and Windows. This keeps the package listing aligned with the actual
  cross-platform runtime support even though Flutter plugin registration is
  only needed for Darwin app integration.

## 0.7.1

* **Apple native runtime packaging**:
  * Added Flutter iOS/macOS Swift Package Manager integration so Apple apps link
    the pinned `leehack/llamadart-native` and `leehack/litert-lm-native`
    XCFramework artifacts through `darwin/llamadart/Package.swift`.
  * Disabled the legacy hook-managed Apple bundle path for Flutter iOS/macOS
    builds, avoiding wrapper/framework `MinimumOSVersion` mismatches in App
    Store uploads. Standalone Dart macOS keeps the native-assets dylib fallback.
  * Raised the Flutter Apple runtime floors to iOS 16.4 and macOS 14.0 to match
    the published XCFramework artifacts.
* **Runtime defaults and release automation**:
  * Android native builds still include both `llama_cpp` and `litert_lm` by
    default; iOS, macOS, Linux, and Windows now default to `llama_cpp` only.
  * Added native release pin automation so the maintainer sync workflow updates
    Apple SPM checksums from published native release asset digests.
  * Added `SpeculativeDecodingConfig` as a backend-neutral generation option for
    selecting speculative decoding strategies such as MTP while keeping the
    existing `GenerationParams.speculativeDecoding` flag as a compatibility
    switch.
  * Added llama.cpp native MTP speculative decoding for compatible GGUF models
    through `SpeculativeDecodingConfig.mtp(...)`, defaulting to a conservative
    one-token draft depth unless callers tune `draftTokenMax`.
  * Updated the default llama.cpp native runtime pin to
    `leehack/llamadart-native@b9547`, including the MTP wrapper exports and
    `llama-common` runtime packaging.
  * Added `ModelParams.speculativeRollbackTokenMax` so llama.cpp contexts can
    reserve recurrent-state rollback snapshots required by Qwen3.5 MTP-style
    models.
  * Guarded llama.cpp MTP on Android Vulkan by default because the upstream
    `draft-mtp` backend-sampling path can abort with `vk::DeviceLostError`;
    CPU and other supported backends remain available, and a dart-define debug
    override is available for reproductions.
* **CI reliability**:
  * Cached and retried tiny GGUF test-model downloads used by VM integration
    tests so main-branch CI is less exposed to Hugging Face 429 rate limits.
  * Excluded local SwiftPM artifact caches from pub archives; Flutter Apple
    consumers still resolve the published remote XCFramework targets.
* **Compatibility note**: no Dart API breaking changes. Flutter Apple apps must
  target iOS 16.4/macOS 14.0 or newer, and non-Android native apps that ship
  `.litertlm` models should opt in with `llamadart_native_runtimes`.

## 0.7.0

* **LiteRT-LM backend and runtime selection**:
  * Added first-class `.litertlm` routing through `LlamaBackend()` on native and
    web targets, with native bundle downloads from `leehack/litert-lm-native`
    and web loading through `@litert-lm/core`.
  * Added `ModelParams.liteRtLmBackend` so callers can select LiteRT-LM CPU,
    GPU, or Android NPU execution where supported. `auto` chooses GPU on
    Android/macOS and CPU elsewhere on native targets.
  * Added cached Hugging Face `.litertlm` loading through
    `loadModelSource(...)`, preserving the selected LiteRT-LM backend after the
    cache manager resolves the local file.
  * Added native LiteRT-LM tokenization, detokenization, log-level control,
    runtime metrics, and high-level `ChatSession` token counting support.
  * Added `hooks.user_defines.llamadart.llamadart_native_tag`,
    `llamadart_native_repository`, and `llamadart_native_path` so apps can test
    a different compatible native runtime source without patching `llamadart`.
  * Updated the Windows runtime fallback scanner to discover custom GitHub and
    local archive cache namespaces when `.dart_tool/lib` is unavailable.
* **LiteRT-LM chat, templates, and generation quality**:
  * Added `GenerationParams.speculativeDecoding` for native LiteRT-LM. The
    default remains disabled; llama.cpp, WebGPU, and LiteRT-LM web reject the
    option until their speculative paths are implemented.
  * Fixed Gemma 4 `.litertlm` thinking and tool calling by replacing the stub
    template with the canonical Gemma 4 chat template, parsing the runtime
    thought channel as reasoning, and suppressing reasoning deltas when callers
    set `enableThinking: false`.
  * Added a filename-keyed `.litertlm` chat-template registry seeded with
    Gemma 4/3/3n and Qwen 2.5/3. Pass `ModelParams.chatTemplate` to override
    detection for other models.
  * Fixed LiteRT-LM tool calling for grammar-using handlers by forwarding
    `supportsGrammarConstraints` from the active `NativeAutoBackend` delegate.
  * Stopped structured tool-call streams from leaking raw Hermes/Qwen JSON or
    Gemma `<|tool_call>` markers as assistant content before the final
    `tool_calls` chunk.
* **Web and chat-app support**:
  * Added `ModelParams.preferMemory64` and `ModelParams.modelBytesHint` so
    large WebGPU GGUF models such as Gemma 4 E2B can choose the 64-bit bridge
    core before hitting the wasm32 address-space limit.
  * Fixed web `.litertlm` chat-app turns by swallowing unsupported token-count
    refreshes, avoiding unsupported `minP`/`penalty` parameters for LiteRT-LM
    web generation, and replacing the stuck "Loading model 0%" label with an
    indeterminate load message.
  * Halved web `.litertlm` load time by skipping WebGPU `CacheStorage` prefetch
    for LiteRT-LM models, which are fetched directly by `@litert-lm/core`.
  * Fixed web GGUF downloads reporting success before the bridge was ready by
    awaiting `window.__llamadartBridgeReadyPromise`, requiring the bridge
    prefetch API, and surfacing actionable errors for old bridge assets.
  * Allowed benign Hugging Face `?download=true` URLs to be prefetched into the
    browser cache while still skipping credentialed or signed URLs.
* **Lifecycle, cancellation, and native stability**:
  * Fixed iOS `.litertlm` loading by resolving embedded `LiteRtLm` and
    `StreamProxy` frameworks from the app bundle, matching the macOS runtime
    path behavior.
  * Improved LiteRT-LM diagnostics before model load, including selected
    CPU/GPU/NPU backend reporting, platform availability errors, and complete
    dynamic-library candidate failures.
  * Validated platform-specific LiteRT-LM companion libraries during
    native-asset setup so incomplete runtime bundles fail at build time.
  * Hardened native and LiteRT-LM cancellation/disposal so in-flight generation
    no longer races token release, worker teardown, engine deletion, closed
    response ports, or stream writes after cancellation.
  * Freed multimodal prompt buffers on tokenize/eval error paths, serialized
    multimodal projector load/unload, and closed a leaked native-backend
    handshake reply port.
* **Correctness and download resilience**:
  * `ChatSession` now forwards empty-choices completion chunks instead of
    throwing, strips multiple `<think>` blocks, and trims history only on
    user-message turn boundaries.
  * `LlamaEngine.generate` wraps unexpected backend errors in
    `LlamaInferenceException` so callers catching `LlamaException` see the
    documented error type.
  * Tool-call parsing now uses stable fallback ids, tolerates code-fence
    language tokens without trailing delimiters, and keeps commas inside quoted
    argument values.
  * JSON-schema-to-GBNF conversion now resolves `$ref`s nested inside other
    `$ref` targets and fails loudly on unresolvable or external `$ref`s.
  * Array grammar generation validates `minItems`/`maxItems`, model downloads
    use connection and idle-read timeouts, and partial-download resume is
    restricted to files with stored validators.
* **Benchmarks, docs, and validation**:
  * Added fair Gemma 4 LiteRT-LM versus llama.cpp/GGUF benchmark tooling for
    Android, macOS, and web, with speculative-decoding metrics, Pixel benchmark
    failure detection, and target-specific timeouts.
  * Added `tool/gguf_chat_features_smoke.dart` and the
    `chat-app-web-gemma4-webgpu-smoke` E2E scenario for real-model parser and
    WebGPU mem64 validation.
  * Updated README, website docs, and `doc/litert_lm_templates.md` for backend
    selection, platform/runtime support, package-size controls, benchmark
    results, model templates, and current LiteRT-LM capability limits.
* **Compatibility note**: no public API breaking changes for existing GGUF /
  llama.cpp callers. LiteRT-LM support is additive, with deprecated benchmark
  wrappers retained for compatibility; unsupported llama.cpp-only parameters are
  rejected for `.litertlm` loads instead of being silently ignored.

## 0.6.17

* **Native runtime sync**:
  * Updated native hook pinning and regenerated bindings through
    `leehack/llamadart-native@b9371`, picking up llama.cpp `b9371`.
  * Picked up the Apple mobile Metal stability fix that disables Metal
    residency sets on iOS/tvOS/visionOS native bundles, avoiding affected
    device context-creation failures such as `MTLLibraryErrorDomain Code=3`.
* **Compatibility note**: no public API breaking changes in `0.6.17`;
  existing `0.6.16` callers remain compatible. The release only refreshes
  the pinned native runtime and generated low-level bindings.

## 0.6.16

* **Native runtime diagnostics**:
  * Fixed native `getVramInfo()` so it reports free/total VRAM from
    llama.cpp GPU-class backend devices when available, using props-based
    memory reporting first and the legacy memory probe as a fallback.
  * Routed native VRAM probing through the ggml registry fallback path so
    Windows split bundles resolve backend-device symbols from the runtime that
    owns the device registry.
* **WebGPU and chat app fixes**:
  * Improved browser recovery for large remote WebGPU model/projector loads by
    retrying wasm32 model-staging aborts with the wasm64 core before surfacing
    memory-pressure failures.
  * Improved the runnable chat app's web remote-model startup path so model
    assets are prefetched into browser cache when available, browser
    `CacheStorage` failures fall back to direct network loading, and
    credentialed/signed model URLs skip persistent browser cache storage.
* **Model download UX**:
  * Improved the runnable chat app's mobile download behavior so lifecycle
    pauses no longer deliberately cancel active foreground downloads; the app
    now lets short screen-lock/background interruptions continue when the OS
    permits and still keeps explicit pause/dispose cancellation paths.
  * Added in-app and docs guidance for mobile large-model downloads, including
    resumable partial files, foreground Dart lifecycle limits, and the need for
    opt-in native background download/model-store integrations for robust
    cross-app GGUF management.
* **Compatibility note**: no public API breaking changes in `0.6.16`;
  existing `0.6.15` callers remain compatible. The changes improve native VRAM
  diagnostics, WebGPU browser recovery, and chat app download lifecycle
  behavior.

## 0.6.15

* **Fixes**:
  * Fixed GLM-OCR and other multimodal chat-template workarounds so image and
    audio content parts are preserved when tool-call normalization runs, system
    prompts are merged before leading media parts, and invalid tool-call
    serialization fails loudly instead of silently falling back to the wrong
    template shape.
* **Testing**:
  * Added `tool/testing/run_local_e2e.dart` as a discovery and orchestration
    entry point for heavyweight local-only Dart E2E, Flutter device, and
    Web/Playwright smoke scenarios.
  * Hardened the upstream llama.cpp chat/template E2E runner against current
    llama.cpp target renames, dynamic backend library lookup, and full
    `test-chat` server/mtmd build requirements.
  * Documented that real-model/device/WebGPU scenarios remain skipped from
    default CI and should be opted into explicitly with `--list` and
    `--dry-run` first.
* **Compatibility note**: no public API breaking changes in `0.6.15`;
  existing `0.6.14` callers remain compatible. The chat-template changes fix
  multimodal serialization behavior for affected templates, and the local E2E
  runner is additive.

## 0.6.14

* **WebGPU bridge assets**:
  * Updated the default WebGPU bridge asset pin to
    `leehack/llama-web-bridge-assets@v0.1.16` (llama.cpp `b9165`),
    picking up the published JS bridge build, TypeScript declaration asset,
    and refreshed bridge docs.
* **Docs**:
  * Added WebGPU readiness guidance covering browser capability checks,
    cross-origin isolation, bridge asset/version diagnostics, fallback behavior,
    model/configuration pressure, and the Flutter Web real-model smoke path.
* **Model download UX**:
  * Added `ModelDownloadController`, a dependency-free helper that turns
    `ModelDownloadManager` cache/download work into app-facing lifecycle states
    for resolving, cache checks, downloads, verification, ready, failed,
    cancelled, and retry flows.
  * Wired the runnable chat app example through a `ModelDownloadManager` adapter
    so its model-management UI demonstrates the controller while preserving the
    example's multi-asset and web-cache service behavior.
* **Compatibility note**: no public API breaking changes in `0.6.14`;
  the WebGPU bridge asset update and `ModelDownloadController` are additive, and
  existing `0.6.13` callers remain compatible.

## 0.6.13

* **Model source download/cache manager**:
  * Added `ModelSource` for local paths, HTTP(S) URLs, and Hugging Face
    `hf://owner/repo/path/to/model.gguf` references, including deterministic
    cache keys and redacted metadata/log identities for signed URLs.
  * Added `ModelLoadOptions`, `ModelCachePolicy`, resolver targets, and
    download/cache metadata/progress value models for package-managed model
    download and cache management.
  * Added native/file-backed `DefaultModelDownloadManager` support for streaming
    HTTP downloads, `.part` files, atomic promotion, persisted metadata,
    authenticated bearer/custom headers, cancellation, retry, Range resume,
    cache hit/refresh/cache-only/no-cache policies, SHA-256 verification,
    cache listing, removal, clearing, and age/size pruning.
  * Improved Hugging Face source ergonomics: `hf://` references now accept
    `?revision=...` for branch/ref names containing slashes, and docs clarify
    current single-file behavior, private/gated bearer-token usage, separate
    `mmproj` asset handling, sharded-GGUF limitations, and redaction guarantees.
  * Serialized concurrent stable-cache downloads for the same remote cache entry
    across manager instances so duplicate callers do not race on shared `.part`
    files or metadata, while distinct cache entries can still download in
    parallel and waiting-caller cancellation does not cancel the active download.
  * Hardened versioned cache metadata recovery: completed files can rebuild
    missing, malformed, or unsupported-schema sidecars without network access,
    while byte-count and stored/caller SHA-256 mismatches are treated as cache
    misses and safely re-downloaded.
  * Clarified `ModelSource.path(...)` option semantics: local paths now reject
    remote/download-only options (non-default cache policies, cache directories,
    authenticated headers, resume, and retry overrides) while continuing to
    support cancellation and optional local SHA-256 verification.
  * Added `LlamaEngine.loadModelSource(...)` to route local sources through the
    existing native local loader, remote sources through the native download
    cache before local loading, and simple remote sources through URL-capable web
    backends when available.
  * Migrated server/testing helpers away from ad-hoc model downloads so examples
    dogfood the package-managed cache manager.
* **State persistence API**:
  * Added `LlamaEngine.supportsStatePersistence`,
    `LlamaEngine.stateSaveFile(...)`, and
    `LlamaEngine.stateLoadFile(...)` so callers can persist and restore
    llama.cpp KV-cache state for fast raw-prompt resume/fork workflows.
  * Added `BackendStatePersistence`, `BackendStatePersistenceSupport`, and
    `StateLoadResult` for custom backend implementers and diagnostics.
  * Documented that state files are opaque llama.cpp artifacts tied to the same
    model and runtime/build, that native paths use the app filesystem while web
    paths use the bridge WASMFS virtual filesystem, and that `ChatSession`
    message history must be persisted separately.
  * Added WebGPU bridge state persistence wiring for bridge assets `v0.1.15+`,
    including Dart JS interop, backend forwarding, and browser integration test
    coverage.
* **Compatibility note**: no public API breaking changes in `0.6.13`;
  existing `loadModel(...)` callers are unchanged. Code that probes state
  persistence support should prefer `LlamaEngine.supportsStatePersistence` over
  structural backend type checks so web/router backends can report
  bridge-version-dependent support accurately.

## 0.6.12

* **Native runtime sync**:
  * Updated native hook pinning to `leehack/llamadart-native@b9016`,
    picking up the CUDA 12.8 Blackwell-capable native bundles.
  * Updated default web bridge asset pinning to
    `leehack/llama-web-bridge-assets@v0.1.14` (llama.cpp `b9016`) so
    native and web runtimes track the same upstream revision.
  * Picked up the bridge-side Qwen UTF-8 streaming stabilization and
    multimodal fallback narrowing, while preserving control-token output for
    parser consumers.
  * Picked up the bridge-side BERT embedding thread-pool sizing fix so
    automatic thread selection does not exceed the compiled WebAssembly
    pthread pool.
* **Load-time tuning knobs**:
  * Added `ModelParams.useMmap` (default `true`) and
    `ModelParams.useMlock` (default `false`), wired to
    `llama_model_params.use_mmap` / `use_mlock`. Lets callers turn off mmap
    for platforms where memory-mapped weights hurt throughput, or pin
    weights in RAM to avoid first-token paging spikes.
  * Added `ModelParams.flashAttention` with the `FlashAttention.{auto,
    enabled, disabled}` enum, wired to
    `llama_context_params.flash_attn_type`. Explicit settings win over the
    existing automatic Android/Vulkan heuristics; `auto` preserves prior
    behavior.
  * Added `ModelParams.cacheTypeK` and `ModelParams.cacheTypeV` with the
    `KvCacheType.{f16, q8_0, q4_0}` enum, wired to
    `llama_context_params.type_k` / `type_v`. Enables KV-cache
    quantization (Q8_0 ≈ halves KV memory; Q4_0 ≈ quarters it). When the
    user requests a non-F16 KV type with `flashAttention: auto`, the
    service auto-promotes flash attention to enabled — llama.cpp requires
    it for KV quantization.
  * Added `ModelParams.kvUnified` (nullable) for explicit override of
    `llama_context_params.kv_unified`. `null` keeps the existing
    auto-enable-when-multi-sequence behavior.
  * Added `ModelParams.ropeFrequencyBase` and
    `ModelParams.ropeFrequencyScale` (both nullable) for
    context-extension overrides on `llama_context_params.rope_freq_base` /
    `rope_freq_scale`. `null` keeps the model's trained values.
  * Forwarded native-compatible `ModelParams` load tuning knobs through the
    WebGPU bridge path, including `maxParallelSequences`, flash attention,
    KV-cache type, KV-unified, RoPE, split-mode, and main-GPU options.
  * Matched native batch defaults on the WebGPU path so unset `batchSize` /
    `microBatchSize` cascade to `n_batch = n_ctx` and `n_ubatch = n_batch`,
    avoiding first-embedding aborts for BERT-class/non-causal encoder models
    while preserving explicit caller values and Qwen3.5 web tuning.
* **GPU device selection API**:
  * Added `ModelParams.mainGpu` and wired it to llama.cpp
    `llama_model_params.main_gpu`.
  * Added `ModelParams.splitMode` and wired it to llama.cpp
    `llama_model_params.split_mode`, enabling explicit single-GPU selection
    with `ModelSplitMode.none`.
* **Windows split-bundle loader fix**:
  * Resolved ggml backend registry/device APIs from the loaded ggml runtime DLL
    when the generated default FFI asset cannot see those symbols, restoring
    explicit Vulkan device selection in Windows split bundles.
* **Native packaging size fix**:
  * Filtered backend-owned runtime dependencies during native asset bundling so
    CUDA runtime DLLs and OpenBLAS runtime libraries are emitted only when their
    owning backend module is selected.
  * Kept unknown non-core runtime libraries bundled for compatibility with
    future native bundle layouts.
* **Compatibility note**: no public API breaking changes in `0.6.12`.

## 0.6.11

* **Native runtime syncs**:
  * Updated native hook pinning and regenerated bindings through `leehack/llamadart-native@b8955`.
* **Gemma 4 streaming fix**:
  * Parsed streamed `<|channel>thought ... <channel|>` blocks into thinking deltas instead of leaking Gemma 4 thought markers into content output.
  * Added engine coverage for Gemma 4 thought-channel chunks split across native stream boundaries.
* **Release stability**:
  * Tracked the chat app lockfile so generated Flutter plugin metadata stays stable in CI and release validation.
* **Compatibility note**: no public API breaking changes in `0.6.11`.

## 0.6.10

* **Native runtime syncs**:
  * Updated native hook pinning and regenerated bindings through `leehack/llamadart-native@b8638`.
* **Multimodal context-safety hardening**:
  * Converted native multimodal prompt-evaluation overflow paths into Dart exceptions instead of allowing downstream sampling asserts.
  * Downscaled staged chat-app image picks to a `384px` max edge across Android, iOS, macOS, and Web to reduce multimodal context pressure.
  * Added a local-only macOS Qwen3.5 multimodal repro harness plus CI-safe provider coverage for the new overflow guidance.
* **Gemma 4 template support and multimodal capability gating**:
  * Added built-in Gemma 4 template detection, rendering, and parsing support, including thinking and tool-call handling.
  * Added runtime projector capability checks so multimodal flows and the chat app gate image/audio input against `supportsVision` / `supportsAudio` instead of model-family assumptions.
  * Documented current Gemma 4 projector behavior in the docs site and chat app guidance.
* **Compatibility note**: no public API breaking changes in `0.6.10`.

## 0.6.9

* **iOS deployment target alignment**:
  * Documented that iOS builds require a minimum deployment target of `16.4` or newer across the README, docs site, and example docs.
  * Updated `example/chat_app` iOS Podfile and Runner project settings to use deployment target `16.4`.
* **Android backend safety**:
  * Honored `ggml_backend_score` during asset-based backend fallback so unsupported Android CPU variant libraries are skipped before initialization.
  * Changed Android `auto` backend resolution to prefer CPU by default while keeping Vulkan available for explicit opt-in.
  * Clarified that changing `hooks.user_defines` requires `flutter clean && flutter pub get` before rebuilding.
* **Compatibility note**: no public API breaking changes in `0.6.9`.

## 0.6.8

* **Native runtime sync**:
  * Updated native hook pinning and regenerated bindings to `leehack/llamadart-native@b8480`.
  * Refreshed generated low-level FFI bindings to match the synced upstream headers.
* **Compatibility note**: no public API breaking changes in `0.6.8`.

## 0.6.7

* **Native runtime sync and Linux loader hardening**:
  * Updated native hook pinning and regenerated bindings to `leehack/llamadart-native@b8373`.
  * Hardened Linux bundle loading for packaged apps and accepted versioned `libllamadart` mappings so colocated native dependencies resolve more reliably at runtime.
* **Hermes tool-call parsing fix**:
  * Fixed Hermes handler parsing when whitespace appears between `<tool_call>` and the JSON payload.
* **Compatibility note**: no public API breaking changes in `0.6.7`.

## 0.6.6

* **Runtime syncs**:
  * Updated native hook pinning to `leehack/llamadart-native@b8216`.
  * Updated default web bridge asset pinning to `leehack/llama-web-bridge-assets@v0.1.10` (llama.cpp `b8216`).
* **Qwen3.5 runtime stabilization (Android + Web)**:
  * Switched bundled Qwen3.5 presets to Unsloth `Q4_K_M` GGUFs across the example catalog and tooling.
  * Added Android-native perf diagnostics chips (`p_eval`, `eval`, `sample`, `reuse`) backed by llama.cpp context timings with manual timing fallback when built-in counters report zero.
  * Restored a targeted Android Vulkan fast path for local Qwen3.5 `0.8B` / `2B` / `4B` models by re-enabling KQV/op-offload/flash-attention where stable.
  * Updated Android chat app defaults to prefer CPU for Qwen3.5 `0.8B` and `2B`, and reduced Android `0.8B` context to `2048` for lower first-token latency.
  * Hardened Android multimodal handling by downscaling staged images in the chat app and forcing Qwen3.5 `0.8B` projector work onto CPU on Android.
  * Fixed WebGPU Qwen prompt/control-token handling and committed companion bridge-side streaming/multimodal fixes required by the local chat app runtime.
* **Compatibility note**: no public API breaking changes in `0.6.6`.

## 0.6.5

* **Embedding API (native backend capability)**:
  * Added `LlamaEngine.embed(...)` and `LlamaEngine.embedBatch(...)` for direct vector generation.
  * Added optional backend capability interface `BackendEmbeddings` for custom backend implementers.
  * Added optional backend batch capability `BackendBatchEmbeddings` and worker-side batch embedding request/response path to reduce isolate round-trip overhead in `embedBatch(...)`.
  * Added `ModelParams.maxParallelSequences` (`n_seq_max`) so contexts can reserve multiple sequence slots for true multi-sequence embedding batches.
  * Wired native isolate/worker/service embedding flow to llama.cpp embedding outputs with optional L2 normalization.
  * Added embedding-focused tests for engine behavior and worker message contracts.
* **Examples/docs**:
  * Added `example/basic_app/bin/llamadart_embedding_example.dart`.
  * Added `example/basic_app/bin/llamadart_sqlite_vector_example.dart` for local embedding retrieval with SQLite vector search.
  * Updated example docs and top-level README with embedding usage snippets.
  * Added `tool/testing/native_embedding_benchmark.dart` to compare sequential embedding calls vs `embedBatch(...)` throughput (with optional `--json-out`).
  * Added `tool/testing/native_embedding_sweep.dart` to run max-seq sweeps and dump CSV speedup reports for plotting.
* **Web bridge sync**:
  * Added WebGPU bridge embedding APIs and wired web backend support for `LlamaEngine.embed(...)` / `embedBatch(...)`.
  * Updated default web bridge asset pinning to `leehack/llama-web-bridge-assets@v0.1.8`.
  * Validated the `v0.1.8` bridge bundle through local fetch-script checksum verification.
* **WebGPU runtime tuning + multimodal stability (chat app/web)**:
  * Reduced bridge log noise and improved runtime profile diagnostics for web sessions.
  * Stabilized multimodal backend switching using resolved runtime mode behavior and added an E2E regression gate.
  * Tuned streaming/typewriter pacing and token callback overhead to improve incremental render smoothness.
  * Added GPU-path multimodal image-size capping to reduce runtime pressure on large image inputs.
* **Chat app model catalog + stability**:
  * Updated `example/chat_app` recommended Qwen presets to the Qwen3.5 lineup (`0.8B`, `2B`, `4B`, `9B`) and removed older Qwen2.5/Qwen3 defaults from the in-app library.
  * Added multimodal projector (`mmproj`) wiring for Qwen3.5 model cards and tuned safer multimodal defaults (`contextSize: 8192`, `maxTokens: 1024`).
  * Fixed Flutter text paint crashes caused by malformed UTF-16 streaming boundaries by aligning incremental reveal to surrogate-pair boundaries and sanitizing text/tool payload rendering paths.
  * Added sanitizer unit coverage and refreshed chat-app README architecture/troubleshooting sections for multimodal and UTF-16 guidance.
* **Compatibility note**: no public API breaking changes in `0.6.5`.

## 0.6.4

* **Multimodal projector offload alignment**:
  * Updated native multimodal projector initialization to follow effective model-load configuration.
  * CPU-only model settings (`preferredBackend: cpu` or `gpuLayers: 0`) now also disable mmproj GPU offload.

* **Package metadata cleanup**:
  * Removed unused Flutter-only constraints/dependencies from the root `pubspec.yaml` (`environment.flutter`, `flutter`, `path_provider`, `json_rpc_2`, `integration_test`) to keep the core package pure Dart.
  * Kept Flutter-specific dependencies scoped to Flutter example apps.
* **Backend selection safety and status accuracy**:
  * Added strict CPU-mode behavior in native backend preparation so `preferredBackend: cpu` no longer initializes optional GPU backends during startup/model load probing.
  * Disabled context-time GPU offload knobs (`offload_kqv`, `op_offload`, flash-attention auto path) when effective GPU layers resolve to zero, preventing GPU allocation attempts during context creation in CPU mode.
  * Added `ModelParams.batchSize` (`n_batch`) and `ModelParams.microBatchSize` (`n_ubatch`) so context batch sizing can be tuned independently from `contextSize` while preserving legacy defaults.
  * Split backend reporting into two semantics: selectable backend options (`getAvailableBackends`) vs active runtime backend (`getBackendName`).
  * Added optional `BackendAvailability` capability and `LlamaEngine.getAvailableBackends()` to support safe settings UIs without forcing GPU initialization.
  * Added optional `BackendRuntimeDiagnostics` capability and `LlamaEngine.getResolvedGpuLayers()` to expose resolved native load-time layer count for runtime diagnostics.
  * Updated `example/chat_app` to populate backend selector options from safe availability discovery while keeping active-backend status bound to effective runtime backend.
  * Improved native auto/explicit backend status resolution to avoid false CPU labeling on Apple consolidated runtimes and false GPU labeling when explicit backend falls back.
* **Web model cache + large-model UX improvements (chat app)**:
  * Updated web **Download** flow to prefetch model/mmproj bytes into browser Cache Storage with live progress and cancellation support.
  * Added best-effort cache eviction for web model delete actions.
  * Added large-model web load fallback to fetch-backed worker runtime path (bridge) to reduce contiguous `ArrayBuffer` pressure.
  * Added dedicated web bridge worker entry wiring and worker fallback diagnostics to improve worker startup reliability.
  * Reduced synthetic load-progress dominance so bridge/network progress appears earlier during web model load.
  * Added warning-only UI guidance for very large web models that may exceed browser memory limits at load time.
* **Web model-load resilience**:
  * Updated `WebGpuLlamaBackend` to retry web model loads with reduced context sizes (and CPU fallback as last attempt) when bridge errors indicate browser memory pressure.
  * Added bridge config plumbing for optional wasm64 core assets (`llama_webgpu_core_mem64`) with automatic fallback to wasm32 when unsupported.
  * Added explicit runtime diagnostics and error normalization for worker-thread and cross-origin-isolation requirements in large web model load flows.
  * Updated default bridge asset pinning in chat app/docs/fetch script to `leehack/llama-web-bridge-assets@v0.1.5`.
  * Updated HF static chat-app deploy workflow to emit COI `custom_headers` in generated Space README frontmatter.

* **Android arm64 CPU variant policy and loader hardening**:
  * Updated native hook tag pin from `b8138` to `b8157` to consume Android arm64 CPU-variant runtime bundles.
  * Added Android arm64 CPU policy keys in hook config: `cpu_profile` (`full` default, `compact`) and advanced `cpu_variants` override.
  * Added hook tests and Android hook integration coverage to verify pubspec-driven CPU variant packaging behavior.
  * Hardened Android runtime backend loading to resolve CPU variant modules even when backend module directory discovery is unavailable.
  * Added Android runtime smoke helper (`scripts/android_runtime_smoke.sh`) and smoke-plan docs for device verification.
  * **Compatibility note**: no public API breaking changes. `android-arm64` now defaults to `cpu_profile: full`, which may increase package size compared with baseline-only CPU packaging.

## 0.6.3

* **Native runtime sync (llama.cpp b8138)**:
  * Synced bundled native runtime/assets and regenerated bindings from
        `b8099` to `b8138`.
  * Pulled in Android arm64 ISA compatibility hardening (including STLUR
        guard changes) to prevent launch-time crashes on older devices.
* **Example app performance and UX polish**:
  * Reduced settings-write overhead during frequent parameter adjustments.
  * Improved model manager responsiveness during download progress updates.
  * Smoothed chat streaming auto-follow and rendering to reduce unnecessary UI work.
* **Web model handling improvements**:
  * Updated web "Download" behavior to verify remote model/mmproj availability without pre-buffering large GGUF payloads in app memory.
  * Clarified that web cache population occurs when a model is first loaded.
* **Stability and quality**:
  * Added safe fallback handling for invalid persisted log-level settings.
  * Added regression tests for persisted settings fallback behavior.
* **New example app**:
  * Added `example/tui_coding_agent`, a `nocterm`-based terminal coding agent with tool-calling loop, workspace-scoped file/command tools, and runtime model switching.
  * Default model source is GLM 4.7 Flash (`unsloth/GLM-4.7-Flash-GGUF:UD-Q4_K_XL`) with support for custom local paths/URLs/Hugging Face shorthand.
  * Added stable text-protocol tool mode as the default (native template grammar tool-calling remains available via `--native-tool-calling` for experimentation).

## 0.6.2

* **Native inference performance improvements**:
  * Reduced request overhead by caching model metadata and skipping
        unnecessary prompt token counting in `create(...)`.
  * Improved native stream throughput with worker-side token chunk batching
        and configurable thresholds (`streamBatchTokenThreshold`,
        `streamBatchByteThreshold`).
  * Added prompt-prefix reuse for native text generation
        (`reusePromptPrefix`, enabled by default) with conservative full-replay
        fallback to preserve deterministic parity.
  * Optimized `ChatSession` context trimming using bounded turn-offset
        search to avoid repeated linear recount loops on long histories.
* **Benchmarking and parity tooling**:
  * Added `tool/testing/native_inference_benchmark.dart` for TTFT,
        throughput, and latency measurement with tunable generation settings.
  * Added `tool/testing/native_prompt_reuse_parity.dart` and curated prompt
        sets for deterministic prompt-reuse parity validation.
  * Added CI prompt-reuse parity checks to catch native reuse regressions.

## 0.6.1

* **Publishing compatibility fix**:
  * Moved hook backend-config support code out of `hook/src/` into
        `lib/src/hook/` because pub.dev currently only allows `hook/build.dart`
        under hook files.
  * Updated hook/test imports accordingly to keep native-assets backend
        selection behavior unchanged.

* **llama.cpp parity expansion (Dart-native template/parser pipeline)**:
  * Reworked template detection/render/parse routing to align with llama.cpp semantics across supported chat formats, including format-specific tool-call parsing and fallback behavior.
  * Added PEG parity components in Dart (`peg_parser_builder`, `peg_chat_parser`) and integrated parser-carrying render/parse flow for PEG-native/constructed formats.
  * Removed brittle fallback coercions that could mutate valid tool names/argument keys, preserving model-emitted tool payloads for dispatch parity.
  * Hardened template capability detection with Jinja AST + execution probing, while preventing typed-content false positives caused by raw content stringification.
  * **[BREAKING]** Removed legacy custom template-handler APIs:
        `ChatTemplateMatcher`, `ChatTemplateRoutingContext`,
        `ChatTemplateEngine.registerHandler(...)`,
        `ChatTemplateEngine.unregisterHandler(...)`,
        `ChatTemplateEngine.clearCustomHandlers(...)`,
        `ChatTemplateEngine.registerTemplateOverride(...)`,
        `ChatTemplateEngine.unregisterTemplateOverride(...)`,
        `ChatTemplateEngine.clearTemplateOverrides(...)`, and
        per-call `customHandlerId` / parse `handlerId` routing.
  * Removed silent render/parse fallback paths so handler/parser failures are surfaced instead of downgraded to content-only output.
  * Added llama.cpp-equivalent per-call template globals/time injection via `chatTemplateKwargs` and `templateNow`.
* **Parity test coverage and tooling**:
  * Added vendored llama.cpp template parity integration coverage for detection + render + parse paths.
  * Added upstream llama.cpp chat/template suite runners and local E2E harness (`run_llama_cpp_chat_tests.sh`, `run_template_parity_suites.sh`).
  * Added mirrored unit tests for new internal template components (`peg_parser_builder`, `template_internal_metadata`) to satisfy structure guards.
* **Test cleanup and maintainability**:
  * Reduced noisy diagnostics in template integration tests and centralized format sample parse payload fixtures for easier parity maintenance.
* **Native integration cleanup (llamadart-native migration)**:
  * Added `tool/testing/prepare_llama_cpp_source.sh` to fetch/refresh `ggml-org/llama.cpp` into `.dart_tool/llama_cpp` (or `LLAMA_CPP_SOURCE_DIR`) pinned to a resolved ref (`LLAMA_CPP_REF`, default `latest` release tag).
  * Updated `tool/testing/run_llama_cpp_chat_tests.sh` to use prepared `.dart_tool` source instead of `third_party/llama_cpp`, so local upstream chat-suite runs no longer depend on vendored source.
  * Updated template parity tests to resolve fixtures from `LLAMA_CPP_TEMPLATES_DIR` or `.dart_tool/llama_cpp/models/templates` instead of `third_party/llama_cpp`.
  * Clarified README backend matrix notes: `KleidiAI`/`ZenDNN` are CPU-path optimizations, not selectable runtime backend modules.
  * Runtime backend probing for split-module bundles now runs during backend initialization (not only after first model load), so device/backend availability is visible earlier in app flows.
  * Native-assets hook output now refreshes emitted native files per build to prevent stale backend module carryover when backend config changes.
* **Linux runtime/link validation and backend loader hardening**:
  * Hardened split-module backend loading to avoid probing backends that are not bundled for the active platform/arch, reducing noisy optional-backend load failures.
  * Added failed-backend memoization so missing optional modules are not retried on every model load.
  * Tightened Linux cache source selection to the current ABI bundle (`linux-arm64` vs `linux-x64`) when preparing runtime dependencies.
  * Added Linux backend/runtime setup guidance in README, including distro-specific package baselines (Ubuntu/Debian, Fedora/RHEL/CentOS, Arch).
  * Added reproducible Docker link-check flows for baseline (`cpu`/`vulkan`/`blas`) and optional `cuda`/`hip` module dependency resolution.
  * Added `scripts/check_native_link_deps.sh` helper plus dedicated validation images:
        `docker/validation/Dockerfile.cuda-linkcheck` and
        `docker/validation/Dockerfile.hip-linkcheck`.
* **Chat example backend UX cleanup**:
  * Removed user-facing `Auto` backend option from settings; only concrete runtime-detected backends are shown.
  * Added migration behavior that resolves legacy saved `Auto` preference to the best detected backend at runtime.

## 0.5.4

* **llama.cpp parity hardening**:
  * `ChatTemplateEngine` now preserves handler-provided tokens even when grammar is attached via params, avoiding token-loss regressions in tool/thinking formats.
  * Native stop-sequence handling now skips preserved tokens so parser-critical markers are not terminated early.
  * Generic tool-instruction system injection now follows llama.cpp semantics more closely (replace first system content when supported, otherwise prepend to first message content).
  * LFM2 output parsing now extracts reasoning more consistently across tool and non-tool output shapes.
* **Chat example loop/lifecycle hardening**:
  * Improved tool-loop guards (first-turn force-only behavior, duplicate/equivalent call suppression, per-tool budget, and loop-stop messaging).
  * Added response fallback that can ground final answers from recent tool results when the model emits stale real-time disclaimers.
  * Added assistant debug badges (`fmt:*`, `think:*`, `content:json`, `fallback:tool-result`) and strengthened detach/exit disposal paths.
* **Parity/integration test robustness**:
  * `tool_calling_integration_test` now accepts both structured `tool_calls` deltas and XML-style `<tool_call>` payloads.
  * llama.cpp template-detection integration expectations were updated for current Ministral-family routing outcomes.
* **Documentation updates**:
  * Clarified chat app behavior when models return JSON-shaped assistant content (for example `{"response":"..."}`) and documented `content:json` diagnostics.
  * Documented example server sampling defaults (`penalty=1.0`, `top_p=0.95`, `min_p=0.05`) and added a CLI README batch parity-matrix usage example.

* **Chat app backend/status fixes**:
  * Backend switching now preserves configured `gpuLayers` while still allowing load-time CPU enforcement.
  * Runtime backend labeling and GPU activity diagnostics now follow effective user selection, preventing false "VULKAN active" status when CPU mode is selected.
* **Context size auto mode**:
  * Restored support for `Context Size: Auto` by preserving `0` in persisted settings and passing auto behavior through to session context-limit resolution.
* **Tool-call parsing fixes (Hermes)**:
  * Introduced staged double-brace recovery: parse as-is first, unwrap one outer `{{...}}` layer second, and only fall back to full `_normalizeDoubleBraces` when all braces are consistently doubled.
  * Added a consistency gate to `_normalizeDoubleBraces` that bails out on mixed single/double brace payloads to prevent corruption of valid nested JSON.
* **Tool-call parsing fixes (Magistral)**:
  * Broadened whitespace skipping in `_extractJsonObject` to handle `\n`, `\r`, and `\t` between `[ARGS]` and the JSON body.
* **Example app (basic\_app)**:
  * Replaced `toList()` buffering with `await for` streaming for real-time token yield.
  * Added `tools` parameter to every follow-up `create()` call and bounded tool-execution loop with `_maxToolRounds = 10`.
* **Test coverage**:
  * Added chat app regression tests for backend switching behavior and context-size auto persistence.
  * Added regression tests for Hermes wrapped+nested double-brace payloads and Magistral `[ARGS]` with newline/nested arguments.
* **Example rename (server)**:
  * Renamed `example/api_server` to `example/llamadart_server`.
  * Renamed the example package/bin entrypoint to `llamadart_server`.
  * Updated llama.cpp tool-call parity defaults/docs to target `example/llamadart_server`.
* **GLM 4.5 template parity**:
  * Added XML tool-call grammar generation for `<tool_call>` payloads with `<arg_key>/<arg_value>` pairs.
  * Added GLM-specific preserved tokens and `<|user|>` stop handling for tool-call flows.
  * Updated parser extraction to handle GLM XML tool calls from assistant content and reasoning blocks.
* **Template/native runtime fixes**:
  * Typed-content template rendering now activates only when messages actually include media parts.
  * Native context reset now clears llama memory in-place instead of reinitializing the context.

## 0.5.3

* **Sampling controls**:
  * Added `minP` to `GenerationParams` with a default value of `0.0` and `copyWith` support.
* **Native backend parity**:
  * Added optional llama.cpp `min_p` sampler initialization in `LlamaCppService` when `minP > 0`.
* **Test coverage**:
  * Added unit coverage for `GenerationParams.minP` default and `copyWith` behavior.

## 0.5.2

* **Chat template parity hardening**:
  * Expanded llama.cpp parity across additional format handlers, including grammar construction, lazy-grammar triggers, preserved tokens, and parser behavior for tool-call payload extraction.
  * Added shared `ToolCallGrammarUtils` helpers for wrapped object/array tool-call grammar generation and root-rule wrapping.
* **Crash fix (grammar parsing)**:
  * Fixed malformed GBNF escaping in Hermes/Command-R string rules that could cause runtime `llama_grammar_init_impl` parse failures during tool-calling generations.
* **Test coverage expansion**:
  * Added and expanded handler-level parity tests (Apertus, LFM2, Nemotron V2, Magistral, Seed-OSS, Xiaomi MiMo, DeepSeek R1/V3, Hermes) and mirrored unit tests for new grammar utilities.

## 0.5.1

* **Documentation fixes**:
  * Updated README internal links to absolute GitHub URLs so they resolve reliably on pub.dev.
  * Updated release/migration wording after 0.5.0 publication and refreshed installation/version snippets.
  * Corrected iOS simulator architecture notes and contributor prerequisites/build target docs.
* **Publishing hygiene**:
  * Expanded `.pubignore` to exclude local build outputs, large model/test artifacts, and checked-out `third_party` sources from package uploads.

## 0.5.0

* **[BREAKING] Public API Changes**:
  * Root exports were tightened; previously exposed internals such as `ToolRegistry`, `LlamaTokenizer`, and `ChatTemplateProcessor` are no longer part of the public package API.
  * `ChatSession` now centers on `create(...)` streaming `LlamaCompletionChunk`; legacy `chat(...)` / `chatText(...)` style usage must migrate.
  * `LlamaChatMessage` constructor names were standardized (`.fromText`, `.withContent`) in place of older named constructors.
  * Default `maxTokens` in `GenerationParams` increased from `512` to `4096`.
  * `LlamaChatMessage.toJson()` no longer includes `name` on `tool` role messages.
  * `ModelParams.logLevel` was removed; logging control now lives on `LlamaEngine` via `setDartLogLevel(...)` and `setNativeLogLevel(...)`.
  * `LlamaBackend` interface changed for custom backend implementers (notably `getVramInfo` and updated `applyChatTemplate`).
  * Model reload behavior is stricter: `loadModel(...)` now requires unloading first.
  * Migration details are documented in `MIGRATION.md`.

* **Template/Parser Parity Expansion**:
  * Added llama.cpp-aligned format detection and handlers for additional templates including FireFunction v2, Functionary v3.2, Functionary v3.1 (Llama 3.1), GPT-OSS, Seed-OSS, Nemotron V2, Apertus, Solar Open, EXAONE MoE, Xiaomi MiMo, and TranslateGemma.
  * Improved parser parity for format-specific tool-calling and reasoning extraction, including `<|python_tag|>` parsing for Llama 3 flows.
  * Narrowed generic grammar auto-application to generic/content-only routing to avoid interfering with format-specific tool schemas.
* **Template Extensibility APIs**:
  * Added global custom handler registration and template override APIs in `ChatTemplateEngine`.
  * Added per-call `customTemplate` and `customHandlerId` routing support and threaded handler identity into parse paths.
  * Added cookbook examples and regression tests for registration precedence and fallback behavior.
* **Logging Controls**:
  * Added split logging controls in `LlamaEngine`: `setDartLogLevel` and `setNativeLogLevel`, while keeping `setLogLevel` as a convenience method.
  * Fixed native `none` log level suppression so llama.cpp/ggml logs are fully muted when requested.
* **Chat App Improvements**:
  * Added model capability badges and per-model generation presets.
  * Added template-aware tool enablement guardrails and separate Dart/native log level settings in the UI.
* **Test Suite Overhaul**:
  * Expanded template parity coverage (detection, handlers, grammar, workarounds, registry precedence, and integration scenarios).
  * Added additional unit tests for exceptions, logging, and core model definitions.

## 0.4.0

* **Cross-Platform Architecture**:
  * Refactored `LlamaBackend` for strict Web isolation using "Native-First" conditional exports, ensuring native performance and full web safety.
  * Standardized backend instantiation via a unified `LlamaBackend()` factory across all examples and scripts.
* **Web & Context Stability**:
  * Resolved "Max Tokens is 0" on Web by implementing `getLoadedContextInfo()` and robust GGUF metadata fallback in `LlamaEngine`.
  * Improved numeric metadata extraction on Web for better compatibility with varied GGUF exporters.
* **GBNF Grammar Stability**:
  * Resolved "Unexpected empty grammar stack" crash by reordering the sampler chain (filtering tokens via GBNF *before* performing probability-based sampling).
* **Test Suite Overhaul**:
  * Pivoted from mock-based unit tests to real-world integration tests using the actual `llama.cpp` native backend.
  * Ensured full verification of model loading, tokenization, text generation, and grammar constraints against physical models.
  * **Multi-Platform Configuration**: Introduced `dart_test.yaml` and `@TestOn` tags to enable seamless execution of all tests across VM and Chrome with a single `dart test` command.
* **Robust Log Silencing**:
  * Implemented FD-level redirection (`dup2` to `/dev/null`) for `LlamaLogLevel.none` on native platforms.
  * This provides a crash-free alternative to FFI-based log callbacks, which were unstable during low-level native initialization (e.g., Metal).
* **Project Hygiene**:
  * Achieved 100% clean `dart analyze` across the core library and all example applications.
  * Replaced legacy stubs in the chat application with a clean, interface-based `ModelService` architecture.
* **Resumable Downloads**:
  * Implemented robust resumable downloads for large models using HTTP Range requests.
  * Added persistent `.meta` files to track download progress across app restarts.
* **Enhanced Download UI**:
  * Refined the `ModelCard` with a visual **Pause/Resume toggle**.
  * Added a **Trash icon** in the card header for full cancellation and data discard of active or partial downloads.
  * Improved progress feedback with clear "Paused" and "Downloading" states.
* **Multimodal Support (Vision & Audio)**: Integrated the experimental `mtmd` module from `llama.cpp` for native platforms.
  * Added `loadMultimodalProjector` to `LlamaEngine`.
  * Introduced `LlamaChatMessage.withContent` and `LlamaContentPart` (Text, Image, Audio).
  * **Fix**: Resolved missing multimodal symbols in native builds by properly linking the `mtmd` module.
* **Moondream 2 & Phi-2 Optimization**:
  * Implemented a specialized `Question: / Answer:` chat template fallback for Moondream models.
  * Added dynamic BOS token handling: Automatically disables BOS injection for models where BOS == EOS (like Moondream) to prevent immediate "End of Generation".
* **Chat API Consolidation**:
  * Moved high-level `chat()` and `chatWithTools()` logic from `LlamaEngine` to `ChatSession`.
  * `LlamaEngine` is now a dedicated low-level orchestrator for model loading, tokenization, and raw inference.
* **Intelligent Tool Flow**:
  * **Optional Tool Calls**: Tools are no longer forced by default. The model now decides when to use a tool vs. responding directly based on context.
  * **Final Response Generation**: After a tool returns a result, the model now generates a natural language response (without grammar constraints) to interpret the result for the user.
  * **forceToolCall**: Added a session-level flag to re-enable strict grammar-constrained tool calls for smaller models (e.g., 0.5B - 1B).
* **App Stability & Resources**:
  * Fixed a crash in the Flutter chat app during close/restart by implementing and using an idempotent `dispose()` in `ChatService`.
  * Added Qwen 2.5 3B and 7B models to the download list with clear RAM/VRAM requirements for testing complex instruction following and tool use.
* **ChatSession Manager**: Introduced a new high-level `ChatSession` class to automatically manage conversation history and system prompts.
* **Context Window Management**: `ChatSession` now implements an automated sliding window to truncate history when the model's context limit is approached.
* **Windows Robustness**:
  * Improved export management for MSVC to ensure symbol visibility.
  * Added Sccache support for Windows builds to significantly improve CI performance.
* **Automated Lifecycle**:
  * Implemented GitHub Actions to automate `llama.cpp` updates, regression testing, and release artifact generation.
* **[BREAKING] API Changes**:
  * `LlamaChatMessage.role` now returns a `LlamaChatRole` enum instead of a `String`. All manual role string comparisons should be updated to use the enum.
* **[DEPRECATED] API Changes**:
  * Default `LlamaChatMessage` constructor (string-based) is now deprecated; use `.fromText()` or `.withContent()` instead.
  * `LlamaChatMessage.roleString` is deprecated and will be removed in v1.0.
* **Engine Upgrades**: Upgraded core `llama.cpp` to tag `b7898`.
* **Robust Media Loading**: Support for loading images and audio via both file paths and raw byte buffers.
* **Bug Fixes**: Improved native resource cleanup and fixed potential null-pointer crashes in the multimodal pipeline.

## 0.3.0

* **[BREAKING] Removal of `LlamaService`**: The legacy `LlamaService` facade has been removed. Use `LlamaEngine` with `LlamaBackend()` instead for all platforms.
* **LoRA Support**: Added full support for Low-Rank Adaptation (LoRA) on all native platforms (iOS, Android, macOS, Linux, Windows).
* **Web Improvements**: Significantly enhanced the web implementation using `wllama` v2 features, including native chat templating and threading info.
* **Logging Refactor**: Implemented a unified logging architecture.
  * **Native Platforms**: Simplified to an on/off toggle to ensure stability. `LlamaLogLevel.none` suppresses all output; other levels enable default stderr logging.
  * **Web**: Supports full granular filtering (Debug, Info, Warn, Error).
* **Stability Fixes**: Resolved frequent "Cannot invoke native callback from a leaf call" crashes during Flutter Hot Restarts by refactoring native resource lifecycle.
* **Improved Lifecycle**: Removed `NativeFinalizer` dependency to avoid race conditions. Explicitly call `dispose()` to release native resources.
* **Robust Loading**: Improved model loading on all platforms with better instance cleanup, script injection, and URL-based loading support.
* **Dynamic Adapters**: Implemented APIs to dynamically add, update scale, or remove LoRA adapters at runtime.
* **LoRA Training Pipeline**: Added a comprehensive Jupyter Notebook for fine-tuning models and converting adapters to GGUF format.
* **API Enhancements**: Updated `ModelParams` to include initial LoRA configurations and introduced `supportsUrlLoading` for better platform abstraction.
* **CLI Tooling**: Updated the `basic_app` example to support testing LoRA adapters via the `--lora` flag.

## 0.2.0+b7883

* **Project Rebrand**: Renamed package from `llama_dart` to `llamadart`.
* **Pure Native Assets**: Migrated to the modern Dart Native Assets mechanism (`hook/build.dart`).
* **Zero Setup**: Native binaries are now automatically downloaded and bundled at runtime based on the target platform and architecture.
* **Version Alignment**: Aligned package versioning and binary distribution with `llama.cpp` release tags (starting with `b7883`).
* **Logging Control**: Implemented comprehensive logging interception for both `llama` and `ggml` backends with configurable log levels.
* **Performance Optimization**: Added token caching to message processing, significantly reducing latency in long conversations.
* **Architecture Overhaul**:
  * Refactored Flutter Chat Example into a clean, layered architecture (Models, Services, Providers, Widgets).
  * Rebuilt CLI Basic Example into a robust conversation tool with interactive and single-response modes.
* **Cross-Platform GPU**: Verified and improved hardware acceleration on macOS/iOS (Metal) and Android/Linux/Windows (Vulkan).
* **New Build System**: Consolidated all native source and build infrastructure into a unified `third_party/` directory.
* **Windows Support**: Added robust MinGW + Vulkan cross-compilation pipeline.
* **UI Enhancements**: Added fine-grained rebuilds using Selectors and isolated painting with RepaintBoundaries.

## 0.1.0

* **WASM Support**: Full support for running the Flutter app and LLM inference in WASM on the web.
* **Performance Improvements**: Optimized memory usage and loading times for web models.
* **Enhanced Web Interop**: Improved `wllama` integration with better error handling and progress reporting.
* **Bug Fixes**: Resolved minor UI issues on mobile and web layouts.

## 0.0.1

* Initial release.
* Supported platforms: iOS, macOS, Android, Linux, Windows, Web.
* Features:
  * Text generation with `llama.cpp` backend.
  * GGUF model support.
  * Hardware acceleration (Metal, Vulkan).
  * Flutter Chat Example.
  * CLI Basic Example.
