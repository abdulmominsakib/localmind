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

Use source-based loading when the projector should be resolved, downloaded, and
cached like a remote model source:

```dart
await engine.loadModelSource(
  ModelSource.parse('hf://owner/repo/model-Q4_K_M.gguf'),
);
await engine.loadMultimodalProjectorSource(
  ModelSource.parse('hf://owner/repo/mmproj.gguf'),
);
```

Native/file-backed backends download remote projectors through the configured
`ModelDownloadManager` before loading the cached local path. URL-loading web
backends support remote unauthenticated projector URLs directly and reject local
filesystem paths or options that require native cache IO such as auth headers,
checksum verification, explicit cache policy changes, custom cache directories,
disabled resume, and custom retry counts.

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
projector can expose only a subset of the family-level modalities. The current
Gemma 4 E2B GGUF projector path in native `llama.cpp` mtmd reports both vision
and audio support; audio remains experimental upstream. Web continues to rely
on the loaded bridge's runtime capability report.

`LlamaAudioContent` is generic audio input routed through normal generation; it
does not by itself provide a transcript contract. For typed whole-file native
transcription, see [Speech to Text](./speech-to-text).

For native LiteRT-LM `.litertlm` bundles, capability depends on the bundle's
native template/model processors. `loadMultimodalProjector`,
`loadMultimodalProjectorSource`, `supportsVision`, and `supportsAudio` are
projector-oriented APIs and are not used by the LiteRT-LM bundle flow. The chat
app therefore uses the selected preset's platform-specific direct-media
capabilities for native Gemma 4 LiteRT-LM audio.

## Web notes

- Web uses bridge runtime paths.
- Multimodal projector loading on web is URL-based.
- `loadMultimodalProjectorSource(...)` accepts remote unauthenticated projector
  URLs on URL-loading web backends; source options that require the native
  download/cache manager are unsupported there.
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
