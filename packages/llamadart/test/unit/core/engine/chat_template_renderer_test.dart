import 'package:llamadart/src/core/engine/chat_template_renderer.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:test/test.dart';

void main() {
  group('ChatTemplateRenderer', () {
    test('renders a template and counts tokens when requested', () async {
      var tokenizeAddSpecial = true;
      final result = await ChatTemplateRenderer.render(
        loadMetadata: () async => const {},
        tokenize: (text, {bool addSpecial = true}) async {
          tokenizeAddSpecial = addSpecial;
          return [1, 2, 3];
        },
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        customTemplate:
            '{{ messages[0]["role"] }}: {{ messages[0]["content"] }}'
            '{% if add_generation_prompt %} assistant:{% endif %}',
      );

      expect(result.prompt, contains('user: hello'));
      expect(result.prompt, contains('assistant:'));
      expect(result.tokenCount, 3);
      expect(tokenizeAddSpecial, isFalse);
    });

    test('skips token count when tokenization is unsupported', () async {
      final result = await ChatTemplateRenderer.render(
        loadMetadata: () async => const {},
        tokenize: (text, {bool addSpecial = true}) async {
          throw UnsupportedError('tokenization unavailable');
        },
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        customTemplate: '{{ messages[0]["content"] }}',
      );

      expect(result.prompt, 'hello');
      expect(result.tokenCount, isNull);
    });
  });
}
