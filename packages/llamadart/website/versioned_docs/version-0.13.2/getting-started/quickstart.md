---
title: "Quickstart: run a model on the device"
sidebar_label: Quickstart
description: Download a small GGUF model from Hugging Face, load it with LlamaEngine, and stream a chat completion.
---

This quickstart uses the core `LlamaEngine` API.

## Minimal generation example

Start with a model source instead of a machine-specific file path. On native
Dart/Flutter targets, `LlamaEngine.load(...)` downloads the file on first run,
stores it in the package-managed model cache, and reuses the cached file on
later runs. The cache is a per-user directory on desktop and the app's cache
directory on Android and iOS, so no `path_provider` setup is needed; see
[Choose the cache location](../guides/model-downloads#choose-the-cache-location)
to move it.

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final LlamaEngine engine = await LlamaEngine.load(
    LlamaModel(
      ModelSource.parse(
        'hf://unsloth/SmolLM2-135M-Instruct-GGUF/'
        'SmolLM2-135M-Instruct-Q2_K.gguf',
      ),
    ),
    params: const ModelParams(contextSize: 1024, gpuLayers: 0),
    onProgress: (progress) {
      final fraction = progress.fraction;
      if (fraction != null) {
        print('download ${(fraction * 100).toStringAsFixed(1)}%');
      }
    },
  );

  try {
    final output = await engine.create(
      const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Rewrite professionally: i need this done asap',
        ),
      ],
      params: const GenerationParams(maxTokens: 64, temp: 0.2),
    ).text();
    print(output);
  } finally {
    await engine.dispose();
  }
}
```

`engine.create(...)` applies the chat template but keeps no history; see
[Choosing the right API](../guides/generation-and-streaming#choosing-the-right-api).

The SmolLM2 135M `Q2_K` model is a smoke-test model: it downloads quickly but
is not a measure of output quality. See [Finding models](./finding-models)
for real starting points. Run it once before a demo; later runs load from the
cache without a network.

LiteRT-LM `.litertlm` bundles load through the same engine; see
[Choosing llama.cpp or LiteRT-LM](../guides/backend-selection).

## Next steps

- Use [First chat session](./first-chat-session) for automatic history.
- Choose a runtime with [Choosing llama.cpp or LiteRT-LM](../guides/backend-selection).
- Compute embeddings with [Embeddings](../guides/embeddings).
- Tune [Runtime Parameters](../configuration/runtime-parameters).
- Add tools with [Tool Calling](../guides/tool-calling).
