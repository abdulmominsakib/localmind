---
title: Quickstart
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

## Next steps

- Use [First Chat Session](./first-chat-session) for automatic history.
- Tune [Runtime Parameters](../configuration/runtime-parameters).
- Add tools with [Tool Calling](../guides/tool-calling).
