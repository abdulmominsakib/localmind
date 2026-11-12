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

On web, this example prefers local bridge assets on `localhost` for development
validation and otherwise prefers CDN assets with local fallback.

## Android notes

- Qwen3.5 `0.8B` and `2B` currently default to `CPU` on Android because that was
  the fastest verified path on the maintainer Pixel test device.
- Runtime chips expose native llama.cpp timing breakdowns (`p_eval`, `eval`,
  `sample`, `reuse`) so Android CPU vs Vulkan comparisons are visible in-app.
- For general model/backend tuning workflow, use
  [Performance Tuning](../guides/performance-tuning) rather than treating these
  example defaults as universal rules.
