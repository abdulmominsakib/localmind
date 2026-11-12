import 'package:dinja/dinja.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_chat_templates.dart';
import 'package:llamadart/src/core/template/handlers/hermes_handler.dart';

import 'qwen_tool_schema_fixture.dart';

// Exercise the exact consumer override, including native v0.18 content shapes.
final litertQwenTemplate = kLiteRtLmChatTemplates
    .firstWhere((template) => template.id == 'qwen3')
    .template;

({LlamaChatTemplateResult rendered, String legacy, String normalized})
renderLiteRtQwenHistory({required ToolChoice choice, required bool thinking}) {
  final messages = HermesHandler().templateMessages(
    qwenResultHistory(),
    templateSource: litertQwenTemplate,
  );
  final context = <String, dynamic>{
    'messages': messages,
    'tools': choice == ToolChoice.none ? null : [qwenResultTool.toJson()],
    'add_generation_prompt': true,
    'enable_thinking': thinking,
  };
  final template = Template(litertQwenTemplate);
  return (
    rendered: renderQwenResultHistory(
      choice: choice,
      thinking: thinking,
      templateSource: litertQwenTemplate,
    ),
    legacy: template.render(context),
    normalized: template.render({
      ...context,
      'messages': [
        for (final message in messages)
          {
            ...message,
            'content': [
              if (message['role'] == 'tool')
                {'type': 'tool_response', 'response': message['content']}
              else
                {'type': 'text', 'text': message['content']},
            ],
          },
      ],
    }),
  );
}

const litertQwenEnvelope =
    '<tool_call>{"name": "inspect", "arguments": '
    '{"code": "123", "options": {}, "items": [], "count": 7, '
    '"active": true, "empty": null}}</tool_call>';
