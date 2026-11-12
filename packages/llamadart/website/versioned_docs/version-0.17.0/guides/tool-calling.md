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
runtime termination reporting, so that a reply cut off at `maxTokens` or the
context stops the loop as `truncated` without running its calls. Native
LiteRT-LM reports why a reply ended on runtimes whose
`stream_proxy_finish_reason_abi_version` export returns 1: litert-lm-native
`v0.18.0-3` and later, including the default pin. Older native runtimes, and
Web `@litert-lm/core@0.18.0`, which reports no cause
([#919](https://github.com/leehack/llamadart/issues/919)), throw
`LlamaUnsupportedException` before starting the loop or modifying its history, including when resuming a turn or
passing an empty tools list. Plain `ChatSession.create` and
`LlamaEngine.create` remain available there for manually managed completion;
their LiteRT-LM `stop` finish reason does not prove the model reached EOS. Do
not execute calls automatically based on that value or infer truncation from
output length. See [LiteRT-LM termination reporting](../maintainers/runtime-ownership#litert-lm-termination-reporting).

GPT-OSS channel and assistant frames wait for final parsing, including headers
continued from the model's prompt, with or without tools. Ordinary prose streams
normally, and `ToolChoice.auto` allows text without a call.
Its reasoning comes from channel frames; literal `<think>`/`</think>`
text stays literal, including in tool arguments. Gemma 4 preserves visible text
after a tool envelope, including its whitespace, across split token delivery.
Calls still arrive complete in the final chunk.

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
the loop stay. Every message an `addMessage` override stores while the loop
adds a message (including a copy of that message, and messages a listener
adds from inside the override) belongs to the turn: the rollback removes it,
and it is neither in `result.messages` nor reported to `onMessageAdded`. The
one exception is a message the override places before the turn in place of a
message from before the turn that it removed, such as a summary of earlier
turns. Messages from before the turn that the override kept stay, even if it
moved them; those it removed stay removed, as after `create`. A rollback
edits the history without calling `addMessage` or `reset`, so a `ChatSession`
subclass that mirrors the history should check `result.rolledBack`.

A class that `implements ChatSession` is rolled back through `reset` and
`addMessage` instead. If two consecutive `history` reads return different
instances for the same message, the turn's messages are matched by role and
content rather than identity, so an equal message that other code added during
the loop can be removed in place of the turn's own, and a message from before
the turn that an `addMessage` override moves after the message it stores counts
as one it stored, so the rollback removes it; one moved only past earlier
messages of the turn stays. A `history` that returns
copies cached until the next mutation gives the same instances on both reads,
so identity matching applies and the turn is not rolled back.

`result.rolledBack` tells whether the turn was removed. Tools that ran keep
their side effects: `result.messages` holds every message of the turn,
including their results, and `onMessageAdded` has already reported the ones
the call added. To resume a rolled-back turn, add `result.messages` back,
answer `result.pendingToolCalls`, and call
`completeWithTools(const [], tools: ...)`. After `truncated`, raise
`maxTokens` and send the turn again instead: `result.messages` ends with the
partial reply, and templates such as Ministral 3's can reject the next user
turn after it.

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

### Tool-result media

A tool can return images with its result. Return a `LlamaToolOutput` from a
handler or `onToolCall`, or put the parts in `LlamaToolResultContent.content`
yourself:

```dart
final camera = ToolDefinition(
  name: 'take_photo',
  description: 'Takes a photo and returns it.',
  parameters: const [],
  handler: (params) async => LlamaToolOutput(
    output: {'ok': true},
    content: [LlamaImageContent(bytes: await takePhoto())],
  ),
);

if ((await engine.capabilities).toolResultMedia
    .contains(LlamaToolResultMedia.image)) {
  await session.sendWithTools('What is in front of the camera?', tools: [camera]);
}
```

The tool turn holds the result as text (JSON for a non-string result, nothing
for `null`), then each `content` part in order: text parts joined by a
newline, and a media marker at each image, exactly as llama-server renders a
`tool` message whose `content` array has `image_url` parts. Without an image,
templates that read typed content get the parts typed, as llama-server passes
them. `toJson` emits that array shape. Images reach the model in prompt order.

In a manual loop, `ToolDefinition.invoke` returns the handler's
`LlamaToolOutput` as is: pass its `output` as `result` and its `content` as
`content`. A `LlamaToolOutput` `result` throws `LlamaArgumentException`.

Support is a chat-format property:

| Requirement | Supported |
| --- | --- |
| Runtime | Native llama.cpp with a loaded projector that reports vision |
| Chat format | Hermes-style `<tool_call>` templates, smoke-tested on macOS CPU and Metal with Qwen3.5-0.8B weights, a `qwen3vl_merger` projector and the Qwen3-VL template |
| Media | Images with a `path` or `bytes` |

`LlamaEngineCapabilities.toolResultMedia` reports `{image}` when the runtime,
projector and the loaded model's template all qualify. Everything else throws
`LlamaUnsupportedException` before rendering or dispatch, including session
history budgeting:

- other formats, such as Qwen3.5's XML tool format or Gemma 4, even for text
  `content`, and a request that routes to the generic format (a response
  schema with tools);
- WebGPU, LiteRT-LM and other runtimes, or no vision projector;
- audio or video parts, and URL-only images (the URL is not fetched or echoed;
  resolve it in the app and pass bytes or a path);
- a template that renders a tool result's marker other than once.

Nested tool calls, tool results or thinking parts throw
`LlamaArgumentException`. Image/audio parts beside `LlamaToolResultContent`,
or on a tool-role message, still throw
([#1445](https://github.com/leehack/llamadart/issues/1445)); put them in
`content` instead.

For an OpenAI-compatible reference, see
[OpenAI-compatible server](../examples/llamadart-server).

## Import a JSON Schema

Use `ToolDefinition.fromJsonSchema` when another library already provides the
input schema. The factory owns a deep copy; `toJsonSchema()` returns a fresh
copy. Its `parameters` list is empty, so integrations must read `toJsonSchema()`.

```dart
final ToolDefinition searchTool = ToolDefinition.fromJsonSchema(
  name: 'search',
  description: 'Search selected collections',
  schema: {
    'type': 'object',
    'properties': {
      'query': {'type': 'string', 'minLength': 1, 'maxLength': 2000},
      'collections': {
        'type': 'array',
        'items': {'type': 'string'},
        'minItems': 1,
      },
    },
    'required': ['query', 'collections'],
    'additionalProperties': false,
  },
  handler: (params) async => {
    'query': params.getRequiredString('query'),
    'collections': params.getList('collections'),
  },
);
```

The initial subset supports scalar types, nested objects and arrays, scalar
`enum`/`const`, nullable type lists, `anyOf`, string length and array item
bounds, and boolean or schema-valued `additionalProperties`. The root must be
an object. Missing `additionalProperties` means `true`; the existing
`ToolParam` constructor keeps its closed-property behavior.

References (local and remote), patterns, numeric bounds, `oneOf`/`allOf`, tuple
arrays, container literals and unsupported constraint combinations throw
`LlamaUnsupportedException`. Malformed schemas throw `LlamaArgumentException`.
This API supports a bounded subset of JSON Schema.
Nonempty annotation-only untyped property schemas accept any JSON value;
annotations and unknown `x-*` metadata are preserved. For empty tool-property schemas, use an explicit `type`; response schemas
keep their existing `{}` object grammar. Response schemas share the rejection of unsupported constraints
and bounds above 2000, but support a wider subset (for example local references
and compiled patterns). Decoded model tool arguments are limited to 128 container
levels in final and partial parsing; deeper values throw `LlamaInferenceException`.

`toJsonSchema()` and `toJson()` return the validated schema with object
defaults made explicit: every object schema includes `properties` (empty when
absent) and `additionalProperties` (`true` when absent).

### Limits

Imported schemas may come from untrusted sources, so the factory bounds them
and throws `LlamaUnsupportedException`, naming the keyword or path and the
limit, when a schema exceeds one:

| Limit | Value |
| --- | --- |
| JSON nesting of the schema document, including `default`/`examples` values | 128 levels |
| Subschema nesting | 32 levels |
| Subschemas plus undeclared `required` names per tool | 1024 |
| `anyOf` alternatives | 64 |
| `enum` values | 1024 |
| Property name length | 128 characters |
| `minLength`, `maxLength`, `minItems`, `maxItems` | 2000 (inclusive) |
| Generated grammar per tool | 262,144 characters |

The bound limit is llama.cpp's grammar repetition limit
(`MAX_REPETITION_THRESHOLD`, 2000): the grammar parser of the llama.cpp release
the native runtime ships (upstream `v0.7.0`) rejects a repetition count above
2000 and silently drops a larger upper bound. The schema factory rejects bounds
above 2000 so those constraints cannot be lost.

The grammar for all tools in a request is checked again before generation on
grammar-capable backends. It throws `LlamaUnsupportedException` when llama.cpp
would refuse to load it: a repeated group whose symbols times its repetition
count exceed 2000. Hermes, for example, puts every schema tool inside one
repeated group, so about 2000 schema tools exceed it.

| Selected tool format | Canonical schema support |
| --- | --- |
| Generic JSON fallback, Hermes, Mistral Nemo JSON | The subset above |
| GLM-4.5, Laguna, Hunyuan V3 | Closed root objects with scalar properties; GLM/Laguna also support string enums |
| Other formats | Rejected before generation |

Active schema tools require grammar-constrained decoding. Native llama.cpp
supports it; WebGPU works only when the selected grammar starts at the first
token (usually `ToolChoice.required`). Lazy auto grammars and LiteRT-LM are
rejected. `ToolChoice.none` can retain declarations for replay without enabling
calls. Final parsed calls and direct `invoke` arguments are validated before
handlers run. A schema constrains the input shape; the app still controls
tool permissions and side effects.

Active schema tools cannot be combined with `responseFormat`, which would
replace the tool grammar. Use separate requests. Undeclared calls and malformed
tool envelopes fail the turn before handlers run. In an open object, an extra
property cannot reuse a declared or required property name, so those
properties keep their own schema. Escaped spellings of a declared name (such as `\u0063ity`)
are rejected too: where a declared name continues with a character, an extra
name cannot spell that character as a `\u` escape. Where a declared name needs
a JSON escape (such as `a"b`), the grammar also rejects extra names with a
different escape at that position (such as `a\nb`). Open objects whose
declared names would add more than 65,536 characters of exclusion rules to one
grammar accept any extra name instead; for tools, final validation still checks
declared properties.

In Hermes `auto` mode, a JSON object with a `name` key outside a
`<tool_call>`, `<tool>` or `<function…>` envelope stays answer text unless it
is a complete call to a declared tool, which is then validated like any other
call. A reply cut off by `maxTokens` or the context size finishes with
`length` (tool loops stop with `truncated`) rather than failing as a malformed
call.

When a Hermes template forces reasoning open (such as QwQ), the
`ToolChoice.required` grammar accepts reasoning closed by `</think>` before the
calls, for schema and `ToolParam` tools.

`required` may name a property that `properties` does not declare: the
grammar requires that key, with a value matching `additionalProperties` (any
JSON value when it is `true`). In a closed object (`additionalProperties:
false`) such a name throws `LlamaArgumentException`, because no object can
satisfy it. Response schemas still require `required` to name declared
properties.

On WebGPU, an automatic tool loop changes to `auto` after its first tool round.
Hermes and Mistral then need lazy grammars, so their schema-backed automatic
loops cannot finish on WebGPU. Use the generic non-lazy JSON format there, or
manage a single required-tool request and its follow-up explicitly.

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

### Tool results on templates without a tool role

Gemma 2/3/3n and older Mistral templates reject the `tool` role. When such a
template fails to render a request with tool results, and accepts a tool
result as a user message, llamadart renders the request again with each run
of consecutive results as one user turn, such as:

```json
{
  "tool_response": {
    "tool": "get_weather",
    "content": "{\"temperature_c\":21}",
    "tool_call_id": "call_1"
  }
}
```

The earlier tool calls appear as JSON in the model turn, with or without
tools on the follow-up request. This restores the tool-result polyfill of
llama.cpp's former minja engine (for example `b6000`); the tested `b10549`
fails the same request with the template's role-alternation error. A request
that the template renders as given, and any template that renders the `tool`
role itself, is unchanged. On the retry, a user message immediately after the
results is appended to their user turn with a newline, so the template still
receives alternating roles. For example, `user → assistant(tool call) →
tool(result) → user("And Rome?")` becomes `user → assistant →
user(result JSON + "\nAnd Rome?")`. Only the render input changes; the app's
history stays intact. This follow-up case also fails in pinned upstream
`b10549` ([#1118](https://github.com/leehack/llamadart/issues/1118)).
A later assistant turn still separates tool rounds, and unrelated consecutive
user messages retain the template's usual validation.

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
