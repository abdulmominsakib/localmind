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
  static const List<String> _toolCallsOpenings = <String>[
    '<｜tool▁calls▁begin｜>',
    '<｜tool_calls_begin｜>',
    '<｜tool calls begin｜>',
    r'<｜tool\_calls\_begin｜>',
    '<｜tool▁calls｜>',
  ];
  static final RegExp _toolsBlockRegex = RegExp(
    '(${_toolCallsOpenings.map(RegExp.escape).join('|')})'
    '([\\s\\S]*?)<｜tool▁calls▁end｜>',
    dotAll: true,
  );

  /// Finds where [parse] may find a tool-call opening in [text].
  ///
  /// Returns the first index at or after [from] where a DeepSeek tool-call
  /// opening starts, or where the rest of [text] is the start of one, and
  /// `text.length` when there is none.
  static int toolCallOpening(String text, [int from = 0]) =>
      ToolCallParsingUtils.literalOpening(text, _toolCallsOpenings, from);

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
        'messages': templateMessages(
          modifiedMessages,
          templateSource: templateSource,
        ),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'enable_thinking': enableThinking,
        'bos_token': bosToken,
        'eos_token': eosToken,
      },
    );

    // Handle enableThinking post-render logic
    final thinkingForcedClosed = isThinkingForcedClosed(prompt);
    var thinkingForcedOpen = false;
    var thoughtClosed = false;
    if (isThinkingForcedOpen(prompt)) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}</think>\n';
        thoughtClosed = true;
      } else {
        thinkingForcedOpen = true;
      }
    }

    final hasTools = tools != null && tools.isNotEmpty;
    final triggerPattern = thinkingForcedOpen
        ? r'[\s\S]*?(</think>\s*)(<｜tool▁calls▁begin｜>|<｜tool_calls_begin｜>|<｜tool calls begin｜>|<｜tool\\_calls\\_begin｜>|<｜tool▁calls｜>)[\s\S]*'
        : r'(?:<think>[\s\S]*?</think>\s*)?(<｜tool▁calls▁begin｜>|<｜tool_calls_begin｜>|<｜tool calls begin｜>|<｜tool\\_calls\\_begin｜>|<｜tool▁calls｜>)[\s\S]*';
    final rendered = LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: requiredGrammarAfterThought(
        buildGrammar(tools),
        metadata: metadata,
        thinkingForcedOpen: thinkingForcedOpen,
      ),
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
    return withThoughtClosedForThinkingOff(
      withThinkingForcedClosed(rendered, closed: thinkingForcedClosed),
      closed: thoughtClosed,
    );
  }

  /// With [thoughtTagsAreText], all of [output] is content and tool calls.
  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
    bool thoughtTagsAreText = false,
  }) {
    // As in llama.cpp (`620d2225`), a forced-open thought is the text before
    // the first `</think>`, kept as generated, and the rest is content; a
    // thought that never closes is reasoning.
    final ThinkingExtraction thinking = thoughtTagsAreText
        ? (content: output.trim(), reasoning: null)
        : thinkingForcedOpen
        ? extractForcedOpenThoughtVerbatim(output, isPartial: isPartial)
        : extractThinking(output);
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
    final blockMatch = _toolsBlockRegex.firstMatch(text);
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
