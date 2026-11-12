import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_chat_templates.dart';
import 'package:test/test.dart';

void main() {
  test('public Qwen3 accessor tracks the installed canonical template', () {
    expect(
      liteRtLmQwen3ChatTemplate,
      kLiteRtLmChatTemplates.singleWhere((item) => item.id == 'qwen3').template,
    );
  });

  for (final thinking in [false, true]) {
    test('public Qwen3 template renders thinking=$thinking', () {
      final rendered = ChatTemplateEngine.render(
        templateSource: liteRtLmQwen3ChatTemplate,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hello'),
        ],
        metadata: const {
          'tokenizer.ggml.bos_token': '',
          'tokenizer.ggml.eos_token': '<|im_end|>',
        },
        addAssistant: true,
        enableThinking: thinking,
      );
      expect(rendered.prompt, contains('<|im_start|>user\nHello<|im_end|>'));
      expect(rendered.prompt.contains('<think>\n\n</think>'), !thinking);
    });
  }
}
