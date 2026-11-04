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
