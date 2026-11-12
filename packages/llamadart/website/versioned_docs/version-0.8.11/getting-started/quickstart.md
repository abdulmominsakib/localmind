---
title: Quickstart
description: Load a GGUF or LiteRT-LM model, generate tokens, and try embeddings with the core llamadart APIs in minutes.
---

This quickstart uses the core `LlamaEngine` API.

## Minimal generation example

Start with a model source instead of a machine-specific file path. On native
Dart/Flutter targets, `loadModelSource(...)` downloads the file on first run,
stores it in the package-managed model cache, and reuses the cached file on
later runs.

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final LlamaEngine engine = LlamaEngine(LlamaBackend());

  try {
    await engine.loadModelSource(
      ModelSource.parse(
        'hf://unsloth/SmolLM2-135M-Instruct-GGUF/'
        'SmolLM2-135M-Instruct-Q2_K.gguf',
      ),
      modelParams: const ModelParams(contextSize: 1024, gpuLayers: 0),
      onProgress: (progress) {
        final fraction = progress.fraction;
        if (fraction != null) {
          print('download ${(fraction * 100).toStringAsFixed(1)}%');
        }
      },
    );

    final output = await engine.create(
      const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Rewrite professionally: i need this done asap',
        ),
      ],
      params: const GenerationParams(maxTokens: 64, temp: 0.2),
    ).map((chunk) => chunk.choices.first.delta.content ?? '').join();
    print(output);
  } finally {
    await engine.dispose();
  }
}
```

This example uses `engine.create(...)`, the stateless chat-completion API: the
model's chat template is applied, but no conversation history is stored between
calls. Use [First Chat Session](./first-chat-session) when you want automatic
multi-turn history, or [Generation and Streaming](../guides/generation-and-streaming)
when you need to choose between raw prompts, stateless chat, and stateful chat.

The small SmolLM2 GGUF above is intended for copy/paste smoke tests. For a live
conference demo, run it once beforehand so the Hugging Face source remains in
the code while the actual presentation path uses the local cache instead of
conference Wi-Fi.

LiteRT-LM `.litertlm` bundles load through the same engine. Native targets load
local bundle paths, including paths resolved by `loadModelSource(...)`; web
targets load web-compatible `.litertlm` URLs through the `@litert-lm/core`
JavaScript runtime.

```dart
await engine.loadModel(
  'path/to/gemma-4-E2B-it.litertlm',
  modelParams: const ModelParams(
    liteRtLmBackend: LiteRtLmBackendPreference.gpu,
  ),
);
```

`LiteRtLmBackendPreference.auto` is the default. It chooses GPU on Android,
macOS, and web, and CPU on other current LiteRT-LM targets. Android native
callers can request `LiteRtLmBackendPreference.npu` for devices and model
bundles that support the LiteRT-LM NPU delegate. Web rejects NPU selection
explicitly.

## Stateless chat completions

For OpenAI-style message arrays, use `engine.create(...)`:

```dart
final messages = [
  LlamaChatMessage.fromText(
    role: LlamaChatRole.user,
    text: 'Give me three bullet points about Dart.',
  ),
];

await for (final chunk in engine.create(messages)) {
  final text = chunk.choices.first.delta.content;
  if (text != null) {
    print(text);
  }
}
```

## Embeddings (single and batch)

```dart
final single = await engine.embed('hello world');
final batch = await engine.embedBatch([
  'semantic search',
  'document retrieval',
]);

print('single dims=${single.length}');
print('batch size=${batch.length}');
```

Embeddings are a llama.cpp/GGUF capability in the current package. Check
`engine.supportsEmbeddings` before calling these APIs when your app can switch
between GGUF and LiteRT-LM models.

## Next steps

- Use [First Chat Session](./first-chat-session) for automatic history.
- Choose a runtime with [Choosing llama.cpp or LiteRT-LM](../guides/backend-selection).
- Build retrieval flows with [Embeddings](../guides/embeddings).
- Tune [Runtime Parameters](../configuration/runtime-parameters).
- Add tools with [Tool Calling](../guides/tool-calling).
