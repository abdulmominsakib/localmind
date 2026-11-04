import 'package:test/test.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/models/tools/tool_params.dart';

void main() {
  group('Tool Models Tests', () {
    test('ToolParam constructors and toJsonSchema', () {
      final p1 = ToolParam.string('loc', description: 'City', required: true);
      expect(p1.name, 'loc');
      expect(p1.required, true);
      expect(p1.toJsonSchema(), {'type': 'string', 'description': 'City'});

      final p2 = ToolParam.number('count');
      expect(p2.toJsonSchema(), {'type': 'number'});

      final p3 = ToolParam.boolean('flag');
      expect(p3.toJsonSchema(), {'type': 'boolean'});

      final p4 = ToolParam.integer('id');
      expect(p4.toJsonSchema(), {'type': 'integer'});

      final p5 = ToolParam.enumType('unit', values: ['c', 'f']);
      expect(p5.toJsonSchema(), {
        'type': 'string',
        'enum': ['c', 'f'],
      });
    });

    test('ToolDefinition toJson and toJsonSchema', () {
      final tool = ToolDefinition(
        name: 'test_tool',
        description: 'A test tool',
        parameters: [
          ToolParam.string('p1', required: true),
          ToolParam.integer('p2'),
        ],
        handler: (params) async => 'result',
      );

      expect(tool.toJsonSchema(), {
        'type': 'object',
        'properties': {
          'p1': {'type': 'string'},
          'p2': {'type': 'integer'},
        },
        'required': ['p1'],
      });

      expect(tool.toJson(), {
        'type': 'function',
        'function': {
          'name': 'test_tool',
          'description': 'A test tool',
          'parameters': tool.toJsonSchema(),
        },
      });
    });

    test('ToolDefinition invoke', () async {
      final tool = ToolDefinition(
        name: 'greet',
        description: 'Greet someone',
        parameters: [ToolParam.string('name', required: true)],
        handler: (params) async => 'Hello ${params.getRequiredString("name")}',
      );

      final result = await tool.invoke({'name': 'Alice'});
      expect(result, 'Hello Alice');
    });

    test('ToolParams safe accessors', () {
      final tp = ToolParams(
        {
              's': 'val',
              'i': 123,
              'd': 45.6,
              'b': true,
              'l': [1, 2],
              'm': {'k': 'v'},
            }
            as Map<String, dynamic>,
      );

      expect(tp.getString('s'), 'val');
      expect(tp.getString('missing'), isNull);
      expect(tp.getRequiredString('s'), 'val');
      expect(() => tp.getRequiredString('missing'), throwsArgumentError);

      expect(tp.getInt('i'), 123);
      expect(tp.getDouble('d'), 45.6);
      expect(tp.getBool('b'), true);
      expect(tp.getList('l'), [1, 2]);
      expect(tp.getObject('m')?.raw, {'k': 'v'});
    });
  });
}
