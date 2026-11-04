import '../models/chat/completion_chunk.dart';
import 'tool_call_parsing_utils.dart';

/// Result of parsing loose tool-call text fallback.
class ToolCallFallbackParseResult {
  /// Remaining user-visible content after extracting tool calls.
  final String content;

  /// Parsed tool calls, if any.
  final List<LlamaCompletionChunkToolCall> toolCalls;

  /// Creates a fallback parse result.
  const ToolCallFallbackParseResult({
    required this.content,
    required this.toolCalls,
  });
}

/// Parses tool calls from loose plain-text payloads.
///
/// This is intentionally permissive and used only when a format-specific
/// parser fails to extract explicit tool-call structures.
ToolCallFallbackParseResult parseToolCallsFromLooseText(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return const ToolCallFallbackParseResult(
      content: '',
      toolCalls: <LlamaCompletionChunkToolCall>[],
    );
  }

  final normalized = _stripToolFence(trimmed);

  final jsonCalls = _parseJsonLikeToolCalls(normalized);
  if (jsonCalls.isNotEmpty) {
    return ToolCallFallbackParseResult(content: '', toolCalls: jsonCalls);
  }

  final functionCall = _parseFunctionCallSyntax(normalized);
  if (functionCall != null) {
    return ToolCallFallbackParseResult(
      content: '',
      toolCalls: <LlamaCompletionChunkToolCall>[functionCall],
    );
  }

  return ToolCallFallbackParseResult(
    content: trimmed,
    toolCalls: const <LlamaCompletionChunkToolCall>[],
  );
}

/// Decodes tool arguments JSON/object text into a map.
Map<String, dynamic> decodeToolArgumentsObject(String? rawArguments) {
  if (rawArguments == null) {
    return const <String, dynamic>{};
  }

  final trimmed = rawArguments.trim();
  if (trimmed.isEmpty) {
    return const <String, dynamic>{};
  }

  final decoded = ToolCallParsingUtils.decodeJsonMapValue(
    trimmed,
    trimInput: true,
  );
  if (decoded != null) {
    return decoded;
  }

  final object = ToolCallParsingUtils.extractFirstJsonObject(trimmed);
  if (object != null) {
    return object;
  }

  return const <String, dynamic>{};
}

/// Normalizes fallback argument aliases.
Map<String, dynamic> normalizeFallbackToolArguments(
  Map<String, dynamic> arguments,
) {
  final normalized = <String, dynamic>{...arguments};
  final wrappedArguments = _unwrapArgumentContainer(normalized);
  if (wrappedArguments != null) {
    normalized
      ..clear()
      ..addAll(wrappedArguments);
  }
  return normalized;
}

Map<String, dynamic>? _unwrapArgumentContainer(Map<String, dynamic> arguments) {
  const wrapperKeys = <String>{'arguments', 'parameters', 'params', 'input'};
  if (arguments.length != 1) {
    return null;
  }

  final entry = arguments.entries.first;
  if (!wrapperKeys.contains(entry.key)) {
    return null;
  }

  return ToolCallParsingUtils.coerceMap(entry.value);
}

/// Normalizes noisy tool aliases to canonical names where possible.
String normalizeFallbackToolName(
  String rawName, {
  Map<String, dynamic>? arguments,
}) {
  // Preserve model-emitted tool name for llama.cpp parity.
  final trimmed = rawName.trim();
  return trimmed;
}

List<LlamaCompletionChunkToolCall> _parseJsonLikeToolCalls(String input) {
  final parts = input
      .split(RegExp(r'\s*;\s*'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);

  if (parts.length > 1) {
    final calls = <LlamaCompletionChunkToolCall>[];
    for (final part in parts) {
      final partDecoded = _decodeJsonLoose(part);
      if (partDecoded == null) {
        continue;
      }

      calls.addAll(
        _toolCallsFromDecoded(partDecoded, startIndex: calls.length),
      );
    }

    if (calls.isNotEmpty) {
      return List<LlamaCompletionChunkToolCall>.unmodifiable(calls);
    }
  }

  final decoded = _decodeJsonLoose(input);
  if (decoded != null) {
    return _toolCallsFromDecoded(decoded, startIndex: 0);
  }

  return const <LlamaCompletionChunkToolCall>[];
}

Object? _decodeJsonLoose(String input) {
  final direct = ToolCallParsingUtils.decodeJsonValue(input);
  if (direct != null) {
    return direct;
  }

  final normalized = _normalizeLooseJsonIdentifiers(input);
  final normalizedDecoded = ToolCallParsingUtils.decodeJsonValue(normalized);
  if (normalizedDecoded != null) {
    return normalizedDecoded;
  }

  return ToolCallParsingUtils.extractFirstJsonObject(normalized);
}

List<LlamaCompletionChunkToolCall> _toolCallsFromDecoded(
  Object decoded, {
  required int startIndex,
}) {
  final decodedMap = ToolCallParsingUtils.coerceMap(decoded);
  if (decodedMap != null) {
    final toolCallsRaw = decodedMap['tool_calls'];
    if (toolCallsRaw != null) {
      final calls = _toolCallsFromDecoded(toolCallsRaw, startIndex: startIndex);
      if (calls.isNotEmpty) {
        return calls;
      }
    }

    final call = _toolCallFromMap(decodedMap, index: startIndex);
    if (call == null) {
      return const <LlamaCompletionChunkToolCall>[];
    }
    return <LlamaCompletionChunkToolCall>[call];
  }

  if (decoded is List) {
    final calls = <LlamaCompletionChunkToolCall>[];
    for (var i = 0; i < decoded.length; i++) {
      final item = ToolCallParsingUtils.coerceMap(decoded[i]);
      if (item == null) {
        continue;
      }

      final call = _toolCallFromMap(item, index: startIndex + i);
      if (call != null) {
        calls.add(call);
      }
    }
    return List<LlamaCompletionChunkToolCall>.unmodifiable(calls);
  }

  return const <LlamaCompletionChunkToolCall>[];
}

LlamaCompletionChunkToolCall? _toolCallFromMap(
  Map<String, dynamic> object, {
  required int index,
}) {
  final candidate =
      ToolCallParsingUtils.coerceMap(object['tool_call']) ?? object;

  final functionRaw = candidate['function'];
  Object? nameRaw;
  Object? argumentsRaw;
  final function = ToolCallParsingUtils.coerceMap(functionRaw);
  if (function != null) {
    nameRaw = function['name'];
    argumentsRaw =
        function['arguments'] ??
        function['parameters'] ??
        function['params'] ??
        function['input'] ??
        candidate['arguments'] ??
        candidate['parameters'] ??
        candidate['args'] ??
        candidate['params'] ??
        candidate['input'];
  } else {
    nameRaw =
        candidate['name'] ??
        functionRaw ??
        candidate['tool_name'] ??
        candidate['code'] ??
        candidate['type'];
    argumentsRaw =
        candidate['arguments'] ??
        candidate['parameters'] ??
        candidate['args'] ??
        candidate['params'] ??
        candidate['input'];
  }

  if (nameRaw is! String || nameRaw.trim().isEmpty) {
    return null;
  }

  final argsMap = argumentsRaw == null
      ? _extractInlineArguments(candidate)
      : _toArgumentsObject(argumentsRaw);
  final normalizedArgs = normalizeFallbackToolArguments(argsMap);
  final normalizedName = normalizeFallbackToolName(
    nameRaw,
    arguments: normalizedArgs,
  );

  if (normalizedName.isEmpty) {
    return null;
  }

  return ToolCallParsingUtils.createFunctionToolCall(
    index: index,
    name: normalizedName,
    id: object['id'] is String ? object['id'] as String : null,
    arguments: normalizedArgs,
  );
}

Map<String, dynamic> _extractInlineArguments(Map<String, dynamic> candidate) {
  const metaKeys = <String>{
    'name',
    'type',
    'code',
    'tool_name',
    'function',
    'tool',
    'toolName',
    'id',
    'call_id',
    'tool_call_id',
    'index',
    'tool_call',
  };

  final inline = <String, dynamic>{};
  for (final entry in candidate.entries) {
    if (metaKeys.contains(entry.key)) {
      continue;
    }
    inline[entry.key] = entry.value;
  }

  return inline;
}

Map<String, dynamic> _toArgumentsObject(Object? raw) {
  if (raw == null) {
    return const <String, dynamic>{};
  }

  final map = ToolCallParsingUtils.coerceMap(raw);
  if (map != null) {
    return map;
  }

  if (raw is String) {
    return decodeToolArgumentsObject(raw);
  }

  return const <String, dynamic>{};
}

LlamaCompletionChunkToolCall? _parseFunctionCallSyntax(String input) {
  final match = RegExp(
    r'^([A-Za-z_][A-Za-z0-9_\.-]*)\s*(?:\((.*)\))?$',
    dotAll: true,
  ).firstMatch(input);
  if (match == null) {
    return null;
  }

  final nameRaw = match.group(1) ?? '';
  final rawArgs = (match.group(2) ?? '').trim();
  final args = _parseFunctionArguments(rawArgs);
  if (rawArgs.isNotEmpty && args == null) {
    return null;
  }

  final normalizedArgs = normalizeFallbackToolArguments(
    args ?? const <String, dynamic>{},
  );
  final normalizedName = normalizeFallbackToolName(
    nameRaw,
    arguments: normalizedArgs,
  );
  if (normalizedName.isEmpty) {
    return null;
  }

  if (rawArgs.isEmpty && normalizedName == nameRaw) {
    return null;
  }

  return ToolCallParsingUtils.createFunctionToolCall(
    index: 0,
    name: normalizedName,
    arguments: normalizedArgs,
  );
}

/// Splits `key=value` argument lists on top-level commas only, leaving commas
/// inside single/double-quoted values intact (e.g. `note='a, b'`).
List<String> _splitArgsRespectingQuotes(String raw) {
  final parts = <String>[];
  final buffer = StringBuffer();
  String? quote;
  for (var i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (quote != null) {
      buffer.write(ch);
      if (ch == quote) {
        quote = null;
      }
    } else if (ch == '"' || ch == "'") {
      quote = ch;
      buffer.write(ch);
    } else if (ch == ',') {
      parts.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(ch);
    }
  }
  if (buffer.isNotEmpty) {
    parts.add(buffer.toString());
  }
  return parts;
}

Map<String, dynamic>? _parseFunctionArguments(String raw) {
  if (raw.trim().isEmpty) {
    return const <String, dynamic>{};
  }

  final asObject = ToolCallParsingUtils.extractFirstJsonObject(raw);
  if (asObject != null) {
    return asObject;
  }

  final result = <String, dynamic>{};
  final pairs = _splitArgsRespectingQuotes(raw);
  for (final rawPair in pairs) {
    final pair = rawPair.trim();
    if (pair.isEmpty) {
      continue;
    }

    final separatorIndex = pair.indexOf('=');
    if (separatorIndex <= 0) {
      return null;
    }

    final key = pair.substring(0, separatorIndex).trim();
    var value = pair.substring(separatorIndex + 1).trim();
    if (key.isEmpty || value.isEmpty) {
      return null;
    }

    if ((value.startsWith("'") && value.endsWith("'")) ||
        (value.startsWith('"') && value.endsWith('"'))) {
      value = value.substring(1, value.length - 1);
      result[key] = value;
      continue;
    }

    if (value == 'true') {
      result[key] = true;
      continue;
    }

    if (value == 'false') {
      result[key] = false;
      continue;
    }

    final intValue = int.tryParse(value);
    if (intValue != null) {
      result[key] = intValue;
      continue;
    }

    final doubleValue = double.tryParse(value);
    if (doubleValue != null) {
      result[key] = doubleValue;
      continue;
    }

    result[key] = value;
  }

  return result;
}

String _stripToolFence(String input) {
  // Require a whitespace boundary after the optional language token so a
  // payload like ```jsonify{...} does not get "json" consumed as the language
  // (which would leave "ify{...}" as the body and corrupt the JSON).
  final fenced = RegExp(
    r'^```(?:(?:tool_code|tool|json)(?=\s))?\s*([\s\S]*?)\s*```$',
  );
  final match = fenced.firstMatch(input);
  if (match == null) {
    return input;
  }

  final inner = match.group(1);
  if (inner == null || inner.trim().isEmpty) {
    return input;
  }

  return inner.trim();
}

String _normalizeLooseJsonIdentifiers(String input) {
  var normalized = input;
  normalized = normalized.replaceAllMapped(
    RegExp(r'("name"\s*:\s*)([A-Za-z_][A-Za-z0-9_\.-]*)'),
    (match) => '${match.group(1)}"${match.group(2)}"',
  );
  normalized = normalized.replaceAllMapped(
    RegExp(r'("function"\s*:\s*)([A-Za-z_][A-Za-z0-9_\.-]*)'),
    (match) => '${match.group(1)}"${match.group(2)}"',
  );
  return normalized;
}
