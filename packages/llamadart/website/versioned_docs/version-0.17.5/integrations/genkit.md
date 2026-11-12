---
title: Genkit with local models
sidebar_label: Genkit
description: Install the separate genkit_llamadart package and generate or stream a first local response.
---

Use `genkit_llamadart` to put local inference behind Genkit's model, tool and
flow APIs. For direct engine control, use the [core quickstart](../getting-started/quickstart).
The [adapter README](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/README.md)
and its guides are canonical for adapter behavior.

## Install the published combination

This example targets published **genkit_llamadart 3.6.0**, **Genkit 1.0.0** and
**llamadart 0.17.0**, on Dart **3.12+**. The adapter remains independently
versioned after its source moves into this repository. Core's Dart floor remains
3.10.7; installing this optional adapter raises the application requirement.

The next `genkit_llamadart` release is planned to target llamadart 0.17; it is
not published yet.

```bash
dart pub add 'genkit:1.0.0' 'genkit_llamadart:3.6.0' 'llamadart:0.17.0'
```

For a Flutter app use `flutter pub add`. Apple SwiftPM apps using GGUF also add
`llamadart_llama_cpp_flutter:0.17.0` directly. A LiteRT-LM app instead needs its
matching companion; see [installation](../getting-started/installation).
iOS requires 16.4+ and macOS 14.0+. On Windows install the matching Microsoft
Visual C++ runtime. CPU is the baseline; GPU placement needs its own qualification.

## Generate, then stream

Save as `bin/main.dart` and run `dart run bin/main.dart /path/to/chat.gguf` with
an existing instruction-tuned GGUF. Without an argument, preparation downloads
the pinned 88 MB SmolLM2 fixture; this small fixture checks the pipeline, not
answer quality. Preparation caches downloads; loading occurs on first use.

```dart
import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';

Future<void> main(List<String> args) async {
  final prepared = await llamaDart.prepareModel(
    name: 'local-chat',
    source: ModelSource.parse(
      args.isEmpty
          ? 'hf://unsloth/SmolLM2-135M-Instruct-GGUF/SmolLM2-135M-Instruct-Q2_K.gguf?revision=9e6855bc4be717fca1ef21360a1db4b29d5c559a'
          : args.single,
    ),
    modelParams: const ModelParams(
      contextSize: 1024,
      device: ComputeDevice.cpu,
    ),
  );
  final ai = prepared.createGenkit();
  const config = LlamaDartGenerationConfig(maxTokens: 32, temperature: 0.2);
  try {
    final first = await ai.generate(prompt: 'Say hello.', config: config);
    if (first.finishReason == FinishReason.failed ||
        first.finishReason == FinishReason.aborted) {
      throw first.cause ?? StateError('Generation did not complete.');
    }
    print(first.text);

    final stream = ai.generateStream(prompt: 'Name a fruit.', config: config);
    await for (final chunk in stream) {
      print(chunk.text);
    }
    final result = await stream.onResult;
    if (result.finishReason == FinishReason.failed ||
        result.finishReason == FinishReason.aborted) {
      throw result.cause ?? StateError('Streaming did not complete.');
    }
  } finally {
    try {
      await prepared.dispose();
    } finally {
      await ai.shutdown();
    }
  }
}
```

`generate` calls here are independent requests. Use Genkit's history/session APIs
when you want a conversation. Do not wrap this runtime in a second llamadart
`ChatSession`. Always inspect the final result: Genkit may represent an adapter
error as `finishReason: failed` instead of throwing during iteration.

For a Stop button call `await prepared.cancelActiveGeneration()` while a request
is active. For per-request cancellation use Genkit's `CancellationController`;
see [lifecycle and cancellation](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/usage.md#lifecycle-and-cancellation).
Dispose the prepared handle before shutting down Genkit; disposal is terminal.

## Next capabilities

- [Tools and generation settings](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/usage.md): tool loops require a compatible template/model. Strict JSON requires grammar support; strict output combined with tools has additional native llama.cpp limits.
- [Runtime support](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/runtime-support.md): permission flags do not establish support. Capabilities are probed for the loaded runtime; unsupported/version-skew requests fail actionably.
- [Retrieval](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/local-retrieval.md) and [embeddings](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/usage.md#multimodal-embeddings): use embedding-specific models and modality probes. Native LiteRT-LM CPU embeddings are distinct from chat and Web support.
- [Media tasks](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/media-models.md), [model preparation](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/model-preparation.md) and [observability](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/observability.md).

## Browser setup

The native filesystem quickstart above is not a complete browser deployment.
The adapter has browser capability guards, but Genkit/browser integration and
model loading still need application testing. Stage the pinned bridge runtime
and worker assets under your origin and configure model-host CORS and isolation
headers using [Web bridge setup](../platforms/webgpu-bridge). A passing fake or
guard test does not prove real worker/model inference. Native-only media owners
and filesystem helpers remain unavailable in browsers; browser virtual paths do
not imply durable storage. Main-only APIs and pending issues are not part of the
published version combination above.
