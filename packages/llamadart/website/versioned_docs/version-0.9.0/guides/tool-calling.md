---
title: Tool calling with local models
sidebar_label: Tool calling
description: Define tools with ToolDefinition, control them with ToolChoice, and run a template-aware tool-calling loop with a local model.
---

Pass `ToolDefinition`s to `engine.create` or `ChatSession.create`. The model's
chat template renders them, and the parser returns the model's calls as
`delta.toolCalls`. Your code runs the tools: nothing in `llamadart`, including
`ChatSession`, invokes a handler for you.

## Define a tool

```dart
final weatherTool = ToolDefinition(
  name: 'get_weather',
  description: 'Get current weather for a city',
  parameters: [
    ToolParam.string('city', description: 'City name', required: true),
    ToolParam.enumType('unit', values: ['celsius', 'fahrenheit']),
  ],
  handler: (params) async {
    final city = params.getRequiredString('city');
    final unit = params.getString('unit') ?? 'celsius';
    return {'city': city, 'temperature': 22, 'unit': unit};
  },
);
```

## Run the tool-call loop

```dart
import 'dart:convert';

final engine = LlamaEngine(LlamaBackend());
await engine.loadModel('model.gguf');
final tools = [weatherTool];
final session = ChatSession(engine);

var parts = <LlamaContentPart>[
  const LlamaTextContent('What is the weather in Seoul?'),
];
for (var round = 0; round < 5; round++) {
  final calls = <LlamaCompletionChunkToolCall>[];
  await for (final chunk in session.create(parts, tools: tools)) {
    final delta = chunk.choices.first.delta;
    if (delta.content != null) print(delta.content);
    calls.addAll(delta.toolCalls ?? const []);
  }
  if (calls.isEmpty) break;

  for (final call in calls) {
    final name = call.function?.name ?? '';
    final arguments = call.function?.arguments ?? '';
    Object? result;
    try {
      final tool = tools.firstWhere((tool) => tool.name == name);
      result = await tool.invoke(
        arguments.isEmpty
            ? const {}
            : jsonDecode(arguments) as Map<String, dynamic>,
      );
    } catch (error) {
      result = 'Error: $error';
    }
    session.addMessage(
      LlamaChatMessage.withContent(
        role: LlamaChatRole.tool,
        content: [
          LlamaToolResultContent(id: call.id, name: name, result: result),
        ],
      ),
    );
  }
  parts = const [];
}
await engine.dispose();
```

- Tool calls arrive complete, with JSON `arguments`, in the final chunk, whose
  `finishReason` is `tool_calls`.
- `ChatSession` stores the assistant's tool calls in its history.
  `session.create(const [])` continues from the tool results without a new
  user turn.
- With `engine.create`, append the assistant message (a `LlamaToolCallContent`
  per call) and the tool messages to your own list before the next call.
- Cap the rounds: a model can keep calling tools.

`LlamaToolResultContent.result` may be any JSON-compatible value. Non-string
results are JSON-encoded into the prompt; strings pass through unchanged. A
message with several results is rendered as one tool message per result.

For an OpenAI-compatible reference, see
[OpenAI-compatible server](../examples/llamadart-server).

## Generic JSON fallback

For templates without a recognized tool-call format, and for Gemma 2/3/3n,
llamadart keeps its generic JSON fallback when tools are passed with
`ToolChoice.auto` or `ToolChoice.required`. It adds a JSON instruction,
builds a grammar from the supplied tools for runtimes that support it, and
parses output such as:

```json
{"tool_call":{"name":"get_weather","arguments":{"city":"Paris"}}}
```

An ordinary answer uses `{"response":"Hello!"}`. The parser returns the
answer or tool call through the same API as a model-specific format. Your
application still decides whether to invoke the tool.

This fallback is an intentional extension to the tested llama.cpp versions
(`b10549` and `v0.5.0`, commit `7fe450e19`). For the tested ChatML Hermes-3,
SmolLM2 and SmolVLM templates, those versions render without tool definitions
or a tool grammar and return JSON tool envelopes as ordinary text. Matching
that behavior would remove llamadart's existing fallback. The template in the
actual model file determines routing; a model family name alone does not.

### What the fallback does not guarantee

A valid JSON shape does not establish that a model chose the correct tool or
arguments. Generic calling depends on instruction following and should be
validated with the exact model and task.

Tool definitions are passed to the template, but a template that ignores its
`tools` variable can omit names, descriptions and parameter documentation
from the prompt. The generic instruction only explains the JSON envelope;
it does not insert a tool catalog. The grammar can constrain names and
argument shapes without explaining their meaning to the model. Inspect
`engine.chatTemplate(...)`; if the definitions are missing, provide them in
your system instruction or use a template with native tool support.

`ToolChoice.none` disables the fallback tool instruction and tool grammar for
these templates. Backend restrictions still apply: in particular, this
fallback does not add grammar enforcement to LiteRT-LM. See
[Chat templates and output parsing](./chat-template-and-parsing) for runtime
routing and [model families](../getting-started/model-families) for formats.

## Tool choice semantics

- `ToolChoice.none`: disable tool calls for that request.
- `ToolChoice.auto`: model decides whether to call tools.
- `ToolChoice.required`: model must emit tool calls.

On Web with WebGPU (llama.cpp), the bridge applies a grammar from the first
token and cannot wait for a tool-call trigger. `ToolChoice.auto` therefore skips
a lazy tool-call grammar, and tool calls are parsed from the output
best-effort. `ToolChoice.required` keeps a grammar that starts at the first
token and fails early with `LlamaUnsupportedException` when the chat format's
required-tool grammar is lazy.

Parser details, such as call validation against the supplied tools, are in
[Template engine internals](./template-engine-internals#tool-call-parsing).
