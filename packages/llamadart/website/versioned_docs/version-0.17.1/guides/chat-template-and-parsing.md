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
- `chatTemplateKwargs`: additional template globals, as llama.cpp's
  `chat_template_kwargs`. TranslateGemma reads its language codes from
  `{'source_lang_code': 'en', 'target_lang_code': 'ko'}`, defaulting to
  `en-GB`; the `sourceLangCode` and `targetLangCode` parameters are
  deprecated. As in llama-server, a boolean `enable_thinking` kwarg (or,
  without one, a boolean `thinking`) overrides `enableThinking` for the
  rendered prompt, forced-open thought, stops and streamed reasoning. Other
  values do not. Every template receives the resulting flag as
  `enable_thinking`, as llama.cpp passes it, so `enableThinking` alone
  reaches templates such as GLM-OCR (`/nothink`) and SmolLM3 (`/no_think`).
  Templates that ignore `enable_thinking` get their own switch from
  `enableThinking` instead: `reasoning` and `skip_thinking` for Cohere2 MoE,
  `reasoning_effort` for Hy3, `thinking_mode` for MiniMax M3 and `thinking`
  for Kimi K3. llama-server sets none of these, so with the default
  `enableThinking: true` Hy3 renders `high` and MiniMax M3 `enabled`, where
  llama-server renders the template defaults `no_think` and `adaptive`; pass
  the kwarg to get those. A kwarg that sets that switch wins over the value
  `enableThinking` sets, as in llama-server, with two exceptions under
  `enableThinking: false`: llamadart still closes a thought the kwarg opens
  (Hy3 `high`, MiniMax M3 `enabled`, Cohere2 MoE `reasoning: true`), which
  llama-server leaves open, and Cohere2 MoE still drops earlier thoughts
  unless `skip_thinking` is set too. Hy3 accepts only `no_think`, `low` and
  `high`; any other `reasoning_effort`, such as `none` or `medium`, makes the
  template throw `LlamaInferenceException`, as llama.cpp's render fails.
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

With thinking off, DeepSeek V3.1, Qwen3, QwQ and Qwen3.5 templates close the
thought in the prompt, and the reply is parsed as content, as in llama-server:
a `<think>` block the model still writes stays in `chunk.text` and the
message content.

Templates such as StepFun3.5-Flash, DeepSeek R1 distills, MiniMax M2 and
Nemotron Nano v2 open the thought even with thinking off. llamadart closes it
in the prompt, but a thought the model still writes before `</think>` is
reasoning, as in llama-server. So that it never streams as `chunk.text`, the
reply's text is held until `</think>` or `<think>` arrives, or the reply ends.
Cohere2 MoE templates open it unless `reasoning` is false, which llamadart
sets from `enableThinking`; their reply is held until a thinking tag,
`<|START_TEXT|>` or `<|START_ACTION|>`, where llama-server ends the thought,
and the text before it is reasoning. Seed-OSS templates open no thought: a
reply has one only when it starts with `<seed:think>`, and other thinking tags
are content, as in llama-server. To parse a reply as the engine does, pass
the render to `ChatTemplateEngine.parseRendered(rendered, output)`, where
`rendered` is the unchanged result of `ChatTemplateEngine.render` or
`engine.chatTemplate`. `ChatTemplateEngine.parse`, which takes only the
format and flags, cannot tell whether the template opened the thought or the
render closed it, so it also ends a Seed-OSS thought at a `</seed:think>` in a
reply that did not open it.

Tencent Hunyuan V3 templates are also detected directly, including their
namespaced reasoning tags and parallel `<tool_call:opensource>` envelopes.

When a DeepSeek V3.1, Qwen3.5, QwQ or other Hermes-style template opens a
thought in the prompt, the reasoning is the text before the first `</think>`
as the model wrote it, escapes and repeated `<think>` included, and the rest is
content, as in llama-server. A Qwen3.5 `<tool_call>` also ends the thought.
A Cohere2 MoE thought ends at `<|END_THINKING|>`, or at a `<|START_TEXT|>` or
`<|START_ACTION|>` that comes first, and thinking tags inside a text or action
are text.
See [Template engine internals](./template-engine-internals) for the parse and
stream rules of each format.

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
GPU, iOS, Android and Web adoption still need separate validation.

Native LiteRT-LM recognizes renamed Qwen 3 bundles only with a Qwen 3
model-type declaration (metadata field 6), or the complete canonical Qwen 3
template in field 7 or `ModelParams.chatTemplate`. Generic ChatML and thinking
markers do not distinguish Qwen 3 from other families. Legacy litert-community
Qwen3-0.6B bundles lack fields 6 and 7: after renaming, disabled thinking can
still produce empty content. Keep `Qwen3` in the filename, or set
`ModelParams.chatTemplate` to `liteRtLmQwen3ChatTemplate`, exported by
`package:llamadart/llamadart.dart`. Obtain it when constructing the parameters;
it follows the installed template across upgrades, so copied Jinja is unnecessary.
Native text conversations honor `enableThinking: false`.

Web `@litert-lm/core@0.18.0` has no conversation-template setter and rejects this
canonical Qwen3 override at model load with `LlamaUnsupportedException`.
Use native LiteRT-LM for this contract. Generic Web overrides and loads without
an override retain their existing behavior.

Other families keep their native bundle
template and content-shape adapter; an override still drives Dart-side metadata
and parsing. Validation evidence:
[Feature validation evidence](../maintainers/feature-validation#qualification-procedures).

On a filename-matched or positively identified Qwen 3 text bundle the native
conversation renders a `ModelParams.chatTemplate` itself and passes each
message's `content` to the template as a list of parts,
`[{"type": "text", "text": ...}]`. A
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
older LiteRT-LM runtimes often read `message.content` as a string. Such a
template writes the serialized list into the prompt when it interpolates the
content, fails the request when it concatenates it, and renders empty messages
when it only handles `content is string`.

On native platforms `llamadart` checks this once per loaded model, on its
first use, and gives a template of any of those three shapes the string again,
so the bundle answers as it was built to. A template that already
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

Jinja string literals in embedded and custom templates accept `\xHH`
hexadecimal escapes, with exactly two hexadecimal digits. For example,
`\x00` matches a NUL character and `\xE9` produces `é`;
`\\x41` keeps the literal text `\x41`. A malformed escape raises
`LlamaException` naming the template source. Model architectures must also be
supported by the selected runtime; this syntax repair does not qualify Flint
for the pinned native runtime
([native #112](https://github.com/leehack/llamadart-native/issues/112)).

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
