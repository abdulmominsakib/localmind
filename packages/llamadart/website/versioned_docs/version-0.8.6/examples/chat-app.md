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
- Model selection and download flow.
- The runnable chat app wires `ModelDownloadController` into its model-management
  flow through a small adapter, so cache checks, progress, cancel, retry, and
  clear ready/failure states come from the same package helper app code can
  reuse. The adapter keeps the example's platform-specific service layer for
  multi-asset model + `mmproj` downloads and browser cache behavior.
- On mobile, active downloads are treated as foreground work: the app no longer
  cancels them just because Android/iOS reports a lifecycle pause, and the card
  tells users to keep the app open. If the OS interrupts the socket anyway, the
  next foreground download attempt reuses the partial file when the server
  honors Range resume. A true sleep-proof UX should be built as an opt-in native
  background downloader/model-store manager and injected through
  `ModelDownloadManager`.
- Runtime backend preference and GPU layer controls.
- Persistent settings and split Dart/native logging controls.
- Tool-calling toggles and model capability badges.
- Runtime-verified multimodal capability gating after `mmproj` load. The app
  hides unsupported attachment types even if a model family advertises broader
  multimodal support.
- Native and web `.litertlm` routing through LiteRT-LM. Native LiteRT-LM is
  enabled for supported targets; iOS x86_64 simulator and Windows arm64 remain
  GGUF-only because no matching LiteRT-LM native bundle is published.

## Gemma 4 note

The download library includes a Gemma 4 E2B GGUF + projector pair. On the
current `llama.cpp` mtmd path used by `llamadart`, that projector exposes
vision support but not audio support, so the app keeps image input enabled and
audio input disabled for that model.

## Web notes

On web, this example prefers local bridge assets on `localhost` for development
validation and otherwise prefers CDN assets with local fallback. The runtime
status panel exposes the active bridge/core variant, fallback reason, model
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

- Qwen3.5 `0.8B` and `2B` currently default to `CPU` on Android because that was
  the fastest verified path on the maintainer Pixel test device.
- GGUF downloads in this example run through the app's foreground Dart process.
  Keep the app visible/unlocked for the most reliable download. The app avoids
  deliberately cancelling on screen lock, but Android can still suspend the
  process; production apps that need guaranteed completion should use a
  foreground service or system download integration behind a custom
  `ModelDownloadManager`.
- Runtime chips expose native llama.cpp timing breakdowns (`p_eval`, `eval`,
  `sample`, `reuse`) so Android CPU vs Vulkan comparisons are visible in-app.
- For general model/backend tuning workflow, use
  [Performance Tuning](../guides/performance-tuning) rather than treating these
  example defaults as universal rules.
