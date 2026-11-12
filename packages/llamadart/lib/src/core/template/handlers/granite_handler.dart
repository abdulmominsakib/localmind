import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/inference/tool_choice.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../template_internal_metadata.dart';
import '../thinking_utils.dart';
import '../tool_call_parsing_utils.dart';
import '../tool_call_grammar_utils.dart';

/// Handler for IBM Granite models.
class GraniteHandler extends ChatTemplateHandler {
  static const String _toolCallPrefix = '<|tool_call|>';

  /// Finds where [parse] may find a tool-call opening in [text].
  ///
  /// Returns the first index at or after [from] where `<|tool_call|>`
  /// starts, or where the rest of [text] is the start of it, and
  /// `text.length` when there is none.
  static int toolCallOpening(String text, [int from = 0]) =>
      ToolCallParsingUtils.literalOpening(text, const [_toolCallPrefix], from);

  static const List<String> _toolPreservedTokens = <String>[
    '<think>',
    '</think>',
    '<response>',
    '</response>',
    '<|tool_call|>',
  ];

  static const List<String> _thinkingPreservedTokens = <String>[
    '<think>',
    '</think>',
    '<response>',
    '</response>',
  ];

  @override
  ChatFormat get format => ChatFormat.granite;

  @override
  TemplateToolCallSerialization get toolCallSerialization =>
      TemplateToolCallSerialization.genericSchemaInContent;

  @override
  List<String> get additionalStops => ['<|end_of_text|>', '<|end_of_role|>'];

  @override
  List<String> getStops({bool hasTools = false, bool enableThinking = true}) =>
      additionalStops;

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
        'bos_token':
            metadata['tokenizer.ggml.bos_token'] ?? '<|start_of_text|>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '<|end_of_text|>',
      },
    );

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
    final toolChoice = metadata[internalToolChoiceMetadataKey];
    final toolChoiceRequired = toolChoice == ToolChoice.required.name;
    final parallelToolCalls =
        metadata[internalParallelToolCallsMetadataKey] == 'true';
    final rendered = LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: hasTools
          ? _buildGraniteToolGrammar(
              tools,
              thinkingForcedOpen: thinkingForcedOpen,
              parallelToolCalls: parallelToolCalls,
            )
          : (thinkingForcedOpen ? _buildThinkingOnlyGrammar() : null),
      grammarLazy: hasTools && !toolChoiceRequired,
      thinkingForcedOpen: thinkingForcedOpen,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      preservedTokens: hasTools
          ? _toolPreservedTokens
          : (thinkingForcedOpen ? _thinkingPreservedTokens : const []),
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: '<|tool_call|>')]
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

    final toolCallIndex = text.indexOf(_toolCallPrefix);
    if (toolCallIndex == -1) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    final prelude = text.substring(0, toolCallIndex);
    final payload = text.substring(toolCallIndex + _toolCallPrefix.length);
    var payloadOffset = 0;
    while (payloadOffset < payload.length &&
        payload.codeUnitAt(payloadOffset) <= 0x20) {
      payloadOffset++;
    }
    final jsonSlice = ToolCallParsingUtils.extractLeadingJsonValue(
      payload,
      payloadOffset,
    );
    if (jsonSlice == null || jsonSlice.value is! List) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    final trailing = payload.substring(jsonSlice.end);
    if (trailing.isNotEmpty) {
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

    return ChatParseResult(
      content: prelude.trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return _buildGraniteToolGrammar(
      tools,
      thinkingForcedOpen: false,
      parallelToolCalls: true,
    );
  }

  String? _buildGraniteToolGrammar(
    List<ToolDefinition>? tools, {
    required bool thinkingForcedOpen,
    required bool parallelToolCalls,
  }) {
    final base = ToolCallGrammarUtils.buildWrappedArrayGrammar(
      tools: tools,
      prefix: '<|tool_call|>',
      suffix: '',
      nameKey: 'name',
      argumentsKey: 'arguments',
      allowParallelToolCalls: parallelToolCalls,
    );
    if (base == null) {
      return null;
    }
    if (!thinkingForcedOpen) {
      return base;
    }
    return _rewriteRootForThinkingPrelude(base);
  }

  String _rewriteRootForThinkingPrelude(String grammar) {
    final lines = grammar.trimRight().split('\n');
    final rootIndex = lines.indexWhere((line) => line.startsWith('root ::= '));
    if (rootIndex == -1) {
      return grammar;
    }
    final rootExpr = lines[rootIndex].substring('root ::= '.length).trim();
    lines[rootIndex] =
        'root ::= "</think>" space "<response>" space response-body "</response>" space $rootExpr';
    final hasResponseRule = lines.any(
      (line) => line.startsWith('response-body ::= '),
    );
    if (!hasResponseRule) {
      lines.add('response-body ::= [^<]*');
    }
    return '${lines.join('\n')}\n';
  }

  String _buildThinkingOnlyGrammar() {
    return '''
root ::= "</think>" space "<response>" space response-body "</response>" space
response-body ::= [^<]*
space ::= "" | " " | "\\n"{1,2} [ \\t]{0,20}
''';
  }
}
