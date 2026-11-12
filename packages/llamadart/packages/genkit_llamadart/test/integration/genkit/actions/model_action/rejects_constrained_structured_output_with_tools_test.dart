import 'package:genkit/genkit.dart' as genkit;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';
import '../test_support/action_harness.dart';

void main() {
  test(
    'model action rejects constrained structured output with tools',
    () async {
      final action = testModelAction(runtime: FakeRuntime());

      expect(
        () => action(
          genkit.ModelRequest(
            messages: <genkit.Message>[
              genkit.Message(
                role: genkit.Role.user,
                content: <genkit.Part>[genkit.TextPart(text: 'JSON please')],
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
            output: genkit.OutputConfig(
              format: 'json',
              schema: <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{
                  'answer': <String, dynamic>{'type': 'string'},
                },
              },
              constrained: true,
            ),
          ),
        ),
        throwsA(
          isA<genkit.GenkitException>().having(
            (error) => error.status,
            'status',
            genkit.StatusCode.unimplemented,
          ),
        ),
      );
    },
  );
}
