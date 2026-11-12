import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/grammar/json_schema_converter.dart';
import 'package:llamadart/src/core/grammar/response_schema_validation.dart';
import 'package:llamadart/src/core/template/response_format.dart';
import 'package:test/test.dart';

import '../../../support/pydantic_audit_schemas.dart';

LlamaStructuredOutput<Object?> typed(Map<String, dynamic> schema) =>
    LlamaStructuredOutput<Object?>.jsonValueSchema(
      schema: schema,
      decoder: (v) => v,
    );

void main() {
  for (final format in ['uuid1', 'uuid2', 'uuid3', 'uuid4', 'uuid5']) {
    test('UUID alias $format follows upstream on raw and typed paths', () {
      for (final hasType in [false, true]) {
        final schema = <String, dynamic>{
          if (hasType) 'type': 'string',
          'format': format,
        };
        expect(
          responseFormatGrammar(schema),
          responseFormatGrammar({'type': 'string', 'format': 'uuid'}),
        );
        final output = typed(schema);
        const valid = 'ABCDEFAB-ABCD-ABCD-ABCD-ABCDEFABCDEF';
        expect(output.parse(jsonEncode(valid)), valid);
        for (final invalid in [
          '"bad"',
          '"GBCDEFAB-ABCD-ABCD-ABCD-ABCDEFABCDEF"',
          '3',
        ]) {
          expect(
            () => output.parse(invalid),
            throwsA(isA<LlamaInferenceException>()),
          );
        }
      }
    });
  }

  for (final (schema, value) in <(Map<String, dynamic>, String)>[
    ({'type': 'array', 'uniqueItems': false}, '[1,1]'),
    ({'type': 'object', 'minProperties': 0}, '{}'),
    ({'type': 'integer', 'multipleOf': 1}, '3'),
    ({'const': 3, 'type': 'number'}, '3'),
  ]) {
    test(
      'trivial assertions and integer number literals remain accepted: $schema',
      () {
        expect(responseFormatGrammar(schema), isNotEmpty);
        expect(typed(schema).parse(value), jsonDecode(value));
      },
    );
  }

  test('trivial assertion siblings do not shadow supported dispatch', () {
    for (final base in <Map<String, dynamic>>[
      {'const': 's'},
      {
        'enum': ['s'],
      },
      {
        'anyOf': [
          {'const': 's'},
        ],
      },
      {
        'allOf': [
          {
            'enum': ['s'],
          },
        ],
      },
      {
        r'$ref': r'#/$defs/S',
        r'$defs': {
          'S': {'const': 's'},
        },
      },
    ]) {
      final schema = {...base, 'uniqueItems': false, 'minProperties': 0};
      expect(responseFormatGrammar(schema), responseFormatGrammar(base));
      expect(typed(schema).parse('"s"'), 's');
    }
    for (final schema in <Map<String, dynamic>>[
      {'type': 'integer', 'multipleOf': 2},
      {'type': 'number', 'multipleOf': 1},
      {'multipleOf': 1},
      {'type': 'array', 'uniqueItems': true},
      {'type': 'object', 'minProperties': 1},
    ]) {
      expect(
        () => responseFormatGrammar(schema),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(() => typed(schema), throwsA(isA<LlamaUnsupportedException>()));
    }
  });

  test('bare minimum array bounds require an item', () {
    final schema = <String, dynamic>{'type': 'array', 'minItems': 1};
    expect(
      responseFormatGrammar(schema),
      contains('root-item ("," space root-item)*'),
    );
    expect(typed(schema).parse('[null]'), [null]);
    expect(
      () => typed(schema).parse('[]'),
      throwsA(isA<LlamaInferenceException>()),
    );
  });

  test('bare maximum array bounds allow empty arrays', () {
    final schema = <String, dynamic>{'type': 'array', 'maxItems': 1};
    expect(responseFormatGrammar(schema), contains('root-item'));
    expect(typed(schema).parse('[]'), isEmpty);
    expect(
      () => typed(schema).parse('[1,2]'),
      throwsA(isA<LlamaInferenceException>()),
    );
  });

  test('array bounds without items constrain arbitrary JSON values', () {
    final schema = <String, dynamic>{
      'type': 'array',
      'minItems': 1,
      'maxItems': 2,
    };
    expect(
      responseFormatGrammar(schema),
      contains(
        'root-item ::= object | array | string | number | boolean | null',
      ),
    );
    final output = typed(schema);
    for (final value in ['[1]', '["s",null]', '[{}]', '[[true]]']) {
      expect(output.parse(value), jsonDecode(value));
    }
    for (final value in ['[]', '[1,2,3]']) {
      expect(
        () => output.parse(value),
        throwsA(isA<LlamaInferenceException>()),
      );
    }
  });

  for (final key in [r'$defs', 'definitions']) {
    test('unused $key assertions and references are ignored', () {
      final schema = <String, dynamic>{
        'type': 'string',
        key: {
          'unused': {
            'not': {'type': 'integer'},
          },
          'missing': {r'$ref': '#/missing'},
          'malformed': {'enum': 1},
          'notSchema': 1,
        },
      };
      expect(
        responseFormatGrammar(schema),
        responseFormatGrammar({'type': 'string'}),
      );
      expect(typed(schema).parse('"s"'), 's');
      final referenced = <String, dynamic>{
        r'$ref': '#/$key/unused',
        key: schema[key],
      };
      final error = throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'path',
          contains(r'$.$ref.not'),
        ),
      );
      expect(() => responseFormatGrammar(referenced), error);
      expect(() => typed(referenced), error);
    });
  }

  test(
    'referenced recursive definitions validate once and parse finite values',
    () {
      final schema = <String, dynamic>{
        r'$ref': r'#/$defs/Node',
        r'$defs': {
          'Node': {
            'type': 'object',
            'properties': {
              'children': {
                'type': 'array',
                'items': {r'$ref': r'#/$defs/Node'},
              },
            },
            'required': ['children'],
          },
        },
      };
      expect(responseFormatGrammar(schema), contains('ref-defs-Node'));
      expect(typed(schema).parse('{"children":[{"children":[]}]}'), {
        'children': [
          {'children': <Object?>[]},
        ],
      });
    },
  );

  test('allOf ref into non-schema enum reports the reference path', () {
    for (final type in [null, 'string']) {
      final schema = <String, dynamic>{
        'type': ?type,
        'allOf': [
          {r'$ref': '#/annotation'},
        ],
        'annotation': {'enum': 1},
      };
      final error = throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'path',
          contains(r'$.allOf[0].$ref'),
        ),
      );
      expect(() => responseFormatGrammar(schema), error);
      expect(() => typed(schema), error);
    }
  });

  test('audit Pydantic 2.13.4: real tuple and discriminator emissions', () {
    final corpus = jsonDecode(pydanticAuditSchemas) as Map<String, dynamic>;
    for (final schema in corpus.values.cast<Map<String, dynamic>>()) {
      expect(responseFormatGrammar(schema), isNotEmpty);
      typed(schema);
    }
    final tuple = typed(corpus['pydantic_tuple'] as Map<String, dynamic>);
    expect(tuple.parse('{"pair":[1,"s"]}'), {
      'pair': [1, 's'],
    });
    expect(
      () => tuple.parse('{"pair":[1]}'),
      throwsA(isA<LlamaInferenceException>()),
    );
    final union = typed(
      corpus['pydantic_discriminator'] as Map<String, dynamic>,
    );
    expect(union.parse('{"pet":{"pet_type":"cat","meows":1}}'), {
      'pet': {'pet_type': 'cat', 'meows': 1},
    });
    expect(
      () => union.parse('{"pet":{"pet_type":"bird","meows":1}}'),
      throwsA(isA<LlamaInferenceException>()),
    );
  });

  test('audit guards: unsupported and shadowed constraints retain paths', () {
    for (final leaf in <Map<String, dynamic>>[
      {
        'type': 'array',
        'items': [
          {'type': 'integer'},
        ],
        'minItems': 2,
      },
      {
        'type': 'array',
        'prefixItems': [
          {'type': 'integer'},
        ],
        'maxItems': 0,
      },
      {'type': 'array', 'prefixItems': [], 'items': {}},
      {'type': 'string', 'format': 'email'},
      for (final key in ['pattern', 'minLength', 'maxLength'])
        {
          'type': 'string',
          'format': 'uuid',
          key: key == 'pattern' ? r'^a$' : 2,
        },
      {'type': 'integer', 'format': 'uuid'},
      {
        'type': 'integer',
        'allOf': [
          {'properties': {}},
        ],
      },
      {'type': 'number', 'minimum': 0},
      {'minimum': 0},
      {
        'type': ['integer', 'number'],
        'minimum': 0,
      },
      {
        'type': 'integer',
        'enum': [1.5],
      },
      {'type': 'integer', 'const': 1.5},
      {'type': 'integer', 'minimum': 100},
      {'type': 'integer', 'minimum': 2222222222222222},
      {'type': 'integer', 'maximum': -2222222222222222},
      {'type': 'integer', 'minimum': 101},
      {'type': 'integer', 'minimum': 1205},
      {'type': 'integer', 'maximum': -100},
      {'type': 'integer', 'maximum': -201},
      {'type': 'integer', 'minimum': '0'},
      {'type': 'integer', 'minimum': 9007199254740992},
      {'type': 'integer', 'minimum': 1000000000000000},
      {'type': 'integer', 'maximum': -1000000000000000},
      {'type': 'integer', 'exclusiveMaximum': -9007199254740991},
      {'type': 'integer', 'exclusiveMinimum': 9007199254740991},
      {'type': 'integer', 'minimum': 3, 'maximum': 2},
      {'type': 'integer', 'minimum': 1, 'exclusiveMinimum': 2},
      {'type': 'integer', 'maximum': 3, 'exclusiveMaximum': 2},
      {
        'type': 'string',
        'allOf': [
          {'properties': {}},
        ],
      },
      {
        'type': 'string',
        'allOf': [
          {
            'enum': [1],
          },
        ],
      },
      {
        'allOf': [
          {
            'enum': ['a'],
          },
          {
            'enum': ['b'],
          },
        ],
      },
      {
        'allOf': [
          {
            'enum': ['a'],
          },
          {'properties': {}},
        ],
      },
      {
        'type': 'integer',
        'allOf': [
          {
            'enum': ['a'],
          },
        ],
      },
      {
        'type': 'object',
        'allOf': [
          {
            'enum': ['a'],
          },
        ],
      },
      {
        'allOf': [
          {'properties': {}},
        ],
        'properties': {},
      },
      {
        'allOf': [
          {'type': 'string', 'minLength': 1},
        ],
      },
      {
        'allOf': [
          {
            'properties': {
              'a': {'type': 'string'},
            },
          },
          {
            'properties': {
              'a': {'type': 'integer'},
            },
          },
        ],
      },
      {
        'allOf': [
          {
            'properties': {},
            'additionalProperties': {'type': 'string'},
          },
        ],
      },
      {
        'allOf': [
          {
            'properties': {},
            'allOf': [
              {'properties': {}},
            ],
          },
        ],
      },
      {
        'allOf': [
          {r'$ref': r'#/$defs/S'},
        ],
        r'$defs': {
          'S': {r'$ref': r'#/$defs/S'},
        },
      },
      {
        'allOf': [
          {r'$ref': '#/missing'},
        ],
      },
    ]) {
      final schema = <String, dynamic>{
        'type': 'object',
        'properties': {'value': leaf},
      };
      final error = throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'path',
          contains(r'$.properties.value'),
        ),
      );
      expect(() => responseFormatGrammar(schema), error, reason: '$leaf');
      expect(() => typed(schema), error, reason: '$leaf');
    }
  });

  test('audit boundaries: tuples, refs and integer intervals', () {
    for (final key in ['items', 'prefixItems']) {
      final output = typed({
        'type': 'array',
        key: [],
        'minItems': 0,
        'maxItems': 0,
      });
      expect(output.parse('[]'), isEmpty);
      expect(
        () => output.parse('[1]'),
        throwsA(isA<LlamaInferenceException>()),
      );
    }
    for (final schema in <Map<String, dynamic>>[
      {'type': 'integer', 'minimum': 0, 'maximum': 0},
      {
        'type': 'integer',
        'minimum': 0,
        'exclusiveMinimum': -1,
        'maximum': 0,
        'exclusiveMaximum': 1,
      },
      {
        'allOf': [
          {'properties': {}, 'additionalProperties': true},
        ],
      },
      {
        'allOf': [
          {
            'enum': [1, 1],
          },
          {
            'enum': [1],
          },
        ],
      },
    ]) {
      expect(responseFormatGrammar(schema), isNotEmpty);
      typed(schema);
    }
  });

  for (final key in ['prefixItems', 'items']) {
    test('audit tuples: $key retains exact grammar and typed validation', () {
      final tuple = [
        {'type': 'integer'},
        {'type': 'string'},
      ];
      for (final bounds in [
        <String, dynamic>{},
        {'minItems': 0},
        {'minItems': 2, 'maxItems': 2},
        {'maxItems': 3},
      ]) {
        final schema = <String, dynamic>{
          'type': 'array',
          key: tuple,
          ...bounds,
        };
        expect(
          responseFormatGrammar(schema),
          JsonSchemaConverter.convert({'type': 'array', key: tuple}),
        );
        final output = typed(schema);
        expect(output.parse('[1,"s"]'), [1, 's']);
        for (final invalid in ['[]', '[1]', '[1,"s",2]', '["x","s"]']) {
          expect(
            () => output.parse(invalid),
            throwsA(isA<LlamaInferenceException>()),
          );
        }
      }
    });
  }

  for (final key in [
    'discriminator',
    'contentMediaType',
    'contentEncoding',
    'example',
    'examples',
    r'$anchor',
    r'$id',
    r'$schema',
    r'$comment',
    'deprecated',
    'readOnly',
    'writeOnly',
    'title',
    'description',
    'default',
    'vendorKeyword',
  ]) {
    test('audit annotations: $key is ignored beside assertions and refs', () {
      for (final base in <Map<String, dynamic>>[
        {'type': 'string'},
        {'const': 's'},
        {
          'anyOf': [
            {'type': 'string'},
          ],
        },
        {
          r'$ref': r'#/$defs/S',
          r'$defs': {
            'S': {'type': 'string'},
          },
        },
      ]) {
        final schema = {
          ...base,
          key: {'minimum': 3, r'$ref': '#/not-a-schema'},
        };
        expect(responseFormatGrammar(schema), responseFormatGrammar(base));
        expect(typed(schema).parse('"s"'), 's');
      }
      expect(typed({key: null}).parse('3'), 3);
    });
  }

  test(
    'audit dynamic maps: normalize caller properties and reference targets',
    () {
      final props = <dynamic, dynamic>{
        'value': <dynamic, dynamic>{r'$ref': r'#/$defs/S'},
      };
      final schema = <String, dynamic>{
        'type': 'object',
        'properties': props,
        r'$defs': <dynamic, dynamic>{
          'S': <dynamic, dynamic>{'type': 'string'},
        },
        'required': ['value'],
      };
      validateResponseSchema(schema);
      final normalized = jsonDecode(jsonEncode(schema)) as Map<String, dynamic>;
      expect(responseFormatGrammar(schema), responseFormatGrammar(normalized));
      final output = typed(schema);
      props.clear();
      expect(output.parse('{"value":"s"}'), {'value': 's'});
      expect(
        () => output.parse('{"value":3}'),
        throwsA(isA<LlamaInferenceException>()),
      );
    },
  );

  test('audit typed dynamic maps: normalize before schema validation', () {
    final schema = <String, dynamic>{
      r'$ref': r'#/$defs/S',
      r'$defs': <dynamic, dynamic>{
        'S': <dynamic, dynamic>{
          'type': 'object',
          'properties': <dynamic, dynamic>{
            'value': <dynamic, dynamic>{'type': 'string'},
          },
          'required': ['value'],
        },
      },
    };
    final output = typed(schema);
    expect(output.parse('{"value":"s"}'), {'value': 's'});
    expect(
      () => output.parse('{"value":3}'),
      throwsA(isA<LlamaInferenceException>()),
    );
  });

  test('audit dynamic maps: invalid nested refs are validated directly', () {
    final schema = <String, dynamic>{
      'type': 'object',
      'properties': <dynamic, dynamic>{
        'value': <dynamic, dynamic>{r'$ref': '#/missing'},
      },
    };
    final error = throwsA(
      isA<LlamaUnsupportedException>().having(
        (e) => e.message,
        'path',
        contains(r'$.properties.value.$ref'),
      ),
    );
    expect(() => validateResponseSchema(schema), error);
    expect(() => responseFormatGrammar(schema), error);
    expect(() => typed(schema), error);
  });

  for (final (format, valid, invalid) in [
    ('uuid', '12345678-1234-abcd-ABCD-123456789abc', 'not-a-uuid'),
    ('date', '2026-10-16', '2026-13-01'),
    ('time', '23:59:59.123+02:30', '24:00:00Z'),
    ('date-time', '2026-10-16T00:00:00Z', '2026-10-16 00:00:00Z'),
  ]) {
    test('audit formats: $format compiles and validates final values', () {
      for (final hasType in [true, false]) {
        final schema = <String, dynamic>{
          if (hasType) 'type': 'string',
          'format': format,
        };
        expect(responseFormatGrammar(schema), isNot(contains('char*')));
        final output = typed(schema);
        expect(output.parse(jsonEncode(valid)), valid);
        expect(
          () => output.parse(jsonEncode(invalid)),
          throwsA(isA<LlamaInferenceException>()),
        );
        expect(
          () => output.parse('3'),
          throwsA(isA<LlamaInferenceException>()),
        );
      }
    });
  }

  for (final (keyword, bound, yes, no) in <(String, num, int, int)>[
    ('minimum', 1.2, 2, 1),
    ('maximum', -1.2, -2, -1),
    ('exclusiveMinimum', -1.2, -1, -2),
    ('exclusiveMaximum', 1.2, 1, 2),
    ('exclusiveMinimum', 1, 2, 1),
    ('exclusiveMaximum', -1, -2, -1),
  ]) {
    test('audit integer bounds: $keyword $bound', () {
      final schema = <String, dynamic>{'type': 'integer', keyword: bound};
      expect(responseFormatGrammar(schema), isNot(contains('integral-part')));
      final output = typed(schema);
      expect(output.parse('$yes'), yes);
      expect(
        () => output.parse('$no'),
        throwsA(isA<LlamaInferenceException>()),
      );
    });
  }

  test('audit allOf: object references enforce merged properties', () {
    final schema = <String, dynamic>{
      r'$defs': {
        'S': {
          'type': 'object',
          'properties': {
            's': {'type': 'string'},
          },
          'required': ['s'],
        },
      },
      'allOf': [
        {r'$ref': r'#/$defs/S'},
        {
          'type': 'object',
          'properties': {
            'n': {'type': 'integer'},
          },
          'required': ['n'],
        },
      ],
    };
    expect(responseFormatGrammar(schema), JsonSchemaConverter.convert(schema));
    expect(responseFormatGrammar(schema), isNot(contains('additional-kv')));
    final output = typed(schema);
    expect(output.parse('{"s":"a","n":1}'), {'s': 'a', 'n': 1});
    expect(
      () => output.parse('{"s":1,"n":1}'),
      throwsA(isA<LlamaInferenceException>()),
    );
    expect(
      () => output.parse('{"s":"a"}'),
      throwsA(isA<LlamaInferenceException>()),
    );
  });

  test('audit allOf: single closed object and bare object compile', () {
    for (final component in <Map<String, dynamic>>[
      {'type': 'object'},
      {
        'type': 'object',
        'properties': {
          'a': {'type': 'integer'},
        },
        'required': ['a'],
        'additionalProperties': false,
      },
    ]) {
      final schema = <String, dynamic>{
        'allOf': [component],
      };
      expect(responseFormatGrammar(schema), isNot(contains('additional-kv')));
      final output = typed(schema);
      expect(
        output.parse(component.containsKey('properties') ? '{"a":1}' : '{}'),
        isA<Map>(),
      );
    }
  });

  test('audit allOf: explicit string enum type', () {
    final schema = <String, dynamic>{
      'type': 'string',
      'allOf': [
        {
          'enum': ['a', 'b'],
        },
        {
          'enum': ['a'],
        },
      ],
    };
    expect(responseFormatGrammar(schema), contains(r'\"a\"'));
    expect(typed(schema).parse('"a"'), 'a');
  });

  test('audit allOf: enum intersection includes local refs', () {
    final schema = <String, dynamic>{
      r'$defs': {
        'E': {
          'enum': ['b', 'a'],
        },
      },
      'allOf': [
        {r'$ref': r'#/$defs/E'},
        {
          'enum': ['a', 'c'],
        },
      ],
    };
    expect(responseFormatGrammar(schema), contains(r'("\"a\"")'));
    final output = typed(schema);
    expect(output.parse('"a"'), 'a');
    expect(() => output.parse('"b"'), throwsA(isA<LlamaInferenceException>()));
  });

  for (final (ref, payload) in <(String, Map<String, dynamic>)>[
    (
      '#/x-hidden',
      {
        'x-hidden': {'type': 'integer', 'multipleOf': 2},
      },
    ),
    (
      '#/properties/b/default',
      {
        'properties': {
          'b': {
            'type': 'object',
            'default': {'type': 'integer', 'multipleOf': 2},
          },
        },
      },
    ),
    (
      '#/examples/0',
      {
        'examples': [
          {'type': 'string'},
        ],
      },
    ),
  ]) {
    test('audit reference targets: reject annotation target $ref', () {
      final schema = <String, dynamic>{...payload, r'$ref': ref};
      // Use a schema-bearing sibling for the default target rather than a ref sibling.
      final wrapped = <String, dynamic>{
        ...payload,
        'type': 'object',
        'properties': {
          ...?payload['properties'] as Map<String, dynamic>?,
          'a': {r'$ref': ref},
        },
      };
      for (final value in [
        wrapped,
        if (!schema.containsKey('properties')) schema,
      ]) {
        final matcher = throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'path',
            contains(r'$ref'),
          ),
        );
        expect(() => responseFormatGrammar(value), matcher);
        expect(() => typed(value), matcher);
      }
    });
  }

  test('audit schema positions: refs can target tuple and union entries', () {
    for (final key in ['items', 'prefixItems', 'anyOf', 'oneOf', 'allOf']) {
      final schema = <String, dynamic>{
        r'$ref': '#/\$defs/S/$key/0',
        r'$defs': {
          'S': {
            if (key == 'items' || key == 'prefixItems') 'type': 'array',
            key: [
              key == 'allOf'
                  ? {
                      'enum': ['s'],
                    }
                  : {'type': 'string'},
            ],
          },
        },
      };
      validateResponseSchema(schema);
      expect(responseFormatGrammar(schema), isNotEmpty);
      expect(typed(schema).parse('"s"'), 's');
    }
  });

  test('audit schema positions: object-root helper follows array pointers', () {
    final schema = <String, dynamic>{
      r'$ref': r'#/$defs/S/items/0',
      r'$defs': {
        'S': {
          'type': 'array',
          'items': [
            {
              'type': 'object',
              'properties': {
                'a': {'type': 'integer'},
              },
              'required': ['a'],
            },
          ],
        },
      },
    };
    final output = LlamaStructuredOutput<Map<String, dynamic>>.jsonSchema(
      schema: schema,
      decoder: (v) => v,
    );
    expect(output.parse('{"a":1}'), {'a': 1});
    expect(
      () => output.parse('{"a":"s"}'),
      throwsA(isA<LlamaInferenceException>()),
    );
  });

  test('audit integer enum: 1.0 is an integer on VM and Web', () {
    for (final keyword in ['enum', 'const']) {
      final schema = <String, dynamic>{
        'type': 'integer',
        keyword: keyword == 'enum' ? [1.0] : 1.0,
      };
      expect(responseFormatGrammar(schema), isNotEmpty);
      expect(typed(schema).parse('1'), 1);
      expect(
        () => typed(schema).parse('1.5'),
        throwsA(isA<LlamaInferenceException>()),
      );
    }
  });

  test(
    'audit typed converter errors identify LlamaStructuredOutput.schema',
    () {
      final schema = <String, dynamic>{
        r'$ref': r'#/$defs/s0',
        r'$defs': {
          for (var i = 0; i < 20000; i++)
            's$i': {r'$ref': '#/\$defs/s${i + 1}'},
          's20000': {'type': 'string'},
        },
      };
      expect(
        () => typed(schema),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'typed prefix',
            startsWith(
              'Unsupported LlamaStructuredOutput.schema JSON schema at \$',
            ),
          ),
        ),
      );
    },
  );
}
