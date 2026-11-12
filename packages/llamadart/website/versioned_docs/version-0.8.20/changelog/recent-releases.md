---
title: Recent Releases
description: Review recent llamadart release highlights and jump to the canonical changelog for full release notes.
---

For canonical full release notes, use:

- [`CHANGELOG.md`](https://github.com/leehack/llamadart/blob/main/CHANGELOG.md)

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
