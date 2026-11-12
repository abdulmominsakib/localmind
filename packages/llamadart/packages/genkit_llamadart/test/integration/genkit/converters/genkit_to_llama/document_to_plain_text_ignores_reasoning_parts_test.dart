import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit_llamadart/src/integration/genkit/converters/genkit_to_llama.dart';
import 'package:test/test.dart';

void main() {
  test('documentToPlainText ignores reasoning parts', () {
    final text = documentToPlainText(
      genkit.DocumentData(
        content: <genkit.Part>[
          genkit.TextPart(text: 'hello'),
          genkit.ReasoningPart(reasoning: 'internal'),
          genkit.TextPart(text: ' world'),
        ],
      ),
    );

    expect(text, 'hello world');
  });
}
