---
title: Recent releases
description: Review recent llamadart release highlights and jump to the canonical changelog for full release notes.
---

For canonical full release notes, use:

- [`CHANGELOG.md`](https://github.com/leehack/llamadart/blob/main/CHANGELOG.md)

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
- Aligned default WebGPU bridge assets to `v0.1.54`, unchanged from 0.11.0:
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
- Aligned default WebGPU bridge assets to `v0.1.54`, unchanged from 0.10.0:
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
- Aligned default WebGPU bridge assets to `v0.1.54`, unchanged from 0.9.0:
  they embed llama.cpp `v0.5.0`, are qualified against native `v0.5.0`, and keep
  Web/native llama.cpp `v0.5.0@7fe450e19305b828c199d602c23a8337aaa1f03b` parity
  and Web `@litert-lm/core@0.15.0`. Immutable Web asset manifest:
  `8a9f83c15035eeb034a6563e6f753382d7d7f9be81503ef76902138da7841176`.

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
- Add `LlamaEngine.scoreNextToken(...)` for next-token log-probabilities on
  native llama.cpp and WebGPU bridge assets `v0.1.52+`, matching llama-server
  `n_probs`; check
  `supportsNextTokenScoring` first
  ([#694](https://github.com/leehack/llamadart/issues/694)).
- Add `example/laya_command_bar`, a Flutter text field that reshapes into a
  reminder, message, calculation or other command as you type, read by a
  Laya decision model, by EmbeddingGemma and labelled examples, or by small
  LLMs' next-token scores, including the decision model decider-2b.
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
- Throw `LlamaModelException` when native llama.cpp cannot find or load a
  multimodal projector, and `LlamaUnsupportedException` when the runtime lacks
  the mtmd functions; `LlamaEngine.supportsAudio` also throws the latter.
  Speech-to-text capabilities now say when no projector is loaded, using the
  new `LlamaEngine.hasMultimodalProjector`
  ([#325](https://github.com/leehack/llamadart/issues/325)).
- Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@v0.5.0` (llama.cpp `v0.5.0`) with Apple companion
  `0.0.20`, regenerated matching Dart FFI bindings, refreshed the `llamadart_llama_cpp_flutter` Apple SwiftPM
  checksum, and aligned current README/website native override docs.
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
- Aligned default WebGPU bridge assets to `v0.1.54` for the decision API,
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
- Aligned default WebGPU bridge assets to `v0.1.44` for matching
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

- Fail Apple builds before native symbol lookup when the resolved llama.cpp
  companion does not match the core native runtime, with actionable upgrade
  guidance.

- Adopted native llama.cpp v0.4.0 with matching bindings and multimodal calls.
  Saved native sessions from older runtimes must be regenerated. Apple companion
  `0.0.18` supplies the matching native runtime.

- Aligned default WebGPU bridge assets to `v0.1.43` for Web/native
  llama.cpp `v0.4.0@5266f24da75dc449bd56cbed7addb9c8e4a6a73e` parity.
  Web `@litert-lm/core@0.15.0` and native LiteRT pins are unchanged. Immutable
  manifest: `111eefc3588842cebfe665b363378edca34924764610263e1eda5280dfcfaa27`.

- Known upstream limitation: llama.cpp v0.4.0 can reject large grammar
  repetitions, such as `root ::= "a"{2000}`. The post-v0.4.0 correction is
  tracked in [native #76](https://github.com/leehack/llamadart-native/issues/76)
  and is not included in this release.

## 0.8.22

- Updated `llamadart_llama_cpp_flutter` to `0.0.17` with the
  Apple SwiftPM `v0.3.0` runtime pin.

- Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@v0.3.0`, regenerated matching Dart FFI bindings,
  refreshed the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and
  aligned current README/website native override docs.

- Aligned default WebGPU bridge assets to `v0.1.41` for corrected
  TypeScript declarations and TTS recovery guidance, retaining Web/native
  llama.cpp `v0.3.0@c1d0e7a004015f23bc0233470b747b596f29b264` parity and Web
  `@litert-lm/core@0.15.0`. Immutable manifest:
  `fe97604daabaad6aefa223a8637d5fd9dcac09dd4a61b2ef19cd6aabb39392b9`.

- Consolidated native release tag grammar across Dart, Python, Bash, workflows,
  and documentation via a machine-readable fixture contract (`#404`).

## 0.8.21

- Aligned default WebGPU bridge assets to `v0.1.39` (immutable manifest
  `b355d01040604f6ae2c5c5fe5bb42b858101a96f03f67e4b27b32fe41ce3b2bf`),
  restoring Web and native llama.cpp upstream
  `v0.2.0@bb4caa7540188872173c44d161602d9271386413` parity with native
  anchor `llamadart-native@v0.2.0-1` while preserving Web
  `@litert-lm/core@0.15.0` packaging.

- Fixed native Qwen3-ASR transcription by applying the model chat template to
  audio turns, while preserving the validated raw-prompt Web bridge contract.
  Empty ASR output now fails explicitly instead of reporting an empty result.

- Fixed Qwen 2.5/3 LiteRT-LM `ToolChoice.required` requests silently running
  without their required-call grammar and finishing with no call. They now fail
  with an actionable `LlamaUnsupportedException` before generation when the
  backend cannot enforce the declared tool schema; Gemma 4 compatibility and
  `auto`/`none` tool routing are unchanged.

- Fixed Gemma 4 thinking-budget output so split channel controls and tool-call
  envelopes stay out of visible assistant content while preserving ordinary
  whitespace. The chat example now also validates custom tool declarations,
  executes declared host handlers exactly once, appends tool results, and
  performs a bounded continuation for both llama.cpp and LiteRT-LM backends.

- Patched the website's vulnerable `nanoid` and `uuid` dependency paths. Until
  Docusaurus replaces its unpatched image parser, automatic local Markdown
  images are rejected; website contributors should use static pathname URLs.

- Fixed `llamadart_native_runtimes` values `none`, `off`, and the string
  `false` selecting every runtime family instead of none;
  the build hook fails with its `No native runtimes selected` error again, as
  it did before 0.8.0. A YAML boolean `false` clears the selection too. Unset,
  empty, and all-unrecognised config still select every family.

- The published package no longer ships the `doc/` directory; that contributor
  and maintainer documentation is maintained on GitHub, and the packaged files
  that link to it now use absolute URLs.

- Fixed unanchored `docs/` and `website/` publish-exclusions that matched those
  directory names at any depth and dropped `tool/docs/` plus the
  `llamadart_server` example's OpenAPI spec and Swagger UI sources from the
  package, leaving the published example unable to analyze. Both patterns are
  now root-anchored.

- Narrowed the `dinja` dependency constraint to `>=1.0.0 <1.1.0` so chat
  template capability detection cannot silently resolve against an unverified
  Jinja parser minor. A 1.0.x patch can still reorganise the private sources
  the analyzer imports; a new coupling test turns that into a named failure.

- Fixed Command R7B, Hermes, and Hunyuan V3 tool grammars so distinct tool or
  parameter names cannot collide after conversion to internal GBNF rule names.

- Fixed DeepSeek V3.2 DSML tool calls using their upstream
  `<｜DSML｜function_calls>` envelope while preserving DeepSeek V4's distinct
  `<｜DSML｜tool_calls>` grammar and parser behavior.

- Fixed partial GLM 4.5, Poolside Laguna, and Muse Glimmer tool envelopes
  leaking into streamed assistant content, while preserving completed calls,
  malformed final output, and ordinary text surrounding Muse recipient
  channels.

- Fixed schema-constrained tool calls for Kimi K3, MiniMax M1/M3, DeepSeek
  V3.2/V4, and Muse Glimmer, including exact escaped names, required fields,
  declared value types, matching MiniMax M3 element tags, zero-argument calls,
  and strings containing delimiter characters. Required-tool mode now accepts
  each format's reasoning/content prefix while still requiring a call.
  MiniMax M3, DeepSeek DSML, Muse Glimmer, Poolside Laguna, and GLM 4.5 now
  reconstruct argument values from the declared tool schema instead of
  guessing from text. Added `ToolParam.nullType` for null-only JSON Schema
  properties.

- Made native video-input capability truthful without claiming end-to-end
  support. Explicit video content now receives a typed actionable rejection,
  public capability remains false, and the native probe calls
  `mtmd_helper_support_video` because helper symbols are exported even when
  video is compiled out. Full support still requires companion FFmpeg/ffprobe
  packaging and Dart frame-lifecycle wiring.

- Native release synchronization and build-hook overrides now accept stable
  `vMAJOR.MINOR.PATCH` artifacts and ordered `vMAJOR.MINOR.PATCH-N` wrapper
  rebuilds plus nightly `bNNNN-N` rebuilds, while preserving historical
  `bNNNN` and `bNNNN-llamadart.N` artifacts. Leading-zero nightly tags,
  rollback, wrapper/nightly `latest` results, missing bundles, and
  manifest/checksum/version skew fail closed; the default native pin is
  unchanged.

- Fixed Web/native backend API parity. `WebAutoBackend` now forwards grammar
  constraint support from its active runtime, so strict structured output fails
  early with an actionable error on unsupported Web backends, and the Web-safe
  `LiteRtLmRuntimeClient` stub now exposes the native client's thinking-tag
  configuration method.

- A failed llama.cpp model load now reports the startup diagnostics collected
  during native library discovery, so a missing or unloadable runtime library
  explains itself instead of surfacing as a bare load failure. Platforms that
  record no diagnostics keep their previous message unchanged.

- llama.cpp worker errors now keep their type. Every backend method routes an
  `ErrorResponse` through the file's own error mapper instead of rebuilding a
  bare `Exception`, `tokenize` and `detokenize` no longer discard the worker's
  error entirely, and a core `UnsupportedError` raised for an unavailable native
  capability is classified rather than flattened. State-file failures now throw
  `LlamaStateException`.

- Fixed multimodal media placeholders being normalized inconsistently. `<img>`,
  `<|img|>`, `<start_of_image>` and indexed markers such as `<|image_1|>` are now
  rewritten to the mtmd marker on every path, rather than depending on which
  layer rendered the prompt. MiniMax-M2 and MiniCPM-5 also now detect a
  forced-open thinking block using the same rule as every other handler.

- aLoRA adapters are now rejected with `LlamaUnsupportedException` instead of
  being applied like ordinary LoRA adapters. An aLoRA adapter must activate only
  after its invocation tokens appear in the prompt, so applying it from the
  start of generation silently changed output. Missing metadata-inspection
  symbols in custom native runtimes also fail closed with the same typed error,
  and rejected adapters are released when the cleanup ABI is available. LoRA
  errors from the worker keep their typed exception instead of arriving as a
  bare `Exception`, and a failed adapter load now throws
  `LlamaModelException`.

- Deprecated `LiteRtLmRuntimeClient.conversationTokenCount()` and
  `replaceConversationWithClone()`. Both are unused and are scheduled for
  removal in the next major release; open an issue if you depend on either.

- `NativeLlamaBackend.modelLoadFromUrl` now throws `LlamaUnsupportedException`
  instead of `UnimplementedError`, bringing it into the `LlamaException`
  hierarchy. It is the same exception type `LlamaEngine.loadModelFromUrl`
  already throws for this condition; each keeps its own message.

- Updated the default native llama.cpp runtime to the immutable
  `leehack/llamadart-native@v0.2.0-1` release (llama.cpp `v0.2.0`), adding LFM2
  DSpark support plus current upstream correctness and backend performance
  fixes. Matching Dart FFI bindings, including the new multimodal
  projector-device field, and the Apple SwiftPM artifact checksum were
  refreshed. Linux `libmtmd.so.0` now loads without the old
  `libmtmd.so.SOVERSION` compatibility alias.

- Removed the abandoned Dart-side MTP/n-gram speculative-decoding scaffolding
  from the llama.cpp backend; speculative decoding behavior is unchanged.

- Bumped `llamadart_llama_cpp_flutter` to `0.0.16` so the `v0.2.0-1` Apple
  SwiftPM pin actually publishes; `0.0.14` was already on pub.dev, so release
  automation skipped it and Apple builds would have kept the `b10514` runtime.

- Corrected the WebGPU bridge docs, which claimed the pinned `v0.1.37` bridge
  assets match the default native llama.cpp runtime. They embed `b10514` and now
  trail the native `v0.2.0-1` pin.

- Chat-template capability detection now logs a debug message naming the
  probe (`string-content`, `typed-content`, `system-role`, `tools`) when its
  render throws, so a template that fails to render is distinguishable from
  one that genuinely lacks the capability.

## 0.8.20

- Updated WebGPU bridge assets to `v0.1.37` (llama.cpp `b10514`), restoring
  native/Web parity and provisioning an explicit 1 MiB Wasm stack for wasm32
  and memory64 so Qwen3-ASR memory64 context construction does not overflow the
  default stack.

- Improved Web microphone transcription with browser-capture warmup trimming
  and early short, silent, and unsupported PCM WAV diagnostics.

- Added logical and micro-batch controls for llama.cpp/WebGPU models to the
  Flutter chat example.

- Made Android Auto probe the packaged Vulkan device before choosing GPU
  offload, avoiding unnecessary CPU fallback on capable models.

- Updated the native LiteRT-LM runtime to `v0.16.0-native.2`; the Apple companion
  packages the iOS Gemma constraint provider and Metal plugins required by the
  published runtime.

- Added an experimental `SpeechToTextEngine.liteRtLm` path with bounded mono
  16 kHz float PCM, partial/final transcript events, worker-isolated CPU
  inference, backpressure, and cancellation.

- Added experimental live English dictation to native Flutter chat models,
  including generic audio-chat models, using selectable checksum-pinned
  Moonshine Tiny (recommended, 54 MB) and Parakeet TDT 0.6B (optional, 615 MB)
  LiteRT sidecars. Live dictation is CPU-only, English-only, capped at five
  minutes, and unavailable on Linux and Web. Audio-chat models retain **Ask
  with voice** as a separate action.

- Improved Flutter chat example model downloads with bounded retries for
  transient network failures, safe resume after truncated responses, and a
  distinct integrity-verification state after transfer reaches 100%. The
  redesigned onboarding and Lab surfaces preserve model-card position while
  downloads reorder and keep streaming responses from pulling users away from
  chat history.

- Added experimental typed Qwen3-TTS synthesis on native llama.cpp and WebGPU
  with capability discovery, cancellation, speaker references, complete
  PCM/WAV output, and synthesis/playback/export controls in the Flutter chat
  example. Apple apps discover the TTS ABI in the embedded llama framework;
  current LiteRT-LM artifacts remain unsupported.

- Updated the native llama.cpp runtime to `b10514`, adding BailingMoE3,
  GraniteSWA/GraniteMoeSWA, speculators-format DSpark checkpoints, and current
  upstream multimodal/backend fixes and performance improvements. Matching Dart
  FFI bindings and the Apple SwiftPM artifact checksum were refreshed.

- Added an experimental typed Qwen3-ASR whole-file transcription workflow, a
  checksum-pinned Qwen3-ASR 0.6B native-and-Web chat-app preset, and file and
  microphone transcription. Web accepts WAV bytes only; native LiteRT-LM live
  dictation remains a separate implementation.

- Added **Ask with voice** to the native Flutter chat example for Gemma 4 E2B
  LiteRT-LM and audio-capable GGUF models. It sends a short microphone recording
  through normal multimodal chat so the model answers the spoken request, while
  remaining separate from typed speech-to-text.

## 0.8.19

- Updated the native llama.cpp runtime to `b10333` and WebGPU bridge assets to
  `v0.1.27` (llama.cpp `b10333`), including matching Dart FFI bindings and
  refreshed Apple SwiftPM artifacts.

- Fixed corrupt Qwen3.5 output on Android Vulkan by preserving the KQV
  offload required for correct hybrid model inference while retaining the
  remaining conservative Android context settings.

## 0.8.18

- Updated native llama.cpp to `b10276`, including Qwen3-TTS model-loading
  primitives, explicit bundled-MTP loading, automatic model-specific token
  suppression, recent model/runtime improvements, the matching load-mode and
  penalty-sampler ABI migrations, and refreshed Apple artifacts. Speech
  generation is not yet exposed through the public Dart API.

- Updated the default LiteRT-LM runtimes to native `v0.15.0-native.3` and Web
  `@litert-lm/core@0.15.0`. The native artifact includes a corrected v0.15
  streaming callback bridge and an Android Dawn rollback for Mali-G715 GPU
  device loss; incompatible callback runtimes now fail safely before
  generation, and concrete macOS app, framework, and cache libraries take
  precedence over process-linked assets.

- Updated WebGPU bridge assets to `v0.1.26` (llama.cpp `b10276`), refreshing
  both WebAssembly runtimes while preserving the existing bridge API.

- Disabled automatic WebGPU fetch-backed model loading by default. Streamed
  loading remains the safe default, with explicit opt-in available for
  controlled range-capable deployments.

## 0.8.17

- Updated the default llama.cpp native runtime to `b10075` with matching
  bindings and Apple artifacts.
- Added Tencent Hunyuan V3 chat-template, reasoning, and tool-call support.
- Fixed Gemma 4 LiteRT-LM text generation in the Web chat app after model
  loading completed successfully.
- Restored GGUF loading in deployed Web chat apps by packaging the pinned
  WebGPU runtime assets with Flutter Web builds.

## 0.8.16

- Updated the default llama.cpp native runtime to `b9982`, including safer
  multimodal UTF-8 prompt handling and refreshed Dart/SwiftPM bindings.
- Improved llama.cpp batching defaults and `ChatSession` context management for
  more predictable generation under constrained contexts.
- Added llama.cpp presence-penalty sampling and thinking-budget controls;
  unsupported WebGPU and LiteRT-LM paths now fail explicitly.
- Reworked the runnable TUI coding agent with a focused Pi-style workflow,
  Unsloth Qwen3.6 defaults, shared model-source loading, and clearer output.
- Improved the OpenAI-compatible server with standard client-managed tool-call
  transcripts, named `tool_choice`, configurable thinking behavior, and shared
  model-source loading.

## 0.8.15

- Added clipboard media attachments to the runnable chat app, including
  `Cmd/Ctrl+V` screenshots and copied image/audio files on desktop and web plus
  a **Paste attachment** action on mobile, while preserving normal text paste.
- Added an app-owned FIFO model-download queue to the runnable chat app, with
  per-card queue positions/cancellation and a responsive shell progress pill
  that remains visible after settings closes.
- Replaced the runnable chat app's broad built-in catalog with a focused
  Unsloth-first set. Added cross-platform Gemma 4 E4B plus native-desktop Gemma
  4 12B/26B-A4B/31B and Qwen3.6 35B-A3B presets. Added downloaded-first ordering,
  name/capability search, Mobile & Web/Desktop filters, clearer incompatible-model
  states, quieter model cards, and independent remove-from-library and
  downloaded-file actions for custom entries.
- Enabled Gemma 4 audio attachments in the runnable chat app for the current
  native GGUF projector and LiteRT-LM bundle while keeping LiteRT-LM Web
  text-only. Persisted capability settings now distinguish direct model media
  input from external `mmproj` input.
- Made native GGUF Auto tuning model- and memory-aware. **Max** now requests
  full llama.cpp offload, while Auto preserves the requested context when the
  model fits and reduces context before selecting partial offload under memory
  pressure. Auto intent persists separately from resolved values so each model
  load, including after an app restart, recalculates current device headroom.
- Fixed native LiteRT-LM response limits being misapplied as forced benchmark
  decode counts. Short answers now stream without waiting for the full token
  allowance, and the chat app flushes the first LiteRT-LM token immediately.
- Updated the default native LiteRT-LM runtime to `v0.14.0-native.2`, fixing
  Android GPU plugin symbol resolution and using the checksum-pinned official
  Apple XCFrameworks for Metal-capable iOS and macOS packaging.

## 0.8.14

- Improved the runnable chat app's web model-cache and loading experience by
  reusing cached GGUF and LiteRT-LM bundles, preserving browser model caches
  during app cache cleanup, allowing text-only downloads without a multimodal
  projector, and polishing download/load progress states.

- Updated the chat app's web runtimes to pinned WebGPU bridge assets `v0.1.18`
  (llama.cpp `b9915`) and `@litert-lm/core@0.14.0` for reproducible hosted and
  local inference.

- Updated the default native llama.cpp runtime to
  `leehack/llamadart-native@b9935`, regenerated matching Dart FFI bindings,
  refreshed the Apple SwiftPM companion checksum, and aligned current runtime
  documentation.

## 0.8.13

- Fixed load lifecycle guards so repeated model loads preserve the active
  model state, URL load unsupported-runtime diagnostics stay typed, and unload
  cancels active generation before freeing llama.cpp handles.

- Tightened LiteRT-LM runtime validation and local smoke coverage by requiring
  complete macOS arm64 runtime caches, adding the missing iOS-compatible
  SwiftPM Gemma provider target, and keeping Flutter macOS LiteRT-LM
  companion-package builds on hook-managed native assets while the current
  SwiftPM artifact set is incomplete.

- Reworked the README into a shorter entry point, fixed stale docs/examples
  found during the documentation review, and aligned release, Android smoke,
  WebGPU mem64, native sync, and capability-support wording with the current
  workflows and runtime behavior. WebGPU runtime LoRA calls now throw an
  unsupported-operation error instead of reporting no-op success.

- Fixed llama.cpp n-gram speculative configuration mapping so
  `draftTokenMax` no longer implicitly overrides upstream `ngramSizeM`, and
  documented upstream comparison commands plus measured n-gram benchmark
  results.

- Added llama.cpp upstream speculative decoding parity through
  `SpeculativeDecodingConfig` constructors for draft-simple, EAGLE3, MTP,
  DFlash, ngram-simple, ngram-map-k, ngram-map-k4v, ngram-mod, ngram-cache,
  and mixed n-gram plus one draft-model strategy, including generic native
  wrapper bindings, docs, and local benchmark matrix coverage. The benchmark
  tooling can generate a llama.cpp-compatible static n-gram cache file for
  `ngram-cache` E2E validation. Speculative benchmark prompts now render with
  configured or loaded GGUF chat templates before the generic fallback instead
  of silently falling back to a hard-coded Gemma prompt.

- Documented compatible DFlash GGUF metadata, a known-good public target/draft
  model pair, and troubleshooting guidance for incompatible `dflash-draft` or
  missing `dflash.target_layers` artifacts.

- Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b9873-llamadart.2`, keeping the `b9873`
  llama.cpp ABI/bindings while picking up wrapper fixes for native release
  provenance and backend-selected speculative sampler acceptance. Refreshed
  the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum and aligned current
  README/website native override docs.

- Hardened LiteRT-LM generation validation so llama.cpp-only speculative
  decoding knobs fail loudly instead of silently degrading to LiteRT-LM's
  boolean speculative toggle.

- Added `LlamaStructuredOutput` and `LlamaEngine.createStructuredJson(...)`
  helpers for strict JSON-object / JSON-schema generation with final-output
  validation and typed decoding.

- Added `LlamaEngine.loadMultimodalProjectorSource(...)` so GGUF multimodal
  projector files can use the same `ModelSource` resolver and native
  download/cache options as `loadModelSource(...)`.

- Improved the runnable chat app's Manage Models cache UX so model and mmproj
  asset cache states are shown separately, missing multimodal projectors can be
  re-cached without re-fetching already cached model assets, and runtime media
  capability mismatches surface as user-readable warnings. Custom signed or
  tokenized Hugging Face URLs now require confirmation before they are saved.

## 0.8.12

- Updated the default LiteRT-LM native runtime pin to
  `leehack/litert-lm-native@v0.14.0-native.1`, refreshed native-assets and
  Apple SwiftPM checksums, and exposed the new native LiteRT-LM 0.14
  load/generation controls.

- Hardened LiteRT-LM 0.14 runtime packaging across Linux, Windows, Android,
  Apple SwiftPM, and macOS local runtime-prep paths.

- Hardened release automation by adding CODEOWNERS coverage for
  publication-sensitive files and making pub.dev/GitHub Release propagation
  waits configurable with longer defaults.

- Added post-merge release automation so a merged release-prep PR can publish
  missing companion package versions, push the core release tag, wait for
  pub.dev, and confirm the GitHub Release without a separate manual tag step.

- Added `LlamaEngine.getModelFileType()` for llama.cpp/GGUF models.

- Refreshed llama.cpp `b9860` native runtime pins and template parity for
  DeepSeek V4 and MiniCPM5, including MiniCPM5 XML tool-call handling.

## 0.8.11

- Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b9829`, refreshed the
  `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and aligned current
  README/website native override docs for the release.

## 0.8.10

- **Potentially breaking behavior change:** native model cache defaults changed
  without breaking Dart source compatibility. `DefaultModelDownloadManager()` now
  prefers the platform shared cache on desktop/server instead of the process temp
  directory, and mobile `DefaultModelDownloadManager.auto()` without an explicit
  app-private directory now uses a best-effort temporary/cache fallback instead
  of throwing. Apps or tests that asserted the old temp path or mobile exception
  should pass an explicit cache directory or follow `MIGRATION.md`.

- Added optional `androidAppPrivateCacheDirectory` and
  `iosAppPrivateCacheDirectory` arguments to
  `DefaultModelDownloadManager.auto(...)` so apps can provide platform-specific
  mobile cache roots without constructor-level `Platform.isAndroid` /
  `Platform.isIOS` branching.
- Updated the default native `DefaultModelDownloadManager()` constructor to use
  the per-user shared model cache on desktop/server platforms and the mobile
  app-private cache fallback, so plain `LlamaEngine(...)` remote source loads use
  a platform-appropriate default while preserving a temporary fallback for hosts
  that cannot expose a desktop cache environment.

## 0.8.9

- Broadened the `hooks` dependency constraint to support both the existing
  build-hooks package family and the latest stable release, restoring the
  pub.dev dependency freshness score without breaking downstream packages that
  still resolve `hooks` 1.x.

- Made web-safe backend stubs the default conditional import/export targets,
  preserving native `dart:io` selection while avoiding false WASM compatibility
  deductions in pub.dev analysis.

## 0.8.8

- Added a CI release-doc version consistency check so current README/website
  install snippets and companion package READMEs stay aligned with package
  `pubspec.yaml` versions, and documented that companion/core package publishing
  happens only after release-prep merge with explicit maintainer approval for
  each tag.

- Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b9803`, regenerated matching Dart FFI bindings,
  refreshed the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and
  aligned current README/website native override docs.

- Added `DefaultModelDownloadManager.auto(...)` plus explicit model cache root
  constructors for shared desktop caches, app-private mobile caches,
  user-selected model libraries, and App Group containers. Implicit shared cache
  resolution now fails loudly on mobile and web where the OS cannot provide a
  hidden cross-developer model folder.

## 0.8.7

- Fixed multimodal chat-template rendering so templates that force-open
  reasoning, such as Qwen3.5 VLM prompts ending with `<think>`, preserve
  `enable_thinking` and stream generated reasoning through `delta.thinking`
  instead of `delta.content`.

## 0.8.6

- Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b9776`, regenerated matching Dart FFI bindings,
  refreshed the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and
  aligned README/website native override docs.

## 0.8.5

- Fixed the split-library mtmd fallback ABI for image and byte-buffer
  multimodal inputs so Windows `mtmd.dll` and other split mtmd native bundles
  use the same bitmap helper signature as the generated native binding path.
  This avoids corrupting the first mtmd bitmap-helper call for Gemma 4/MMProj
  style multimodal loads and adds native symbol regression coverage for the
  fallback ABI.

## 0.8.4

- Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b9744`, regenerated matching Dart FFI bindings,
  refreshed the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and
  aligned current README/website native override docs.
- Expanded llama.cpp chat-template parity coverage for current upstream
  fixtures, including Cohere2 MoE, LFM2.5 tool-call, and Granite 4.1 templates.
  LFM2.5 prompts that use plain `List of tools: [...]` now route through the
  LFM2 handler, and `ToolChoice.required` uses grammar-constrained LFM2
  tool-call generation.
- Fixed streaming tool-call parsing so partial North/Cohere bare action arrays
  are not emitted as content before the complete tool call is parsed, and
  expanded the local GGUF feature smoke coverage for thinking, tool-call, and
  optional multimodal turns.

## 0.8.3

- Fixed Windows CUDA backend discovery when the native asset bundle directory is
  not on the app `PATH`. Apps using the CUDA llama.cpp backend can now resolve
  bundled CUDA redistributables beside `ggml-cuda.dll` without manually adding
  `.dart_tool/lib` or the native bundle path to `PATH`.

## 0.8.2

- Updated the default llama.cpp native runtime pin to
  `leehack/llamadart-native@b9694`, regenerated matching Dart FFI bindings,
  refreshed the `llamadart_llama_cpp_flutter` Apple SwiftPM checksum, and
  updated the default WebGPU bridge asset pin to
  `leehack/llama-web-bridge-assets@v0.1.17` (llama.cpp `b9699`). The WebGPU
  backend now caps unset large-model browser batches so Gemma 4 mem64 loads do
  not fall back to context-sized compute buffers.
- Added `BackendGpuEnumeration.listGpuDevices({probeBackends})` and
  `LlamaEngine.listGpuDevices` so apps can enumerate GPU-class devices and
  select llama.cpp offload targets by backend-specific `mainGpu` index.
- Added Cohere2 MoE / North Code chat-template detection and parsing so
  `<|START_TEXT|>` responses and `<|START_ACTION|>` tool-call arrays are
  handled separately from older Command-R templates.

## 0.8.1

- Fixed docs references that still pointed at
  `llamadart_litert_lm_flutter` `0.0.1` and
  the pre-`native.1` LiteRT-LM release after the 0.8.0 native pin sync moved
  LiteRT-LM Apple/runtime artifacts to `v0.13.1-native.1`.
- Routed native `.litertlm` image/audio chat parts through LiteRT-LM
  Conversation message JSON so bundles with native media processors can accept
  `LlamaImageContent` / `LlamaAudioContent` path and encoded-byte inputs without
  a separate `mmproj` projector.

## 0.8.0

- Split Flutter Apple SwiftPM runtime linking into companion packages:
  `llamadart_llama_cpp_flutter` for GGUF/llama.cpp and
  `llamadart_litert_lm_flutter` for `.litertlm`/LiteRT-LM. The core package
  remains a native-assets package without Flutter plugin metadata; the
  companion package sources live under `packages/` in this repository.
- Changed unset or empty `llamadart_native_runtimes` to mean all available
  runtime families. Flutter iOS/macOS companion packages decide Apple SPM
  runtimes when present; other builds continue to use
  `llamadart_native_runtimes`.
- Added opt-in native `.litertlm` `ModelParams` for activation data type,
  prefill chunk size, parallel file-section loading, and Android NPU LiteRT
  dispatch library directory, forwarding the pinned LiteRT-LM
  `v0.13.1-native.1`
  engine-settings C APIs while keeping defaults unchanged.
- Extended the LiteRT-LM engine smoke tool with matching environment variables
  and documented the support decision for each candidate runtime knob.
- Kept LiteRT-LM web rejecting these native-only settings explicitly.
- Added llama.cpp MTP benchmark diagnostics and local smoke/benchmark tools so
  baseline-vs-MTP runs can report decode timing, draft/accepted token counts,
  draft verification timing, and acceptance rate.
- Added `SpeculativeDecodingConfig.mtp(draftModelPath: ...)` for llama.cpp
  external draft-model MTP sessions.
- Removed the Android Vulkan MTP allow-list dart define and the model-name
  based Android Vulkan acceleration shortcut. Vulkan MTP now runs only when
  callers explicitly request Vulkan plus MTP in runtime parameters.

## 0.7.2

- Added explicit pub.dev platform metadata for Android, iOS, Linux, macOS, web,
  and Windows. This keeps the package listing aligned with the actual
  cross-platform runtime support even though Flutter plugin registration is
  only needed for Darwin app integration.

## 0.7.1

- Added Flutter iOS/macOS Swift Package Manager integration so Apple apps link
  pinned `leehack/llamadart-native` and `leehack/litert-lm-native`
  XCFramework artifacts through `darwin/llamadart/Package.swift`.
- Disabled the legacy hook-managed Apple bundle path for Flutter iOS/macOS
  builds, avoiding wrapper/framework `MinimumOSVersion` mismatches in App Store
  uploads.
- Raised the Flutter Apple runtime floors to iOS 16.4 and macOS 14.0 to match
  the published XCFramework artifacts.
- Kept Android native builds on both `llama_cpp` and `litert_lm` by default;
  iOS, macOS, Linux, and Windows now default to `llama_cpp` only. Non-Android
  `.litertlm` apps should opt in with `llamadart_native_runtimes`.
- Added native release pin automation for Apple SPM checksums, excluded local
  SwiftPM artifact caches from pub archives, and hardened main-branch CI against
  Hugging Face tiny-model download rate limits.
- Compatibility note: no Dart API breaking changes. Flutter Apple apps must
  target iOS 16.4/macOS 14.0 or newer.

## 0.7.0

- Added LiteRT-LM as a first-class backend for native `.litertlm` bundles and
  single-turn web-compatible `.litertlm` URLs, alongside the existing
  llama.cpp/GGUF path.
- Added `ModelParams.liteRtLmBackend` so callers can select LiteRT-LM CPU, GPU,
  or Android NPU execution where the pinned runtime supports it.
- Added native LiteRT-LM tokenization, detokenization, log-level control,
  runtime metrics, cached Hugging Face loading, and package hook overrides for
  testing compatible native runtime sources.
- Added `GenerationParams.speculativeDecoding` for native LiteRT-LM and wired
  the benchmark app so speculative runs are reflected in metrics.
- Fixed Gemma 4 `.litertlm` thinking and tool calling with canonical templates,
  thought-channel parsing, reasoning suppression, and a filename-keyed template
  registry for Gemma and Qwen LiteRT-LM bundles.
- Fixed iOS `.litertlm` loading by resolving embedded `LiteRtLm` and
  `StreamProxy` frameworks from the app bundle.
- Added WebGPU mem64 selection through `ModelParams.preferMemory64` and
  `ModelParams.modelBytesHint` so large GGUF models such as Gemma 4 E2B can
  choose the 64-bit bridge core.
- Fixed chat-app web downloads, LiteRT-LM web loading/generation, unsupported
  token-count refreshes, and misleading LiteRT-LM load progress.
- Hardened native and LiteRT-LM cancellation/disposal, multimodal cleanup,
  parser correctness, grammar generation, model download timeouts, and partial
  download resume behavior.
- Added Gemma 4 benchmark tooling, GGUF chat-feature smoke coverage, and the
  WebGPU Gemma 4 mem64 E2E scenario.
- Updated README and website docs for backend choice, capability limits,
  platform support, package-size controls, benchmark results, model templates,
  and pinned runtime artifacts.
- Compatibility note: no public API breaking changes for existing GGUF /
  llama.cpp callers. LiteRT-LM support is additive, with deprecated benchmark
  wrappers retained for compatibility; unsupported llama.cpp-only parameters are
  rejected for `.litertlm` loads instead of being silently ignored.

## 0.6.17

- Synced native hook pinning and regenerated bindings through
  `leehack/llamadart-native@b9371`, picking up llama.cpp `b9371`.
- Picked up the Apple mobile Metal stability fix that disables Metal residency
  sets on iOS/tvOS/visionOS native bundles, avoiding affected device
  context-creation failures such as `MTLLibraryErrorDomain Code=3`.
- Compatibility note: no public API breaking changes in `0.6.17`; existing
  `0.6.16` callers remain compatible.

## 0.6.16

- Fixed native `getVramInfo()` so llama.cpp GPU-class backend devices can
  report free/total VRAM when available, with Windows split-bundle registry
  fallback handling for backend-device symbols.
- Improved browser recovery for large remote WebGPU model/projector loads by
  retrying wasm32 model-staging aborts with the wasm64 core before surfacing
  memory-pressure failures.
- Improved the runnable chat app's web remote-model startup path so model assets
  are prefetched into browser cache when available, browser `CacheStorage`
  failures fall back to direct network loading, and credentialed/signed model
  URLs skip persistent browser cache storage.
- Improved the runnable chat app's mobile download behavior so lifecycle pauses
  no longer deliberately cancel active foreground downloads; the app now lets
  short screen-lock/background interruptions continue when the OS permits and
  still keeps explicit pause/dispose cancellation paths.
- Added in-app and docs guidance for mobile large-model downloads, including
  resumable partial files, foreground Dart lifecycle limits, and the need for
  opt-in native background download/model-store integrations for robust
  cross-app GGUF management.
- Compatibility note: no public API breaking changes in `0.6.16`; existing
  `0.6.15` callers remain compatible.

## 0.6.15

- Fixed GLM-OCR and other multimodal chat-template workarounds so image and
  audio content parts are preserved when tool-call normalization runs, system
  prompts are merged before leading media parts, and invalid tool-call
  serialization fails loudly instead of silently falling back to the wrong
  template shape.
- Added `tool/testing/run_local_e2e.dart` as a discovery and orchestration
  entry point for heavyweight local-only Dart E2E, Flutter device, and
  Web/Playwright smoke scenarios.
- Hardened the upstream llama.cpp chat/template E2E runner against current
  llama.cpp target renames, dynamic backend library lookup, and full
  `test-chat` server/mtmd build requirements.
- Documented that real-model/device/WebGPU scenarios remain skipped from
  default CI and should be opted into explicitly with `--list` and `--dry-run`
  first.
- Compatibility note: no public API breaking changes in `0.6.15`; existing
  `0.6.14` callers remain compatible. The chat-template changes fix
  multimodal serialization behavior for affected templates, and the local E2E
  runner is additive.

## 0.6.14

- Updated the default WebGPU bridge asset pin to
  `leehack/llama-web-bridge-assets@v0.1.16` (llama.cpp `b9165`), picking up
  the published JS bridge build, TypeScript declaration asset, and refreshed
  bridge docs.
- Added WebGPU readiness guidance covering browser capability checks,
  cross-origin isolation, bridge asset/version diagnostics, fallback behavior,
  model/configuration pressure, and the Flutter Web real-model smoke path.
- Added `ModelDownloadController`, a dependency-free helper that turns
  `ModelDownloadManager` cache/download work into app-facing lifecycle states
  for resolving, cache checks, downloads, verification, ready, failed,
  cancelled, and retry flows.
- Wired the runnable chat app example through a `ModelDownloadManager` adapter
  so its model-management UI demonstrates the controller while preserving the
  example's multi-asset and web-cache service behavior.
- Compatibility note: no public API breaking changes in `0.6.14`; the WebGPU
  bridge asset update and `ModelDownloadController` are additive, and existing
  `0.6.13` callers remain compatible.

## 0.6.13

- Added package-managed model source downloads and cache management:
  `ModelSource`, `ModelLoadOptions`, `ModelCachePolicy`, resolver targets,
  download/cache metadata, progress callbacks, cache inspection, removal,
  clearing, and age/size pruning.
- Added native/file-backed `DefaultModelDownloadManager` support for streaming
  HTTP downloads, `.part` files with atomic promotion, authenticated bearer and
  custom headers, cooperative cancellation, retry, HTTP Range resume, cache
  hit/refresh/cache-only/no-cache policies, SHA-256 verification, and persisted
  redacted metadata for signed URLs.
- Improved Hugging Face `hf://` ergonomics with `?revision=...` parsing for
  branch/ref names containing slashes, plus docs for private/gated bearer-token
  usage, separate `mmproj` assets, sharded-GGUF limitations, and redaction
  guarantees.
- Hardened download/cache correctness by serializing concurrent same-entry
  downloads, recovering missing or malformed cache metadata sidecars, treating
  mismatched byte-count/SHA-256 metadata as cache misses, and rejecting
  remote-only options for local `ModelSource.path(...)` inputs.
- Added `LlamaEngine.loadModelSource(...)` so local path sources keep using the
  existing native loader, remote HTTP(S)/Hugging Face sources download through
  the package-managed native cache before local loading, and URL-capable web
  backends keep using direct URL loading for simple unauthenticated requests.
- Added KV-cache state persistence APIs: `LlamaEngine.supportsStatePersistence`,
  `stateSaveFile(...)`, `stateLoadFile(...)`, backend support diagnostics, and
  WebGPU bridge forwarding for bridge assets `v0.1.15+`.
- Compatibility note: no public API breaking changes in `0.6.13`; existing
  `loadModel(...)` callers are unchanged.

## 0.6.12

- Synced default WebGPU bridge asset pinning to
  `leehack/llama-web-bridge-assets@v0.1.14` (llama.cpp `b9016`) to match the
  native runtime pin.
- Picked up bridge-side Qwen UTF-8 streaming stabilization and multimodal
  fallback narrowing while preserving control-token output for parser consumers.
- Picked up the bridge-side BERT embedding thread-pool sizing fix so automatic
  thread selection does not exceed the compiled WebAssembly pthread pool.
- Forwarded native-compatible `ModelParams` load tuning knobs through the
  WebGPU bridge path, including sequence slots, flash attention, KV cache type,
  RoPE overrides, split mode, and main GPU.
- Matched native batch defaults on WebGPU so unset `batchSize` and
  `microBatchSize` use `n_batch = n_ctx` and `n_ubatch = n_batch`, avoiding
  first-embedding aborts for BERT-class/non-causal encoder models while
  preserving model-specific Qwen3.5-0.8B WebGPU safety tuning.
- Filtered backend-owned runtime dependencies during native asset bundling so
  CUDA runtime DLLs and OpenBLAS runtime libraries are emitted only when their
  owning backend module is selected, while unknown runtime libraries stay
  bundled for forward compatibility.
- Compatibility note: no public API breaking changes in `0.6.12`.

## 0.6.11

- Synced native hook pinning and regenerated bindings through
  `leehack/llamadart-native@b8955`.
- Fixed Gemma 4 streaming so `<|channel>thought ... <channel|>` output is
  emitted as thinking deltas instead of content text, including when channel
  markers are split across streamed chunks.
- Tracked the chat app lockfile for stable generated Flutter plugin metadata in
  CI and release validation.
- Compatibility note: no public API breaking changes in `0.6.11`.

## 0.6.10

- Synced native hook pinning and regenerated bindings through
  `leehack/llamadart-native@b8638`.
- Hardened multimodal prompt overflow handling so native failures surface as
  Dart exceptions, and reduced staged chat-app image size to a `384px` max edge
  to lower multimodal context pressure.
- Added built-in Gemma 4 template detection/render/parse support, including
  thinking and tool-call handling.
- Added runtime projector capability gating so multimodal flows and the chat app
  respect actual `supportsVision` / `supportsAudio` results instead of
  model-family assumptions.
- Compatibility note: no public API breaking changes in `0.6.10`.

## 0.6.9

- Documented that iOS builds require a minimum deployment target of `16.4` or
  newer across the README, docs site, and example docs.
- Updated `example/chat_app` iOS Podfile and Runner project settings to use
  deployment target `16.4`.
- Honored `ggml_backend_score` during Android asset-based backend fallback so
  unsupported CPU variant libraries are skipped before initialization.
- Changed Android `auto` backend resolution to prefer CPU by default while
  keeping Vulkan available for explicit opt-in.
- Clarified that changing `hooks.user_defines` requires
  `flutter clean && flutter pub get` before rebuilding.
- Compatibility note: no public API breaking changes in `0.6.9`.

## 0.6.8

- Synced native hook pinning and regenerated bindings to
  `leehack/llamadart-native@b8480`.
- Refreshed generated low-level FFI bindings to match the synced upstream
  headers.
- Compatibility note: no public API breaking changes in `0.6.8`.

## 0.6.7

- Synced native hook pinning and regenerated bindings to
  `leehack/llamadart-native@b8373`.
- Hardened Linux bundle loading for packaged apps and improved versioned
  `libllamadart` dependency resolution.
- Fixed Hermes tool-call parsing when whitespace appears between `<tool_call>`
  and the JSON payload.
- Compatibility note: no public API breaking changes in `0.6.7`.

## 0.6.6

- Synced native hook pin to `leehack/llamadart-native@b8216`.
- Updated default web bridge asset pinning to
  `leehack/llama-web-bridge-assets@v0.1.10` (llama.cpp `b8216`).
- Switched bundled Qwen3.5 example presets to Unsloth `Q4_K_M` GGUFs.
- Added native perf diagnostics chips in the chat app (`p_eval`, `eval`,
  `sample`, `reuse`) and Android-specific Qwen tuning guidance.
- Restored a targeted Android Vulkan fast path for local Qwen3.5 `0.8B` / `2B`
  / `4B` models while keeping CPU as the recommended Android preset for
  `0.8B` / `2B`.
- Fixed local web chat app bridge/runtime handling for Qwen prompt streaming and
  multimodal fallback behavior.
- Compatibility note: no public API breaking changes in `0.6.6`.

## 0.6.5

- Added embedding APIs: `LlamaEngine.embed(...)` and
  `LlamaEngine.embedBatch(...)`.
- Added backend embedding capability interfaces for custom backend
  implementations.
- Added multi-sequence embedding batching support via
  `ModelParams.maxParallelSequences` (`n_seq_max`).
- Added native embedding benchmark tooling:
  `tool/testing/native_embedding_benchmark.dart` and
  `tool/testing/native_embedding_sweep.dart`.
- Added website docs for embeddings and updated basic-app docs with embedding
  examples.
- Added a Basic App SQLite vector retrieval example using
  `bin/llamadart_sqlite_vector_example.dart`.
- Updated default WebGPU bridge asset pinning to
  `leehack/llama-web-bridge-assets@v0.1.8`.
- Improved WebGPU runtime stability/tuning in chat app flows (backend switching,
  streaming smoothness, and multimodal regression gating).
- Added GPU-path multimodal image-size capping to reduce memory/runtime pressure
  on larger image inputs.
- Compatibility note: no public API breaking changes in `0.6.5`.

## 0.6.4

- Aligned multimodal projector offload with effective model-load settings,
  including CPU-only configurations.
- Added safer backend selection/discovery APIs and improved runtime backend
  status plus GPU-layer diagnostics accuracy.
- Improved web large-model handling with cache-prefetch download UX, bridge
  worker fallback paths, memory-pressure retries, and wasm64-core fallback
  wiring.
- Synced native hook tag to `b8157` and added Android arm64 CPU-profile and
  variant policy support with loader hardening.

## 0.6.3

- Synced native runtime to llama.cpp `b8138` and picked up Android arm64
  crash/compatibility hardening.
- Example app performance/UX polish and web model handling improvements.
- Added `example/tui_coding_agent`, a terminal coding agent example with
  default stable text-protocol tool mode.
- Added persisted settings log-level fallback handling with regression tests.

## 0.6.2

- Native inference performance improvements (request overhead, stream batching,
  and prompt-prefix reuse with parity-safe fallback).
- Added native benchmark and prompt-reuse parity tooling, plus CI parity
  coverage.

## 0.6.1

- Publishing compatibility fix for hook backend-config code paths.
- Continued parity hardening around template/parser behavior.

## 0.6.x line highlights

- Expanded llama.cpp template and parser parity.
- Stronger handling for tool payload fidelity.
- More deterministic behavior around template routing and fallback removal.

## 0.5.x line highlights

- Public API tightening and migration cleanup.
- Split Dart/native log controls.
- Example/runtime reliability improvements.

## Release usage guidance

- For upgrade planning, combine this page with
  [Upgrade Checklist](../migration/upgrade-checklist).
- For breaking changes, always validate against the exact release tag notes.
