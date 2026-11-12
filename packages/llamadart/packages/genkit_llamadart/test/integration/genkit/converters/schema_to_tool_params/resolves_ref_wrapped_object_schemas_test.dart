import 'package:genkit_llamadart/src/integration/genkit/converters/schema_to_tool_params.dart';
import 'package:test/test.dart';

void main() {
  test('legacy references resolve within their declared definition block', () {
    final params = schemaToToolParams(
      normalizeToolInputSchema({
        r'$ref': '#/definitions/Input',
        'definitions': {
          'Input': {
            'type': 'object',
            'properties': {
              'value': {r'$ref': '#/definitions/Value'},
            },
            'required': ['value'],
          },
          'Value': {'type': 'null'},
        },
      }),
    );
    expect(params.single.toJsonSchema(), {'type': 'null'});
    expect(params.single.required, isTrue);
  });

  test('schemaToToolParams resolves ref-wrapped object schemas', () {
    final params = schemaToToolParams(
      normalizeToolInputSchema(<String, dynamic>{
        r'$ref': r'#/$defs/LookupInput',
        r'$defs': <String, dynamic>{
          'LookupInput': <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'city': <String, dynamic>{
                'type': 'string',
                'description': 'City to look up.',
              },
            },
            'required': <String>['city'],
          },
        },
      }),
    );

    expect(params, hasLength(1));
    expect(params.single.name, 'city');
    expect(params.single.required, isTrue);
  });

  test('schemaToToolParams accepts ref-wrapped empty objects', () {
    final params = schemaToToolParams(
      normalizeToolInputSchema(<String, dynamic>{
        r'$ref': r'#/$defs/EmptyInput',
        r'$defs': <String, dynamic>{
          'EmptyInput': <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
          },
        },
      }),
    );

    expect(params, isEmpty);
  });
}
