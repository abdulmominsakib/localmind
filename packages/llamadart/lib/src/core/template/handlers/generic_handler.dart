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
import '../tool_call_parsing_utils.dart';

/// The built-in ChatML template used as fallback when the model has none.
const String _chatMlTemplate = '''
{%- for message in messages -%}
  {{- '<|im_start|>' + message.role + '\\n' + message.content + '<|im_end|>\\n' -}}
{%- endfor -%}
{%- if add_generation_prompt -%}
  {{- '<|im_start|>assistant\\n' -}}
{%- endif -%}
''';

/// Handler for generic ChatML-based models.
///
/// This is the universal fallback handler. Used when a model's template
/// contains `<|im_start|>` tokens but no format-specific tool call markers.
///
/// Tool calls follow llama.cpp generic JSON envelopes:
/// - `{"tool_call": {"name": ..., "arguments": ...}}`
/// - `{"response": "..."}`
class GenericHandler extends ChatTemplateHandler {
  /// Creates a generic ChatML-compatible handler.
  ///
  /// [format] and [toolCallSerialization] allow the engine to reuse generic
  /// rendering for content-only fallbacks without inheriting generic tool-call
  /// prompt serialization.
  GenericHandler({
    ChatFormat format = ChatFormat.generic,
    TemplateToolCallSerialization toolCallSerialization =
        TemplateToolCallSerialization.genericSchemaInContent,
  }) : _format = format,
       _toolCallSerialization = toolCallSerialization;

  final ChatFormat _format;
  final TemplateToolCallSerialization _toolCallSerialization;

  @override
  ChatFormat get format => _format;

  @override
  TemplateToolCallSerialization get toolCallSerialization =>
      _toolCallSerialization;

  @override
  List<String> get additionalStops => ['<|im_end|>'];

  @override
  LlamaChatTemplateResult render({
    required String templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    bool enableThinking = true,
  }) {
    // Use provided template if available, otherwise fall back to ChatML
    final effectiveTemplate = templateSource.isNotEmpty
        ? templateSource
        : _chatMlTemplate;

    final template = Template(effectiveTemplate);
    final prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': templateMessages(messages),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
      },
    );

    final stops = _inferStopsFromTemplate(effectiveTemplate);

    return LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: buildGrammar(tools),
      grammarLazy: false,
      additionalStops: stops,
      grammarTriggers: const [],
    );
  }

  List<String> _inferStopsFromTemplate(String templateSource) {
    final stops = <String>{};

    if (templateSource.contains('<end_of_turn>')) {
      stops.add('<end_of_turn>');
    }
    if (templateSource.contains('<|im_end|>')) {
      stops.add('<|im_end|>');
    }
    if (templateSource.contains('<|end|>')) {
      stops.add('<|end|>');
    }

    if (stops.isEmpty) {
      stops.addAll(additionalStops);
    }

    return stops.toList(growable: false);
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

    final trimmed = text.trim();
    final decoded = ToolCallParsingUtils.decodeJsonObject(trimmed);
    if (decoded == null) {
      if (isPartial) {
        final partial = _parsePartialEnvelope(trimmed);
        if (partial != null) {
          return ChatParseResult(
            content: partial.content,
            reasoningContent: thinking.reasoning,
            toolCalls: partial.toolCalls,
          );
        }
        if (trimmed.startsWith('{')) {
          // Match llama.cpp partial generic parsing behavior: incomplete JSON
          // envelopes do not stream raw object fragments as assistant content.
          return ChatParseResult(
            content: '',
            reasoningContent: thinking.reasoning,
          );
        }
      }
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    if (decoded.containsKey('tool_calls')) {
      final toolCalls = _extractToolCalls(decoded['tool_calls']);
      if (toolCalls == null) {
        return ChatParseResult(
          content: trimmed,
          reasoningContent: thinking.reasoning,
        );
      }
      return ChatParseResult(
        content: '',
        reasoningContent: thinking.reasoning,
        toolCalls: toolCalls,
      );
    }

    if (decoded.containsKey('tool_call')) {
      final toolCall = _toToolCall(decoded['tool_call'], 0);
      if (toolCall == null) {
        return ChatParseResult(
          content: trimmed,
          reasoningContent: thinking.reasoning,
        );
      }
      return ChatParseResult(
        content: '',
        reasoningContent: thinking.reasoning,
        toolCalls: [toolCall],
      );
    }

    final response = decoded['response'];
    if (decoded.containsKey('response')) {
      return ChatParseResult(
        content: response is String
            ? response
            : const JsonEncoder.withIndent('  ').convert(response),
        reasoningContent: thinking.reasoning,
      );
    }

    return ChatParseResult(
      content: trimmed,
      reasoningContent: thinking.reasoning,
    );
  }

  List<LlamaCompletionChunkToolCall>? _extractToolCalls(Object? value) {
    return ToolCallParsingUtils.parseToolCallArray(value);
  }

  LlamaCompletionChunkToolCall? _toToolCall(Object? value, int index) {
    final map = ToolCallParsingUtils.coerceMap(value);
    if (map == null) {
      return null;
    }

    final rawName = map['name'];
    if (rawName is! String || rawName.isEmpty) {
      return null;
    }

    final rawId = map['id'];
    final id = rawId is String && rawId.isNotEmpty ? rawId : null;

    return ToolCallParsingUtils.createFunctionToolCall(
      index: index,
      name: rawName,
      id: id,
      arguments: map.containsKey('arguments') ? map['arguments'] : null,
    );
  }

  LlamaCompletionChunkToolCall _createPartialToolCall({
    required int index,
    required String name,
    String? id,
    Object? arguments,
  }) {
    return ToolCallParsingUtils.createFunctionToolCall(
      index: index,
      name: name,
      id: id,
      arguments: arguments,
      assignFallbackId: false,
    );
  }

  _PartialGenericEnvelope? _parsePartialEnvelope(String text) {
    final partialToolCall = _parsePartialToolCall(text);
    if (partialToolCall != null) {
      return _PartialGenericEnvelope(content: '', toolCalls: [partialToolCall]);
    }
    final partialToolCalls = _parsePartialToolCallsArray(text);
    if (partialToolCalls.isNotEmpty) {
      return _PartialGenericEnvelope(content: '', toolCalls: partialToolCalls);
    }

    final responseMatch = RegExp(r'"response"\s*:\s*"').firstMatch(text);
    if (responseMatch != null) {
      return _PartialGenericEnvelope(
        content: _decodePartialJsonString(text, responseMatch.end),
        toolCalls: const [],
      );
    }

    return null;
  }

  LlamaCompletionChunkToolCall? _parsePartialToolCall(String text) {
    final toolCallKey = RegExp(r'"tool_call"\s*:\s*\{');
    final match = toolCallKey.firstMatch(text);
    if (match == null) {
      return null;
    }
    final objectStart = match.end - 1;
    final body = text.substring(objectStart);

    final name = _extractTopLevelStringField(body, 'name');
    if (name == null || name.isEmpty) {
      return null;
    }

    final id = _extractTopLevelStringField(body, 'id');
    final rawArguments = _extractPartialArguments(body);

    return _createPartialToolCall(
      index: 0,
      name: name,
      id: id,
      arguments: rawArguments,
    );
  }

  List<LlamaCompletionChunkToolCall> _parsePartialToolCallsArray(String text) {
    final toolCallsKey = RegExp(r'"tool_calls"\s*:\s*\[');
    final match = toolCallsKey.firstMatch(text);
    if (match == null) {
      return const [];
    }

    final body = text.substring(match.end);
    final calls = <LlamaCompletionChunkToolCall>[];

    for (final callBody in _extractPartialTopLevelArrayObjects(body)) {
      final name = _extractTopLevelStringField(callBody, 'name');
      if (name == null || name.isEmpty) {
        continue;
      }

      final id = _extractTopLevelStringField(callBody, 'id');
      final rawArguments = _extractPartialArguments(callBody);

      calls.add(
        _createPartialToolCall(
          index: calls.length,
          name: name,
          id: id,
          arguments: rawArguments,
        ),
      );
    }

    return calls;
  }

  String _decodePartialJsonString(String text, int start) {
    final content = StringBuffer();
    var i = start;

    while (i < text.length) {
      final ch = text.codeUnitAt(i);
      if (ch == 0x22) {
        break;
      }

      if (ch != 0x5C) {
        content.writeCharCode(ch);
        i++;
        continue;
      }

      if (i + 1 >= text.length) {
        break;
      }

      final escape = text.codeUnitAt(i + 1);
      switch (escape) {
        case 0x22: // "
        case 0x5C: // \
        case 0x2F: // /
          content.writeCharCode(escape);
          i += 2;
          continue;
        case 0x62: // b
          content.writeCharCode(0x08);
          i += 2;
          continue;
        case 0x66: // f
          content.writeCharCode(0x0C);
          i += 2;
          continue;
        case 0x6E: // n
          content.writeCharCode(0x0A);
          i += 2;
          continue;
        case 0x72: // r
          content.writeCharCode(0x0D);
          i += 2;
          continue;
        case 0x74: // t
          content.writeCharCode(0x09);
          i += 2;
          continue;
        case 0x75: // uXXXX
          final decoded = _decodeUnicodeEscape(text, i);
          if (decoded == null) {
            return content.toString();
          }
          content.write(decoded.value);
          i += decoded.consumed;
          continue;
        default:
          // Invalid escape sequence in partial output: stop at last valid
          // decoded prefix so streaming/final parse prefixes remain aligned.
          return content.toString();
      }
    }

    return content.toString();
  }

  _DecodedUnicodeEscape? _decodeUnicodeEscape(String text, int start) {
    if (start + 5 >= text.length) {
      return null;
    }

    final hex = text.substring(start + 2, start + 6);
    final codeUnit = int.tryParse(hex, radix: 16);
    if (codeUnit == null) {
      return null;
    }

    final isHighSurrogate = codeUnit >= 0xD800 && codeUnit <= 0xDBFF;
    if (isHighSurrogate &&
        start + 11 < text.length &&
        text.codeUnitAt(start + 6) == 0x5C &&
        text.codeUnitAt(start + 7) == 0x75) {
      final lowHex = text.substring(start + 8, start + 12);
      final lowCodeUnit = int.tryParse(lowHex, radix: 16);
      if (lowCodeUnit != null &&
          lowCodeUnit >= 0xDC00 &&
          lowCodeUnit <= 0xDFFF) {
        final codePoint =
            0x10000 + ((codeUnit - 0xD800) << 10) + (lowCodeUnit - 0xDC00);
        return _DecodedUnicodeEscape(
          value: String.fromCharCode(codePoint),
          consumed: 12,
        );
      }
    }

    return _DecodedUnicodeEscape(
      value: String.fromCharCode(codeUnit),
      consumed: 6,
    );
  }

  String _extractPartialArguments(String body) {
    final valueStart = _findTopLevelKeyValueStart(body, 'arguments');
    if (valueStart == null) {
      return '';
    }

    final pos = valueStart;
    if (pos >= body.length) {
      return '';
    }

    final startChar = body[pos];
    if (startChar == '{') {
      return _extractPartialJsonObject(body, pos);
    }
    if (startChar == '[') {
      return _extractPartialJsonArray(body, pos);
    }
    if (startChar == '"') {
      return _decodePartialJsonString(body, pos + 1);
    }

    return _extractPartialPrimitive(body, pos);
  }

  String _extractPartialJsonObject(String text, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == '\\') {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) {
        continue;
      }
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          return text.substring(start, i + 1);
        }
      }
    }
    return text.substring(start).trimRight();
  }

  String _extractPartialJsonArray(String text, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == '\\') {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) {
        continue;
      }
      if (ch == '[') {
        depth++;
      } else if (ch == ']') {
        depth--;
        if (depth == 0) {
          return text.substring(start, i + 1);
        }
      }
    }
    return text.substring(start).trimRight();
  }

  String _extractPartialPrimitive(String text, int start) {
    var i = start;
    while (i < text.length) {
      final ch = text.codeUnitAt(i);
      if (ch == 0x2C || ch == 0x7D || ch == 0x5D) {
        break;
      }
      i++;
    }
    return text.substring(start, i).trim();
  }

  List<String> _extractPartialTopLevelArrayObjects(String text) {
    final objects = <String>[];
    var i = 0;
    while (i < text.length) {
      while (i < text.length &&
          (_isWhitespace(text.codeUnitAt(i)) || text.codeUnitAt(i) == 0x2C)) {
        i++;
      }
      if (i >= text.length || text.codeUnitAt(i) == 0x5D) {
        break;
      }

      if (text.codeUnitAt(i) != 0x7B) {
        i++;
        continue;
      }

      final object = _extractPartialJsonObject(text, i);
      if (object.isEmpty) {
        break;
      }

      objects.add(object);
      i += object.length;
    }
    return objects;
  }

  String? _extractTopLevelStringField(String objectText, String key) {
    final valueStart = _findTopLevelKeyValueStart(objectText, key);
    if (valueStart == null ||
        valueStart >= objectText.length ||
        objectText.codeUnitAt(valueStart) != 0x22) {
      return null;
    }
    return _decodePartialJsonString(objectText, valueStart + 1);
  }

  int? _findTopLevelKeyValueStart(String objectText, String key) {
    if (objectText.isEmpty || objectText.codeUnitAt(0) != 0x7B) {
      return null;
    }

    var depth = 0;
    var i = 0;
    while (i < objectText.length) {
      final ch = objectText.codeUnitAt(i);
      if (ch == 0x7B) {
        depth++;
        i++;
        continue;
      }
      if (ch == 0x7D) {
        depth--;
        if (depth <= 0) {
          break;
        }
        i++;
        continue;
      }

      if (ch != 0x22) {
        i++;
        continue;
      }

      final parsed = _parseJsonStringToken(objectText, i);
      if (parsed == null) {
        break;
      }

      if (depth == 1 && parsed.value == key) {
        var cursor = parsed.end;
        while (cursor < objectText.length &&
            _isWhitespace(objectText.codeUnitAt(cursor))) {
          cursor++;
        }
        if (cursor < objectText.length &&
            objectText.codeUnitAt(cursor) == 0x3A) {
          cursor++;
          while (cursor < objectText.length &&
              _isWhitespace(objectText.codeUnitAt(cursor))) {
            cursor++;
          }
          return cursor;
        }
      }

      i = parsed.end;
    }

    return null;
  }

  _JsonStringToken? _parseJsonStringToken(String text, int quoteStart) {
    if (quoteStart >= text.length || text.codeUnitAt(quoteStart) != 0x22) {
      return null;
    }

    final buffer = StringBuffer();
    var i = quoteStart + 1;
    while (i < text.length) {
      final ch = text.codeUnitAt(i);
      if (ch == 0x22) {
        return _JsonStringToken(value: buffer.toString(), end: i + 1);
      }

      if (ch != 0x5C) {
        buffer.writeCharCode(ch);
        i++;
        continue;
      }

      if (i + 1 >= text.length) {
        return null;
      }

      final escape = text.codeUnitAt(i + 1);
      switch (escape) {
        case 0x22: // "
        case 0x5C: // \
        case 0x2F: // /
          buffer.writeCharCode(escape);
          i += 2;
          continue;
        case 0x62: // b
          buffer.writeCharCode(0x08);
          i += 2;
          continue;
        case 0x66: // f
          buffer.writeCharCode(0x0C);
          i += 2;
          continue;
        case 0x6E: // n
          buffer.writeCharCode(0x0A);
          i += 2;
          continue;
        case 0x72: // r
          buffer.writeCharCode(0x0D);
          i += 2;
          continue;
        case 0x74: // t
          buffer.writeCharCode(0x09);
          i += 2;
          continue;
        case 0x75: // uXXXX
          final decoded = _decodeUnicodeEscape(text, i);
          if (decoded == null) {
            return null;
          }
          buffer.write(decoded.value);
          i += decoded.consumed;
          continue;
        default:
          return null;
      }
    }

    return null;
  }

  bool _isWhitespace(int charCode) {
    return charCode == 0x20 ||
        charCode == 0x09 ||
        charCode == 0x0A ||
        charCode == 0x0D;
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    // Generic handler doesn't build grammar — relies on prompt-based tool calling
    return null;
  }

  /// The built-in ChatML template string.
  static String get chatMlTemplate => _chatMlTemplate;
}

class _PartialGenericEnvelope {
  final String content;
  final List<LlamaCompletionChunkToolCall> toolCalls;

  const _PartialGenericEnvelope({
    required this.content,
    required this.toolCalls,
  });
}

class _DecodedUnicodeEscape {
  final String value;
  final int consumed;

  const _DecodedUnicodeEscape({required this.value, required this.consumed});
}

class _JsonStringToken {
  final String value;
  final int end;

  const _JsonStringToken({required this.value, required this.end});
}
