---
title: Template engine internals
description: How the Dart port of the llama.cpp chat template, render and parse pipeline is structured, and how to debug template routing.
---

`llamadart` reimplements the `llama.cpp` chat-template/render/parse stack in
Dart so routing and parser behavior stay consistent across native and web
targets.

## Design goal

The template system prioritizes llama.cpp parity:

- format detection behavior
- handler routing logic
- tool-grammar attachment rules
- parse behavior for thinking and tool-call envelopes

## End-to-end pipeline

```mermaid
sequenceDiagram
    autonumber
    participant App as App/ChatSession
    participant Engine as LlamaEngine
    participant Detect as Format detector
    participant Handler as ChatTemplateHandler
    participant Dinja as dinja runtime
    participant Backend as Generation backend
    participant Parser as Chunk parser

    App->>Engine: create(messages, tools, params)
    Engine->>Detect: detect template format
    Detect-->>Engine: format + capability hints
    Engine->>Handler: select handler/workarounds
    Handler->>Dinja: render chat template
    Dinja-->>Handler: rendered prompt
    Handler-->>Engine: prompt + stops + grammar/parser payload
    Engine->>Backend: generate from rendered prompt

    loop streaming tokens
        Backend-->>Engine: token bytes
        Engine->>Parser: incremental decode/parse
        Parser-->>App: content/thinking/tool deltas
    end

    Engine->>Parser: finalize parse
    Parser-->>App: final tool-call structures + finish reason
```

## Main components

### 1. Format detection

- `ChatTemplateEngine` detects format from template signatures.
- Each detected format maps to a concrete `ChatTemplateHandler`.
- Handlers live under `lib/src/core/template/handlers/`.

### 2. Template capabilities and routing

- `TemplateCaps` reports whether a template supports system role, tools,
  tool calls, parallel tool calls, string and typed content, object
  arguments, and thinking channels.
- `JinjaAnalyzer` detects all but thinking with llama.cpp's capability
  probes: it renders llama.cpp's probe conversations and records which values
  the template reads. Thinking support comes from the template's thinking
  markers.
- A template that reads both strings and content part lists gets image and
  audio as typed parts, unless a further probe finds that it rejects both
  kinds. Every other template gets the media marker in its text.
- Routing workarounds mirror llama.cpp behavior for schema mode, tool-choice
  behavior, and system-message adaptation.

### 3. Render stage

- Handler `render(...)` builds the final prompt and metadata payload.
- Result includes:
  - prompt text
  - stop sequences
  - optional grammar
  - optional PEG parser payload
  - preserved tokens and lazy grammar triggers

### 4. Parse stage

- During streaming, partial output is parsed incrementally for content/thinking
  deltas and tool-call envelopes.
- On completion, final parse produces stable tool-call structures and finish
  reason semantics.
- PEG-backed parse paths are used when parser payloads are present.

## Tool-call parsing

Qwen XML tool calls are validated against the tools supplied to `engine.create`.
Schema-declared strings such as `"123"` retain their type. Unknown functions,
unknown or duplicate parameters, missing required values, and invalid value
types remain response content instead of producing callable tool deltas.
Tool calls are emitted after final validation; malformed output is preserved
through the existing rollback behavior. Direct schema-free template parsing
retains its legacy behavior, so pass tool definitions when validating calls.

Without a tool-call grammar, as with `ToolChoice.auto` on WebGPU, Qwen2.5 can
copy the double braces its GGUF template prints in the tool prompt:
`<tool_call>{{"name": "get_weather", "arguments": {"city": "Paris"}}}</tool_call>`,
sometimes with fewer or more closing braces. The Hermes/Qwen parser extracts
the call. When only closing braces and whitespace follow the call before
`</tool_call>`, the envelope leaves no content, as for the single-brace form;
otherwise its text stays in content. This deliberately differs from upstream
llama.cpp (`7fe450e1`), which fails to parse this output and returns no tool
call.

Streamed content and reasoning start and end with the whitespace the final
parse keeps, with or without tools, apart from the cases below. The parse
trims content, so the stream holds back leading whitespace until other text
arrives, and trailing whitespace until more text arrives or generation ends.
Other text waits only as described below, for example while it may be a
thinking tag or, with tools, a tool-call opening.

When tool calls are parsed, streamed content equals the content of the final
parse for Hermes, Mistral Nemo, Magistral, Qwen3-Coder XML, DeepSeek R1 and
V3, Command R7B, Cohere2 MoE, Granite, Nemotron V2, Apertus, MiniCPM5,
Hunyuan V3 and EXAONE MoE output, and for Seed-OSS, MiniMax M2, Apriel 1.5
and Xiaomi MiMo output without a forced-open thought; those four parses
ignore one. Text from where the format's parse may find a tool-call opening,
and trailing whitespace, is held until later output rules the opening out or
generation ends, as llama.cpp (`7fe450e1`) PEG `until` stops content before a
whole delimiter or a partial one at the end of the input. With Qwen3-Coder
XML, a `<tool_call>` also ends a forced-open thought when the output has no
thinking tag, as its parse does. For these formats, with or without tools, a
start tag the model repeats at the start of a forced-open thought is dropped,
as in the parse, and when the output has no start tag, an end tag after the
first one is content. A later start tag makes the parse end a thought at each
earlier end tag; the stream does so only when the start tag arrives in the
same token as the end tag.

Streamed reasoning equals the parse too. The parse trims each thought;
upstream llama.cpp (`7fe450e1`) keeps the whitespace before `</think>`, so
with the Qwen3 template it returns `"Plan it.\n"` for
`<think>\nPlan it.\n</think>`. Except for Qwen3-Coder XML, the parse also
replaces an escaped `\n` or `\r` in reasoning with a newline or a carriage
return; the Qwen3-Coder XML parse keeps them, as llama.cpp (`7fe450e1`) does
with the Qwen3.5 template. When tool calls are parsed, the stream of the
formats above replaces them too, holding back a trailing `\` until the next
token; otherwise it keeps them as generated. One exception is a forced-open
thought that never closes and starts with whitespace, with or without tools.
The parse keeps it untrimmed,
but the stream drops the leading whitespace before it can know the thought
will not close. The streamed text is then no prefix of the parse, so the final
reconciliation adds nothing and the trailing whitespace is lost too:
`"  \n Hello there.  \n\n"` streams as `"Hello there."`. The EXAONE MoE parse
returns a forced-open thought that never closes as content, so it streams as
reasoning and then as content. The DeepSeek V3 parse returns one as
reasoning, as llama.cpp (`7fe450e1`) does with the DeepSeek V3.1 template.

Output parsed with a PEG parser (Ministral, Solar Open, Nemotron V3, or
Qwen3-Coder XML given a parser) streams the content and reasoning of partial
PEG parses when tool calls are parsed. Those parses hold back a possible
opening themselves. A Ministral thought cut off by the token limit therefore
streams as reasoning, although the final parse returns it, with its `[THINK]`
tag, as content. Without tools, the PEG parse trims only trailing whitespace,
so the stream keeps leading whitespace.

Streams built from partial parses hold back trailing whitespace until more
text arrives. They are used for Gemma 4 output, and, when tool calls are
parsed, for PEG output, Kimi K3, MiniMax M1 and M3, DeepSeek V3.2 and V4,
Muse Glimmer, GLM 4.5 and Laguna output, and output of other formats not
listed above that starts with a forced-open thought or a tool call. A partial
parse taken before `</think>` arrives can stream leading whitespace of a
forced-open thought that the final parse trims.

## `dinja` integration

`llamadart` uses [`dinja`](https://pub.dev/packages/dinja), the Dart Jinja
runtime used as the execution layer for model-provided chat templates
(`tokenizer.chat_template`).

`dinja` was built in the `llamadart` ecosystem as a Dart port of the
llama.cpp-style minimal Jinja execution model, then used as the foundation of
the template engine in this package.

Inside `llamadart`, the `jinja/` integration layer acts as the Dinja-plugin
surface: it wires llama.cpp-specific globals and capability analysis into
template execution.

Why this matters:

- no Python runtime dependency in app environments
- on-device template rendering in pure Dart
- reusable lexer/parser access for capability analysis (`JinjaAnalyzer`)

In practice, our template integration stack is:

1. `dinja` template execution for render.
2. `llamadart` routing/parity logic around it.
3. `llamadart` parser/grammar infrastructure for streamed output.

## Practical debugging flow

1. Call `engine.chatTemplate(...)` to inspect prompt/format/stops.
2. Verify tool schema and grammar expectations before generation.
3. Compare parsed output in partial vs final streaming stages.
4. Re-test after model/runtime upgrades to catch routing shifts early.

## Related docs

- [Chat Templates and Parsing](./chat-template-and-parsing)
- [Tool Calling](./tool-calling)
- [Generation and Streaming](./generation-and-streaming)
