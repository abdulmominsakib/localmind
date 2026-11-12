import 'dart:io';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';

/// The tool [forcedOpenRequiredCalls] call.
final ToolDefinition forcedOpenRequiredTool = ToolDefinition(
  name: 'get_weather',
  description: 'Weather',
  parameters: [ToolParam.string('location', required: true)],
);

/// Vendored templates that open a thought in the prompt, each with its format
/// and an output that ends the thought and makes one required call.
const forcedOpenRequiredCalls =
    <({String template, ChatFormat format, String output})>[
      (
        template: 'Cohere2MoE.jinja',
        format: ChatFormat.cohere2Moe,
        output:
            'plan<|END_THINKING|><|START_ACTION|>[{"tool_name": "get_weather", '
            '"parameters": {"location": "Paris"}}]<|END_ACTION|>',
      ),
      (
        template: 'openbmb-MiniCPM5-1B.jinja',
        format: ChatFormat.minicpm5,
        output:
            'plan</think><function name="get_weather">'
            '<param name="location">Paris</param></function>',
      ),
      (
        template: 'tencent-Hy3.jinja',
        format: ChatFormat.hunyuanV3,
        output:
            'plan</think:opensource><tool_calls:opensource>\n'
            '<tool_call:opensource>get_weather<tool_sep:opensource>\n'
            '<arg_key:opensource>location</arg_key:opensource>\n'
            '<arg_value:opensource>Paris</arg_value:opensource>\n'
            '</tool_call:opensource>\n</tool_calls:opensource>',
      ),
    ];

/// Renders [template] for a required [forcedOpenRequiredTool] call.
LlamaChatTemplateResult renderForcedOpenRequiredCall(
  String template, {
  bool enableThinking = true,
}) => ChatTemplateEngine.render(
  templateSource: File(
    'test/fixtures/llama_cpp_templates/$template',
  ).readAsStringSync(),
  messages: [
    const LlamaChatMessage.fromText(
      role: LlamaChatRole.user,
      text: 'Weather in Paris?',
    ),
  ],
  metadata: const {},
  tools: [forcedOpenRequiredTool],
  toolChoice: ToolChoice.required,
  enableThinking: enableThinking,
);
