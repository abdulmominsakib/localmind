import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/grammar/llguidance_schema_contract.dart';
import 'package:test/test.dart';

Map<String, dynamic> _property(Map<String, dynamic> schema) => {
  'type': 'object',
  'properties': {'v': schema},
  'required': ['v'],
};

Map<String, dynamic> _optionalProperties(int count) => {
  'type': 'object',
  'properties': {
    for (var i = 0; i < count; i++) 'k$i': {'type': 'integer'},
  },
};

Map<String, dynamic> _allOfEnums(int width, int components) => {
  'type': 'string',
  'allOf': [
    for (var c = 0; c < components; c++)
      {
        'enum': [for (var i = 0; i < width; i++) 'v$i'],
      },
  ],
};

void main() {
  // Both the GBNF converter and the pinned runtime accepted each of these.
  final accepted = <String, Map<String, dynamic>>{
    'flat object': {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'age': {'type': 'integer'},
      },
      'required': ['name', 'age'],
      'additionalProperties': false,
    },
    'root array': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'nested object and bounded array': _property({
      'type': 'object',
      'properties': {
        'tags': {
          'type': 'array',
          'items': {'type': 'string'},
          'minItems': 1,
          'maxItems': 3,
        },
      },
      'required': ['tags'],
    }),
    'recursive ref through items': {
      'type': 'object',
      'properties': {
        'root': {r'$ref': r'#/$defs/node'},
      },
      'required': ['root'],
      r'$defs': {
        'node': {
          'type': 'object',
          'properties': {
            'v': {'type': 'integer'},
            'kids': {
              'type': 'array',
              'items': {r'$ref': r'#/$defs/node'},
              'maxItems': 2,
            },
          },
          'required': ['v'],
        },
      },
    },
    'ref cycle through a property': {
      r'$ref': r'#/$defs/n',
      r'$defs': {
        'n': {
          'type': 'object',
          'properties': {
            'c': {r'$ref': r'#/$defs/n'},
          },
          'required': ['c'],
        },
      },
    },
    'definitions ref': {
      'type': 'object',
      'properties': {
        'a': {r'$ref': '#/definitions/s'},
      },
      'required': ['a'],
      'definitions': {
        's': {'type': 'boolean'},
      },
    },
    'anyOf': _property({
      'anyOf': [
        {'type': 'string', 'maxLength': 5},
        {'type': 'integer'},
      ],
    }),
    'pattern class and counted repetition': _property({
      'type': 'string',
      'pattern': r'^[A-Z]{3}-[0-9]{2}$',
    }),
    'pattern group alternation': _property({
      'type': 'string',
      'pattern': r'^(ab|cd)+$',
    }),
    'pattern escaped metacharacters': _property({
      'type': 'string',
      'pattern': r'^\$[0-9]+\.[0-9]{2}$',
    }),
    'pattern trailing class dash': _property({
      'type': 'string',
      'pattern': r'^[a-]$',
    }),
    'pattern repetition product at the limit': _property({
      'type': 'string',
      'pattern': r'^(?:a{300}){300}$',
    }),
    'format uuid': _property({'type': 'string', 'format': 'uuid'}),
    'format date': _property({'type': 'string', 'format': 'date'}),
    'integer bounds': _property({
      'type': 'integer',
      'minimum': 3,
      'maximum': 7,
    }),
    'mixed enum': _property({
      'enum': ['a', 1, null, true],
    }),
    'object const': _property({
      'const': {
        'k': [1, 2],
      },
    }),
    'allOf object merge': {
      'allOf': [
        {
          'type': 'object',
          'properties': {
            'a': {'type': 'string'},
          },
        },
        {
          'properties': {
            'b': {'type': 'integer'},
          },
        },
      ],
    },
    'allOf enum product at the limit': _allOfEnums(141, 2),
    'type list': _property({
      'type': ['string', 'null'],
    }),
    'closed tuple': _property({
      'type': 'array',
      'prefixItems': [
        {'type': 'string'},
        {'type': 'integer'},
      ],
      'minItems': 2,
      'maxItems': 2,
    }),
    'additionalProperties schema': {
      'type': 'object',
      'additionalProperties': {'type': 'integer'},
    },
    'string length': _property({
      'type': 'string',
      'minLength': 2,
      'maxLength': 4,
    }),
    'root draft 2020-12 and id': {
      r'$schema': 'https://json-schema.org/draft/2020-12/schema#',
      r'$id': 'https://example.com/s.json',
      'type': 'object',
    },
    'trivial assertions': {
      'type': 'object',
      'minProperties': 0,
      'properties': {
        'n': {'type': 'integer', 'multipleOf': 1},
      },
    },
    'largest safe integer const': _property({'const': 9007199254740992}),
    '400 optional properties': _optionalProperties(400),
  };
  for (final entry in accepted.entries) {
    test('accepts ${entry.key}', () {
      validateLlguidanceResponseSchema(entry.value);
    });
  }

  // Each of these passes the GBNF subset but fails at the LiteRT-LM send
  // (INTERNAL) or compiles to a different language there.
  final refused = <String, (Map<String, dynamic>, String)>{
    'oneOf': (
      _property({
        'oneOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
      }),
      r'$.properties.v.oneOf',
    ),
    'uniqueItems false': (
      _property({'type': 'array', 'uniqueItems': false}),
      r'$.properties.v.uniqueItems',
    ),
    r'$dynamicAnchor': (
      {r'$dynamicAnchor': 'node', 'type': 'object'},
      r'$.$dynamicAnchor',
    ),
    r'$recursiveAnchor': (
      {r'$recursiveAnchor': true, 'type': 'object'},
      r'$.$recursiveAnchor',
    ),
    'x-guidance options': (
      {
        'x-guidance': {'coerce_one_of': true},
        'type': 'object',
      },
      r'$.x-guidance',
    ),
    'draft-07 schema': (
      {r'$schema': 'http://json-schema.org/draft-07/schema#', 'type': 'object'},
      r'$.$schema',
    ),
    'unknown schema URI': (
      {r'$schema': 'https://example.com/meta', 'type': 'object'},
      r'$.$schema',
    ),
    'nested id': (
      _property({r'$id': 'https://example.com/inner', 'type': 'integer'}),
      r'$.properties.v.$id',
    ),
    'nested schema': (
      _property({
        r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        'type': 'integer',
      }),
      r'$.properties.v.$schema',
    ),
    'format uuid4': (
      _property({'type': 'string', 'format': 'uuid4'}),
      r'$.properties.v.format',
    ),
    'format time': (
      _property({'type': 'string', 'format': 'time'}),
      r'$.properties.v.format',
    ),
    'format date-time': (
      _property({'type': 'string', 'format': 'date-time'}),
      r'$.properties.v.format',
    ),
    'open prefixItems': (
      _property({
        'type': 'array',
        'prefixItems': [
          {'type': 'string'},
        ],
      }),
      r'$.properties.v.prefixItems',
    ),
    'items array form': (
      _property({
        'type': 'array',
        'items': [
          {'type': 'string'},
        ],
        'minItems': 1,
      }),
      r'$.properties.v.prefixItems',
    ),
    'pattern class intersection': (
      _property({'type': 'string', 'pattern': r'^[a&&b]+$'}),
      r'$.properties.v.pattern',
    ),
    'pattern class symmetric difference': (
      _property({'type': 'string', 'pattern': r'^[a~~b]+$'}),
      r'$.properties.v.pattern',
    ),
    'pattern repetition product': (
      _property({'type': 'string', 'pattern': r'^(a{1000}){1000}$'}),
      r'$.properties.v.pattern',
    ),
    'pattern repetition product inside alternation': (
      _property({'type': 'string', 'pattern': r'^(b|(?:a{400}){400})$'}),
      r'$.properties.v.pattern',
    ),
    'integer const beyond 2^53': (
      _property({'const': 18014398509481984}),
      r'$.properties.v.const',
    ),
    'integer in nested enum value beyond 2^53': (
      _property({
        'enum': [
          {
            'n': [18014398509481984],
          },
        ],
      }),
      r'$.properties.v.enum',
    ),
    'allOf enum product': (_allOfEnums(142, 2), r'$.allOf'),
    'allOf enum product through a ref': (
      {
        'type': 'string',
        'allOf': [
          {r'$ref': r'#/$defs/e'},
          {r'$ref': r'#/$defs/e'},
          {r'$ref': r'#/$defs/e'},
        ],
        r'$defs': {
          'e': {
            'enum': [for (var i = 0; i < 28; i++) 'v$i'],
          },
        },
      },
      r'$.allOf',
    ),
    '401 optional properties': (_optionalProperties(401), r'$ allows'),
    'optional properties summed across anyOf': (
      _property({
          'anyOf': [
            {
              'type': 'object',
              'properties': {
                for (var i = 0; i < 201; i++) 'a$i': {'type': 'integer'},
              },
            },
            {r'$ref': r'#/$defs/b'},
          ],
        })
        ..[r'$defs'] = {
          'b': {
            'type': 'object',
            'properties': {
              for (var i = 0; i < 200; i++) 'b$i': {'type': 'integer'},
            },
          },
        },
      r'$.properties.v allows',
    ),
    'pointer escape in ref': (
      {
        'type': 'object',
        'properties': {
          'a': {r'$ref': r'#/$defs/a~1b'},
        },
        r'$defs': {
          'a/b': {'type': 'integer'},
        },
      },
      r'$.properties.a.$ref',
    ),
    'ref cycle with no value between': (
      {
        r'$ref': r'#/$defs/a',
        r'$defs': {
          'a': {
            'anyOf': [
              {r'$ref': r'#/$defs/b'},
              {'type': 'string'},
            ],
          },
          'b': {r'$ref': r'#/$defs/a'},
        },
      },
      r'$ref',
    ),
    'refused keyword reached only through a ref': (
      {
        'type': 'object',
        'properties': {
          'a': {r'$ref': r'#/$defs/u'},
        },
        r'$defs': {
          'u': {
            'oneOf': [
              {'type': 'string'},
            ],
          },
        },
      },
      r'$.properties.a.$ref.oneOf',
    ),
  };
  for (final entry in refused.entries) {
    test('refuses ${entry.key} before generation', () {
      final (schema, path) = entry.value;
      expect(
        () => validateLlguidanceResponseSchema(schema),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'message',
            allOf(contains('native LiteRT-LM'), contains(path)),
          ),
        ),
      );
    });
  }

  test('keeps the GBNF subset refusals', () {
    expect(
      () => validateLlguidanceResponseSchema({
        'type': 'object',
        'minProperties': 1,
      }),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'message',
          contains('JSON-schema-to-GBNF subset'),
        ),
      ),
    );
  });

  test('ignores unreferenced definitions', () {
    validateLlguidanceResponseSchema({
      'type': 'object',
      r'$defs': {
        'unused': {
          'oneOf': [
            {'type': 'string'},
          ],
        },
      },
    });
  });
}
