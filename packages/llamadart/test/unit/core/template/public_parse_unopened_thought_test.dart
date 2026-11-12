import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  for (final format in [
    ChatFormat.hermes,
    ChatFormat.deepseekV3,
    ChatFormat.qwen3CoderXml,
  ]) {
    test(
      'parse ends a thought at an end tag before any start tag: $format',
      () {
        final parsed = ChatTemplateEngine.parse(
          format.index,
          'Plan.</think>Answer.',
        );

        expect(parsed.reasoningContent, 'Plan.');
        expect(parsed.content, 'Answer.');
      },
    );
  }
}
