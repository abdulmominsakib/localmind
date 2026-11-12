# genkit_llamadart

[![pub package](https://img.shields.io/pub/v/genkit_llamadart.svg)](https://pub.dev/packages/genkit_llamadart)
[![pub points](https://img.shields.io/pub/points/genkit_llamadart)](https://pub.dev/packages/genkit_llamadart/score)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/LICENSE)

Run local LLMs in [Genkit Dart](https://pub.dev/packages/genkit) applications.
Use llama.cpp GGUF models or LiteRT-LM bundles through
[`llamadart`](https://pub.dev/packages/llamadart) for offline, on-device AI in
Dart and Flutter: chat, token streaming, tool calling, structured JSON output
and text/image/audio embeddings. Native preview models also provide batch transcription,
WAV synthesis and PNG image generation.

The model runs in your application's process. Download it once or supply a
local file, then run inference offline. Features depend on the loaded model
and backend; strict JSON requires grammar support and embeddings require an
embedding model. See [runtime support](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/runtime-support.md).

## Install

Requires Dart 3.12 or newer, Genkit 1.x and llamadart 0.19.x.

```bash
dart pub add genkit genkit_llamadart
```

For Flutter apps, use `flutter pub add` instead. Follow the
[llamadart installation guide](https://llamadart.leehack.com/) for runtime and
platform setup. Apple apps using Swift Package Manager need the runtime
companion matching their model family:

```bash
flutter pub add 'llamadart_llama_cpp_flutter:^0.19.0'
flutter pub add 'llamadart_litert_lm_flutter:^0.19.0'
```

Choose the GGUF companion, the LiteRT-LM companion, or both if your app uses
both runtimes. Apple companion builds require iOS 16.4+ or macOS 14.0+; an iOS
Podfile must also target 16.4+ when using CocoaPods.

llamadart supports Android, iOS, macOS, Linux, Windows and Web. Backend features
and setup differ by platform. This adapter's browser guard tests do not qualify
a complete Genkit Web deployment; validate your chosen browser and runtime.

## Quickstart

Save this as `bin/main.dart` in your Dart app, then run `dart run bin/main.dart`.
This native Dart example downloads [Qwen3.5-0.8B Q4_K_M](https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF)
(about 533 MB) from Hugging Face; later runs reuse the cached model.

```dart
import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';

Future<void> main(List<String> args) async {
  final prepared = await llamaDart.prepareModel(
    name: 'local-chat',
    source: ModelSource.parse(
      args.isEmpty
          ? 'hf://unsloth/Qwen3.5-0.8B-GGUF/Qwen3.5-0.8B-Q4_K_M.gguf?revision=6ab461498e2023f6e3c1baea90a8f0fe38ab64d0'
          : args.single,
    ),
    modelParams: const ModelParams(
      contextSize: 4096,
      device: ComputeDevice.cpu,
    ),
  );
  final ai = prepared.createGenkit();
  const config = LlamaDartGenerationConfig(
    temperature: 1.0,
    topP: 1.0,
    topK: 20,
    penalty: 1.0,
    presencePenalty: 2.0,
    maxTokens: 128,
  );
  try {
    final response = await ai.generate(
      prompt: 'Say hello in one sentence.',
      config: config,
    );
    if (response.finishReason == FinishReason.failed ||
        response.finishReason == FinishReason.aborted) {
      throw response.cause ?? StateError('Generation did not complete.');
    }
    print(response.text);
  } finally {
    try {
      await prepared.dispose();
    } finally {
      await ai.shutdown();
    }
  }
}
```

The 4,096-token context and 128-token output limit bound this example. CPU
execution needs no GPU setup on supported native platforms. Sampling follows
[Qwen's nonthinking text recommendations](https://huggingface.co/Qwen/Qwen3.5-0.8B#best-practices).
This example runs text-only on native llama.cpp; image input needs a matching
projector. Omitted `minP` and `enableThinking` default to `0` and `false`.
Use `ComputeDevice.auto` to let llamadart select a backend for your platform.

Weights download during preparation and load into the runtime on first use.
Requests to the same model run one at a time; different model names use separate
runtimes. Dispose the prepared handle when your app is done, then shut down
Genkit. Disposal is terminal.

For other models, [prepare a source](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/model-preparation.md)
from a local path, HTTPS URL or Hugging Face repository. The preparation guide
covers revision pinning, checksum verification and download progress. Use an
instruct/chat GGUF for chat, an embedding GGUF for vectors, or a `.litertlm` bundle on a supported
LiteRT-LM target. Check the model card for its license and memory requirements.

## Stream a response

Replace the contents of the quickstart's `try` block with this
streaming code. It reuses the prepared model and sampling configuration and
awaits `onResult` for the final outcome:

```dart
final stream = ai.generateStream(
  prompt: 'List three uses for offline AI, one short phrase per line.',
  config: config,
);
await for (final chunk in stream) {
  print(chunk.text);
}
final response = await stream.onResult;
if (response.finishReason == FinishReason.failed ||
    response.finishReason == FinishReason.aborted) {
  throw response.cause ?? StateError('Generation did not complete.');
}
```

For a stop button, call `prepared.cancelActiveGeneration()`.
For request cancellation, pass a Genkit `CancellationController` token. See
[lifecycle and cancellation](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/usage.md#lifecycle-and-cancellation).

## What you can build

| Feature | Requirements / guide |
| --- | --- |
| Offline chat and streaming | Instruct/chat model; [streaming example](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_streaming_example.dart) |
| Tool calling and agent loops | Tool-capable model/runtime; richer [input schemas](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/tool-input-schemas.md) require grammar support; [tool calling](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/usage.md#tool-calling) |
| Structured JSON output | Grammar-capable backend; [JSON with active tools](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/usage.md#constrained-json-with-tools) requires native llama.cpp; [JSON guide](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/usage.md#structured-json-output) |
| Text/image/audio embeddings for search / RAG | Compatible embedding model; [embedding guide](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/usage.md#embeddings) |
| Application resource/data input | Explicit allowlisted normalization before generation; [resource recipe](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/resource-input.md) |
| Next-token probabilities | Capability-enabled decoder runtime; [typed scoring action](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/next-token-scoring.md) |
| Image and audio input | Compatible multimodal model and runtime, matching projector when required; explicit resolver for native HTTP(S) input; [media guide](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/usage.md#image-and-audio-input) |
| Batch transcription, speech synthesis and image generation | Loaded native typed engines; [speech/image guide](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/media-models.md) |
| Choice, score and yes/no decisions | Experimental Laya encoder/head; native CPU [Genkit flow recipe](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/decision-flows.md) |
| Dedicated raw-prompt contexts and live LoRA | Application-owned native runtimes; [owner guide](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/runtime-owners.md) |
| Same-process raw-prompt caches | Opt-in default native owners; [cache limits](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/prompt-caches.md); no general chat checkpoints |
| Experimental text sessions | Separate `experimental.dart` entry point; bounded native [Genkit bidi sessions](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/bidi-sessions.md) |
| Token counts and loaded runtime diagnostics | Explicit inspection without inference; [inspection guide](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/model-inspection.md) |
| Downloads, cache and progress UI | `ModelSource` and preparation tasks; [model preparation](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/model-preparation.md) |
| OpenTelemetry traces and metrics | Application-configured telemetry provider; [observability](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/observability.md) |

The plugin checks loaded runtime capabilities before each request. Definition
flags permit features; they do not guarantee model support. Discovery stays
lazy, so support booleans start at `false` until verified. Unsupported requests
fail explicitly. See [feature permissions and discovery](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/runtime-support.md).

Strict JSON with active tools requires native llama.cpp, one call per turn and
thinking disabled. LiteRT-LM does not provide this adapter's grammar-constrained
JSON. Dedicated native LiteRT-LM CPU embedding engines support qualified
text/image/audio inputs; conversation engines and Web LiteRT-LM reject embedding
requests. Tool-call quality varies by model; runtime support alone does not prove
reliability. Retrieval and Genkit document augmentation remain application
responsibilities.

## Runnable examples

Runnable examples download and cache pinned Hugging Face models by default.
Overrides accept local paths, `hf://` sources or HTTPS URLs. Media input/output
files remain local. The example index includes a verification matrix.

Run the standalone [pub.dev quickstart](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_example.dart)
from a checkout; its default downloads the pinned Qwen3.5 model:

```bash
dart run example/genkit_llamadart_example.dart
```

The [example index](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/README.md)
provides commands, model sizes and setup for streaming, typed tool loops,
structured JSON, embeddings, local retrieval, inspection/scoring, download UI,
Laya decisions, dedicated owners, live LoRA, image input, transcription, WAV
synthesis, PNG generation and telemetry. Most chat examples can reuse a local
model through `LLAMADART_MODEL_SOURCE` (or the older `LLAMADART_MODEL_PATH`).

For a small retrieval application, try the
[local-text question-answering recipe](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/local-retrieval.md).
It explicitly inserts bounded passages in messages; Genkit's standard `docs`
forwarding remains unsupported.

## Guides and API reference

- [Generation settings (including thinking, presence penalties and speculative decoding), tools, JSON, embeddings and cancellation](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/usage.md)
- [Model preparation, cache policy and loading UI](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/model-preparation.md)
- [Raw-text token counts, context capacity and backend inspection](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/model-inspection.md)
- [Batch transcription, WAV synthesis and PNG generation](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/media-models.md)
- [Runtime support, discovery and custom runtimes](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/runtime-support.md)
- [Telemetry and engine observers](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/observability.md)
- [Migration to 3.0 / Genkit 1.0](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/migration.md)
- [Public API reference](https://pub.dev/documentation/genkit_llamadart/latest/)
- [Changelog](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/CHANGELOG.md)

## Coding agent setup

The package includes [Dart package skills](https://dart.dev/tools/pub/package-skills)
for generation, model preparation, tool calling and structured output. Install
them into your coding agent's skills directory from your app's root:

```bash
dart run skills@ get
```

## Help and contributing

Report bugs or request features in the
[issue tracker](https://github.com/leehack/llamadart/issues).
[CONTRIBUTING.md](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/CONTRIBUTING.md) covers local checks, meaningful regression
tests and releases; [ARCHITECTURE.md](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/ARCHITECTURE.md) describes package layering.
