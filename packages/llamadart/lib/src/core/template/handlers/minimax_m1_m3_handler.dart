import 'dart:convert';

import '../../exceptions.dart';
import '../../grammar/json_schema_converter.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';
import '../tool_call_grammar_utils.dart';
import '../tool_call_parsing_utils.dart';
import '../tool_schema_utils.dart';
import 'specialized_handler_utils.dart';

/// Handler for MiniMax M1 newline-delimited JSON tool calls.
class MinimaxM1Handler extends DirectJinjaHandler
    implements ToolSchemaAwareChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.minimaxM1;

  @override
  bool get parsesThoughtBeforeEndTag => false;

  @override
  List<String> get additionalStops => const ['<end_of_sentence>'];

  @override
  List<String> get preservedTokens => const [
    '<tool_calls>',
    '</tool_calls>',
    '<end_of_sentence>',
  ];

  @override
  List<String> get grammarTriggerValues => const ['<tool_calls>'];

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

  /// Parses MiniMax M1 output using [tools] to validate emitted call objects.
  @override
  ChatParseResult parseWithTools(
    String output, {
    List<ToolDefinition>? tools,
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    if (!parseToolCalls) {
      return ChatParseResult(content: output.trim());
    }
    const start = '<tool_calls>';
    const end = '</tool_calls>';
    final startIndex = output.indexOf(start);
    if (startIndex < 0) {
      return ChatParseResult(
        content:
            (isPartial ? hideIncompleteProtocolSuffix(output, start) : output)
                .trim(),
      );
    }
    final endIndex = output.indexOf(end, startIndex + start.length);
    if (endIndex < 0) {
      return ChatParseResult(
        content: isPartial
            ? output.substring(0, startIndex).trim()
            : output.trim(),
      );
    }

    final body = output.substring(startIndex + start.length, endIndex);
    final calls = _parseJsonObjectSequence(body, schemas: toolSchemas(tools));
    if (calls == null) {
      return ChatParseResult(content: output.trim());
    }
    final remaining = output.replaceRange(
      startIndex,
      endIndex + end.length,
      '',
    );
    return ChatParseResult(content: remaining.trim(), toolCalls: calls);
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    if (tools == null || tools.isEmpty) {
      return null;
    }
    requireUniqueToolNames(tools, format: 'MiniMax M1');

    final converter = JsonSchemaConverter();
    final callRules = <String>[];
    for (var i = 0; i < tools.length; i++) {
      final tool = tools[i];
      final schema = tool.toJsonSchema();
      converter.resolveRefs(schema, schema);
      final argumentsRule = converter.visit(schema, 'tool-$i-arguments');
      final callRule = 'tool-$i-call';
      converter.rules[callRule] =
          '"{" space "\\"name\\"" space ":" space '
          '${ToolCallGrammarUtils.literal(jsonEncode(tool.name))} space "," space '
          '"\\"arguments\\"" space ":" space $argumentsRule "}" space';
      callRules.add(callRule);
    }

    final buffer = StringBuffer()
      ..writeln('root ::= "<tool_calls>\\n" tool-call+ "</tool_calls>"')
      ..writeln('tool-call ::= tool-choice "\\n"')
      ..writeln('tool-choice ::= ${callRules.join(' | ')}');
    final otherRules = converter.rules.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in otherRules) {
      buffer.writeln('${entry.key} ::= ${entry.value}');
    }
    return buffer.toString();
  }
}

/// Handler for MiniMax M3 namespaced XML tool calls.
class MinimaxM3Handler extends DirectJinjaHandler
    implements ToolSchemaAwareChatTemplateHandler {
  /// Namespace prefix emitted before every MiniMax M3 tool tag.
  static const namespace = ']<]minimax[>[';

  @override
  ChatFormat get format => ChatFormat.minimaxM3;

  @override
  String get thinkingStartTag => '<mm:think>';

  @override
  String get thinkingEndTag => '</mm:think>';

  @override
  List<String> get additionalStops => const ['[e~['];

  @override
  List<String> get preservedTokens => const [
    '<mm:think>',
    '</mm:think>',
    namespace,
  ];

  @override
  List<String> get grammarTriggerValues => const ['$namespace<tool_call>'];

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

  /// Parses MiniMax M3 output using [tools] for schema-directed argument types.
  @override
  ChatParseResult parseWithTools(
    String output, {
    List<ToolDefinition>? tools,
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    // Partial markers are provisional: emitting them now cannot be undone
    // when the remaining bytes complete a thinking delimiter. Final parsing
    // keeps unmatched prefixes as literal text.
    final thinkingInput = isPartial
        ? hideIncompleteProtocolSuffix(
            hideIncompleteProtocolSuffix(output, thinkingEndTag),
            thinkingStartTag,
          )
        : output;
    final thinking = thinkingForcedOpen
        ? extractForcedOpenThoughtVerbatim(
            output,
            endTag: thinkingEndTag,
            isPartial: isPartial,
          )
        : extractThinking(
            thinkingInput,
            startTag: thinkingStartTag,
            endTag: thinkingEndTag,
          );
    if (!parseToolCalls) {
      return ChatParseResult(
        content: thinking.content,
        reasoningContent: thinking.reasoning,
      );
    }
    final schemas = toolSchemas(tools);
    final rawContent = thinking.content;
    const namespacedScopeStart = '$namespace<tool_call>';
    const namespacedScopeEnd = '$namespace</tool_call>';
    final scopeStartIndex = rawContent.indexOf(namespacedScopeStart);
    if (scopeStartIndex < 0) {
      return ChatParseResult(
        content: isPartial
            ? hideIncompleteProtocolSuffix(rawContent, namespacedScopeStart)
            : rawContent,
        reasoningContent: thinking.reasoning,
      );
    }
    final scopeEndIndex = rawContent.indexOf(
      namespacedScopeEnd,
      scopeStartIndex + namespacedScopeStart.length,
    );
    if (scopeEndIndex < 0 && !isPartial) {
      return ChatParseResult(
        content: rawContent,
        reasoningContent: thinking.reasoning,
      );
    }
    final parsed = parseInvokeScope(
      rawContent,
      scopeStart: namespacedScopeStart,
      scopeEnd: namespacedScopeEnd,
      invokeStartPattern: RegExp(
        '${RegExp.escape(namespace)}<invoke name="([^"]+)">',
      ),
      invokeEnd: '$namespace</invoke>',
      parseArguments: (name, body) {
        final schema = schemas[name];
        if (schemas.isNotEmpty && schema == null) {
          return null;
        }
        return _parseDynamicTagArguments(
          body,
          schema: schema,
          tagPrefix: namespace,
        );
      },
      isPartial: isPartial,
    );
    return ChatParseResult(
      content: parsed.success ? parsed.remaining.trim() : rawContent,
      reasoningContent: thinking.reasoning,
      toolCalls: parsed.success ? parsed.calls : const [],
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return _MinimaxM3GrammarBuilder(tools).build();
  }

  @override
  String? buildRequiredGrammar(List<ToolDefinition>? tools) {
    return _MinimaxM3GrammarBuilder(tools).build(required: true);
  }
}

class _MinimaxM3GrammarBuilder {
  static const _namespace = MinimaxM3Handler.namespace;

  final List<ToolDefinition>? tools;
  final JsonSchemaConverter _converter = JsonSchemaConverter();
  final List<String> _rules = <String>[];

  _MinimaxM3GrammarBuilder(this.tools);

  String? build({bool required = false}) {
    final resolvedTools = tools;
    if (resolvedTools == null || resolvedTools.isEmpty) {
      return null;
    }
    requireUniqueToolNames(resolvedTools, format: 'MiniMax M3');
    final toolRules = <String>[];
    for (var toolIndex = 0; toolIndex < resolvedTools.length; toolIndex++) {
      final tool = resolvedTools[toolIndex];
      requireNonEmptyProtocolName(
        tool.name,
        format: 'MiniMax M3',
        kind: 'tool',
      );
      final schema = tool.toJsonSchema();
      final arguments = _members(
        schema,
        'm3-tool-$toolIndex-arg',
        schemaPath: 'tool "${tool.name}" arguments',
      );
      final toolRule = 'm3-tool-$toolIndex';
      _rules.add(
        '$toolRule ::= '
        '${ToolCallGrammarUtils.literal('$_namespace<invoke name="${escapeAttribute(tool.name)}">')} '
        'm3-space $arguments m3-space '
        '${ToolCallGrammarUtils.literal('$_namespace</invoke>')} m3-space',
      );
      toolRules.add(toolRule);
    }

    final buffer = StringBuffer()
      ..writeln(
        'root ::= '
        '${ToolCallGrammarUtils.literal('$_namespace<tool_call>')} m3-space '
        'm3-tool+ ${ToolCallGrammarUtils.literal('$_namespace</tool_call>')}',
      )
      ..writeln('m3-tool ::= ${toolRules.join(' | ')}')
      ..writeln(r'm3-space ::= [ \t\n\r]*');
    for (final rule in _rules) {
      buffer.writeln(rule);
    }
    appendJsonRules(buffer, _converter);
    final grammar = buffer.toString();
    return required
        ? withRequiredPrefix(
            grammar,
            delimiter: '$_namespace<tool_call>',
            prefixName: 'm3-required-prefix',
          )
        : grammar;
  }

  String _members(
    Map<String, dynamic> schema,
    String prefix, {
    required String schemaPath,
  }) {
    final properties = schemaProperties(schema);
    final required = schemaRequired(schema);
    final requiredMembers = <String>[];
    final optionalMembers = <String>[];
    var propertyIndex = 0;
    for (final entry in properties.entries) {
      final rule = _element(
        entry.key,
        entry.value,
        '$prefix-${propertyIndex++}',
        schemaPath: '$schemaPath.${entry.key}',
      );
      (required.contains(entry.key) ? requiredMembers : optionalMembers).add(
        rule,
      );
    }
    final optionalState = addOptionalStateRules(
      _rules,
      '$prefix-optional',
      optionalMembers,
      format: 'MiniMax M3',
      schemaPath: schemaPath,
      separator: 'm3-space',
    );
    return <String>[
      ...requiredMembers.map((rule) => '$rule m3-space'),
      ?optionalState,
    ].join(' ');
  }

  String _element(
    String tag,
    Map<String, dynamic> schema,
    String rule, {
    required String schemaPath,
  }) {
    _requireDynamicTagName(tag, format: 'MiniMax M3');
    final closingText = '$_namespace</$tag>';
    final valueRule = _value(
      schema,
      '$rule-value',
      closingText,
      schemaPath: schemaPath,
    );
    _rules.add(
      '$rule ::= ${ToolCallGrammarUtils.literal('$_namespace<$tag>')} '
      '$valueRule ${ToolCallGrammarUtils.literal(closingText)}',
    );
    return rule;
  }

  String _value(
    Map<String, dynamic> schema,
    String prefix,
    String closingText, {
    required String schemaPath,
  }) {
    if (schemaResolvesToString(schema)) {
      return addUntilRules(_rules, '$prefix-string', closingText);
    }
    if (schema['type'] == 'object') {
      return _members(schema, '$prefix-member', schemaPath: schemaPath);
    }
    if (schema['type'] == 'array' && schema['items'] is Map) {
      final item = _element(
        'item',
        Map<String, dynamic>.from(schema['items'] as Map),
        '$prefix-item',
        schemaPath: '$schemaPath[]',
      );
      return '($item m3-space)*';
    }
    return _converter.visit(schema, prefix);
  }
}

List<LlamaCompletionChunkToolCall>? _parseJsonObjectSequence(
  String body, {
  Map<String, Map<String, dynamic>> schemas = const {},
}) {
  final calls = <LlamaCompletionChunkToolCall>[];
  var cursor = 0;
  while (cursor < body.length) {
    while (cursor < body.length &&
        isProtocolWhitespace(body.codeUnitAt(cursor))) {
      cursor++;
    }
    if (cursor == body.length) {
      break;
    }
    final slice = ToolCallParsingUtils.extractLeadingJsonValue(body, cursor);
    if (slice == null || slice.value is! Map) {
      return null;
    }
    if (!ToolCallParsingUtils.hasUniqueJsonObjectKeys(
      body.substring(cursor, slice.end),
    )) {
      return null;
    }
    if (schemas.isEmpty) {
      final parsed = ToolCallParsingUtils.parseToolCallArray(<Object?>[
        slice.value,
      ], startIndex: calls.length);
      if (parsed == null || parsed.length != 1) {
        return null;
      }
      calls.add(parsed.single);
    } else {
      final call = Map<String, dynamic>.from(slice.value! as Map);
      if (call.length != 2 ||
          !call.containsKey('name') ||
          !call.containsKey('arguments')) {
        return null;
      }
      final name = call['name'];
      final arguments = call['arguments'];
      final schema = name is String && name.isNotEmpty ? schemas[name] : null;
      if (schema == null || arguments is! Map) {
        return null;
      }
      final validated = validateToolSchemaValue(arguments, schema);
      if (!validated.valid) {
        return null;
      }
      calls.add(
        ToolCallParsingUtils.createFunctionToolCall(
          index: calls.length,
          name: name,
          arguments: Map<String, dynamic>.from(validated.value! as Map),
        ),
      );
    }
    cursor = slice.end;
  }
  return calls.isEmpty ? null : calls;
}

Map<String, dynamic>? _parseDynamicTagArguments(
  String body, {
  Map<String, dynamic>? schema,
  String tagPrefix = '',
}) {
  final parsed = _parseDynamicElements(
    body,
    schema: schema,
    tagPrefix: tagPrefix,
  );
  if (parsed == null) {
    return null;
  }
  if (parsed.elements.isEmpty) {
    if (body.trim().isNotEmpty) {
      return null;
    }
    return schema == null || schemaRequired(schema).isEmpty
        ? <String, dynamic>{}
        : null;
  }
  if (!_haveUniqueElementNames(parsed.elements)) {
    return null;
  }
  final result = <String, dynamic>{};
  for (final element in parsed.elements) {
    result[element.name] = element.value;
  }
  if (schema != null &&
      !result.keys.toSet().containsAll(schemaRequired(schema))) {
    return null;
  }
  return result;
}

_DynamicElements? _parseDynamicElements(
  String input, {
  Map<String, dynamic>? schema,
  String tagPrefix = '',
}) {
  final elements = <_DynamicElement>[];
  final properties = schema == null ? null : schemaProperties(schema);
  var cursor = 0;
  while (cursor < input.length) {
    while (cursor < input.length &&
        isProtocolWhitespace(input.codeUnitAt(cursor))) {
      cursor++;
    }
    if (cursor == input.length) {
      break;
    }
    final opening = RegExp(
      '${RegExp.escape(tagPrefix)}<([A-Za-z_][A-Za-z0-9_.-]*)>',
    ).matchAsPrefix(input, cursor);
    if (opening == null) {
      return null;
    }
    final name = opening.group(1)!;
    final close = _findMatchingDynamicClose(
      input,
      name,
      opening.end,
      tagPrefix: tagPrefix,
    );
    if (close == null) {
      return null;
    }
    final raw = input.substring(opening.end, close.start);
    final propertySchema = properties?[name];
    if (properties != null && propertySchema == null) {
      return null;
    }
    Object? value;
    if (propertySchema != null && propertySchema['type'] == 'object') {
      final children = _parseDynamicElements(
        raw,
        schema: propertySchema,
        tagPrefix: tagPrefix,
      );
      if (children == null) {
        return null;
      }
      if (!_haveUniqueElementNames(children.elements)) {
        return null;
      }
      value = <String, dynamic>{
        for (final element in children.elements) element.name: element.value,
      };
      if (!(value as Map).keys.toSet().containsAll(
        schemaRequired(propertySchema),
      )) {
        return null;
      }
    } else if (propertySchema != null && propertySchema['type'] == 'array') {
      final itemSchema = propertySchema['items'];
      final itemProperties = itemSchema is Map
          ? <String, dynamic>{
              'type': 'object',
              'properties': {'item': itemSchema},
            }
          : null;
      final children = _parseDynamicElements(
        raw,
        schema: itemProperties,
        tagPrefix: tagPrefix,
      );
      if (children == null ||
          children.elements.any((element) => element.name != 'item')) {
        return null;
      }
      value = children.elements
          .map((element) => element.value)
          .toList(growable: false);
    } else if (propertySchema != null) {
      final decoded = decodeToolSchemaText(raw, propertySchema);
      if (!decoded.valid) {
        return null;
      }
      value = decoded.value;
    } else {
      final children = _parseDynamicElements(raw, tagPrefix: tagPrefix);
      if (children != null && children.elements.isNotEmpty) {
        if (children.elements.every((element) => element.name == 'item')) {
          value = children.elements
              .map((element) => element.value)
              .toList(growable: false);
        } else {
          if (!_haveUniqueElementNames(children.elements)) {
            return null;
          }
          value = <String, dynamic>{
            for (final element in children.elements)
              element.name: element.value,
          };
        }
      } else {
        value = ToolCallParsingUtils.decodeJsonValueOrString(raw);
      }
    }
    elements.add(_DynamicElement(name: name, value: value));
    cursor = close.end;
  }
  return _DynamicElements(elements);
}

bool _haveUniqueElementNames(List<_DynamicElement> elements) {
  final names = <String>{};
  return elements.every((element) => names.add(element.name));
}

({int start, int end})? _findMatchingDynamicClose(
  String input,
  String name,
  int start, {
  String tagPrefix = '',
}) {
  final tagPattern = RegExp(
    '${RegExp.escape(tagPrefix)}<(/?)${RegExp.escape(name)}>',
  );
  var depth = 1;
  for (final match in tagPattern.allMatches(input, start)) {
    if (match.group(1) == '/') {
      depth--;
      if (depth == 0) {
        return (start: match.start, end: match.end);
      }
    } else {
      depth++;
    }
  }
  return null;
}

void _requireDynamicTagName(String value, {required String format}) {
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$').hasMatch(value)) {
    throw LlamaUnsupportedException(
      '$format cannot represent tool parameter "$value" as an XML tag. '
      'Use a name matching [A-Za-z_][A-Za-z0-9_.-]*.',
    );
  }
}

class _DynamicElements {
  final List<_DynamicElement> elements;

  const _DynamicElements(this.elements);
}

class _DynamicElement {
  final String name;
  final Object? value;

  const _DynamicElement({required this.name, required this.value});
}
