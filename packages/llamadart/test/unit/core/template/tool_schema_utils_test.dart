import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/tool_schema_utils.dart';
import 'package:test/test.dart';

void main() {
  group('tool schema utilities', () {
    test('indexes schemas by their exact tool names', () {
      final schemas = toolSchemas([_tool]);

      expect(schemas.keys, ['inspect']);
      expect(schemaRequired(schemas['inspect']!), {'code', 'count'});
      expect(schemaProperties(schemas['inspect']!).keys, {
        'code',
        'count',
        'options',
        'items',
        'empty',
      });
    });

    test(
      'rejects empty and duplicate tool identities before schema lookup',
      () {
        final duplicate = ToolDefinition(
          name: _tool.name,
          description: 'Duplicate schema',
          parameters: const [],
          handler: (_) async => null,
        );
        final empty = ToolDefinition(
          name: '',
          description: 'Empty schema identity',
          parameters: const [],
          handler: (_) async => null,
        );

        expect(
          () => toolSchemas([_tool, duplicate]),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              contains('declared more than once'),
            ),
          ),
        );
        expect(
          () => toolSchemas([empty]),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              contains('non-empty tool names'),
            ),
          ),
        );
      },
    );

    test('rejects lossy parameter identities before schema construction', () {
      final invalidTools = <ToolDefinition>[
        ToolDefinition(
          name: 'empty_top_level',
          description: 'Empty top-level parameter',
          parameters: [ToolParam.string('')],
          handler: (_) async => null,
        ),
        ToolDefinition(
          name: 'duplicate_top_level',
          description: 'Duplicate top-level parameter',
          parameters: [ToolParam.string('value'), ToolParam.integer('value')],
          handler: (_) async => null,
        ),
        ToolDefinition(
          name: 'duplicate_nested',
          description: 'Duplicate nested parameter',
          parameters: [
            ToolParam.object(
              'options',
              properties: [ToolParam.string('mode'), ToolParam.boolean('mode')],
            ),
          ],
          handler: (_) async => null,
        ),
        ToolDefinition(
          name: 'empty_array_object',
          description: 'Empty parameter nested in an array object',
          parameters: [
            ToolParam.array(
              'items',
              itemType: ToolParam.object(
                'ignored_item_name',
                properties: [ToolParam.string('')],
              ),
            ),
          ],
          handler: (_) async => null,
        ),
      ];

      for (final tool in invalidTools) {
        expect(
          () => toolSchemas([tool]),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              anyOf(contains('non-empty parameter names'), contains('unique')),
            ),
          ),
        );
      }
    });

    test('preserves lexical strings and validates primitive types', () {
      expect(decodeToolSchemaText('123', const {'type': 'string'}), (
        valid: true,
        value: '123',
      ));
      expect(decodeToolSchemaText('123', const {'type': 'integer'}), (
        valid: true,
        value: 123,
      ));
      expect(
        decodeToolSchemaText('123', const {'type': 'boolean'}).valid,
        isFalse,
      );
      expect(decodeToolSchemaText('null', const {'type': 'null'}), (
        valid: true,
        value: null,
      ));
    });

    test('validates nested containers, required keys, and unknown keys', () {
      final schema = _tool.toJsonSchema();
      expect(
        validateToolSchemaValue({
          'code': '001',
          'count': 7,
          'options': {'enabled': true},
          'items': ['a', 'b'],
          'empty': null,
        }, schema).valid,
        isTrue,
      );
      expect(validateToolSchemaValue({'code': '001'}, schema).valid, isFalse);
      expect(
        validateToolSchemaValue({
          'code': '001',
          'count': 7,
          'unknown': true,
        }, schema).valid,
        isFalse,
      );
      expect(
        validateToolSchemaValue({
          'code': '001',
          'count': 7,
          'options': {'enabled': 'true'},
        }, schema).valid,
        isFalse,
      );
    });

    test('enforces string enum members without coercion', () {
      const schema = {
        'type': 'string',
        'enum': ['auto', 'manual'],
      };
      expect(decodeToolSchemaText('auto', schema).valid, isTrue);
      expect(decodeToolSchemaText('1', schema).valid, isFalse);
    });
  });
}

final _tool = ToolDefinition(
  name: 'inspect',
  description: 'Inspect values',
  parameters: [
    ToolParam.string('code', required: true),
    ToolParam.integer('count', required: true),
    ToolParam.object(
      'options',
      properties: [ToolParam.boolean('enabled', required: true)],
    ),
    ToolParam.array('items', itemType: ToolParam.string('item')),
    ToolParam.nullType('empty'),
  ],
  handler: (_) async => null,
);
