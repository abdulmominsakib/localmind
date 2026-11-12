import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit_llamadart/src/integration/genkit/converters/genkit_to_llama.dart';
import 'package:test/test.dart';

void main() {
  test('toLlamaMessages expands tool response messages', () {
    final messages = <genkit.Message>[
      genkit.Message(
        role: genkit.Role.tool,
        content: <genkit.Part>[
          genkit.ToolResponsePart(
            toolResponse: genkit.ToolResponse(
              ref: 'call-1',
              name: 'lookup',
              output: 'sunny',
            ),
          ),
          genkit.ToolResponsePart(
            toolResponse: genkit.ToolResponse(
              ref: 'call-2',
              name: 'lookup',
              output: 'windy',
            ),
          ),
        ],
      ),
      genkit.Message(
        role: genkit.Role.user,
        content: <genkit.Part>[genkit.TextPart(text: 'hello')],
      ),
    ];

    final converted = toLlamaMessages(messages);

    expect(converted, hasLength(3));
    expect(converted.first.role.name, 'tool');
    expect(converted[1].role.name, 'tool');
    expect(converted.last.content, 'hello');
    expect(converted.first.content, contains('sunny'));
    expect(converted[1].content, contains('windy'));
  });
}
