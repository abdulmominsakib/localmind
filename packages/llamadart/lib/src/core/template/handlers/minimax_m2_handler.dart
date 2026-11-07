import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../xml_tool_call_format.dart';

/// Handler for MiniMax M2 format.
///
/// Uses generic XML tool call parser logic.
class MinimaxM2Handler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.minimaxM2;

  @override
  TemplateToolCallSerialization get toolCallSerialization =>
      TemplateToolCallSerialization.normalizeOnly;

  @override
  List<String> get additionalStops => ['<|end_of_text|>'];

  @override
  List<String> get preservedTokens => const [
    '<think>',
    '</think>',
    '<minimax:tool_call>',
    '</minimax:tool_call>',
  ];

  @override
  LlamaChatTemplateResult render({
    required String templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    bool enableThinking = true,
  }) {
    final template = Template(templateSource);
    var prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': templateMessages(messages),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'bos_token':
            metadata['tokenizer.ggml.bos_token'] ?? '<|begin_of_text|>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '<|end_of_text|>',
      },
    );

    var thinkingForcedOpen = false;
    if (prompt.endsWith('<think>\n')) {
      if (!enableThinking) {
        prompt = '$prompt</think>\n\n';
      } else {
        thinkingForcedOpen = true;
      }
    }

    final hasTools = tools != null && tools.isNotEmpty;
    return LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: buildGrammar(tools),
      grammarLazy: hasTools,
      thinkingForcedOpen: thinkingForcedOpen,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      preservedTokens: hasTools ? preservedTokens : const [],
      grammarTriggers: hasTools
          ? [
              const GrammarTrigger(
                type: 0,
                value: '<minimax:tool_call>\n<invoke name="',
              ),
            ]
          : [],
    );
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    final result = parseXmlToolCalls(
      output,
      XmlToolCallFormat.minimaxM2,
      startThink: '<think>',
      endThink: '</think>',
      parseToolCalls: parseToolCalls,
    );
    return ChatParseResult(
      content: result.content.trim(),
      reasoningContent: result.reasoningContent,
      toolCalls: result.toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return buildXmlToolCallGrammar(tools, XmlToolCallFormat.minimaxM2);
  }
}
