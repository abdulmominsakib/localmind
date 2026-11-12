import 'package:llamadart/src/backends/llama_cpp/lazy_grammar_triggers.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:test/test.dart';

void main() {
  group('lazyGrammarTriggerInputs', () {
    test('maps each trigger type to a pattern or token', () {
      final inputs = lazyGrammarTriggerInputs(const [
        GenerationGrammarTrigger.typed(
          type: GrammarTriggerType.word,
          value: '<tool_call>(x)',
        ),
        GenerationGrammarTrigger.typed(
          type: GrammarTriggerType.token,
          value: '<tool_call>',
          token: 151657,
        ),
        GenerationGrammarTrigger.typed(
          type: GrammarTriggerType.token,
          value: '42',
        ),
        GenerationGrammarTrigger.typed(
          type: GrammarTriggerType.token,
          value: 'not a token id',
        ),
        GenerationGrammarTrigger.typed(
          type: GrammarTriggerType.pattern,
          value: r'\{"name"',
        ),
        GenerationGrammarTrigger.typed(
          type: GrammarTriggerType.patternFull,
          value: r'[\s\S]*?<call>',
        ),
        GenerationGrammarTrigger.typed(
          type: GrammarTriggerType.patternFull,
          value: r'^anchored$',
        ),
        GenerationGrammarTrigger.typed(
          type: GrammarTriggerType.patternFull,
          value: '',
        ),
      ]);

      expect(inputs.patterns, [
        r'<tool_call>\(x\)',
        r'\{"name"',
        r'^[\s\S]*?<call>$',
        r'^anchored$',
        r'^$',
      ]);
      expect(inputs.tokens, [151657, 42]);
    });

    test('maps raw wire values like their typed equivalents', () {
      const raw = GenerationGrammarTrigger(type: 0, value: 'a.b');

      expect(lazyGrammarTriggerInputs(const [raw]).patterns, [r'a\.b']);
    });

    test('rejects a raw trigger type that is not a wire value', () {
      expect(
        () => lazyGrammarTriggerInputs(const [
          GenerationGrammarTrigger(type: 7, value: '<tool_call>'),
        ]),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });
  });
}
