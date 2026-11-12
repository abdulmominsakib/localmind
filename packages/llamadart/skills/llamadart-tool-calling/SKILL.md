---
name: llamadart-tool-calling
description: >-
  Use when adding tool or function calling to a llamadart app: defining
  ToolDefinition and ToolParam, running the tool-call loop with
  ChatSession.sendWithTools or by hand, choosing ToolChoice, or debugging
  models that ignore or malform tool calls.
---

# Tool calling with llamadart

## Guidelines

- At a backend-reported length cutoff, LFM `chunk.partialToolCalls` and collected
  `reply.partialToolCalls` hold raw named-call diagnostics from an unfinished
  envelope, in order. `function.arguments` preserves exact Python/JSON text,
  including unfinished syntax or an empty raw string after an argument opener.
  Unknown names remain diagnostic only; no `{}` or closing syntax is invented.
  Never decode it as typed arguments, execute it
  or append it to history. `completion.message`, sessions and automatic loops
  exclude diagnostics. All executable calls remain withheld at length.
  Natural EOF/cancellation expose no diagnostics and retain existing policy;
  none/parsing-disabled output stays literal.

- Prefer `session.sendWithTools(text, tools: ..., maxRounds: ...)`: it runs
  each call's `ToolDefinition.handler` (concurrently for parallel calls),
  adds a `LlamaChatRole.tool` message per call with the call's id, and
  repeats until the model answers. Check `result.stopReason`
  (`LlamaToolLoopStopReason`): only `completed` means a final answer;
  `maxRounds`, `unhandledToolCalls`, `contextExceeded`, `truncated` and
  `cancelled` leave `result.pendingToolCalls` unrun. `truncated` means a
  reply hit `GenerationParams.maxTokens` or the context end; its text may be
  partial tool-call markup. A backend-reported limit withholds the whole reply's
  call set, including complete calls before a partial parallel call, so its
  `pendingToolCalls` is empty and no calls from that reply run. Raise `maxTokens`
  and retry. `completeWithTools(parts)` takes media
  parts; `completeWithTools(const [])` continues the turn.
- After a stop, the history is ready for a new user turn, except after
  `unhandledToolCalls`. `maxRounds`, `contextExceeded`, `truncated`, a
  cancel that left no answer, and any thrown error roll the whole turn back from its
  user message, because templates such as Ministral 3's reject a user turn
  after unanswered calls or tool results. For `completeWithTools(const [])`
  that includes the open turn's earlier messages, such as your tool results.
  Turns trimmed for context are not restored. Check `result.rolledBack` (a
  rollback does not call `addMessage` or `reset`, except on a class that
  `implements ChatSession`, which it rebuilds through them, matching by
  content when two consecutive `history` reads return different instances);
  `result.messages` keeps the turn's messages, including results of tools that
  ran. To resume, add them back, answer `pendingToolCalls` and call
  `completeWithTools(const [])`.
  A cancel during the answer keeps the partial answer, on WebGPU too; a
  cancel before any reply content may keep an empty answer or roll back;
  empty terminal chunks are not
  an answer. A cancel that also reports a generation limit rolls back and
  keeps `cancelled` as its stop reason. Check `result.rolledBack`. For a new chat, call
  `engine.cancelGeneration()` and `session.reset()`: a late reply from the
  old turn is not added to the reset history. Await the old loop before
  starting another generation on the same engine.
- `handler` is optional. Leave it out for a tool the app runs itself (user
  approval, remote execution): give `onToolCall`, or let the loop stop with
  `unhandledToolCalls`, add a result for every pending call with
  `session.addMessage(...)` (even to decline it) and call
  `completeWithTools(const [], tools: ...)`. The turn stays open until then.
- In the loop, a throwing tool, an unknown tool name or non-object arguments
  become the tool result `{'error': message}` so the model can recover. That
  puts the exception text into the prompt and history: pass `onToolError` to
  shape or redact that result, or rethrow from it to fail the loop.
  `toolChoice` applies only to the first request.
- `ChatSession.create` and `engine.create` only return calls in
  `chunk.toolCalls`; use them by hand to stream replies or to run tools
  outside the loop.
- Tool calls arrive complete, with JSON-encoded `arguments`, in the final
  chunk; its `chunk.finishReason` is `LlamaFinishReason.toolCalls`. With
  Hermes-detected templates (Hermes 2 Pro/3, Qwen2.5, Qwen3 and QwQ),
  cancelling inside an unfinished `<tool_call>` keeps preceding answer text
  without raw envelope markup. If no output preceded it, `ChatSession.create`
  throws `LlamaStateException` ("Generation was cancelled before any output.")
  and rolls back the turn. Natural EOS, caller stops and token limits retain
  their existing parsing behavior. Collect
  the whole stream with `collect()` (or use `engine.complete` /
  `session.send`): `LlamaCompletion.toolCalls` holds `LlamaToolCallContent`
  entries with decoded `arguments` (empty when they are not a JSON object;
  `rawJson` keeps the text).
- GPT-OSS channel and assistant frames wait for final parsing, including headers
  continued from the model's prompt, with or without tools. Ordinary prose
  streams normally, and `ToolChoice.auto` still allows text without a call.
  Gemma 4 keeps visible
  text after a tool envelope, including its whitespace; the envelope itself
  stays out of content even across split tokens. GPT-OSS reasoning comes from
  channel frames; literal `<think>`/`</think>` text stays literal, including in
  tool arguments.
- By hand, invoke through `tool.invoke(call.arguments)`, which wraps the
  arguments in `ToolParams` for typed access; schema-factory tools validate them, and
  throws `LlamaStateException` for a tool without a handler. Read required
  arguments with `getRequired*`, which throws when one is missing. Catch errors
  and return them to the model as the tool result rather than crashing the
  loop.
- Return results with a `LlamaChatRole.tool` message containing
  `LlamaToolResultContent(id: call.id, name: ..., result: ...)`. `result` can
  be any JSON-compatible value.
- Do not attach image/audio parts to tool-role messages or alongside
  `LlamaToolResultContent`, even under a user/assistant role. `create` and
  `chatTemplate` throw `LlamaUnsupportedException` before rendering or
  dispatch, including session history budgeting.
- To return an image from a tool, check
  `(await engine.capabilities).toolResultMedia` for
  `LlamaToolResultMedia.image`, then return
  `LlamaToolOutput(output: {...}, content: [LlamaImageContent(bytes: ...)])`
  from the handler, or set `LlamaToolResultContent(..., content: [...])`.
  In a manual loop, `invoke` returns that `LlamaToolOutput`: pass its
  `output` as `result` and its `content` as `content`, never the output
  itself as `result` (that throws `LlamaArgumentException`).
  Only native llama.cpp with a vision projector and a Hermes-style template
  (smoke-tested on macOS CPU and Metal with Qwen3.5-0.8B weights, a
  `qwen3vl_merger` projector and the Qwen3-VL template) takes it; other formats, runtimes, audio, video and
  URL-only images throw `LlamaUnsupportedException`.
- With `ChatSession`, the assistant's tool calls are already in history; add
  the tool results with `session.addMessage(...)` and continue with
  `session.create(const [])`. With `engine.create`, append the collected
  `completion.message` (it carries one `LlamaToolCallContent` per call) and
  the tool messages to your own list.
  Keep its `LlamaThinkingContent` parts too: LFM2/LFM2.5 templates can replay
  assistant reasoning alongside calls, applying their own history-retention policy.
- Read arguments from parsed tool-call parts. For LFM2/LFM2.5, quoted
  `<|tool_call_end|>` text inside an argument is literal data; preserve it when
  invoking tools and replaying their results. Python-style LFM2 argument values
  follow their declared `ToolParam` types: `True`/`None` become boolean/null
  only for those types, while `False` on a string parameter stays `"False"`.
  Named object/array arguments and zero-argument calls are supported. Keep
  copied backslashes literal; ambiguous Python-style strings are not globally
  unescaped. This does not enable canonical `fromJsonSchema` generation on
  LFM2. In LFM2 JSON tool calls (`ToolChoice.required` or a
  `Force JSON schema.` prompt), string arguments keep a double quote
  the model left unescaped where no closing quote could stand; a quote before
  `,`, `}` or `]` still ends the string. Auto grammar preserves copied
  bare text and balanced object/list spellings as strings only for one required
  plain string argument. Copied path-like values may retain a trailing backslash
  or an unmatched opening quote, in a singleton list without a terminal comma.
  Ambiguous spellings stay non-executable; other declarations retain their types
  and strict quote boundaries. A schema-valid auto prefix closed with a foreign
  XML tag can remain raw diagnostic text with no executable calls. A trailing
  list comma cannot lead into this diagnostic form. Its argument bytes exclude
  `<` and its tail excludes special markers; never execute these diagnostics. Required/force-JSON and `none` behavior is unchanged.
  For the one-string form, values that would continue a completed copied-path
  call use the existing Python `tool(arguments={"field":"..."})` envelope with
  JSON string escaping. The inner object follows the declared single-field
  schema. A declared `arguments` field uses a `parameters` envelope instead.
  Read the declared argument from the parsed tool call.
- Native llama.cpp enforces LFM2/LFM2.5 auto Python calls with a lazy schema
  grammar after a tool-start marker outside reasoning. Keep legacy `ToolParam`
  declarations typed; required/force-JSON requests retain their JSON grammar,
  and `none` adds no tool grammar. Web text-only requests require assets
  v0.1.82+ and loaded-core `lazyGrammar`/`penaltyPromptTokensWithGrammar` probes;
  older runtimes or media inputs throw before inference.
  Custom backends need the truthful `BackendPromptPenaltyGeneration`
  capability and route from `package:llamadart/backend.dart`; implementing the
  interface with a false getter still rejects. Optional native chat cannot
  bypass this route; mandatory structured-chat backends reject it. Argument expansion is bounded
  to 4096 states; unsupported schemas throw rather than silently dropping grammar.
  Auto enums ending in an odd number of backslashes throw unsupported before
  inference; use a plain string parameter for copied paths.
  Auto grammar allows a trailing list comma and bounds formatting whitespace
  outside quoted strings: eight characters per separator, up to sixteen in an
  empty call or container. Quoted argument values, enum literals and quoted
  object keys keep their whitespace.
- LFM2/LFM2.5 tool markers inside reasoning remain `thinking` text and never
  produce executable calls. Calls after the thought closes still work; literal
  `<think>`/`</think>` inside complete tool arguments remain argument data.
- Set `parallelToolCalls: true` to allow the supported format's parallel tool
  grammar. Template capability reports describe history rendering and do not
  silently override that explicit request; the flag cannot add a protocol the
  format or backend does not implement.
- Qwen3-Coder XML replies (Qwen3-Coder, Qwen3.5, StepFun3.5-Flash, Nemotron 3
  Nano) parse as in llama-server: content ends at the first `<tool_call>`,
  only the first call counts without `parallelToolCalls`, and an invalid call
  or text after the calls is dropped, not returned as content. A call needs a
  line break after each tag and around each value, and its required
  arguments before its optional ones. With `ToolChoice.required`, a
  thought and text may precede the calls, so leave room in `maxTokens`, and
  the Qwen3-Coder template's first call may leave out `<tool_call>` and start
  at `<function=name>`. With `ToolChoice.auto` that tag is text.
- Ling 3.0 (Bailing V3) replies parse as in llama-server: a `<tool_call>` ends
  a forced-open thought, a call is `<tool_call>name` with `<arg_key>` and
  `<arg_value>` pairs (a string value up to `</arg_value>`, any other JSON), and
  a Hermes JSON call stays content. With `ToolChoice.required`, a thought and
  text may precede the calls, so leave room in `maxTokens`.
- Consume all parsed Solar Open content-channel segments, preserving the
  whitespace between them. Parsed and streamed completions remove channel
  framing while retaining the accepted content.
- Always cap the number of tool rounds (`maxRounds`, default 5); a model can
  call tools forever.
- `ToolChoice.auto` lets the model decide, `ToolChoice.required` forces a call
  (unless `maxTokens` runs out first, where a thought or text may precede it)
  and `ToolChoice.none` disables tools for one request. With Hermes templates
  that open reasoning in the prompt (such as QwQ), a required call follows the
  model's closed `</think>` reasoning, which streams as `chunk.thinking`.
- Tool quality depends on the model and its template. Templates without a
  native tool format use a generic JSON fallback that constrains the output
  shape but does not guarantee the right tool or arguments. If calls look
  wrong, inspect `engine.chatTemplate(...)` to see whether tool definitions
  reach the prompt, and describe the tools in the system prompt if not. To
  replace a broken GGUF template, load with `ModelParams(chatTemplate: ...)`;
  prompts and tool-call parsing then both follow that template. On a native
  LiteRT-LM Qwen 3 text bundle the runtime renders that template, and from
  `v0.18.0` hands it each message's `content` as a list of
  `{"type": "text", "text": ...}` parts, so read both the string and the
  list shape. Other native `.litertlm` bundles render their embedded
  template, which can leave tools out of the prompt (Qwen3.5 does);
  `engine.chatTemplate(...)` shows a Dart render of it, while parsing keeps
  the file-name template (`llamadart.chat_template.parsing` in
  `getMetadata()`).
- Gemma 2/3/3n and legacy Mistral templates retry a failed tool-result render
  with consecutive results as one user turn. A user message immediately after
  those results is appended with a newline on that retry. Stored history and
  successful first renders stay unchanged; unrelated consecutive user turns
  still follow the template's validation.
- Render errors name the built-in ChatML fallback when model template metadata
  is absent or empty. PEG parse errors use `peg-simple`, `peg-native`, or the
  historical `peg-constructed` name retained for Qwen3 Coder XML.
- A recursive chat template (for example Command R+ or
  Hermes-2-Pro-Llama-3-8B `tool_use` with a null-typed parameter) fails with
  `LlamaInferenceException` naming the selected template on the Dart VM and
  JavaScript. On dart2wasm, stack overflow cannot be caught and may trap or
  hang. Replace the broken template or use a compatible tool schema;
  rendering does not repair upstream templates.
- Automatic `sendWithTools` and `completeWithTools` loops need a runtime that
  reports why generation stopped; a reply cut off at `maxTokens` returns
  `LlamaToolLoopStopReason.truncated` and runs no tools. Native LiteRT-LM
  reports it from litert-lm-native `v0.18.0-3` (the default pin does).
  LiteRT-LM Web infers it from `@litert-lm/core@0.19.0` token counts through
  `LlamaBackend.withTextHistory()` once a load probe passes; a reply ending
  exactly at `maxTokens` also counts as truncated, so leave headroom. Older
  native runtimes, Web runtimes that fail the probe and the default Web
  constructors throw `LlamaUnsupportedException` before generation or history
  mutation; manual
  `ChatSession.create`/`LlamaEngine.create` still work there, but their `stop`
  does not prove EOS. Do not infer truncation from output length or run tool
  handlers automatically from an unverified terminal result.
- Runtime limits: LiteRT-LM has no grammar enforcement, LiteRT-LM on web
  forwards tools only through `LlamaBackend.withTextHistory()`
  (`ToolChoice.required`, `parallelToolCalls` and tool-result `content`
  throw), and WebGPU `ToolChoice.auto` parses calls best-effort.
  `(await engine.capabilities).supportsToolCalling`,
  `supportsStructuredOutput` and `supportsLazyGrammar` report these per
  loaded model. Test tool flows on every target runtime.

## Existing JSON schemas

Use `ToolDefinition.fromJsonSchema(name: ..., description: ..., schema: ...,
handler: ...)` for imported schemas; do not flatten them to `ToolParam`s. The
factory owns a deep copy and exposes fresh canonical copies through
`toJsonSchema()`; `parameters` is empty. The root must be an object. Missing
`additionalProperties` means true; legacy helper tools retain closed behavior.
The supported subset includes nested objects/arrays, scalar enum/const,
nullable type lists, anyOf and length/item bounds. `required` may name an
undeclared property of an open object; its value must match
`additionalProperties`, and a closed object rejects such a name. Nonempty annotation-only
untyped properties accept any JSON value; annotations and `x-*` metadata are
preserved. Decoded tool-call arguments deeper than 128 containers throw
`LlamaInferenceException` during final and partial parsing. References, patterns,
numeric bounds, oneOf/allOf and other unsupported constraints fail explicitly.
Generic JSON, Hermes and Mistral Nemo JSON support this subset; GLM/Laguna
and Hunyuan require closed scalar objects (GLM/Laguna also allow string enums).
Other formats and runtimes without an active tool grammar are rejected.
WebGPU lazy auto grammars require `supportsLazyGrammar` from the loaded
bridge core. On older cores, use a supported non-lazy required-tool
format. LiteRT-LM is unsupported. Final parsed calls and direct invocation
are validated. Schemas past the guide's size limits (for example 32 nesting
levels, 64 `anyOf` alternatives, or length/item bounds above 2000) throw
`LlamaUnsupportedException`. See the guide's "Import a JSON Schema" section
for an example.

## Examples

Define a tool and run a bounded tool-call loop with `ChatSession`:

```dart
import 'package:llamadart/llamadart.dart';

final ToolDefinition weatherTool = ToolDefinition(
  name: 'get_weather',
  description: 'Get current weather for a city',
  parameters: [
    ToolParam.string('city', description: 'City name', required: true),
    ToolParam.enumType('unit', values: ['celsius', 'fahrenheit']),
  ],
  handler: (params) async {
    final String city = params.getRequiredString('city');
    final String unit = params.getString('unit') ?? 'celsius';
    return {'city': city, 'temperature': 22, 'unit': unit};
  },
);

Future<String?> runTools(LlamaEngine engine, String question) async {
  final ChatSession session = ChatSession(engine);
  final LlamaToolLoopResult result = await session.sendWithTools(
    question,
    tools: [weatherTool],
    maxRounds: 5,
  );
  if (result.stopReason != LlamaToolLoopStopReason.completed) {
    print('Stopped: ${result.stopReason.name}');
    return null;
  }
  return result.text;
}
```

Run a tool that needs approval in the app instead of a handler:

```dart
import 'package:llamadart/llamadart.dart';

const ToolDefinition deleteFileTool = ToolDefinition(
  name: 'delete_file',
  description: 'Delete a file in the workspace',
  parameters: [],
);

Future<LlamaToolLoopResult> runWithApproval(
  ChatSession session,
  String request,
  Future<bool> Function(LlamaToolCallContent call) approve,
) {
  return session.sendWithTools(
    request,
    tools: [deleteFileTool],
    onToolCall: (LlamaToolCallContent call) async =>
        await approve(call) ? {'deleted': true} : {'error': 'Denied by user'},
  );
}
```

Force a single tool call for one request:

```dart
import 'package:llamadart/llamadart.dart';

Future<LlamaToolCallContent?> forceCall(
  LlamaEngine engine,
  List<ToolDefinition> tools,
  String request,
) async {
  final LlamaCompletion reply = await engine.complete(
    [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: request)],
    tools: tools,
    toolChoice: ToolChoice.required,
    params: const GenerationParams(maxTokens: 256, temp: 0),
  );
  return reply.toolCalls.firstOrNull;
}
```

## More

- Tool calling: https://llamadart.leehack.com/docs/guides/tool-calling
- Chat templates and parsing: https://llamadart.leehack.com/docs/guides/chat-template-and-parsing
