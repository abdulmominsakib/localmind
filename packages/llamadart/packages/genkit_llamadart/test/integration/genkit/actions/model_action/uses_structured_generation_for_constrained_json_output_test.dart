import 'package:genkit/genkit.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';
import '../test_support/action_harness.dart';

void main() {
  test(
    'model action uses structured generation for constrained JSON output',
    () async {
      final runtime = FakeRuntime()
        ..templateResult = const llama.LlamaChatTemplateResult(
          prompt: 'prompt',
          format: 0,
          grammarTriggers: [
            llama.GrammarTrigger(type: 0, value: '<json>'),
            llama.GrammarTrigger(type: 1, value: '42', token: 42),
            llama.GrammarTrigger(type: 2, value: 'answer.*'),
            llama.GrammarTrigger(type: 3, value: '.*answer.*'),
          ],
        )
        ..generatedTokens = <String>['{"answer":"hi"}'];
      final action = testModelAction(runtime: runtime);

      final response = await action(
        genkit.ModelRequest(
          messages: <genkit.Message>[
            genkit.Message(
              role: genkit.Role.user,
              content: <genkit.Part>[
                genkit.TextPart(text: 'Respond with JSON'),
              ],
            ),
          ],
          output: genkit.OutputConfig(
            format: 'json',
            schema: <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{
                'answer': <String, dynamic>{'type': 'string'},
              },
            },
          ),
        ),
      );

      expect(runtime.chatTemplateCallCount, 1);
      expect(runtime.generateCallCount, 1);
      expect(
        runtime.lastGenerationParams!.grammarTriggers.map(
          (trigger) => trigger.triggerType,
        ),
        llama.GrammarTriggerType.values,
      );
      expect(
        runtime.lastGenerationParams!.grammarTriggers.map(
          (trigger) => trigger.value,
        ),
        ['<json>', '42', 'answer.*', '.*answer.*'],
      );
      expect(runtime.lastGenerationParams!.grammarTriggers[1].token, 42);
      expect(response.text, '{"answer":"hi"}');
    },
  );

  test('rejects unsupported grammar triggers before generation', () async {
    final runtime = FakeRuntime()
      ..templateResult = const llama.LlamaChatTemplateResult(
        prompt: 'prompt',
        grammarTriggers: [llama.GrammarTrigger(type: 99, value: 'invalid')],
      );
    final action = testModelAction(runtime: runtime);
    await expectLater(
      action(
        genkit.ModelRequest(
          messages: [
            genkit.Message(
              role: genkit.Role.user,
              content: [genkit.TextPart(text: 'Return JSON')],
            ),
          ],
          output: genkit.OutputConfig(format: 'json'),
        ),
      ),
      throwsA(isA<llama.LlamaUnsupportedException>()),
    );
    expect(runtime.generateCallCount, 0);
  });
}
