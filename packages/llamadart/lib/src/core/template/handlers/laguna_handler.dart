import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';
import 'glm45_handler.dart';
import 'specialized_handler_utils.dart';

/// Poolside Laguna uses GLM-style argument tags with a distinct turn stop.
class LagunaHandler extends DirectJinjaHandler
    implements ToolSchemaAwareChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.laguna;

  @override
  List<String> get additionalStops => const ['</assistant>'];

  @override
  List<String> get preservedTokens => const [
    '<think>',
    '</think>',
    '<tool_call>',
    '</tool_call>',
    '<arg_key>',
    '</arg_key>',
    '<arg_value>',
    '</arg_value>',
    '</assistant>',
  ];

  @override
  List<String> get grammarTriggerValues => const ['<tool_call>'];

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    return parseWithTools(
      output,
      isPartial: isPartial,
      parseToolCalls: parseToolCalls,
      thinkingForcedOpen: thinkingForcedOpen,
    );
  }

  /// Parses Laguna output using [tools] for schema-directed argument types.
  @override
  ChatParseResult parseWithTools(
    String output, {
    List<ToolDefinition>? tools,
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    if (parseToolCalls && _hasMalformedLagunaToolBlock(output)) {
      final thinking = extractThinking(
        output,
        thinkingForcedOpen: thinkingForcedOpen,
      );
      return ChatParseResult(
        content: thinking.content,
        reasoningContent: thinking.reasoning,
      );
    }
    return Glm45Handler().parseWithTools(
      output,
      tools: tools,
      isPartial: isPartial,
      parseToolCalls: parseToolCalls,
      thinkingForcedOpen: thinkingForcedOpen,
    );
  }

  bool _hasMalformedLagunaToolBlock(String output) {
    final blockPattern = RegExp(r'<tool_call>\s*([\s\S]*?)</tool_call>');
    final pairPattern = RegExp(
      r'<arg_key>\s*[\s\S]*?\s*</arg_key>\s*<arg_value>\s*[\s\S]*?\s*</arg_value>',
    );
    for (final block in blockPattern.allMatches(output)) {
      final body = block.group(1) ?? '';
      final firstArgument = body.indexOf('<arg_key>');
      if (firstArgument < 0) {
        continue;
      }
      final argumentBody = body.substring(firstArgument);
      if (argumentBody.replaceAll(pairPattern, '').trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return Glm45Handler().buildGrammar(tools);
  }

  @override
  String? buildRequiredGrammar(List<ToolDefinition>? tools) {
    final grammar = buildGrammar(tools);
    return grammar == null
        ? null
        : withRequiredPrefix(
            grammar,
            delimiter: '\n<tool_call>',
            prefixName: 'laguna-required-prefix',
          );
  }
}
