---
title: Multimodal (Vision and Audio)
---

Multimodal inference requires a model/runtime path that supports vision or
audio behavior. GGUF models use a model plus projector pair. Native
`.litertlm` bundles use LiteRT-LM's bundle-native media processors and do not
load a separate projector.

## GGUF projector flow

```dart
await engine.loadModel('/path/to/model.gguf');
await engine.loadMultimodalProjector('/path/to/mmproj.gguf');
```

Projector offload follows effective model-load configuration. If model loading
is CPU-only (`preferredBackend: GpuBackend.cpu` or `gpuLayers: 0`), projector
initialization also runs CPU-only.

## LiteRT-LM bundle flow

```dart
await engine.loadModel('/path/to/model.litertlm');

final message = LlamaChatMessage.withContent(
  role: LlamaChatRole.user,
  content: const [
    LlamaTextContent('Describe this image.'),
    LlamaImageContent(path: '/path/to/image.jpg'),
  ],
);

await for (final chunk in engine.create([message])) {
  final text = chunk.choices.first.delta.content;
  if (text != null) {
    print(text);
  }
}
```

Native LiteRT-LM accepts `LlamaImageContent` and `LlamaAudioContent` backed by
local paths or encoded media bytes. Remote image URLs and raw PCM
`Float32List` audio samples are rejected before native generation because the
current LiteRT-LM C message loader expects a local `path` or base64 `blob`.

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

For native LiteRT-LM `.litertlm` bundles, capability depends on the bundle's
native template/model processors. `loadMultimodalProjector`, `supportsVision`,
and `supportsAudio` are projector-oriented APIs and are not used by the
LiteRT-LM bundle flow.

## Web notes

- Web uses bridge runtime paths.
- Multimodal projector loading on web is URL-based.
- Local file path media inputs are native-first; web flows use browser file
  bytes/URLs.
- LiteRT-LM web through `@litert-lm/core` remains text-only in `llamadart`.

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
