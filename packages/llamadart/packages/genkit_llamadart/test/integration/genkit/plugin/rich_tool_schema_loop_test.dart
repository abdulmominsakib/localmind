import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:schemantic/schemantic.dart';
import 'package:test/test.dart';

import '../../../core/runtime/test_support/fake_runtime.dart';

void main() {
  for (final interrupt in [false, true]) {
    test(
      'rich schemas reach handlers and history ${interrupt ? 'after interrupt/resume' : 'in ordinary loops'}',
      () async {
        final runtime = FakeRuntime()
          ..createScripts.addAll([
            [
              thinkingChunk('prior reasoning'),
              toolCallChunk(
                id: 'lookup-call',
                name: 'lookup',
                arguments: '{"value":null,"mode":2}',
              ),
              if (interrupt)
                toolCallChunk(
                  id: 'confirm-call',
                  name: 'confirm',
                  arguments: '{}',
                  index: 1,
                ),
            ],
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
          description: 'Lookup',
          inputSchema: SchemanticType.from(
            jsonSchema: {
              r'$ref': r'#/$defs/Input',
              r'$defs': {
                'Input': {
                  'type': 'object',
                  'properties': {
                    'value': {
                      'type': ['string', 'null'],
                    },
                    'mode': {
                      'type': 'integer',
                      'enum': [1, 2],
                    },
                  },
                  'required': ['value', 'mode'],
                  'additionalProperties': false,
                },
              },
            },
            parse: (value) => (value as Map).cast<String, dynamic>(),
          ),
          outputSchema: SchemanticType.string(),
          fn: (input, _) async {
            expect(input, {'value': null, 'mode': 2});
            calls++;
            return ToolResult.response('found');
          },
        );
        final confirm = ai.defineInterrupt<Map<String, dynamic>, String>(
          name: 'confirm',
          description: 'Confirm',
          inputSchema: SchemanticType.from(
            jsonSchema: {'type': 'object'},
            parse: (v) => (v as Map).cast<String, dynamic>(),
          ),
        );
        var result = await ai.generate(
          model: llamaDart.model('local'),
          prompt: 'Lookup',
          tools: [tool, if (interrupt) confirm],
          maxTurns: 2,
        );
        if (interrupt) {
          expect(
            result.finishReason,
            FinishReason.interrupted,
            reason: '${result.error}',
          );
          result = await ai.generate(
            model: llamaDart.model('local'),
            messages: result.messages,
            tools: [tool, confirm],
            maxTurns: 2,
            interruptRespond: [
              InterruptResponse(result.interrupts.single, 'approved'),
            ],
          );
        }
        expect(
          result.finishReason,
          FinishReason.stop,
          reason: '${result.error}',
        );
        expect(result.text, 'done');
        expect(calls, 1);
        expect(runtime.createCallCount, 2);
        final schema = runtime.lastTools!.first.toJsonSchema();
        expect(schema['additionalProperties'], isFalse);
        expect(schema['properties']['value'], {
          'type': ['string', 'null'],
        });
        final history = runtime.recordedMessages.last
            .expand((m) => m.parts)
            .whereType<llama.LlamaToolResultContent>();
        expect(history.first.id, 'lookup-call');
        expect(history.first.result, 'found');
        expect(
          result.messages
              .expand((m) => m.content)
              .where((p) => p.isReasoning)
              .single
              .reasoning,
          'prior reasoning',
        );
      },
    );
  }
}
