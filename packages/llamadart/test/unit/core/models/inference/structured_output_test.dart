import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  group('LlamaStructuredOutput', () {
    test('builds responseFormat and decodes typed object output', () {
      final output = LlamaStructuredOutput<_Contact>.jsonSchema(
        name: 'contact',
        schema: const {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'email': {'type': 'string'},
          },
          'required': ['name', 'email'],
          'additionalProperties': false,
        },
        decoder: _Contact.fromJson,
      );

      expect(output.responseFormat['type'], 'json_schema');
      expect(output.responseFormat['json_schema']['name'], 'contact');

      final contact = output.parse(
        '{"name":"Ada Lovelace","email":"ada@example.com"}',
      );

      expect(contact.name, 'Ada Lovelace');
      expect(contact.email, 'ada@example.com');
    });

    test('accepts JSON Schema annotation metadata', () {
      final output = LlamaStructuredOutput<Map<String, dynamic>>.jsonSchema(
        schema: const {
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          r'$id': 'https://example.com/contact.schema.json',
          r'$comment': 'Annotations are ignored by constrained decoding.',
          'title': 'Contact',
          'description': 'Extracted contact fields.',
          'type': 'object',
          'properties': {
            'name': {
              'title': 'Name',
              'description': 'Display name.',
              'type': 'string',
              'default': 'Unknown',
              'examples': ['Ada Lovelace'],
            },
          },
          'required': ['name'],
          'additionalProperties': false,
          'readOnly': true,
          'writeOnly': false,
          'deprecated': false,
        },
        decoder: (json) => json,
      );

      expect(output.parse('{"name":"Ada Lovelace"}'), {'name': 'Ada Lovelace'});
      expect(
        output.responseFormat['json_schema']['schema']['properties']['name'],
        containsPair('description', 'Display name.'),
      );
    });

    test('accepts annotation-only siblings on ref schemas', () {
      final output = LlamaStructuredOutput<Map<String, dynamic>>.jsonSchema(
        schema: const {
          'type': 'object',
          'properties': {
            'contact': {
              r'$ref': '#/\$defs/contact',
              'title': 'Contact',
              'description': 'Reference annotations are ignored.',
              r'$comment': 'Safe alongside ref.',
            },
          },
          'required': ['contact'],
          r'$defs': {
            'contact': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
              'required': ['name'],
              'additionalProperties': false,
            },
          },
        },
        decoder: (json) => json,
      );

      expect(output.parse('{"contact":{"name":"Ada Lovelace"}}'), {
        'contact': {'name': 'Ada Lovelace'},
      });
    });

    test('rejects validation siblings on ref schemas', () {
      expect(
        () => LlamaStructuredOutput<Map<String, dynamic>>.jsonSchema(
          schema: const {
            'type': 'object',
            'properties': {
              'contact': {r'$ref': '#/\$defs/contact', 'type': 'object'},
            },
            r'$defs': {
              'contact': {'type': 'object'},
            },
          },
          decoder: (json) => json,
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains(r'$ref cannot be combined'),
          ),
        ),
      );
    });

    test('rejects schema that cannot be represented safely', () {
      expect(
        () => LlamaStructuredOutput<List<Object?>>.jsonValueSchema(
          schema: const {
            'type': 'array',
            'items': {'type': 'string'},
            'minItems': 2,
            'maxItems': 1,
          },
          decoder: (value) => value as List<Object?>,
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('Unsupported structured JSON schema'),
          ),
        ),
      );
    });

    for (final testCase in const [
      (
        name: 'minimum',
        keyword: 'minimum',
        schema: {
          'type': 'object',
          'properties': {
            'age': {'type': 'integer', 'minimum': 0},
          },
        },
      ),
      (
        name: 'pattern',
        keyword: 'pattern',
        schema: {'type': 'string', 'pattern': r'^\w+$'},
      ),
      (
        name: 'format',
        keyword: 'format',
        schema: {'type': 'string', 'format': 'email'},
      ),
      (
        name: 'uniqueItems',
        keyword: 'uniqueItems',
        schema: {
          'type': 'array',
          'items': {'type': 'string'},
          'uniqueItems': true,
        },
      ),
    ]) {
      test('rejects unsupported schema keyword ${testCase.name}', () {
        expect(
          () => LlamaStructuredOutput<Object?>.jsonValueSchema(
            schema: testCase.schema,
            decoder: (value) => value,
          ),
          throwsA(
            isA<LlamaUnsupportedException>()
                .having(
                  (error) => error.message,
                  'message',
                  contains('Unsupported structured JSON schema'),
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains(testCase.keyword),
                ),
          ),
        );
      });
    }

    for (final testCase in const [
      (name: 'primitive', schema: {'type': 'string'}),
      (
        name: 'array',
        schema: {
          'type': 'array',
          'items': {'type': 'string'},
        },
      ),
    ]) {
      test('rejects ${testCase.name} root schema in jsonSchema', () {
        expect(
          () => LlamaStructuredOutput<Map<String, dynamic>>.jsonSchema(
            schema: testCase.schema,
            decoder: (json) => json,
          ),
          throwsA(
            isA<LlamaUnsupportedException>()
                .having(
                  (error) => error.message,
                  'message',
                  contains('requires a JSON object root schema'),
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('LlamaStructuredOutput.jsonValueSchema'),
                ),
          ),
        );
      });
    }

    test('decodes primitive jsonValueSchema output', () {
      final output = LlamaStructuredOutput<String>.jsonValueSchema(
        schema: const {
          'type': 'string',
          'enum': ['bug', 'feature'],
        },
        decoder: (value) => value as String,
      );

      expect(output.parse('"bug"'), 'bug');
    });

    test('decodes array jsonValueSchema output', () {
      final output = LlamaStructuredOutput<List<String>>.jsonValueSchema(
        schema: const {
          'type': 'array',
          'items': {'type': 'string'},
          'minItems': 1,
        },
        decoder: (value) => (value as List).cast<String>(),
      );

      expect(output.parse('["red","blue"]'), ['red', 'blue']);
    });

    test('rejects malformed final JSON output', () {
      final output = LlamaStructuredOutput<Map<String, dynamic>>.jsonObject(
        decoder: (json) => json,
      );

      expect(
        () => output.parse('not json'),
        throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.message,
            'message',
            contains('Malformed structured JSON output'),
          ),
        ),
      );
    });

    test('rejects final JSON that does not match schema', () {
      final output = LlamaStructuredOutput<Map<String, dynamic>>.jsonSchema(
        schema: const {
          'type': 'object',
          'properties': {
            'ok': {'type': 'boolean'},
          },
          'required': ['ok'],
          'additionalProperties': false,
        },
        decoder: (json) => json,
      );

      expect(
        () => output.parse('{"ok":"yes"}'),
        throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.details,
            'details',
            contains(r'$.ok must be a boolean'),
          ),
        ),
      );
    });

    test('collects streamed chunks before final validation', () async {
      final output = LlamaStructuredOutput<Map<String, dynamic>>.jsonSchema(
        schema: const {
          'type': 'object',
          'properties': {
            'ok': {'type': 'boolean'},
          },
          'required': ['ok'],
        },
        decoder: (json) => json,
      );

      final result = await Stream.fromIterable([
        _chunk('{"ok":'),
        _chunk('true}'),
      ]).parseStructuredJson(output);

      expect(result, {'ok': true});
    });
  });
}

class _Contact {
  const _Contact({required this.name, required this.email});

  final String name;
  final String email;

  static _Contact fromJson(Map<String, dynamic> json) {
    return _Contact(
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }
}

LlamaCompletionChunk _chunk(String content) {
  return LlamaCompletionChunk(
    id: 'chunk',
    object: 'chat.completion.chunk',
    created: 0,
    model: 'test',
    choices: [
      LlamaCompletionChunkChoice(
        index: 0,
        delta: LlamaCompletionChunkDelta(content: content),
      ),
    ],
  );
}
