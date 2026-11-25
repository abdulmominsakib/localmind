import 'package:dinja/dinja.dart';

import '../../exceptions.dart';
import '../../grammar/json_schema_converter.dart';
import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/inference/tool_choice.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';
import '../tool_call_grammar_utils.dart';
import '../tool_call_parsing_utils.dart';
import '../tool_schema_utils.dart';
import '../template_internal_metadata.dart';

/// Shared rendering and tool-choice handling for direct Jinja formats.
abstract class DirectJinjaHandler extends ChatTemplateHandler {
  @override
  TemplateToolCallSerialization get toolCallSerialization =>
      TemplateToolCallSerialization.normalizeOnly;

  /// Beginning-of-sequence fallback when model metadata omits it.
  String get defaultBosToken => '';

  /// End-of-sequence fallback when model metadata omits it.
  String get defaultEosToken => '';

  /// Protocol markers that begin grammar-constrained generation.
  List<String> get grammarTriggerValues => const [];

  /// Builds the grammar used when the caller requires a tool call.
  String? buildRequiredGrammar(List<ToolDefinition>? tools) =>
      buildGrammar(tools);

  /// Whether the parse takes reply text before a first thinking end tag as a
  /// thought.
  bool get parsesThoughtBeforeEndTag => true;

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
      context: <String, dynamic>{
        'messages': templateMessages(messages, templateSource: templateSource),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((tool) => tool.toJson()).toList(),
        'enable_thinking': enableThinking,
        'thinking': enableThinking,
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? defaultBosToken,
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? defaultEosToken,
        'current_date': resolveTemplateNow(
          metadata,
        ).toIso8601String().substring(0, 10),
      },
      defaults: {'thinking_mode': enableThinking ? 'enabled' : 'disabled'},
    );

    var thinkingForcedOpen = false;
    var thoughtClosed = false;
    if (isThinkingForcedOpen(prompt, startTag: thinkingStartTag)) {
      if (enableThinking) {
        thinkingForcedOpen = true;
      } else {
        prompt = '${prompt.trimRight()}$thinkingEndTag';
        thoughtClosed = true;
      }
    }

    final hasTools = tools != null && tools.isNotEmpty;
    final toolCallsRequired =
        metadata[internalToolChoiceMetadataKey] == ToolChoice.required.name;
    final rendered = LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: toolCallsRequired
          ? buildRequiredGrammar(tools)
          : buildGrammar(tools),
      grammarLazy: hasTools && !toolCallsRequired,
      thinkingForcedOpen: thinkingForcedOpen,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      preservedTokens: hasTools ? preservedTokens : const [],
      grammarTriggers: hasTools
          ? grammarTriggerValues
                .map((value) => GrammarTrigger(type: 0, value: value))
                .toList(growable: false)
          : const [],
    );
    return withThoughtClosedForThinkingOff(
      rendered,
      closed: thoughtClosed && parsesThoughtBeforeEndTag,
    );
  }
}

/// Adds bounded, duplicate-safe states for any-order optional properties.
String? addOptionalStateRules(
  List<String> rules,
  String prefix,
  List<String> optionalRules, {
  required String format,
  required String schemaPath,
  required String separator,
}) {
  if (optionalRules.isEmpty) {
    return null;
  }
  // Each optional property doubles the subset-state count. Ten properties cap
  // one object at 1,024 states and 5,120 non-empty transitions.
  const maxOptionalProperties = 10;
  if (optionalRules.length > maxOptionalProperties) {
    throw LlamaUnsupportedException(
      '$format grammar supports at most $maxOptionalProperties optional '
      'properties per object because duplicate-safe any-order grammar states '
      'grow exponentially; $schemaPath declares ${optionalRules.length}. '
      'Make additional properties required or reduce the object schema.',
    );
  }

  final visited = <String>{};
  String stateName(List<int> remaining) {
    if (remaining.length == optionalRules.length) {
      return prefix;
    }
    return remaining.isEmpty
        ? '$prefix-done'
        : '$prefix-${remaining.join('-')}';
  }

  void addState(List<int> remaining) {
    final name = stateName(remaining);
    if (!visited.add(name)) {
      return;
    }
    if (remaining.isEmpty) {
      rules.add('$name ::= ""');
      return;
    }

    final alternatives = <String>['""'];
    for (final index in remaining) {
      final next = <int>[...remaining]..remove(index);
      addState(next);
      final continuation = separator.isEmpty
          ? stateName(next)
          : '$separator ${stateName(next)}';
      alternatives.add('${optionalRules[index]} $continuation');
    }
    rules.add('$name ::= ${alternatives.join(' | ')}');
  }

  addState(List<int>.generate(optionalRules.length, (index) => index));
  return prefix;
}

/// Requires a tool section after content that excludes its opening marker.
String withRequiredPrefix(
  String grammar, {
  required String delimiter,
  required String prefixName,
}) {
  final lines = grammar.split('\n');
  final rootIndex = lines.indexWhere((line) => line.startsWith('root ::= '));
  if (rootIndex < 0) {
    return grammar;
  }
  lines[rootIndex] = lines[rootIndex].replaceFirst(
    'root ::= ',
    'required-tool-section ::= ',
  );
  final prefixRules = <String>[];
  final prefixRule = addUntilRules(prefixRules, prefixName, delimiter);
  return <String>[
    'root ::= $prefixRule required-tool-section',
    ...lines,
    ...prefixRules,
  ].join('\n');
}

/// Appends converter rules in deterministic name order.
void appendJsonRules(StringBuffer buffer, JsonSchemaConverter converter) {
  final rules = converter.rules.entries.toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));
  for (final entry in rules) {
    buffer.writeln('${entry.key} ::= ${entry.value}');
  }
}

/// Adds rules accepting content up to, but excluding, a delimiter.
String addUntilRules(List<String> rules, String name, String delimiter) {
  final pattern = delimiter.runes
      .map(String.fromCharCode)
      .toList(growable: false);
  final alphabet = <String>[];
  for (final character in pattern) {
    if (!alphabet.contains(character)) {
      alphabet.add(character);
    }
  }
  final fallback = '[^${alphabet.map(_escapeGbnfCharClass).join()}]';
  String state(int index) => '$name-$index';

  for (var index = 0; index < pattern.length; index++) {
    final alternatives = <String>[];
    for (final character in alphabet) {
      final candidate = <String>[...pattern.take(index), character];
      var next = candidate.length;
      while (next > 0 &&
          !_endsWithCharacters(candidate, pattern.take(next).toList())) {
        next--;
      }
      if (next == pattern.length) {
        continue;
      }
      alternatives.add(
        '${ToolCallGrammarUtils.literal(character)} ${state(next)}',
      );
    }
    alternatives.add('$fallback ${state(0)}');
    rules.add('${state(index)} ::= (${alternatives.join(' | ')})?');
  }
  rules.add('$name ::= ${state(0)}');
  return name;
}

/// Adds rules accepting content up to and including the first [delimiter],
/// as llama.cpp's `p.ac` emits them.
String addThroughRules(List<String> rules, String name, String delimiter) {
  final pattern = delimiter.runes
      .map(String.fromCharCode)
      .toList(growable: false);
  final alphabet = <String>[];
  for (final character in pattern) {
    if (!alphabet.contains(character)) {
      alphabet.add(character);
    }
  }
  final fallback = '[^${alphabet.map(_escapeGbnfCharClass).join()}]';
  String state(int index) => '$name-$index';

  for (var index = 0; index < pattern.length; index++) {
    final alternatives = <String>[];
    for (final character in alphabet) {
      final candidate = <String>[...pattern.take(index), character];
      var next = candidate.length;
      while (next > 0 &&
          !_endsWithCharacters(candidate, pattern.take(next).toList())) {
        next--;
      }
      final literal = ToolCallGrammarUtils.literal(character);
      alternatives.add(
        next == pattern.length ? literal : '$literal ${state(next)}',
      );
    }
    alternatives.add('$fallback ${state(0)}');
    rules.add('${state(index)} ::= ${alternatives.join(' | ')}');
  }
  rules.add('$name ::= ${state(0)}');
  return name;
}

bool _endsWithCharacters(List<String> value, List<String> suffix) {
  if (suffix.length > value.length) {
    return false;
  }
  final offset = value.length - suffix.length;
  for (var index = 0; index < suffix.length; index++) {
    if (value[offset + index] != suffix[index]) {
      return false;
    }
  }
  return true;
}

String _escapeGbnfCharClass(String character) {
  return switch (character) {
    r'\' => r'\\',
    '\n' => r'\n',
    '\r' => r'\r',
    '\t' => r'\t',
    ']' => r'\]',
    '^' => r'\^',
    '-' => r'\-',
    _ => character,
  };
}

/// Parses a complete invoke scope or suppresses its unfinished stream suffix.
ParsedInvokeCalls parseInvokeScope(
  String input, {
  required String scopeStart,
  required String scopeEnd,
  required RegExp invokeStartPattern,
  required String invokeEnd,
  required Map<String, dynamic>? Function(String, String) parseArguments,
  required bool isPartial,
}) {
  final scopeStartIndex = input.indexOf(scopeStart);
  if (scopeStartIndex < 0) {
    return ParsedInvokeCalls(
      calls: const [],
      remaining: isPartial
          ? hideIncompleteProtocolSuffix(input, scopeStart)
          : input,
    );
  }
  final bodyStart = scopeStartIndex + scopeStart.length;
  final scopeEndIndex = input.indexOf(scopeEnd, bodyStart);
  if (scopeEndIndex < 0 && !isPartial) {
    return ParsedInvokeCalls.failure();
  }
  final scopeComplete = scopeEndIndex >= 0;
  final body = input.substring(
    bodyStart,
    scopeComplete ? scopeEndIndex : input.length,
  );
  final calls = <LlamaCompletionChunkToolCall>[];
  final allowPartial = isPartial && !scopeComplete;
  ParsedInvokeCalls partialResult() => ParsedInvokeCalls(
    calls: calls,
    remaining: input.substring(0, scopeStartIndex),
  );
  var cursor = 0;
  while (cursor < body.length) {
    final start = invokeStartPattern.firstMatch(body.substring(cursor));
    if (start == null) {
      if (body.substring(cursor).trim().isNotEmpty) {
        return allowPartial ? partialResult() : ParsedInvokeCalls.failure();
      }
      break;
    }
    final absoluteStart = cursor + start.start;
    if (body.substring(cursor, absoluteStart).trim().isNotEmpty) {
      return allowPartial ? partialResult() : ParsedInvokeCalls.failure();
    }
    final argumentsStart = cursor + start.end;
    final end = body.indexOf(invokeEnd, argumentsStart);
    if (end < 0) {
      return allowPartial ? partialResult() : ParsedInvokeCalls.failure();
    }
    final name = decodeCanonicalAttribute(start.group(1) ?? '');
    if (name == null) {
      return allowPartial ? partialResult() : ParsedInvokeCalls.failure();
    }
    final arguments = parseArguments(name, body.substring(argumentsStart, end));
    if (name.isEmpty || arguments == null) {
      return allowPartial ? partialResult() : ParsedInvokeCalls.failure();
    }
    calls.add(
      ToolCallParsingUtils.createFunctionToolCall(
        index: calls.length,
        name: name,
        arguments: arguments,
      ),
    );
    cursor = end + invokeEnd.length;
  }
  if (calls.isEmpty) {
    return allowPartial ? partialResult() : ParsedInvokeCalls.failure();
  }
  if (!scopeComplete) {
    return partialResult();
  }
  final remaining = input.replaceRange(
    scopeStartIndex,
    scopeEndIndex + scopeEnd.length,
    '',
  );
  return ParsedInvokeCalls(calls: calls, remaining: remaining);
}

String _unescapeAttribute(String value) => value
    .replaceAll('&quot;', '"')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

/// Decodes an attribute only when its escaping is canonical.
String? decodeCanonicalAttribute(String value) {
  final decoded = _unescapeAttribute(value);
  return escapeAttribute(decoded) == value ? decoded : null;
}

/// Escapes the attribute characters recognized by specialized protocols.
String escapeAttribute(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Rejects empty identities that a tool protocol cannot represent.
void requireNonEmptyProtocolName(
  String value, {
  required String format,
  required String kind,
}) {
  if (value.isEmpty) {
    throw LlamaUnsupportedException(
      '$format cannot represent an empty $kind name in its tool-call '
      'protocol.',
    );
  }
}

/// Validates unambiguous tool and parameter identities before grammar binding.
void requireUniqueToolNames(
  List<ToolDefinition> tools, {
  required String format,
}) {
  final names = <String>{};
  for (final tool in tools) {
    requireNonEmptyProtocolName(tool.name, format: format, kind: 'tool');
    if (!names.add(tool.name)) {
      throw LlamaUnsupportedException(
        '$format cannot bind duplicate tool name "${tool.name}" to one '
        'schema-exact parser route. Use unique tool names.',
      );
    }
    validateToolParameterIdentities(tool);
  }
}

/// Suppresses a trailing partial opening marker during streaming.
String hideIncompleteProtocolSuffix(String input, String marker) {
  for (var length = marker.length - 1; length > 0; length--) {
    if (input.endsWith(marker.substring(0, length))) {
      return input.substring(0, input.length - length);
    }
  }
  return input;
}

/// Trims optional parsed content and maps empty content to null.
String? nullIfEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Recognizes the ASCII whitespace allowed between protocol elements.
bool isProtocolWhitespace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x0A ||
    codeUnit == 0x0D ||
    codeUnit == 0x09;

/// Result of parsing an invoke scope, including malformed-final rollback.
class ParsedInvokeCalls {
  /// Whether the scope was valid or a permitted partial stream.
  final bool success;

  /// Complete calls parsed before the end of the scope.
  final List<LlamaCompletionChunkToolCall> calls;

  /// Content outside the consumed protocol scope.
  final String remaining;

  /// Creates a successful complete or partial result.
  const ParsedInvokeCalls({required this.calls, required this.remaining})
    : success = true;

  /// Creates a malformed-final result that preserves no parsed calls.
  const ParsedInvokeCalls.failure()
    : success = false,
      calls = const [],
      remaining = '';
}
