import 'package:genkit/genkit.dart' as genkit;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';
import '../test_support/action_harness.dart';

void main() {
  test(
    'unmeasurable tool argument characters do not fail the model response',
    () async {
      final runtime = FakeRuntime()
        ..createChunks = [
          toolCallChunk(id: 'r', name: 'lookup', arguments: '{"value":1e400}'),
        ];
      final response = await testModelAction(runtime: runtime)(
        genkit.ModelRequest(
          messages: [
            genkit.Message(
              role: genkit.Role.user,
              content: [genkit.TextPart(text: 'lookup')],
            ),
          ],
          tools: [
            genkit.ToolDefinition(
              name: 'lookup',
              description: 'Lookup',
              inputSchema: {
                'type': 'object',
                'properties': {
                  'value': {'type': 'number'},
                },
              },
            ),
          ],
        ),
      );
      expect(response.finishReason, genkit.FinishReason.stop);
      expect(
        (response.toolRequests.single.input as Map)['value'],
        double.infinity,
      );
      expect(response.usage!.outputCharacters, isNull);
      expect(response.usage!.inputCharacters, 6);
      expect(response.usage!.outputImages, 0);
    },
  );

  test(
    'counts delivered history, tool and media content once after streaming',
    () async {
      final runtime = FakeRuntime()
        ..createChunks = [
          thinkingChunk('why'),
          textChunk('o'),
          textChunk('k'),
          stopChunk(),
        ];
      final action = testModelAction(runtime: runtime);
      final chunks = <genkit.ModelResponseChunk>[];
      final response = await action(
        genkit.ModelRequest(
          messages: [
            genkit.Message(
              role: genkit.Role.system,
              content: [genkit.TextPart(text: 's')],
            ),
            genkit.Message(
              role: genkit.Role.user,
              content: [
                genkit.TextPart(text: 'Hi😀'),
                genkit.MediaPart(
                  media: genkit.Media(
                    url: 'data:image/png;base64,AA==',
                    contentType: 'image/png',
                  ),
                ),
                genkit.MediaPart(
                  media: genkit.Media(
                    url: 'data:audio/wav;base64,AA==',
                    contentType: 'audio/wav',
                  ),
                ),
              ],
            ),
            genkit.Message(
              role: genkit.Role.model,
              content: [
                genkit.ReasoningPart(reasoning: 'omitted'),
                genkit.TextPart(text: 'a'),
                genkit.ToolRequestPart(
                  toolRequest: genkit.ToolRequest(
                    name: 'lookup',
                    ref: 'r',
                    input: {'x': 1},
                  ),
                ),
              ],
            ),
            genkit.Message(
              role: genkit.Role.tool,
              content: [
                genkit.ToolResponsePart(
                  toolResponse: genkit.ToolResponse(
                    name: 'lookup',
                    ref: 'r',
                    output: {'ignored': true},
                    content: [
                      genkit.TextPart(text: 'one'),
                      genkit.TextPart(text: 'two'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        onChunk: chunks.add,
      );
      expect(chunks, isNotEmpty);
      expect(response.usage!.inputCharacters, 20);
      expect(response.usage!.outputCharacters, 5);
      expect(response.usage!.inputImages, 1);
      expect(response.usage!.inputAudioFiles, 1);
      expect(response.usage!.outputImages, 0);
      expect(response.usage!.outputAudioFiles, 0);
      expect(response.usage!.inputTokens, isNull);
      expect(response.usage!.thoughtsTokens, isNull);
      expect(response.usage!.inputVideos, isNull);
      expect(runtime.lastMessages![2].reasoning, isNull);
    },
  );
}
