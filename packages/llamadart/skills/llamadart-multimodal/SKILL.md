---
name: llamadart-multimodal
description: >-
  Use when sending images or audio to a model with llamadart: loading a GGUF
  multimodal projector (mmproj), building LlamaImageContent or
  LlamaAudioContent messages, checking engine.capabilities for vision and
  audio input, using
  LiteRT-LM bundle-native media, handling web limits, or debugging media that
  is ignored or rejected.
---

# Multimodal input with llamadart

With a llama.cpp runtime older than ggml `0.28.0` (llamadart-native
`v0.8.0`), native Android Vulkan Qwen3.5 (`general.architecture=qwen35`) on a
GPU with a subgroup size below 32 other than 8 permits only ordinary text with
`microBatchSize` unset or `1..8`; media, speculation and embeddings are typed
unsupported (#948). The bundled runtime lifts this, but the Qwen3.5 image
encoder stays on the CPU on those GPUs. Probe loaded-model modalities and
speculative strategies before offering them.

## Guidelines

- Loading, chat and streaming basics are in the llamadart-getting-started and
  llamadart-chat-streaming skills; this skill only covers media.
- Pick the flow by model format:
  - GGUF (llama.cpp): load the model and its matching projector in one call,
    `LlamaModel(source, projector: projectorSource)` passed to
    `LlamaEngine.load` or `setModel`. The projector must come from the same
    model family and release as the model.
  - `.litertlm` (LiteRT-LM): the bundle carries its own media processors. Do
    not pass a projector: `LlamaModel.projector` throws
    `LlamaUnsupportedException`, before any download when the file name,
    `ModelSource.format` or a custom backend's fixed runtime identity names
    LiteRT-LM. A refused replacement keeps the previous model loaded.
    `loadMultimodalProjectorSource` also throws on LiteRT-LM.
- Cancelling native LiteRT-LM image chat causes the next request to reinitialize
  its native engine once work settles, including a late subscription cancel.
  Keep using the public engine; allow for initialization latency on that request.
- Use `engine.loadMultimodalProjectorSource(source, download: ...)` only to
  change the projector of a model that is already loaded; before a model is
  loaded it throws `LlamaContextException`. A projector that is missing or
  rejected by the runtime throws `LlamaModelException`.
- After loading the model and any projector, read
  `final caps = await engine.capabilities;` and check `caps.supportsVision`
  and `caps.supportsAudio` before offering image or audio input. A
  projector can expose only some of a family's modalities; never infer support
  from the model card. `engine.hasMultimodalProjector` only says a projector is
  loaded.
- For a GGUF model they report the loaded projector; for a native `.litertlm`
  bundle they report the modalities the bundle declares. A `false` there does
  not block the request; only a custom runtime older than LiteRT-LM v0.18.0 can
  under-report it. The
  `engine.supportsVision` and `engine.supportsAudio` getters report the same
  values as `capabilities`.
- Always check before sending media to a GGUF model. With no projector loaded,
  image or audio parts throw `LlamaUnsupportedException` on llama.cpp, native
  and WebGPU; on native so does input the loaded projector cannot encode.
- Put media in a message with
  `LlamaChatMessage.withContent(role: ..., content: [...])`, or pass the parts
  to `ChatSession.create`. Place media before the text that refers to it.
- Keep image/audio in user messages, separate from tool results. A tool's
  images go in `LlamaToolResultContent.content` only when
  `(await engine.capabilities).toolResultMedia` contains
  `LlamaToolResultMedia.image` (native llama.cpp, vision projector,
  Hermes-style template such as Qwen3-VL). Tool-role media and media alongside
  `LlamaToolResultContent` under any role throw `LlamaUnsupportedException` in
  `create` and `chatTemplate`, including session history budgeting.
- Media sources that each runtime actually reads:
  - `LlamaImageContent(path: ...)` or `LlamaImageContent(bytes: ...)` with
    encoded JPEG/PNG bytes. Prefer `path` on native.
  - `LlamaAudioContent(path: ...)`, `LlamaAudioContent(bytes: ...)` with
    encoded audio (for example WAV), or `samples:` (raw PCM `Float32List`).
  - `LlamaImageContent.url` is consumed only by the web bridge. Native
    llama.cpp and native LiteRT-LM throw `LlamaUnsupportedException` for it;
    download the image and pass bytes instead.
  - Native LiteRT-LM also rejects raw PCM `samples` and `bytes` combined with
    `width`/`height` (raw RGB). Do not set `width`/`height` on encoded bytes.
- Video is not supported. `await engine.supportsVideo` is always `false` and
  `LlamaVideoContent` fails with `LlamaUnsupportedException`; send extracted
  frames as `LlamaImageContent` instead.
- Loading a second projector replaces the first. `unloadMultimodalProjector()`
  drops only the projector; `unloadModel()` and `dispose()` also release it.
  `setModel` replaces the loaded model and its projector, with no
  `unloadModel()` first: pass the new model's projector in its `LlamaModel`,
  because the old one is gone and must not be reused.
- Projector offload follows the model load: `ModelParams(gpuLayers: 0)` or
  `preferredBackend: GpuBackend.cpu` also keeps the projector on CPU. If
  multimodal output is wrong or crashes on GPU, get a CPU baseline first.
- On llama.cpp, `GenerationParams.thinkingBudget` and speculative decoding
  throw `LlamaUnsupportedException` for requests that contain media. Leave
  them unset for multimodal turns.
- llama.cpp decodes the images of some projectors with non-causal attention
  (Gemma 3 and Gemma 4 other than E2B and E4B, among others) and cannot
  split one across micro-batches. An image with more tokens than
  `ModelParams.microBatchSize` (512 by default) then throws
  `LlamaInferenceException` naming the token count: load the model with
  `microBatchSize` of at least that and `batchSize` no smaller, or downscale
  the image. Gemma 4 gives an image up to 1120 tokens. When `batchSize`
  equals `microBatchSize` there is no error; the image is decoded in several
  batches with a logged warning, and answers can be less accurate.
- The package does not resize media. Downscale large images (the example chat
  app caps the long edge at 384px) and keep `maxTokens` and context budgets
  tighter than for text; images in history keep consuming context on later
  turns.
- Web:
  - WebGPU loads projectors by URL: a remote unauthenticated URL, or a
    `ModelSource.path` that is a URL relative to the document or a `blob:`
    URL. `ModelLoadOptions` that need the native cache
    (`bearerToken`/`headers`, `sha256`, `cachePolicy`, `cacheDirectory`,
    `cancelToken`, `resume: false`, custom `maxRetries`) throw
    `LlamaUnsupportedException`.
  - Media file paths are native-only; on web pass browser file bytes or URLs.
  - LiteRT-LM on web is text-only.
- `LlamaAudioContent` is generic audio routed through generation, not a
  transcript API. For transcription use `SpeechToTextEngine.load` or
  `SpeechToTextEngine.attach` with a model adapter, such as
  `Qwen3AsrAdapter` or your own `SpeechToTextPromptAdapter` (llamadart-speech
  skill).

## Examples

GGUF model plus projector, with capability checks before sending an image:

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final LlamaEngine engine = await LlamaEngine.load(
    LlamaModel(
      ModelSource.path('/models/gemma-3-4b-it-Q4_K_M.gguf'),
      projector: ModelSource.path('/models/mmproj-gemma-3-4b-it.gguf'),
    ),
  );
  try {
    final LlamaEngineCapabilities caps = await engine.capabilities;
    if (!caps.supportsVision) {
      throw StateError('This projector does not provide vision input.');
    }
    print('audio input: ${caps.supportsAudio}');

    final LlamaChatMessage message = LlamaChatMessage.withContent(
      role: LlamaChatRole.user,
      content: const [
        LlamaImageContent(path: '/photos/receipt.jpg'),
        LlamaTextContent('What is the total on this receipt?'),
      ],
    );

    final String answer = await engine.create(
      [message],
      params: const GenerationParams(maxTokens: 128),
    ).text();
    print(answer);
  } finally {
    await engine.dispose();
  }
}
```

Switching GGUF models that each need their own projector:

```dart
import 'package:llamadart/llamadart.dart';

Future<bool> switchVisionModel(
  LlamaEngine engine, {
  required String modelUri,
  required String projectorUri,
}) async {
  // setModel replaces the loaded model and its projector.
  await engine.setModel(
    LlamaModel(
      ModelSource.parse(modelUri),
      projector: ModelSource.parse(projectorUri),
    ),
  );
  return (await engine.capabilities).supportsVision;
}
```

Image and audio bytes with a native `.litertlm` bundle (no projector):

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';

Future<String> describeClip(
  LlamaEngine engine,
  String imagePath,
  String wavPath,
) async {
  await engine.setModel(
    LlamaModel(ModelSource.path('/models/gemma-4-E2B-it.litertlm')),
  );

  final Uint8List imageBytes = await File(imagePath).readAsBytes();
  final Uint8List audioBytes = await File(wavPath).readAsBytes();
  return engine.create(
    [
      LlamaChatMessage.withContent(
        role: LlamaChatRole.user,
        content: [
          LlamaImageContent(bytes: imageBytes),
          LlamaAudioContent(bytes: audioBytes),
          const LlamaTextContent('Does the audio match the picture?'),
        ],
      ),
    ],
    params: const GenerationParams(maxTokens: 160),
  ).text();
}
```

## More

- Media embeddings use `LlamaEmbeddingInput`, `embedContent` / `embedContentBatch`
  and `await engine.embeddingCapabilities`, separately from chat capabilities.
  Model/projector and backend requirements:
  https://llamadart.leehack.com/docs/guides/embeddings
- Multimodal guide: https://llamadart.leehack.com/docs/guides/multimodal
- Speech to text: https://llamadart.leehack.com/docs/guides/speech-to-text
- Support matrix: https://llamadart.leehack.com/docs/platforms/support-matrix
- Performance tuning: https://llamadart.leehack.com/docs/guides/performance-tuning
