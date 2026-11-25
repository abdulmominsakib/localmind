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
import '../tool_schema_utils.dart';

/// Handler for Tencent Hunyuan V3's namespaced chat and tool-call format.
class HunyuanV3Handler extends ChatTemplateHandler
    implements ToolSchemaAwareChatTemplateHandler {
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

  /// Finds where [parse] may find a tool-call opening in [text].
  ///
  /// Returns the first index at or after [from] where a tool call, a
  /// tool-call envelope or the end-of-sequence token it removes starts, or
  /// where the rest of [text] is the start of one, and `text.length` when
  /// there is none.
  static int toolCallOpening(String text, [int from = 0]) =>
      ToolCallParsingUtils.literalOpening(text, const [
        _toolCallStart,
        _toolCallsStart,
        _eos,
      ], from);

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
        'messages': templateMessages(messages, templateSource: templateSource),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((tool) => tool.toJson()).toList(),
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? _eos,
      },
      defaults: {'reasoning_effort': enableThinking ? 'high' : 'no_think'},
    );

    var thoughtClosed = false;
    var thinkingForcedOpen = isThinkingForcedOpen(
      prompt,
      startTag: thinkingStartTag,
    );
    if (thinkingForcedOpen && !enableThinking) {
      prompt = '${prompt.trimRight()}$thinkingEndTag';
      thoughtClosed = true;
      thinkingForcedOpen = false;
    }

    final hasTools = tools != null && tools.isNotEmpty;
    final rendered = LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: requiredGrammarAfterThought(
        buildGrammar(tools),
        metadata: metadata,
        thinkingForcedOpen: thinkingForcedOpen,
      ),
      grammarLazy: hasTools,
      additionalStops: additionalStops,
      preservedTokens: hasTools ? preservedTokens : const [],
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: _toolCallsStart)]
          : const [],
      thinkingForcedOpen: thinkingForcedOpen,
    );
    return withThoughtClosedForThinkingOff(rendered, closed: thoughtClosed);
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) => parseWithTools(
    output,
    isPartial: isPartial,
    parseToolCalls: parseToolCalls,
    thinkingForcedOpen: thinkingForcedOpen,
  );

  /// Parses canonical-schema arguments without guessing string types.
  @override
  ChatParseResult parseWithTools(
    String output, {
    List<ToolDefinition>? tools,
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    final schemas = toolSchemas(tools);
    final canonicalNames = {
      for (final tool in tools ?? const <ToolDefinition>[])
        if (toolUsesJsonSchema(tool)) tool.name,
    };
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

    ChatParseResult rollback() => ChatParseResult(
      content: thinking.content.trim(),
      reasoningContent: thinking.reasoning,
    );

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    var remaining = thinking.content;
    for (final match in _toolCallBlockPattern.allMatches(thinking.content)) {
      final block = match.group(1) ?? '';
      final separatorIndex = block.indexOf(_toolSeparator);
      if (separatorIndex < 0) {
        return rollback();
      }

      final name = block.substring(0, separatorIndex).trim();
      if (name.isEmpty) {
        return rollback();
      }

      final arguments = <String, dynamic>{};
      final argumentsBlock = block.substring(
        separatorIndex + _toolSeparator.length,
      );
      var argumentCursor = 0;
      for (final argumentMatch in _argPairPattern.allMatches(argumentsBlock)) {
        if (argumentsBlock
            .substring(argumentCursor, argumentMatch.start)
            .trim()
            .isNotEmpty) {
          return rollback();
        }
        final key = (argumentMatch.group(1) ?? '').trim();
        if (key.isEmpty || arguments.containsKey(key)) {
          return rollback();
        }
        final value = (argumentMatch.group(2) ?? '').trim();
        if (canonicalNames.contains(name)) {
          final property = schemaProperties(schemas[name]!)[key];
          if (property == null) return rollback();
          final decoded = schemaResolvesToString(property)
              ? validateToolSchemaValue(
                  value.startsWith('"')
                      ? ToolCallParsingUtils.decodeJsonValueOrString(value)
                      : value,
                  property,
                )
              : decodeToolSchemaText(value, property);
          if (!decoded.valid) return rollback();
          arguments[key] = decoded.value;
        } else {
          arguments[key] = ToolCallParsingUtils.decodeJsonValueOrString(value);
        }
        argumentCursor = argumentMatch.end;
      }
      if (argumentsBlock.substring(argumentCursor).trim().isNotEmpty) {
        return rollback();
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

    final withoutEnvelope = _removeBalancedToolCallsEnvelope(remaining);
    if (withoutEnvelope == null ||
        (toolCalls.isEmpty && withoutEnvelope != remaining)) {
      return rollback();
    }
    if (_containsToolProtocolFragment(withoutEnvelope)) {
      return rollback();
    }
    remaining = withoutEnvelope.replaceAll(_eos, '').trim();
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
    toolSchemas(tools);
    validateFixedArgumentToolSchemas(tools, format: 'Hunyuan-V3');

    final choices = <String>[];
    final rules = <String>[];
    for (final tool in tools) {
      final toolName = ToolCallGrammarUtils.ruleName(tool.name);
      final toolRule = '$toolName-call';
      choices.add(toolRule);

      final argumentRules = <String>[];
      final schema = tool.toJsonSchema();
      final required = schemaRequired(schema);
      for (final parameter in schemaProperties(schema).entries) {
        final parameterName = ToolCallGrammarUtils.ruleName(parameter.key);
        final argumentRule = '$toolName-$parameterName-arg';
        final valueRule = '$argumentRule-value';
        rules.add(_valueRule(valueRule, parameter.value));
        rules.add(
          '$argumentRule ::= ${_literal('$_argKeyStart${parameter.key}$_argKeyEnd\n$_argValueStart')} '
          '$valueRule ${_literal('$_argValueEnd\n')}',
        );
        argumentRules.add(
          required.contains(parameter.key) ? argumentRule : '($argumentRule)?',
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
      r'integer ::= "-"? ("0" | [1-9] [0-9]*)',
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
    if (type == 'integer') {
      return '$name ::= integer';
    }
    if (type == 'number') {
      return '$name ::= number';
    }
    if (type == 'null') return '$name ::= "null"';
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

  static bool _containsToolProtocolFragment(String input) {
    return const [
      '<tool_calls',
      '</tool_calls',
      '<tool_call',
      '</tool_call',
      '<tool_sep',
      '<arg_key',
      '</arg_key',
      '<arg_value',
      '</arg_value',
    ].any(input.contains);
  }

  static String? _removeBalancedToolCallsEnvelope(String input) {
    final start = input.indexOf(_toolCallsStart);
    final end = input.indexOf(_toolCallsEnd);
    if (start < 0 && end < 0) {
      return input;
    }
    if (start < 0 ||
        end < start ||
        input.indexOf(_toolCallsStart, start + _toolCallsStart.length) >= 0 ||
        input.indexOf(_toolCallsEnd, end + _toolCallsEnd.length) >= 0 ||
        input
            .substring(start + _toolCallsStart.length, end)
            .trim()
            .isNotEmpty) {
      return null;
    }
    return '${input.substring(0, start)}'
        '${input.substring(end + _toolCallsEnd.length)}';
  }
}
