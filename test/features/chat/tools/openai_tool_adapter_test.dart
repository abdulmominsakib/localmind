import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/data/tools/adapters/openai_tool_adapter.dart';
import 'package:localmind/features/chat/data/tools/adapters/tool_transport_adapter.dart';
import 'package:localmind/features/chat/data/tools/tool_definition.dart';

void main() {
  group('OpenAiToolAdapter', () {
    test('reconstructs tool call arguments from delta chunks', () {
      final adapter = OpenAiToolAdapter();
      adapter.consumeDynamicChunk({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_1',
                  'type': 'function',
                  'function': {'name': 'calc.add', 'arguments': ''},
                },
              ],
            },
          },
        ],
      });
      adapter.consumeDynamicChunk({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': '{"a":1,"b":2}'},
                },
              ],
            },
          },
        ],
      });

      final calls = adapter.takeCompletedCalls();
      expect(calls.length, 1);
      expect(calls.single.name, 'calc.add');
      expect(calls.single.arguments['a'], 1);
    });

    test('builds tool definition payload', () {
      final adapter = OpenAiToolAdapter();
      final payload = adapter.buildToolDefinitionPayload([
        const ToolDefinition(
          name: 'calc.add',
          description: 'Add two numbers',
          inputSchema: {'type': 'object'},
          providerType: ToolProviderType.builtIn,
        ),
      ]);
      expect(payload['tools'], isA<List>());
      expect(payload['tools'][0]['function']['name'], 'calc.add');
    });

    test('builds tool result message', () {
      final adapter = OpenAiToolAdapter();
      final msg = adapter.buildToolResultMessage(
        call: const ParsedToolCall(
          id: 'call_1',
          name: 'calc.add',
          arguments: {'a': 1, 'b': 2},
        ),
        output: '3',
      );
      expect(msg['role'], 'tool');
      expect(msg['tool_call_id'], 'call_1');
      expect(msg['content'], '3');
    });
  });
}
