import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/grammar/json_schema_converter.dart';
import 'package:llamadart/src/core/template/response_format.dart';
import 'package:test/test.dart';

Map<String, dynamic> format(Object? schema) => {
  'type': 'json_schema',
  'json_schema': {'schema': schema},
};

void main() {
  const schema = {
    'type': 'object',
    'properties': {
      'ok': {'type': 'boolean'},
    },
  };

  group('responseFormatSchema', () {
    test('maps supported shapes to the constraining schema', () {
      expect(responseFormatSchema(null), isNull);
      expect(responseFormatSchema(const {'type': 'text'}), isNull);
      expect(responseFormatSchema(const {'type': 'json_object'}), {
        'type': 'object',
      });
      expect(
        responseFormatSchema(const {
          'type': 'json_schema',
          'json_schema': {
            'schema': schema,
            'name': 'status',
            'description': 'Status flag',
            'strict': true,
          },
        }),
        same(schema),
      );
    });

    test('treats null-valued keys as absent', () {
      expect(
        responseFormatSchema(const {'type': 'text', 'json_schema': null}),
        isNull,
      );
      expect(
        responseFormatSchema(const {'type': 'json_object', 'schema': null}),
        {'type': 'object'},
      );
      expect(
        responseFormatSchema(const {
          'type': 'json_schema',
          'schema': null,
          'json_schema': {
            'schema': schema,
            'name': null,
            'description': null,
            'strict': null,
            'schma': null,
          },
        }),
        same(schema),
      );
    });

    test('accepts LlamaStructuredOutput response formats', () {
      final output = LlamaStructuredOutput<Object?>.jsonValueSchema(
        schema: const {'type': 'array'},
        decoder: (value) => value,
        name: 'items',
        description: 'Items',
        strict: false,
      );

      expect(responseFormatSchema(output.responseFormat), {'type': 'array'});
    });

    for (final (format, message) in <(Map<String, dynamic>, String)>[
      (
        const {'type': 'json_shema'},
        "Unsupported responseFormat.type 'json_shema'; expected 'text', "
            "'json_object' or 'json_schema'.",
      ),
      (
        const {'json_object': true},
        "responseFormat.type must be one of 'text', 'json_object' or "
            "'json_schema'; got no type.",
      ),
      (
        const {'type': 'text', 'json_schema': schema},
        "Unsupported responseFormat key 'json_schema' for type 'text'; "
            'supported keys: type.',
      ),
      (
        const {
          'type': 'json_schema',
          'json_schema': {'schma': schema},
        },
        "Unsupported responseFormat.json_schema key 'schma' for type "
            "'json_schema'; supported keys: schema, name, description, strict.",
      ),
      (
        const {'type': 'json_schema', 'json_schema': 'x'},
        "responseFormat.json_schema must be an object with a 'schema' JSON "
            "object for type 'json_schema'.",
      ),
      (
        const {
          'type': 'json_schema',
          'json_schema': {'schema': schema, 'name': 1},
        },
        'responseFormat.json_schema.name must be a string.',
      ),
      (
        {
          'type': 'json_schema',
          'json_schema': {
            'schema': <dynamic, dynamic>{'type': 'object'},
          },
        },
        'responseFormat.json_schema.schema must be a JSON object typed '
            'Map<String, dynamic>, as jsonDecode returns or a '
            '<String, dynamic>{} literal declares; got '
            '${<dynamic, dynamic>{}.runtimeType}.',
      ),
      (
        const {
          'type': 'json_schema',
          'json_schema': {'schema': null},
        },
        'responseFormat.json_schema.schema must be a JSON object typed '
            'Map<String, dynamic>, as jsonDecode returns or a '
            '<String, dynamic>{} literal declares; got none.',
      ),
    ]) {
      test('rejects $format', () {
        expect(
          () => responseFormatSchema(format),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              message,
            ),
          ),
        );
      });
    }
  });

  group('responseFormatGrammar', () {
    Map<String, dynamic> nestedItems(int levels) {
      Map<String, dynamic> schema = {'type': 'integer'};
      for (var i = 0; i < levels; i++) {
        schema = {'type': 'array', 'items': schema};
      }
      return schema;
    }

    // 0.14 intentionally rejects constraints previously discarded by conversion.
    test('keeps the converter grammar for supported schemas', () {
      for (final schema in <Map<String, dynamic>>[
        {'type': 'string', 'pattern': r'^[a-zA-Z0-9]{9}$'},
        {'type': 'string', 'maxLength': 2000},
        {
          'type': 'object',
          'x-vendor': {'minimum': 1},
        },
      ]) {
        expect(responseFormatSchema(format(schema)), same(schema));
        expect(
          responseFormatGrammar(schema),
          JsonSchemaConverter.convert(schema),
        );
      }
    });

    test('reports unsupported schemas with paths before conversion', () {
      for (final (schema, path) in <(Map<String, dynamic>, String)>[
        ({r'$ref': 'https://example.com/s.json'}, r'$.$ref'),
        ({r'$ref': '#/missing'}, r'$.$ref'),
        ({'type': 'date'}, r'$.type'),
        ({'type': 'object', 'properties': 'x'}, r'$.properties'),
        (nestedItems(100000), r'$'),
      ]) {
        expect(
          () => responseFormatGrammar(schema),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'path',
              contains(path),
            ),
          ),
        );
      }
    });

    test('reports non-JSON values that stop conversion', () {
      final cyclic = <String, dynamic>{'type': 'object'};
      cyclic['properties'] = {'self': cyclic};
      for (final schema in <Map<String, dynamic>>[
        {'const': double.nan},
        {
          'enum': [DateTime(2026)],
        },
        {
          'const': {1: 'x'},
        },
        cyclic,
      ]) {
        expect(
          () => responseFormatGrammar(schema),
          throwsA(
            isA<LlamaArgumentException>().having(
              (error) => error.message,
              'message',
              contains('must contain only JSON values'),
            ),
          ),
        );
      }
    });

    test('reports a stack overflow from a long reference chain', () {
      const links = 20000;
      final schema = <String, dynamic>{
        r'$defs': {
          for (var i = 0; i < links; i++)
            'n$i': i == links - 1
                ? {'type': 'integer'}
                : {
                    'type': 'object',
                    'properties': {
                      'next': {r'$ref': '#/\$defs/n${i + 1}'},
                    },
                  },
        },
        r'$ref': r'#/$defs/n0',
      };
      expect(responseFormatSchema(format(schema)), same(schema));
      expect(
        () => responseFormatGrammar(schema),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(contains('Unsupported'), contains(r'$')),
          ),
        ),
      );
    });
  });
}
