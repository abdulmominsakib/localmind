import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:schemantic/schemantic.dart';
import 'package:test/test.dart';

import '../../../core/runtime/test_support/fake_runtime.dart';

void main() {
  final cases = <String, List<llama.LlamaCompletionChunk>>{
    'missing tool name': [toolCallChunk(id: 'call', name: '', arguments: '{}')],
    'non-object inline arguments': [
      textChunk('<tool_call>{"name":"lookup","arguments":[]}</tool_call>'),
      stopChunk(),
    ],
    'invalid JSON arguments': [
      toolCallChunk(id: 'call', name: 'lookup', arguments: '{'),
    ],
    'non-object arguments': [
      toolCallChunk(id: 'call', name: 'lookup', arguments: '[]'),
    ],
    'invalid inline call': [
      textChunk('<tool_call>{bad}</tool_call>'),
      stopChunk(),
    ],
    'incomplete inline call': [
      textChunk('<tool_call>{"name":"lookup"'),
      stopChunk(),
    ],
    'complete call followed by incomplete call': [
      textChunk(
        '<tool_call>{"name":"lookup","arguments":{}}</tool_call><tool_call>',
      ),
      stopChunk(),
    ],
    'complete call followed by unmatched end': [
      textChunk(
        '<tool_call>{"name":"lookup","arguments":{}}</tool_call></tool_call>',
      ),
      stopChunk(),
    ],
    'token-limited call': [
      toolCallChunk(id: 'call', name: 'lookup', arguments: '{}'),
      textChunk('', finishReason: 'length'),
    ],
    'tool choice none': [
      toolCallChunk(id: 'call', name: 'lookup', arguments: '{}'),
    ],
    'inline tool choice none': [
      textChunk('<tool_call>{"name":"lookup","arguments":{}}</tool_call>'),
      stopChunk(),
    ],
  };
  for (final entry in cases.entries) {
    test('${entry.key} cannot dispatch a tool', () async {
      final runtime = FakeRuntime()
        ..createScripts.addAll([
          entry.value,
          [textChunk('done'), stopChunk()],
        ]);
      final plugin = LlamaDartPlugin(
        models: const [
          LlamaModelDefinition(name: 'local', modelPath: '/unused'),
        ],
        runtimeFactory: () => runtime,
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      var calls = 0;
      final tool = ai.defineTool<Map<String, dynamic>, String>(
        name: 'lookup',
        description: 'Look up a value',
        inputSchema: SchemanticType.from(
          jsonSchema: {'type': 'object', 'properties': <String, Object?>{}},
          parse: (json) => (json as Map).cast<String, dynamic>(),
        ),
        outputSchema: SchemanticType.string(),
        fn: (_, _) async {
          calls++;
          return ToolResult.response('result');
        },
      );
      final result = await ai.generate(
        model: llamaDart.model('local'),
        prompt: 'lookup',
        tools: [tool],
        toolChoice: entry.key.contains('none')
            ? ToolChoice.none
            : ToolChoice.auto,
        maxTurns: 2,
      );
      expect(
        result.finishReason,
        entry.key == 'inline tool choice none'
            ? FinishReason.stop
            : FinishReason.failed,
      );
      expect(calls, 0);
      expect(runtime.createCallCount, 1);
      if (entry.key != 'inline tool choice none') {
        expect(result.error, isNotNull);
        expect(
          result.cause,
          isA<GenkitException>().having(
            (error) => error.status,
            'status',
            StatusCode.dataLoss,
          ),
        );
      }
    });
  }
  test('unsupported runtime rejects tools before inference', () async {
    final runtime = FakeRuntime()
      ..capabilitySnapshot = const llama.LlamaEngineCapabilities(
        isSupported: true,
        supportsToolCalling: false,
      );
    final plugin = LlamaDartPlugin(
      models: const [LlamaModelDefinition(name: 'local', modelPath: '/unused')],
      runtimeFactory: () => runtime,
    );
    final ai = Genkit(plugins: [plugin], isDevEnv: false);
    addTearDown(() async {
      await plugin.dispose();
      await ai.shutdown();
    });
    final tool = ai.defineTool<void, String>(
      name: 'lookup',
      description: 'Look up a value',
      outputSchema: SchemanticType.string(),
      fn: (_, _) async => ToolResult.response('result'),
    );
    final result = await ai.generate(
      model: llamaDart.model('local'),
      prompt: 'lookup',
      tools: [tool],
    );
    expect(result.finishReason, FinishReason.failed);
    expect(runtime.createCallCount, 0);
  });
}
