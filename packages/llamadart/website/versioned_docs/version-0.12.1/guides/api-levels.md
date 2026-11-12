---
title: High-level vs backend API
sidebar_label: API levels
description: Choose between the high-level LlamaEngine and ChatSession API and the LlamaBackend API for advanced runtime control.
---

`llamadart` exposes two API layers:

- **High-level API** (`LlamaEngine` + `ChatSession`) for most application code.
- **Backend API** (`LlamaBackend`) for advanced runtime control.

## Entrypoints

| Import | Contents | Stability |
| --- | --- | --- |
| `package:llamadart/llamadart.dart` | The app API: engines, sessions, models, `LlamaBackend()` and errors. | Semantic versioning |
| `package:llamadart/backend.dart` | The backend SPI: the optional `Backend*` interfaces, `LiteRtLmBackend`, `LiteRtLmRuntimeClient` and its ASR session types, and the `LlamaEngineBackendHooks` extension. | Semantic versioning |
| `package:llamadart/llama_cpp_bindings.dart` | Raw llama.cpp, ggml and mtmd FFI bindings. Native only. | None: any llama.cpp update can change them |

Apps need only the first. Import `backend.dart` next to it to implement a
custom backend or a test fake (`implements LlamaBackend, BackendTextToSpeech`),
or to drive LiteRT-LM directly.

## High-Level API

Use this by default. It handles model lifecycle, template routing, streaming, and
chat history management.

**Key Components:**
- **`LlamaEngine`**: Loads/unloads models, runs generation, and can produce
  embeddings.
- **`ChatSession`**: Keeps message history for multi-turn conversation flows.

**Advantages:**
- **Simplicity**: Work with message/content objects instead of low-level backend calls.
- **Template-aware**: Uses model chat templates and parsing behavior automatically.
- **Tool support**: Works with structured tool-call outputs.
- **Embedding APIs**: `embed(...)` and `embedBatch(...)` on the same engine.
- **Next-token scores**: `scoreNextToken(...)` returns next-token
  log-probabilities; see
  [Next-token scores](./generation-and-streaming#next-token-scores).
- **State persistence**: `stateSaveFile(...)` / `stateLoadFile(...)`; see
  [State persistence](./model-lifecycle#save-and-restore-prompt-state).

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final LlamaEngine engine = await LlamaEngine.load(
    LlamaModel(ModelSource.path('model.gguf')),
  );

  try {
    final ChatSession session = ChatSession(engine)
      ..systemPrompt = 'You are a concise assistant.';

    final LlamaCompletion reply = await session.send(
      'Hello! Give me one sentence about local inference.',
    );
    print(reply.text);
  } finally {
    await engine.dispose();
  }
}
```

## Low-Level API

`LlamaBackend` gives direct access to model/context handles and raw generation
streams.

**Key Components:**
- **`LlamaBackend`**: Exposes explicit model/context creation and byte-stream
  generation.

**Advantages:**
- **Granular control**: Manage handles and pipeline steps directly.
- **Integration flexibility**: Useful for specialized runtime integrations.
- **Optional capabilities**: Backends can expose extra interfaces from
  `package:llamadart/backend.dart`, such as `BackendStatePersistence` when a
  runtime supports native KV-cache snapshots.

```dart
import 'dart:convert';
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final LlamaBackend backend = LlamaBackend();
  final ModelParams modelParams = const ModelParams();

  final int modelHandle = await backend.modelLoad('model.gguf', modelParams);
  final int contextHandle = await backend.contextCreate(
    modelHandle,
    modelParams,
  );

  try {
    final Stream<String> textStream = backend
        .generate(
          contextHandle,
          'Hello from low-level API',
          const GenerationParams(),
        )
        .transform(const Utf8Decoder());

    await for (final String text in textStream) {
      print(text);
    }
  } finally {
    await backend.contextFree(contextHandle);
    await backend.modelFree(modelHandle);
    await backend.dispose();
  }
}
```

## Which should you choose?

Start with the high-level API. Move down to `LlamaBackend` only when you need
explicit handle-level control that `LlamaEngine`/`ChatSession` do not provide.
