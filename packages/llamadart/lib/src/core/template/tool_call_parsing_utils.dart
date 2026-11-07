import 'dart:convert';

import '../models/chat/completion_chunk.dart';

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

  /// Decodes [text] as JSON and falls back to the original string on failure.
  static Object decodeJsonValueOrString(String text, {bool trimInput = false}) {
    final normalizedInput = trimInput ? text.trim() : text;
    return decodeJsonValue(normalizedInput) ?? normalizedInput;
  }

  /// Encodes parsed tool-call arguments to the chunk wire format.
  static String encodeArguments(Object? arguments) {
    if (arguments == null) {
      return '';
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

    final decoded = decodeJsonValue(input.substring(offset, end));
    if (decoded == null) {
      return null;
    }

    return ParsedJsonValueSlice(value: decoded, end: end);
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
        final stringValue = value.toString();
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
