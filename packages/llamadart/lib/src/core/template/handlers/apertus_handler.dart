import 'package:dinja/dinja.dart';

import '../../grammar/json_schema_converter.dart';
import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';
import '../tool_call_grammar_utils.dart';
import '../tool_call_parsing_utils.dart';

/// Handler for Apertus format.
class ApertusHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.apertus;

  @override
  String get thinkingStartTag => '<|inner_prefix|>';

  @override
  String get thinkingEndTag => '<|inner_suffix|>';

  @override
  List<String> get additionalStops => [];

  @override
  List<String> get preservedTokens => const [
    '<|system_start|>',
    '<|system_end|>',
    '<|developer_start|>',
    '<|developer_end|>',
    '<|user_start|>',
    '<|user_end|>',
    '<|assistant_start|>',
    '<|assistant_end|>',
    '<|inner_prefix|>',
    '<|inner_suffix|>',
    '<|tools_prefix|>',
    '<|tools_suffix|>',
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
    final triggerPattern = thinkingForcedOpen
        ? r'[\s\S]*?(<\|inner_suffix\|>\s*)(<\|tools_prefix\|>)[\s\S]*'
        : r'(?:<\|inner_prefix\|>[\s\S]*?<\|inner_suffix\|>\s*)?(<\|tools_prefix\|>)[\s\S]*';
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
          ? [GrammarTrigger(type: 3, value: triggerPattern)]
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
    final thinking = extractThinking(
      output,
      thinkingForcedOpen: thinkingForcedOpen,
      startTag: thinkingStartTag,
      endTag: thinkingEndTag,
    );
    final text = thinking.content;

    if (!parseToolCalls) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    const prefix = '<|tools_prefix|>';
    const suffix = '<|tools_suffix|>';

    final start = text.indexOf(prefix);
    if (start == -1) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    final prelude = text.substring(0, start);
    final payload = text.substring(start + prefix.length);
    final jsonSlice = ToolCallParsingUtils.extractLeadingJsonValue(payload, 0);
    if (jsonSlice == null || jsonSlice.value is! List) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    var cursor = jsonSlice.end;
    while (cursor < payload.length && payload.codeUnitAt(cursor) <= 0x20) {
      cursor++;
    }
    if (!payload.startsWith(suffix, cursor)) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    final toolCalls = ToolCallParsingUtils.parseSingleKeyToolCallArray(
      jsonSlice.value,
      assignFallbackIds: false,
    );
    if (toolCalls == null) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    final trailing = payload.substring(cursor + suffix.length);
    return ChatParseResult(
      content: '$prelude$trailing'.trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    if (tools == null || tools.isEmpty) {
      return null;
    }

    final itemSchemas = tools
        .map(
          (tool) => <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{tool.name: tool.toJsonSchema()},
            'required': <String>[tool.name],
          },
        )
        .toList(growable: false);

    final schema = <String, dynamic>{
      'type': 'array',
      'items': itemSchemas.length == 1
          ? itemSchemas.first
          : <String, dynamic>{'anyOf': itemSchemas},
      'minItems': 1,
    };

    final grammar = JsonSchemaConverter.convert(schema);
    return ToolCallGrammarUtils.wrapRootGrammar(
      grammar,
      prefix: '<|tools_prefix|>',
      suffix: '<|tools_suffix|>',
    );
  }
}
