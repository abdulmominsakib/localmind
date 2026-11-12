---
title: Tool calling with local models
sidebar_label: Tool calling
description: Define tools with ToolDefinition, control them with ToolChoice, and run a template-aware tool-calling loop with a local model.
---

Pass `ToolDefinition`s to `engine.create` or `ChatSession.create`. The model's
chat template renders them, and the parser returns the model's calls as
`chunk.toolCalls`. `session.sendWithTools` runs the calls with each tool's
`handler` until the model answers; `create` and `engine.create` only return
the calls, and your code runs them.

Automatic loops (`sendWithTools` and `completeWithTools`) require reliable
runtime termination reporting. The pinned native LiteRT-LM `v0.18.0` and
Web `@litert-lm/core@0.18.0` cannot distinguish normal completion from a
per-request token cutoff. They throw `LlamaUnsupportedException` before
starting the loop or modifying its history, including when resuming a turn or
passing an empty tools list. Plain `ChatSession.create` and
`LlamaEngine.create` remain available for manually managed completion; their
LiteRT-LM `stop` finish reason does not prove the model reached EOS. Do not
execute calls automatically based on that value or infer truncation from
output length. See the [owner runtime prerequisite](../maintainers/runtime-ownership#litert-lm-termination-reporting).

## Define a tool

`handler` is optional: leave it out for a tool your app runs itself.

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
final engine = await LlamaEngine.load(
  LlamaModel(ModelSource.path('model.gguf')),
);
final session = ChatSession(engine);

final result = await session.sendWithTools(
  'What is the weather in Seoul?',
  tools: [weatherTool],
  maxRounds: 5,
);
switch (result.stopReason) {
  case LlamaToolLoopStopReason.completed:
    print(result.text);
  case LlamaToolLoopStopReason.unhandledToolCalls:
  case LlamaToolLoopStopReason.maxRounds:
  case LlamaToolLoopStopReason.contextExceeded:
  case LlamaToolLoopStopReason.truncated:
  case LlamaToolLoopStopReason.cancelled:
    print('Stopped (${result.stopReason.name}): ${result.pendingToolCalls}');
}
await engine.dispose();
```

Each round collects a reply. When it calls tools, `sendWithTools` runs the
calls concurrently and adds one tool message per call, in call order, with a
`LlamaToolResultContent` carrying the call's `id` and `name`; the next round
continues the turn without a new user message. `completeWithTools(parts)`
does the same for multimodal parts, and `completeWithTools(const [])`
continues the current turn.

- **No handler:** a call to a tool without a `handler` runs `onToolCall`.
  Without `onToolCall`, the loop stops before running any call of that reply,
  with `unhandledToolCalls`; `result.pendingToolCalls` lists them. Add a tool
  message per call with `session.addMessage(...)`, then call
  `completeWithTools(const [], tools: ...)` to continue. Answer every call,
  even to decline it: until then the history ends with the calls, and
  templates such as Ministral 3's reject a new user turn.
- **Errors:** an exception from a tool, a call to an unknown tool name, or
  arguments that are not a JSON object become the tool result
  `{'error': message}`, so the model can recover. That puts the exception's
  text into the prompt and the session history; pass `onToolError` to choose
  the result, for example to redact secrets, or rethrow from it to fail the
  loop.
- **Bounds:** after `maxRounds` tool rounds, further calls are returned
  unrun with `maxRounds`. Calls proposed from a prompt that did not fit the
  context budget (`session.lastRequestFitContext == false`) are not run
  (`contextExceeded`). A reply cut off at `GenerationParams.maxTokens` or the
  end of the context (`finishReason` `length`) stops the loop with
  `truncated`, without running its calls: its text may be an unfinished
  tool call or thinking, not an answer. A reported limit takes precedence over
  any parsed calls: even complete calls before a partial second parallel call
  are withheld, so `result.pendingToolCalls` is empty for that reply.
  `result.completion` keeps its text and thinking; raise `maxTokens` and send
  the turn again. The whole turn is rolled back, including earlier tool
  rounds; effects of tools that already ran cannot be undone.
- **Cancel:** `engine.cancelGeneration()`, model unload or replacement, and
  engine disposal stop the loop with `cancelled`.
  Running tools finish first. A partial answer stays as the turn's reply.
  If a reply also reports a generation limit, `cancelled` takes precedence
  and the incomplete turn is rolled back.
- `toolChoice` applies to the first request only, so `ToolChoice.required`
  forces one call and later rounds can answer.

### History after a stop

Every stop leaves the session ready for a new user turn, except
`unhandledToolCalls`, which waits for your tool messages:

| Stop | `session.history` |
| --- | --- |
| `completed` | Keeps the turn, ending with the answer. |
| `cancelled` during the answer | Keeps the turn, ending with the partial answer. A cancel before the answer's first token may keep an empty answer or roll back, depending on timing, backend, template and parser; check `result.rolledBack`. |
| `unhandledToolCalls` | Keeps the turn, ending with the calls to answer. |
| `maxRounds`, `contextExceeded`, `truncated`, other `cancelled` stops, or an error | Rolls the whole turn back, from its user message on. |

A rolled-back turn would otherwise end with unanswered calls or tool results,
which some templates, such as Ministral 3's and Mistral Small 3.2's, cannot
render before a new user turn. `completeWithTools(const [], ...)` continues
the open turn, so its rollback also removes that turn's earlier messages,
including the tool results you added. Messages that other code added during
the loop stay. Older turns that context trimming dropped stay dropped, as
after `create`. A rollback edits the history without calling `addMessage` or
`reset`, so a `ChatSession` subclass that mirrors the history should check
`result.rolledBack`.

`result.rolledBack` tells whether the turn was removed. Tools that ran keep
their side effects: `result.messages` holds every message of the turn,
including their results, and `onMessageAdded` has already reported the ones
the call added. To resume a rolled-back turn, add `result.messages` back,
answer `result.pendingToolCalls`, and call
`completeWithTools(const [], tools: ...)`.

On WebGPU a cancel ends generation with a stream error; the loop still
reports it as `cancelled`.

To start a new chat while the loop runs, call `engine.cancelGeneration()`,
await the loop, then call `session.reset()`: a reset while a reply is
generating can leave that reply in the new chat
([#888](https://github.com/leehack/llamadart/issues/888)).

### Run the calls yourself

To stream each reply or control every call, collect the reply and add the
results yourself:

```dart
final tools = [weatherTool];
final reply = await session.create(
  [const LlamaTextContent('What is the weather in Seoul?')],
  tools: tools,
).collect();
for (final call in reply.toolCalls) {
  session.addMessage(
    LlamaChatMessage.withContent(
      role: LlamaChatRole.tool,
      content: [
        LlamaToolResultContent(
          id: call.id,
          name: call.name,
          result: await weatherTool.invoke(call.arguments),
        ),
      ],
    ),
  );
}
if (reply.toolCalls.isNotEmpty) {
  print(await session.create(const [], tools: tools).text());
} else {
  print(reply.text);
}
```

- Tool calls arrive complete, with JSON `arguments`, in the final chunk, whose
  `chunk.finishReason` is `LlamaFinishReason.toolCalls`. `collect()` returns
  them as `LlamaToolCallContent`s with decoded `arguments` (empty when they
  are not a JSON object; `rawJson` keeps the generated text).
- `ChatSession` stores the assistant's tool calls in its history.
  `session.create(const [])` continues from the tool results without a new
  user turn.
- With `engine.create`, append the collected `completion.message` (a
  `LlamaToolCallContent` per call) and the tool messages to your own list
  before the next call.
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
