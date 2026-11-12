import 'dart:convert';

import 'package:dinja/dinja.dart';

import '../../exceptions.dart';
import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_role.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/inference/tool_choice.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../template_internal_metadata.dart';
import '../thinking_utils.dart';
import '../tool_call_fallback_parser.dart';
import '../tool_call_parsing_utils.dart';
import '../tool_call_grammar_utils.dart';
import '../tool_schema_utils.dart';
import 'lfm2_auto_grammar.dart';

/// Handler for LFM2 and LFM2.5 (Liquid Foundation Model) formats.
///
/// Uses `<|tool_call_start|>` / `<|tool_call_end|>` special tokens for tool
/// calls. LFM2 templates wrap tool definitions in `<|tool_list_start|>` /
/// `<|tool_list_end|>`; LFM2.5 templates write a plain list.
class Lfm2Handler extends ChatTemplateHandler
    implements ToolSchemaAwareChatTemplateHandler {
  /// Finds a possible tool-call list for the stream's content gate.
  static int toolCallOpening(String text, [int from = 0]) =>
      ToolCallParsingUtils.literalOpening(text, const [
        '<|tool_call_start|>',
      ], from);

  static final RegExp _forceJsonSchemaLineMarker = RegExp(
    r'force json schema\.\n',
    caseSensitive: false,
  );

  static final RegExp _forceJsonSchemaMarker = RegExp(
    r'force json schema\.',
    caseSensitive: false,
  );

  @override
  ChatFormat get format => ChatFormat.lfm2;

  @override
  List<String> get additionalStops => ['<|im_end|>'];

  @override
  List<String> getStops({bool hasTools = false, bool enableThinking = true}) {
    if (hasTools) {
      return const [];
    }

    return additionalStops;
  }

  @override
  List<String> get preservedTokens => const [
    '<|tool_call_start|>',
    '<|tool_call_end|>',
  ];

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
    final hasTools = tools != null && tools.isNotEmpty;
    final toolChoice = metadata[internalToolChoiceMetadataKey];
    final toolChoiceRequired = toolChoice == ToolChoice.required.name;
    final parallelToolCalls =
        metadata[internalParallelToolCallsMetadataKey] == 'true';
    final hasForceJsonMarker = _shouldConstrainWithJsonTools(messages);
    final shouldConstrainWithJsonTools =
        hasTools && (hasForceJsonMarker || toolChoiceRequired);
    final shouldConstrainWithPythonTools =
        hasTools &&
        !shouldConstrainWithJsonTools &&
        toolChoice != ToolChoice.none.name;
    final effectiveMessages = hasForceJsonMarker
        ? _stripForceJsonSchemaMarker(messages)
        : messages;
    final adjustedMessages = templateMessages(
      effectiveMessages,
      templateSource: templateSource,
    );
    // llama.cpp supplies the alias used by LFM2.5 templates alongside reasoning.
    for (final message in adjustedMessages) {
      if (message['reasoning_content'] case final String reasoning
          when reasoning.isNotEmpty) {
        message['thinking'] = reasoning;
      }
    }

    final prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': adjustedMessages,
        'add_generation_prompt': addAssistant,
        'tools': _serializeToolsForTemplate(tools),
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '',
      },
    );

    return withLfm2AutoGrammar(
      LlamaChatTemplateResult(
        prompt: prompt,
        format: format.index,
        grammar: shouldConstrainWithJsonTools
            ? _jsonGrammar(tools, parallelToolCalls: parallelToolCalls)
            : shouldConstrainWithPythonTools
            ? buildLfm2AutoGrammar(tools, parallelToolCalls: parallelToolCalls)
            : null,
        grammarLazy:
            (shouldConstrainWithJsonTools && !toolChoiceRequired) ||
            shouldConstrainWithPythonTools,
        additionalStops: getStops(
          hasTools: hasTools,
          enableThinking: enableThinking,
        ),
        preservedTokens: hasTools ? preservedTokens : const [],
        grammarTriggers: shouldConstrainWithJsonTools
            ? [
                const GrammarTrigger(
                  type: 3,
                  value: r'\s*<\|tool_call_start\|>\s*\[',
                ),
              ]
            : shouldConstrainWithPythonTools
            ? [GrammarTrigger(type: 3, value: _autoGrammarTrigger(prompt))]
            : [],
      ),
      enabled: shouldConstrainWithPythonTools,
    );
  }

  String _autoGrammarTrigger(String prompt) {
    final initialThought = isThinkingForcedOpen(prompt, startTag: '<think>')
        ? r'[\s\S]*?</think>'
        : '';
    // The sole capturing group marks the replay boundary. Marker text inside
    // reasoning remains unconstrained and non-executable, as in the parser.
    return '$initialThought'
        r'(?:(?!<think>|<\|tool_call_start\|>)[\s\S]|'
        r'<think>[\s\S]*?</think>)*?'
        r'(<\|tool_call_start\|>)[\s\S]*';
  }

  bool _shouldConstrainWithJsonTools(List<LlamaChatMessage> messages) {
    if (messages.isEmpty) {
      return false;
    }

    final first = messages.first;
    if (first.role != LlamaChatRole.system) {
      return false;
    }

    final content = first.content;
    return _forceJsonSchemaLineMarker.hasMatch(content) ||
        _forceJsonSchemaMarker.hasMatch(content);
  }

  List<LlamaChatMessage> _stripForceJsonSchemaMarker(
    List<LlamaChatMessage> messages,
  ) {
    if (messages.isEmpty) {
      return messages;
    }

    final first = messages.first;
    if (first.role != LlamaChatRole.system) {
      return messages;
    }

    var stripped = first.content.replaceFirst(_forceJsonSchemaLineMarker, '');
    if (stripped == first.content) {
      stripped = first.content.replaceFirst(_forceJsonSchemaMarker, '');
    }
    if (stripped == first.content) {
      return messages;
    }

    return <LlamaChatMessage>[
      first.copyWith(content: stripped),
      ...messages.skip(1),
    ];
  }

  /// Passes each tool as `name`, `description` and `parameters`, the shape
  /// LiquidAI's LFM2 and LFM2.5 model cards show. This deliberately differs
  /// from llama-server, which passes the OpenAI shape (`type`, `function`).
  List<Map<String, dynamic>>? _serializeToolsForTemplate(
    List<ToolDefinition>? tools,
  ) {
    if (tools == null || tools.isEmpty) {
      return null;
    }

    return tools
        .map(
          (tool) => <String, dynamic>{
            'name': tool.name,
            'description': tool.description,
            'parameters': tool.toJsonSchema(),
          },
        )
        .toList(growable: false);
  }

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

  @override
  ChatParseResult parseWithTools(
    String output, {
    List<ToolDefinition>? tools,
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    if (!parseToolCalls) {
      final thinking = extractThinking(
        output,
        thinkingForcedOpen: thinkingForcedOpen,
      );
      return ChatParseResult(
        content: thinking.content.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    final schemas = toolSchemas(tools);
    const opening = '<|tool_call_start|>';
    const closing = '<|tool_call_end|>';
    final toolCalls = <LlamaCompletionChunkToolCall>[];
    final partialToolCalls = <LlamaCompletionChunkToolCall>[];
    final content = StringBuffer();
    final initialThought = _initialThoughtState(
      output,
      schemas,
      thinkingForcedOpen: thinkingForcedOpen,
    );
    // A later explicit opener makes the earlier prefix content in the legacy
    // final parse. Its channel is not safe to stream until a boundary or EOF.
    if (isPartial && thinkingForcedOpen && !initialThought.boundarySeen) {
      return ChatParseResult(content: '');
    }
    var inThought = initialThought.inThought;
    var from = 0;
    while (true) {
      final start = output.indexOf(opening, from);
      if (start == -1) break;
      final prefix = output.substring(from, start);
      inThought = _afterThoughtTags(prefix, inThought);
      if (inThought) {
        // Reasoning is plain text, even when it resembles a quoted call.
        final thoughtEnd = output.indexOf('</think>', start);
        final after = thoughtEnd == -1
            ? output.length
            : thoughtEnd + '</think>'.length;
        content
          ..write(prefix)
          ..write(output.substring(start, after));
        from = after;
        inThought = thoughtEnd == -1;
        continue;
      }
      final payloadStart = start + opening.length;
      final firstEnd = output.indexOf(closing, payloadStart);
      if (firstEnd == -1 ||
          isPartial && _toolCallEnd(output, payloadStart) == null) {
        if (isPartial) {
          partialToolCalls.addAll(
            _unfinishedCalls(output.substring(payloadStart), toolCalls.length),
          );
          content.write(prefix);
          from = output.length;
        }
        break;
      }
      final envelope = _parseEnclosedCalls(
        output,
        payloadStart,
        firstEnd,
        startIndex: toolCalls.length,
        schemas: schemas,
      );
      content.write(prefix);
      final after = envelope.end + closing.length;
      if (envelope.calls != null) {
        toolCalls.addAll(envelope.calls!);
      }
      from = after;
    }
    content.write(output.substring(from));
    final contentText = content.toString();

    final thinking = extractThinking(
      contentText,
      thinkingForcedOpen: thinkingForcedOpen,
    );

    return ChatParseResult(
      content: isPartial
          ? withoutTrailingTagPrefix(thinking.content, [
              '<think>',
              '</think>',
              opening,
            ]).trim()
          : thinking.content.trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
      partialToolCalls: partialToolCalls,
    );
  }

  // Read only the named-call boundary; incomplete arguments remain raw text.
  // This does not validate schemas, repair syntax or create executable calls.
  List<LlamaCompletionChunkToolCall> _unfinishedCalls(String text, int index) {
    final calls = <LlamaCompletionChunkToolCall>[];
    var at = 0;
    var position = index;
    void space() {
      while (at < text.length && ' \t\r\n'.contains(text[at])) {
        at++;
      }
    }

    space();
    if (at < text.length && text[at] == '[') {
      at++;
    }
    while (at < text.length) {
      space();
      if (at == text.length || text[at] == ']') break;
      String? name;
      String? arguments;
      String? id;
      int opening;
      if (text[at] == '{') {
        opening = at;
        final end = _diagnosticContainerEnd(text, opening);
        if (end == null) return const [];
        final fields = _diagnosticJsonFields(text.substring(opening, end.end));
        name = fields.name;
        arguments = fields.arguments;
        id = fields.id;
        at = end.end;
      } else {
        final match = RegExp(
          r'([A-Za-z_][A-Za-z0-9_.-]*)\s*\(',
        ).matchAsPrefix(text, at);
        if (match == null) break;
        name = match[1];
        opening = match.end - 1;
        final end = _diagnosticContainerEnd(text, opening);
        if (end == null) return const [];
        arguments = text.substring(
          opening + 1,
          end.closed ? end.end - 1 : end.end,
        );
        at = end.end;
      }
      if (name != null && name.isNotEmpty && arguments != null) {
        calls.add(
          LlamaCompletionChunkToolCall(
            index: position,
            id: id,
            type: 'function',
            function: LlamaCompletionChunkFunction(
              name: name,
              arguments: arguments,
            ),
          ),
        );
      }
      position++;
      space();
      if (at == text.length || text[at] != ',') break;
      at++;
    }
    return calls;
  }

  // Returns EOF for an unfinished container, without inventing its closer.
  ({int end, bool closed})? _diagnosticContainerEnd(String text, int start) {
    final closers = <String>[];
    String? quote;
    for (var i = start; i < text.length; i++) {
      final char = text[i];
      if (quote != null) {
        if (char == r'\') {
          i++;
        } else if (char == quote) {
          quote = null;
        }
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if ('([{'.contains(char)) {
        closers.add({'(': ')', '[': ']', '{': '}'}[char]!);
      } else if (')]}'.contains(char)) {
        if (closers.isEmpty || closers.removeLast() != char) return null;
        if (closers.isEmpty) return (end: i + 1, closed: true);
      }
    }
    return (end: text.length, closed: false);
  }

  ({String? name, String? arguments, String? id}) _diagnosticJsonFields(
    String text, {
    bool nested = false,
  }) {
    String? name;
    String? arguments;
    String? id;
    var at = 1;
    final keyPattern = RegExp(r'\s*("(?:[^"\\]|\\.)*")\s*:');
    while (at < text.length) {
      final key = keyPattern.matchAsPrefix(text, at);
      if (key == null) break;
      final String field;
      try {
        field = jsonDecode(key[1]!) as String;
      } on FormatException {
        break;
      }
      final start = key.end;
      var end = start;
      final closers = <String>[];
      String? quote;
      for (; end < text.length; end++) {
        final char = text[end];
        if (quote != null) {
          if (char == r'\') {
            end++;
          } else if (char == quote) {
            quote = null;
          }
        } else if (char == '"') {
          quote = char;
        } else if ('[{'.contains(char)) {
          closers.add(char == '[' ? ']' : '}');
        } else if (closers.isNotEmpty && char == closers.last) {
          closers.removeLast();
        } else if (closers.isEmpty && (char == ',' || char == '}')) {
          break;
        }
      }
      // A trailing escape may advance beyond EOF; preserve its exact bytes.
      end = end.clamp(start, text.length);
      final value = text.substring(start, end);
      if (field == 'arguments') {
        arguments = value;
      } else if (field == 'function' &&
          !nested &&
          value.trimLeft().startsWith('{')) {
        final function = _diagnosticJsonFields(value.trimLeft(), nested: true);
        name = function.name;
        arguments = function.arguments;
      } else if (field == 'name' || field == 'id') {
        try {
          final decoded = jsonDecode(value);
          if (decoded is String) {
            if (field == 'name') {
              name = decoded;
            } else {
              id = decoded;
            }
          }
        } on FormatException {
          /* An unfinished name is not a call. */
        }
      }
      if (end == text.length || text[end] != ',') break;
      at = end + 1;
    }
    return (name: name, arguments: arguments, id: id);
  }

  ({int end, List<LlamaCompletionChunkToolCall>? calls}) _parseEnclosedCalls(
    String output,
    int payloadStart,
    int firstEnd, {
    required int startIndex,
    required Map<String, Map<String, dynamic>> schemas,
  }) {
    var end = _toolCallEnd(output, payloadStart) ?? firstEnd;
    var calls = _parseCallList(
      output.substring(payloadStart, end).trim(),
      startIndex: startIndex,
      schemas: schemas,
    );
    // An unmatched quote must not consume a later call or visible prose.
    if (end != firstEnd && calls == null) {
      end = firstEnd;
      calls = _parseCallList(
        output.substring(payloadStart, end).trim(),
        startIndex: startIndex,
        schemas: schemas,
      );
    }
    return (end: end, calls: calls);
  }

  ({bool inThought, bool boundarySeen}) _initialThoughtState(
    String output,
    Map<String, Map<String, dynamic>> schemas, {
    required bool thinkingForcedOpen,
  }) {
    var from = 0;
    while (from < output.length) {
      final open = output.indexOf('<think>', from);
      final close = output.indexOf('</think>', from);
      final tag = open == -1
          ? close
          : close == -1 || open < close
          ? open
          : close;
      if (tag == -1) break;
      final call = output.indexOf('<|tool_call_start|>', from);
      if (call == -1 || tag < call) {
        return (inThought: tag == close, boundarySeen: true);
      }
      final payload = call + '<|tool_call_start|>'.length;
      final end = output.indexOf('<|tool_call_end|>', payload);
      if (end == -1 || _toolCallEnd(output, payload) == null) break;
      // Tags in a complete argument are data, not the first thought marker.
      from =
          _parseEnclosedCalls(
            output,
            payload,
            end,
            startIndex: 0,
            schemas: schemas,
          ).end +
          '<|tool_call_end|>'.length;
    }
    return (inThought: thinkingForcedOpen, boundarySeen: false);
  }

  bool _afterThoughtTags(String text, bool inThought) {
    var from = 0;
    while (from < text.length) {
      final tag = inThought ? '</think>' : '<think>';
      final at = text.indexOf(tag, from);
      if (at == -1) break;
      inThought = !inThought;
      from = at + tag.length;
    }
    return inThought;
  }

  int? _toolCallEnd(String output, int from) {
    var start = from;
    final list = RegExp(r'\s*\[\s*\{').matchAsPrefix(output, from);
    if (list != null) {
      // JSON lists use the inner-quote reading of their grammar.
      final end = ToolCallParsingUtils.innerQuoteJsonContainerEnd(
        output,
        output.indexOf('[', from),
      );
      if (end == null) return null;
      start = end;
    }
    int? quote;
    for (var i = start; i < output.length; i++) {
      final codeUnit = output.codeUnitAt(i);
      if (quote != null) {
        if (codeUnit == 0x5c) {
          i++;
        } else if (codeUnit == quote) {
          quote = null;
        }
      } else if (codeUnit == 0x22 || codeUnit == 0x27) {
        quote = codeUnit;
      } else if (output.startsWith('<|tool_call_end|>', i)) {
        return i;
      }
    }
    return null;
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) =>
      _jsonGrammar(tools, parallelToolCalls: false);

  String? _jsonGrammar(
    List<ToolDefinition>? tools, {
    required bool parallelToolCalls,
  }) => ToolCallGrammarUtils.buildWrappedArrayGrammar(
    tools: tools,
    prefix: '<|tool_call_start|>',
    suffix: '<|tool_call_end|>',
    allowParallelToolCalls: parallelToolCalls,
    // LFM2 models copy quotes into JSON strings without escaping them.
    innerQuoteStrings: true,
  );

  List<LlamaCompletionChunkToolCall>? _parseCallList(
    String payload, {
    required int startIndex,
    Map<String, Map<String, dynamic>> schemas = const {},
  }) {
    try {
      return ToolCallParsingUtils.parseToolCallArray(
            ToolCallParsingUtils.decodeJsonValue(payload) ??
                ToolCallParsingUtils.decodeJsonValueWithInnerQuotes(payload),
            startIndex: startIndex,
            failOnInvalidItem: false,
            assignFallbackIds: true,
          ) ??
          (schemas.isEmpty
              ? _parsePythonStyleToolCallList(payload, startIndex: startIndex)
              : _parseSchemaCallList(payload, schemas, startIndex));
    } on LlamaInferenceException {
      // Arguments the wire format refuses (too deep, not finite) are model
      // text, not a caller error, so they must not throw out of parse.
      return null;
    } on StackOverflowError {
      // dart2js converts a list recursively, and a list under a map key only
      // when the key is read, past any catch in the JSON helpers. A depth limit
      // would also refuse lists that decode, since the overflow depends on the
      // stack, and the partial conversion is discarded here.
      return null;
    }
  }

  List<LlamaCompletionChunkToolCall>? _parseSchemaCallList(
    String payload,
    Map<String, Map<String, dynamic>> schemas,
    int startIndex,
  ) {
    final typed = _PythonCallList(
      payload,
      schemas,
    ).parse(startIndex: startIndex);
    if (typed != null) return typed;
    // Preserve the established malformed-quote leniency for text-only tools;
    // typed values must be read from their named schema positions.
    final legacy = _parsePythonStyleToolCallList(
      payload,
      startIndex: startIndex,
    );
    if (legacy == null) return null;
    for (final call in legacy) {
      final schema = schemas[call.function?.name];
      if (schema == null ||
          !schemaProperties(schema).values.every(schemaResolvesToString)) {
        return null;
      }
      final arguments = ToolCallParsingUtils.decodeJsonValue(
        call.function?.arguments ?? '',
      );
      if (!validateToolSchemaValue(arguments, schema).valid) return null;
    }
    return legacy;
  }

  List<LlamaCompletionChunkToolCall>? _parsePythonStyleToolCallList(
    String payload, {
    required int startIndex,
  }) {
    var body = payload.trim();
    if (body.startsWith('[') && body.endsWith(']')) {
      body = body.substring(1, body.length - 1).trim();
    }
    if (body.isEmpty) {
      return const <LlamaCompletionChunkToolCall>[];
    }

    final parts = _splitPythonStyleToolCalls(body);
    if (parts.isEmpty) {
      return null;
    }

    final calls = <LlamaCompletionChunkToolCall>[];
    for (final part in parts) {
      final parsed = parseToolCallsFromLooseText(part);
      if (parsed.toolCalls.length != 1 || parsed.content.isNotEmpty) {
        return null;
      }
      final call = parsed.toolCalls.single;
      calls.add(
        LlamaCompletionChunkToolCall(
          index: startIndex + calls.length,
          id: call.id,
          type: call.type,
          function: call.function,
        ),
      );
    }

    return calls;
  }

  List<String> _splitPythonStyleToolCalls(String body) {
    final parts = <String>[];
    final buffer = StringBuffer();
    String? quote;
    var depth = 0;

    for (var i = 0; i < body.length; i++) {
      final ch = body[i];
      if (quote != null) {
        buffer.write(ch);
        if (ch == r'\' && i + 1 < body.length) {
          i++;
          buffer.write(body[i]);
        } else if (ch == quote) {
          quote = null;
        }
        continue;
      }

      if (ch == '"' || ch == "'") {
        quote = ch;
        buffer.write(ch);
      } else if (ch == '(' || ch == '[' || ch == '{') {
        depth++;
        buffer.write(ch);
      } else if (ch == ')' || ch == ']' || ch == '}') {
        if (depth > 0) {
          depth--;
        }
        buffer.write(ch);
      } else if (ch == ',' && depth == 0) {
        final part = buffer.toString().trim();
        if (part.isNotEmpty) {
          parts.add(part);
        }
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }

    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) {
      parts.add(tail);
    }

    return parts;
  }
}

// Python-call strings preserve copied backslashes; schemas determine scalar types.
class _PythonCallList {
  _PythonCallList(this._source, this._schemas);

  final Map<String, Map<String, dynamic>> _schemas;
  static const Set<String> _legacyWrappers = {
    'arguments',
    'parameters',
    'params',
    'input',
  };

  static final RegExp _nameAtStart = RegExp(r'[A-Za-z_][A-Za-z0-9_.-]*');
  static final RegExp _numberAtStart = RegExp(
    r'-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?',
  );

  /// One less than the wire format's limit, which counts the arguments map.
  static const int _maxValueDepth = 127;
  static const Map<String, Object?> _literals = {
    'True': true,
    'False': false,
    'None': null,
    'true': true,
    'false': false,
    'null': null,
  };

  final String _source;
  int _at = 0;
  int _depth = 0;

  /// The calls of the whole source, or null if it is not such a list.
  List<LlamaCompletionChunkToolCall>? parse({required int startIndex}) {
    try {
      final calls = <LlamaCompletionChunkToolCall>[];
      _skipSpace();
      final bracketed = _accept('[');
      _skipSpace();
      while (true) {
        _skipSpace();
        calls.add(_call(startIndex + calls.length));
        _skipSpace();
        if (!_accept(',')) break;
        _skipSpace();
        // Python lists permit one terminal separator, unlike bare call text.
        if (bracketed && _source.startsWith(']', _at)) break;
      }
      if (bracketed) _expect(']');
      _skipSpace();
      return _at == _source.length ? calls : null;
    } on FormatException {
      return null;
    }
  }

  LlamaCompletionChunkToolCall _call(int index) {
    final name = _matchName();
    final schema = _schemas[name];
    if (schema == null) throw const FormatException();
    final properties = schemaProperties(schema);
    _skipSpace();
    _expect('(');
    _skipSpace();
    final arguments = <String, dynamic>{};
    if (!_accept(')')) {
      while (true) {
        _skipSpace();
        final key = _matchName();
        _skipSpace();
        _expect('=');
        _skipSpace();
        if (arguments.containsKey(key)) throw const FormatException();
        final property =
            properties[key] ??
            (_legacyWrappers.contains(key)
                ? schema
                : schema['additionalProperties'] == false
                ? null
                : <String, dynamic>{});
        if (property == null) throw const FormatException();
        arguments[key] = _value(property);
        _skipSpace();
        if (_accept(')')) break;
        _expect(',');
        _skipSpace();
        if (_accept(')')) break;
      }
    }
    if (arguments.length == 1) {
      final entry = arguments.entries.single;
      if (_legacyWrappers.contains(entry.key) &&
          !properties.containsKey(entry.key)) {
        // A declared property owns its name; otherwise preserve the existing
        // whole-argument wrapper syntax using the declared inner types.
        final inner = ToolCallParsingUtils.decodeJsonMapValue(entry.value);
        if (inner != null) {
          arguments
            ..clear()
            ..addAll(inner);
        }
      }
    }
    if (!validateToolSchemaValue(arguments, schema).valid) {
      throw const FormatException();
    }
    return ToolCallParsingUtils.createFunctionToolCall(
      index: index,
      name: name,
      arguments: arguments,
    );
  }

  Object? _value([Map<String, dynamic> schema = const {}]) {
    if (_at >= _source.length) throw const FormatException();
    final alternatives = schema['anyOf'];
    final types = schema['type'];
    if (alternatives is List || types is List) {
      final branches = alternatives is List
          ? [
              for (final branch in alternatives)
                Map<String, dynamic>.from(branch as Map),
            ]
          : [
              for (final type in types as List) {...schema, 'type': type},
            ];
      final nullLiteral = RegExp(
        r'^(?:None|null)(?=\s*[,)}\]])',
      ).hasMatch(_source.substring(_at));
      branches.sort((a, b) {
        int rank(Map<String, dynamic> branch) =>
            nullLiteral && branch['type'] == 'null'
            ? 0
            : schemaResolvesToString(branch)
            ? 1
            : 2;
        return rank(a).compareTo(rank(b));
      });
      final start = _at;
      final depth = _depth;
      for (final branch in branches) {
        _at = start;
        _depth = depth;
        try {
          final value = _value(branch);
          if (validateToolSchemaValue(value, schema).valid) return value;
        } on FormatException {
          // A different declared alternative may accept this emitted value.
        }
      }
      _at = start;
      _depth = depth;
      throw const FormatException();
    }
    final char = _source[_at];
    if (char == '"' || char == "'") return _string(char);
    if (schemaResolvesToString(schema)) return _unquotedString();
    if (char == '[') return _list(schema);
    if (char == '{') return _dict(schema);
    final word = _nameAtStart.matchAsPrefix(_source, _at);
    if (word != null) {
      if (!_literals.containsKey(word[0])) throw const FormatException();
      _at = word.end;
      return _literals[word[0]];
    }
    final number = _numberAtStart.matchAsPrefix(_source, _at);
    if (number == null) throw const FormatException();
    _at = number.end;
    final value = jsonDecode(number[0]!) as num;
    if (!value.isFinite) throw const FormatException();
    return value;
  }

  String _string(String quote) {
    final start = ++_at;
    while (_at < _source.length) {
      final char = _source[_at++];
      if (char == quote) {
        if (_depth > 0 && quote == '"') {
          try {
            return jsonDecode(_source.substring(start - 1, _at)) as String;
          } on FormatException {
            // Python containers may contain copied text that is not JSON.
          }
        }
        return _source.substring(start, _at - 1);
      }
      if (char == r'\') {
        _at++;
      }
    }
    throw const FormatException();
  }

  String _unquotedString() {
    final start = _at;
    final closers = <String>[];
    String? quote;
    while (_at < _source.length) {
      final char = _source[_at];
      if (quote != null) {
        if (char == r'\') {
          _at += 2;
          continue;
        }
        if (char == quote) quote = null;
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if (char == '[' || char == '{' || char == '(') {
        closers.add({'[': ']', '{': '}', '(': ')'}[char]!);
      } else if (closers.isNotEmpty && char == closers.last) {
        closers.removeLast();
      } else if (closers.isEmpty && ',)]}'.contains(char)) {
        break;
      }
      _at++;
    }
    if (quote != null || closers.isNotEmpty || _at > _source.length) {
      throw const FormatException();
    }
    final value = _source.substring(start, _at).trim();
    if (value.isEmpty) throw const FormatException();
    return value;
  }

  List<Object?> _list(Map<String, dynamic> schema) {
    _expect('[');
    _enterContainer();
    _skipSpace();
    final items = <Object?>[];
    if (!_accept(']')) {
      do {
        _skipSpace();
        final itemSchema = schema['items'];
        items.add(
          _value(itemSchema is Map<String, dynamic> ? itemSchema : const {}),
        );
        _skipSpace();
      } while (_accept(','));
      _expect(']');
    }
    _depth--;
    return items;
  }

  Map<String, Object?> _dict(Map<String, dynamic> schema) {
    _expect('{');
    _enterContainer();
    _skipSpace();
    final entries = <String, Object?>{};
    if (!_accept('}')) {
      do {
        _skipSpace();
        if (_at >= _source.length) throw const FormatException();
        final quote = _source[_at];
        if (quote != '"' && quote != "'") throw const FormatException();
        final key = _string(quote);
        _skipSpace();
        _expect(':');
        _skipSpace();
        if (entries.containsKey(key)) throw const FormatException();
        entries[key] = _value(schemaProperties(schema)[key] ?? const {});
        _skipSpace();
      } while (_accept(','));
      _expect('}');
    }
    _depth--;
    return entries;
  }

  void _enterContainer() {
    if (++_depth > _maxValueDepth) throw const FormatException();
  }

  String _matchName() {
    final match = _nameAtStart.matchAsPrefix(_source, _at);
    if (match == null) throw const FormatException();
    _at = match.end;
    return match[0]!;
  }

  void _skipSpace() {
    while (_at < _source.length && ' \t\r\n'.contains(_source[_at])) {
      _at++;
    }
  }

  bool _accept(String char) {
    if (_at < _source.length && _source[_at] == char) {
      _at++;
      return true;
    }
    return false;
  }

  void _expect(String char) {
    if (!_accept(char)) throw const FormatException();
  }
}
