import 'dart:convert';

import '../exceptions.dart';
import '../grammar/json_value_depth.dart';
import '../models/chat/completion_chunk.dart';

/// Literal text in [ToolCallParsingUtils]'s id stringifier.
class _IdText {
  const _IdText(this.text);

  final String text;
}

/// A parsed JSON value and the exclusive end offset where it stopped.
class ParsedJsonValueSlice {
  /// The decoded JSON value.
  final Object? value;

  /// The exclusive end offset in the source string.
  final int end;

  /// Creates a parsed JSON value slice.
  const ParsedJsonValueSlice({required this.value, required this.end});
}

/// Shared helpers for JSON-style tool-call parsing.
class ToolCallParsingUtils {
  /// [value]'s `toString`, without the recursion that overflows on a deep
  /// list or map.
  static String _stringifyId(Object value) {
    final out = StringBuffer();
    final pending = <Object?>[value];
    while (pending.isNotEmpty) {
      final item = pending.removeLast();
      if (item is _IdText) {
        out.write(item.text);
      } else if (item is List) {
        out.write('[');
        pending.add(const _IdText(']'));
        for (var i = item.length - 1; i >= 0; i--) {
          pending.add(item[i]);
          if (i > 0) pending.add(const _IdText(', '));
        }
      } else if (item is Map) {
        out.write('{');
        pending.add(const _IdText('}'));
        final entries = item.entries.toList(growable: false);
        for (var i = entries.length - 1; i >= 0; i--) {
          pending
            ..add(entries[i].value)
            ..add(_IdText('${entries[i].key}: '));
          if (i > 0) pending.add(const _IdText(', '));
        }
      } else {
        out.write(item);
      }
    }
    return out.toString();
  }

  /// Attempts to decode [text] into a JSON object.
  static Map<String, dynamic>? decodeJsonObject(String text) {
    if (text.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  /// Decodes [value] into a string-keyed JSON object when possible.
  static Map<String, dynamic>? decodeJsonMapValue(
    Object? value, {
    bool trimInput = false,
  }) {
    final map = coerceMap(value);
    if (map != null) {
      return map;
    }

    if (value is String) {
      return decodeJsonObject(trimInput ? value.trim() : value);
    }

    return null;
  }

  /// Coerces [value] to a string-keyed map when possible.
  static Map<String, dynamic>? coerceMap(Object? value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries) '${entry.key}': entry.value,
      };
    }
    return null;
  }

  /// Parses a list of simple function-style tool-call maps.
  static List<LlamaCompletionChunkToolCall>? parseToolCallArray(
    Object? decoded, {
    Iterable<String> nameKeys = const <String>['name'],
    Iterable<String> argumentKeys = const <String>['arguments'],
    Iterable<String> idKeys = const <String>['id'],
    int startIndex = 0,
    bool assignFallbackIds = false,
    bool failOnInvalidItem = true,
  }) {
    if (decoded is! List) {
      return null;
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    for (final item in decoded) {
      final map = coerceMap(item);
      if (map == null) {
        if (failOnInvalidItem) {
          return null;
        }
        continue;
      }

      final function = coerceMap(map['function']);
      final nameSource = function ?? map;
      final name = _firstNonEmptyString(nameSource, nameKeys);
      if (name == null) {
        if (failOnInvalidItem) {
          return null;
        }
        continue;
      }

      final id =
          _firstNonEmptyString(map, idKeys, stringify: true) ??
          (function == null
              ? null
              : _firstNonEmptyString(function, idKeys, stringify: true));
      var argumentValue = _firstPresentValue(nameSource, argumentKeys);
      if (!argumentValue.found && function != null) {
        argumentValue = _firstPresentValue(map, argumentKeys);
      }
      toolCalls.add(
        createFunctionToolCall(
          index: startIndex + toolCalls.length,
          name: name,
          id: id,
          arguments: argumentValue.found ? argumentValue.value : null,
          assignFallbackId: assignFallbackIds,
        ),
      );
    }

    return toolCalls;
  }

  /// Parses arrays shaped like `[ {"tool_name": {...args...}} ]`.
  static List<LlamaCompletionChunkToolCall>? parseSingleKeyToolCallArray(
    Object? decoded, {
    int startIndex = 0,
    bool assignFallbackIds = false,
    bool failOnInvalidItem = true,
  }) {
    if (decoded is! List) {
      return null;
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    for (final item in decoded) {
      final map = coerceMap(item);
      if (map == null || map.length != 1) {
        if (failOnInvalidItem) {
          return null;
        }
        continue;
      }

      final entry = map.entries.first;
      final name = entry.key;
      if (name.isEmpty) {
        if (failOnInvalidItem) {
          return null;
        }
        continue;
      }

      toolCalls.add(
        createFunctionToolCall(
          index: startIndex + toolCalls.length,
          name: name,
          arguments: entry.value,
          assignFallbackId: assignFallbackIds,
        ),
      );
    }

    return toolCalls;
  }

  /// Attempts to decode [text] into any JSON value.
  static Object? decodeJsonValue(String text, {bool trimInput = false}) {
    final normalizedInput = trimInput ? text.trim() : text;
    if (normalizedInput.isEmpty) {
      return null;
    }

    try {
      return jsonDecode(normalizedInput);
    } catch (_) {
      return null;
    }
  }

  /// Decodes [text] as JSON whose string values may hold raw inner quotes,
  /// as `JsonSchemaConverter.convert(innerQuoteStrings: true)` admits them.
  ///
  /// A raw `"` in a string value is text when the next non-space character
  /// cannot follow a closing quote, or when `"` or `}"` follows it;
  /// otherwise it closes the string. Keys keep strict JSON. Returns null when
  /// [text] is not JSON under that reading.
  static Object? decodeJsonValueWithInnerQuotes(String text) {
    final out = StringBuffer();
    _scanInnerQuoteJson(text, 0, out);
    return decodeJsonValue(out.toString());
  }

  /// The end offset of the JSON object or array at [start], read as
  /// [decodeJsonValueWithInnerQuotes] reads it, or null when it is unclosed.
  static int? innerQuoteJsonContainerEnd(String text, int start) =>
      start < text.length && '[{'.contains(text[start])
      ? _scanInnerQuoteJson(text, start, null)
      : null;

  /// With [out], copies [text] from [start] with inner quotes escaped and
  /// returns null; without it, returns the offset after the container that
  /// opens at [start], or null when that container is unclosed.
  static int? _scanInnerQuoteJson(String text, int start, StringBuffer? out) {
    final objects = <bool>[];
    var key = false;
    for (var i = start; i < text.length; i++) {
      final char = text[i];
      out?.write(char);
      if (char != '"') {
        switch (char) {
          case '{':
            objects.add(true);
            key = true;
          case '[':
            objects.add(false);
            key = false;
          case '}' || ']':
            if (objects.isNotEmpty) objects.removeLast();
            key = false;
            if (out == null && objects.isEmpty) return i + 1;
          case ':':
            key = false;
          case ',':
            key = objects.isNotEmpty && objects.last;
        }
        continue;
      }
      for (i++; i < text.length; i++) {
        final inner = text[i];
        if (inner == r'\') {
          out?.write(inner);
          if (++i < text.length) out?.write(text[i]);
        } else if (inner == '"' && !key && _isInnerQuote(text, i)) {
          out?.write(r'\"');
        } else {
          out?.write(inner);
          if (inner == '"') break;
        }
      }
    }
    return null;
  }

  static bool _isInnerQuote(String text, int quote) {
    final after = quote + 1;
    if (text.startsWith('"', after) || text.startsWith('}"', after)) {
      return true;
    }
    var at = after;
    while (at < text.length && text[at] == ' ') {
      at++;
    }
    if (at == text.length) return false;
    final next = text.codeUnitAt(at);
    return next >= 0x20 && next != 0x7f && !'",}]'.contains(text[at]);
  }

  /// Decodes [text] as JSON and falls back to the original string on failure.
  static Object? decodeJsonValueOrString(
    String text, {
    bool trimInput = false,
  }) {
    final normalizedInput = trimInput ? text.trim() : text;
    if (normalizedInput.isEmpty) {
      return normalizedInput;
    }

    try {
      return jsonDecode(normalizedInput);
    } catch (_) {
      return normalizedInput;
    }
  }

  /// Encodes parsed tool-call arguments to the chunk wire format.
  static String encodeArguments(Object? arguments) {
    if (arguments == null) {
      return '';
    }
    final depth = jsonValueDepth(arguments);
    if (depth == null || depth > 128) {
      throw LlamaInferenceException(
        'Tool-call arguments must contain JSON values nested at most 128 levels deep.',
      );
    }
    return arguments is String ? arguments : jsonEncode(arguments);
  }

  /// Normalizes raw JSON-like tool arguments into a stable string payload.
  static String normalizeJsonArguments(
    String rawText, {
    bool trimInput = false,
    bool wrapScalarsAsValue = false,
    String emptyFallback = '{}',
  }) {
    final normalizedInput = trimInput ? rawText.trim() : rawText;
    if (normalizedInput.isEmpty) {
      return emptyFallback;
    }

    try {
      final decoded = jsonDecode(normalizedInput);
      if (decoded is Map<String, dynamic>) {
        return jsonEncode(decoded);
      }
      if (decoded is Map) {
        return jsonEncode(Map<String, dynamic>.from(decoded));
      }
      if (wrapScalarsAsValue) {
        return jsonEncode(<String, dynamic>{'value': decoded});
      }
      return jsonEncode(decoded);
    } catch (_) {
      return normalizedInput;
    }
  }

  /// Extracts the first JSON object found within [input].
  static Map<String, dynamic>? extractFirstJsonObject(String input) {
    final start = input.indexOf('{');
    if (start < 0) {
      return null;
    }

    final jsonSlice = extractLeadingJsonValue(input, start);
    if (jsonSlice == null || jsonSlice.value is! Map) {
      return null;
    }

    return coerceMap(jsonSlice.value);
  }

  /// Finds where one of [openings] may start in [text].
  ///
  /// Returns the first index at or after [from] where an opening starts, or
  /// where the rest of [text] is the start of one, and `text.length` when
  /// there is none.
  static int literalOpening(
    String text,
    List<String> openings, [
    int from = 0,
  ]) {
    var first = text.length;
    for (final opening in openings) {
      final index = text.indexOf(opening, from);
      if (index >= 0) {
        if (index < first) {
          first = index;
        }
        continue;
      }
      final partialFrom = text.length - opening.length + 1;
      for (var i = partialFrom > from ? partialFrom : from; i < first; i++) {
        if (opening.startsWith(text.substring(i))) {
          first = i;
          break;
        }
      }
    }
    return first;
  }

  /// Extracts a single leading JSON value starting at [offset].
  static ParsedJsonValueSlice? extractLeadingJsonValue(
    String input,
    int offset,
  ) {
    if (offset >= input.length) {
      return null;
    }

    int? end;
    final first = input.codeUnitAt(offset);
    if (first == 0x7B || first == 0x5B) {
      end = _findStructuredJsonEnd(input, offset);
    } else if (first == 0x22) {
      end = _findJsonStringEnd(input, offset);
    } else {
      final scalar = RegExp(
        r'(?:-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null)',
      ).matchAsPrefix(input, offset);
      if (scalar != null) {
        end = scalar.end;
      }
    }

    if (end == null || end <= offset) {
      return null;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(input.substring(offset, end));
    } catch (_) {
      return null;
    }

    return ParsedJsonValueSlice(value: decoded, end: end);
  }

  /// Whether [input] is valid JSON with unique keys in every object.
  ///
  /// JSON decoding normally collapses duplicate keys before schema validation.
  /// Protocol parsers that must fail closed on ambiguous objects can use this
  /// check before accepting the decoded value.
  static bool hasUniqueJsonObjectKeys(String input) {
    try {
      jsonDecode(input);
    } catch (_) {
      return false;
    }
    return _UniqueJsonObjectKeyScanner(input).scan();
  }

  /// Builds a function-style tool call chunk.
  static LlamaCompletionChunkToolCall createFunctionToolCall({
    required int index,
    required String name,
    String? id,
    Object? arguments,
    String type = 'function',
    bool assignFallbackId = true,
  }) {
    final normalizedId = id != null && id.isNotEmpty
        ? id
        : (assignFallbackId ? 'call_$index' : null);

    return LlamaCompletionChunkToolCall(
      index: index,
      id: normalizedId,
      type: type,
      function: LlamaCompletionChunkFunction(
        name: name,
        arguments: encodeArguments(arguments),
      ),
    );
  }

  static String? _firstNonEmptyString(
    Map<String, dynamic> map,
    Iterable<String> keys, {
    bool stringify = false,
  }) {
    for (final key in keys) {
      if (!map.containsKey(key)) {
        continue;
      }
      final value = map[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
      if (stringify && value != null) {
        final stringValue = _stringifyId(value);
        if (stringValue.isNotEmpty) {
          return stringValue;
        }
      }
    }
    return null;
  }

  static ({bool found, Object? value}) _firstPresentValue(
    Map<String, dynamic> map,
    Iterable<String> keys,
  ) {
    for (final key in keys) {
      if (map.containsKey(key)) {
        return (found: true, value: map[key]);
      }
    }
    return (found: false, value: null);
  }

  static int? _findStructuredJsonEnd(String input, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = start; i < input.length; i++) {
      final ch = input.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
          continue;
        }
        if (ch == 0x5C) {
          escaped = true;
          continue;
        }
        if (ch == 0x22) {
          inString = false;
        }
        continue;
      }

      if (ch == 0x22) {
        inString = true;
        continue;
      }
      if (ch == 0x7B || ch == 0x5B) {
        depth++;
        continue;
      }
      if (ch == 0x7D || ch == 0x5D) {
        depth--;
        if (depth == 0) {
          return i + 1;
        }
      }
    }

    return null;
  }

  static int? _findJsonStringEnd(String input, int start) {
    var escaped = false;
    for (var i = start + 1; i < input.length; i++) {
      final ch = input.codeUnitAt(i);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == 0x5C) {
        escaped = true;
        continue;
      }
      if (ch == 0x22) {
        return i + 1;
      }
    }
    return null;
  }
}

class _UniqueJsonObjectKeyScanner {
  _UniqueJsonObjectKeyScanner(this.input);

  final String input;
  var _offset = 0;

  bool scan() {
    if (!_scanValue()) {
      return false;
    }
    _skipWhitespace();
    return _offset == input.length;
  }

  bool _scanValue() {
    _skipWhitespace();
    if (_offset >= input.length) {
      return false;
    }
    return switch (input.codeUnitAt(_offset)) {
      0x7B => _scanObject(),
      0x5B => _scanArray(),
      0x22 => _scanString(),
      _ => _scanScalar(),
    };
  }

  bool _scanObject() {
    _offset++;
    _skipWhitespace();
    if (_consume(0x7D)) {
      return true;
    }

    final keys = <String>{};
    while (_offset < input.length) {
      _skipWhitespace();
      if (_offset >= input.length || input.codeUnitAt(_offset) != 0x22) {
        return false;
      }
      final keyStart = _offset;
      if (!_scanString()) {
        return false;
      }
      final key = jsonDecode(input.substring(keyStart, _offset)) as String;
      if (!keys.add(key)) {
        return false;
      }

      _skipWhitespace();
      if (!_consume(0x3A) || !_scanValue()) {
        return false;
      }
      _skipWhitespace();
      if (_consume(0x7D)) {
        return true;
      }
      if (!_consume(0x2C)) {
        return false;
      }
    }
    return false;
  }

  bool _scanArray() {
    _offset++;
    _skipWhitespace();
    if (_consume(0x5D)) {
      return true;
    }
    while (_offset < input.length) {
      if (!_scanValue()) {
        return false;
      }
      _skipWhitespace();
      if (_consume(0x5D)) {
        return true;
      }
      if (!_consume(0x2C)) {
        return false;
      }
    }
    return false;
  }

  bool _scanString() {
    if (!_consume(0x22)) {
      return false;
    }
    var escaped = false;
    while (_offset < input.length) {
      final character = input.codeUnitAt(_offset++);
      if (escaped) {
        escaped = false;
      } else if (character == 0x5C) {
        escaped = true;
      } else if (character == 0x22) {
        return true;
      }
    }
    return false;
  }

  bool _scanScalar() {
    final start = _offset;
    while (_offset < input.length) {
      final character = input.codeUnitAt(_offset);
      if (_isJsonWhitespace(character) ||
          character == 0x2C ||
          character == 0x5D ||
          character == 0x7D) {
        break;
      }
      _offset++;
    }
    return _offset > start;
  }

  void _skipWhitespace() {
    while (_offset < input.length &&
        _isJsonWhitespace(input.codeUnitAt(_offset))) {
      _offset++;
    }
  }

  bool _consume(int character) {
    if (_offset >= input.length || input.codeUnitAt(_offset) != character) {
      return false;
    }
    _offset++;
    return true;
  }
}

bool _isJsonWhitespace(int character) =>
    character == 0x20 ||
    character == 0x09 ||
    character == 0x0A ||
    character == 0x0D;
