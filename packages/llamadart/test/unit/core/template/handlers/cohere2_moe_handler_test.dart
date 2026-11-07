import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/handlers/cohere2_moe_handler.dart';
import 'package:test/test.dart';

void main() {
  test('Cohere2MoeHandler exposes North Code stops and format', () {
    final handler = Cohere2MoeHandler();

    expect(handler.format, ChatFormat.cohere2Moe);
    expect(handler.getStops(hasTools: false), contains('<|END_TEXT|>'));
    expect(handler.getStops(hasTools: true), contains('<|END_ACTION|>'));
  });

  test('ChatTemplateEngine routes START_TEXT templates to Cohere2MoeHandler', () {
    const template =
        '{{ bos_token }}{% for message in messages %}<|START_OF_TURN_TOKEN|><|USER_TOKEN|>{{ message.content }}<|END_OF_TURN_TOKEN|>{% endfor %}{% if add_generation_prompt %}<|START_OF_TURN_TOKEN|><|CHATBOT_TOKEN|>{% if enable_thinking %}<|START_THINKING|>{% else %}<|START_THINKING|><|END_THINKING|>{% endif %}{% endif %}<|START_TEXT|>{{ content }}<|END_TEXT|><|START_ACTION|>[]<|END_ACTION|>';
    final rendered = ChatTemplateEngine.render(
      templateSource: template,
      messages: const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
      ],
      metadata: const {'tokenizer.ggml.bos_token': '<s>'},
      tools: const <ToolDefinition>[],
      enableThinking: false,
    );

    expect(rendered.format, ChatFormat.cohere2Moe.index);
    expect(rendered.prompt, contains('<|END_THINKING|>'));
    expect(rendered.additionalStops, contains('<|END_TEXT|>'));
  });
}
