import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:schemantic/schemantic.dart';
import 'package:test/test.dart';

import '../../../core/runtime/test_support/fake_runtime.dart';

void main() {
  for (final interrupt in [false, true]) {
    test(
      'Genkit handlers forward text presentations ${interrupt ? 'after resume' : 'in call order'}',
      () async {
        final runtime = FakeRuntime()
          ..createScripts.addAll([
            [
              thinkingChunk('prior reasoning'),
              toolCallChunk(
                id: 'first',
                name: 'lookup',
                arguments: '{"key":"one"}',
              ),
              toolCallChunk(
                id: 'second',
                name: 'lookup',
                arguments: '{"key":"two"}',
                index: 1,
              ),
              if (interrupt)
                toolCallChunk(
                  id: 'confirmation',
                  name: 'confirm',
                  arguments: '{}',
                  index: 2,
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
        final calls = <String>[];
        final tool = ai.defineTool<Map<String, dynamic>, String>(
          name: 'lookup',
          description: 'Lookup',
          inputSchema: SchemanticType.from(
            jsonSchema: {
              'type': 'object',
              'properties': {
                'key': {'type': 'string'},
              },
              'required': ['key'],
            },
            parse: (v) => (v as Map).cast<String, dynamic>(),
          ),
          outputSchema: SchemanticType.string(),
          fn: (input, _) async {
            final key = input['key'] as String;
            calls.add(key);
            return ToolResult.response(
              'structured:$key',
              parts: [
                TextPart(text: key),
                TextPart(text: ''),
                TextPart(text: 'presentation'),
              ],
            );
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
          prompt: 'lookup',
          tools: [tool, if (interrupt) confirm],
          maxTurns: 2,
          config: const LlamaDartGenerationConfig(parallelToolCalls: true),
        );
        if (interrupt) {
          expect(result.finishReason, FinishReason.interrupted);
          expect(result.interrupts, hasLength(1));
          expect(runtime.createCallCount, 1);
          expect(calls, ['one', 'two']);
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
        final historyReasoning = result.messages
            .expand((message) => message.content)
            .where((part) => part.isReasoning);
        expect(historyReasoning.single.reasoning, 'prior reasoning');
        expect(
          runtime.recordedMessages[1].any(
            (message) => message.reasoning != null,
          ),
          isFalse,
        );
        expect(calls, ['one', 'two']);
        final forwarded = runtime.recordedMessages[1]
            .expand((m) => m.parts)
            .whereType<llama.LlamaToolResultContent>()
            .toList();
        expect(forwarded.map((p) => p.id), [
          'first',
          'second',
          if (interrupt) 'confirmation',
        ]);
        expect(forwarded.map((p) => p.name), [
          'lookup',
          'lookup',
          if (interrupt) 'confirm',
        ]);
        expect(forwarded.map((p) => p.result), [
          'one\n\npresentation',
          'two\n\npresentation',
          if (interrupt) 'approved',
        ]);
        final history = result.messages
            .expand((m) => m.content)
            .where((p) => p.isToolResponse)
            .map((p) => p.toolResponse!)
            .where((p) => p.name == 'lookup')
            .toList();
        expect(history.map((p) => p.output), [
          'structured:one',
          'structured:two',
        ]);
        expect(history.map((p) => p.content!.length), [3, 3]);
      },
    );
  }

  test('unsupported result parts stop before the second model turn', () async {
    final runtime = FakeRuntime()
      ..createChunks = [
        toolCallChunk(id: 'call', name: 'lookup', arguments: '{}'),
      ];
    final plugin = LlamaDartPlugin(
      models: const [LlamaModelDefinition(name: 'local', modelPath: '/unused')],
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
        jsonSchema: {'type': 'object'},
        parse: (v) => (v as Map).cast<String, dynamic>(),
      ),
      outputSchema: SchemanticType.string(),
      fn: (_, _) async {
        calls++;
        return ToolResult.response(
          'output',
          parts: [
            TextPart(text: 'first'),
            MediaPart(
              media: Media(
                url: 'https://host/SECRET_SENTINEL?token=TOKEN_SENTINEL',
                contentType: 'image/png',
              ),
            ),
          ],
        );
      },
    );
    final result = await ai.generate(
      model: llamaDart.model('local'),
      prompt: 'lookup',
      tools: [tool],
      maxTurns: 2,
    );
    expect(result.finishReason, FinishReason.failed);
    expect(calls, 1);
    expect(runtime.createCallCount, 1);
    expect('${result.error} ${result.cause}', isNot(contains('SENTINEL')));
    expect(
      result.cause,
      isA<GenkitException>().having(
        (e) => e.status,
        'status',
        StatusCode.unimplemented,
      ),
    );
  });
}
