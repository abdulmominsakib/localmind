import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/grammar/json_schema_converter.dart';
import 'package:llamadart/src/core/grammar/tool_grammar_generator.dart';
import 'package:llamadart/src/core/template/tool_call_parsing_utils.dart';
import 'package:llamadart/src/core/models/tools/tool_input_schema.dart';
import 'package:test/test.dart';

void main() {
  final rejected = <String, Map<String, dynamic>>{
    for (final keyword in [
      'format',
      'multipleOf',
      'uniqueItems',
      'contains',
      'minContains',
      'maxContains',
      'minProperties',
      'maxProperties',
      'patternProperties',
      'propertyNames',
      'dependentRequired',
      'dependentSchemas',
      'dependencies',
      'not',
      'if',
      'then',
      'else',
      'unevaluatedItems',
      'unevaluatedProperties',
      r'$dynamicRef',
      r'$recursiveRef',
    ])
      keyword: {'type': 'integer', keyword: keyword == 'multipleOf' ? 2 : 1},
    for (final format in ['email', 'int32'])
      'format $format': {'type': 'string', 'format': format},
    'pattern': {'type': 'string', 'pattern': r'^\w+$'},
    'unanchored pattern': {'type': 'string', 'pattern': 'abc'},
    'maxLength': {'type': 'string', 'maxLength': 3000},
    'minLength': {'type': 'string', 'minLength': 2001},
    'maxItems': {
      'type': 'array',
      'items': {'type': 'string'},
      'maxItems': 5000,
    },
    'minItems': {
      'type': 'array',
      'items': {'type': 'string'},
      'minItems': 2001,
    },
    'ref siblings': {r'$ref': r'#/$defs/s', 'maxLength': 4},
    'anyOf siblings': {
      'anyOf': [
        {'type': 'string'},
      ],
      'maxLength': 4,
    },
    'oneOf siblings': {
      'oneOf': [
        {'type': 'string'},
      ],
      'type': 'string',
    },
    'const siblings': {'const': 'abc', 'maxLength': 1},
    'enum siblings': {
      'enum': ['abc'],
      'pattern': '^a\$',
    },
    'literal type mismatch': {
      'type': 'integer',
      'enum': ['abc'],
    },
    'pattern siblings': {
      'type': 'string',
      'pattern': '^[a-z]+\$',
      'minLength': 3,
    },
    'tuple siblings': {
      'type': 'array',
      'prefixItems': [
        {'type': 'string'},
      ],
      'items': {'type': 'integer'},
    },
    'tuple bounds': {
      'type': 'array',
      'prefixItems': [
        {'type': 'string'},
      ],
      'maxItems': 0,
    },
    'allOf': {
      'allOf': [
        {'type': 'string', 'minLength': 3},
      ],
    },
    'undeclared required': {
      'type': 'object',
      'required': ['missing'],
    },
    'wrong context': {
      'type': 'string',
      'properties': {
        'x': {'type': 'string'},
      },
    },
    'null type': {'type': null},
    'null properties': {'type': 'object', 'properties': null},
    'null keyword': {'type': 'string', 'maxLength': null},
    'reference in items': {
      'type': 'array',
      'items': {r'$ref': '#/missing'},
    },
    'reference in extra properties': {
      'type': 'object',
      'additionalProperties': {r'$ref': '#/missing'},
    },
    'reference in tuple': {
      'type': 'array',
      'prefixItems': [
        {r'$ref': '#/missing'},
      ],
    },
    'reference in anyOf': {
      'anyOf': [
        {r'$ref': '#/missing'},
      ],
    },
    'reference in oneOf': {
      'oneOf': [
        {r'$ref': '#/missing'},
      ],
    },
    'reference in definitions': {
      r'$ref': '#/properties/value/definitions/s',
      'definitions': {
        's': {r'$ref': '#/missing'},
      },
    },
    'missing reference': {r'$ref': '#/missing'},
  };
  for (final entry in rejected.entries) {
    test('raw and typed reject ${entry.key} with a schema path', () {
      final schema = <String, dynamic>{
        'type': 'object',
        'properties': {'value': entry.value},
        r'$defs': {
          's': {'type': 'string'},
        },
      };
      final error = throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'schema path',
          contains(r'$.properties.value'),
        ),
      );
      expect(() => render(schema), error);
      expect(() => ToolGrammarGenerator.generateForSchema(schema), error);
      expect(
        () => LlamaStructuredOutput<Object?>.jsonValueSchema(
          schema: schema,
          decoder: (v) => v,
        ),
        error,
      );
    });
  }

  test('annotation payloads must also contain JSON values', () {
    final cycle = <Object?>[];
    cycle.add(cycle);
    for (final metadata in [DateTime(2026), cycle]) {
      final schema = <String, dynamic>{'type': 'string', 'x-data': metadata};
      expect(() => render(schema), throwsA(isA<LlamaArgumentException>()));
      expect(
        () => LlamaStructuredOutput<Object?>.jsonValueSchema(
          schema: schema,
          decoder: (v) => v,
        ),
        throwsA(isA<LlamaArgumentException>()),
      );
    }
  });

  test('empty imported tool properties still need an explicit type', () {
    expect(
      () => ToolDefinition.fromJsonSchema(
        name: 'inspect',
        description: 'Inspect',
        schema: {
          'type': 'object',
          'properties': {'value': <String, dynamic>{}},
        },
      ),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });

  test('annotation-only schemas accept any JSON value in both paths', () {
    final schema = <String, dynamic>{
      'description': 'Anything',
      'x-vendor': {'minimum': 1},
    };
    expect(render(schema), contains('root ::= value'));
    final output = LlamaStructuredOutput<Object?>.jsonValueSchema(
      schema: schema,
      decoder: (v) => v,
    );
    for (final value in [
      null,
      true,
      3,
      'text',
      <Object?>[],
      <String, dynamic>{},
    ]) {
      expect(output.parse(jsonEncode(value)), value);
    }
    expect(JsonSchemaConverter.convert({}), contains('root ::= object'));
    expect(
      render({
        'type': 'object',
        'properties': {'x': schema},
      }),
      contains('value'),
    );
  });

  test('allOf merges skip annotation-only components like upstream', () {
    const object = {
      'type': 'object',
      'properties': {
        'ok': {'type': 'boolean'},
      },
    };
    final grammar = render({
      'allOf': [object],
    });
    for (final neutral in <Map<String, dynamic>>[
      {'description': 'Base'},
      {
        'x-vendor': {'minimum': 1},
      },
      {},
    ]) {
      for (final schema in <Map<String, dynamic>>[
        {
          'allOf': [neutral, object],
        },
        {
          'type': 'object',
          r'$defs': {'neutral': neutral},
          'allOf': [
            object,
            {r'$ref': r'#/$defs/neutral'},
          ],
        },
      ]) {
        expect(render(schema), grammar, reason: '$schema');
        final output = LlamaStructuredOutput<Map<String, dynamic>>.jsonSchema(
          schema: schema,
          decoder: (json) => json,
        );
        expect(output.parse('{"ok":true}'), {'ok': true});
        for (final invalid in ['{"ok":1}', 'true', '[]']) {
          expect(
            () => output.parse(invalid),
            throwsA(isA<LlamaInferenceException>()),
            reason: invalid,
          );
        }
      }
    }
  });

  test('allOf without an object merge rejects annotation-only components', () {
    for (final schema in <Map<String, dynamic>>[
      {
        'allOf': [
          {'description': 'Base'},
        ],
      },
      {
        'allOf': [
          {'description': 'Base'},
          {
            'enum': ['a', 'b'],
          },
        ],
      },
      {
        'type': 'string',
        'allOf': [
          {
            'enum': ['a'],
          },
          {'title': 'Base'},
        ],
      },
    ]) {
      final error = throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('beside annotation-only components'),
        ),
      );
      expect(() => render(schema), error, reason: '$schema');
      expect(
        () => LlamaStructuredOutput<Object?>.jsonValueSchema(
          schema: schema,
          decoder: (value) => value,
        ),
        error,
        reason: '$schema',
      );
    }
  });

  test('compiled patterns agree with typed final validation', () {
    for (final schema in <Map<String, dynamic>>[
      {'type': 'string', 'pattern': r'^[a-z]{2,4}$'},
      {'pattern': r'^[a-z]{2,4}$'},
    ]) {
      expect(render(schema), contains('[a-z]'));
      final output = LlamaStructuredOutput<Object?>.jsonValueSchema(
        schema: schema,
        decoder: (v) => v,
      );
      expect(output.parse('"abc"'), 'abc');
      for (final invalid in [r'"abc\n"', '"A"', '3']) {
        expect(
          () => output.parse(invalid),
          throwsA(isA<LlamaInferenceException>()),
        );
      }
    }
  });

  test('annotation and extension siblings do not shadow assertions', () {
    for (final schema in <Map<String, dynamic>>[
      {
        'anyOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
        'x-note': true,
      },
      {
        'oneOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
        'title': 'Union',
      },
      {
        r'$ref': r'#/$defs/s',
        r'$defs': {
          's': {'type': 'string'},
        },
        'x-note': true,
      },
    ]) {
      expect(render(schema), isNotEmpty);
      final output = LlamaStructuredOutput<Object?>.jsonValueSchema(
        schema: schema,
        decoder: (v) => v,
      );
      expect(output.parse('"value"'), 'value');
    }
  });

  test('escaped local reference segments agree with typed parsing', () {
    final schema = <String, dynamic>{
      r'$ref': r'#/$defs/a~1b~0c',
      r'$defs': {
        'a/b~c': {'type': 'string'},
      },
    };
    expect(render(schema), contains('string'));
    final output = LlamaStructuredOutput<Object?>.jsonValueSchema(
      schema: schema,
      decoder: (v) => v,
    );
    expect(output.parse('"yes"'), 'yes');
    expect(() => output.parse('3'), throwsA(isA<LlamaInferenceException>()));
  });

  test('compatible literal types and metadata are accepted', () {
    for (final (type, value) in <(String, Object?)>[
      ('null', null),
      ('boolean', true),
      ('integer', 2),
      ('number', 2.5),
      ('string', 's'),
      ('object', <String, dynamic>{}),
      ('array', <Object?>[]),
    ]) {
      final schema = <String, dynamic>{
        'type': type,
        'const': value,
        'x-note': true,
      };
      expect(render(schema), isNotEmpty);
      final output = LlamaStructuredOutput<Object?>.jsonValueSchema(
        schema: schema,
        decoder: (v) => v,
      );
      expect(output.parse(jsonEncode(value)), value);
    }
  });

  test('schema JSON depth boundary includes annotations', () {
    Object? value = 0;
    for (var i = 0; i < 127; i++) {
      value = [value];
    }
    final schema = <String, dynamic>{'type': 'string', 'examples': value};
    expect(render(schema), isNotEmpty);
    expect(
      () => render({
        ...schema,
        'examples': [value],
      }),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });

  test('all response bounds accept 2000', () {
    for (final schema in <Map<String, dynamic>>[
      {'type': 'string', 'minLength': 2000, 'maxLength': 2000},
      {
        'type': 'array',
        'items': {'type': 'integer'},
        'minItems': 2000,
        'maxItems': 2000,
      },
    ]) {
      expect(render(schema), isNotEmpty);
      LlamaStructuredOutput<Object?>.jsonValueSchema(
        schema: schema,
        decoder: (v) => v,
      );
    }
  });

  // Raw JSON text, because the VM decodes int64 extremes to exact ints while
  // Web rounds them to the nearest double.
  for (final (keyword, bound) in [
    ('minimum', '-9223372036854775808'),
    ('exclusiveMinimum', '-9223372036854775808'),
    ('exclusiveMaximum', '-9223372036854775808'),
    ('maximum', '9223372036854775807'),
    ('minimum', '-9.3e18'),
    ('minimum', '-9007199254740992'),
    ('maximum', '9007199254740992'),
  ]) {
    final partner = keyword.endsWith('inimum') ? 'maximum' : 'minimum';
    for (final other in ['', ', "$partner": 0']) {
      final raw = '{"type": "integer", "$keyword": $bound$other}';
      test('raw and typed reject inexact integer bound $raw', () {
        final schema = <String, dynamic>{
          'type': 'object',
          'properties': {'value': jsonDecode(raw)},
        };
        final error = throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'bound path',
            contains(
              '\$.properties.value.$keyword must be a number within the '
              'exact VM/Web integer range',
            ),
          ),
        );
        expect(() => render(schema), error);
        expect(
          () => LlamaStructuredOutput<Object?>.jsonValueSchema(
            schema: schema,
            decoder: (v) => v,
          ),
          error,
        );
      });
    }
  }

  test('integer bounds at the exact VM/Web range limits are enforced', () {
    for (final schema in <Map<String, dynamic>>[
      {
        'type': 'integer',
        'minimum': -9007199254740991,
        'maximum': 9007199254740991,
      },
      {
        'type': 'integer',
        'exclusiveMinimum': -9007199254740991,
        'exclusiveMaximum': 9007199254740991,
      },
    ]) {
      final exclusive = schema.containsKey('exclusiveMinimum');
      final low = exclusive ? -9007199254740990 : -9007199254740991;
      final high = exclusive ? 9007199254740990 : 9007199254740991;
      expect(render(schema), isNotEmpty);
      final output = LlamaStructuredOutput<Object?>.jsonValueSchema(
        schema: schema,
        decoder: (v) => v,
      );
      for (final value in [low, 0, high]) {
        expect(output.parse('$value'), value);
      }
      for (final value in ['${low - 1}', '${high + 1}']) {
        expect(
          () => output.parse(value),
          throwsA(isA<LlamaInferenceException>()),
          reason: value,
        );
      }
    }
  });

  test('annotation-only tool properties preserve arbitrary values', () {
    final tool = ToolDefinition.fromJsonSchema(
      name: 'inspect',
      description: 'Inspect',
      schema: {
        'type': 'object',
        'properties': {
          'value': {'description': 'Anything', 'x-vendor': true},
        },
        'required': ['value'],
      },
    );
    expect(ToolGrammarGenerator.generate([tool])!.grammar, contains('value'));
    expect(
      tool.toJsonSchema()['properties']['value']['description'],
      'Anything',
    );
  });

  test('tool annotations and anyOf extensions retain validation', () {
    final tool = ToolDefinition.fromJsonSchema(
      name: 'inspect',
      description: 'Inspect',
      schema: {
        'type': 'object',
        'properties': {
          'value': {
            'anyOf': [
              {'description': 'Any'},
              {'type': 'integer'},
            ],
            'x-note': true,
            'readOnly': true,
          },
        },
      },
    );
    for (final value in [
      null,
      true,
      3,
      's',
      <Object?>[],
      <String, dynamic>{},
    ]) {
      expect(
        validateToolInputValue({'value': value}, tool.toJsonSchema()).valid,
        isTrue,
      );
    }
  });

  test(
    'deep model arguments fail through final and partial production parsing',
    () {
      final output =
          '<tool_call>{"name":"inspect","arguments":{"value":${'[' * 5000}0${']' * 5000}}}</tool_call>';
      for (final partial in [false, true]) {
        expect(
          () => ChatTemplateEngine.parse(
            ChatFormat.hermes.index,
            output,
            isPartial: partial,
          ),
          throwsA(isA<LlamaInferenceException>()),
        );
      }
    },
  );

  test('model arguments are bounded on direct, final and partial helpers', () {
    Object? value = 0;
    for (var i = 0; i < 5000; i++) {
      value = [value];
    }
    final error = throwsA(isA<LlamaInferenceException>());
    expect(() => ToolCallParsingUtils.encodeArguments(value), error);
    expect(
      () => ToolCallParsingUtils.createFunctionToolCall(
        index: 0,
        name: 'f',
        arguments: value,
      ),
      error,
    );
    expect(
      () => ToolCallParsingUtils.parseToolCallArray([
        {'name': 'f', 'arguments': value},
      ]),
      error,
    );
    final cycle = <Object?>[];
    cycle.add(cycle);
    expect(() => ToolCallParsingUtils.encodeArguments(cycle), error);
  });

  test('argument nesting accepts 128 and rejects 129', () {
    Object? value = 0;
    for (var i = 0; i < 128; i++) {
      value = [value];
    }
    expect(
      ToolCallParsingUtils.encodeArguments(value),
      '${'[' * 128}0${']' * 128}',
    );
    expect(
      () => ToolCallParsingUtils.encodeArguments([value]),
      throwsA(isA<LlamaInferenceException>()),
    );
    expect(
      ToolCallParsingUtils.encodeArguments('{"raw":true}'),
      '{"raw":true}',
    );
  });
}

String? render(Map<String, dynamic> schema) => ChatTemplateEngine.render(
  templateSource: null,
  messages: [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'JSON')],
  metadata: {},
  responseFormat: {
    'type': 'json_schema',
    'json_schema': {'schema': schema},
  },
).grammar;
