---
title: Chat App Example
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

## Test

```bash
cd example/chat_app
flutter test
```

## What it demonstrates

- Real-time streaming chat UI.
- Model selection and download flow.
- Runtime backend preference and GPU layer controls.
- Persistent settings and split Dart/native logging controls.
- Tool-calling toggles and model capability badges.

## Web notes

On web, this example uses bridge runtime assets with local-first loading and CDN
fallback behavior.
