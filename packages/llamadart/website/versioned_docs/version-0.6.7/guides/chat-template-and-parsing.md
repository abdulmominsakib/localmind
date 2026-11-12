---
title: Chat Templates and Parsing
---

`llamadart` routes chat rendering/parsing through template handlers aligned to
llama.cpp behavior.

## Parity model

`llamadart` reimplements llama.cpp-style template detection, rendering,
workarounds, grammar wiring, and parse behavior in Dart. This is why
`engine.create(...)` and `engine.chatTemplate(...)` can keep consistent behavior
across native and web backends.

Template rendering is powered by [`dinja`](https://pub.dev/packages/dinja), the
Dart Jinja runtime used by `llamadart` for llama.cpp-compatible template
execution.

For internals and pipeline details, see
[Template Engine Internals](./template-engine-internals).

## Core API

Use `engine.chatTemplate(...)` when you need:

- prompt preview,
- grammar and stop-sequence inspection,
- format-aware rendering diagnostics.

```dart
final result = await engine.chatTemplate(
  messages,
  tools: tools,
  toolChoice: ToolChoice.auto,
  parallelToolCalls: false,
  customTemplate: null,
  chatTemplateKwargs: const {'use_builtin_tools': true},
);

print(result.prompt);
print(result.format);
```

## Useful parameters

- `customTemplate`: per-call template override.
- `chatTemplateKwargs`: additional template globals.
- `templateNow`: deterministic time injection for tests.
- `sourceLangCode` / `targetLangCode`: TranslateGemma style metadata.
- `responseFormat`: structured-output schema hints.

## When to inspect template output

Inspect template output when debugging:

- tool-call shape mismatches,
- stop-sequence behavior,
- model-specific reasoning/content boundaries,
- template routing differences after upgrades.

## Custom template overrides

For application code, the supported customization path is `customTemplate` on
`engine.chatTemplate(...)`.

```dart
import 'package:llamadart/llamadart.dart';

const String customTemplate = '''
{% for message in messages %}
{{ message['role'] }}: {{ message['content'] }}
{% endfor %}
Assistant:
''';

Future<void> main() async {
  final LlamaEngine engine = LlamaEngine(LlamaBackend());

  try {
    await engine.loadModel('model.gguf');
    final messages = [
      LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'Explain local inference in one sentence.',
      ),
    ];

    final rendered = await engine.chatTemplate(
      messages,
      customTemplate: customTemplate,
      addAssistant: true,
    );

    print(rendered.prompt);
    print(rendered.stopSequences);
  } finally {
    await engine.dispose();
  }
}
```

## About custom handlers

`ChatTemplateHandler` is an internal extension point used by built-in format
implementations.

There is currently no public API to register custom handlers globally from
application code. If you need first-class support for a new template format,
open an issue with a minimal reproducible template and sample outputs.
