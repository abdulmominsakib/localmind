import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';
import '../tool_call_grammar_utils.dart';
import '../tool_call_parsing_utils.dart';

/// Handler for Tencent Hunyuan V3's namespaced chat and tool-call format.
class HunyuanV3Handler extends ChatTemplateHandler {
  static const String _namespace = ':opensource';
  static const String _eos = '<｜hy_eos$_namespace｜>';
  static const String _user = '<｜hy_User$_namespace｜>';
  static const String _toolCallsStart = '<tool_calls$_namespace>';
  static const String _toolCallsEnd = '</tool_calls$_namespace>';
  static const String _toolCallStart = '<tool_call$_namespace>';
  static const String _toolCallEnd = '</tool_call$_namespace>';
  static const String _toolSeparator = '<tool_sep$_namespace>';
  static const String _argKeyStart = '<arg_key$_namespace>';
  static const String _argKeyEnd = '</arg_key$_namespace>';
  static const String _argValueStart = '<arg_value$_namespace>';
  static const String _argValueEnd = '</arg_value$_namespace>';

  static final RegExp _pythonFormatCall = RegExp(
    r"'([^'\r\n]*)\{\}([^'\r\n]*)'\.format\(([A-Za-z_][A-Za-z0-9_]*)\)",
  );
  static final RegExp _toolCallBlockPattern = RegExp(
    '${RegExp.escape(_toolCallStart)}([\\s\\S]*?)${RegExp.escape(_toolCallEnd)}',
  );
  static final RegExp _argPairPattern = RegExp(
    '${RegExp.escape(_argKeyStart)}([\\s\\S]*?)${RegExp.escape(_argKeyEnd)}'
    r'\s*'
    '${RegExp.escape(_argValueStart)}([\\s\\S]*?)${RegExp.escape(_argValueEnd)}',
  );

  @override
  ChatFormat get format => ChatFormat.hunyuanV3;

  @override
  String get thinkingStartTag => '<think$_namespace>';

  @override
  String get thinkingEndTag => '</think$_namespace>';

  @override
  TemplateToolCallSerialization get toolCallSerialization =>
      TemplateToolCallSerialization.normalizeOnly;

  @override
  List<String> get additionalStops => const [_eos, _user];

  @override
  List<String> get preservedTokens => const [
    _eos,
    _user,
    '<｜hy_Assistant$_namespace｜>',
    '<think$_namespace>',
    '</think$_namespace>',
    _toolCallsStart,
    _toolCallsEnd,
    _toolCallStart,
    _toolCallEnd,
    _toolSeparator,
    _argKeyStart,
    _argKeyEnd,
    _argValueStart,
    _argValueEnd,
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
    final template = Template(_normalizeTemplate(templateSource));
    var prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': templateMessages(messages),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((tool) => tool.toJson()).toList(),
        'reasoning_effort': enableThinking ? 'high' : 'no_think',
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? _eos,
      },
    );

    var thinkingForcedOpen = isThinkingForcedOpen(
      prompt,
      startTag: thinkingStartTag,
    );
    if (thinkingForcedOpen && !enableThinking) {
      prompt = '${prompt.trimRight()}$thinkingEndTag';
      thinkingForcedOpen = false;
    }

    final hasTools = tools != null && tools.isNotEmpty;
    return LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: buildGrammar(tools),
      grammarLazy: hasTools,
      additionalStops: additionalStops,
      preservedTokens: hasTools ? preservedTokens : const [],
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: _toolCallsStart)]
          : const [],
      thinkingForcedOpen: thinkingForcedOpen,
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
      startTag: thinkingStartTag,
      endTag: thinkingEndTag,
      thinkingForcedOpen: thinkingForcedOpen,
    );
    if (!parseToolCalls) {
      return ChatParseResult(
        content: thinking.content,
        reasoningContent: thinking.reasoning,
      );
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    var remaining = thinking.content;
    for (final match in _toolCallBlockPattern.allMatches(thinking.content)) {
      final block = match.group(1) ?? '';
      final separatorIndex = block.indexOf(_toolSeparator);
      if (separatorIndex < 0) {
        continue;
      }

      final name = block.substring(0, separatorIndex).trim();
      if (name.isEmpty) {
        continue;
      }

      final arguments = <String, dynamic>{};
      final argumentsBlock = block.substring(
        separatorIndex + _toolSeparator.length,
      );
      for (final argumentMatch in _argPairPattern.allMatches(argumentsBlock)) {
        final key = (argumentMatch.group(1) ?? '').trim();
        if (key.isEmpty) {
          continue;
        }
        final value = (argumentMatch.group(2) ?? '').trim();
        arguments[key] = ToolCallParsingUtils.decodeJsonValueOrString(value);
      }

      toolCalls.add(
        ToolCallParsingUtils.createFunctionToolCall(
          index: toolCalls.length,
          name: name,
          arguments: arguments,
        ),
      );
      remaining = remaining.replaceFirst(match.group(0)!, '');
    }

    remaining = remaining
        .replaceAll(_toolCallsStart, '')
        .replaceAll(_toolCallsEnd, '')
        .replaceAll(_eos, '')
        .trim();
    return ChatParseResult(
      content: remaining,
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    if (tools == null || tools.isEmpty) {
      return null;
    }

    final choices = <String>[];
    final rules = <String>[];
    for (final tool in tools) {
      final toolName = _ruleName(tool.name);
      final toolRule = '$toolName-call';
      choices.add(toolRule);

      final argumentRules = <String>[];
      for (final parameter in tool.parameters) {
        final parameterName = _ruleName(parameter.name);
        final argumentRule = '$toolName-$parameterName-arg';
        final valueRule = '$argumentRule-value';
        rules.add(_valueRule(valueRule, parameter.toJsonSchema()));
        rules.add(
          '$argumentRule ::= ${_literal('$_argKeyStart${parameter.name}$_argKeyEnd\n$_argValueStart')} '
          '$valueRule ${_literal('$_argValueEnd\n')}',
        );
        argumentRules.add(
          parameter.required ? argumentRule : '($argumentRule)?',
        );
      }

      rules.add(
        '$toolRule ::= ${_literal('$_toolCallStart${tool.name}$_toolSeparator\n')} '
        '${argumentRules.join(' ')} ${_literal('$_toolCallEnd\n')}',
      );
    }

    return [
      'root ::= ${_literal('$_toolCallsStart\n')} tool-call+ ${_literal(_toolCallsEnd)}',
      'tool-call ::= ${choices.join(' | ')}',
      ...rules,
      r'raw-alpha ::= [A-Za-z]',
      r'raw-tail ::= [A-Za-z0-9_ ./:-]',
      r'raw-string ::= raw-alpha raw-tail*',
      r'space ::= " "?',
      r'string ::= "\"" ([^"\\] | "\\" .)* "\""',
      r'number ::= "-"? ([0-9] | [1-9] [0-9]*) ("." [0-9]+)? ([eE] [+-]? [0-9]+)?',
      r'boolean ::= "true" | "false"',
      r'null ::= "null"',
      r'value ::= string | number | boolean | null | arr | obj',
      r'arr ::= "[" space (value ("," space value)*)? "]"',
      r'obj ::= "{" space (string ":" space value ("," space string ":" space value)*)? "}"',
    ].join('\n');
  }

  static String _normalizeTemplate(String templateSource) {
    return templateSource.replaceAllMapped(_pythonFormatCall, (match) {
      final prefix = match.group(1) ?? '';
      final suffix = match.group(2) ?? '';
      final argument = match.group(3) ?? '';
      return "'$prefix' + $argument + '$suffix'";
    });
  }

  static String _valueRule(String name, Map<String, dynamic> schema) {
    final type = schema['type'];
    final enumValues = schema['enum'];
    if (type == 'string') {
      if (enumValues is List && enumValues.isNotEmpty) {
        final rawValues = enumValues
            .whereType<String>()
            .map(_literal)
            .join(' | ');
        return '$name ::= $rawValues | string';
      }
      return '$name ::= raw-string | string';
    }
    if (type == 'integer' || type == 'number') {
      return '$name ::= number';
    }
    if (type == 'boolean') {
      return '$name ::= boolean';
    }
    if (type == 'array') {
      return '$name ::= arr';
    }
    if (type == 'object') {
      return '$name ::= obj';
    }
    return '$name ::= value';
  }

  static String _literal(String value) => ToolCallGrammarUtils.literal(value);

  static String _ruleName(String value) {
    return value.replaceAll(RegExp('[^A-Za-z0-9]'), '-').toLowerCase();
  }
}
