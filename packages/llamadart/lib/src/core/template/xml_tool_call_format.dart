import '../models/tools/tool_definition.dart';
import '../models/chat/completion_chunk.dart';
import 'chat_parse_result.dart';
import 'thinking_utils.dart';
import 'tool_call_parsing_utils.dart';
import 'tool_schema_utils.dart';

/// Describes the XML-style tool call format used by several models.
///
/// Retains the semantics of llama.cpp's former `xml_tool_call_format` struct.
/// Shared by MiniMax M2, Qwen3 Coder XML, Apriel, Seed OSS, and legacy
/// format definitions.
class XmlToolCallFormat {
  /// Opening scope tag (e.g., `<minimax:tool_call>`).
  final String scopeStart;

  /// Start of a tool call (e.g., `<invoke name="`).
  final String toolStart;

  /// Separator between tool name and arguments (e.g., `">`).
  final String toolSep;

  /// Start of a key (e.g., `<parameter name="`).
  final String keyStart;

  /// Separator between key and value (e.g., `">`).
  final String keyValSep;

  /// End of a value (e.g., `</parameter>`).
  final String valEnd;

  /// End of a tool call (e.g., `</invoke>`).
  final String toolEnd;

  /// Closing scope tag (e.g., `</minimax:tool_call>`).
  final String scopeEnd;

  /// How argument values are decoded.
  ///
  /// `true` preserves raw strings, `false` requires JSON, and `null` accepts
  /// either form. This matches the three-state upstream field that preceded
  /// llama.cpp's format-specific PEG parsers.
  final bool? rawArgval;

  /// Whether to trim whitespace from raw argument values.
  final bool trimRawArgval;

  /// Override for the last value's end marker.
  ///
  /// An empty string means the tool-end marker immediately follows the final
  /// value.
  final String? lastValEnd;

  /// Override for the last tool's end marker.
  final String? lastToolEnd;

  /// Whether tool calls can appear inside thinking blocks.
  final bool allowToolcallInThink;

  /// Whether a scope may follow a closed one, separated only by whitespace,
  /// to hold the next tool call.
  ///
  /// The grammar of such a format holds one tool call per scope.
  final bool repeatsScope;

  /// Creates a [XmlToolCallFormat] definition.
  const XmlToolCallFormat({
    required this.scopeStart,
    required this.toolStart,
    required this.toolSep,
    required this.keyStart,
    required this.keyValSep,
    required this.valEnd,
    required this.toolEnd,
    required this.scopeEnd,
    this.rawArgval,
    this.trimRawArgval = false,
    this.lastValEnd,
    this.lastToolEnd,
    this.allowToolcallInThink = false,
    this.repeatsScope = false,
  });

  /// Finds where [parseXmlToolCalls] may find a tool-call opening in [text].
  ///
  /// Returns the first index at or after [from] where [scopeStart], or
  /// [toolStart] without a scope, starts, or where the rest of [text] is the
  /// start of it, and `text.length` when there is none.
  int toolCallOpening(String text, [int from = 0]) =>
      ToolCallParsingUtils.literalOpening(text, [
        scopeStart.isEmpty ? toolStart : scopeStart,
      ], from);

  /// Standard XML format (e.g. Qwen 2.5/3 Coder).
  static const qwen3Coder = XmlToolCallFormat(
    scopeStart: qwen3CoderScopeStart,
    toolStart: '<function=',
    toolSep: '>',
    keyStart: '<parameter=',
    keyValSep: '>',
    valEnd: '</parameter>',
    toolEnd: '</function>',
    scopeEnd: '</tool_call>',
    trimRawArgval: true,
    allowToolcallInThink: true,
    repeatsScope: true,
  );

  /// The tool-call scope opening of [qwen3Coder].
  static const qwen3CoderScopeStart = '<tool_call>';

  /// The opening of a call to [name] outside a scope, such as
  /// `<function=get_weather>`.
  String bareCallOpening(String name) => '$toolStart$name$toolSep';

  /// Kimi K2 format.
  static const kimiK2 = XmlToolCallFormat(
    scopeStart: '<|tool_calls_section_begin|>',
    toolStart: '<|tool_call_begin|>',
    toolSep: '<|tool_call_argument_begin|>{',
    keyStart: '"',
    keyValSep: '": ',
    valEnd: ', ',
    toolEnd: '}<|tool_call_end|>',
    scopeEnd: '<|tool_calls_section_end|>',
    rawArgval: false,
    lastValEnd: '',
  );

  /// MiniMax M2 format.
  static const minimaxM2 = XmlToolCallFormat(
    scopeStart: '<minimax:tool_call>\n',
    toolStart: '<invoke name="',
    toolSep: '">\n',
    keyStart: '<parameter name="',
    keyValSep: '">',
    valEnd: '</parameter>\n',
    toolEnd: '</invoke>\n',
    scopeEnd: '</minimax:tool_call>',
  );

  /// MiniCPM5 XML function-call format.
  static const minicpm5 = XmlToolCallFormat(
    scopeStart: '',
    toolStart: '<function name="',
    toolSep: '">',
    keyStart: '<param name="',
    keyValSep: '">',
    valEnd: '</param>',
    toolEnd: '</function>',
    scopeEnd: '',
  );

  /// Seed-OSS format.
  ///
  /// As in llama.cpp, a scope starts only with a line break after its tag.
  static const seedOss = XmlToolCallFormat(
    scopeStart: '<seed:tool_call>\n',
    toolStart: '<function=',
    toolSep: '>',
    keyStart: '<parameter=',
    keyValSep: '>',
    valEnd: '</parameter>',
    toolEnd: '</function>',
    scopeEnd: '</seed:tool_call>',
    repeatsScope: true,
  );

  /// Apriel 1.5 format.
  static const apriel15 = XmlToolCallFormat(
    scopeStart: '<tool_calls>[',
    toolStart: '{"name": "',
    toolSep: '", "arguments": {',
    keyStart: '"',
    keyValSep: '": ',
    valEnd: ', ',
    toolEnd: '}, ',
    scopeEnd: ']</tool_calls>',
    rawArgval: false,
    lastValEnd: '}',
    lastToolEnd: '}',
  );

  /// Xiaomi MiMo format.
  static const xiaomiMimo = XmlToolCallFormat(
    scopeStart: '',
    toolStart: '<tool_call>\n{"name": "',
    toolSep: '", "arguments": {',
    keyStart: '"',
    keyValSep: '": ',
    valEnd: ', ',
    toolEnd: '}\n</tool_call>',
    scopeEnd: '',
    rawArgval: false,
    lastValEnd: '',
  );

  /// Generic fallback XML format.
  static const generic = XmlToolCallFormat(
    scopeStart: '',
    toolStart: '<tool_code>',
    toolSep: '\n',
    keyStart: '<',
    keyValSep: '>',
    valEnd: '</',
    toolEnd: '</tool_code>',
    scopeEnd: '',
  );
}

/// Builds a simple XML-style tool-call grammar for [format].
///
/// The root of a format that [XmlToolCallFormat.repeatsScope] admits one tool
/// call per scope, in consecutive scopes, as llama.cpp's grammar does; when
/// [parallelToolCalls] is false, exactly one. Other formats ignore it.
String? buildXmlToolCallGrammar(
  List<ToolDefinition>? tools,
  XmlToolCallFormat format, {
  bool parallelToolCalls = true,
}) {
  if (tools == null || tools.isEmpty) {
    return null;
  }

  final toolNames = tools
      .map((tool) => tool.name)
      .toSet()
      .toList(growable: false);
  final paramNames = <String>{};
  for (final tool in tools) {
    for (final parameter in tool.parameters) {
      paramNames.add(parameter.name);
    }
  }

  final toolNameRule = toolNames.map(_literal).join(' | ');
  final paramNameRule = paramNames.isEmpty
      ? 'identifier'
      : paramNames.map(_literal).join(' | ');

  final scopeStart = format.scopeStart.isEmpty
      ? ''
      : '${_literal(format.scopeStart)} ';
  final scopeEnd = format.scopeEnd.isEmpty
      ? ''
      : ' ${_literal(format.scopeEnd)}';
  const jsonValueRules = r'''
identifier ::= [A-Za-z_] [A-Za-z0-9_-]*
space ::= " "?
string ::= "\"" ([^"\\] | "\\\\" .)* "\""
number ::= "-"? ([0-9] | [1-9] [0-9]*) ("." [0-9]+)? ([eE] [-+]? [0-9]+)?
boolean ::= "true" | "false"
null ::= "null"
value ::= string | number | boolean | null | arr | obj
arr ::= "[" space (value ("," space value)*)? space "]"
obj ::= "{" space (string ":" space value ("," space string ":" space value)*)? space "}"
''';

  if (format.repeatsScope) {
    // Seed-OSS emits the XML envelope with line breaks between tags. Lazy grammar
    // activation replays that exact trigger text, so whitespace must be valid
    // in the grammar rather than relying on eager constrained decoding to
    // remove it.
    final scope = 'xml-space tool-call ${_literal(format.scopeEnd)} xml-space';
    return '''
root ::= ${parallelToolCalls ? 'tool-call-scope+' : 'tool-call-scope'}
tool-call-scope ::= ${_literal(format.scopeStart)} $scope
tool-call ::= ${_literal(format.toolStart)} tool-name ${_literal(format.toolSep)} xml-space param* ${_literal(format.toolEnd)} xml-space
param ::= ${_literal(format.keyStart)} param-name ${_literal(format.keyValSep)} xml-value ${_literal(format.valEnd)} xml-space
tool-name ::= $toolNameRule
param-name ::= $paramNameRule
xml-value ::= raw-text | value
raw-text ::= ([^<])*
xml-space ::= [ \\t\\n\\r]*
$jsonValueRules
''';
  }

  if (format == XmlToolCallFormat.minicpm5) {
    return '''
root ::= ${scopeStart}tool-call+$scopeEnd
tool-call ::= ${_literal(format.toolStart)} tool-name ${_literal(format.toolSep)} param* ${_literal(format.toolEnd)}
param ::= ${_literal(format.keyStart)} param-name ${_literal(format.keyValSep)} minicpm-value ${_literal(format.valEnd)}
tool-name ::= $toolNameRule
param-name ::= $paramNameRule
minicpm-value ::= raw-text | value
raw-text ::= ([^<])*
$jsonValueRules
''';
  }

  final argumentValueRule = switch (format.rawArgval) {
    true => 'raw-text',
    false => 'value',
    null => 'argument-value',
  };
  final argumentsRule = format.lastValEnd == null
      ? '(param ${_literal(format.valEnd)})*'
      : format.lastValEnd!.isEmpty
      ? '(param (${_literal(format.valEnd)} param)*)?'
      : '(param (${_literal(format.valEnd)} param)*)? ${_literal(format.lastValEnd!)}';
  final toolCallRule =
      '${_literal(format.toolStart)} tool-name ${_literal(format.toolSep)} arguments ${_literal(format.toolEnd)}';
  final rootRule = format.lastToolEnd == null
      ? '${scopeStart}tool-call+$scopeEnd'
      : '${scopeStart}tool-call* last-tool-call$scopeEnd';
  final lastToolCallRule = format.lastToolEnd == null
      ? ''
      : '\nlast-tool-call ::= ${_literal(format.toolStart)} tool-name ${_literal(format.toolSep)} arguments ${_literal(format.lastToolEnd!)}';
  final rawTextRule = format.rawArgval == false ? '' : '\nraw-text ::= ([^<])*';
  final eitherValueRule = format.rawArgval == null
      ? '\nargument-value ::= raw-text | value'
      : '';

  return '''
root ::= $rootRule
tool-call ::= $toolCallRule$lastToolCallRule
arguments ::= $argumentsRule
param ::= ${_literal(format.keyStart)} param-name ${_literal(format.keyValSep)} $argumentValueRule
tool-name ::= $toolNameRule
param-name ::= $paramNameRule$rawTextRule$eitherValueRule
$jsonValueRules
''';
}

String _literal(String value) {
  final escaped = value
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
  return '"$escaped"';
}

/// Parses XML-style tool calls with optional reasoning.
///
/// Matches llama.cpp's `consume_reasoning_with_xml_tool_calls`.
/// When [schemas] is supplied, only declared tools and schema-valid arguments
/// are accepted. Omitting it preserves the legacy schema-free parser.
/// Escaped `\n` and `\r` in reasoning are unescaped unless
/// [unescapeReasoning] is false. Without [extractsThought], all of [input] is
/// content and tool calls. With [verbatimForcedThought], a forced-open
/// thought is the text before the first [endThink] or tool-call scope, kept as
/// generated, and the rest is content.
///
/// With [endsAtLastCall], for a [XmlToolCallFormat.repeatsScope] format, the
/// reply ends at its last tool call, as in llama.cpp's Qwen3-Coder parser: the
/// content is the text before the first scope, the calls are those of the
/// consecutive scopes after it that each hold one valid call, up to
/// [maxToolCalls], and the rest is dropped.
///
/// Without [schemas], the arguments that [stringArguments] lists for a tool
/// keep their text as generated instead of being read as JSON.
ChatParseResult parseXmlToolCalls(
  String input,
  XmlToolCallFormat format, {
  String startThink = '<think>',
  String endThink = '</think>',
  bool isPartial = false,
  bool parseToolCalls = true,
  bool thinkingForcedOpen = false,
  bool unescapeReasoning = true,
  bool extractsThought = true,
  bool verbatimForcedThought = false,
  bool endsAtLastCall = false,
  int? maxToolCalls,
  Map<String, Map<String, dynamic>>? schemas,
  Map<String, Set<String>>? stringArguments,
}) {
  String? reasoning;
  var content = input;

  // Qwen3.6 can emit a tool call directly after a thinking tag that was
  // already opened in the prompt. Split that leading thinking text before
  // parsing the tool scope instead of classifying the whole tool call as
  // reasoning when no closing tag was generated.
  final forcedOpenToolScopeIndex =
      parseToolCalls &&
          format.allowToolcallInThink &&
          thinkingForcedOpen &&
          !content.contains(startThink) &&
          !content.contains(endThink)
      ? (format.scopeStart.isEmpty
            ? content.indexOf(format.toolStart)
            : content.indexOf(format.scopeStart))
      : -1;
  if (extractsThought && verbatimForcedThought && thinkingForcedOpen) {
    final thought = extractForcedOpenThoughtVerbatim(
      content,
      endTag: endThink,
      contentOpenings: [
        format.scopeStart.isEmpty ? format.toolStart : format.scopeStart,
      ],
      isPartial: isPartial,
    );
    reasoning = thought.reasoning;
    content = thought.content;
  } else if (extractsThought && forcedOpenToolScopeIndex >= 0) {
    final leadingReasoning = content
        .substring(0, forcedOpenToolScopeIndex)
        .trim();
    reasoning = leadingReasoning.isEmpty ? null : leadingReasoning;
    content = content.substring(forcedOpenToolScopeIndex);
  } else if (extractsThought) {
    // Extract thinking/reasoning first.
    // Keep an incomplete trailing XML tool-scope prefix out of streamed
    // reasoning. A tokenizer may split `<tool_call>` over multiple pieces;
    // treating the prefix as reasoning would leak tool markup before the
    // complete scope can be parsed on the next chunk.
    final deferredScopePrefixLength =
        isPartial && format.allowToolcallInThink && thinkingForcedOpen
        ? _trailingPrefixLength(content, format.scopeStart)
        : 0;
    final thinkingInput = deferredScopePrefixLength == 0
        ? content
        : content.substring(0, content.length - deferredScopePrefixLength);
    final thinkResult = extractThinking(
      thinkingInput,
      startTag: startThink,
      endTag: endThink,
      thinkingForcedOpen: thinkingForcedOpen,
      unescape: unescapeReasoning,
    );
    reasoning = thinkResult.reasoning;
    content = thinkResult.content;
  }

  if (!parseToolCalls) {
    return ChatParseResult(
      content: content.trim(),
      reasoningContent: reasoning,
    );
  }
  if (endsAtLastCall) {
    return _parseCallsEndingReply(
      content,
      format,
      reasoning: reasoning,
      schemas: schemas,
      maxToolCalls: maxToolCalls,
      isPartial: isPartial,
    );
  }

  final toolCalls = <LlamaCompletionChunkToolCall>[];
  final parsedContent = StringBuffer();
  var remainingContent = format.scopeStart.isEmpty ? '' : content;
  final originalContent = content;
  var parseFailed = false;

  // Find scope start
  final scopeIdx = format.scopeStart.isEmpty
      ? 0
      : content.indexOf(format.scopeStart);

  if (scopeIdx == -1) {
    return ChatParseResult(
      content: content.trim(),
      reasoningContent: reasoning,
    );
  }

  if (format.scopeStart.isNotEmpty) {
    remainingContent = content.substring(0, scopeIdx);
    content = content.substring(scopeIdx + format.scopeStart.length);
  }

  // Parse individual tool calls
  var callIndex = 0;
  var pos = 0;
  // The end of the scope closed before the latest repeated one, and the calls
  // parsed before that one opened.
  ({int scopeEnd, int calls})? repeatedScope;

  while (pos < content.length) {
    final _ParsedXmlToolCall? toolCall;
    // A call's end position already skips the whitespace after it.
    if (format.repeatsScope &&
        callIndex > 0 &&
        content.startsWith(format.scopeEnd, pos)) {
      // Only another whitespace-separated scope holding a valid call
      // continues the calls; anything else after the closed scope is
      // trailing content.
      final toolIdx = _nextScopeToolStart(content, pos, format);
      final nextCall = toolIdx == null
          ? null
          : _parseXmlToolCall(
              content,
              toolIdx,
              format,
              schemas,
              stringArguments,
            );
      if (nextCall == null) break;
      repeatedScope = (scopeEnd: pos, calls: toolCalls.length);
      toolCall = nextCall;
    } else {
      final toolIdx = content.indexOf(format.toolStart, pos);
      if (toolIdx == -1) {
        if (format.scopeStart.isNotEmpty) {
          final remaining = content.substring(pos).trimLeft();
          if (remaining.isNotEmpty &&
              !_startsWithScopeTail(remaining, format)) {
            parseFailed = true;
          }
        } else if (pos < content.length) {
          parsedContent.write(content.substring(pos));
        }
        break;
      }
      if (format.scopeStart.isNotEmpty &&
          content.substring(pos, toolIdx).trim().isNotEmpty) {
        parseFailed = true;
        break;
      }
      if (format.scopeStart.isEmpty && toolIdx > pos) {
        parsedContent.write(content.substring(pos, toolIdx));
      }

      toolCall = _parseXmlToolCall(
        content,
        toolIdx,
        format,
        schemas,
        stringArguments,
      );
      if (toolCall == null) {
        if (format.scopeStart.isNotEmpty) {
          parseFailed = true;
        } else {
          parsedContent.write(content.substring(toolIdx));
        }
        break;
      }
    }
    pos = toolCall.nextPos;

    toolCalls.add(
      ToolCallParsingUtils.createFunctionToolCall(
        index: callIndex,
        name: toolCall.name,
        arguments: toolCall.arguments,
      ),
    );
    callIndex++;
  }

  // Find scope end and append any trailing content
  if (format.scopeStart.isEmpty) {
    remainingContent = parsedContent.toString();
  } else if (format.scopeEnd.isNotEmpty) {
    var scopeEndIdx = parseFailed ? -1 : content.indexOf(format.scopeEnd, pos);
    // A malformed or unclosed repeated scope stays content, after the calls
    // of the scopes before it.
    if (scopeEndIdx == -1 && repeatedScope != null) {
      toolCalls.removeRange(repeatedScope.calls, toolCalls.length);
      scopeEndIdx = repeatedScope.scopeEnd;
      parseFailed = false;
    }
    if (scopeEndIdx != -1) {
      final trailing = content.substring(scopeEndIdx + format.scopeEnd.length);
      if (trailing.trim().isNotEmpty) {
        remainingContent += trailing;
      }
    } else {
      parseFailed = true;
    }
  }

  if (parseFailed) {
    return ChatParseResult(
      content: originalContent.trim(),
      reasoningContent: reasoning,
    );
  }

  return ChatParseResult(
    content: remainingContent.trim(),
    reasoningContent: reasoning,
    toolCalls: toolCalls,
  );
}

/// Parses the scopes that end [content] for [parseXmlToolCalls] with
/// `endsAtLastCall`.
///
/// Each scope holds one call framed by line breaks as in llama.cpp's
/// Qwen3-Coder parser: `<tool_call>\n<function=NAME>\n`, then each argument
/// as `<parameter=KEY>\n` and its value up to the first
/// `\n</parameter>\n`, then `</function>\n</tool_call>`. A finished reply
/// may end a valid call without its scope end, or with only the start of one,
/// and the call counts, as llama.cpp takes it at the end of the input. A
/// partial reply holds back the start of a scope it may still complete.
ChatParseResult _parseCallsEndingReply(
  String content,
  XmlToolCallFormat format, {
  required String? reasoning,
  required Map<String, Map<String, dynamic>>? schemas,
  required int? maxToolCalls,
  required bool isPartial,
}) {
  final scopeIdx = content.indexOf(format.scopeStart);
  if (scopeIdx == -1) {
    final held = isPartial
        ? _trailingPrefixLength(content, format.scopeStart)
        : 0;
    return ChatParseResult(
      content: content.substring(0, content.length - held).trim(),
      reasoningContent: reasoning,
    );
  }
  final toolCalls = <LlamaCompletionChunkToolCall>[];
  var pos = scopeIdx;
  while ((maxToolCalls == null || toolCalls.length < maxToolCalls) &&
      content.startsWith('${format.scopeStart}\n', pos)) {
    final call = _parseLineFramedCall(
      content,
      pos + format.scopeStart.length + 1,
      schemas,
    );
    if (call == null) break;
    final closed = content.startsWith(format.scopeEnd, call.nextPos);
    if (!closed &&
        (isPartial ||
            !format.scopeEnd.startsWith(content.substring(call.nextPos)))) {
      break;
    }
    toolCalls.add(
      ToolCallParsingUtils.createFunctionToolCall(
        index: toolCalls.length,
        name: call.name,
        arguments: call.arguments,
      ),
    );
    if (!closed) break;
    pos = _consumeXmlWhitespace(content, call.nextPos + format.scopeEnd.length);
  }
  return ChatParseResult(
    content: content.substring(0, scopeIdx).trim(),
    reasoningContent: reasoning,
    toolCalls: toolCalls,
  );
}

/// llama.cpp takes the required arguments of a call in any order only up to
/// this many, and in declaration order beyond it.
const _maxPermutedRequiredArguments = 6;

/// Parses the Qwen3-Coder call that opens at [start] with `<function=`.
///
/// With [schemas], as llama.cpp's grammar-derived parser does, the call names
/// a declared tool, its required arguments come first, each once, and its
/// optional ones follow, in any order and possibly repeated, the last value
/// winning. A string value is kept as generated; any other value is JSON with
/// nothing around it, or a string the schema allows.
_ParsedXmlToolCall? _parseLineFramedCall(
  String content,
  int start,
  Map<String, Map<String, dynamic>>? schemas,
) {
  const functionOpen = '<function=';
  const functionClose = '</function>';
  if (!content.startsWith(functionOpen, start)) return null;
  final nameStart = start + functionOpen.length;
  final nameEnd = content.indexOf('>\n', nameStart);
  if (nameEnd == -1) return null;
  final name = content.substring(nameStart, nameEnd);
  final schema = schemas?[name];
  if (name.isEmpty ||
      name.contains('\n') ||
      (schemas != null && schema == null)) {
    return null;
  }
  final properties = schema == null ? null : schemaProperties(schema);
  final requiredNames = schema == null
      ? const <String>{}
      : schemaRequired(schema);
  final requiredOrder = [
    for (final key in properties?.keys ?? const <String>[])
      if (requiredNames.contains(key)) key,
  ];
  final args = <String, dynamic>{};
  var pos = nameEnd + 2;
  var requiredSeen = 0;
  while (true) {
    final argument = _parseLineFramedArgument(content, pos, properties);
    final key = argument?.key;
    if (requiredSeen < requiredOrder.length) {
      final expected = requiredOrder.length > _maxPermutedRequiredArguments
          ? {requiredOrder[requiredSeen]}
          : requiredOrder.where((name) => !args.containsKey(name)).toSet();
      if (argument == null || !expected.contains(key)) return null;
      requiredSeen++;
    } else if (argument == null ||
        (properties != null && requiredNames.contains(key))) {
      break;
    }
    args[key!] = argument.value;
    pos = argument.nextPos;
  }
  if (!content.startsWith(functionClose, pos)) return null;
  pos += functionClose.length;
  if (pos < content.length) {
    if (content.codeUnitAt(pos) != 0x0A) return null;
    pos++;
  }
  return _ParsedXmlToolCall(name: name, arguments: args, nextPos: pos);
}

/// Parses the argument that opens at [start] with `<parameter=`, or returns
/// null when there is none or its value is invalid for [properties].
({String key, Object? value, int nextPos})? _parseLineFramedArgument(
  String content,
  int start,
  Map<String, Map<String, dynamic>>? properties,
) {
  const parameterOpen = '<parameter=';
  const valueEnd = '\n</parameter>\n';
  if (!content.startsWith(parameterOpen, start)) return null;
  final keyStart = start + parameterOpen.length;
  final keyEnd = content.indexOf('>\n', keyStart);
  if (keyEnd == -1) return null;
  final key = content.substring(keyStart, keyEnd);
  final schema = properties?[key];
  if (key.isEmpty ||
      key.contains('\n') ||
      (properties != null && schema == null)) {
    return null;
  }
  final valueStart = keyEnd + 2;
  final valueEndIdx = content.indexOf(valueEnd, valueStart);
  if (valueEndIdx == -1) return null;
  final raw = content.substring(valueStart, valueEndIdx);
  final Object? value;
  if (schema == null) {
    value = ToolCallParsingUtils.decodeJsonValueOrString(raw);
  } else {
    final decoded = _decodeLineFramedValue(raw, schema);
    if (!decoded.valid) return null;
    value = decoded.value;
  }
  return (key: key, value: value, nextPos: valueEndIdx + valueEnd.length);
}

/// Decodes the raw value [raw] of an argument with [schema].
///
/// As llama.cpp does, a value that may be a string is JSON only when it is a
/// JSON value other than a string, and otherwise the text as generated.
ToolSchemaValueResult _decodeLineFramedValue(
  String raw,
  Map<String, dynamic> schema,
) {
  if (schemaResolvesToString(schema)) {
    return validateToolSchemaValue(raw, schema);
  }
  // llama.cpp's JSON value has no whitespace around it.
  if (raw.isNotEmpty && raw.trim() == raw) {
    final decoded = raw == 'null'
        ? (value: null)
        : switch (ToolCallParsingUtils.decodeJsonValue(raw)) {
            null => null,
            final Object value => (value: value),
          };
    if (decoded != null && decoded.value is! String) {
      final result = validateToolSchemaValue(decoded.value, schema);
      if (result.valid) return result;
    }
  }
  return validateToolSchemaValue(raw, schema);
}

/// Returns where the tool call of a scope that follows the scope end at
/// [scopeEnd] in [text] starts, when only whitespace separates them.
int? _nextScopeToolStart(String text, int scopeEnd, XmlToolCallFormat format) {
  final scopeStart = _consumeXmlWhitespace(
    text,
    scopeEnd + format.scopeEnd.length,
  );
  if (!text.startsWith(format.scopeStart, scopeStart)) return null;
  final toolStart = _consumeXmlWhitespace(
    text,
    scopeStart + format.scopeStart.length,
  );
  return text.startsWith(format.toolStart, toolStart) ? toolStart : null;
}

int _trailingPrefixLength(String value, String prefix) {
  if (prefix.isEmpty) {
    return 0;
  }

  final maxLength = value.length < prefix.length
      ? value.length
      : prefix.length - 1;
  for (var length = maxLength; length > 0; length--) {
    if (value.endsWith(prefix.substring(0, length))) {
      return length;
    }
  }
  return 0;
}

_ParsedXmlToolCall? _parseXmlToolCall(
  String content,
  int toolIdx,
  XmlToolCallFormat format,
  Map<String, Map<String, dynamic>>? schemas, [
  Map<String, Set<String>>? stringArguments,
]) {
  final nameStart = toolIdx + format.toolStart.length;
  final sepIdx = content.indexOf(format.toolSep, nameStart);
  if (sepIdx == -1) {
    return null;
  }

  final name = content.substring(nameStart, sepIdx).trim();
  if (name.isEmpty || (schemas != null && !schemas.containsKey(name))) {
    return null;
  }

  final arguments = _parseXmlArguments(
    content,
    sepIdx + format.toolSep.length,
    format,
    schemas?[name],
    stringArguments?[name] ?? const {},
  );
  if (arguments == null) {
    return null;
  }

  return _ParsedXmlToolCall(
    name: name,
    arguments: arguments.arguments,
    nextPos: arguments.nextPos,
  );
}

_ParsedXmlArguments? _parseXmlArguments(
  String content,
  int start,
  XmlToolCallFormat format,
  Map<String, dynamic>? schema,
  Set<String> stringArguments,
) {
  final properties = schema == null ? null : schemaProperties(schema);
  final strictScope = format.scopeStart.isNotEmpty;
  final args = <String, dynamic>{};
  var pos = start;
  var consumedToolEnd = false;

  while (pos < content.length) {
    pos = _consumeXmlWhitespace(content, pos);

    final toolEndLen = _matchToolEnd(content, pos, format);
    if (toolEndLen != null) {
      pos += toolEndLen;
      consumedToolEnd = true;
      break;
    }

    final keyIdx = content.indexOf(format.keyStart, pos);
    if (keyIdx == -1) {
      if (strictScope && _matchToolEnd(content, pos, format) == null) {
        return null;
      }
      break;
    }
    if (strictScope && content.substring(pos, keyIdx).trim().isNotEmpty) {
      return null;
    }

    final keyNameStart = keyIdx + format.keyStart.length;
    final keyNameEnd = content.indexOf(format.keyValSep, keyNameStart);
    if (keyNameEnd == -1) {
      return null;
    }

    final key = content.substring(keyNameStart, keyNameEnd).trim();
    if (key.isEmpty ||
        (properties != null &&
            (!properties.containsKey(key) || args.containsKey(key)))) {
      return null;
    }
    pos = keyNameEnd + format.keyValSep.length;

    final argumentValue = _parseXmlArgumentValue(
      content,
      pos,
      format,
      schema: properties?[key],
      keepsText: stringArguments.contains(key),
    );
    if (argumentValue == null) {
      return null;
    }
    args[key] = argumentValue.value;
    pos = argumentValue.nextPos;
  }

  pos = _consumeXmlWhitespace(content, pos);
  if (!consumedToolEnd) {
    final toolEndLen = _matchToolEnd(content, pos, format);
    if (toolEndLen != null) {
      pos += toolEndLen;
    } else if (strictScope) {
      return null;
    }
  }

  if (schema != null && !validateToolSchemaValue(args, schema).valid) {
    return null;
  }
  return _ParsedXmlArguments(arguments: args, nextPos: pos);
}

_ParsedCdataValue? _parseCdataValue(
  String content,
  int start,
  XmlToolCallFormat format,
) {
  const cdataStart = '<![CDATA[';
  const cdataEnd = ']]>';
  if (!content.startsWith(cdataStart, start)) {
    return null;
  }

  final cdataEndIdx = content.indexOf(cdataEnd, start + cdataStart.length);
  if (cdataEndIdx == -1) {
    return null;
  }

  final valueEnd = _consumeValueEnd(
    content,
    cdataEndIdx + cdataEnd.length,
    format,
  );
  if (valueEnd == null) {
    return null;
  }

  return _ParsedCdataValue(
    value: content.substring(start + cdataStart.length, cdataEndIdx),
    nextPos: valueEnd,
  );
}

int? _matchToolEnd(String text, int at, XmlToolCallFormat format) {
  if (format.toolEnd.isNotEmpty && text.startsWith(format.toolEnd, at)) {
    return format.toolEnd.length;
  }
  if (format.lastToolEnd != null &&
      format.lastToolEnd!.isNotEmpty &&
      text.startsWith(format.lastToolEnd!, at)) {
    return format.lastToolEnd!.length;
  }
  return null;
}

int _findNextToolEndIndex(String text, int from, XmlToolCallFormat format) {
  final toolEndIdx = format.toolEnd.isEmpty
      ? -1
      : text.indexOf(format.toolEnd, from);
  final lastToolEndIdx =
      (format.lastToolEnd != null && format.lastToolEnd!.isNotEmpty)
      ? text.indexOf(format.lastToolEnd!, from)
      : -1;
  if (toolEndIdx == -1) {
    return lastToolEndIdx;
  }
  if (lastToolEndIdx == -1) {
    return toolEndIdx;
  }
  return toolEndIdx < lastToolEndIdx ? toolEndIdx : lastToolEndIdx;
}

bool _startsWithScopeTail(String text, XmlToolCallFormat format) {
  if (format.scopeEnd.isEmpty) {
    return text.isEmpty;
  }
  if (text.startsWith(format.scopeEnd)) {
    return true;
  }
  if (format.lastToolEnd != null &&
      format.lastToolEnd!.isNotEmpty &&
      text.startsWith('${format.lastToolEnd}${format.scopeEnd}')) {
    return true;
  }
  if (format.toolEnd.isNotEmpty &&
      text.startsWith('${format.toolEnd}${format.scopeEnd}')) {
    return true;
  }
  return false;
}

int _consumeXmlWhitespace(String text, int from) {
  var pos = from;
  while (pos < text.length) {
    final codeUnit = text.codeUnitAt(pos);
    if (codeUnit > 0x20) {
      break;
    }
    pos++;
  }
  return pos;
}

_ParsedXmlArgumentValue? _parseXmlArgumentValue(
  String content,
  int start,
  XmlToolCallFormat format, {
  Map<String, dynamic>? schema,
  bool keepsText = false,
}) {
  if (schema != null) {
    final cdata = _parseCdataValue(content, start, format);
    final end = cdata == null ? _findValueEnd(content, start, format) : null;
    if (cdata == null && end == null) return null;
    var raw = cdata?.value ?? content.substring(start, end!.valueEnd);
    if (format.trimRawArgval) raw = raw.trim();
    final decoded = decodeToolSchemaText(raw, schema);
    if (!decoded.valid) return null;
    return _ParsedXmlArgumentValue(
      value: decoded.value,
      nextPos: cdata?.nextPos ?? end!.nextPos,
    );
  }

  if (format.rawArgval == false) {
    final valueStart = _consumeXmlWhitespace(content, start);
    final parsed = ToolCallParsingUtils.extractLeadingJsonValue(
      content,
      valueStart,
    );
    if (parsed == null) {
      return null;
    }
    final nextPos = _consumeValueEnd(content, parsed.end, format);
    if (nextPos == null) {
      return null;
    }
    return _ParsedXmlArgumentValue(value: parsed.value, nextPos: nextPos);
  }

  final cdataValue = _parseCdataValue(content, start, format);
  if (cdataValue != null) {
    return _ParsedXmlArgumentValue(
      value: cdataValue.value,
      nextPos: cdataValue.nextPos,
    );
  }

  final valueEnd = _findValueEnd(content, start, format);
  if (valueEnd == null) {
    return null;
  }

  var value = content.substring(start, valueEnd.valueEnd);
  if (format.trimRawArgval) {
    value = value.trim();
  }
  return _ParsedXmlArgumentValue(
    value: format.rawArgval == true || keepsText
        ? value
        : ToolCallParsingUtils.decodeJsonValueOrString(value),
    nextPos: valueEnd.nextPos,
  );
}

int? _consumeValueEnd(String content, int start, XmlToolCallFormat format) {
  final markerStart = _consumeXmlWhitespace(content, start);
  if (format.valEnd.isNotEmpty &&
      content.startsWith(format.valEnd, markerStart)) {
    return markerStart + format.valEnd.length;
  }

  final lastValEnd = format.lastValEnd;
  if (lastValEnd == null ||
      (lastValEnd.isNotEmpty && !content.startsWith(lastValEnd, markerStart))) {
    return null;
  }
  final afterMarker = markerStart + lastValEnd.length;
  final toolEndStart = _consumeXmlWhitespace(content, afterMarker);
  return _matchToolEnd(content, toolEndStart, format) == null
      ? null
      : afterMarker;
}

_ValueEndMatch? _findValueEnd(
  String content,
  int start,
  XmlToolCallFormat format,
) {
  _ValueEndMatch? best;
  if (format.valEnd.isNotEmpty) {
    final index = content.indexOf(format.valEnd, start);
    if (index != -1) {
      best = _ValueEndMatch(
        valueEnd: index,
        nextPos: index + format.valEnd.length,
      );
    }
  }

  final lastValEnd = format.lastValEnd;
  if (lastValEnd != null) {
    if (lastValEnd.isEmpty) {
      final toolEndIndex = _findNextToolEndIndex(content, start, format);
      if (toolEndIndex != -1 &&
          (best == null || toolEndIndex < best.valueEnd)) {
        best = _ValueEndMatch(valueEnd: toolEndIndex, nextPos: toolEndIndex);
      }
    } else {
      var searchFrom = start;
      while (searchFrom <= content.length - lastValEnd.length) {
        final index = content.indexOf(lastValEnd, searchFrom);
        if (index == -1) {
          break;
        }
        final afterMarker = index + lastValEnd.length;
        final toolEndStart = _consumeXmlWhitespace(content, afterMarker);
        if (_matchToolEnd(content, toolEndStart, format) != null) {
          if (best == null || index < best.valueEnd) {
            best = _ValueEndMatch(valueEnd: index, nextPos: afterMarker);
          }
          break;
        }
        searchFrom = index + lastValEnd.length;
      }
    }
  }
  return best;
}

final class _ParsedCdataValue {
  final String value;
  final int nextPos;

  const _ParsedCdataValue({required this.value, required this.nextPos});
}

final class _ParsedXmlToolCall {
  final String name;
  final Map<String, dynamic> arguments;
  final int nextPos;

  const _ParsedXmlToolCall({
    required this.name,
    required this.arguments,
    required this.nextPos,
  });
}

final class _ParsedXmlArguments {
  final Map<String, dynamic> arguments;
  final int nextPos;

  const _ParsedXmlArguments({required this.arguments, required this.nextPos});
}

final class _ParsedXmlArgumentValue {
  final Object? value;
  final int nextPos;

  const _ParsedXmlArgumentValue({required this.value, required this.nextPos});
}

final class _ValueEndMatch {
  final int valueEnd;
  final int nextPos;

  const _ValueEndMatch({required this.valueEnd, required this.nextPos});
}
