import 'package:dinja/dinja.dart';

import '../../grammar/json_schema_converter.dart';
import '../../models/chat/chat_role.dart';
import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';
import '../tool_call_parsing_utils.dart';
import '../tool_call_grammar_utils.dart';

/// Handler for DeepSeek V3.1 format.
///
/// Similar to Hermes with `<tool_call>` tags but uses prefix-based thinking
/// and `<|end_of_sentence|>` stop token.
class DeepseekV3Handler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.deepseekV3;

  @override
  List<String> get additionalStops => ['<｜end▁of▁sentence｜>'];

  @override
  List<String> get preservedTokens => const [
    '<think>',
    '</think>',
    '<｜tool▁calls▁begin｜>',
    '<｜tool▁call▁begin｜>',
    '<｜tool▁sep｜>',
    '<｜tool▁call▁end｜>',
    '<｜tool▁calls▁end｜>',
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
    final bosToken =
        metadata['tokenizer.ggml.bos_token'] ?? '<|begin_of_sentence|>';
    final eosToken =
        metadata['tokenizer.ggml.eos_token'] ?? '<|end_of_sentence|>';

    // Prepend bos_token to the first system message if it exists
    final modifiedMessages = messages.map((m) {
      if (m.role == LlamaChatRole.system && m == messages.first) {
        return m.copyWith(content: '$bosToken${m.content}');
      }
      return m;
    }).toList();

    var prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': modifiedMessages.map((m) => m.toJson()).toList(),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'bos_token': bosToken,
        'eos_token': eosToken,
      },
    );

    // Handle enableThinking post-render logic
    var thinkingForcedOpen = false;
    if (isThinkingForcedOpen(prompt)) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}</think>\n';
      } else {
        thinkingForcedOpen = true;
      }
    }

    final hasTools = tools != null && tools.isNotEmpty;
    final triggerPattern = thinkingForcedOpen
        ? r'[\s\S]*?(</think>\s*)(<｜tool▁calls▁begin｜>|<｜tool_calls_begin｜>|<｜tool calls begin｜>|<｜tool\\_calls\\_begin｜>|<｜tool▁calls｜>)[\s\S]*'
        : r'(?:<think>[\s\S]*?</think>\s*)?(<｜tool▁calls▁begin｜>|<｜tool_calls_begin｜>|<｜tool calls begin｜>|<｜tool\\_calls\\_begin｜>|<｜tool▁calls｜>)[\s\S]*';
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
    final hasClosingThink = output.contains('</think>');

    // Match llama.cpp DeepSeek-V3 behavior:
    // if thinking is forced-open and final output has no closing think tag,
    // treat output as regular content/tool-call channel (not reasoning).
    if (thinkingForcedOpen && !isPartial && !hasClosingThink) {
      return _parseContentAndToolCalls(
        output,
        reasoning: null,
        parseToolCalls: parseToolCalls,
      );
    }

    final thinking = extractThinking(
      output,
      thinkingForcedOpen: thinkingForcedOpen,
    );
    return _parseContentAndToolCalls(
      thinking.content,
      reasoning: thinking.reasoning,
      parseToolCalls: parseToolCalls,
    );
  }

  ChatParseResult _parseContentAndToolCalls(
    String text, {
    required String? reasoning,
    required bool parseToolCalls,
  }) {
    if (!parseToolCalls) {
      return ChatParseResult(content: text.trim(), reasoningContent: reasoning);
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    var contentText = text;
    final toolsBlockRegex = RegExp(
      r'(<｜tool▁calls▁begin｜>|<｜tool_calls_begin｜>|<｜tool calls begin｜>|<｜tool\\_calls\\_begin｜>|<｜tool▁calls｜>)([\s\S]*?)<｜tool▁calls▁end｜>',
      dotAll: true,
    );
    final blockMatch = toolsBlockRegex.firstMatch(text);
    if (blockMatch != null) {
      final leading = text.substring(0, blockMatch.start).trim();
      final trailing = text.substring(blockMatch.end).trim();
      contentText = [
        leading,
        trailing,
      ].where((part) => part.isNotEmpty).join('\n');

      // Match llama.cpp DeepSeek-V3 parser:
      // (optional begin)name<sep>{...}<end>
      final v3CallRegex = RegExp(
        r'(?:<｜tool▁call▁begin｜>)?([^\n<]+)<｜tool▁sep｜>([\s\S]*?)<｜tool▁call▁end｜>',
        dotAll: true,
      );
      final callMatches = v3CallRegex.allMatches(blockMatch.group(2)!);
      for (var i = 0; i < callMatches.length; i++) {
        final toolName = (callMatches.elementAt(i).group(1) ?? '').trim();
        final rawArguments = (callMatches.elementAt(i).group(2) ?? '').trim();
        if (toolName.isEmpty) {
          continue;
        }

        final arguments = _decodeJson(rawArguments);
        if (arguments == null) {
          continue;
        }
        toolCalls.add(
          ToolCallParsingUtils.createFunctionToolCall(
            index: i,
            name: toolName,
            arguments: arguments,
          ),
        );
      }

      // Match llama.cpp behavior: malformed tool block falls back to content.
      if (toolCalls.isEmpty) {
        return ChatParseResult(
          content: text.trim(),
          reasoningContent: reasoning,
        );
      }
    }

    return ChatParseResult(
      content: contentText.trim(),
      reasoningContent: reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    if (tools == null || tools.isEmpty) {
      return null;
    }

    final converter = JsonSchemaConverter();
    final toolRuleNames = <String>[];

    for (var i = 0; i < tools.length; i++) {
      final tool = tools[i];
      final schema = tool.toJsonSchema();
      converter.resolveRefs(schema, schema);
      final argsRule = converter.visit(schema, 'tool-$i-args');

      final toolRuleName = 'tool-$i-call';
      final prefix = ToolCallGrammarUtils.literal('${tool.name}<｜tool▁sep｜>');
      final suffix = ToolCallGrammarUtils.literal('<｜tool▁call▁end｜>');
      converter.rules[toolRuleName] =
          '( "<｜tool▁call▁begin｜>" )? $prefix $argsRule $suffix';
      toolRuleNames.add(toolRuleName);
    }

    const rootRule = '( "</think>" space )? tool-calls';
    const toolCallsRule =
        '( "<｜tool▁calls▁begin｜>" | "<｜tool_calls_begin｜>" | "<｜tool calls begin｜>" | "<｜tool\\\\_calls\\\\_begin｜>" | "<｜tool▁calls｜>" ) space tool-call+ "<｜tool▁calls▁end｜>" space';
    final toolCallRule = toolRuleNames.join(' | ');

    final buffer = StringBuffer()
      ..writeln('root ::= $rootRule')
      ..writeln('tool-calls ::= $toolCallsRule')
      ..writeln('tool-call ::= $toolCallRule');

    final otherRules = converter.rules.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in otherRules) {
      if (entry.key == 'root' ||
          entry.key == 'tool-calls' ||
          entry.key == 'tool-call') {
        continue;
      }
      buffer.writeln('${entry.key} ::= ${entry.value}');
    }

    return buffer.toString();
  }

  Object? _decodeJson(String input) {
    return ToolCallParsingUtils.decodeJsonValue(input);
  }
}
