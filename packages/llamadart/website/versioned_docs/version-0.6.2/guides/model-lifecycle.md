---
title: Model Lifecycle
---

This guide covers model load/unload flows and safe lifecycle patterns.

## Single model lifecycle

```dart
final engine = LlamaEngine(LlamaBackend());
await engine.loadModel('/path/to/model.gguf');

// ...run inference...

await engine.unloadModel();
await engine.dispose();
```

## Switching models

`LlamaEngine.loadModel(...)` requires no currently loaded model. Unload first:

```dart
await engine.unloadModel();
await engine.loadModel('/path/to/another_model.gguf');
```

## Load from URL (web-focused)

```dart
await engine.loadModelFromUrl(
  'https://example.com/model.gguf',
  onProgress: (progress) => print('progress: $progress'),
);
```

`loadModelFromUrl` requires a backend with URL loading support.

## Multimodal projector lifecycle

```dart
await engine.loadMultimodalProjector('/path/to/mmproj.gguf');
final canSee = await engine.supportsVision;
final canHear = await engine.supportsAudio;
print('vision=$canSee audio=$canHear');
```

Projector resources are released by `unloadModel()` or `dispose()`.

## LoRA adapters at runtime

```dart
await engine.setLora('/path/to/adapter.gguf', scale: 0.8);
await engine.removeLora('/path/to/adapter.gguf');
await engine.clearLoras();
```

See [LoRA Adapters](./lora-adapters) for scaling strategy, stacking, and
platform-specific behavior.

## Recommended lifecycle checks

- Check `engine.isReady` before inference paths.
- Use `try/finally` to guarantee `dispose()` on shutdown.
- Keep model switch logic serialized to avoid overlapping load/unload calls.
