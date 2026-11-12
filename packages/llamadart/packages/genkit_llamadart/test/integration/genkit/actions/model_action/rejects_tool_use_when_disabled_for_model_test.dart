import 'package:genkit/genkit.dart' as genkit;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';
import '../test_support/action_harness.dart';

void main() {
  test('model action rejects tool use when disabled for the model', () async {
    final action = testModelAction(
      runtime: FakeRuntime(),
      definition: testModelDefinition(supportsTools: false),
    );

    expect(
      () => action(
        genkit.ModelRequest(
          messages: <genkit.Message>[
            genkit.Message(
              role: genkit.Role.user,
              content: <genkit.Part>[genkit.TextPart(text: 'Use a tool')],
            ),
          ],
          tools: <genkit.ToolDefinition>[
            genkit.ToolDefinition(
              name: 'lookup',
              description: 'Lookup a value',
              inputSchema: <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{},
              },
            ),
          ],
        ),
      ),
      throwsA(
        isA<genkit.GenkitException>().having(
          (error) => error.status,
          'status',
          genkit.StatusCode.failedPrecondition,
        ),
      ),
    );
  });
}
