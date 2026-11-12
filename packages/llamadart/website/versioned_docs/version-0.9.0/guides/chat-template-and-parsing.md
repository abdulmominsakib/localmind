---
title: Chat templates and output parsing
sidebar_label: Chat templates
description: How llamadart detects, renders and parses chat templates in line with llama.cpp, and how to inspect or override a template.
---

`llamadart` reimplements llama.cpp's template detection, rendering and parsing
in Dart, so `engine.create` and `engine.chatTemplate` behave the same on native
and web. Templates run on [`dinja`](https://pub.dev/packages/dinja), a Dart
Jinja runtime; the pipeline is described in
[Template engine internals](./template-engine-internals).

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

Structured output (`responseFormat`, `LlamaStructuredOutput`,
`parseStructuredJson`) is covered in
[Generation and Streaming](./generation-and-streaming#structured-json-output).
`chatTemplate(...)` still accepts the deprecated `jsonSchema` shortcut; if both
are passed, `responseFormat` wins.

## When to inspect template output

Inspect template output when debugging:

- tool-call shape mismatches,
- stop-sequence behavior,
- model-specific reasoning/content boundaries,
- template routing differences after upgrades.

## Built-in format coverage

Built-in handlers include newer formats such as Gemma 4. In practice that means
`llamadart` can detect and parse:

- `<|turn> ... <turn|>` turn framing,
- `<|think|>` thinking enablement in the system prompt,
- `<|channel>thought ... <channel|>` reasoning output,
- `<|tool_call>call:name{args}<tool_call|>` tool-call envelopes.

Gemma 4 thought-channel output is parsed incrementally during streaming, so
`chunk.choices.first.delta.thinking` carries reasoning text while
`chunk.choices.first.delta.content` remains reserved for final answer content.

Tencent Hunyuan V3 templates are also detected directly, including their
namespaced reasoning tags and parallel `<tool_call:opensource>` envelopes.

### LiteRT-LM template registry

GGUF models expose `tokenizer.chat_template` metadata directly through the
llama.cpp backend. Native `.litertlm` bundles do not currently expose their
embedded template through the LiteRT-LM FFI, so `llamadart` uses a
filename-keyed registry for supported Gemma and Qwen LiteRT-LM families.

Native LiteRT-LM `engine.create(...)` uses LiteRT-LM's Conversation APIs for
eligible text-only chat requests so system messages, history, tools, and extra
context stay structured inside the runtime. The Dart template registry is still
used for template metadata, streamed output parsing, `engine.chatTemplate(...)`,
web LiteRT-LM, and fallback prompt rendering when a request cannot use the
native conversation path.

Use `ModelParams.chatTemplate` when loading a `.litertlm` bundle whose family is
not in the registry or whose filename has been changed. The maintained registry
coverage, smoke commands, and contribution notes live in
[`doc/litert_lm_templates.md`](https://github.com/leehack/llamadart/blob/main/doc/litert_lm_templates.md).

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

`ChatTemplateHandler` is exported so handler types are visible, but handlers
are selected internally by `ChatFormat`; apps cannot register their own.

There is currently no public API to register custom handlers globally from
application code. If you need first-class support for a new template format,
open an issue with a minimal reproducible template and sample outputs.
