import 'package:genkit/plugin.dart' as genkit;
import 'package:genkit_llamadart/src/integration/genkit/converters/schema_to_tool_params.dart';
import 'package:test/test.dart';

void main() {
  final propertyCases = <String, Object?>{
    'nullable union': {
      'type': ['string', 'null'],
    },
    'unknown type': {'type': 'date'},
    'missing type': <String, dynamic>{},
    'null type declaration': {'type': null},
    'boolean schema': false,
    'integer enum': {
      'type': 'integer',
      'enum': [1, 2],
    },
    'mixed enum': {
      'type': 'string',
      'enum': ['a', null],
    },
    'empty enum': {'type': 'string', 'enum': []},
    'integer bounds': {'type': 'integer', 'minimum': 1, 'maximum': 5},
    'string bounds': {'type': 'string', 'maxLength': 5},
    'pattern': {'type': 'string', 'pattern': '^a'},
    'format': {'type': 'string', 'format': 'email'},
    'constant': {'type': 'string', 'const': 'a'},
    'composition': {
      'anyOf': [
        {'type': 'string'},
        {'type': 'null'},
      ],
    },
    'untyped array': {'type': 'array'},
    'tuple array': {
      'type': 'array',
      'items': [
        {'type': 'string'},
      ],
    },
    'array bounds': {
      'type': 'array',
      'items': {'type': 'string'},
      'minItems': 1,
    },
    'object policy': {'type': 'object', 'additionalProperties': false},
    'nested unknown constraint': {
      'type': 'array',
      'items': {'type': 'integer', 'multipleOf': 2},
    },
  };
  for (final entry in propertyCases.entries) {
    test('rejects ${entry.key} instead of dropping its contract', () {
      expect(
        () => schemaToToolParams(
          normalizeToolInputSchema({
            'type': 'object',
            'properties': {'value': entry.value},
          }),
        ),
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
  final rootCases = <String, Map<String, dynamic>>{
    'closed root': {'type': 'object', 'additionalProperties': false},
    'schema for extra properties': {
      'type': 'object',
      'additionalProperties': {'type': 'string'},
    },
    'nullable object root': {
      'type': ['object', 'null'],
      'properties': <String, dynamic>{},
    },
    'malformed properties': {'type': 'object', 'properties': []},
    'malformed required': {'type': 'object', 'required': 'value'},
    'unknown required property': {
      'type': 'object',
      'required': ['value'],
    },
    'duplicate required': {
      'type': 'object',
      'properties': {
        'value': {'type': 'string'},
      },
      'required': ['value', 'value'],
    },
    'reference constraint sibling': {
      r'$ref': r'#/$defs/Input',
      r'$defs': {
        'Input': {
          'type': 'object',
          'properties': {
            'value': {'type': 'integer'},
          },
        },
      },
      'properties': {
        'value': {'type': 'string'},
      },
    },
    'ambiguous definition names': {
      r'$ref': r'#/$defs/Input',
      r'$defs': {
        'Input': {'type': 'object'},
      },
      'definitions': {
        'Input': {'type': 'string'},
      },
    },
    'missing reference': {r'$ref': r'#/$defs/Missing'},
    'legacy reference to modern definition': {
      r'$ref': '#/definitions/Input',
      r'$defs': {
        'Input': {'type': 'object'},
      },
    },
    'modern reference to legacy definition': {
      r'$ref': r'#/$defs/Input',
      'definitions': {
        'Input': {'type': 'object'},
      },
    },
    'nested reference to the wrong definition block': {
      'type': 'object',
      'properties': {
        'value': {r'$ref': '#/definitions/Value'},
      },
      r'$defs': {
        'Value': {'type': 'string'},
      },
    },
    'external reference': {r'$ref': 'https://example.invalid/schema'},
    'circular reference': {
      r'$ref': r'#/$defs/Input',
      r'$defs': {
        'Input': {r'$ref': r'#/$defs/Input'},
      },
    },
  };
  for (final entry in rootCases.entries) {
    test('rejects ${entry.key}', () {
      expect(
        () => schemaToToolParams(normalizeToolInputSchema(entry.value)),
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
  test('explicit unrestricted properties retain the default open contract', () {
    expect(
      schemaToToolParams(
        normalizeToolInputSchema({
          'type': 'object',
          'additionalProperties': true,
        }),
      ),
      isEmpty,
    );
  });
}
