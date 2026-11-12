import '../../grammar/json_schema_converter.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';
import '../tool_call_grammar_utils.dart';
import '../tool_call_parsing_utils.dart';
import '../tool_schema_utils.dart';
import 'specialized_handler_utils.dart';

abstract class _DeepseekDsmlHandler extends DirectJinjaHandler
    implements ToolSchemaAwareChatTemplateHandler {
  static const _prefix = '<｜DSML｜';

  String get _callsEnvelope;

  String get _callsStart => '$_prefix$_callsEnvelope>';

  String get _callsEnd => '</｜DSML｜$_callsEnvelope>';

  @override
  List<String> get additionalStops => const ['<｜end▁of▁sentence｜>'];

  @override
  List<String> get preservedTokens => [
    '<think>',
    '</think>',
    _callsStart,
    _callsEnd,
  ];

  @override
  List<String> get grammarTriggerValues => [_callsStart];

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

  /// Parses DSML output using [tools] to enforce exact emitted schemas.
  @override
  ChatParseResult parseWithTools(
    String output, {
    List<ToolDefinition>? tools,
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    final thinking = _extractDsmlThinking(
      output,
      callsStart: _callsStart,
      isPartial: isPartial,
      thinkingForcedOpen: thinkingForcedOpen,
    );
    if (!parseToolCalls) {
      return ChatParseResult(
        content: thinking.content,
        reasoningContent: thinking.reasoning,
      );
    }
    final schemas = toolSchemas(tools);
    final parsed = parseInvokeScope(
      thinking.content,
      scopeStart: _callsStart,
      scopeEnd: _callsEnd,
      invokeStartPattern: RegExp(r'<｜DSML｜invoke name="([^"]+)">'),
      invokeEnd: '</｜DSML｜invoke>',
      parseArguments: (name, body) {
        final schema = schemas[name];
        if (schemas.isNotEmpty && schema == null) {
          return null;
        }
        return _parseDsmlArguments(body, schema: schema);
      },
      isPartial: isPartial,
    );
    return ChatParseResult(
      content: parsed.success ? parsed.remaining.trim() : thinking.content,
      reasoningContent: thinking.reasoning,
      toolCalls: parsed.success ? parsed.calls : const [],
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return _DsmlGrammarBuilder(tools, envelope: _callsEnvelope).build();
  }

  @override
  String? buildRequiredGrammar(List<ToolDefinition>? tools) {
    return _DsmlGrammarBuilder(
      tools,
      envelope: _callsEnvelope,
    ).build(required: true);
  }
}

/// Handler for DeepSeek V3.2 DSML function calls.
class DeepseekV32Handler extends _DeepseekDsmlHandler {
  @override
  ChatFormat get format => ChatFormat.deepseekV32;

  @override
  String get _callsEnvelope => 'function_calls';
}

/// Handler for DeepSeek V4 DSML tool calls.
class DeepseekV4Handler extends _DeepseekDsmlHandler {
  @override
  ChatFormat get format => ChatFormat.deepseekV4;

  @override
  String get _callsEnvelope => 'tool_calls';
}

class _DsmlGrammarBuilder {
  static const _prefix = '｜DSML｜';

  final List<ToolDefinition>? tools;
  final String envelope;
  final JsonSchemaConverter _converter = JsonSchemaConverter();
  final List<String> _rules = <String>[];

  _DsmlGrammarBuilder(this.tools, {required this.envelope});

  String? build({bool required = false}) {
    final resolvedTools = tools;
    if (resolvedTools == null || resolvedTools.isEmpty) {
      return null;
    }
    requireUniqueToolNames(resolvedTools, format: 'DeepSeek DSML');

    final callsStart = '<$_prefix$envelope>';
    final callsEnd = '</$_prefix$envelope>';
    final toolRules = <String>[];
    for (var toolIndex = 0; toolIndex < resolvedTools.length; toolIndex++) {
      final tool = resolvedTools[toolIndex];
      requireNonEmptyProtocolName(
        tool.name,
        format: 'DeepSeek DSML',
        kind: 'tool',
      );
      final schema = tool.toJsonSchema();
      _converter.resolveRefs(schema, schema);
      final properties = schemaProperties(schema);
      final requiredNames = schemaRequired(schema);
      final requiredRules = <String>[];
      final optionalRules = <String>[];
      var propertyIndex = 0;
      for (final entry in properties.entries) {
        requireNonEmptyProtocolName(
          entry.key,
          format: 'DeepSeek DSML',
          kind: 'parameter',
        );
        final argumentRule = 'dsml-tool-$toolIndex-arg-${propertyIndex++}';
        final isString = schemaResolvesToString(entry.value);
        const close = '</｜DSML｜parameter>';
        final valueRule = isString
            ? addUntilRules(_rules, '$argumentRule-string', close)
            : _converter.visit(entry.value, '$argumentRule-value');
        final opening =
            '<｜DSML｜parameter name="${escapeAttribute(entry.key)}" '
            'string="${isString ? 'true' : 'false'}">';
        _rules.add(
          '$argumentRule ::= ${ToolCallGrammarUtils.literal(opening)} '
          '$valueRule ${ToolCallGrammarUtils.literal(close)}',
        );
        (requiredNames.contains(entry.key) ? requiredRules : optionalRules).add(
          argumentRule,
        );
      }

      final optionalState = addOptionalStateRules(
        _rules,
        'dsml-tool-$toolIndex-optional',
        optionalRules,
        format: 'DeepSeek DSML',
        schemaPath: 'tool "${tool.name}" arguments',
        separator: 'dsml-space',
      );
      final arguments = <String>[
        ...requiredRules.map((rule) => '$rule dsml-space'),
        ?optionalState,
      ].join(' ');

      final toolRule = 'dsml-tool-$toolIndex';
      _rules.add(
        '$toolRule ::= '
        '${ToolCallGrammarUtils.literal('<｜DSML｜invoke name="${escapeAttribute(tool.name)}">')} '
        'dsml-space $arguments '
        '${ToolCallGrammarUtils.literal('</｜DSML｜invoke>')} dsml-space',
      );
      toolRules.add(toolRule);
    }

    final buffer = StringBuffer()
      ..writeln(
        'root ::= ${ToolCallGrammarUtils.literal(callsStart)} dsml-space '
        'dsml-tool+ ${ToolCallGrammarUtils.literal(callsEnd)}',
      )
      ..writeln('dsml-tool ::= ${toolRules.join(' | ')}')
      ..writeln(r'dsml-space ::= [ \t\n\r]*');
    for (final rule in _rules) {
      buffer.writeln(rule);
    }
    appendJsonRules(buffer, _converter);
    final grammar = buffer.toString();
    return required
        ? withRequiredPrefix(
            grammar,
            delimiter: callsStart,
            prefixName: 'dsml-required-prefix',
          )
        : grammar;
  }
}

ThinkingExtraction _extractDsmlThinking(
  String output, {
  required String callsStart,
  required bool isPartial,
  required bool thinkingForcedOpen,
}) {
  if (thinkingForcedOpen) {
    final callsIndex = output.indexOf(callsStart);
    final thinkEndIndex = output.indexOf('</think>');
    if (callsIndex >= 0 && (thinkEndIndex < 0 || callsIndex < thinkEndIndex)) {
      final reasoning = output.substring(0, callsIndex).trim();
      return (
        content: output.substring(callsIndex).trim(),
        reasoning: reasoning.isEmpty ? null : reasoning,
      );
    }
    if (isPartial) {
      if (thinkEndIndex >= 0 || output.contains('<think>')) {
        final thinking = extractThinking(
          output,
          thinkingForcedOpen: thinkingForcedOpen,
        );
        final pendingMarkerLength = _matchingDelimiterPrefixSuffixLength(
          thinking.content,
          callsStart,
        );
        return (
          content: thinking.content
              .substring(0, thinking.content.length - pendingMarkerLength)
              .trim(),
          reasoning: thinking.reasoning,
        );
      }
      final pendingMarkerLength = _matchingDelimiterPrefixSuffixLength(
        output,
        callsStart,
      );
      final reasoning = output
          .substring(0, output.length - pendingMarkerLength)
          .trim();
      return (content: '', reasoning: reasoning.isEmpty ? null : reasoning);
    }
  }
  return extractThinking(output, thinkingForcedOpen: thinkingForcedOpen);
}

int _matchingDelimiterPrefixSuffixLength(String input, String delimiter) {
  final maxLength = input.length < delimiter.length - 1
      ? input.length
      : delimiter.length - 1;
  for (var length = maxLength; length > 0; length--) {
    if (input.endsWith(delimiter.substring(0, length))) {
      return length;
    }
  }
  return 0;
}

Map<String, dynamic>? _parseDsmlArguments(
  String body, {
  Map<String, dynamic>? schema,
}) {
  final pattern = RegExp(
    r'<｜DSML｜parameter name="([^"]+)" string="(true|false)">([\s\S]*?)</｜DSML｜parameter>',
  );
  if (body.replaceAll(pattern, '').trim().isNotEmpty) {
    return null;
  }
  final result = <String, dynamic>{};
  final properties = schema == null ? null : schemaProperties(schema);
  for (final match in pattern.allMatches(body)) {
    final key = decodeCanonicalAttribute(match.group(1) ?? '');
    final stringAttribute = match.group(2) == 'true';
    final raw = match.group(3) ?? '';
    final propertySchema = key == null ? null : properties?[key];
    if (key == null ||
        key.isEmpty ||
        result.containsKey(key) ||
        (properties != null && propertySchema == null) ||
        (propertySchema != null &&
            stringAttribute != schemaResolvesToString(propertySchema))) {
      return null;
    }
    if (propertySchema != null) {
      final decoded = decodeToolSchemaText(raw, propertySchema);
      if (!decoded.valid) {
        return null;
      }
      result[key] = decoded.value;
    } else if (stringAttribute) {
      result[key] = raw;
    } else {
      final decoded = ToolCallParsingUtils.decodeJsonValue(raw);
      if (decoded == null && raw.trim() != 'null') {
        return null;
      }
      result[key] = decoded;
    }
  }
  if (schema != null &&
      !result.keys.toSet().containsAll(schemaRequired(schema))) {
    return null;
  }
  return result;
}
