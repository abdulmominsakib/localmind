---
title: Laya Tetris example
sidebar_label: Laya Tetris
description: A Flutter app in which a Laya decision model plays real-time Tetris through DecisionEngine, with first-launch model downloads and a published fine-tuned head.
---

Path: `example/laya_tetris` · Platforms: macOS 14.0+, iOS 16.4+, Android 10+
(API 29), Web · First-run download: `laya-Q8_0.gguf` (421 MB),
`laya-head.safetensors` (106 MB) and `laya-head-tetris.safetensors` (106 MB)

A Flutter app in which a
[Laya](https://huggingface.co/convaiinnovations/laya) decision model plays
real-time Tetris while gravity keeps running. Live demo:
https://leehack-flutter-laya-tetris.static.hf.space

## Run

```bash
cd example/laya_tetris
flutter pub get
flutter run -d macos   # or an iOS or Android device
```

Variants, from `example/laya_tetris`:

```bash
# Web: fetch the pinned bridge assets, then run
WEBGPU_BRIDGE_OUT_DIR="$PWD/web/webgpu_bridge" \
  ../../scripts/fetch_webgpu_bridge_assets.sh
flutter run -d chrome

# Headless games from local model files, no downloads
dart run bin/bench.dart --model laya-Q8_0.gguf --head laya-head.safetensors \
  --tuned-head laya-head-tetris.safetensors

# Use your own tuned head
flutter run -d macos --dart-define=LAYA_TUNED_HEAD_URL=<url>
```

The app caches the downloads in a `laya/` folder and reuses them on later
launches. A Web build needs a cross-origin isolated page.

## What it demonstrates

- One `LlamaEngine` holding the backbone GGUF, shared by two
  `DecisionEngine`s: the base head and a Tetris-tuned head
  ([Decision models](../guides/decision-models)).
- First-launch downloads with progress through `loadModelSource` for the
  backbone and `modelDownloadManager.ensureModel` for the heads
  ([Downloads and cache](../guides/model-downloads)).
- Yes/no and `choice` questions sent as one `systemOneBatch` call per piece,
  or per knockout round, while the llama.cpp worker isolate does the work
  ([Batches](../guides/decision-models#batches)).
- A typed `ChoiceKey.of` over the candidate placements, read back with
  `answerOf` ([Choice values](../guides/decision-models#choice-values)).
- Switching GPU and CPU, backbones and thread counts at runtime by disposing
  the engine and loading a new one
  ([Backend selection](../guides/backend-selection)).
- The same app on the llama.cpp WebGPU bridge
  ([Decision models: Web](../guides/decision-models#web)).

## Test

```bash
cd example/laya_tetris
flutter test
```

`LAYA_MODEL_DIR=<folder> flutter test test/laya_models_local_test.dart` also
loads the real backbone and base head from `<folder>`.

Full options: the players, candidate modes, tuned-head lookup order, Web
serving, headless benchmark flags and measured results are in the
[example README](https://github.com/leehack/llamadart/tree/main/example/laya_tetris);
fine-tuning the head is in
[`training/README.md`](https://github.com/leehack/llamadart/blob/main/example/laya_tetris/training/README.md).
