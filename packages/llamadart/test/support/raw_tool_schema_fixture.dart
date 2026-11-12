import 'package:llamadart/llamadart.dart';

ToolDefinition rawSchemaTool({ToolHandler? handler}) =>
    ToolDefinition.fromJsonSchema(
      name: 'inspect',
      description: 'Inspect typed values',
      handler: handler,
      schema: {
        'type': 'object',
        'properties': {
          'code': {
            'type': ['string', 'null'],
          },
          'mode': {
            'type': 'integer',
            'enum': [1, 2],
          },
          'nested': {
            'type': 'object',
            'properties': {
              'active': {'type': 'boolean'},
            },
            'required': ['active'],
            'additionalProperties': false,
          },
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'minItems': 1,
            'maxItems': 2,
          },
        },
        'required': ['code', 'mode', 'nested', 'tags'],
        'additionalProperties': false,
      },
    );

const rawToolArguments = <String, dynamic>{
  'code': null,
  'mode': 2,
  'nested': {'active': true},
  'tags': ['a'],
};

ToolDefinition rawScalarTool() => ToolDefinition.fromJsonSchema(
  name: 'weather',
  description: 'Weather',
  schema: {
    'type': 'object',
    'properties': {
      'city': {'type': 'string'},
      'count': {'type': 'integer'},
      'nothing': {'type': 'null'},
    },
    'required': ['city', 'count'],
    'additionalProperties': false,
  },
);
