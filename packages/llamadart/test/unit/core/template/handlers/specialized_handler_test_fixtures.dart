import 'dart:convert';

import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';

final weatherTool = ToolDefinition(
  name: 'weather',
  description: 'Weather',
  parameters: const [],
  handler: (_) async => null,
);

final weatherWithCityTool = ToolDefinition(
  name: 'weather',
  description: 'Weather',
  parameters: [ToolParam.string('city', required: true)],
  handler: (_) async => null,
);

final weatherNestedTool = ToolDefinition(
  name: 'weather',
  description: 'Weather with options',
  parameters: [
    ToolParam.string('city', required: true),
    ToolParam.object(
      'options',
      properties: [ToolParam.string('units', required: true)],
      required: true,
    ),
  ],
  handler: (_) async => null,
);

final attributeTool = ToolDefinition(
  name: 'weather&"alerts',
  description: 'Weather alerts',
  parameters: const [],
  handler: (_) async => null,
);

final escapedSchemaTool = ToolDefinition(
  name: 'weather',
  description: 'Weather',
  parameters: [ToolParam.string('city&"zone', required: true)],
  handler: (_) async => null,
);

final escapedAttributeSchemaTool = ToolDefinition(
  name: 'weather&"alerts',
  description: 'Weather alerts',
  parameters: [ToolParam.string('city&"zone', required: true)],
  handler: (_) async => null,
);

final zeroArgTool = ToolDefinition(
  name: 'ping',
  description: 'Ping',
  parameters: const [],
  handler: (_) async => null,
);

final schemaTool = ToolDefinition(
  name: 'inspect',
  description: 'Inspect typed values',
  parameters: [
    ToolParam.string('code', required: true),
    ToolParam.object('options', properties: const [], required: true),
    ToolParam.array(
      'items',
      itemType: ToolParam.string('item'),
      required: true,
    ),
    ToolParam.integer('count', required: true),
    ToolParam.boolean('active', required: true),
    ToolParam.nullType('empty', required: true),
  ],
  handler: (_) async => null,
);

Map<String, dynamic> arguments(dynamic parsed) {
  return jsonDecode(parsed.toolCalls.first.function!.arguments!)
      as Map<String, dynamic>;
}
