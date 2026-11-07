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

/// Handler for Hermes 2 Pro / Qwen 2.5 / Qwen 3 format.
///
/// Uses `<tool_call>` / `</tool_call>` XML tags with JSON payloads.
/// Tool call format: `<tool_call>{"name": "fn", "arguments": {...}}</tool_call>`
class HermesHandler extends ChatTemplateHandler {
  static final RegExp _openRegex = RegExp(
    r'(?:(```(?:xml|json)?\n\s*)?((?:<tool_call>|<function_call>|<tool>|<tools>|<response>|<json>|<xml>|<JSON>)?)(\s*\{\s*"name"))|<function=([^>]+)>|<function name="([^"]+)">',
    dotAll: true,
  );

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
        'messages': templateMessages(messages),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'enable_thinking': enableThinking,
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
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
      preservedTokens: hasTools ? preservedTokens : [],
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: '<tool_call>')]
          : [],
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

    while (true) {
      final match = _firstMatchFrom(text, cursor);
      if (match == null) {
        break;
      }
      if (match.start > cursor) {
        content.write(text.substring(cursor, match.start));
      }

      final blockStart = match.group(1) ?? '';
      final openTag = match.group(2) ?? '';
      final namedToolStart = match.group(3);
      var functionName = match.group(4) ?? '';
      functionName = functionName.isEmpty
          ? (match.group(5) ?? '')
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
        if (jsonRange == null) {
          parseFailed = true;
          break;
        }
        final toolCall = _toNamedToolCall(jsonRange.value, toolCalls.length);
        if (toolCall == null) {
          parseFailed = true;
          break;
        }
        toolCalls.add(toolCall);
        cursor = _consumeWhitespaces(text, jsonRange.end);

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

    // Build a GBNF grammar that constrains output to valid Hermes tool calls
    final toolRules = <String>[];
    final toolChoices = <String>[];

    for (final tool in tools) {
      final ruleName = _sanitizeName(tool.name);
      toolChoices.add('$ruleName-call');

      final schema = tool.toJsonSchema();
      final argsRule = _jsonSchemaToGbnf(schema, '$ruleName-args');
      toolRules.add(argsRule);
      toolRules.add(
        '$ruleName-call ::= "{\\"name\\": \\"${tool.name}\\", \\"arguments\\": " $ruleName-args "}"',
      );
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

  String _sanitizeName(String name) =>
      name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-').toLowerCase();

  String _jsonSchemaToGbnf(Map<String, dynamic> schema, String ruleName) {
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};

    if (properties.isEmpty) {
      return '$ruleName ::= "{" space "}"';
    }

    final parts = <String>[];
    var first = true;
    for (final entry in properties.entries) {
      final sep = first ? '' : '", " space ';
      first = false;
      final propType = (entry.value as Map<String, dynamic>)['type'] as String?;
      final valueRule = _typeToGbnf(propType);
      parts.add('$sep"\\"${entry.key}\\": " space $valueRule');
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
