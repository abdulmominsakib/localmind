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

/// Handler for GLM 4.5 format.
///
/// Uses `<|observation|>` as a stop token for tool call observation.
/// Tool call format:
/// `<tool_call>func_name<arg_key>key</arg_key><arg_value>value</arg_value></tool_call>`
///
/// Supports `<think>`/`</think>` for reasoning.
class Glm45Handler extends ChatTemplateHandler
    implements ToolSchemaAwareChatTemplateHandler {
  static final RegExp _toolCallBlockPattern = RegExp(
    r'<tool_call>\s*([\s\S]*?)</tool_call>',
  );
  static final RegExp _argPairPattern = RegExp(
    r'<arg_key>\s*([\s\S]*?)\s*</arg_key>\s*<arg_value>\s*([\s\S]*?)\s*</arg_value>',
  );

  @override
  ChatFormat get format => ChatFormat.glm45;

  @override
  TemplateToolCallSerialization get toolCallSerialization =>
      TemplateToolCallSerialization.normalizeOnly;

  @override
  List<String> get additionalStops => ['<|user|>', '<|observation|>'];

  @override
  List<String> get preservedTokens => const [
    '<|endoftext|>',
    '[MASK]',
    '[gMASK]',
    '[sMASK]',
    '<sop>',
    '<eop>',
    '<|system|>',
    '<|user|>',
    '<|assistant|>',
    '<|observation|>',
    '<|begin_of_image|>',
    '<|end_of_image|>',
    '<|begin_of_video|>',
    '<|end_of_video|>',
    '<|begin_of_audio|>',
    '<|end_of_audio|>',
    '<|begin_of_transcription|>',
    '<|end_of_transcription|>',
    '<|code_prefix|>',
    '<|code_middle|>',
    '<|code_suffix|>',
    '/nothink',
    '<think>',
    '</think>',
    '<tool_call>',
    '</tool_call>',
    '<arg_key>',
    '</arg_key>',
    '<arg_value>',
    '</arg_value>',
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
    var prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': templateMessages(messages, templateSource: templateSource),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '[gMASK]<sop>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '<|user|>',
        'clear_thinking': false,
      },
    );

    // Handle enableThinking post-render logic
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
    // GLM 4.5 tool calls are wrapped in <tool_call> XML blocks.
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
      preservedTokens: hasTools ? preservedTokens : const [],
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: '<tool_call>')]
          : const [],
    );
    return withThoughtClosedForThinkingOff(rendered, closed: thoughtClosed);
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

  /// Parses GLM output using [tools] for schema-directed argument types.
  @override
  ChatParseResult parseWithTools(
    String output, {
    List<ToolDefinition>? tools,
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

    final parseText = isPartial ? _hideIncompleteToolCallBlock(text) : text;
    final extractedFromContent = _extractToolCalls(
      parseText,
      schemas: toolSchemas(tools),
    );
    if (extractedFromContent == null) {
      return ChatParseResult(
        content: parseText.trim(),
        reasoningContent: thinking.reasoning,
      );
    }
    final toolCalls = <LlamaCompletionChunkToolCall>[
      ...extractedFromContent.toolCalls,
    ];
    var contentText = extractedFromContent.remainingContent;

    return ChatParseResult(
      content: contentText.trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    if (tools == null || tools.isEmpty) {
      return null;
    }
    toolSchemas(tools);
    validateFixedArgumentToolSchemas(
      tools,
      format: 'GLM-4.5/Laguna',
      stringEnums: true,
    );

    final toolChoiceRules = <String>[];
    final toolRules = <String>[];

    for (final tool in tools) {
      final toolRuleName = '${ToolCallGrammarUtils.ruleName(tool.name)}-call';
      toolChoiceRules.add(toolRuleName);

      final argParts = <String>[];
      final schema = tool.toJsonSchema();
      final required = schemaRequired(schema);
      for (final parameter in schemaProperties(schema).entries) {
        final paramSchema = parameter.value;
        final paramRuleName =
            '${ToolCallGrammarUtils.ruleName(tool.name)}-arg-'
            '${ToolCallGrammarUtils.ruleName(parameter.key)}';
        final valueRuleName =
            '${ToolCallGrammarUtils.ruleName(tool.name)}-arg-'
            '${ToolCallGrammarUtils.ruleName(parameter.key)}-value';

        final valueRules = _buildValueRules(
          valueRuleName: valueRuleName,
          schema: paramSchema,
        );

        toolRules.addAll(valueRules);
        toolRules.add(
          '$paramRuleName ::= "<arg_key>${_escapeLiteral(parameter.key)}</arg_key>" "\\n"? "<arg_value>" $valueRuleName "</arg_value>"',
        );
        argParts.add(
          required.contains(parameter.key)
              ? 'glm-space $paramRuleName'
              : '(glm-space $paramRuleName)?',
        );
      }

      final argsRule = argParts.join(' ');
      toolRules.add(
        '$toolRuleName ::= "${_escapeLiteral(tool.name)}" $argsRule',
      );
    }

    final toolChoiceRule = 'tool-choice ::= ${toolChoiceRules.join(' | ')}';

    return [
      'root ::= tool-call+',
      'tool-call ::= "\\n"? "<tool_call>" glm-space tool-choice glm-space "</tool_call>" glm-space',
      toolChoiceRule,
      ...toolRules,
      ..._glmUntilAnyLiteralRules('glm-string-raw', _glmProtocolMarkers),
      // GLM-4.6 and Laguna XS put newlines between tags; GLM-4.7 and Laguna
      // S 2.1 put none. Same whitespace rule as llama.cpp's generated parser.
      'glm-space ::= | " " | "\\n"{1,2} [ \\t]{0,20}',
      'space ::= " "?',
      'string ::= "\\"" ([^"\\\\] | "\\\\" .)* "\\""',
      'integer ::= "-"? ("0" | [1-9] [0-9]*)',
      'number ::= "-"? ([0-9] | [1-9] [0-9]*) ("." [0-9]+)? ([eE] [+-]? [0-9]+)?',
      'boolean ::= "true" | "false"',
      'null ::= "null"',
      'value ::= string | number | boolean | null | arr | obj',
      'arr ::= "[" space (value ("," space value)*)? "]"',
      'obj ::= "{" space (string ":" space value ("," space string ":" space value)*)? "}"',
    ].join('\n');
  }

  List<String> _buildValueRules({
    required String valueRuleName,
    required Map<String, dynamic> schema,
  }) {
    final type = schema['type'];
    final enumValues = schema['enum'];

    if (type == 'string') {
      if (enumValues is List && enumValues.isNotEmpty) {
        final rawEnum = enumValues
            .whereType<String>()
            .map((value) => '"${_escapeLiteral(value)}"')
            .join(' | ');
        final jsonEnum = enumValues
            .whereType<String>()
            .map((value) => '"\\"${_escapeLiteral(value)}\\""')
            .join(' | ');
        return ['$valueRuleName ::= $rawEnum | $jsonEnum'];
      }
      return ['$valueRuleName ::= glm-string-raw-0'];
    }

    if (type == 'integer') {
      return ['$valueRuleName ::= integer'];
    }
    if (type == 'number') {
      return ['$valueRuleName ::= number'];
    }

    if (type == 'null') return ['$valueRuleName ::= "null"'];
    if (type == 'boolean') {
      return ['$valueRuleName ::= boolean'];
    }

    if (type == 'array') {
      return ['$valueRuleName ::= arr'];
    }

    if (type == 'object') {
      return ['$valueRuleName ::= obj'];
    }

    return ['$valueRuleName ::= value'];
  }

  String _escapeLiteral(String input) {
    return input.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }

  Object? _decodeArgValue(String value) {
    if (value.isEmpty) {
      return '';
    }

    return ToolCallParsingUtils.decodeJsonValueOrString(value);
  }

  _ExtractedToolCalls? _extractToolCalls(
    String input, {
    required Map<String, Map<String, dynamic>> schemas,
  }) {
    final toolCalls = <LlamaCompletionChunkToolCall>[];
    var remaining = input;

    final matches = _toolCallBlockPattern.allMatches(input);
    for (final match in matches) {
      final block = match.group(1) ?? '';
      final firstArgIdx = block.indexOf('<arg_key>');
      final toolName = firstArgIdx == -1
          ? block.trim()
          : block.substring(0, firstArgIdx).trim();
      if (firstArgIdx >= 0 &&
          block
              .substring(firstArgIdx)
              .replaceAll(_argPairPattern, '')
              .trim()
              .isNotEmpty) {
        return null;
      }
      final schema = schemas[toolName];
      if (schemas.isNotEmpty && schema == null) {
        return null;
      }
      final properties = schema == null ? null : schemaProperties(schema);
      final required = schema == null
          ? const <String>{}
          : schemaRequired(schema);
      final args = <String, dynamic>{};
      for (final argMatch in _argPairPattern.allMatches(block)) {
        final key = (argMatch.group(1) ?? '').trim();
        final rawValue = (argMatch.group(2) ?? '').trim();
        if (key.isEmpty || _containsExactGlmProtocolMarker(rawValue)) {
          return null;
        }
        if (args.containsKey(key)) {
          return null;
        }
        final propertySchema = properties?[key];
        if (properties != null && propertySchema == null) {
          return null;
        }
        if (propertySchema == null) {
          args[key] = _decodeArgValue(rawValue);
        } else {
          final decoded = _decodeGlmSchemaText(rawValue, propertySchema);
          if (!decoded.valid) {
            return null;
          }
          args[key] = decoded.value;
        }
      }

      if (toolName.isEmpty || !args.keys.toSet().containsAll(required)) {
        return null;
      }

      final index = toolCalls.length;
      toolCalls.add(
        ToolCallParsingUtils.createFunctionToolCall(
          index: index,
          name: toolName,
          arguments: args,
        ),
      );

      final fullBlock = match.group(0);
      if (fullBlock != null && fullBlock.isNotEmpty) {
        remaining = remaining.replaceFirst(fullBlock, '');
      }
    }

    if (toolCalls.isNotEmpty && _containsGlmProtocolRemainder(remaining)) {
      return null;
    }

    return _ExtractedToolCalls(
      toolCalls: toolCalls,
      remainingContent: remaining,
    );
  }
}

const _glmProtocolMarkers = [
  '<tool_call>',
  '</tool_call>',
  '<arg_key>',
  '</arg_key>',
  '<arg_value>',
  '</arg_value>',
];

bool _containsExactGlmProtocolMarker(String input) {
  return _glmProtocolMarkers.any(input.contains);
}

bool _containsGlmProtocolRemainder(String input) {
  for (final marker in _glmProtocolMarkers) {
    if (input.contains(marker)) {
      return true;
    }
  }
  for (final marker in _glmProtocolMarkers) {
    for (var length = marker.length - 1; length >= 5; length--) {
      if (input.endsWith(marker.substring(0, length))) {
        return true;
      }
    }
  }
  return false;
}

ToolSchemaValueResult _decodeGlmSchemaText(
  String raw,
  Map<String, dynamic> schema,
) {
  if (schemaResolvesToString(schema)) {
    final decoded = ToolCallParsingUtils.decodeJsonValue(raw);
    return validateToolSchemaValue(decoded is String ? decoded : raw, schema);
  }
  return decodeToolSchemaText(raw, schema);
}

List<String> _glmUntilAnyLiteralRules(
  String ruleBase,
  List<String> delimiters,
) {
  final markers = delimiters
      .map(
        (delimiter) =>
            delimiter.runes.map(String.fromCharCode).toList(growable: false),
      )
      .toList(growable: false);
  final prefixes = <String>{''};
  for (final delimiter in delimiters) {
    for (var length = 1; length < delimiter.length; length++) {
      prefixes.add(delimiter.substring(0, length));
    }
  }
  final states = prefixes.toList(growable: false)
    ..sort((left, right) {
      final byLength = left.length.compareTo(right.length);
      return byLength != 0 ? byLength : left.compareTo(right);
    });
  final stateIndexes = <String, int>{
    for (var index = 0; index < states.length; index++) states[index]: index,
  };
  final alphabet = markers
      .expand((marker) => marker)
      .toSet()
      .toList(growable: false);
  String charClass(Iterable<String> characters) =>
      characters.map(_escapeGlmCharacterClass).join();
  final lines = <String>[];
  for (var state = 0; state < states.length; state++) {
    // llama.cpp keeps one grammar stack per alternative and checks every
    // vocabulary token against each one, so characters are grouped by target
    // state and every return to the start state shares the negated class.
    final specific = <String>[];
    final charactersByTarget = <int, List<String>>{};
    for (final character in alphabet) {
      final candidate = '${states[state]}$character';
      if (delimiters.any(candidate.endsWith)) {
        specific.add(character);
        continue;
      }
      final nextState = states
          .where(candidate.endsWith)
          .fold<String>(
            '',
            (longest, prefix) =>
                prefix.length > longest.length ? prefix : longest,
          );
      final next = stateIndexes[nextState]!;
      if (next == 0) {
        continue;
      }
      specific.add(character);
      charactersByTarget.putIfAbsent(next, () => []).add(character);
    }
    final alternatives = [
      for (final MapEntry(key: next, value: characters)
          in charactersByTarget.entries)
        '[${charClass(characters)}] $ruleBase-$next',
      '[^${charClass(specific)}] $ruleBase-0',
    ];
    lines.add('$ruleBase-$state ::= (${alternatives.join(' | ')})?');
  }
  return lines;
}

String _escapeGlmCharacterClass(String character) {
  return switch (character) {
    r'\' => r'\\',
    ']' => r'\]',
    '-' => r'\-',
    '^' => r'\^',
    _ => character,
  };
}

String _hideIncompleteToolCallBlock(String input) {
  const toolCallMarker = '<tool_call>';
  final open = input.lastIndexOf(toolCallMarker);
  final close = input.lastIndexOf('</tool_call>');
  if (open > close) {
    return input.substring(0, open);
  }
  for (final marker in const [
    toolCallMarker,
    '</tool_call>',
    '<arg_key>',
    '</arg_key>',
    '<arg_value>',
    '</arg_value>',
  ]) {
    for (var length = 1; length < marker.length; length++) {
      if (input.endsWith(marker.substring(0, length))) {
        return input.substring(0, input.length - length);
      }
    }
  }
  return input;
}

class _ExtractedToolCalls {
  final List<LlamaCompletionChunkToolCall> toolCalls;
  final String remainingContent;

  const _ExtractedToolCalls({
    required this.toolCalls,
    required this.remainingContent,
  });
}
