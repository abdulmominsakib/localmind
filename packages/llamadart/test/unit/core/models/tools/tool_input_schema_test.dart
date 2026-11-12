import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/models/tools/tool_input_schema.dart';
import 'package:test/test.dart';

import '../../../../support/raw_tool_schema_fixture.dart';

void main() {
  test('malformed null keywords are rejected rather than defaulted', () {
    for (final schema in <Map<String, dynamic>>[
      {'type': 'object', 'properties': null},
      {'type': 'object', 'required': null},
      {
        'type': 'object',
        'properties': {
          'x': {'type': null},
        },
      },
      {
        'type': 'object',
        'properties': {
          'x': {'anyOf': null},
        },
      },
      {
        'type': 'object',
        'properties': {
          'x': {'type': 'string', 'minLength': null},
        },
      },
    ]) {
      expect(
        () => ToolDefinition.fromJsonSchema(
          name: 'invalid',
          description: 'Invalid',
          schema: schema,
        ),
        throwsA(isA<LlamaArgumentException>()),
      );
    }
  });

  test(
    'open properties and numbers still require finite JSON values',
    () async {
      var calls = 0;
      final tool = ToolDefinition.fromJsonSchema(
        name: 'open',
        description: 'Open',
        schema: {'type': 'object'},
        handler: (_) async {
          calls++;
          return true;
        },
      );
      final cycle = <String, dynamic>{};
      cycle['self'] = cycle;
      for (final value in [
        double.nan,
        double.infinity,
        Object(),
        cycle,
        {1: true},
      ]) {
        await expectLater(
          tool.invoke({'extra': value}),
          throwsA(isA<LlamaArgumentException>()),
        );
      }
      expect(calls, 0);
      expect(
        await tool.invoke({
          'extra': [1, null, 'ok'],
        }),
        isTrue,
      );
    },
  );

  test('schema constructor owns input and returned maps', () {
    final source = <String, dynamic>{
      'type': 'object',
      'properties': {
        'q': {'type': 'string'},
      },
      'required': ['q'],
      'additionalProperties': false,
    };
    final tool = ToolDefinition.fromJsonSchema(
      name: 'search',
      description: 'Search',
      schema: source,
    );
    (source['properties'] as Map)['q'] = {'type': 'integer'};
    final first = tool.toJsonSchema();
    expect((first['properties'] as Map)['q'], {'type': 'string'});
    (first['properties'] as Map).clear();
    expect(tool.toJsonSchema()['properties'], {
      'q': {'type': 'string'},
    });
    expect(
      (tool.toJson()['function'] as Map)['parameters'],
      tool.toJsonSchema(),
    );
    expect(tool.parameters, isEmpty);
  });

  test(
    'raw JSON defaults remain open while legacy helper behavior stays closed',
    () {
      final tool = ToolDefinition.fromJsonSchema(
        name: 'open',
        description: 'Open',
        schema: {'type': 'object', 'properties': {}},
      );
      expect(tool.toJsonSchema()['additionalProperties'], isTrue);
      expect(
        validateToolInputValue({'extra': 42}, tool.toJsonSchema()).valid,
        isTrue,
      );
      const legacy = ToolDefinition(
        name: 'closed',
        description: 'Closed',
        parameters: [],
      );
      expect(
        legacy.toJsonSchema().containsKey('additionalProperties'),
        isFalse,
      );
      expect(
        validateToolInputValue({'extra': 42}, legacy.toJsonSchema()).valid,
        isFalse,
      );
    },
  );

  test(
    'schema-backed handler receives valid typed values and rejects invalid input',
    () async {
      var invocations = 0;
      final tool = rawSchemaTool(
        handler: (params) async {
          invocations++;
          return params.getInt('mode');
        },
      );
      expect(await tool.invoke(Map<String, dynamic>.from(rawToolArguments)), 2);
      await expectLater(
        Future.sync(() => tool.invoke({...rawToolArguments, 'mode': '2'})),
        throwsA(isA<LlamaArgumentException>()),
      );
      expect(invocations, 1);
    },
  );

  test(
    'handler remains optional and missing handler has the same state error',
    () async {
      final tool = rawSchemaTool();
      await expectLater(
        tool.invoke(Map<String, dynamic>.from(rawToolArguments)),
        throwsA(isA<LlamaStateException>()),
      );
    },
  );

  for (final schema in <Map<String, dynamic>>[
    {},
    {'type': 'string'},
    {'type': 'object', 'properties': []},
    {
      'type': 'object',
      'properties': {
        'x': {'type': 'invalid'},
      },
    },
    {
      'type': 'object',
      'properties': {
        'x': {'type': []},
      },
    },
    {
      'type': 'object',
      'properties': {
        '': {'type': 'string'},
      },
    },
    {
      'type': 'object',
      'required': ['missing'],
      'additionalProperties': false,
    },
    {
      'type': 'object',
      'required': [''],
    },
    {
      'type': 'object',
      'required': [1],
    },
    {
      'type': 'object',
      'required': ['x', 'x'],
    },
    {
      'type': 'object',
      'properties': {
        'x': {'type': 'string'},
      },
      'required': ['x', 'x'],
    },
    {
      'type': 'object',
      'properties': {
        'x': {'type': 'string', 'enum': []},
      },
    },
    {
      'type': 'object',
      'properties': {
        'x': {
          'type': 'string',
          'enum': ['a', 'a'],
        },
      },
    },
    {'type': 'object', 'properties': {}, 'additionalProperties': 42},
    {
      'type': 'object',
      'properties': {
        'x': {'type': 'string', 'minLength': -1},
      },
    },
    {
      'type': 'object',
      'properties': {
        'x': {
          'type': 'array',
          'items': {'type': 'string'},
          'minItems': 2,
          'maxItems': 1,
        },
      },
    },
    {
      'type': 'object',
      'properties': {
        'x': {'anyOf': []},
      },
    },
    {
      'type': 'object',
      'properties': {
        'x': {
          'anyOf': [true],
        },
      },
    },
  ]) {
    test('malformed schema is an argument error: $schema', () {
      expect(
        () => ToolDefinition.fromJsonSchema(
          name: 'invalid',
          description: 'Invalid',
          schema: schema,
        ),
        throwsA(isA<LlamaArgumentException>()),
      );
    });
  }

  for (final property in <Map<String, dynamic>>[
    {'type': 'number', 'minimum': 0},
    {'type': 'integer', 'maximum': 10},
    {'type': 'string', 'pattern': '^[a-z]+\$'},
    {
      'oneOf': [
        {'type': 'string'},
        {'type': 'null'},
      ],
    },
    {
      'allOf': [
        {'type': 'string'},
      ],
    },
    {r'$ref': 'https://example.invalid/schema.json'},
    {r'$ref': r'#/$defs/value'},
    {
      'type': 'array',
      'items': [
        {'type': 'string'},
      ],
    },
    {
      'type': 'string',
      'enum': [42],
    },
    {'type': 'string', 'const': true},
    {
      'enum': [{}],
    },
    {
      'type': 'string',
      'minLength': 1,
      'enum': ['a'],
    },
    {
      'anyOf': [
        {'type': 'string'},
      ],
      'type': 'string',
    },
    {'properties': {}},
    {
      'type': 'string',
      'items': {'type': 'string'},
    },
    {'type': 'integer', 'minLength': 2},
  ]) {
    test(
      'unsupported constraints fail rather than lose meaning: $property',
      () {
        expect(
          () => ToolDefinition.fromJsonSchema(
            name: 'unsupported',
            description: 'Unsupported',
            schema: {
              'type': 'object',
              'properties': {'x': property},
            },
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      },
    );
  }

  test(
    'nullable, numeric enums, containers and property policy validate together',
    () {
      final schema = rawSchemaTool().toJsonSchema();
      expect(validateToolInputValue(rawToolArguments, schema).valid, isTrue);
      for (final invalid in <Map<String, dynamic>>[
        {...rawToolArguments, 'code': 42},
        {...rawToolArguments, 'mode': '2'},
        {...rawToolArguments, 'mode': 3},
        {
          ...rawToolArguments,
          'nested': {'active': 'true'},
        },
        {...rawToolArguments, 'tags': []},
        {
          ...rawToolArguments,
          'tags': ['a', 'b', 'c'],
        },
        {
          ...rawToolArguments,
          'tags': [1],
        },
        {...rawToolArguments, 'extra': true},
        {...rawToolArguments}..remove('code'),
      ]) {
        expect(
          validateToolInputValue(invalid, schema).valid,
          isFalse,
          reason: '$invalid',
        );
      }
    },
  );

  test(
    'anyOf, scalar const, Unicode lengths and typed additional values validate',
    () {
      final tool = ToolDefinition.fromJsonSchema(
        name: 'union',
        description: 'Union',
        schema: {
          'type': 'object',
          'properties': {
            'value': {
              'anyOf': [
                {
                  'type': 'integer',
                  'enum': [1, 2],
                },
                {'type': 'null'},
              ],
            },
            'fixed': {'const': true},
            'text': {'type': 'string', 'minLength': 1, 'maxLength': 1},
          },
          'required': ['value', 'fixed', 'text'],
          'additionalProperties': {'type': 'boolean'},
        },
      );
      final schema = tool.toJsonSchema();
      expect(
        validateToolInputValue({
          'value': null,
          'fixed': true,
          'text': '😀',
          'extra': false,
        }, schema).valid,
        isTrue,
      );
      for (final invalid in [
        {'value': '2', 'fixed': true, 'text': 'a'},
        {'value': 3, 'fixed': true, 'text': 'a'},
        {'value': 1, 'fixed': false, 'text': 'a'},
        {'value': 1, 'fixed': true, 'text': ''},
        {'value': 1, 'fixed': true, 'text': 'ab'},
        {'value': 1, 'fixed': true, 'text': 'a', 'extra': 42},
      ]) {
        expect(validateToolInputValue(invalid, schema).valid, isFalse);
      }
    },
  );

  test(
    'required may name properties that only additionalProperties describes',
    () async {
      final source = <String, dynamic>{
        'type': 'object',
        'properties': {
          'city': {'type': 'string'},
          'nested': {
            'type': 'object',
            'required': ['id'],
            'additionalProperties': {'type': 'string'},
          },
        },
        'required': ['city', 'units', 'nested'],
      };
      Map<String, dynamic>? received;
      final tool = ToolDefinition.fromJsonSchema(
        name: 'lookup',
        description: 'Lookup',
        schema: source,
        handler: (params) async => received = params.raw,
      );
      final schema = tool.toJsonSchema();
      expect(schema['required'], ['city', 'units', 'nested']);
      expect((schema['properties'] as Map).keys, ['city', 'nested']);

      final args = <String, dynamic>{
        'city': 'Seoul',
        'units': {
          'scale': ['c'],
        },
        'nested': {'id': 'x'},
      };
      expect(await tool.invoke(args), args);
      expect(received, args);
      for (final units in [null, 1, 'c', true]) {
        expect(
          validateToolInputValue({...args, 'units': units}, schema).valid,
          isTrue,
          reason: '$units',
        );
      }
      for (final invalid in <Map<String, dynamic>>[
        {'city': 'Seoul', 'nested': args['nested']},
        {'city': 'Seoul', 'units': 'c', 'nested': <String, dynamic>{}},
        {
          'city': 'Seoul',
          'units': 'c',
          'nested': {'id': 1},
        },
      ]) {
        expect(
          validateToolInputValue(invalid, schema).valid,
          isFalse,
          reason: '$invalid',
        );
        await expectLater(
          tool.invoke(invalid),
          throwsA(isA<LlamaArgumentException>()),
        );
      }
    },
  );

  test('closed objects cannot require an undeclared property', () {
    for (final (schema, path) in <(Map<String, dynamic>, String)>[
      (
        {
          'type': 'object',
          'properties': {
            'city': {'type': 'string'},
          },
          'required': ['city', 'units'],
          'additionalProperties': false,
        },
        'input',
      ),
      (
        {
          'type': 'object',
          'properties': {
            'nested': {
              'type': 'object',
              'required': ['id'],
              'additionalProperties': false,
            },
          },
        },
        'input.nested',
      ),
    ]) {
      expect(
        () => ToolDefinition.fromJsonSchema(
          name: 'closed',
          description: 'Closed',
          schema: schema,
        ),
        throwsA(
          isA<LlamaArgumentException>().having(
            (error) => error.message,
            'message',
            allOf(contains('required at $path'), contains('false')),
          ),
        ),
      );
    }
  });

  test('non-JSON values fail with a typed argument error', () {
    final cycle = <Object?>[];
    cycle.add(cycle);
    for (final value in <Object?>[
      double.nan,
      [const MapEntry('a', 1)],
      {1: 'x'},
      cycle,
      Object(),
    ]) {
      expect(
        () => copyToolInputSchema({'type': 'object', 'default': value}),
        throwsA(isA<LlamaArgumentException>()),
        reason: '$value',
      );
    }
  });

  group('untrusted schema limits', () {
    ToolDefinition build(Map<String, dynamic> schema) =>
        ToolDefinition.fromJsonSchema(
          name: 'limited',
          description: 'Limited',
          schema: schema,
        );
    Map<String, dynamic> object(Map<String, dynamic> properties) => {
      'type': 'object',
      'properties': properties,
      'required': properties.keys.toList(),
      'additionalProperties': false,
    };
    Map<String, dynamic> nest(int depth) {
      Map<String, dynamic> schema = {'type': 'string'};
      for (var i = 0; i < depth; i++) {
        schema = object({'a': schema});
      }
      return schema;
    }

    Matcher unsupported(String message) => throwsA(
      isA<LlamaUnsupportedException>().having(
        (error) => error.message,
        'message',
        contains(message),
      ),
    );

    test('nesting is bounded without exhausting the stack', () {
      expect(() => build(nest(32)), returnsNormally);
      expect(() => build(nest(33)), unsupported('deeper than 32 levels'));
      expect(() => build(nest(20000)), unsupported('at most 128 levels'));
      Object deep = 'leaf';
      for (var i = 0; i < 200; i++) {
        deep = [deep];
      }
      expect(
        () => build(
          object({
            'x': {'type': 'string', 'default': deep},
          }),
        ),
        unsupported('at most 128 levels'),
      );
    });

    test('subschema count, alternatives, enums and names are bounded', () {
      Map<String, dynamic> wide(int count) => object({
        for (var i = 0; i < count; i++) 'p$i': {'type': 'string'},
      });
      expect(() => build(wide(1023)), returnsNormally);
      expect(() => build(wide(1024)), unsupported('at most 1024 subschemas'));

      Map<String, dynamic> alternatives(int count) => object({
        'x': {
          'anyOf': [
            for (var i = 0; i < count; i++) {'const': i},
          ],
        },
      });
      expect(() => build(alternatives(64)), returnsNormally);
      expect(
        () => build(alternatives(65)),
        unsupported('anyOf at input.x has 65 alternatives; the limit is 64'),
      );

      Map<String, dynamic> enumerated(int count) => object({
        'x': {
          'enum': [for (var i = 0; i < count; i++) i],
        },
      });
      expect(() => build(enumerated(1024)), returnsNormally);
      expect(
        () => build(enumerated(1025)),
        unsupported('enum at input.x has 1025 values; the limit is 1024'),
      );

      expect(
        () => build(
          object({
            '😀' * 128: {'type': 'string'},
          }),
        ),
        returnsNormally,
      );
      expect(
        () => build(
          object({
            'a' * 129: {'type': 'string'},
          }),
        ),
        unsupported('at most 128 characters'),
      );
      expect(
        () => build({
          'type': 'object',
          'required': ['😀' * 128],
        }),
        returnsNormally,
      );
      expect(
        () => build({
          'type': 'object',
          'required': ['a' * 129],
        }),
        unsupported('at most 128 characters'),
      );
    });

    test('undeclared required names share the subschema budget', () {
      // Every name maps to the same grammar rule name, the worst case for
      // rule-name collision handling.
      List<String> colliding(int count) => [
        for (var i = 0; i < count; i++)
          'a${i.toRadixString(2).replaceAll('0', '!').replaceAll('1', '#')}',
      ];
      Map<String, dynamic> open(int declared, int undeclared) => {
        'type': 'object',
        'properties': {
          for (var i = 0; i < declared; i++) 'p$i': {'type': 'string'},
        },
        'required': colliding(undeclared),
      };
      const limit = 'at most 1024 subschemas and undeclared required';

      expect(() => build(open(0, 1023)), returnsNormally);
      expect(() => build(open(0, 1024)), unsupported(limit));
      expect(() => build(open(512, 511)), returnsNormally);
      expect(() => build(open(512, 512)), unsupported(limit));
      expect(() => build(open(0, 8000)), unsupported(limit));
    });

    test('generated grammar size is bounded', () {
      expect(
        () => build(
          object({
            'x': {
              'enum': [for (var i = 0; i < 1000; i++) '$i${'v' * 300}'],
            },
          }),
        ),
        unsupported('the limit is 262144'),
      );
    });

    for (final keyword in ['minLength', 'maxLength', 'minItems', 'maxItems']) {
      test('$keyword stays within the llama.cpp repetition limit', () {
        Map<String, dynamic> bounded(int bound) => object({
          'x': keyword.endsWith('Length')
              ? {'type': 'string', keyword: bound}
              : {
                  'type': 'array',
                  'items': {'type': 'string'},
                  keyword: bound,
                },
        });
        for (final bound in [0, 1999, 2000]) {
          expect(() => build(bounded(bound)), returnsNormally);
        }
        expect(
          () => build(bounded(2001)),
          unsupported(
            '$keyword at input.x is 2001; llama.cpp grammars accept at most 2000',
          ),
        );
      });
    }

    for (final suffix in ['Length', 'Items']) {
      for (final minimum in [true, false]) {
        final keyword = '${minimum ? 'min' : 'max'}$suffix';
        test('$keyword 2000 still validates tool input values', () {
          final schema = build(
            object({
              'x': suffix == 'Length'
                  ? {'type': 'string', keyword: 2000}
                  : {
                      'type': 'array',
                      'items': {'type': 'string'},
                      keyword: 2000,
                    },
            }),
          ).toJsonSchema();
          for (final count in [1999, 2000, 2001]) {
            final value = suffix == 'Length'
                ? 'a' * count
                : List.filled(count, 'a');
            expect(
              validateToolInputValue({'x': value}, schema).valid,
              minimum ? count >= 2000 : count <= 2000,
              reason: '$keyword with $count values',
            );
          }
        });
      }
    }

    test('deep values validate without exhausting the stack', () {
      Object deep = 'leaf';
      for (var i = 0; i < 100000; i++) {
        deep = [deep];
      }
      final schema = build({'type': 'object'}).toJsonSchema();
      expect(validateToolInputValue({'x': deep}, schema).valid, isTrue);
      final cycle = <Object?>[];
      cycle.add(cycle);
      expect(validateToolInputValue({'x': cycle}, schema).valid, isFalse);
    });
  });
}
