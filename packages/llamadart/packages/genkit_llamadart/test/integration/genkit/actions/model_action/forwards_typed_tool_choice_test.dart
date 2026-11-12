import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit_llamadart/src/integration/genkit/actions/model_action.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';
import '../test_support/action_harness.dart';

void main() {
  final choices = <genkit.ToolChoice?, llama.ToolChoice>{
    null: llama.ToolChoice.auto,
    genkit.ToolChoice.auto: llama.ToolChoice.auto,
    genkit.ToolChoice.required: llama.ToolChoice.required,
    genkit.ToolChoice.none: llama.ToolChoice.none,
    const genkit.ToolChoice('future-choice'): llama.ToolChoice.auto,
  };
  for (final entry in choices.entries) {
    for (final hasTools in [true, false]) {
      test('forwards ${entry.key} with tools=$hasTools', () async {
        final runtime = FakeRuntime()..createChunks = [stopChunk()];
        final registry = testRegistry(runtime: runtime);
        addTearDown(registry.dispose);
        final action = buildModelAction(
          definition: testModelDefinition(),
          registry: registry,
        );
        await action(
          genkit.ModelRequest(
            messages: [
              genkit.Message(
                role: genkit.Role.user,
                content: [genkit.TextPart(text: 'Look up a value')],
              ),
            ],
            tools: hasTools
                ? [
                    genkit.ToolDefinition(
                      name: 'lookup',
                      description: 'Look up a value',
                      inputSchema: {'type': 'object', 'properties': {}},
                    ),
                  ]
                : null,
            toolChoice: entry.key,
          ),
        );
        expect(runtime.lastToolChoice, hasTools ? entry.value : null);
        expect(runtime.createCallCount, 1);
      });
    }
  }
}
