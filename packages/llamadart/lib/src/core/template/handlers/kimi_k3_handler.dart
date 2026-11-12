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

/// Handler for Kimi K3's XTML response and typed tool-call protocol.
class KimiK3Handler extends DirectJinjaHandler
    implements ToolSchemaAwareChatTemplateHandler {
  static const _open = '<|open|>';
  static const _close = '<|close|>';
  static const _sep = '<|sep|>';
  static const _thinkClose =
      '$_close'
      'think$_sep';
  static const _responseStart =
      '$_open'
      'response$_sep';
  static const _responseEnd =
      '$_close'
      'response$_sep';
  static const _toolsStart =
      '$_open'
      'tools$_sep';
  static const _toolsEnd =
      '$_close'
      'tools$_sep';

  @override
  ChatFormat get format => ChatFormat.kimiK3;

  @override
  String get thinkingStartTag =>
      '$_open'
      'think$_sep';

  @override
  String get thinkingEndTag => _thinkClose;

  @override
  List<String> get additionalStops => const ['<|end_of_msg|>'];

  @override
  List<String> get preservedTokens => const [
    '<|open|>',
    '<|close|>',
    '<|sep|>',
    '<|end_of_msg|>',
  ];

  @override
  List<String> get grammarTriggerValues => const [_toolsStart];

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

  /// Parses Kimi K3 output using [tools] to validate emitted names and values.
  @override
  ChatParseResult parseWithTools(
    String output, {
    List<ToolDefinition>? tools,
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    var remaining = output.trimLeft();
    String? reasoning;
    var inThought = thinkingForcedOpen;
    if (remaining.startsWith(thinkingStartTag)) {
      remaining = remaining.substring(thinkingStartTag.length);
      inThought = true;
    } else if (isPartial && _isMarkerPrefix(remaining)) {
      return const ChatParseResult(content: '');
    }
    final thinkEnd = remaining.indexOf(_thinkClose);
    if (thinkEnd >= 0) {
      reasoning = remaining.substring(0, thinkEnd).trim();
      remaining = remaining.substring(thinkEnd + _thinkClose.length);
    } else if (inThought) {
      // A thought without a closer ends at the response or, with tools and
      // no response, at a tool block, so the call is not lost in reasoning.
      var responseIndex = remaining.indexOf(_responseStart);
      if (responseIndex < 0 && parseToolCalls) {
        responseIndex = remaining.indexOf(_toolsStart);
      }
      if (responseIndex < 0) {
        return ChatParseResult(
          content: '',
          reasoningContent: nullIfEmpty(
            isPartial ? _hideMarkerSuffix(remaining) : remaining,
          ),
        );
      }
      reasoning = remaining.substring(0, responseIndex).trim();
      remaining = remaining.substring(responseIndex);
    }

    var content = '';
    final responseStart = remaining.indexOf(_responseStart);
    if (responseStart >= 0) {
      final bodyStart = responseStart + _responseStart.length;
      final responseEnd = remaining.indexOf(_responseEnd, bodyStart);
      content = remaining.substring(0, responseStart);
      if (responseEnd < 0) {
        final body = _stripKimiTurnEnd(
          remaining.substring(bodyStart),
          isPartial: isPartial,
        );
        return ChatParseResult(
          content: '$content${isPartial ? _hideMarkerSuffix(body) : body}'
              .trim(),
          reasoningContent: nullIfEmpty(reasoning),
        );
      }
      content += remaining.substring(bodyStart, responseEnd);
      remaining = remaining.substring(responseEnd + _responseEnd.length);
    } else if (isPartial) {
      remaining = _hideMarkerSuffix(remaining);
    }

    if (!parseToolCalls) {
      return ChatParseResult(
        content: '$content${_stripKimiTurnEnd(remaining, isPartial: isPartial)}'
            .trim(),
        reasoningContent: nullIfEmpty(reasoning),
      );
    }

    final parsed = _parseKimiTools(
      remaining,
      isPartial: isPartial,
      schemas: toolSchemas(tools),
    );
    if (!parsed.success) {
      final preserved =
          '$content${_stripKimiTurnEnd(remaining, isPartial: isPartial)}'
              .trim();
      return ChatParseResult(
        content: preserved,
        reasoningContent: nullIfEmpty(reasoning),
      );
    }
    return ChatParseResult(
      content: '$content${parsed.remaining}'.trim(),
      reasoningContent: nullIfEmpty(reasoning),
      toolCalls: parsed.calls,
    );
  }

  ParsedInvokeCalls _parseKimiTools(
    String input, {
    required bool isPartial,
    required Map<String, Map<String, dynamic>> schemas,
  }) {
    final scopeStart = input.indexOf(_toolsStart);
    if (scopeStart < 0) {
      return ParsedInvokeCalls(
        calls: const [],
        remaining: _stripKimiTurnEnd(
          isPartial ? hideIncompleteProtocolSuffix(input, _toolsStart) : input,
          isPartial: isPartial,
        ),
      );
    }
    final bodyStart = scopeStart + _toolsStart.length;
    final scopeEnd = input.indexOf(_toolsEnd, bodyStart);
    if (scopeEnd < 0) {
      return isPartial
          ? ParsedInvokeCalls(
              calls: const [],
              remaining: _stripKimiTurnEnd(
                input.substring(0, scopeStart),
                isPartial: true,
              ),
            )
          : ParsedInvokeCalls.failure();
    }

    final body = input.substring(bodyStart, scopeEnd);
    final callPattern = RegExp(
      r'<\|open\|>call\s+tool="([^"]+)"(?:\s+index="[0-9]+")?<\|sep\|>([\s\S]*?)<\|close\|>call<\|sep\|>',
    );
    final matches = callPattern.allMatches(body).toList(growable: false);
    if (matches.isEmpty || body.replaceAll(callPattern, '').trim().isNotEmpty) {
      return ParsedInvokeCalls.failure();
    }

    final calls = <LlamaCompletionChunkToolCall>[];
    for (final match in matches) {
      final name = decodeCanonicalAttribute(match.group(1) ?? '');
      final callBody = match.group(2) ?? '';
      final schema = name == null ? null : schemas[name];
      if (name == null ||
          name.isEmpty ||
          (schemas.isNotEmpty && schema == null)) {
        return ParsedInvokeCalls.failure();
      }
      final arguments = _parseKimiArguments(callBody, schema: schema);
      if (arguments == null) {
        return ParsedInvokeCalls.failure();
      }
      calls.add(
        ToolCallParsingUtils.createFunctionToolCall(
          index: calls.length,
          name: name,
          arguments: arguments,
        ),
      );
    }

    final removeEnd = scopeEnd + _toolsEnd.length;
    final remaining = input.replaceRange(scopeStart, removeEnd, '');
    return ParsedInvokeCalls(
      calls: calls,
      remaining: _stripKimiTurnEnd(remaining, isPartial: isPartial),
    );
  }

  Map<String, dynamic>? _parseKimiArguments(
    String body, {
    Map<String, dynamic>? schema,
  }) {
    final jsonPattern = RegExp(
      r'<\|open\|>json\s+type="object"<\|sep\|>([\s\S]*?)<\|close\|>json<\|sep\|>',
    );
    final jsonMatch = jsonPattern.firstMatch(body);
    if (jsonMatch != null) {
      if (body.replaceFirst(jsonPattern, '').trim().isNotEmpty) {
        return null;
      }
      final decoded = ToolCallParsingUtils.decodeJsonObject(
        jsonMatch.group(1) ?? '',
      );
      if (decoded == null || schema == null) {
        return decoded;
      }
      final validated = validateToolSchemaValue(decoded, schema);
      return validated.valid
          ? Map<String, dynamic>.from(validated.value! as Map)
          : null;
    }

    final argumentPattern = RegExp(
      r'<\|open\|>argument\s+key="([^"]+)"\s+type="([^"]+)"<\|sep\|>([\s\S]*?)<\|close\|>argument<\|sep\|>',
    );
    if (body.replaceAll(argumentPattern, '').trim().isNotEmpty) {
      return null;
    }
    final result = <String, dynamic>{};
    final properties = schema == null ? null : schemaProperties(schema);
    for (final match in argumentPattern.allMatches(body)) {
      final key = decodeCanonicalAttribute(match.group(1) ?? '');
      final type = match.group(2) ?? '';
      final raw = match.group(3) ?? '';
      final propertySchema = key == null ? null : properties?[key];
      if (key == null ||
          key.isEmpty ||
          result.containsKey(key) ||
          (properties != null && propertySchema == null) ||
          (propertySchema != null && type != _kimiTypeName(propertySchema))) {
        return null;
      }
      if (propertySchema != null) {
        final decoded = decodeToolSchemaText(raw, propertySchema);
        if (!decoded.valid) {
          return null;
        }
        result[key] = decoded.value;
      } else if (type == 'string') {
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

  static const _turnEnd =
      '$_close'
      'message$_sep';

  static const _markers = [
    '$_open'
        'think$_sep',
    _thinkClose,
    _responseStart,
    _responseEnd,
    _toolsStart,
    _turnEnd,
    '<|end_of_msg|>',
  ];

  /// Whether [text] is a proper prefix of a protocol marker.
  static bool _isMarkerPrefix(String text) =>
      text.isNotEmpty &&
      _markers.any(
        (marker) => marker.length > text.length && marker.startsWith(text),
      );

  /// [text] without a trailing proper prefix of a protocol marker, which a
  /// partial parse cannot yet tell from text.
  static String _hideMarkerSuffix(String text) {
    var hidden = 0;
    for (final marker in _markers) {
      for (var length = marker.length - 1; length > hidden; length--) {
        if (text.endsWith(marker.substring(0, length))) {
          hidden = length;
          break;
        }
      }
    }
    return text.substring(0, text.length - hidden);
  }

  /// [input] without turn-end markers, and on a partial parse without one
  /// that is still arriving.
  String _stripKimiTurnEnd(String input, {bool isPartial = false}) {
    var text = input.replaceAll(_turnEnd, '').replaceAll('<|end_of_msg|>', '');
    if (isPartial) {
      text = hideIncompleteProtocolSuffix(text.trimRight(), _turnEnd);
      text = hideIncompleteProtocolSuffix(text, '<|end_of_msg|>');
    }
    return text.trim();
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return _KimiK3GrammarBuilder(tools).build();
  }

  @override
  String? buildRequiredGrammar(List<ToolDefinition>? tools) {
    return _KimiK3GrammarBuilder(tools).build(required: true);
  }
}

class _KimiK3GrammarBuilder {
  final List<ToolDefinition>? tools;
  final JsonSchemaConverter _converter = JsonSchemaConverter();
  final List<String> _rules = <String>[];

  _KimiK3GrammarBuilder(this.tools);

  String? build({bool required = false}) {
    final resolvedTools = tools;
    if (resolvedTools == null || resolvedTools.isEmpty) {
      return null;
    }
    requireUniqueToolNames(resolvedTools, format: 'Kimi K3');

    final callRules = <String>[];
    String? stringValueRule;
    for (var toolIndex = 0; toolIndex < resolvedTools.length; toolIndex++) {
      final tool = resolvedTools[toolIndex];
      requireNonEmptyProtocolName(tool.name, format: 'Kimi K3', kind: 'tool');
      final schema = tool.toJsonSchema();
      final properties = schemaProperties(schema);
      final requiredNames = schemaRequired(schema);
      final requiredRules = <String>[];
      final optionalRules = <String>[];
      var propertyIndex = 0;
      for (final entry in properties.entries) {
        requireNonEmptyProtocolName(
          entry.key,
          format: 'Kimi K3',
          kind: 'parameter',
        );
        final argumentRule = 'kimi-tool-$toolIndex-arg-${propertyIndex++}';
        final typeName = _kimiTypeName(entry.value);
        const close = '<|close|>argument<|sep|>';
        final valueRule = typeName == 'string'
            ? (stringValueRule ??= addUntilRules(
                _rules,
                'kimi-string-value',
                close,
              ))
            : _converter.visit(entry.value, '$argumentRule-value');
        final opening =
            '<|open|>argument key="${escapeAttribute(entry.key)}" '
            'type="$typeName"<|sep|>';
        _rules.add(
          '$argumentRule ::= ${ToolCallGrammarUtils.literal(opening)} '
          '$valueRule ${ToolCallGrammarUtils.literal(close)}',
        );
        (requiredNames.contains(entry.key) ? requiredRules : optionalRules).add(
          argumentRule,
        );
      }

      _converter.resolveRefs(schema, schema);
      final jsonRule = _converter.visit(schema, 'kimi-tool-$toolIndex-json');
      final optionalArguments = addOptionalStateRules(
        _rules,
        'kimi-tool-$toolIndex-optional',
        optionalRules,
        format: 'Kimi K3',
        schemaPath: 'tool "${tool.name}" arguments',
        separator: '',
      );
      final rawArguments = <String>[
        ...requiredRules,
        ?optionalArguments,
      ].join(' ');
      final rawArgumentsRule = rawArguments.isEmpty ? '""' : rawArguments;
      final arguments = properties.isEmpty
          ? '(kimi-empty-arguments | kimi-json-$toolIndex)'
          : '(kimi-raw-$toolIndex | kimi-json-$toolIndex)';
      _rules
        ..add('kimi-raw-$toolIndex ::= $rawArgumentsRule')
        ..add(
          'kimi-json-$toolIndex ::= '
          '${ToolCallGrammarUtils.literal('<|open|>json type="object"<|sep|>')} '
          '$jsonRule '
          '${ToolCallGrammarUtils.literal('<|close|>json<|sep|>')}',
        );
      final callRule = 'kimi-tool-$toolIndex';
      final callOpen = '<|open|>call tool="${escapeAttribute(tool.name)}"';
      _rules.add(
        '$callRule ::= ${ToolCallGrammarUtils.literal(callOpen)} '
        '(" index=\\"" [0-9]+ "\\"")? '
        '${ToolCallGrammarUtils.literal('<|sep|>')} $arguments '
        '${ToolCallGrammarUtils.literal('<|close|>call<|sep|>')}',
      );
      callRules.add(callRule);
    }

    final buffer = StringBuffer()
      ..writeln(
        'root ::= ${ToolCallGrammarUtils.literal('<|open|>tools<|sep|>')} '
        'kimi-tool+ '
        '${ToolCallGrammarUtils.literal('<|close|>tools<|sep|>')} '
        '${ToolCallGrammarUtils.literal('<|close|>message<|sep|>')}',
      )
      ..writeln('kimi-tool ::= ${callRules.join(' | ')}')
      ..writeln('kimi-empty-arguments ::= ""');
    for (final rule in _rules) {
      buffer.writeln(rule);
    }
    appendJsonRules(buffer, _converter);
    final grammar = buffer.toString();
    return required
        ? withRequiredPrefix(
            grammar,
            delimiter: '<|open|>tools<|sep|>',
            prefixName: 'kimi-required-prefix',
          )
        : grammar;
  }
}

String _kimiTypeName(Map<String, dynamic> schema) {
  if (schemaResolvesToString(schema)) {
    return 'string';
  }
  return switch (schema['type']) {
    'integer' || 'number' => 'number',
    'boolean' => 'boolean',
    'null' => 'null',
    'object' => 'object',
    'array' => 'array',
    _ => 'string',
  };
}
