import 'package:genkit/genkit.dart' as genkit;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';
import '../test_support/action_harness.dart';

void main() {
  test(
    'model action returns tool requests from final tool call chunk',
    () async {
      final runtime = FakeRuntime()
        ..createChunks = <dynamic>[
          toolCallChunk(
            id: 'call-1',
            name: 'get_weather',
            arguments: '{"city":"Seoul"}',
          ),
        ].cast();
      final action = testModelAction(runtime: runtime);

      final response = await action(
        genkit.ModelRequest(
          messages: <genkit.Message>[
            genkit.Message(
              role: genkit.Role.user,
              content: <genkit.Part>[genkit.TextPart(text: 'Weather?')],
            ),
          ],
          tools: <genkit.ToolDefinition>[
            genkit.ToolDefinition(
              name: 'get_weather',
              description: 'Get weather',
              inputSchema: <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{
                  'city': <String, dynamic>{'type': 'string'},
                },
              },
            ),
          ],
        ),
      );

      expect(response.toolRequests, hasLength(1));
      expect(response.toolRequests.single.name, 'get_weather');
      expect(response.toolRequests.single.input, <String, dynamic>{
        'city': 'Seoul',
      });
      expect(response.raw, isNot(contains('path')));
      expect(response.usage!.outputCharacters, '{"city":"Seoul"}'.length);
    },
  );
}
