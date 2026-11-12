import 'package:genkit/plugin.dart' as genkit;
import 'package:genkit_llamadart/src/integration/genkit/converters/genkit_to_llama.dart';
import 'package:test/test.dart';

void main() {
  test(
    'model-facing schemas retain nested types, enums and required nulls',
    () {
      final schema = <String, dynamic>{
        'type': 'object',
        'required': ['city', 'unit', 'unset'],
        'properties': {
          'city': {'type': 'string', 'description': 'City to look up.'},
          'unit': {
            'type': 'string',
            'enum': ['celsius', 'fahrenheit'],
          },
          'unset': {'type': 'null'},
          'filters': {
            'type': 'object',
            'properties': {
              'days': {'type': 'integer'},
              'ratio': {'type': 'number'},
              'active': {'type': 'boolean'},
            },
            'required': ['days'],
          },
          'rows': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'value': {'type': 'null'},
              },
              'required': ['value'],
            },
          },
        },
      };
      final tool = toLlamaTools([
        genkit.ToolDefinition(
          name: 'lookup',
          description: 'Lookup',
          inputSchema: schema,
        ),
      ]).tools.single;
      expect(tool.toJsonSchema(), schema);
      expect((tool.toJson()['function'] as Map)['parameters'], schema);
    },
  );
}
