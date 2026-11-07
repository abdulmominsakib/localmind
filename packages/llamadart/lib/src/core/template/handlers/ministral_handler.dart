import 'package:dinja/dinja.dart';

import '../../grammar/json_schema_converter.dart';
import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/inference/tool_choice.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../peg_parser_builder.dart';
import '../template_internal_metadata.dart';
import '../thinking_utils.dart';
import '../tool_call_grammar_utils.dart';
import '../tool_call_parsing_utils.dart';

/// Handler for Ministral format.
///
/// Uses `[TOOL_CALLS]name[ARGS]{...}` tool call records with optional
/// `[THINK]...[/THINK]` reasoning blocks.
class MinistralHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.ministral;

  @override
  String get thinkingStartTag => '[THINK]';

  @override
  String get thinkingEndTag => '[/THINK]';

  @override
  List<String> get additionalStops => ['</s>'];

  @override
  List<String> get preservedTokens => const [
    '[THINK]',
    '[/THINK]',
    '[TOOL_CALLS]',
    '[ARGS]',
  ];

  @override
  List<String> getStops({bool hasTools = false, bool enableThinking = true}) {
    return [...additionalStops, if (hasTools) '[TOOL_CALLS]'];
  }

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
        'messages': _serializeMessages(messages),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((tool) => tool.toJson()).toList(growable: false),
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
      },
    );

    var thinkingForcedOpen = false;
    if (isThinkingForcedOpen(prompt, startTag: thinkingStartTag)) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}$thinkingEndTag\n';
      } else {
        thinkingForcedOpen = true;
      }
    }

    final hasTools = tools != null && tools.isNotEmpty;
    final toolChoice = metadata[internalToolChoiceMetadataKey];
    final toolChoiceNone = toolChoice == ToolChoice.none.name;
    final toolChoiceRequired = toolChoice == ToolChoice.required.name;
    final parallelToolCalls =
        metadata[internalParallelToolCallsMetadataKey] == 'true';
    final allowToolCalls = hasTools && !toolChoiceNone;
    final parser = _buildParser(
      tools,
      allowToolCalls: allowToolCalls,
      minToolCalls: toolChoiceRequired ? 1 : 0,
      maxToolCalls: parallelToolCalls ? -1 : 1,
    );
    return LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: allowToolCalls ? buildGrammar(tools) : null,
      grammarLazy: allowToolCalls && !toolChoiceRequired,
      thinkingForcedOpen: thinkingForcedOpen,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      preservedTokens: preservedTokens,
      grammarTriggers: allowToolCalls
          ? [const GrammarTrigger(type: 0, value: '[TOOL_CALLS]')]
          : [],
      parser: parser,
    );
  }

  String _buildParser(
    List<ToolDefinition>? tools, {
    required bool allowToolCalls,
    required int minToolCalls,
    required int maxToolCalls,
  }) {
    final builder = ChatPegNativeBuilder();
    final hasTools = tools != null && tools.isNotEmpty;

    final reasoning = builder.optional(
      builder.literal('[THINK]') +
          builder.reasoning(builder.until('[/THINK]')) +
          builder.literal('[/THINK]'),
    );

    if (!hasTools || !allowToolCalls) {
      builder.setRoot(reasoning + builder.content(builder.rest()));
      return builder.save();
    }

    var toolChoice = builder.choice(<PegParser>[]);
    for (final tool in tools) {
      final name = tool.name;
      final schema = tool.toJsonSchema();

      final toolRule = builder.rule(
        'tool-$name',
        builder.toolOpen(builder.toolName(builder.literal(name)) + '[ARGS]') +
            builder.toolArgs(
              builder.schema(builder.json(), 'tool-$name-schema', schema),
            ),
      );
      toolChoice |= toolRule;
    }

    final toolCalls = builder.triggerRule(
      'tool-call',
      builder.repeat(
        builder.literal('[TOOL_CALLS]') + toolChoice,
        minToolCalls,
        maxToolCalls,
      ),
    );

    builder.setRoot(
      reasoning + builder.content(builder.until('[TOOL_CALLS]')) + toolCalls,
    );
    return builder.save();
  }

  List<Map<String, dynamic>> _serializeMessages(
    List<LlamaChatMessage> messages,
  ) {
    return messages
        .map((message) {
          final json = message.toJson();
          final role = json['role'];
          if (role != 'system' && role != 'assistant') {
            return json;
          }

          final blocks = <Map<String, dynamic>>[];

          final reasoning = json['reasoning_content'];
          if (reasoning is String && reasoning.isNotEmpty) {
            blocks.add({'type': 'thinking', 'thinking': reasoning});
          }

          final content = json['content'];
          if (content is String) {
            if (content.isNotEmpty) {
              blocks.add({'type': 'text', 'text': content});
            }
          } else if (content is List) {
            for (final item in content) {
              final block = ToolCallParsingUtils.coerceMap(item);
              if (block != null) {
                blocks.add(block);
              }
            }
          }

          if (blocks.isNotEmpty) {
            json['content'] = blocks;
          }
          json.remove('reasoning_content');
          return json;
        })
        .toList(growable: false);
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
      startTag: thinkingStartTag,
      endTag: thinkingEndTag,
    );
    final text = thinking.content;
    final trimmed = text.trim();

    if (!parseToolCalls) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    if (!trimmed.contains('[TOOL_CALLS]')) {
      try {
        final parsedBareArray = _parseToolCallArray(trimmed);
        if (parsedBareArray.isNotEmpty) {
          return ChatParseResult(
            content: '',
            reasoningContent: thinking.reasoning,
            toolCalls: parsedBareArray,
          );
        }
      } catch (_) {
        // Not a strict JSON array tool-call payload.
      }

      final bareNameJsonCall = _parseNameJsonSingleCall(trimmed);
      if (bareNameJsonCall != null) {
        return ChatParseResult(
          content: '',
          reasoningContent: thinking.reasoning,
          toolCalls: [bareNameJsonCall],
        );
      }

      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    final markerIdx = trimmed.indexOf('[TOOL_CALLS]');
    final contentBefore = trimmed.substring(0, markerIdx).trim();
    final afterMarker = trimmed.substring(markerIdx).trim();

    final argsCalls = _parseArgsToolCalls(afterMarker);
    if (argsCalls.isNotEmpty) {
      return ChatParseResult(
        content: contentBefore,
        reasoningContent: thinking.reasoning,
        toolCalls: argsCalls,
      );
    }

    final jsonArrayPayload = afterMarker
        .substring('[TOOL_CALLS]'.length)
        .trim();
    try {
      final toolCalls = _parseToolCallArray(jsonArrayPayload);
      if (toolCalls.isNotEmpty) {
        return ChatParseResult(
          content: contentBefore,
          reasoningContent: thinking.reasoning,
          toolCalls: toolCalls,
        );
      }
    } catch (_) {
      // Not a JSON-array tool-call payload.
    }

    final markerlessNameJsonCall = _parseNameJsonSingleCall(jsonArrayPayload);
    if (markerlessNameJsonCall != null) {
      return ChatParseResult(
        content: contentBefore,
        reasoningContent: thinking.reasoning,
        toolCalls: [markerlessNameJsonCall],
      );
    }

    return ChatParseResult(
      content: trimmed,
      reasoningContent: thinking.reasoning,
    );
  }

  List<LlamaCompletionChunkToolCall> _parseArgsToolCalls(String text) {
    final toolCalls = <LlamaCompletionChunkToolCall>[];
    final pattern = RegExp(r'(?:\[TOOL_CALLS\]\s*)?([A-Za-z0-9_\.-]+)\[ARGS\]');

    for (final match in pattern.allMatches(text)) {
      final name = match.group(1);
      if (name == null || name.isEmpty) {
        continue;
      }

      final jsonObj = _extractJsonObject(text, match.end);
      if (jsonObj == null) {
        continue;
      }

      final index = toolCalls.length;
      toolCalls.add(
        ToolCallParsingUtils.createFunctionToolCall(
          index: index,
          name: name,
          arguments: jsonObj,
        ),
      );
    }

    return toolCalls;
  }

  String? _extractJsonObject(String input, int offset) {
    var start = offset;
    while (start < input.length) {
      final ch = input[start];
      if (ch != ' ' && ch != '\n' && ch != '\r' && ch != '\t') {
        break;
      }
      start++;
    }
    if (start >= input.length || input[start] != '{') {
      return null;
    }

    final jsonSlice = ToolCallParsingUtils.extractLeadingJsonValue(
      input,
      start,
    );
    if (jsonSlice == null || jsonSlice.value is! Map) {
      return null;
    }

    return input.substring(start, jsonSlice.end);
  }

  List<LlamaCompletionChunkToolCall> _parseToolCallArray(String jsonText) {
    final decoded = ToolCallParsingUtils.decodeJsonValue(jsonText);
    return ToolCallParsingUtils.parseToolCallArray(
          decoded,
          assignFallbackIds: true,
          failOnInvalidItem: false,
        ) ??
        const <LlamaCompletionChunkToolCall>[];
  }

  LlamaCompletionChunkToolCall? _parseNameJsonSingleCall(String text) {
    final match = RegExp(r'^([A-Za-z0-9_\.-]+)\s*').firstMatch(text);
    if (match == null) {
      return null;
    }

    final name = match.group(1);
    if (name == null || name.isEmpty) {
      return null;
    }

    final jsonObj = _extractJsonObject(text, match.end);
    if (jsonObj == null) {
      return null;
    }

    final jsonStart = text.indexOf(jsonObj, match.end);
    if (jsonStart == -1) {
      return null;
    }

    final suffix = text.substring(jsonStart + jsonObj.length).trim();
    if (suffix.isNotEmpty) {
      return null;
    }

    return ToolCallParsingUtils.createFunctionToolCall(
      index: 0,
      name: name,
      arguments: jsonObj,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    if (tools == null || tools.isEmpty) {
      return null;
    }

    final converter = JsonSchemaConverter();
    final toolRuleNames = <String>[];

    for (var i = 0; i < tools.length; i++) {
      final tool = tools[i];
      final schema = tool.toJsonSchema();
      converter.resolveRefs(schema, schema);
      final argsRule = converter.visit(schema, 'tool-$i-args');

      final ruleName = 'tool-$i-call';
      converter.rules[ruleName] =
          '${ToolCallGrammarUtils.literal('${tool.name}[ARGS]')} $argsRule';
      toolRuleNames.add(ruleName);
    }

    final buffer = StringBuffer()
      ..writeln(
        'root ::= "[TOOL_CALLS]" space tool-call (space "[TOOL_CALLS]" space tool-call)* space',
      )
      ..writeln('tool-call ::= ${toolRuleNames.join(' | ')}');

    final otherRules = converter.rules.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in otherRules) {
      if (entry.key == 'root' || entry.key == 'tool-call') {
        continue;
      }
      buffer.writeln('${entry.key} ::= ${entry.value}');
    }

    return buffer.toString();
  }
}
