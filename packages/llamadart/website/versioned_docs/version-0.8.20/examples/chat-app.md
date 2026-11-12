---
title: Chat App Example
description: Explore the production-style Flutter chat app example with model downloads, runtime controls, and streaming UX.
---

Path: `example/chat_app`

Flutter app showing production-style local chat UX with runtime controls.

Live demo: https://leehack-llamadart.static.hf.space

## Run

```bash
cd example/chat_app
flutter pub get
flutter run
```

If you run this example on Apple platforms, set the project deployment target to
iOS `16.4` or macOS `14.0` or newer before building.

This example keeps the default all-runtime configuration so native `.litertlm`
presets work on supported targets. If your app only ships GGUF models, set
`llamadart_native_runtimes` to `[llama_cpp]` to avoid bundling LiteRT-LM on
hook-managed native-assets builds.

## Test

```bash
cd example/chat_app
flutter test
```

## What it demonstrates

- Real-time streaming chat UI.
- Responsive conversation-first navigation with full-screen mobile settings.
- Compact runtime status with detailed performance diagnostics on demand.
- Copy and regenerate actions for plain assistant responses.
- Model selection and download flow.
- App-owned FIFO download scheduling, with queue positions and cancellation for
  waiting items. A responsive progress pill remains visible in the shell after
  the settings panel closes and reopens download details when tapped.
- The runnable chat app wires `ModelDownloadController` into its model-management
  flow through a small adapter, so cache checks, progress, cancel, retry, and
  clear ready/failure states come from the same package helper app code can
  reuse. The adapter keeps the example's platform-specific service layer for
  multi-asset model + `mmproj` downloads and browser cache behavior.
- On mobile, active downloads are treated as foreground work: the app no longer
  cancels them just because Android/iOS reports a lifecycle pause. The card
  tells users to keep the app open, and shell-level progress remains visible
  when settings closes. If the OS interrupts the socket anyway, the next
  foreground download attempt reuses the partial file when the server honors
  Range resume. A true sleep-proof UX should be built as an opt-in native
  background downloader/model-store manager and injected through
  `ModelDownloadManager`.
- Runtime backend preference, GPU layer, logical batch-size (`n_batch`), and
  micro-batch-size (`n_ubatch`) controls. `Auto` preserves backend-specific
  safe defaults; explicit values apply on the next model load. The app disables
  these llama.cpp/WebGPU controls for LiteRT-LM bundles, whose runtime does not
  expose them.
- Persistent settings and split Dart/native logging controls.
- Tool-calling toggles and model capability badges.
- Runtime-verified multimodal capability gating after `mmproj` load, plus
  declared direct-media capabilities for native model bundles such as
  LiteRT-LM. The app hides unsupported attachment types for the active platform.
- Separate file and microphone transcription actions for compatible Qwen3-ASR
  GGUF models, backed by the typed whole-file `SpeechToTextEngine`. Native file
  selection accepts WAV, MP3, and FLAC; WebGPU bridge assets `v0.1.30+` accept
  WAV bytes. The microphone captures a temporary foreground WAV and transcribes
  it only after **Stop & transcribe**; it does not emit live partial text. These
  actions are distinct from generic audio attachment and are not shown for
  current LiteRT-LM chat bundles. Microphone capture is enabled on Android,
  iOS, macOS, Windows, and supported secure browser origins; Linux capture
  remains disabled pending a safe external-recorder preflight, while
  selected-file transcription remains available there.
- Experimental live English dictation for native chat models, including
  generic audio-chat models, through independently installed, checksum-pinned
  LiteRT sidecars. Moonshine Tiny is the recommended 54 MB default; Parakeet
  TDT 0.6B is an optional higher-capacity, heavier 615 MB choice. Selection is
  persistent and the composer shows size, installed state, determinate
  download progress, cancel, and retry. The app streams mono 16 kHz PCM to a
  worker-isolated, CPU-only `SpeechToTextEngine.liteRtLm` session, shows confirmed and pending
  five-second-window text, and returns the final transcript to the editable
  composer without auto-sending. A persisted **Live dictation** switch in the
  settings explains and enables or disables this optional workflow. This path
  is enabled on Android, iOS, macOS, and Windows, capped at five minutes, and
  remains unavailable for Linux recording and Web. Audio-chat models
  retain **Ask with voice** as a separate action. Parakeet TDT follows its
  upstream [CC-BY-4.0 license](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3).
- **Ask with voice** for native Gemma 4 E2B, using either the LiteRT-LM
  direct-media bundle or the GGUF model with its matching audio-capable
  projector. It records up to 30 seconds, then **Stop & ask** sends the WAV
  bytes through ordinary multimodal chat so the model can answer the spoken
  request. It does not use `SpeechToTextEngine` and provides no transcript,
  timestamp, confidence, or live-partial contract. Qwen3-ASR keeps the separate
  five-minute **Stop & transcribe** workflow and takes precedence for ASR
  profiles.
- A dedicated cross-platform Qwen3-TTS mode backed by `TextToSpeechEngine`.
  Type an utterance, optionally choose a language and select or record
  speaker-reference audio, then cancel synthesis, automatically play the
  completed 24 kHz mono output, replay it, or save it as a WAV file. This is
  separate from chat generation and does not automatically read assistant
  responses aloud. Web uses bridge assets `v0.1.33+`, accepts selected speaker
  references as bytes, and does not record speaker references. The Web example
  limits one utterance to 96 codec frames (about 7.7 seconds) to bound browser
  memory and generation time, and labels output that reaches that limit.
- The voice-question UI is code-supported on Android, iOS, macOS, and Windows
  when the selected native profile declares direct audio input or the loaded
  projector reports audio support; Linux recording and Web are excluded. That
  platform gating is not an end-to-end validation claim. The experimental
  llama.cpp GGUF audio-answer path currently has engine-level Metal evidence
  on macOS. Current packaged microphone UI evidence is LiteRT-LM on macOS;
  Android, iOS, and Windows still need real-model/device validation.
  Real-model/device results should cite the
  `chat-app-voice-question-smoke` test-matrix row.
- Voice-question capture makes a best-effort attempt to delete the temporary
  WAV after reading it. The encoded bytes remain in the in-memory conversation
  history for subsequent turns and regeneration, which can reprocess the
  recording and consume additional memory.
- LiteRT-LM first initializes audio preprocessing on the selected backend, then
  transparently retries CPU if that executor is incompatible and remembers the
  working choice for the loaded model. For the validated Gemma 4 E2B bundle,
  GPU text/vision with CPU audio is the resolved path; LiteRT-LM itself is not
  universally limited to CPU audio.
- Clipboard image/audio attachments through `Cmd/Ctrl+V` on desktop and web or
  **Paste attachment** on touch devices. Text-only clipboard content still
  follows the normal composer paste path, and media is capped at 64 MB.
- Native and web `.litertlm` routing through LiteRT-LM. Native LiteRT-LM is
  enabled for supported targets; the example excludes the iOS x86_64 Simulator
  architecture while the arm64-only companion is enabled, and Windows arm64
  remains GGUF-only.

## Built-in model catalog

The built-in library is intentionally small and Unsloth-first:

- Cross-platform: FunctionGemma 270M, Qwen3.5 0.8B, Qwen3-ASR 0.6B,
  Qwen3-TTS 1.7B Base,
  Gemma 4 E2B GGUF, Gemma 4 E2B LiteRT-LM, and Gemma 4 E4B GGUF.
- Native desktop: Gemma 4 12B, Gemma 4 26B A4B,
  Gemma 4 31B, and Qwen3.6 35B A3B.

GGUF chat presets use [Unsloth distributions](https://huggingface.co/unsloth).
The dedicated speech presets use llama.cpp's `ggml-org` Qwen3-ASR and Qwen3-TTS
pairs, while the `.litertlm` artifacts come from `litert-community`; cards
identify each source. Both speech model/projector pairs use immutable URLs and
verified SHA-256 digests. The library defaults to the current platform, promotes
downloaded models, and supports name/capability search plus Mobile, Web, and
Desktop filters. Browsing another platform keeps incompatible model actions
disabled and explains why. Gemma 4 E4B remains cross-platform because it is
designed for capable edge/mobile devices as well as desktops.

Model cards prioritize size, RAM, compatibility, capabilities, cache state, and
the primary download/load action. Recommended context and output limits remain
visible without repeating every sampling parameter on every card.

Availability filters match each preset's platform restrictions. Qwen3-ASR and
Qwen3-TTS appear under native and **Web** with their validated platform-specific
input contracts, while the largest native models remain **Desktop** only.
Web Qwen3-TTS requires bridge assets `v0.1.33+`, memory64, and enough browser
memory for the roughly 1.48 GB model/projector pair.

The complete Qwen3-ASR model/projector, microphone, and final-transcript flow
has passed on a physical Pixel using CPU inference and in the iOS Simulator.
Physical-iPhone and Windows validation remain outstanding.

For native GGUF models, Auto runtime planning uses the selected model size,
reported device memory, conservative system headroom, and requested context. It
chooses full offload when the model fits, reduces context before partial
offload when memory is tight, and maps the UI's **Max** setting to llama.cpp's
full-offload sentinel. Auto intent is stored independently from its resolved
layer and context values, so headroom is recalculated on every model load and
after app restarts. Selecting a lower GPU-layer value disables that tuning and
keeps the manual value fixed.

Custom and discovered model cards expose a dedicated actions menu. Removing an
entry from the library is separate from deleting its downloaded files, and the
confirmation dialog offers both choices when cached assets exist.

## Gemma 4 note

The download library includes Gemma 4 E2B, E4B, 12B, 26B A4B, and 31B GGUF
tiers. E2B, E4B, and 12B expose image, audio, and video input on the current
native `llama.cpp` mtmd path; 26B A4B and 31B expose image/video input but do
not support audio. The native Gemma 4 E2B LiteRT-LM bundle accepts audio
directly without an external projector. On code-supported native recorder
targets, **Ask with voice** can send a recording to that bundle or to an
audio-capable E2B, E4B, or 12B GGUF projector. This is generic audio-input chat,
not typed speech-to-text. Current packaged microphone UI validation covers the
LiteRT-LM E2B path on macOS; the E2B GGUF path has engine-level Metal evidence,
not device UI validation. Web GGUF audio remains runtime-gated, and LiteRT-LM
Web remains text-only.

## Web notes

On web, this example prefers local bridge assets on `localhost` for development
validation and otherwise prefers CDN assets with local fallback. The runtime
details view exposes the active bridge/core variant, fallback reason, model
source, cache state, and runtime notes so you can distinguish browser capability
problems from model/configuration pressure.

When the model path is a remote HTTP(S) URL, the web app tries to prefetch the
model into browser cache before handing it to the bridge. If `CacheStorage` is
unavailable, quota-limited, or rejects the write, startup falls back to direct
network loading instead of failing the model load. Signed or otherwise
credentialed model URLs with userinfo, query strings, or fragments bypass
persistent browser cache storage so credentials are not stored as cache request
keys. Web multimodal projectors are fetched directly by the bridge and are not
part of the chat startup cache prefetch.

For reliable large GGUF loads, serve the app with COOP/COEP headers so
`window.crossOriginIsolated === true`. A built smoke path is documented in
[WebGPU Bridge](../platforms/webgpu-bridge); it uses
`tool/testing/serve_static_with_headers.py` and the real-model Playwright smoke
against a small Qwen3.5 model.

## Android notes

- Qwen3.5 `0.8B` currently defaults to `CPU` on Android because that was the
  fastest verified path on the maintainer Pixel test device.
- GGUF downloads in this example run through the app's foreground Dart process.
  Keep the app visible/unlocked for the most reliable download. The app avoids
  deliberately cancelling on screen lock, but Android can still suspend the
  process; production apps that need guaranteed completion should use a
  foreground service or system download integration behind a custom
  `ModelDownloadManager`.
- Runtime details expose native llama.cpp timing breakdowns (`p_eval`, `eval`,
  `sample`, `reuse`) so Android CPU vs Vulkan comparisons remain visible
  without crowding the conversation.
- For general model/backend tuning workflow, use
  [Performance Tuning](../guides/performance-tuning) rather than treating these
  example defaults as universal rules.
