import 'dart:io';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';

/// The tool of [renderQwen3CoderRequiredCall].
final ToolDefinition qwen3CoderRequiredTool = ToolDefinition(
  name: 'get_weather',
  description: 'w',
  parameters: [ToolParam.string('location', required: true)],
);

/// Vendored Qwen3-Coder XML templates with a thinking flag, and whether
/// llama.cpp (`cd959bae9`) lets the first call leave out `<tool_call>`: only
/// for a template without a thought, as Qwen3-Coder's.
const qwen3CoderRequiredTemplates =
    <({String template, bool enableThinking, bool bareFirstCall})>[
      (
        template: 'test/fixtures/llama_cpp_templates/Qwen3-Coder.jinja',
        enableThinking: true,
        bareFirstCall: true,
      ),
      (
        template: 'test/fixtures/templates/Qwen3_5-0_8B.jinja',
        enableThinking: true,
        bareFirstCall: false,
      ),
      (
        template: 'test/fixtures/templates/Qwen3_5-0_8B.jinja',
        enableThinking: false,
        bareFirstCall: false,
      ),
      (
        template: 'test/fixtures/llama_cpp_templates/StepFun3.5-Flash.jinja',
        enableThinking: true,
        bareFirstCall: false,
      ),
      (
        template: 'test/fixtures/llama_cpp_templates/StepFun3.5-Flash.jinja',
        enableThinking: false,
        bareFirstCall: false,
      ),
      (
        template:
            'test/fixtures/llama_cpp_templates/'
            'NVIDIA-Nemotron-3-Nano-30B-A3B-BF16.jinja',
        enableThinking: true,
        bareFirstCall: false,
      ),
      (
        template:
            'test/fixtures/llama_cpp_templates/'
            'NVIDIA-Nemotron-3-Nano-30B-A3B-BF16.jinja',
        enableThinking: false,
        bareFirstCall: false,
      ),
    ];

/// Renders [template] for a required [qwen3CoderRequiredTool] call.
LlamaChatTemplateResult renderQwen3CoderRequiredCall(
  String template, {
  required bool enableThinking,
  required bool parallelToolCalls,
}) => ChatTemplateEngine.render(
  templateSource: File(template).readAsStringSync(),
  messages: const [
    LlamaChatMessage.fromText(
      role: LlamaChatRole.user,
      text: 'Weather in Paris?',
    ),
  ],
  metadata: const {},
  tools: [qwen3CoderRequiredTool],
  toolChoice: ToolChoice.required,
  parallelToolCalls: parallelToolCalls,
  enableThinking: enableThinking,
);

/// Replies that llama.cpp's required-call grammar for such a template takes
/// (`valid`) and does not (`invalid`), checked against it with
/// `test-gbnf-validator`.
///
/// After a thought, llama.cpp's grammar also takes a `<tool_call>` split
/// between its thought and content rules, each of which may end inside it,
/// as in `<tool_call> ` before a call or, with [parallelToolCalls] false, a
/// second call; its parse then drops what follows the first call. They are
/// invalid here.
({List<String> valid, List<String> invalid}) qwen3CoderRequiredReplies({
  required bool parallelToolCalls,
  required bool bareFirstCall,
}) {
  String call(String location, {bool scope = true}) =>
      '${scope ? '<tool_call>\n' : ''}<function=get_weather>\n'
      '<parameter=location>\n$location\n</parameter>\n'
      '</function>\n</tool_call>';
  final paris = call('Paris');
  final rome = call('Rome');
  final bareParis = call('Paris', scope: false);
  final bareRome = call('Rome', scope: false);
  return (
    valid: [
      paris,
      '$paris\n',
      'Let me check.\n$paris',
      'Let me check.\n\n$paris',
      'plan\n</think>\n\n$paris',
      '<think>\nplan\n</think>\n\nI will look it up.\n$paris',
      'plan</think>A</think>B $paris',
      'Use <function=unknown> here.\n$paris',
      'Use <function=get_weathers> now.\n$paris',
      if (parallelToolCalls) ...[
        '$paris\n$rome',
        'Text.\n$paris$rome',
        '$paris\n\n$rome\n',
      ],
      if (bareFirstCall) ...[
        bareParis,
        'Let me check.\n$bareParis',
        if (parallelToolCalls) '$bareParis\n$rome',
      ] else
        '$bareParis\n$rome',
    ],
    invalid: [
      '',
      'No tool.',
      'plan</think>',
      '$paris\nDone.',
      '<tool_call> $paris',
      paris.replaceFirst('get_weather', 'unknown'),
      '$paris\n$bareRome',
      if (!parallelToolCalls) '$paris\n$rome',
      if (bareFirstCall) ...[
        if (!parallelToolCalls) '$bareParis\n$rome',
        '<function=get_weather> is a tool.\n$paris',
      ] else ...[
        bareParis,
        'Let me check.\n$bareParis',
      ],
    ],
  );
}
