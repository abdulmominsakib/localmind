---
title: Quickstart
description: Load a GGUF or LiteRT-LM model, generate tokens, and try embeddings with the core llamadart APIs in minutes.
---

This quickstart uses the core `LlamaEngine` API.

## Minimal generation example

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final LlamaEngine engine = LlamaEngine(LlamaBackend());

  try {
    await engine.loadModel('path/to/model.gguf');

    await for (final String token in engine.generate(
      'Write one short sentence about local inference.',
    )) {
      print(token);
    }
  } finally {
    await engine.dispose();
  }
}
```

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
