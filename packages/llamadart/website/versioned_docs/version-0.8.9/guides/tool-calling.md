---
title: Tool Calling
---

`llamadart` supports template-aware tool calling through `ToolDefinition` and
`ToolChoice`.

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

## Run completion with tools

```dart
final stream = engine.create(
  [
    LlamaChatMessage.fromText(
      role: LlamaChatRole.user,
      text: 'What is the weather in Seoul?',
    ),
  ],
  tools: [weatherTool],
  toolChoice: ToolChoice.auto,
  parallelToolCalls: false,
);
```

## Typical execution loop

1. Stream assistant response.
2. Detect tool call content from deltas/messages.
3. Execute matching tool handler.
4. Append tool result message.
5. Call `engine.create(...)` again for final assistant response.

For an end-to-end OpenAI-compatible reference, see
`example/llamadart_server` and the docs page
[OpenAI-Compatible Server](../examples/llamadart-server).

## Tool choice semantics

- `ToolChoice.none`: disable tool calls for that request.
- `ToolChoice.auto`: model decides whether to call tools.
- `ToolChoice.required`: model must emit tool calls.
