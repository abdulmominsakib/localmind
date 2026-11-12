import 'package:genkit/plugin.dart' as genkit;
import 'package:genkit_llamadart/src/integration/genkit/converters/genkit_to_llama.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

void main() {
  genkit.ToolDefinition tool(Map<String, dynamic> schema) =>
      genkit.ToolDefinition(
        name: 'lookup',
        description: 'Lookup',
        inputSchema: schema,
      );

  test(
    'rich schemas retain constraints, local references and owned values',
    () {
      final schema = <String, dynamic>{
        r'$ref': r'#/$defs/Input',
        r'$defs': {
          'Input': {
            'type': 'object',
            'properties': {
              'nullable': {
                'type': ['string', 'null'],
              },
              'mode': {
                'type': 'integer',
                'enum': [1, 2],
              },
              'fixed': {'const': 'ok'},
              'short': {'type': 'string', 'minLength': 1, 'maxLength': 5},
              'rows': {
                'type': 'array',
                'items': {r'$ref': r'#/$defs/Value'},
                'minItems': 1,
                'maxItems': 2,
              },
              'choice': {
                'anyOf': [
                  {r'$ref': r'#/$defs/Value'},
                  {'type': 'null'},
                ],
              },
              'extras': {
                'type': 'object',
                'additionalProperties': {r'$ref': r'#/$defs/Value'},
              },
            },
            'required': ['nullable', 'mode'],
            'additionalProperties': false,
          },
          'Value': {'type': 'string'},
        },
      };
      final converted = toLlamaTools([tool(schema)]);
      final definition = converted.tools.single;
      final modelSchema = definition.toJsonSchema();
      final properties = modelSchema['properties'] as Map;
      expect(properties['nullable'], {
        'type': ['string', 'null'],
      });
      expect(properties['mode'], {
        'type': 'integer',
        'enum': [1, 2],
      });
      expect(properties['fixed'], {'const': 'ok'});
      expect(properties['short'], {
        'type': 'string',
        'minLength': 1,
        'maxLength': 5,
      });
      expect(properties['rows'], {
        'type': 'array',
        'items': {'type': 'string'},
        'minItems': 1,
        'maxItems': 2,
      });
      expect(properties['choice'], {
        'anyOf': [
          {'type': 'string'},
          {'type': 'null'},
        ],
      });
      expect(properties['extras'], {
        'type': 'object',
        'properties': {},
        'additionalProperties': {'type': 'string'},
      });
      expect(modelSchema['additionalProperties'], isFalse);
      expect(modelSchema['required'], ['nullable', 'mode']);
      expect(converted.inputSchemas['lookup'], modelSchema);
      expect(
        (definition.toJson()['function'] as Map)['parameters'],
        modelSchema,
      );
      (schema[r'$defs'] as Map).clear();
      (properties['mode'] as Map)['enum'] = [9];
      expect((definition.toJsonSchema()['properties'] as Map)['mode'], {
        'type': 'integer',
        'enum': [1, 2],
      });
    },
  );

  test(
    'dialect annotations need no remote meta-schema and property names survive',
    () {
      final converted = toLlamaTools([
        tool({
          r'$schema': 'http://json-schema.org/draft-07/schema#',
          'type': 'object',
          'properties': {
            r'$schema': {
              'type': ['string', 'null'],
              r'$schema': 'http://json-schema.org/draft-07/schema#',
            },
          },
          'additionalProperties': false,
        }),
      ]);
      final schema = converted.tools.single.toJsonSchema();
      expect(schema.containsKey(r'$schema'), isFalse);
      expect(schema['properties'], {
        r'$schema': {
          'type': ['string', 'null'],
        },
      });
    },
  );

  test('legacy tools retain best-effort runtime compatibility', () {
    final converted = toLlamaTools([
      tool({
        'type': 'object',
        'properties': {
          'value': {'type': 'string'},
        },
      }),
    ]);
    expect(converted.inputSchemas, isEmpty);
    expect(converted.tools.single.parameters.single.name, 'value');
    expect(toLlamaTools(null).tools, isEmpty);
  });

  test('owned adapter schemas retain the core unsupported-template guard', () {
    final converted = toLlamaTools([
      tool({
        'type': 'object',
        'properties': {
          'value': {
            'type': ['string', 'null'],
          },
        },
        'additionalProperties': false,
      }),
    ]);
    expect(
      () => llama.ChatTemplateEngine.render(
        templateSource: '<|start_header_id|>ipython<|end_header_id|>',
        messages: [llama.LlamaChatMessage(role: 'user', content: 'Lookup')],
        metadata: {},
        tools: converted.tools,
      ),
      throwsA(isA<llama.LlamaUnsupportedException>()),
    );
  });

  test('canonical objects retain the default open property policy', () {
    final converted = toLlamaTools([
      tool({
        'type': 'object',
        'properties': {
          'value': {
            'type': ['integer', 'null'],
          },
        },
      }),
    ]);
    expect(
      converted.tools.single.toJsonSchema()['additionalProperties'],
      isTrue,
    );
  });

  final invalid = <String, Map<String, dynamic>>{
    'numeric bounds': {'type': 'integer', 'minimum': 1},
    'patterns': {'type': 'string', 'pattern': '^a'},
    'formats': {'type': 'string', 'format': 'email'},
    'oneOf': {
      'oneOf': [
        {'type': 'string'},
        {'type': 'null'},
      ],
    },
    'invalid enum': {
      'type': 'integer',
      'enum': [1, 'a'],
    },
    'remote ref in alternative': {
      'anyOf': [
        {r'$ref': 'https://example.invalid/secret'},
        {'type': 'null'},
      ],
    },
    'wrong ref namespace in alternative': {
      'anyOf': [
        {r'$ref': '#/definitions/Value'},
      ],
    },
    'ref constraint sibling': {r'$ref': r'#/$defs/Value', 'maxLength': 1},
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key} without dropping constraints', () {
      expect(
        () => toLlamaTools([
          tool({
            'type': 'object',
            'properties': {'value': entry.value},
            r'$defs': {
              'Value': {'type': 'string'},
            },
          }),
        ]),
        throwsA(
          isA<genkit.GenkitException>().having(
            (e) => e.status,
            'status',
            genkit.StatusCode.invalidArgument,
          ),
        ),
      );
    });
  }

  test(
    'schema copying rejects cycles and bounded expansion rejects ref trees',
    () {
      final cycle = <String, dynamic>{'type': 'object'};
      cycle['properties'] = {'self': cycle};
      expect(
        () => toLlamaTools([tool(cycle)]),
        throwsA(isA<genkit.GenkitException>()),
      );
      final definitions = <String, dynamic>{
        'Leaf': {'type': 'null'},
      };
      var previous = 'Leaf';
      for (var i = 0; i < 16; i++) {
        final name = 'Level$i';
        definitions[name] = {
          'type': 'object',
          'properties': {
            'left': {r'$ref': '#/definitions/$previous'},
            'right': {r'$ref': '#/definitions/$previous'},
          },
        };
        previous = name;
      }
      expect(
        () => toLlamaTools([
          tool({
            r'$ref': '#/definitions/$previous',
            'definitions': definitions,
          }),
        ]),
        throwsA(isA<genkit.GenkitException>()),
      );
    },
  );
}
