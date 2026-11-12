import 'package:test/test.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';

void main() {
  group('Tool Models Tests', () {
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

    test('ToolDefinition without a handler cannot be invoked', () async {
      const tool = ToolDefinition(
        name: 'approve',
        description: 'Run by the app',
        parameters: [],
      );

      expect(tool.handler, isNull);
      await expectLater(
        tool.invoke(const {}),
        throwsA(
          isA<LlamaStateException>().having(
            (e) => e.message,
            'message',
            contains('"approve"'),
          ),
        ),
      );
    });
  });
}
