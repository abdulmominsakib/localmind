import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';
import '../xml_tool_call_format.dart';

/// Handler for Seed-OSS format.
///
/// Uses `<seed:think>`/`</seed:think>` for reasoning and
/// `<seed:tool_call><function=...>...</function></seed:tool_call>` for tools.
class SeedOssHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.seedOss;

  @override
  TemplateToolCallSerialization get toolCallSerialization =>
      TemplateToolCallSerialization.normalizeOnly;

  @override
  String get thinkingStartTag => '<seed:think>';

  @override
  String get thinkingEndTag => '</seed:think>';

  @override
  List<String> get additionalStops => [];

  @override
  List<String> get preservedTokens => const [
    '<seed:think>',
    '</seed:think>',
    '<seed:tool_call>',
    '</seed:tool_call>',
    '<function=',
    '</function>',
    '<parameter=',
    '</parameter>',
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
          ? [const GrammarTrigger(type: 0, value: '<seed:tool_call><function=')]
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
      XmlToolCallFormat.seedOss,
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
    return buildXmlToolCallGrammar(tools, XmlToolCallFormat.seedOss);
  }
}
