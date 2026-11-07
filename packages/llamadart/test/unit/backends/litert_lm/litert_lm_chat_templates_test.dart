import 'package:llamadart/src/backends/litert_lm/litert_lm_chat_templates.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_chat_template.dart';
import 'package:test/test.dart';

/// Mirrors `LiteRtLmService._resolveBuiltinTemplate`: first match wins.
String? resolveId(String fileName) {
  return resolveTemplate(fileName)?.id;
}

LiteRtLmChatTemplate? resolveTemplate(String fileName) {
  final normalized = fileName.toLowerCase().replaceAll('_', '-');
  for (final template in kLiteRtLmChatTemplates) {
    if (template.matches(normalized)) {
      return template;
    }
  }
  return null;
}

void main() {
  group('LiteRT-LM chat template registry', () {
    test('resolves each seeded family from representative bundle names', () {
      expect(resolveId('gemma-4-E2B-it.litertlm'), 'gemma4');
      expect(resolveId('gemma-4-E4B-it.litertlm'), 'gemma4');
      expect(resolveId('gemma-3n-E2B-it.litertlm'), 'gemma3n');
      expect(resolveId('gemma-3n-E4B-it.litertlm'), 'gemma3n');
      expect(resolveId('gemma-3-4b-it.litertlm'), 'gemma');
      expect(resolveId('gemma-2-2b-it.litertlm'), 'gemma');
      expect(resolveId('Qwen3-0.6B.litertlm'), 'qwen3');
      expect(resolveId('Qwen3.5-2B.litertlm'), 'qwen3');
      expect(resolveId('Qwen2.5-1.5B-Instruct.litertlm'), 'qwen25');
    });

    test('precedence: specific families win over broader ones', () {
      // gemma-4 / gemma-3n must not be swallowed by the gemma-3 entry, and
      // qwen3 must not be swallowed by the qwen entry.
      expect(resolveId('gemma-4-E2B-it.litertlm'), isNot('gemma'));
      expect(resolveId('gemma-3n-E4B-it.litertlm'), isNot('gemma'));
      expect(resolveId('Qwen3-0.6B.litertlm'), isNot('qwen25'));
    });

    test(
      'returns null for unseeded models (caller falls back / overrides)',
      () {
        expect(resolveId('phi-4-mini-instruct.litertlm'), isNull);
        expect(resolveId('some-unknown-model.litertlm'), isNull);
      },
    );

    test('does not mis-route qwen-derived models to the Qwen 2.5 template', () {
      // DeepSeek-R1-Distill-Qwen needs its own handler; the bare `qwen` rule
      // must not greedily claim it.
      expect(resolveId('DeepSeek-R1-Distill-Qwen-1.5B.litertlm'), isNull);
    });

    test('templates omit a leading BOS token (native runtime adds it)', () {
      for (final template in kLiteRtLmChatTemplates) {
        expect(
          template.template,
          isNot(contains('bos_token')),
          reason: '${template.id} must not emit bos_token',
        );
      }
    });

    test(
      'uses parser-compatible thought markers for Qwen/Hermes templates',
      () {
        final gemma4 = resolveTemplate('gemma-4-E2B-it.litertlm')!;
        final qwen3 = resolveTemplate('Qwen3-0.6B.litertlm')!;
        final qwen25 = resolveTemplate('Qwen2.5-1.5B-Instruct.litertlm')!;

        expect(gemma4.thinkingStartTag, '<|channel>thought\n');
        expect(gemma4.thinkingEndTag, '<channel|>');
        expect(qwen3.thinkingStartTag, '<think>');
        expect(qwen3.thinkingEndTag, '</think>');
        expect(qwen25.thinkingStartTag, '<think>');
        expect(qwen25.thinkingEndTag, '</think>');
      },
    );
  });
}
