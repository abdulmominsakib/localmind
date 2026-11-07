import 'package:llamadart/src/backends/litert_lm/litert_lm_chat_template.dart';
import 'package:test/test.dart';

void main() {
  group('LiteRtLmChatTemplate', () {
    test('matches normalized family substrings', () {
      const template = LiteRtLmChatTemplate(
        id: 'example',
        template: 'template',
        familyMatches: ['gemma-4', 'gemma4'],
      );

      expect(template.matches('gemma-4-e2b-it.litertlm'), isTrue);
      expect(template.matches('gemma4-e2b-it.litertlm'), isTrue);
      expect(template.matches('qwen3-0.6b.litertlm'), isFalse);
    });

    test('defaults to Gemma 4 thought-channel markers', () {
      const template = LiteRtLmChatTemplate(
        id: 'gemma4',
        template: 'template',
        familyMatches: ['gemma-4'],
      );

      expect(template.thinkingStartTag, '<|channel>thought\n');
      expect(template.thinkingEndTag, '<channel|>');
    });
  });
}
