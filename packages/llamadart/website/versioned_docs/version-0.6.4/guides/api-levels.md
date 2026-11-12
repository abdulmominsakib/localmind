---
title: Low-Level vs High-Level API
---

`llamadart` exposes two API layers:

- **High-level API** (`LlamaEngine` + `ChatSession`) for most application code.
- **Backend API** (`LlamaBackend`) for advanced runtime control.

## High-Level API

Use this by default. It handles model lifecycle, template routing, streaming, and
chat history management.

**Key Components:**
- **`LlamaEngine`**: Loads/unloads models and runs stateless chat completions.
- **`ChatSession`**: Keeps message history for multi-turn conversation flows.

**Advantages:**
- **Simplicity**: Work with message/content objects instead of low-level backend calls.
- **Template-aware**: Uses model chat templates and parsing behavior automatically.
- **Tool support**: Works with structured tool-call outputs.

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final LlamaEngine engine = LlamaEngine(LlamaBackend());

  try {
    await engine.loadModel('model.gguf');

    final ChatSession session = ChatSession(engine)
      ..systemPrompt = 'You are a concise assistant.';

    await for (final LlamaCompletionChunk chunk in session.create([
      LlamaTextContent('Hello! Give me one sentence about local inference.'),
    ])) {
      final String? text = chunk.choices.first.delta.content;
      if (text != null) {
        print(text);
      }
    }
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
