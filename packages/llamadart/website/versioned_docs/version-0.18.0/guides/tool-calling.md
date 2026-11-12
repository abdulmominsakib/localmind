---
title: Tool calling with local models
sidebar_label: Tool calling
description: Define tools with ToolDefinition, control them with ToolChoice, and run a template-aware tool-calling loop with a local model.
---

Pass `ToolDefinition`s to `engine.create` or `ChatSession.create`. The model's
chat template renders them, and the parser returns the model's calls as
`chunk.toolCalls`. `session.sendWithTools` runs the calls with each tool's
`handler` until the model answers; `create` and `engine.create` only return
the calls, and your code runs them. Runtime-specific limits are under
[Runtime notes](#runtime-notes).

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
including the tool results you added. Messages that other code added during the loop stay, while messages an
`addMessage` override stores for the turn go with it. A rollback edits the
history without calling `addMessage` or `reset`, so a `ChatSession` subclass
that mirrors the history should check `result.rolledBack`; a class that only
`implements ChatSession` is rolled back through `reset` and `addMessage`.
The matching rules are in the
[`completeWithTools` API docs](https://pub.dev/documentation/llamadart/latest/llamadart/ChatSessionToolLoopExtension/completeWithTools.html).

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
await the loop, then call `session.reset()`: a late reply from the
cancelled turn is not added to the new chat.

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

For LFM2/LFM2.5, a quoted `<|tool_call_end|>` inside an argument is literal
argument data. Parsed tool calls preserve it until the actual envelope closes,
including when the response streams in small chunks.

Python-style LFM2 calls such as `[set_flag(enabled=True)]` use each declared
`ToolParam` type: booleans and null become JSON values, object/array parameters
retain their named position, and a declared zero-argument call yields `{}`.
For a string parameter, `value=False` remains the string `"False"`; copied
backslashes in Python-style string arguments remain literal. Ambiguous copied
text and escaped text are not globally unescaped. The existing JSON call form
keeps JSON string decoding. For a tool with one required plain string argument, auto grammar also preserves
parser-supported bare text and balanced object/list spellings as strings. Copied
path-like values may retain a trailing backslash or an unmatched opening quote,
in a singleton list without a terminal comma. Ambiguous copied spellings remain
non-executable; the grammar does not reinterpret them as a different value.
Other declarations and list forms retain their declared types and strict quotes.
An auto reply closed with a foreign XML tag such as `</function_call>` can remain
raw diagnostic text instead of being forced into an executable tool envelope.
This diagnostic form requires a schema-valid call prefix without a trailing
list comma, excludes `<` from its argument bytes, and excludes special markers
from its tail. It never yields an executable call. Required/force-JSON and `none` behavior is unchanged.
For that one-string form, a direct string cannot continue a completed copied-path
call as argument data. Such values use the existing Python wrapper
`save_note(arguments={"text":"..."})`, whose JSON string encoding preserves the
value. The generation grammar requires exactly the declared inner property and
its type. If the declared property is named `arguments`, the envelope uses
`parameters` instead; parsed calls contain the declared argument.

Declare every argument with the correct type. This parser change does not add
canonical `ToolDefinition.fromJsonSchema` generation support for LFM2: the
existing capability gate still rejects it. Required calls retain the existing
JSON-list grammar. Tool markers inside recognized reasoning remain `thinking`
text and never become executable calls. Calls after the thought closes still
work, and literal `<think>`/`</think>` inside complete tool arguments stay data.

An explicit `parallelToolCalls: true` reaches the supported format's tool
grammar even when template probes do not recognize parallel assistant history.
The capability report still describes that history support; the flag does not
add an unsupported format or backend protocol. This corrects
[#1713](https://github.com/leehack/llamadart/issues/1713), while the reasoning
boundary is tracked by [#1714](https://github.com/leehack/llamadart/issues/1714).
LFM2/LFM2.5 `ToolChoice.auto` uses a schema-directed Python-call grammar on
native llama.cpp and supported Web bridge runtimes. It waits for a tool-start marker outside reasoning, allowing
ordinary text before a call, then enforces declared names, required and unique
arguments, value types, and the explicit parallel flag. Prompt tokens seed only
the penalty sampler, preserving sampling before activation without feeding the
prompt to the grammar. Required and force-JSON requests keep their JSON-list
grammar; `none` adds no tool grammar. The auto grammar permits a trailing list
comma and bounds formatting whitespace outside quoted strings, preventing
separator loops: eight characters per separator, or up to sixteen in an empty
call or container where two separators meet. Whitespace inside quoted argument
values, enum literals and quoted object keys is unchanged.

Use legacy `ToolParam` declarations for this path. Grammar expansion is bounded
to 4096 argument states; oversized declarations, arrays without a declared item
type, and string enum values containing both quote styles or ending in an odd
number of backslashes throw
`LlamaUnsupportedException`. Copied-string backslashes retain the parser policy
above. Grammar constrains structure and types, not the accuracy of copied text.

The new auto path requires both lazy grammar and prompt penalties with grammar.
Web requires assets v0.1.82+ whose loaded core reports both `lazyGrammar` and
`penaltyPromptTokensWithGrammar`. Missing, false or non-boolean reports reject
before inference. This scoped Web route is text-only; ordinary grammar requests
keep their previous prompt-penalty behavior. A custom backend must implement
`BackendPromptPenaltyGeneration` from `package:llamadart/backend.dart`, report
its loaded runtime's truthful capability, and implement the scoped generation
route; interface presence alone is insufficient. Optional native chat cannot
bypass this route; a backend requiring structured chat input rejects the
combination before generation. Nested object keys support quoted and
backslashed names through parser-compatible literals. Existing generic auto fallback
is separate. See [#1715](https://github.com/leehack/llamadart/issues/1715);
length-truncated diagnostics are described below.

In LFM2/LFM2.5 JSON tool calls (`ToolChoice.required`, or a prompt carrying
LFM2's `Force JSON schema.` marker), string arguments keep a double quote the
model left unescaped when no closing quote could stand there, so
`print(f"hi {name}")` arrives whole. A quote followed by `,`, `}` or `]`
(except `}"`) still ends the string
([#1609](https://github.com/leehack/llamadart/issues/1609)).

When a backend reports a length cutoff inside an LFM tool envelope,
`chunk.partialToolCalls` and the collected `reply.partialToolCalls` preserve
recognized named calls as raw diagnostic records. Their `function.arguments`
is the exact generated argument text: Python keyword arguments or JSON value
text, including unfinished containers, quotes and escapes. Complete prefixes
inside that unfinished list keep their order too; this does not make them
executable. A recognized argument opener with zero emitted argument bytes
preserves the empty raw string; it never fabricates `{}` or a closing token.
A name without an argument opening produces no diagnostic call. Unknown names
may remain in diagnostics; this does not declare or validate a tool.
The unfinished envelope stays out of answer text, while preceding answer and
reasoning content remain available. All executable calls are still withheld at
length, including complete calls from an earlier closed envelope.

Never execute diagnostic records, decode them as typed tool arguments or append
them as tool calls to history. `completion.message`, `ChatSession` history and
automatic tool loops exclude them. Natural EOF and cancellation retain their
existing parsing behavior and expose no `partialToolCalls`; diagnostics never
establish why generation ended. `ToolChoice.none` and parsing-disabled output
stay literal. In particular, LiteRT-LM Web still has the unknown-finish-cause
restriction tracked by [#919](https://github.com/leehack/llamadart/issues/919).

```dart
final reply = await engine.complete(messages, tools: tools);
for (final diagnostic in reply.partialToolCalls) {
  print('${diagnostic.function?.name}: ${diagnostic.function?.arguments}');
}
// Run only reply.toolCalls through the normal tool workflow.
```

Solar Open replies may contain several content-channel segments. Parsed and
streamed completions preserve each accepted segment and the whitespace between
them, while removing the channel framing.

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
or on a tool-role message, throw; put them in `content` instead.

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
the native runtime ships (upstream `v0.8.0`) rejects a repetition count above
2000 and silently drops a larger upper bound. The schema factory rejects bounds
above 2000 so those constraints cannot be lost.

The grammar for all tools in a request is checked again before generation on
runtimes that support grammar constraints. It throws `LlamaUnsupportedException` when llama.cpp
would refuse to load it: a repeated group whose symbols times its repetition
count exceed 2000. Hermes, for example, puts every schema tool inside one
repeated group, so about 2000 schema tools exceed it.

The llama.cpp `v0.8.0` grammar parser also refuses a grammar nested or chained
more than 256 levels deep. Generated schema grammars keep a list of up to 1023
optional properties under that, but a `$ref` alias chain of 255 or more
levels, or an object with more than about 7000 optional properties, still
exceeds it and fails to load. A grammar above it makes generation throw
`LlamaInferenceException`, on Web as on native. On Web, a schema of about 7000
or more properties or a grammar of 1 MB or more instead traps the runtime, and
later generations can fail until the page reloads; keep tool schemas well below
that.

| Selected tool format | Canonical schema support |
| --- | --- |
| Generic JSON fallback, Hermes, Mistral Nemo JSON | The subset above |
| GLM-4.5, Laguna, Hunyuan V3 | Closed root objects with scalar properties; GLM/Laguna also support string enums |
| Other formats | Rejected before generation |

Active schema tools require grammar-constrained decoding. Native llama.cpp
supports it. LiteRT-LM is rejected, and WebGPU is limited as described under
[WebGPU](#webgpu). `ToolChoice.none` can retain declarations for replay
without enabling calls. Final parsed calls and direct `invoke` arguments are
validated before handlers run. A schema constrains the input shape; the app still controls
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
history stays intact. This follow-up case also fails in llama.cpp's `b10549`
template set ([#1118](https://github.com/leehack/llamadart/issues/1118)).
A later assistant turn still separates tool rounds, and unrelated consecutive
user messages retain the template's usual validation.

## Tool choice semantics

- `ToolChoice.none`: disable tool calls for that request.
- `ToolChoice.auto`: model decides whether to call tools.
- `ToolChoice.required`: model must emit tool calls.

### WebGPU

On Web with WebGPU (llama.cpp), lazy tool-call grammars require the loaded
bridge core to report `lazyGrammar` (`v0.1.75+` assets). Check
`(await engine.capabilities).supportsLazyGrammar`. Supported runtimes retain
the grammar and triggers for `ToolChoice.auto`, including schema-backed tool
loops, and keep the prompt outside repetition/presence penalties as native does.

On older or incompatible cores, `ToolChoice.auto` keeps best-effort parsing
without the lazy template grammar. Explicit `grammarLazy`, custom grammar roots,
and schema-tool requests needing a lazy grammar throw
`LlamaUnsupportedException`. Non-lazy required-tool grammars remain supported.
This capability does not establish LFM2 auto Python-call grammar enforcement;
that separate template contract is tracked in
[#1715](https://github.com/leehack/llamadart/issues/1715).

Parser details, such as call validation against the supplied tools, are in
[Template engine internals](./template-engine-internals#tool-call-parsing).

## Runtime notes

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
output length.

GPT-OSS channel and assistant frames wait for final parsing, including headers
continued from the model's prompt, with or without tools. Ordinary prose streams
normally, and `ToolChoice.auto` allows text without a call.
Its reasoning comes from channel frames; literal `<think>`/`</think>`
text stays literal, including in tool arguments. Gemma 4 preserves visible text
after a tool envelope, including its whitespace, across split token delivery.
Calls still arrive complete in the final chunk.
