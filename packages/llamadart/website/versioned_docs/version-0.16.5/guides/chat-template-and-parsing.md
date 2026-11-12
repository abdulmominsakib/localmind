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

Jinja string literals in embedded and custom templates accept `\xHH`
hexadecimal escapes, with exactly two hexadecimal digits. For example,
`\x00` matches a NUL character and `\xE9` produces `é`;
`\\x41` keeps the literal text `\x41`. A malformed escape raises
`LlamaException` naming the template source. Model architectures must also be
supported by the selected runtime; this syntax repair does not qualify Flint
for the pinned native runtime
([native #112](https://github.com/leehack/llamadart-native/issues/112)).

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
- `chatTemplateKwargs`: additional template globals, as llama.cpp's
  `chat_template_kwargs`. TranslateGemma reads its language codes from
  `{'source_lang_code': 'en', 'target_lang_code': 'ko'}`, defaulting to
  `en-GB`; the `sourceLangCode` and `targetLangCode` parameters are
  deprecated.
- `templateNow`: deterministic time injection, including `strftime_now` and
  date globals. For multi-turn chat, construct
  `TemplateTimeChatSession(engine, templateNow: DateTime.utc(2026, 1, 2))`.
  Each listened request snapshots that session setting before context
  preparation, so budgeting and generation use the same time. Changing it
  affects the next request; each tool-loop round is a request. `reset()` keeps
  it, and setting it to `null` restores the normal clock. Ordinary
  `ChatSession` interfaces and application extensions remain compatible.
  This controls Dart-rendered templates; LiteRT-LM runtime-owned templates
  retain their runtime clock.
- `responseFormat`: structured-output constraint; unrecognised shapes and
  schemas the grammar converter cannot represent throw
  `LlamaUnsupportedException`. Native LiteRT-LM uses a separate admitted JSON
  Schema provider for its bounded scalar-object subset; it never consumes GBNF.

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
`chunk.thinking` carries reasoning text while `chunk.text` remains reserved
for final answer content.

Tencent Hunyuan V3 templates are also detected directly, including their
namespaced reasoning tags and parallel `<tool_call:opensource>` envelopes.

### LiteRT-LM template registry

GGUF models expose `tokenizer.chat_template` metadata directly through the
llama.cpp backend. Native `.litertlm` bundles do not currently expose their
embedded template through the LiteRT-LM FFI, so `llamadart` uses a
filename-keyed registry for supported Gemma and Qwen LiteRT-LM families.

Native LiteRT-LM `engine.create(...)` uses LiteRT-LM's Conversation APIs for
eligible chat requests, including images and audio, so system messages,
history, tools, media, and extra context stay structured inside the runtime.
The Dart template registry is still used for template metadata, streamed output
parsing, `engine.chatTemplate(...)`, web LiteRT-LM, and fallback prompt
rendering when a request cannot use the native conversation path.

For native CPU Qwen3-0.6B, use the updated
[LiteRT-LM bundle](https://huggingface.co/litert-community/Qwen3-0.6B/resolve/e6687177e00897731e7716267eebd4eba0dde7c2/Qwen3-0.6B.litertlm)
(revision `e6687177e00897731e7716267eebd4eba0dde7c2`, SHA-256
`c5f39b4191926786c3e6668b62af4d6eb15248dfc7a5348252a9b406f33f2108`).
The older `8414150f` bundle can emit literal byte-level token spellings such
as `ĠðŁĺĬ` instead of an emoji. A runtime upgrade alone does not repair its
tokenizer; replace the model artifact. Preserve literal user text rather than
rewriting these characters. The updated bundle is verified on macOS CPU;
Linux/Windows CPU qualification runs in the maintained smoke workflow.
GPU, iOS, Android and Web adoption still need separate validation
([#554](https://github.com/leehack/llamadart/issues/554)).

Native LiteRT-LM recognizes renamed Qwen 3 bundles only with a Qwen 3
model-type declaration (metadata field 6), or the complete canonical Qwen 3
template in field 7 or `ModelParams.chatTemplate`. Generic ChatML and thinking
markers do not distinguish Qwen 3 from other families. Legacy litert-community
Qwen3-0.6B bundles lack fields 6 and 7: after renaming, disabled thinking can
still produce empty content. Keep `Qwen3` in the filename, or set
`ModelParams.chatTemplate` to `liteRtLmQwen3ChatTemplate`, exported by
`package:llamadart/llamadart.dart`. Obtain it when constructing the parameters;
it follows the installed template across upgrades, so copied Jinja is unnecessary.
Native text conversations honor `enableThinking: false`; older runtimes without
the template setter throw `LlamaUnsupportedException`.

Web `@litert-lm/core@0.18.0` has no conversation-template setter and rejects this
canonical Qwen3 override at model load with `LlamaUnsupportedException`.
Use native LiteRT-LM for this contract. Generic Web overrides and loads without
an override retain their existing behavior.

Other families keep their native bundle
template and content-shape adapter; an override still drives Dart-side metadata
and parsing. The maintained registry coverage, smoke commands, and contribution
notes live in
[`doc/litert_lm_templates.md`](https://github.com/leehack/llamadart/blob/main/doc/litert_lm_templates.md).

On a filename-matched or positively identified Qwen 3 text bundle the native
conversation renders a `ModelParams.chatTemplate` itself, and from LiteRT-LM
`v0.18.0` it passes each
message's `content` to the template as a list of parts,
`[{"type": "text", "text": ...}]`, where `v0.17.0-8` passed the string. A
template that concatenates `message['content']` as a string fails the
generation with `LlamaInferenceException`, and one that interpolates it
renders the list into the prompt without an error. Read both shapes:

```jinja
{%- if message['content'] is string -%}
  {{- message['content'] -}}
{%- else -%}
  {%- for part in message['content'] -%}
    {%- if part['type'] == 'text' -%}{{- part['text'] -}}{%- endif -%}
  {%- endfor -%}
{%- endif -%}
```

`engine.chatTemplate(...)` renders in Dart and does not show what the runtime
rendered.

The template embedded in a bundle receives the same list. Bundles built for
LiteRT-LM before `v0.18.0` often read `message.content` as a string, which the
older runtime allowed for a single text part. With `v0.18.0` such a template
writes the serialized list into the prompt when it interpolates the content,
fails the request when it concatenates it, and renders empty messages when it
only handles `content is string`.

On native platforms `llamadart` checks this once per loaded model, on its
first use, and gives a template of any of those three shapes the string again,
so the bundle answers as it did with `v0.17.0-8`. A template that already
reads parts is left alone. If `llamadart` cannot adapt a template it logs one
warning, and a request that then fails names the template. That is the case
for a template written in the runtime's single-turn `is_appending_to_prefill`
form. Web LiteRT-LM (`@litert-lm/core` `0.18.0`) has no such adapter: use a
bundle whose template reads content parts.

## Custom template overrides

To replace a model's template for every request, such as a GGUF file whose
embedded template is missing or broken, load it with
`ModelParams(chatTemplate: ...)`. `engine.create` and `engine.chatTemplate`
then render with that template instead of `tokenizer.chat_template` and its
`tool_use` variant, and detect the tool-call and reasoning format from it, as
llama.cpp's `--chat-template-file` does. On llama.cpp, null or empty keeps
the model's template; on LiteRT-LM, an empty string also replaces the built-in
template. The value is Jinja source: unlike llama.cpp's `--chat-template`, a
name such as `chatml` is not mapped to a built-in template.
`engine.getMetadata()` still reports the GGUF `tokenizer.chat_template`.

To preview a different template for one call, pass `customTemplate` to
`engine.chatTemplate(...)`; it takes precedence over `ModelParams.chatTemplate`.
The low-level WebGPU `LlamaBackend.applyChatTemplate` cannot render either
override and throws `LlamaUnsupportedException`.

```dart
import 'package:llamadart/llamadart.dart';

const String customTemplate = '''
{% for message in messages %}
{{ message['role'] }}: {{ message['content'] }}
{% endfor %}
Assistant:
''';

Future<void> main() async {
  final LlamaEngine engine = await LlamaEngine.load(
    LlamaModel(ModelSource.path('model.gguf')),
  );

  try {
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
