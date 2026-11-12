import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';
import '../tool_call_parsing_utils.dart';
import '../tool_call_grammar_utils.dart';

/// Handler for Nemotron V2 format.
class NemotronV2Handler extends ChatTemplateHandler {
  static const String _toolCallPrefix = '<TOOLCALL>';

  /// Finds where [parse] may find a tool-call opening in [text].
  ///
  /// Returns the first index at or after [from] where `<TOOLCALL>`
  /// starts, or where the rest of [text] is the start of it, and
  /// `text.length` when there is none.
  static int toolCallOpening(String text, [int from = 0]) =>
      ToolCallParsingUtils.literalOpening(text, const [_toolCallPrefix], from);

  @override
  ChatFormat get format => ChatFormat.nemotronV2;

  @override
  List<String> get additionalStops => [];

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
        'messages': templateMessages(messages, templateSource: templateSource),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
      },
    );

    var thinkingForcedOpen = false;
    var thoughtClosed = false;
    if (isThinkingForcedOpen(prompt)) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}</think>';
        thoughtClosed = true;
      } else {
        thinkingForcedOpen = true;
      }
    }

    final hasTools = tools != null && tools.isNotEmpty;
    final triggerPattern = thinkingForcedOpen
        ? r'[\s\S]*?(</think>\s*)(<TOOLCALL>)[\s\S]*'
        : r'(?:<think>[\s\S]*?</think>\s*)?(<TOOLCALL>)[\s\S]*';
    final rendered = LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: buildGrammar(tools),
      grammarLazy: hasTools,
      thinkingForcedOpen: thinkingForcedOpen,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      grammarTriggers: hasTools
          ? [GrammarTrigger(type: 3, value: triggerPattern)]
          : [],
    );
    return withThoughtClosedForThinkingOff(rendered, closed: thoughtClosed);
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
    );
    final text = thinking.content;

    if (!parseToolCalls) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    const suffix = '</TOOLCALL>';

    final start = text.indexOf(_toolCallPrefix);
    if (start == -1) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    final prelude = text.substring(0, start);
    final payload = text.substring(start + _toolCallPrefix.length);
    final jsonSlice = ToolCallParsingUtils.extractLeadingJsonValue(payload, 0);
    if (jsonSlice == null || jsonSlice.value is! List) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    if (!payload.startsWith(suffix, jsonSlice.end)) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    final toolCalls = ToolCallParsingUtils.parseToolCallArray(
      jsonSlice.value,
      assignFallbackIds: false,
    );
    if (toolCalls == null) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    final trailing = payload.substring(jsonSlice.end + suffix.length);
    return ChatParseResult(
      content: '$prelude$trailing'.trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return ToolCallGrammarUtils.buildWrappedArrayGrammar(
      tools: tools,
      prefix: '<TOOLCALL>',
      suffix: '</TOOLCALL>',
    );
  }
}
