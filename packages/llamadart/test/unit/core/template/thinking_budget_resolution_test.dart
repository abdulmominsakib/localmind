import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  final qwenXml = ChatFormat.qwen3CoderXml.index;
  final noPrefix = ChatFormat.hermes.index;

  group('ChatTemplateEngine.resolveThinkingBudget', () {
    test('fills tags and closes a Qwen3-Coder XML thought with a newline', () {
      final tags = ChatTemplateEngine.thinkingTagsFor(qwenXml);
      final resolved = ChatTemplateEngine.resolveThinkingBudget(
        qwenXml,
        const ThinkingBudget(maxTokens: 8),
      );

      expect(resolved.maxTokens, 8);
      expect(resolved.startTag, tags.startTag);
      expect(resolved.endTag, tags.endTag);
      expect(resolved.forcedMessage, '\n');
    });

    test('appends the prefix to a caller forced message', () {
      final resolved = ChatTemplateEngine.resolveThinkingBudget(
        qwenXml,
        const ThinkingBudget(maxTokens: 8, forcedMessage: 'Out of budget.'),
      );

      expect(resolved.forcedMessage, 'Out of budget.\n');
    });

    test('adds no prefix for a format without one', () {
      final resolved = ChatTemplateEngine.resolveThinkingBudget(
        noPrefix,
        const ThinkingBudget(maxTokens: 8),
      );

      expect(resolved.forcedMessage, isNull);
    });

    test('keeps a caller forced message for a format without a prefix', () {
      final resolved = ChatTemplateEngine.resolveThinkingBudget(
        noPrefix,
        const ThinkingBudget(maxTokens: 8, forcedMessage: 'Stop.'),
      );

      expect(resolved.forcedMessage, 'Stop.');
    });

    test('leaves a caller end tag and its forced message as given', () {
      final resolved = ChatTemplateEngine.resolveThinkingBudget(
        qwenXml,
        const ThinkingBudget(
          maxTokens: 8,
          startTag: '<a>',
          endTag: '</a>',
          forcedMessage: 'Stop.',
        ),
      );

      expect(resolved.startTag, '<a>');
      expect(resolved.endTag, '</a>');
      expect(resolved.forcedMessage, 'Stop.');
    });

    test('adds no prefix when the backend does not render the prompt', () {
      final resolved = ChatTemplateEngine.resolveThinkingBudget(
        qwenXml,
        const ThinkingBudget(maxTokens: 8),
        rendersPrompt: false,
      );

      expect(resolved.forcedMessage, isNull);
    });

    test('takes the generic tags for an index past the end of ChatFormat', () {
      final resolved = ChatTemplateEngine.resolveThinkingBudget(
        ChatFormat.values.length,
        const ThinkingBudget(maxTokens: 8),
      );

      expect(resolved.startTag, '<think>');
      expect(resolved.endTag, '</think>');
      expect(resolved.forcedMessage, isNull);
      expect(ChatTemplateEngine.thinkingTagsFor(ChatFormat.values.length), (
        startTag: '<think>',
        endTag: '</think>',
      ));
    });

    test('throws RangeError for a negative index', () {
      expect(
        () => ChatTemplateEngine.resolveThinkingBudget(
          -1,
          const ThinkingBudget(maxTokens: 8),
        ),
        throwsRangeError,
      );
      expect(() => ChatTemplateEngine.thinkingTagsFor(-1), throwsRangeError);
    });
  });
}
