import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';

// Exact affected model template; provenance is in fixtures/Qwen3_5-0_8B.md.
const qwenResultTemplatePath = 'test/fixtures/templates/Qwen3_5-0_8B.jinja';
const qwenResultPayload = <String, dynamic>{
  'code': '123',
  'options': <String, dynamic>{},
  'items': <Object?>[],
  'count': 7,
  'active': true,
  'empty': null,
};
final qwenResultTool = ToolDefinition(
  name: 'inspect',
  description: 'Report the typed values from the previous tool result.',
  parameters: [
    ToolParam.string('code', required: true),
    ToolParam.object('options', properties: [], required: true),
    ToolParam.array(
      'items',
      itemType: ToolParam.string('item'),
      required: true,
    ),
    ToolParam.integer('count', required: true),
    ToolParam.boolean('active', required: true),
    ToolParam.nullType('empty', required: true),
  ],
  handler: (_) async => qwenResultPayload,
);

List<LlamaChatMessage> qwenResultHistory({bool stringControl = false}) => [
  const LlamaChatMessage.fromText(
    role: LlamaChatRole.user,
    text: 'Inspect these values.',
  ),
  LlamaChatMessage.withContent(
    role: LlamaChatRole.assistant,
    content: [
      LlamaToolCallContent(
        id: 'call_0',
        name: 'inspect',
        arguments: qwenResultPayload,
        rawJson: jsonEncode(qwenResultPayload),
      ),
    ],
  ),
  LlamaChatMessage.withContent(
    role: LlamaChatRole.tool,
    content: [
      LlamaToolResultContent(
        id: 'call_0',
        name: 'inspect',
        result: stringControl
            ? jsonEncode(qwenResultPayload)
            : qwenResultPayload,
      ),
    ],
  ),
  const LlamaChatMessage.fromText(
    role: LlamaChatRole.user,
    text: 'Use inspect again with the same values.',
  ),
];

LlamaChatTemplateResult renderQwenResultHistory({
  ToolChoice choice = ToolChoice.required,
  bool thinking = true,
  bool stringControl = false,
}) => ChatTemplateEngine.render(
  templateSource: File(qwenResultTemplatePath).readAsStringSync(),
  messages: qwenResultHistory(stringControl: stringControl),
  metadata: const {},
  tools: [qwenResultTool],
  toolChoice: choice,
  enableThinking: thinking,
);

// Qwen XML envelope shape follows pinned llama.cpp test-chat.cpp Qwen3.5
// emissions; numeric-looking strings and empty containers exercise schema types.
const qwenResultEnvelope =
    '<tool_call>\n<function=inspect>\n'
    '<parameter=code>\n123\n</parameter>\n'
    '<parameter=options>\n{}\n</parameter>\n'
    '<parameter=items>\n[]\n</parameter>\n'
    '<parameter=count>\n7\n</parameter>\n'
    '<parameter=active>\ntrue\n</parameter>\n'
    '<parameter=empty>\nnull\n</parameter>\n'
    '</function>\n</tool_call>';
