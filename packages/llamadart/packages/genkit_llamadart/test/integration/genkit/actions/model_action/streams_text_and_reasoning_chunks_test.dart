import 'package:genkit/genkit.dart' as genkit;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';
import '../test_support/action_harness.dart';

void main() {
  test('model action streams text and reasoning chunks', () async {
    final runtime = FakeRuntime()
      ..createChunks = <dynamic>[
        thinkingChunk('thinking'),
        textChunk('hello'),
        stopChunk(),
      ].cast();
    final action = testModelAction(runtime: runtime);

    final streamed = <genkit.ModelResponseChunk>[];
    final response = await action(
      genkit.ModelRequest(
        messages: <genkit.Message>[
          genkit.Message(
            role: genkit.Role.user,
            content: <genkit.Part>[genkit.TextPart(text: 'Hi')],
          ),
        ],
      ),
      onChunk: streamed.add,
    );

    expect(streamed, hasLength(2));
    expect(streamed.first.content.first.reasoning, 'thinking');
    expect(streamed.last.text, 'hello');
    expect(response.text, 'hello');
    expect(response.message!.content.first.reasoning, 'thinking');
  });
}
