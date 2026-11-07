import 'package:test/test.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/models/tools/tool_params.dart';

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

  group('ToolParams', () {
    final data = {
      's': 'hello',
      'i': 42,
      'd': 3.14,
      'b': true,
      'l': [1, 2, 3],
      'o': {'x': 1},
    };
    final params = ToolParams(data);

    test('getString', () {
      expect(params.getString('s'), 'hello');
      expect(params.getString('none'), isNull);
      expect(() => params.getString('i'), throwsArgumentError);
      expect(params.getRequiredString('s'), 'hello');
      expect(() => params.getRequiredString('none'), throwsArgumentError);
    });

    test('getInt', () {
      expect(params.getInt('i'), 42);
      expect(params.getInt('d'), 3);
      expect(params.getInt('none'), isNull);
      expect(() => params.getInt('s'), throwsArgumentError);
      expect(params.getRequiredInt('i'), 42);
    });

    test('getDouble', () {
      expect(params.getDouble('d'), 3.14);
      expect(params.getDouble('i'), 42.0);
      expect(params.getDouble('none'), isNull);
      expect(() => params.getDouble('s'), throwsArgumentError);
      expect(params.getRequiredDouble('d'), 3.14);
    });

    test('getBool', () {
      expect(params.getBool('b'), true);
      expect(params.getBool('none'), isNull);
      expect(() => params.getBool('s'), throwsArgumentError);
      expect(params.getRequiredBool('b'), true);
    });

    test('getList', () {
      expect(params.getList<int>('l'), [1, 2, 3]);
      expect(params.getList('none'), isNull);
      expect(() => params.getList('s'), throwsArgumentError);
      expect(params.getRequiredList<int>('l'), [1, 2, 3]);
    });

    test('getObject', () {
      final obj = params.getObject('o');
      expect(obj, isNotNull);
      expect(obj!.getInt('x'), 1);
      expect(params.getObject('none'), isNull);
      expect(() => params.getObject('s'), throwsArgumentError);
      expect(params.getRequiredObject('o').getInt('x'), 1);
    });

    test('has and raw', () {
      expect(params.has('s'), true);
      expect(params.has('none'), false);
      expect(params.raw, data);
      expect(params['s'], 'hello');
    });

    test('toString', () {
      expect(params.toString(), contains('s: hello'));
    });
  });
}
