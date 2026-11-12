---
title: Chat app example
sidebar_label: Chat app
description: A Flutter chat app with a model library, queued downloads, runtime controls, multimodal input, speech and streaming chat.
---

Path: `example/chat_app` · Platforms: Android, iOS 16.4+, macOS 14.0+,
Windows, Linux, Web

A Flutter chat app that downloads models from a built-in library and streams
on-device chat, with runtime controls and diagnostics. Live demo:
https://leehack-llamadart.static.hf.space

## Run

```bash
cd example/chat_app
flutter pub get
flutter run
```

Variants:

```bash
# Native downloads authenticated with a Hugging Face token
flutter run --dart-define=HF_TOKEN=<your_token>

# Web, from the repository root: build with the bridge assets, then serve
# with cross-origin isolation headers
./scripts/build_chat_app_web.sh
python3 tool/testing/serve_static_with_headers.py \
  --directory example/chat_app/build/web --port 8080

# Web smoke test with a mock bridge and no model download
dart run tool/testing/run_local_e2e.dart --scenario chat-app-web-mock-smoke
```

## What it demonstrates

- Streaming chat with per-model sampling presets, thinking output, and copy
  and regenerate actions
  ([Generation and streaming](../guides/generation-and-streaming)).
- Tool-calling toggles and editable tool declarations
  ([Tool calling](../guides/tool-calling)).
- A model library with queued, cancellable downloads through
  `ModelDownloadController`, cached across launches
  ([Downloads and cache](../guides/model-downloads)).
- Image and audio attachments, including clipboard paste, enabled only when
  the loaded projector or bundle reports the capability
  ([Multimodal](../guides/multimodal)).
- GGUF and `.litertlm` models through one engine API; the app enables both
  native runtime families, which an app that ships only GGUF does not need
  ([Backend selection](../guides/backend-selection)).
- Backend, GPU layer, context and batch controls, Auto memory planning, and
  runtime diagnostics
  ([Performance tuning](../guides/performance-tuning)).

## Speech and voice

With a Qwen3-ASR model loaded, the composer transcribes a selected file or a
microphone recording of up to 30 seconds. On Android, iOS, macOS and Windows,
native chat models can add live English dictation through a separately
installed LiteRT model: Moonshine Tiny
(54 MB) or Parakeet TDT 0.6B (615 MB). Native Gemma 4 E2B answers a spoken
question through **Ask with voice**, and the Qwen3-TTS preset switches the
composer to speech synthesis. See [Speech to text](../guides/speech-to-text) and
[Text to speech](../guides/text-to-speech).

## Test

```bash
cd example/chat_app
flutter test
flutter test --platform chrome test/chat_generation_service_test.dart
```

The second command covers Web-only paths.

Full options: the model catalog, download behavior, settings, platform and
validation status, Web and Android notes, and troubleshooting are in the
[example README](https://github.com/leehack/llamadart/tree/main/example/chat_app).
