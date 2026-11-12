import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/src/integration/genkit/converters/constrained_tools.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

void main() {
  test(
    'injected draft-07 metadata validates locally without weakening values',
    () async {
      final schema = <String, dynamic>{
        r'$schema': 'http://json-schema.org/draft-07/schema#',
        'type': 'string',
        'minLength': 2,
      };
      await validateConstrainedValue('ok', schema);
      await expectLater(
        validateConstrainedValue(7, schema),
        throwsA(isA<GenkitException>()),
      );
      await expectLater(
        validateConstrainedValue('x', schema),
        throwsA(isA<GenkitException>()),
      );
      expect(schema[r'$schema'], 'http://json-schema.org/draft-07/schema#');
    },
  );

  test(
    'a property named schema keeps its validation and required constraint',
    () async {
      final schema = <String, dynamic>{
        r'$schema': 'http://json-schema.org/draft-07/schema#',
        'type': 'object',
        'properties': {
          r'$schema': {
            'type': 'integer',
            'enum': [2],
          },
        },
        'required': [r'$schema'],
        'additionalProperties': false,
      };
      await validateConstrainedValue({r'$schema': 2}, schema);
      for (final value in [
        {r'$schema': '2'},
        {r'$schema': 3},
        <String, Object?>{},
      ]) {
        await expectLater(
          validateConstrainedValue(value, schema),
          throwsA(isA<GenkitException>()),
        );
      }
    },
  );

  test(
    'tool envelopes preserve output constraints without nested dialect fetches',
    () async {
      final schema = constrainedToolSchema(
        [
          llama.ToolDefinition(
            name: 'lookup',
            description: 'Lookup',
            parameters: [],
          ),
        ],
        llama.ToolChoice.auto,
        {
          r'$schema': 'http://json-schema.org/draft-07/schema#',
          'type': 'string',
          'minLength': 2,
        },
      );
      await validateConstrainedValue({'response': 'ok'}, schema);
      await expectLater(
        validateConstrainedValue({'response': 'x'}, schema),
        throwsA(isA<GenkitException>()),
      );
      await expectLater(
        validateConstrainedValue({'response': 7}, schema),
        throwsA(isA<GenkitException>()),
      );
    },
  );
}
