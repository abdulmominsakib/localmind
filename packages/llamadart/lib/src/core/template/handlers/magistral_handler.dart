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

/// Handler for Magistral format.
///
/// A variant of Mistral Nemo that supports thinking/reasoning with
/// `[THINK]`/`[/THINK]` tags, alongside `[TOOL_CALLS]` for function calling.
class MagistralHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.magistral;

  @override
  String get thinkingStartTag => '[THINK]';

  @override
  String get thinkingEndTag => '[/THINK]';

  @override
  List<String> get additionalStops => ['</s>'];

  @override
  List<String> get preservedTokens => const ['[THINK]', '[/THINK]'];

  @override
  List<String> getStops({bool hasTools = false, bool enableThinking = true}) {
    return [...additionalStops, if (hasTools) '[TOOL_CALLS]'];
  }

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

    // Handle enableThinking post-render logic
    var thinkingForcedOpen = false;
    if (isThinkingForcedOpen(prompt, startTag: thinkingStartTag)) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}$thinkingEndTag\n';
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
      preservedTokens: hasTools
          ? const ['[THINK]', '[/THINK]', '[TOOL_CALLS]']
          : preservedTokens,
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: '[TOOL_CALLS]')]
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
    final trimmed = text.trim();

    if (!parseToolCalls) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    const prefix = '[TOOL_CALLS]';
    final markerIdx = text.indexOf(prefix);
    if (markerIdx == -1) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    final contentBefore = text.substring(0, markerIdx);
    final payload = text.substring(markerIdx + prefix.length);
    var cursor = 0;
    while (cursor < payload.length && payload.codeUnitAt(cursor) <= 0x20) {
      cursor++;
    }
    final jsonSlice = ToolCallParsingUtils.extractLeadingJsonValue(
      payload,
      cursor,
    );
    if (jsonSlice == null || jsonSlice.value is! List) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    final toolCalls = ToolCallParsingUtils.parseToolCallArray(
      jsonSlice.value,
      assignFallbackIds: false,
    );
    if (toolCalls == null) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    final trailing = payload.substring(jsonSlice.end);
    if (trailing.isNotEmpty) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    return ChatParseResult(
      content: contentBefore.trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return ToolCallGrammarUtils.buildWrappedArrayGrammar(
      tools: tools,
      prefix: '[TOOL_CALLS]',
      suffix: '',
      idKey: 'id',
      idPattern: r'^[a-zA-Z0-9]{9}$',
    );
  }
}
