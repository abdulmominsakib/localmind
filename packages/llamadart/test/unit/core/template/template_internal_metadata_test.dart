import 'package:llamadart/src/core/template/template_internal_metadata.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/template/thinking_utils.dart';
import 'package:test/test.dart';

void main() {
  test(
    'LFM auto policy follows exact grammar copies, not replaced or unmarked grammars',
    () {
      final source = withLfm2AutoGrammar(
        const LlamaChatTemplateResult(
          prompt: '<think>',
          grammar: 'root ::= "ok"',
          grammarLazy: true,
        ),
        enabled: true,
      );
      final thoughtCopy = withTemplateOpenedThought(
        source,
        startTag: '<think>',
      );
      expect(thoughtCopy.thinkingForcedOpen, isTrue);
      expect(isLfm2AutoGrammar(thoughtCopy), isTrue);
      for (final (grammar, lazy, expected) in [
        (source.grammar, true, true),
        ('root ::= "replaced"', true, false),
        (source.grammar, false, false),
      ]) {
        final copy = withThoughtMarksOf(
          LlamaChatTemplateResult(
            prompt: 'copy',
            grammar: grammar,
            grammarLazy: lazy,
          ),
          source,
        );
        expect(isLfm2AutoGrammar(copy), expected);
      }
      final ordinary = LlamaChatTemplateResult(
        prompt: '<think>',
        grammar: source.grammar,
        grammarLazy: true,
      );
      expect(
        isLfm2AutoGrammar(
          withTemplateOpenedThought(ordinary, startTag: '<think>'),
        ),
        isFalse,
      );
    },
  );

  test('withSingleToolCall marks a result, and copies keep the mark', () {
    LlamaChatTemplateResult result() => LlamaChatTemplateResult(prompt: 'p');
    final single = withSingleToolCall(result(), single: true);
    final unmarked = withSingleToolCall(result(), single: false);
    expect(singleToolCallOf(single), isTrue);
    expect(singleToolCallOf(unmarked), isFalse);
    expect(singleToolCallOf(withThoughtMarksOf(result(), single)), isTrue);
    expect(singleToolCallOf(withThoughtMarksOf(result(), unmarked)), isFalse);
  });

  test('withBareFirstCall marks a result, and copies keep the mark', () {
    LlamaChatTemplateResult result() => LlamaChatTemplateResult(prompt: 'p');
    final bare = withBareFirstCall(result(), bare: true);
    final unmarked = withBareFirstCall(result(), bare: false);
    expect(bareFirstCallOf(bare), isTrue);
    expect(bareFirstCallOf(unmarked), isFalse);
    expect(bareFirstCallOf(withThoughtMarksOf(result(), bare)), isTrue);
    expect(bareFirstCallOf(withThoughtMarksOf(result(), unmarked)), isFalse);
  });

  group('chatTemplateKwargsFromMetadata', () {
    test('decodes the stored kwargs object', () {
      expect(
        chatTemplateKwargsFromMetadata({
          internalChatTemplateKwargsMetadataKey: '{"a": 1, "b": "x"}',
        }),
        {'a': 1, 'b': 'x'},
      );
    });

    test('returns an empty map for missing or unreadable kwargs', () {
      expect(chatTemplateKwargsFromMetadata(const {}), isEmpty);
      expect(
        chatTemplateKwargsFromMetadata({
          internalChatTemplateKwargsMetadataKey: '  ',
        }),
        isEmpty,
      );
      expect(
        chatTemplateKwargsFromMetadata({
          internalChatTemplateKwargsMetadataKey: '[1, 2]',
        }),
        isEmpty,
      );
      expect(
        chatTemplateKwargsFromMetadata({
          internalChatTemplateKwargsMetadataKey: '{not json',
        }),
        isEmpty,
      );
    });
  });
}
