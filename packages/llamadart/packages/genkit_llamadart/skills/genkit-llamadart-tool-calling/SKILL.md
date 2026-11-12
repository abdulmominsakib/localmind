---
name: genkit-llamadart-tool-calling
description: >-
  Use when adding Genkit tools or an agent loop to a genkit_llamadart app:
  ai.defineTool with object input schemas, ToolResult.response, passing tools
  and maxTurns to ai.generate or ai.generateStream, carrying multi-turn history,
  or debugging local models that skip tools or emit weak arguments.
---

# Tool calling with genkit_llamadart

## Guidelines

- Define tools with `ai.defineTool<Input, Output>(name:, description:, inputSchema:, outputSchema:, fn:)`
  and pass them with `tools:` to `ai.generate` or `ai.generateStream`. Genkit
  runs the loop: it executes each tool request and calls the model again, up
  to `maxTurns`. Always set `maxTurns`.
- Tool callbacks return `ToolResult.response(value)`. Return text or
  JSON-compatible data, or supply `parts: [TextPart(text: '...')]` for the
  model-facing presentation. Nonempty text parts are joined with newlines;
  structured `output` remains in Genkit history and is not appended to that
  presentation. Missing/empty parts fall back to output. Non-text result parts
  fail with `UNIMPLEMENTED`; multimodal tool results remain unsupported.
- Tool input schemas and tool-call arguments must be JSON objects, because
  llamadart passes arguments as `Map<String, dynamic>`. Primitive or list root
  inputs fail with `INVALID_ARGUMENT`. For a no-argument tool, use an object
  schema with no properties.
- Simple schemas keep their existing runtime compatibility. Nullable/type
  alternatives, scalar enums/const, `anyOf`, string/array length bounds and
  restrictive `additionalProperties` policies use llamadart 0.13's owned schema
  API. They require grammar support and a supported template. Use explicit
  closed objects for fixed argument names. Rich-schema responses are buffered
  until final argument validation; invalid output publishes no partial result.
  Numeric bounds, patterns, formats and `oneOf`/`allOf` remain rejected. Do not
  remove a safety constraint and assume it is enforced. See the
  [schema guide](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/doc/tool-input-schemas.md)
  and [runnable example](https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_tool_schema_example.dart).
- Named Schemantic object schemas work; local `$ref`/`$defs` wrappers are
  resolved before parameters are mapped.
- The model definition must keep `supportsTools: true` (the default).
  Requests with tools on a model registered with `supportsTools: false` fail
  with `FAILED_PRECONDITION`. The loaded runtime must also confirm tool calling;
  unsupported runtimes fail before generation with `UNIMPLEMENTED`. The same
  checks apply to tool request/result history even without new tool definitions.
- Constrained JSON with active tools requires native llama.cpp, one call per
  turn and `enableThinking: false`. Qwen3 1.7B is qualified. WebGPU and LiteRT-LM
  reject it. `required` persists across Genkit turns; explicitly switch to
  `none` or `auto` when the application allows a final answer. Constrained
  content is published only after complete parsing/schema validation.
- `LlamaDartGenerationConfig(parallelToolCalls: true)` lets the model emit
  several calls in one turn (default `false`). Keep `enableThinking: false`
  unless the model's template needs reasoning.
- A tool that throws, or a model error, resolves the response with
  `FinishReason.failed`; exhausting `maxTurns` or a cancel yields
  `FinishReason.aborted`. Check `finishReason` before using `response.text`.
- For multi-turn chat, keep `response.messages` (it includes the tool
  requests and tool results) and pass it back with `messages:` plus the next
  user message.
- Local models vary in tool reliability. Use a tool-capable instruct model,
  specific tool descriptions that name the expected argument keys, a system
  message that says when to call tools, and a low temperature.

## Examples

Define a tool with an object input schema and run a bounded tool loop,
keeping history across turns:

```dart
import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:schemantic/schemantic.dart';

final SchemanticType<Map<String, dynamic>> weatherInput =
    SchemanticType.from<Map<String, dynamic>>(
      jsonSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'city': <String, Object?>{
            'type': 'string',
            'description': 'City name, for example Seoul',
          },
        },
        'required': <String>['city'],
      },
      parse: (json) => (json as Map).cast<String, dynamic>(),
    );

Future<void> main() async {
  final plugin = llamaDart(
    models: const <LlamaModelDefinition>[
      LlamaModelDefinition(
        name: 'local-agent',
        modelPath: '/models/tool-capable-instruct.gguf',
        modelParams: ModelParams(contextSize: 8192),
        supportsEmbeddings: false,
      ),
    ],
  );
  final ai = Genkit(plugins: <LlamaDartPlugin>[plugin]);

  final weatherTool = ai.defineTool<Map<String, dynamic>, Map<String, dynamic>>(
    name: 'get_weather',
    description: 'Get current weather. Input JSON key: city.',
    inputSchema: weatherInput,
    outputSchema: SchemanticType.map(
      SchemanticType.string(),
      SchemanticType.dynamicSchema(),
    ),
    fn: (input, context) async {
      final city = input['city'] as String? ?? 'unknown';
      return ToolResult.response(<String, dynamic>{
        'city': city,
        'condition': 'clear',
        'temperatureC': 19,
      });
    },
  );

  var history = <Message>[
    Message(
      role: Role.system,
      content: <Part>[
        TextPart(
          text: 'Use get_weather for weather questions, then answer briefly.',
        ),
      ],
    ),
  ];

  try {
    for (final question in <String>[
      'What is the weather in Seoul?',
      'Should I bring a jacket?',
    ]) {
      final response = await ai.generate(
        model: llamaDart.model('local-agent'),
        messages: <Message>[
          ...history,
          Message(
            role: Role.user,
            content: <Part>[TextPart(text: question)],
          ),
        ],
        tools: <Tool<Map<String, dynamic>, Map<String, dynamic>>>[weatherTool],
        maxTurns: 4,
        config: const LlamaDartGenerationConfig(
          temperature: 0.2,
          enableThinking: false,
        ),
      );

      if (response.finishReason == FinishReason.failed ||
          response.finishReason == FinishReason.aborted) {
        print('Stopped: ${response.error?.message}');
        break;
      }
      print(response.text);
      history = response.messages;
    }
  } finally {
    await plugin.dispose();
    await ai.shutdown();
  }
}
```

Stream a tool-using turn with a no-argument tool. Define tools once per
`Genkit` instance and reuse them across requests:

```dart
import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:schemantic/schemantic.dart';

final SchemanticType<Map<String, dynamic>> noArguments =
    SchemanticType.from<Map<String, dynamic>>(
      jsonSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      },
      parse: (json) => (json as Map? ?? const {}).cast<String, dynamic>(),
    );

Tool<Map<String, dynamic>, String> defineClockTool(Genkit ai) {
  return ai.defineTool<Map<String, dynamic>, String>(
    name: 'get_current_time',
    description: 'Get the current local time. Call it with an empty object.',
    inputSchema: noArguments,
    outputSchema: SchemanticType.string(),
    fn: (input, context) async {
      return ToolResult.response(DateTime.now().toIso8601String());
    },
  );
}

Future<String> streamAgentTurn(
  Genkit ai,
  Tool<Map<String, dynamic>, String> clockTool,
  String prompt,
) async {
  final stream = ai.generateStream<Object?, LlamaDartGenerationConfig>(
    model: llamaDart.model('local-agent'),
    prompt: prompt,
    tools: <Tool<Map<String, dynamic>, String>>[clockTool],
    maxTurns: 4,
    config: const LlamaDartGenerationConfig(
      temperature: 0.2,
      enableThinking: false,
    ),
  );

  await for (final chunk in stream) {
    stdout.write(chunk.text);
  }
  stdout.writeln();

  final response = await stream.onResult;
  return response.finishReason == FinishReason.failed ||
          response.finishReason == FinishReason.aborted
      ? 'Stopped: ${response.error?.message}'
      : response.text;
}
```

## More

- Check the final generation result before acting on streamed tool previews.
  Invalid or token-limited final calls fail with `DATA_LOSS`; partial argument
  deltas are allowed during streaming.
- `ToolChoice.none` prevents handler execution; inline tool-looking text stays
  inert. Genkit 1.0 keeps `required` across turns, so the application must change
  the next turn's choice when it needs a final text answer.

- Runnable agent example:
  https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_agent_example.dart
- llamadart tool-calling behavior per runtime:
  https://llamadart.leehack.com/docs/guides/tool-calling
