import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';

/// The tools of the Ling 3.0 upstream fixtures and grammar replies.
final List<ToolDefinition> ling3Tools = [
  ToolDefinition(
    name: 'get_weather',
    description: 'w',
    parameters: [ToolParam.string('location', required: true)],
  ),
  ToolDefinition(
    name: 'get_time',
    description: 't',
    parameters: [
      ToolParam.string('tz', required: true),
      ToolParam.integer('days'),
    ],
  ),
  ToolDefinition(
    name: 'set_flags',
    description: 'f',
    parameters: [
      ToolParam.boolean('verbose', required: true),
      ToolParam.array('tags', itemType: ToolParam.string('item')),
      ToolParam.object('config', properties: [ToolParam.integer('k')]),
    ],
  ),
  ToolDefinition(
    name: 'book',
    description: 'b',
    parameters: [
      ToolParam.string('from', required: true),
      ToolParam.string('to', required: true),
      ToolParam.integer('seats'),
    ],
  ),
  ToolDefinition(
    name: 'big',
    description: 'b',
    parameters: [
      for (final name in 'abcdefg'.split(''))
        ToolParam.string(name, required: true),
    ],
  ),
  ToolDefinition(
    name: 'big6',
    description: 'b',
    parameters: [
      for (final name in 'abcdef'.split(''))
        ToolParam.string(name, required: true),
    ],
  ),
  ToolDefinition(name: 'ping', description: 'p', parameters: const []),
  ToolDefinition(
    name: 'misc',
    description: 'm',
    parameters: [
      ToolParam.enumType('mode', values: ['fast', 'slow'], required: true),
    ],
  ),
  ToolDefinition(
    name: 'get_weather_extra',
    description: 'e',
    parameters: [ToolParam.string('q', required: true)],
  ),
];

/// A tool whose arguments may be several JSON types, which a request refuses
/// as a canonical JSON Schema tool, so only a handler takes it.
final List<ToolDefinition> ling3SchemaTools = [
  ToolDefinition.fromJsonSchema(
    name: 'mixed',
    description: 'm',
    schema: {
      'type': 'object',
      'properties': {
        'level': {
          'type': ['integer', 'string'],
        },
        'maybe': {
          'type': ['string', 'null'],
        },
        'any': {
          'anyOf': [
            {'type': 'integer'},
            {'type': 'string'},
          ],
        },
      },
      'required': ['level'],
      'additionalProperties': true,
    },
  ),
];
