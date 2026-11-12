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

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final engine = LlamaEngine(LlamaBackend());
  await engine.loadModel('path/to/model.gguf');

  final session = ChatSession(engine, systemPrompt: 'You are concise.');

  await for (final chunk in session.create([
    const LlamaTextContent('What is quantization in one sentence?'),
  ])) {
    final text = chunk.choices.first.delta.content;
    if (text != null) {
      print(text);
    }
  }

  await engine.dispose();
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

Use `engine.create(...)` directly if your application already owns full message
history (for example an API server that receives complete request payloads).
