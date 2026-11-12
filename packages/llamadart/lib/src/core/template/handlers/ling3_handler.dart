import '../../grammar/json_schema_converter.dart';
import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/inference/tool_choice.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../template_internal_metadata.dart';
import '../thinking_utils.dart';
import '../tool_call_grammar_utils.dart';
import '../tool_call_parsing_utils.dart';
import '../tool_schema_utils.dart';
import 'specialized_handler_utils.dart';
import 'xml_argument_grammar.dart';

/// Handler for Ling 3.0 (Bailing V3) `<role>` templates.
///
/// A call is `<tool_call>name`, then `<arg_key>k</arg_key>` and
/// `<arg_value>v</arg_value>` pairs, then `</tool_call>`. Parses as llama.cpp's
/// `ling3` parser does: a forced-open thought ends at `</think>` or at a
/// `<tool_call>`, a string value is the raw text up to its closing tag, and
/// any other value is JSON.
class Ling3Handler extends DirectJinjaHandler
    implements ToolSchemaAwareChatTemplateHandler {
  static const String _callStart = '<tool_call>';
  static const String _callEnd = '</tool_call>';
  static const String _keyStart = '<arg_key>';
  static const String _keyEnd = '</arg_key>';
  static const String _valueStart = '<arg_value>';
  static const String _valueEnd = '</arg_value>';
  static const String _roleEnd = '<|role_end|>';
  static const String _thoughtEnd = '</think>';

  @override
  ChatFormat get format => ChatFormat.ling3;

  @override
  List<String> get additionalStops => const [_roleEnd];

  @override
  List<String> get preservedTokens => const [
    '<think>',
    _thoughtEnd,
    _callStart,
    _callEnd,
    _keyStart,
    _keyEnd,
    _valueStart,
    _valueEnd,
    _roleEnd,
  ];

  @override
  List<String> get grammarTriggerValues => const [_callStart];

  @override
  LlamaChatTemplateResult render({
    required String templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    bool enableThinking = true,
  }) {
    final base = super.render(
      templateSource: templateSource,
      messages: messages,
      metadata: metadata,
      addAssistant: addAssistant,
      tools: tools,
      enableThinking: enableThinking,
    );
    final hasTools = tools != null && tools.isNotEmpty;
    final required =
        metadata[internalToolChoiceMetadataKey] == ToolChoice.required.name;
    final parallel = metadata[internalParallelToolCallsMetadataKey] == 'true';
    final rendered = LlamaChatTemplateResult(
      prompt: base.prompt,
      format: base.format,
      grammar: _callGrammar(
        tools,
        parallel: parallel,
        required: required,
        thoughtOpen: base.thinkingForcedOpen,
      ),
      grammarLazy: hasTools && !required,
      thinkingForcedOpen: base.thinkingForcedOpen,
      additionalStops: base.additionalStops,
      preservedTokens: base.preservedTokens,
      grammarTriggers: base.grammarTriggers,
    );
    return withSingleToolCall(
      withThinkingForcedClosed(
        rendered,
        closed: isThinkingForcedClosed(base.prompt),
      ),
      single: hasTools && !parallel,
    );
  }

  /// llama.cpp's Ling 3 call grammar for [tools].
  ///
  /// A string value is any text up to `</arg_value>`; another value is JSON for
  /// its schema, and one that may be either tries the JSON first. The required
  /// arguments come first, in any order up to six of them, then the optional
  /// ones, in any order and possibly repeated. With [required], text and,
  /// after a forced-open [thoughtOpen], the thought precede the calls.
  static String? _callGrammar(
    List<ToolDefinition>? tools, {
    required bool parallel,
    required bool required,
    required bool thoughtOpen,
  }) {
    if (tools == null || tools.isEmpty) return null;
    final literal = ToolCallGrammarUtils.literal;
    final converter = JsonSchemaConverter();
    final valueEnds = ValueEndRules(converter);
    final rules = <String>[];
    final stringValue = addThroughRules(rules, 'ling3-arg-string', _valueEnd);
    final toolRules = <String>[];
    final schemas = toolSchemas(tools);
    for (var toolIndex = 0; toolIndex < tools.length; toolIndex++) {
      final tool = tools[toolIndex];
      final schema = schemas[tool.name]!;
      converter.resolveRefs(schema, schema);
      final requiredNames = schemaRequired(schema);
      final requiredRules = <String>[];
      final optionalRules = <String>[];
      var argumentIndex = 0;
      for (final MapEntry(:key, :value) in schemaProperties(schema).entries) {
        final argumentRule = 'ling3-arg-$toolIndex-${argumentIndex++}';
        final valueRule = mayBeString(value)
            ? stringValue
            : '${valueEnds.visit(value, '$argumentRule-schema')} '
                  '${literal(_valueEnd)}';
        rules.add(
          '$argumentRule ::= space? ${literal(_keyStart)} ${literal(key)} '
          '${literal(_keyEnd)} space? ${literal(_valueStart)} $valueRule',
        );
        (requiredNames.contains(key) ? requiredRules : optionalRules).add(
          argumentRule,
        );
      }
      final arguments = [
        if (requiredRules.isNotEmpty)
          permutedArguments(rules, 'ling3-$toolIndex-args', requiredRules),
        if (optionalRules.isNotEmpty) '(${optionalRules.join(' | ')})*',
      ];
      final toolRule = 'ling3-tool-$toolIndex';
      rules.add(
        '$toolRule ::= ${literal(_callStart)} ${literal(tool.name)} '
        '${arguments.isEmpty ? '' : '${arguments.join(' ')} '}'
        'space? ${literal(_callEnd)}',
      );
      toolRules.add(toolRule);
    }

    final oneCall = '(${toolRules.join(' | ')})';
    final buffer = StringBuffer()
      ..writeln(
        'ling3-tool-call ::= $oneCall'
        '${parallel ? ' (space $oneCall)*' : ''} '
        'space ling3-tail? ${literal(_roleEnd)}?',
      )
      ..writeln(
        'root ::= ${required ? '${thoughtOpen ? 'ling3-thought ${literal(_thoughtEnd)}? ' : ''}'
                  'ling3-content? ling3-tool-call ling3-tail? '
                  '${literal(_roleEnd)}?' : 'ling3-tool-call'}',
      )
      ..writeln(r'space ::= | " " | "\n"{1,2} [ \t]{0,20}');
    ToolCallGrammarUtils.excludingRules('ling3-tail', [
      _roleEnd,
    ]).forEach(buffer.writeln);
    if (required) {
      ToolCallGrammarUtils.excludingRules('ling3-content', [
        _callStart,
      ]).forEach(buffer.writeln);
      if (thoughtOpen) {
        ToolCallGrammarUtils.excludingRules('ling3-thought', [
          _thoughtEnd,
          _callStart,
        ]).forEach(buffer.writeln);
      }
    }
    rules.forEach(buffer.writeln);
    valueEnds.writeTo(buffer);
    return buffer.toString();
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) =>
      _callGrammar(tools, parallel: true, required: false, thoughtOpen: false);

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

  /// Parses [output] as llama.cpp's Ling 3 parser does, after a prompt that
  /// opens a thought only with [thinkingForcedOpen].
  ///
  /// The reasoning ends at `</think>` or at the first `<tool_call>`, and the
  /// content before the first call is text. The first call is a complete one
  /// of a declared tool, and [singleToolCall] allows no other. Anything that
  /// follows the calls up to `<|role_end|>`, and anything after that, is
  /// content, as is a `<tool_call>` that is not a valid call. A first call
  /// that the output ends inside is dropped, and a partial parse also holds
  /// back every ending that may start a tag.
  @override
  ChatParseResult parseWithTools(
    String output, {
    List<ToolDefinition>? tools,
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
    bool singleToolCall = false,
  }) {
    final content = StringBuffer();
    String? reasoning;
    var position = 0;
    if (thinkingForcedOpen) {
      final end = _firstOf(output, const [_thoughtEnd, _callStart], 0);
      if (end < 0) {
        return ChatParseResult(
          content: '',
          reasoningContent: _nonEmpty(
            isPartial
                ? withoutTrailingTagPrefix(output, const [
                    _thoughtEnd,
                    _callStart,
                  ])
                : output,
          ),
        );
      }
      reasoning = output.substring(0, end);
      position = end;
      if (output.startsWith(_thoughtEnd, position)) {
        position += _thoughtEnd.length;
      }
    }

    final schemas = parseToolCalls
        ? toolSchemas(tools)
        : const <String, Map<String, dynamic>>{};
    final toolCalls = <Map<String, dynamic>>[];
    var held = false;
    if (schemas.isNotEmpty) {
      final converter = JsonSchemaConverter();
      for (final schema in schemas.values) {
        converter.resolveRefs(schema, schema);
      }
      final open = output.indexOf(_callStart, position);
      final textEnd = open < 0 ? output.length : open;
      final text = output.substring(position, textEnd);
      content.write(
        open < 0 && isPartial
            ? withoutTrailingTagPrefix(text, const [_callStart])
            : text,
      );
      if (open >= 0) {
        position = open;
        final section = _callSection(
          output,
          open,
          tools!,
          schemas,
          single: singleToolCall,
          isPartial: isPartial,
        );
        held = section.held;
        if (section.calls.isNotEmpty) {
          toolCalls.addAll(section.calls);
          position = section.end;
        }
      } else {
        position = output.length;
      }
    }
    if (!held) content.write(_tail(output, position, isPartial: isPartial));

    return ChatParseResult(
      content: content.toString().trim(),
      reasoningContent: _nonEmpty(reasoning),
      toolCalls: [
        for (var index = 0; index < toolCalls.length; index++)
          ToolCallParsingUtils.createFunctionToolCall(
            index: index,
            name: toolCalls[index]['name'] as String,
            arguments: toolCalls[index]['arguments'] as Map<String, dynamic>,
          ),
      ],
    );
  }

  static String? _nonEmpty(String? text) {
    final trimmed = text?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static int _firstOf(String text, List<String> markers, int from) {
    var first = -1;
    for (final marker in markers) {
      final index = text.indexOf(marker, from);
      if (index >= 0 && (first < 0 || index < first)) first = index;
    }
    return first;
  }

  /// The text of [output] from [from] up to the second `<|role_end|>`, without
  /// either, and then the rest: as llama.cpp reads it after the calls.
  static String _tail(String output, int from, {required bool isPartial}) {
    final buffer = StringBuffer();
    var position = from;
    for (var pass = 0; pass < 2 && position < output.length; pass++) {
      final end = output.indexOf(_roleEnd, position);
      if (end < 0) {
        final text = output.substring(position);
        buffer.write(
          isPartial ? withoutTrailingTagPrefix(text, const [_roleEnd]) : text,
        );
        return buffer.toString();
      }
      buffer.write(output.substring(position, end));
      position = end + _roleEnd.length;
    }
    if (position < output.length) buffer.write(output.substring(position));
    return buffer.toString();
  }

  /// The calls that start at [start] and the end of the last one.
  ///
  /// [_CallSection.held] is whether the output ends inside a call that more
  /// output may complete into one.
  static _CallSection _callSection(
    String output,
    int start,
    List<ToolDefinition> tools,
    Map<String, Map<String, dynamic>> schemas, {
    required bool single,
    required bool isPartial,
  }) {
    final calls = <Map<String, dynamic>>[];
    var position = start;
    var end = start;
    while (true) {
      final result = _parseCall(output, position, tools, schemas);
      if (result.status == _Status.matched) {
        calls.add({'name': result.name, 'arguments': result.arguments});
        end = result.end;
        if (single) break;
        position = _skipSpace(output, end);
        if (!output.startsWith(_callStart, position)) {
          final rest = output.substring(position);
          final startsCall =
              isPartial && rest.isNotEmpty && _callStart.startsWith(rest);
          return _CallSection(calls, position, held: startsCall);
        }
        continue;
      }
      if (result.status == _Status.incomplete && (isPartial || calls.isEmpty)) {
        return _CallSection(calls, end, held: true);
      }
      break;
    }
    return _CallSection(calls, calls.isEmpty ? start : _skipSpace(output, end));
  }

  static int _skipSpace(String text, int from) {
    var index = from;
    while (index < text.length && ' \t\r\n'.contains(text[index])) {
      index++;
    }
    return index;
  }

  static _CallResult _parseCall(
    String output,
    int start,
    List<ToolDefinition> tools,
    Map<String, Map<String, dynamic>> schemas,
  ) {
    var incomplete = false;
    for (final tool in tools) {
      final result = _parseToolCall(
        output,
        start,
        tool.name,
        schemas[tool.name]!,
      );
      if (result.status == _Status.matched) return result;
      incomplete |= result.status == _Status.incomplete;
    }
    return incomplete ? _CallResult.incomplete : _CallResult.failed;
  }

  static _CallResult _parseToolCall(
    String output,
    int start,
    String toolName,
    Map<String, dynamic> schema,
  ) {
    var position = start + _callStart.length;
    final named = _literal(output, position, toolName);
    if (named != _Status.matched) return _CallResult.of(named);
    position = _skipSpace(output, position + toolName.length);

    final properties = schemaProperties(schema);
    final requiredNames = schemaRequired(schema);
    final pending = [
      for (final name in properties.keys)
        if (requiredNames.contains(name)) name,
    ];
    final optional = [
      for (final name in properties.keys)
        if (!requiredNames.contains(name)) name,
    ];
    final arguments = <String, dynamic>{};
    while (pending.isNotEmpty) {
      final result = _parseArgument(
        output,
        position,
        properties,
        pending.length > 6 ? pending.sublist(0, 1) : pending,
      );
      if (result.status != _Status.matched) {
        return _CallResult.of(result.status);
      }
      arguments[result.name!] = result.value;
      pending.remove(result.name);
      position = result.end;
    }
    while (optional.isNotEmpty) {
      final result = _parseArgument(output, position, properties, optional);
      if (result.status == _Status.incomplete) return _CallResult.incomplete;
      if (result.status != _Status.matched) break;
      arguments[result.name!] = result.value;
      position = result.end;
    }
    position = _skipSpace(output, position);
    final closed = _literal(output, position, _callEnd);
    return closed == _Status.matched
        ? _CallResult(toolName, arguments, position + _callEnd.length)
        : _CallResult.of(closed);
  }

  /// Whether [literal] is at [position] of [text], is the start of what [text]
  /// ends with there, or is not at all.
  static _Status _literal(String text, int position, String literal) {
    if (text.startsWith(literal, position)) return _Status.matched;
    return literal.startsWith(text.substring(position))
        ? _Status.incomplete
        : _Status.failed;
  }

  static _Argument _parseArgument(
    String output,
    int start,
    Map<String, Map<String, dynamic>> properties,
    List<String> allowed,
  ) {
    var position = _skipSpace(output, start);
    final opening = _literal(output, position, _keyStart);
    if (opening != _Status.matched) return _Argument.of(opening);
    position += _keyStart.length;
    String? name;
    var incomplete = false;
    for (final candidate in allowed) {
      final status = _literal(output, position, '$candidate$_keyEnd');
      if (status == _Status.matched) {
        name = candidate;
        break;
      }
      incomplete |= status == _Status.incomplete;
    }
    if (name == null) {
      return incomplete ? _Argument.incomplete : _Argument.failed;
    }
    position = _skipSpace(output, position + name.length + _keyEnd.length);
    final valueOpening = _literal(output, position, _valueStart);
    if (valueOpening != _Status.matched) return _Argument.of(valueOpening);
    position += _valueStart.length;

    final schema = properties[name]!;
    final onlyString = _onlyString(schema);
    if (!onlyString) {
      final json = _jsonValue(output, position);
      if (json.status == _Status.matched) {
        return _Argument(name, json.value, json.end);
      }
      if (!mayBeString(schema)) return _Argument.of(json.status);
    }
    final close = output.indexOf(_valueEnd, position);
    return close < 0
        ? _Argument.incomplete
        : _Argument(
            name,
            output.substring(position, close),
            close + _valueEnd.length,
          );
  }

  /// A JSON value at [position] directly followed by `</arg_value>`.
  static _Argument _jsonValue(String output, int position) {
    final slice = ToolCallParsingUtils.extractLeadingJsonValue(
      output,
      position,
    );
    if (slice == null) {
      return output.indexOf(_valueEnd, position) < 0
          ? _Argument.incomplete
          : _Argument.failed;
    }
    final closed = _literal(output, slice.end, _valueEnd);
    return closed == _Status.matched
        ? _Argument(null, slice.value, slice.end + _valueEnd.length)
        : _Argument.of(closed);
  }

  /// Whether every value of [schema] is a string, which llama.cpp then takes
  /// as raw text.
  static bool _onlyString(Map<String, dynamic> schema) {
    final type = schema['type'];
    if (type is String) return type == 'string';
    if (type is List) return type.length == 1 && type.first == 'string';
    if (schema.containsKey('const')) return schema['const'] is String;
    final values = schema['enum'];
    if (values is List) {
      return values.isNotEmpty && values.every((value) => value is String);
    }
    for (final key in const ['anyOf', 'oneOf']) {
      final children = schema[key];
      if (children is List) {
        return children.every(
          (child) => child is Map && _onlyString(child.cast<String, dynamic>()),
        );
      }
    }
    return false;
  }
}

enum _Status { matched, incomplete, failed }

final class _CallSection {
  _CallSection(this.calls, this.end, {this.held = false});

  final List<Map<String, dynamic>> calls;
  final int end;
  final bool held;
}

final class _CallResult {
  _CallResult(String this.name, Map<String, dynamic> this.arguments, this.end)
    : status = _Status.matched;
  const _CallResult.of(this.status) : name = null, arguments = null, end = -1;

  static const incomplete = _CallResult.of(_Status.incomplete);
  static const failed = _CallResult.of(_Status.failed);

  final _Status status;
  final String? name;
  final Map<String, dynamic>? arguments;
  final int end;
}

final class _Argument {
  const _Argument(this.name, this.value, this.end) : status = _Status.matched;
  const _Argument.of(this.status) : name = null, value = null, end = -1;

  static const incomplete = _Argument.of(_Status.incomplete);
  static const failed = _Argument.of(_Status.failed);

  final _Status status;
  final String? name;
  final Object? value;
  final int end;
}
