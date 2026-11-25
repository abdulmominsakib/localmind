import 'dart:convert';

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

/// Handler for Hermes 2 Pro / Qwen 2.5 / Qwen 3 format.
///
/// Uses `<tool_call>` / `</tool_call>` XML tags with JSON payloads.
/// Tool call format: `<tool_call>{"name": "fn", "arguments": {...}}</tool_call>`
///
/// A tagged payload may add one outer `{`:
/// `<tool_call>{{"name": "fn", "arguments": {...}}}</tool_call>`. The
/// Qwen2.5-0.5B-Instruct GGUF template prints this form in its tool prompt, and
/// the model copies it when no grammar constrains it. The call is extracted.
/// When only closing braces and whitespace sit between the call and its close
/// tag, and a fenced envelope also closes its fence, the envelope leaves no
/// content, as for the single-brace form. Otherwise the envelope text stays in
/// content and parsing continues after the call. This differs from upstream:
/// llama.cpp `7fe450e1` fails to parse this output and extracts no call.
class HermesHandler extends ChatTemplateHandler
    implements ToolSchemaAwareChatTemplateHandler {
  static const List<String> _openTags = <String>[
    '<tool_call>',
    '<function_call>',
    '<tool>',
    '<tools>',
    '<response>',
    '<json>',
    '<xml>',
    '<JSON>',
  ];

  static final RegExp _openRegex = RegExp(
    '(?:(```(?:xml|json)?\\n\\s*)?(?:(${_openTags.join('|')})(\\s*\\{)?)?'
    r'(\s*\{\s*"name"))|<function=([^>]+)>|<function name="([^"]+)">',
    dotAll: true,
  );

  /// The forms [_openRegex] matches, as parts matched left to right.
  static final List<List<_OpeningPart>> _openingForms = [
    for (final fence in <String>['', '```\n', '```xml\n', '```json\n'])
      for (final tag in <String>['', ..._openTags])
        for (final outerBrace in tag.isEmpty ? [false] : [false, true])
          [
            if (fence.isNotEmpty) ...[_OpeningLiteral(fence), _openingSpaces],
            if (tag.isNotEmpty) _OpeningLiteral(tag),
            if (outerBrace) ...[_openingSpaces, const _OpeningLiteral('{')],
            _openingSpaces,
            const _OpeningLiteral('{'),
            _openingSpaces,
            const _OpeningLiteral('"name"'),
          ],
    const [
      _OpeningLiteral('<function='),
      _OpeningRun('>'),
      _OpeningLiteral('>'),
    ],
    const [
      _OpeningLiteral('<function name="'),
      _OpeningRun('"'),
      _OpeningLiteral('">'),
    ],
  ];

  static final RegExp _regexSpace = RegExp(r'\s');

  // A raw newline cannot occur inside a JSON string. Let a closing tag after
  // one remain visible when malformed JSON leaves a quote unterminated.
  static final RegExp _toolCallCloseOrString = RegExp(
    r'"(?:\\.|[^"\\\r\n])*(?:"|\\?$)|</tool_call>',
    dotAll: true,
  );

  /// Whether final text contains a tool-call envelope opening, excluding
  /// prefixes held back only while tokens are still arriving.
  ///
  /// Bare or fenced `{"name"` JSON and generic answer tags such as `<json>`
  /// are answer text unless they parse as a call to a declared tool.
  static bool hasCompleteToolCallOpening(String text) =>
      text.contains('<tool_call>') ||
      text.contains('<function_call>') ||
      _openRegex
          .allMatches(text)
          .any(
            (match) =>
                _isToolEnvelopeTag(match.group(2) ?? '') ||
                match.group(5) != null ||
                match.group(6) != null,
          );

  static bool _isToolEnvelopeTag(String tag) =>
      tag.startsWith('<tool') || tag.startsWith('<function');

  /// Finds where [parse] may find a tool-call opening in [text].
  ///
  /// Returns the first index at or after [from] where an opening starts, or
  /// where the rest of [text] is the start of one, and `text.length` when
  /// there is none.
  static int toolCallOpening(String text, [int from = 0]) {
    for (var index = from; index < text.length; index++) {
      if (_openingForms.any((form) => _mayMatchOpening(text, index, form))) {
        return index;
      }
    }
    return text.length;
  }

  /// Whether [form] matches [text] at [start], or matches all of the rest.
  static bool _mayMatchOpening(
    String text,
    int start,
    List<_OpeningPart> form,
  ) {
    var index = start;
    for (final part in form) {
      switch (part) {
        case _OpeningLiteral(:final literal):
          for (var offset = 0; offset < literal.length; offset++) {
            if (index + offset == text.length) return true;
            if (text.codeUnitAt(index + offset) != literal.codeUnitAt(offset)) {
              return false;
            }
          }
          index += literal.length;
        case _OpeningSpaces():
          while (index < text.length && _regexSpace.hasMatch(text[index])) {
            index++;
          }
        case _OpeningRun(:final stop):
          if (index == text.length) return true;
          if (text[index] == stop) return false;
          while (index < text.length && text[index] != stop) {
            index++;
          }
      }
    }
    return true;
  }

  @override
  ChatFormat get format => ChatFormat.hermes;

  @override
  List<String> get additionalStops => ['<|im_end|>'];

  @override
  List<String> get preservedTokens => const ['<tool_call>', '</tool_call>'];

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
        'enable_thinking': enableThinking,
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
      },
    );

    // Handle enableThinking post-render logic
    final thinkingForcedClosed = isThinkingForcedClosed(prompt);
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
    final rendered = LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: requiredGrammarAfterThought(
        buildGrammar(tools),
        metadata: metadata,
        thinkingForcedOpen: thinkingForcedOpen,
      ),
      grammarLazy: hasTools,
      thinkingForcedOpen: thinkingForcedOpen,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      preservedTokens: hasTools ? preservedTokens : [],
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: '<tool_call>')]
          : [],
    );
    return withThoughtClosedForThinkingOff(
      withThinkingForcedClosed(rendered, closed: thinkingForcedClosed),
      closed: thoughtClosed,
    );
  }

  /// On [cancelled], withholds unfinished tool envelopes from answer text.
  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool cancelled = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) => _parse(
    output,
    isPartial: isPartial,
    cancelled: cancelled,
    parseToolCalls: parseToolCalls,
    thinkingForcedOpen: thinkingForcedOpen,
  );

  /// Parses like [parse]; with canonical schema tools, an untagged or
  /// generically tagged `{"name"` object is a call only when it is complete
  /// and names a declared tool. Otherwise it stays answer content.
  /// With [thoughtTagsAreText], all of [output] is content and tool calls.
  @override
  ChatParseResult parseWithTools(
    String output, {
    List<ToolDefinition>? tools,
    bool isPartial = false,
    bool cancelled = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
    bool thoughtTagsAreText = false,
  }) => _parse(
    output,
    isPartial: isPartial,
    cancelled: cancelled,
    parseToolCalls: parseToolCalls,
    thinkingForcedOpen: thinkingForcedOpen,
    thoughtTagsAreText: thoughtTagsAreText,
    declaredNames: tools != null && tools.any(toolUsesJsonSchema)
        ? {for (final tool in tools) tool.name}
        : null,
  );

  ChatParseResult _parse(
    String output, {
    required bool isPartial,
    required bool cancelled,
    required bool parseToolCalls,
    required bool thinkingForcedOpen,
    bool thoughtTagsAreText = false,
    Set<String>? declaredNames,
  }) {
    // As in llama.cpp (`620d2225`), a forced-open thought is the text before
    // the first `</think>`, kept as generated, and the rest is content.
    final ThinkingExtraction thinking = thoughtTagsAreText
        ? (content: output.trim(), reasoning: null)
        : thinkingForcedOpen
        ? extractForcedOpenThoughtVerbatim(output, isPartial: isPartial)
        : extractThinking(output);
    final text = thinking.content;

    if (!parseToolCalls) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    if (isPartial) {
      final visiblePrefix = _contentBeforePendingToolEnvelope(text);
      if (visiblePrefix != null) {
        return ChatParseResult(
          content: visiblePrefix.trim(),
          reasoningContent: thinking.reasoning,
        );
      }
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    final content = StringBuffer();
    var cursor = 0;
    var parseFailed = false;

    // Schema-backed final parses retain malformed output for engine validation.
    while (true) {
      final match = _firstMatchFrom(text, cursor);
      if (match == null) {
        final pendingStart = text.indexOf('<tool_call>', cursor);
        final pendingPayload = pendingStart < 0
            ? ''
            : text.substring(pendingStart + '<tool_call>'.length).trimLeft();
        if (cancelled &&
            (isPartial || declaredNames == null) &&
            pendingStart >= 0 &&
            (pendingPayload.isEmpty || pendingPayload.startsWith('{')) &&
            !text.contains('</tool_call>', pendingStart)) {
          content.write(text.substring(cursor, pendingStart));
          cursor = text.length;
        }
        break;
      }
      if (match.start > cursor) {
        content.write(text.substring(cursor, match.start));
      }

      final blockStart = match.group(1) ?? '';
      final openTag = match.group(2) ?? '';
      final hasOuterBrace = match.group(3) != null;
      final namedToolStart = match.group(4);
      var functionName = match.group(5) ?? '';
      functionName = functionName.isEmpty
          ? (match.group(6) ?? '')
          : functionName;

      if (namedToolStart != null) {
        final matchText = match.group(0)!;
        final startOffset = matchText.lastIndexOf(namedToolStart);
        if (startOffset < 0) {
          parseFailed = true;
          break;
        }
        // Skip leading whitespace in namedToolStart to find the actual '{'
        var jsonStart = match.start + startOffset;
        while (jsonStart < text.length &&
            _isWhitespace(text.codeUnitAt(jsonStart))) {
          jsonStart++;
        }
        final jsonRange = _extractJsonObjectRange(text, jsonStart);
        // On cancellation, an unfinished envelope is control output. Search
        // after a complete JSON value so quoted closing tags cannot close it.
        // Keep the legacy recovery of double-brace payloads.
        if (cancelled &&
            (isPartial || declaredNames == null) &&
            openTag == '<tool_call>' &&
            !hasOuterBrace &&
            !_toolCallCloseOrString
                .allMatches(text, jsonRange?.end ?? jsonStart)
                .any((match) => match[0] == '</tool_call>')) {
          cursor = text.length;
          break;
        }
        final toolCall = jsonRange == null
            ? null
            : _toNamedToolCall(jsonRange.value, toolCalls.length);
        if (declaredNames != null &&
            !_isToolEnvelopeTag(openTag) &&
            (jsonRange != null || !isPartial) &&
            !declaredNames.contains(toolCall?.function?.name)) {
          final end = jsonRange?.end ?? match.end;
          content.write(text.substring(match.start, end));
          cursor = end;
          continue;
        }
        if (jsonRange == null) {
          parseFailed = true;
          break;
        }
        if (toolCall == null) {
          parseFailed = true;
          break;
        }
        toolCalls.add(toolCall);
        cursor = _consumeWhitespaces(text, jsonRange.end);
        if (hasOuterBrace) {
          final envelopeEnd = _outerBraceEnvelopeEnd(
            text,
            cursor,
            openTag: openTag,
            blockStart: blockStart,
          );
          if (envelopeEnd == null) {
            content.write(text.substring(match.start, jsonStart));
          } else {
            cursor = envelopeEnd;
          }
          continue;
        }

        if (openTag.isNotEmpty) {
          final closeTag = '</${openTag.substring(1)}';
          if (!text.startsWith(closeTag, cursor)) {
            parseFailed = true;
            break;
          }
          cursor = _consumeWhitespaces(text, cursor + closeTag.length);
        }
        if (blockStart.isNotEmpty) {
          if (!text.startsWith('```', cursor)) {
            parseFailed = true;
            break;
          }
          cursor = _consumeWhitespaces(text, cursor + 3);
        }
        continue;
      }

      if (functionName.isEmpty) {
        cursor = match.end;
        continue;
      }

      final jsonRange = _extractJsonObjectRange(text, match.end);
      if (jsonRange == null) {
        parseFailed = true;
        break;
      }
      toolCalls.add(
        ToolCallParsingUtils.createFunctionToolCall(
          index: toolCalls.length,
          name: functionName,
          arguments: _normalizeArguments(
            text.substring(match.end, jsonRange.end),
          ),
        ),
      );

      cursor = _consumeWhitespaces(text, jsonRange.end);
      if (!text.startsWith('</function>', cursor)) {
        parseFailed = true;
        break;
      }
      cursor = _consumeWhitespaces(text, cursor + '</function>'.length);

      if (blockStart.isNotEmpty) {
        if (!text.startsWith('```', cursor)) {
          parseFailed = true;
          break;
        }
        cursor = _consumeWhitespaces(text, cursor + 3);
      }
    }

    if (parseFailed) {
      if (isPartial) {
        return ChatParseResult(
          content: content.toString().trim(),
          reasoningContent: thinking.reasoning,
          toolCalls: toolCalls,
        );
      }
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    if (cursor < text.length) {
      content.write(text.substring(cursor));
    }

    return ChatParseResult(
      content: content.toString().trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    if (tools == null || tools.isEmpty) return null;
    toolSchemas(tools);

    if (tools.any(toolUsesJsonSchema)) {
      final grammar = ToolCallGrammarUtils.buildWrappedObjectGrammar(
        tools: tools,
        prefix: '',
        suffix: '',
      )!;
      // Qwen-style output puts a newline after <tool_call>, as the legacy
      // grammar allows.
      return grammar
          .split('\n')
          .map((line) {
            if (!line.startsWith('root ::= ')) return line;
            final call = line.substring('root ::= '.length);
            return 'root ::= ("<tool_call>" space $call "</tool_call>" space)+';
          })
          .join('\n');
    }

    // Build a GBNF grammar that constrains output to valid Hermes tool calls
    final toolRules = <String>[];
    final toolChoices = <String>[];

    for (final tool in tools) {
      final ruleName = ToolCallGrammarUtils.ruleName(tool.name);
      toolChoices.add('$ruleName-call');

      final schema = tool.toJsonSchema();
      final argsRule = _jsonSchemaToGbnf(schema, '$ruleName-args');
      toolRules.add(argsRule);
      final prefix = ToolCallGrammarUtils.literal(
        '{"name": ${jsonEncode(tool.name)}, "arguments": ',
      );
      toolRules.add('$ruleName-call ::= $prefix $ruleName-args "}"');
    }

    final choiceRule = 'tool-choice ::= ${toolChoices.join(' | ')}';
    final root =
        'root ::= "<tool_call>" space tool-choice "</tool_call>" (space "<tool_call>" space tool-choice "</tool_call>")*';

    return [root, choiceRule, ...toolRules, _commonGbnfRules()].join('\n');
  }

  RegExpMatch? _firstMatchFrom(String text, int from) {
    final matches = _openRegex.allMatches(text, from);
    if (matches.isEmpty) {
      return null;
    }
    return matches.first;
  }

  String? _contentBeforePendingToolEnvelope(String text) {
    final lower = text.toLowerCase();
    const markers = <String>[
      '<tool_call',
      '<function_call',
      '<function=',
      '<function name=',
    ];

    var markerStart = -1;
    for (final marker in markers) {
      final index = lower.indexOf(marker);
      if (index >= 0 && (markerStart == -1 || index < markerStart)) {
        markerStart = index;
      }
    }
    if (markerStart < 0) {
      return null;
    }

    final afterMarker = text.substring(markerStart);
    final completeXmlToolCall = RegExp(
      r'<tool_call>[\s\S]*?</tool_call>',
      caseSensitive: false,
    ).hasMatch(afterMarker);
    final completeFunctionCall = RegExp(
      r'<function(?:=[^>]+| name="[^"]+")>[\s\S]*?</function>',
      caseSensitive: false,
    ).hasMatch(afterMarker);
    if (completeXmlToolCall || completeFunctionCall) {
      return null;
    }

    return text.substring(0, markerStart);
  }

  int? _outerBraceEnvelopeEnd(
    String text,
    int start, {
    required String openTag,
    required String blockStart,
  }) {
    var cursor = start;
    while (text.startsWith('}', cursor)) {
      cursor = _consumeWhitespaces(text, cursor + 1);
    }
    final closeTag = '</${openTag.substring(1)}';
    if (!text.startsWith(closeTag, cursor)) {
      return null;
    }
    cursor = _consumeWhitespaces(text, cursor + closeTag.length);
    if (blockStart.isNotEmpty) {
      if (!text.startsWith('```', cursor)) {
        return null;
      }
      cursor = _consumeWhitespaces(text, cursor + 3);
    }
    return cursor;
  }

  ParsedJsonValueSlice? _extractJsonObjectRange(String text, int start) {
    final jsonSlice = ToolCallParsingUtils.extractLeadingJsonValue(text, start);
    if (jsonSlice == null || jsonSlice.value is! Map) {
      return null;
    }
    return jsonSlice;
  }

  LlamaCompletionChunkToolCall? _toNamedToolCall(Object? jsonValue, int index) {
    final map = ToolCallParsingUtils.coerceMap(jsonValue);
    if (map == null) {
      return null;
    }
    final name = map['name'];
    if (name is! String || name.isEmpty) {
      return null;
    }

    final rawId = map['id'];
    final id = rawId is String && rawId.isNotEmpty ? rawId : 'call_$index';

    return ToolCallParsingUtils.createFunctionToolCall(
      index: index,
      name: name,
      id: id,
      arguments: map.containsKey('arguments') ? map['arguments'] : null,
    );
  }

  String _normalizeArguments(String jsonText) {
    return ToolCallParsingUtils.normalizeJsonArguments(jsonText);
  }

  int _consumeWhitespaces(String text, int start) {
    var pos = start;
    while (pos < text.length && _isWhitespace(text.codeUnitAt(pos))) {
      pos++;
    }
    return pos;
  }

  bool _isWhitespace(int codeUnit) =>
      codeUnit == 0x20 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D ||
      codeUnit == 0x09;

  String _jsonSchemaToGbnf(Map<String, dynamic> schema, String ruleName) {
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};

    if (properties.isEmpty) {
      return '$ruleName ::= "{" space "}"';
    }

    final parts = <String>[];
    var first = true;
    for (final entry in properties.entries) {
      final separator = first
          ? ''
          : '${ToolCallGrammarUtils.literal(', ')} space ';
      first = false;
      final propType = (entry.value as Map<String, dynamic>)['type'] as String?;
      final valueRule = _typeToGbnf(propType);
      final key = ToolCallGrammarUtils.literal('${jsonEncode(entry.key)}: ');
      parts.add('$separator$key space $valueRule');
    }

    return '$ruleName ::= "{" space ${parts.join(' ')} space "}"';
  }

  String _typeToGbnf(String? type) {
    switch (type) {
      case 'string':
        return 'string';
      case 'number':
      case 'integer':
        return 'number';
      case 'boolean':
        return 'boolean';
      case 'array':
        return 'arr';
      default:
        return 'value';
    }
  }

  String _commonGbnfRules() {
    return r'''
space ::= " "?
string ::= "\"" ([^"\\] | "\\\\" .)* "\""
number ::= "-"? ([0-9] | [1-9] [0-9]*) ("." [0-9]+)? ([eE] [-+]? [0-9]+)?
boolean ::= "true" | "false"
null ::= "null"
value ::= string | number | boolean | null | arr | obj
arr ::= "[" space (value ("," space value)*)? space "]"
obj ::= "{" space (string ":" space value ("," space string ":" space value)*)? space "}"''';
  }
}

sealed class _OpeningPart {
  const _OpeningPart();
}

/// Matches [literal].
final class _OpeningLiteral extends _OpeningPart {
  const _OpeningLiteral(this.literal);

  final String literal;
}

/// Matches `\s*`.
final class _OpeningSpaces extends _OpeningPart {
  const _OpeningSpaces();
}

const _openingSpaces = _OpeningSpaces();

/// Matches one or more characters other than [stop].
final class _OpeningRun extends _OpeningPart {
  const _OpeningRun(this.stop);

  final String stop;
}
