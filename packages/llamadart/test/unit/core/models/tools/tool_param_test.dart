import 'package:test/test.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';

void main() {
  group('ToolParam', () {
    test('string param', () {
      final p = ToolParam.string('test', description: 'desc', required: true);
      expect(p.name, 'test');
      expect(p.description, 'desc');
      expect(p.required, true);
      expect(p.toJsonSchema(), {'type': 'string', 'description': 'desc'});
    });

    test('integer param', () {
      final p = ToolParam.integer('test');
      expect(p.toJsonSchema(), {'type': 'integer'});
    });

    test('number param', () {
      final p = ToolParam.number('test');
      expect(p.toJsonSchema(), {'type': 'number'});
    });

    test('boolean param', () {
      final p = ToolParam.boolean('test');
      expect(p.toJsonSchema(), {'type': 'boolean'});
    });

    test('null param', () {
      final p = ToolParam.nullType('test', required: true);
      expect(p.required, isTrue);
      expect(p.toJsonSchema(), {'type': 'null'});
    });

    test('enum param', () {
      final p = ToolParam.enumType('test', values: ['a', 'b']);
      expect(p.toJsonSchema(), {
        'type': 'string',
        'enum': ['a', 'b'],
      });
    });

    test('array param', () {
      final p = ToolParam.array('test', itemType: ToolParam.string('item'));
      expect(p.toJsonSchema(), {
        'type': 'array',
        'items': {'type': 'string'},
      });
    });

    test('object param', () {
      final p = ToolParam.object(
        'test',
        properties: [
          ToolParam.string('s', required: true),
          ToolParam.integer('i'),
        ],
        description: 'obj',
      );
      expect(p.toJsonSchema(), {
        'type': 'object',
        'properties': {
          's': {'type': 'string'},
          'i': {'type': 'integer'},
        },
        'required': ['s'],
        'description': 'obj',
      });
    });
  });
}
