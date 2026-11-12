---
title: First Chat Session
---

`ChatSession` wraps `LlamaEngine` for multi-turn conversations with automatic
history management.

## Why use ChatSession

- Keeps conversation history for you.
- Applies context-window trimming as history grows.
- Stores assistant messages (including tool call payloads) in session state.

## Minimal chat session

This example also starts from a Hugging Face source so new users can paste the
code without first inventing a local model path. The first run downloads and
caches the model; later runs reuse the cached GGUF.

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final engine = LlamaEngine(LlamaBackend());
  try {
    await engine.loadModelSource(
      ModelSource.parse(
        'hf://unsloth/SmolLM2-135M-Instruct-GGUF/'
        'SmolLM2-135M-Instruct-Q2_K.gguf',
      ),
      modelParams: const ModelParams(contextSize: 1024, gpuLayers: 0),
    );

    final session = ChatSession(engine, systemPrompt: 'You are concise.');

    await for (final chunk in session.create([
      const LlamaTextContent('What is quantization in one sentence?'),
    ])) {
      final text = chunk.choices.first.delta.content;
      if (text != null) {
        print(text);
      }
    }
  } finally {
    await engine.dispose();
  }
}
```

## Resetting state

```dart
session.reset();
```

To clear both history and system prompt:

```dart
session.reset(keepSystemPrompt: false);
```

## When to use engine.create instead

Use `engine.create(...)` directly if your application already owns the full
message history. Common examples are OpenAI-compatible API servers, stateless
HTTP handlers, or apps that persist/edit transcripts themselves.

With `engine.create(...)`, you pass the complete `List<LlamaChatMessage>` for
every request and you must append the assistant response yourself before the
next turn. With `ChatSession`, each `session.create(...)` call takes only the new
user content parts; the session appends user and assistant messages to its
history for you.
