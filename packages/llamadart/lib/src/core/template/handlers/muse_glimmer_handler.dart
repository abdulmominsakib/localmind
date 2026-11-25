import '../../exceptions.dart';
import '../../grammar/json_schema_converter.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../tool_call_grammar_utils.dart';
import '../tool_call_parsing_utils.dart';
import '../tool_schema_utils.dart';
import 'specialized_handler_utils.dart';

/// Handler for Muse Glimmer recipient channels and ATEM tool calls.
class MuseGlimmerHandler extends DirectJinjaHandler
    implements ToolSchemaAwareChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.museGlimmer;

  @override
  bool get parsesThoughtBeforeEndTag => false;

  @override
  List<String> get additionalStops => const ['<|eot|>'];

  @override
  List<String> get preservedTokens => const [
    '<|start|>',
    '<|message|>',
    '<|eom|>',
    '<|eot|>',
    '<atem:function_calls>',
    '</atem:function_calls>',
  ];

  @override
  List<String> get grammarTriggerValues => const ['<atem:function_calls>'];

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

  /// Parses Muse output using [tools] for schema-directed argument types.
  @override
  ChatParseResult parseWithTools(
    String output, {
    List<ToolDefinition>? tools,
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    final schemas = parseToolCalls
        ? toolSchemas(tools)
        : const <String, Map<String, dynamic>>{};
    final channelPattern = RegExp(
      r'(?:<\|start\|>assistant)?\s+to=([^<]+)<\|message\|>([\s\S]*?)(<\|eom\|>|<\|eot\|>|$)',
    );
    final matches = channelPattern.allMatches(output).toList(growable: false);
    if (matches.isEmpty) {
      return ChatParseResult(
        content: (isPartial ? _hideIncompleteMuseRoute(output) : output).trim(),
      );
    }

    final content = StringBuffer();
    final reasoning = StringBuffer();
    final calls = <LlamaCompletionChunkToolCall>[];
    int? lastContentCodeUnit;
    var cursor = 0;
    for (final match in matches) {
      lastContentCodeUnit = _appendMuseContent(
        content,
        lastContentCodeUnit,
        output.substring(cursor, match.start),
      );
      final rawRecipient = match.group(1) ?? '';
      final recipient = rawRecipient.trim();
      final body = match.group(2) ?? '';
      if (recipient.isEmpty || rawRecipient != recipient) {
        final terminator = match.group(3) ?? '';
        if (!isPartial || terminator.isNotEmpty) {
          lastContentCodeUnit = _appendMuseContent(
            content,
            lastContentCodeUnit,
            match.group(0) ?? body,
            channelBody: true,
          );
        }
      } else if (recipient == 'self') {
        if (reasoning.isNotEmpty) reasoning.writeln();
        reasoning.write(body);
      } else if (recipient == 'user') {
        lastContentCodeUnit = _appendMuseContent(
          content,
          lastContentCodeUnit,
          body,
          channelBody: true,
        );
      } else if (parseToolCalls) {
        final parsed = _parseAtemCalls(body, calls.length, schemas: schemas);
        final routeMatchesCall =
            parsed != null &&
            parsed.length == 1 &&
            parsed.single.function?.name == recipient;
        if (!routeMatchesCall) {
          final terminator = match.group(3) ?? '';
          if (!isPartial || terminator.isNotEmpty) {
            lastContentCodeUnit = _appendMuseContent(
              content,
              lastContentCodeUnit,
              match.group(0) ?? body,
              channelBody: true,
            );
          }
        } else {
          calls.addAll(parsed);
        }
      } else {
        lastContentCodeUnit = _appendMuseContent(
          content,
          lastContentCodeUnit,
          body,
          channelBody: true,
        );
      }
      cursor = match.end;
    }
    final trailing = output.substring(cursor);
    _appendMuseContent(
      content,
      lastContentCodeUnit,
      isPartial ? _hideIncompleteMuseRoute(trailing) : trailing,
    );

    return ChatParseResult(
      content: content.toString().trim(),
      reasoningContent: nullIfEmpty(reasoning.toString()),
      toolCalls: calls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return _MuseGrammarBuilder(tools).build();
  }

  @override
  String? buildRequiredGrammar(List<ToolDefinition>? tools) {
    return _MuseGrammarBuilder(tools).build(required: true);
  }
}

int? _appendMuseContent(
  StringBuffer content,
  int? lastCodeUnit,
  String value, {
  bool channelBody = false,
}) {
  if (value.isEmpty) {
    return lastCodeUnit;
  }
  if (channelBody &&
      lastCodeUnit != null &&
      !isProtocolWhitespace(lastCodeUnit) &&
      !isProtocolWhitespace(value.codeUnitAt(0))) {
    content.writeln();
  }
  content.write(value);
  return value.codeUnitAt(value.length - 1);
}

String _hideIncompleteMuseRoute(String input) {
  const routeStarts = ['<|start|>assistant to=', ' to='];
  var hideFrom = input.length;
  for (final routeStart in routeStarts) {
    for (var length = 1; length < routeStart.length; length++) {
      final prefix = routeStart.substring(0, length);
      if (input.endsWith(prefix)) {
        hideFrom = hideFrom < input.length - length
            ? hideFrom
            : input.length - length;
      }
    }
    final completeStart = input.lastIndexOf(routeStart);
    if (completeStart >= 0 &&
        input.indexOf('<|message|>', completeStart + routeStart.length) < 0) {
      hideFrom = hideFrom < completeStart ? hideFrom : completeStart;
    }
  }
  return input.substring(0, hideFrom);
}

class _MuseGrammarBuilder {
  static const _scopeStart = '<atem:function_calls>';
  static const _scopeEnd = '</atem:function_calls>';

  final List<ToolDefinition>? tools;
  final JsonSchemaConverter _converter = JsonSchemaConverter();
  final List<String> _rules = <String>[];

  _MuseGrammarBuilder(this.tools);

  String? build({bool required = false}) {
    final resolvedTools = tools;
    if (resolvedTools == null || resolvedTools.isEmpty) {
      return null;
    }
    requireUniqueToolNames(resolvedTools, format: 'Muse Glimmer');

    final toolRules = <String>[];
    final requiredToolRules = <String>[];
    for (var toolIndex = 0; toolIndex < resolvedTools.length; toolIndex++) {
      final tool = resolvedTools[toolIndex];
      _requireMuseRecipientName(tool.name);
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
          format: 'Muse Glimmer',
          kind: 'parameter',
        );
        final argumentRule = 'muse-tool-$toolIndex-arg-${propertyIndex++}';
        const close = '</atem:parameter>';
        final valueRule = schemaResolvesToString(entry.value)
            ? addUntilRules(_rules, '$argumentRule-string', close)
            : _converter.visit(entry.value, '$argumentRule-value');
        final opening = '<atem:parameter name="${escapeAttribute(entry.key)}">';
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
        'muse-tool-$toolIndex-optional',
        optionalRules,
        format: 'Muse Glimmer',
        schemaPath: 'tool "${tool.name}" arguments',
        separator: 'muse-space',
      );
      final arguments = <String>[
        ...requiredRules.map((rule) => '$rule muse-space'),
        ?optionalState,
      ].join(' ');

      final toolRule = 'muse-tool-$toolIndex';
      _rules.add(
        '$toolRule ::= '
        '${ToolCallGrammarUtils.literal('<atem:invoke name="${escapeAttribute(tool.name)}">')} '
        'muse-space $arguments '
        '${ToolCallGrammarUtils.literal('</atem:invoke>')} muse-space',
      );
      toolRules.add(toolRule);

      final requiredToolRule = 'muse-required-tool-$toolIndex';
      _rules.add(
        '$requiredToolRule ::= '
        '${ToolCallGrammarUtils.literal(' to=${tool.name}<|message|>$_scopeStart')} '
        'muse-space $toolRule ${ToolCallGrammarUtils.literal(_scopeEnd)}',
      );
      requiredToolRules.add(requiredToolRule);
    }

    final buffer = StringBuffer();
    if (required) {
      final analysisBody = addUntilRules(
        _rules,
        'muse-analysis-body',
        '<|eom|>',
      );
      buffer
        ..writeln(
          'root ::= (${ToolCallGrammarUtils.literal('<|start|>assistant')})? '
          'muse-analysis* muse-required-tool',
        )
        ..writeln(
          'muse-analysis ::= '
          '${ToolCallGrammarUtils.literal(' to=self<|message|>')} '
          '$analysisBody '
          '${ToolCallGrammarUtils.literal('<|eom|><|start|>assistant')}',
        )
        ..writeln('muse-required-tool ::= ${requiredToolRules.join(' | ')}');
    } else {
      buffer
        ..writeln(
          'root ::= ${ToolCallGrammarUtils.literal(_scopeStart)} muse-space '
          'muse-tool+ ${ToolCallGrammarUtils.literal(_scopeEnd)}',
        )
        ..writeln('muse-tool ::= ${toolRules.join(' | ')}');
    }
    buffer.writeln(r'muse-space ::= [ \t\n\r]*');
    for (final rule in _rules) {
      buffer.writeln(rule);
    }
    appendJsonRules(buffer, _converter);
    return buffer.toString();
  }
}

List<LlamaCompletionChunkToolCall>? _parseAtemCalls(
  String body,
  int start, {
  Map<String, Map<String, dynamic>> schemas = const {},
}) {
  const scopeStart = '<atem:function_calls>';
  const scopeEnd = '</atem:function_calls>';
  final scopeStartIndex = body.indexOf(scopeStart);
  final scopeEndIndex = body.indexOf(scopeEnd);
  if (scopeStartIndex < 0 || scopeEndIndex < scopeStartIndex) {
    return null;
  }
  if (body.substring(0, scopeStartIndex).trim().isNotEmpty ||
      body.substring(scopeEndIndex + scopeEnd.length).trim().isNotEmpty) {
    return null;
  }
  final scope = body.substring(
    scopeStartIndex + scopeStart.length,
    scopeEndIndex,
  );
  final invokePattern = RegExp(
    r'<atem:invoke name="([^"]+)">([\s\S]*?)</atem:invoke>',
  );
  if (scope.replaceAll(invokePattern, '').trim().isNotEmpty) {
    return null;
  }
  final calls = <LlamaCompletionChunkToolCall>[];
  for (final invoke in invokePattern.allMatches(scope)) {
    final name = decodeCanonicalAttribute(invoke.group(1) ?? '');
    if (name == null) {
      return null;
    }
    final schema = schemas[name];
    if (schemas.isNotEmpty && schema == null) {
      return null;
    }
    final properties = schema == null ? null : schemaProperties(schema);
    final required = schema == null ? const <String>{} : schemaRequired(schema);
    final params = invoke.group(2) ?? '';
    final parameterPattern = RegExp(
      r'<atem:parameter name="([^"]+)">([\s\S]*?)</atem:parameter>',
    );
    if (name.isEmpty ||
        params.replaceAll(parameterPattern, '').trim().isNotEmpty) {
      return null;
    }
    final arguments = <String, dynamic>{};
    for (final parameter in parameterPattern.allMatches(params)) {
      final key = decodeCanonicalAttribute(parameter.group(1) ?? '');
      final raw = parameter.group(2) ?? '';
      if (key == null || key.isEmpty || arguments.containsKey(key)) {
        return null;
      }
      final propertySchema = properties?[key];
      if (properties != null && propertySchema == null) {
        return null;
      }
      if (propertySchema == null) {
        arguments[key] = ToolCallParsingUtils.decodeJsonValueOrString(raw);
      } else {
        final decoded = decodeToolSchemaText(raw, propertySchema);
        if (!decoded.valid) {
          return null;
        }
        arguments[key] = decoded.value;
      }
    }
    if (!arguments.keys.toSet().containsAll(required)) {
      return null;
    }
    calls.add(
      ToolCallParsingUtils.createFunctionToolCall(
        index: start + calls.length,
        name: name,
        arguments: arguments,
      ),
    );
  }
  return calls.isEmpty ? null : calls;
}

void _requireMuseRecipientName(String value) {
  if (value.isEmpty ||
      value.trim() != value ||
      value == 'self' ||
      value == 'user' ||
      value.contains('<')) {
    throw LlamaUnsupportedException(
      'Muse Glimmer cannot represent tool name "$value" in its recipient '
      'channel. Use a non-empty name without surrounding whitespace or "<", '
      'and do not use the reserved names "self" or "user".',
    );
  }
}
