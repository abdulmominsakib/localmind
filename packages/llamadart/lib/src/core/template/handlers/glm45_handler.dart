import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';
import '../tool_call_parsing_utils.dart';

/// Handler for GLM 4.5 format.
///
/// Uses `<|observation|>` as a stop token for tool call observation.
/// Tool call format:
/// `<tool_call>func_name<arg_key>key</arg_key><arg_value>value</arg_value></tool_call>`
///
/// Supports `<think>`/`</think>` for reasoning.
class Glm45Handler extends ChatTemplateHandler {
  static final RegExp _toolCallBlockPattern = RegExp(
    r'<tool_call>\s*([\s\S]*?)</tool_call>',
  );
  static final RegExp _argPairPattern = RegExp(
    r'<arg_key>\s*([\s\S]*?)\s*</arg_key>\s*<arg_value>\s*([\s\S]*?)\s*</arg_value>',
  );

  @override
  ChatFormat get format => ChatFormat.glm45;

  @override
  TemplateToolCallSerialization get toolCallSerialization =>
      TemplateToolCallSerialization.normalizeOnly;

  @override
  List<String> get additionalStops => ['<|user|>', '<|observation|>'];

  @override
  List<String> get preservedTokens => const [
    '<|endoftext|>',
    '[MASK]',
    '[gMASK]',
    '[sMASK]',
    '<sop>',
    '<eop>',
    '<|system|>',
    '<|user|>',
    '<|assistant|>',
    '<|observation|>',
    '<|begin_of_image|>',
    '<|end_of_image|>',
    '<|begin_of_video|>',
    '<|end_of_video|>',
    '<|begin_of_audio|>',
    '<|end_of_audio|>',
    '<|begin_of_transcription|>',
    '<|end_of_transcription|>',
    '<|code_prefix|>',
    '<|code_middle|>',
    '<|code_suffix|>',
    '/nothink',
    '<think>',
    '</think>',
    '<tool_call>',
    '</tool_call>',
    '<arg_key>',
    '</arg_key>',
    '<arg_value>',
    '</arg_value>',
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
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '[gMASK]<sop>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '<|user|>',
        'clear_thinking': false,
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
    // GLM 4.5 tool calls are wrapped in <tool_call> XML blocks.
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
          ? [const GrammarTrigger(type: 0, value: '<tool_call>')]
          : const [],
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
    );
    final text = thinking.content;

    if (!parseToolCalls) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    final extractedFromContent = _extractToolCalls(text);
    final toolCalls = <LlamaCompletionChunkToolCall>[
      ...extractedFromContent.toolCalls,
    ];
    var contentText = extractedFromContent.remainingContent;

    return ChatParseResult(
      content: contentText.trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    if (tools == null || tools.isEmpty) {
      return null;
    }

    final toolChoiceRules = <String>[];
    final toolRules = <String>[];

    for (final tool in tools) {
      final toolRuleName = '${_sanitizeRuleName(tool.name)}-call';
      toolChoiceRules.add(toolRuleName);

      final argParts = <String>[];
      for (final parameter in tool.parameters) {
        final paramSchema = parameter.toJsonSchema();
        final paramRuleName =
            '${_sanitizeRuleName(tool.name)}-arg-${_sanitizeRuleName(parameter.name)}';
        final valueRuleName =
            '${_sanitizeRuleName(tool.name)}-arg-${_sanitizeRuleName(parameter.name)}-value';

        final valueRule = _buildValueRule(
          valueRuleName: valueRuleName,
          schema: paramSchema,
        );

        toolRules.add(valueRule);
        toolRules.add(
          '$paramRuleName ::= "<arg_key>${_escapeLiteral(parameter.name)}</arg_key>\\n<arg_value>" $valueRuleName "</arg_value>\\n"',
        );
        argParts.add(parameter.required ? paramRuleName : '($paramRuleName)?');
      }

      final argsRule = argParts.join(' ');
      toolRules.add(
        '$toolRuleName ::= "${_escapeLiteral(tool.name)}\\n" $argsRule',
      );
    }

    final toolChoiceRule = 'tool-choice ::= ${toolChoiceRules.join(' | ')}';

    return [
      'root ::= tool-call+',
      'tool-call ::= "\\n<tool_call>" tool-choice "</tool_call>\\n"',
      toolChoiceRule,
      ...toolRules,
      'raw-alpha ::= [A-Za-z]',
      'raw-tail ::= [A-Za-z0-9_ ./:-]',
      'raw-string ::= raw-alpha raw-tail*',
      'space ::= " "?',
      'string ::= "\\"" ([^"\\\\] | "\\\\" .)* "\\""',
      'number ::= "-"? ([0-9] | [1-9] [0-9]*) ("." [0-9]+)? ([eE] [+-]? [0-9]+)?',
      'boolean ::= "true" | "false"',
      'null ::= "null"',
      'value ::= string | number | boolean | null | arr | obj',
      'arr ::= "[" space (value ("," space value)*)? "]"',
      'obj ::= "{" space (string ":" space value ("," space string ":" space value)*)? "}"',
    ].join('\n');
  }

  String _buildValueRule({
    required String valueRuleName,
    required Map<String, dynamic> schema,
  }) {
    final type = schema['type'];
    final enumValues = schema['enum'];

    if (type == 'string') {
      if (enumValues is List && enumValues.isNotEmpty) {
        final rawEnum = enumValues
            .whereType<String>()
            .map((value) => '"${_escapeLiteral(value)}"')
            .join(' | ');
        final jsonEnum = enumValues
            .whereType<String>()
            .map((value) => '"\\"${_escapeLiteral(value)}\\""')
            .join(' | ');
        return '$valueRuleName ::= $rawEnum | $jsonEnum';
      }
      return '$valueRuleName ::= raw-string | string';
    }

    if (type == 'integer' || type == 'number') {
      return '$valueRuleName ::= number';
    }

    if (type == 'boolean') {
      return '$valueRuleName ::= boolean';
    }

    if (type == 'array') {
      return '$valueRuleName ::= arr';
    }

    if (type == 'object') {
      return '$valueRuleName ::= obj';
    }

    return '$valueRuleName ::= value';
  }

  String _sanitizeRuleName(String input) {
    return input.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-').toLowerCase();
  }

  String _escapeLiteral(String input) {
    return input.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }

  Object? _decodeArgValue(String value) {
    if (value.isEmpty) {
      return '';
    }

    return ToolCallParsingUtils.decodeJsonValueOrString(value);
  }

  _ExtractedToolCalls _extractToolCalls(String input) {
    final toolCalls = <LlamaCompletionChunkToolCall>[];
    var remaining = input;

    final matches = _toolCallBlockPattern.allMatches(input);
    for (final match in matches) {
      final block = match.group(1) ?? '';
      final firstArgIdx = block.indexOf('<arg_key>');
      final toolName = firstArgIdx == -1
          ? block.trim()
          : block.substring(0, firstArgIdx).trim();
      final args = <String, dynamic>{};
      for (final argMatch in _argPairPattern.allMatches(block)) {
        final key = (argMatch.group(1) ?? '').trim();
        final rawValue = (argMatch.group(2) ?? '').trim();
        if (key.isEmpty) {
          continue;
        }
        args[key] = _decodeArgValue(rawValue);
      }

      if (toolName.isEmpty) {
        continue;
      }

      final index = toolCalls.length;
      toolCalls.add(
        ToolCallParsingUtils.createFunctionToolCall(
          index: index,
          name: toolName,
          arguments: args,
        ),
      );

      final fullBlock = match.group(0);
      if (fullBlock != null && fullBlock.isNotEmpty) {
        remaining = remaining.replaceFirst(fullBlock, '');
      }
    }

    return _ExtractedToolCalls(
      toolCalls: toolCalls,
      remainingContent: remaining,
    );
  }
}

class _ExtractedToolCalls {
  final List<LlamaCompletionChunkToolCall> toolCalls;
  final String remainingContent;

  const _ExtractedToolCalls({
    required this.toolCalls,
    required this.remainingContent,
  });
}
