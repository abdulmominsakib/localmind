---
title: Multimodal (Vision and Audio)
---

Multimodal inference requires a model and projector pair that supports
vision/audio behavior.

## Load projector

```dart
await engine.loadModel('/path/to/model.gguf');
await engine.loadMultimodalProjector('/path/to/mmproj.gguf');
```

## Build multimodal message

```dart
final message = LlamaChatMessage.withContent(
  role: LlamaChatRole.user,
  content: const [
    LlamaImageContent(path: '/path/to/image.jpg'),
    LlamaTextContent('Describe this image in one sentence.'),
  ],
);

await for (final chunk in engine.create([message])) {
  final text = chunk.choices.first.delta.content;
  if (text != null) {
    print(text);
  }
}
```

## Capability checks

```dart
final supportsVision = await engine.supportsVision;
final supportsAudio = await engine.supportsAudio;
```

## Web notes

- Web uses bridge runtime paths.
- Multimodal projector loading on web is URL-based.
- Local file path media inputs are native-first; web flows use browser file
  bytes/URLs.
