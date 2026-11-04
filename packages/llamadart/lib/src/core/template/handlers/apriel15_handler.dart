import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';
import '../xml_tool_call_format.dart';

/// Handler for Apriel 1.5 format.
///
/// Uses `<thinking>` tags for reasoning and `<tool_calls>[...]</tool_calls>`
/// for tool call arrays.
class Apriel15Handler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.apriel15;

  @override
  String get thinkingStartTag => '<thinking>';

  @override
  String get thinkingEndTag => '</thinking>';

  @override
  List<String> get additionalStops => [];

  @override
  List<String> get preservedTokens => const [
    '<thinking>',
    '</thinking>',
    '<tool_calls>',
    '</tool_calls>',
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
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
      },
    );

    var thinkingForcedOpen = false;
    if (isThinkingForcedOpen(prompt, startTag: thinkingStartTag)) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}$thinkingEndTag';
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
          ? [const GrammarTrigger(type: 0, value: '<tool_calls>[{"name": "')]
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
    final parsed = parseXmlToolCalls(
      output,
      XmlToolCallFormat.apriel15,
      startThink: thinkingStartTag,
      endThink: thinkingEndTag,
      parseToolCalls: parseToolCalls,
    );
    return ChatParseResult(
      content: parsed.content.trim(),
      reasoningContent: parsed.reasoningContent,
      toolCalls: parsed.toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return buildXmlToolCallGrammar(tools, XmlToolCallFormat.apriel15);
  }
}
