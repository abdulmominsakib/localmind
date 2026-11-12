---
title: "Multimodal input: vision and audio"
sidebar_label: Multimodal
description: "Send images and audio to multimodal models: GGUF model plus projector pairs, LiteRT-LM bundles, capability checks and web notes."
---

Multimodal inference requires a model/runtime path that supports vision or
audio behavior. GGUF models use a model plus projector pair. Native
`.litertlm` bundles use LiteRT-LM's bundle-native media processors and do not
load a separate projector.

## GGUF projector flow

Load the model and its projector in one call:

```dart
final engine = await LlamaEngine.load(
  LlamaModel(
    ModelSource.path('/path/to/model.gguf'),
    projector: ModelSource.path('/path/to/mmproj.gguf'),
  ),
);
```

Remote sources are resolved, downloaded and cached together, and `setModel`
takes the same `LlamaModel` on an existing engine:

```dart
await engine.setModel(
  LlamaModel(
    ModelSource.parse('hf://owner/repo/model-Q4_K_M.gguf'),
    projector: ModelSource.parse('hf://owner/repo/mmproj.gguf'),
  ),
);
```

To change only the projector of a loaded model, call
`loadMultimodalProjectorSource`:

```dart
await engine.loadMultimodalProjectorSource(
  ModelSource.parse('hf://owner/repo/other-mmproj.gguf'),
  download: ModelLoadOptions(maxRetries: 3),
);
```

Native/file-backed backends download remote projectors through the configured
`ModelDownloadManager` before loading the cached local path. URL-loading web
backends fetch the projector themselves, from a remote unauthenticated URL or
a `ModelSource.path` that is a URL relative to the document or a `blob:` URL,
and reject options that require native cache IO such as auth headers, a
`cancelToken`, checksum verification, explicit cache policy changes, custom
cache directories, disabled resume, and custom retry counts.

Projector offload follows effective model-load configuration. If model loading
is CPU-only (`preferredBackend: GpuBackend.cpu` or `gpuLayers: 0`), projector
initialization also runs CPU-only.

`unloadModel()`, `dispose()` and a `setModel` that replaces the model release
the projector with the model.
`unloadMultimodalProjector()` releases only the projector and keeps the model
loaded. Loading another projector replaces the active one.

## LiteRT-LM bundle flow

```dart
final engine = await LlamaEngine.load(
  LlamaModel(ModelSource.path('/path/to/model.litertlm')),
);
```

A `.litertlm` model takes no projector: passing one throws
`LlamaUnsupportedException`, before any download when `ModelSource.format` or
the file name gives the format.

Native LiteRT-LM accepts `LlamaImageContent` and `LlamaAudioContent` backed by
local paths or encoded media bytes. Remote image URLs and raw PCM
`Float32List` audio samples are rejected with `LlamaUnsupportedException`
before native generation because the current LiteRT-LM C message loader
expects a local `path` or base64 `blob`.

Native LiteRT-LM starts audio preprocessing on the selected backend (CPU when
NPU is selected). If that fails, it retries on CPU and keeps CPU audio for the
loaded model; with the GPU backend, the Gemma 4 E2B bundle resolves to GPU text
and vision with CPU audio.

## Build multimodal message

```dart
final message = LlamaChatMessage.withContent(
  role: LlamaChatRole.user,
  content: const [
    LlamaImageContent(path: '/path/to/image.jpg'),
    LlamaTextContent('Describe this image in one sentence.'),
  ],
);

final description = await engine.create([message]).text();
print(description);
```

On native `llama.cpp`, a request that carries image or audio parts and sets
`GenerationParams.thinkingBudget` or speculative decoding
(`speculativeDecoding` or `speculativeDecodingConfig`) throws
`LlamaUnsupportedException`; both are text-only there. Leave them unset for
media turns.

## Capability checks

```dart
final capabilities = await engine.capabilities;
final supportsVision = capabilities.supportsVision;
final supportsAudio = capabilities.supportsAudio;
final supportsVideo = await engine.supportsVideo; // false in current releases
```

Always prefer these runtime checks over model-card assumptions. Read
`capabilities` again after loading or unloading a projector. With no
projector loaded, a GGUF model (native `llama.cpp` or WebGPU) rejects image
and audio parts with `LlamaUnsupportedException` instead of answering from the
text alone. A loaded projector can expose only a subset of the family-level
modalities. The current Gemma 4 E2B GGUF projector path in native `llama.cpp`
mtmd reports both vision and audio support; audio remains experimental
upstream. Web continues to rely
on the loaded bridge's runtime capability report.

Native `.litertlm` bundles process media themselves, without a projector.
`capabilities.supportsVision` and `supportsAudio` report the modalities the
bundle declares. That declaration can under-report for bundles whose section
types are not lowercase ([litert-lm-native#60](https://github.com/leehack/litert-lm-native/issues/60)), so a `false` does not block the
request. `LlamaModel.projector` and `loadMultimodalProjectorSource` apply only
to GGUF models; the
`engine.supportsVision` and `engine.supportsAudio` getters report what
`capabilities` reports, for both formats.

Video isn't supported; send extracted frames as `LlamaImageContent`.
`LlamaVideoContent` fails with `LlamaUnsupportedException`.

`LlamaAudioContent` is generic audio input routed through normal generation; it
does not by itself provide a transcript contract. For typed transcription, see
[Speech to Text](./speech-to-text).

## Web notes

- Web uses bridge runtime paths.
- Multimodal projector loading on web is URL-based.
- A projector on a URL-loading web backend is a remote unauthenticated URL, or
  a `ModelSource.path` that is a URL relative to the document or a `blob:`
  URL; download options that require the native download/cache manager are
  unsupported there.
- Local file path media inputs are native-first; web flows use browser file
  bytes/URLs. `LlamaImageContent.url` is read only by the web bridge: native
  `llama.cpp` throws `LlamaUnsupportedException` for it, so download the image
  and pass its bytes.
- LiteRT-LM web through `@litert-lm/core` remains text-only in `llamadart`.

## Tuning notes

- Start with smaller images or audio inputs before changing backend settings.
- The example chat app caps picked image inputs to a `384px` max edge before
  staging them, but direct `LlamaImageContent(...)` usage does not resize media
  for you.
- Projector load success does not imply every modality is available. Re-check
  `capabilities.supportsVision` / `supportsAudio` after loading `mmproj`.
- Keep context and generation budgets tighter than your text-only defaults.
- Follow-up turns after an image can still overflow the active context window if
  conversation history grows too large.
- If multimodal is unstable on GPU, establish a working CPU baseline first.
- For broader tuning workflow and diagnostics guidance, see
  [Performance Tuning](./performance-tuning).
