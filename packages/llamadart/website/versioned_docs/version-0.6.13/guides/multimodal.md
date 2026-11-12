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

Projector offload follows effective model-load configuration. If model loading
is CPU-only (`preferredBackend: GpuBackend.cpu` or `gpuLayers: 0`), projector
initialization also runs CPU-only.

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

Always prefer these runtime checks over model-card assumptions. A loaded
projector can expose only a subset of the family-level modalities. For example,
the current Gemma 4 E2B/E4B GGUF projector path in `llama.cpp` mtmd exposes
vision, but not audio, in `llamadart`.

## Web notes

- Web uses bridge runtime paths.
- Multimodal projector loading on web is URL-based.
- Local file path media inputs are native-first; web flows use browser file
  bytes/URLs.

## Tuning notes

- Start with smaller images or audio inputs before changing backend settings.
- The example chat app caps picked image inputs to a `384px` max edge before
  staging them, but direct `LlamaImageContent(...)` usage does not resize media
  for you.
- Projector load success does not imply every modality is available. Re-check
  `engine.supportsVision` / `engine.supportsAudio` after loading `mmproj`.
- Keep context and generation budgets tighter than your text-only defaults.
- Follow-up turns after an image can still overflow the active context window if
  conversation history grows too large.
- If multimodal is unstable on GPU, establish a working CPU baseline first.
- For broader tuning workflow and diagnostics guidance, see
  [Performance Tuning](./performance-tuning).
