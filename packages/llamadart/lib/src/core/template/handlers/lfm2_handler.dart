import 'package:dinja/dinja.dart';

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

/// Handler for LFM2 (Liquid Foundation Model 2) format.
///
/// Uses `<|tool_call_start|>` / `<|tool_call_end|>` special tokens for tool calls,
/// and `<|tool_list_start|>` / `<|tool_list_end|>` for tool definitions.
class Lfm2Handler extends ChatTemplateHandler {
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
    final hasForceJsonMarker = _shouldConstrainWithJsonTools(messages);
    final shouldConstrainWithJsonTools =
        hasTools && (hasForceJsonMarker || toolChoiceRequired);
    final effectiveMessages = hasForceJsonMarker
        ? _stripForceJsonSchemaMarker(messages)
        : messages;

    final prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': effectiveMessages.map((m) => m.toJson()).toList(),
        'add_generation_prompt': addAssistant,
        'tools': _serializeToolsForTemplate(tools),
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '',
      },
    );

    return LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: shouldConstrainWithJsonTools ? buildGrammar(tools) : null,
      grammarLazy: shouldConstrainWithJsonTools && !toolChoiceRequired,
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
          : [],
    );
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

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    var contentText = output;

    // LFM2 format:
    // <|tool_call_start|>[{"name":"fn","arguments":{...}}]<|tool_call_end|>
    final toolCallRegex = RegExp(
      r'<\|tool_call_start\|>\s*(.*?)\s*<\|tool_call_end\|>',
      dotAll: true,
    );

    final matches = toolCallRegex.allMatches(output);
    for (var i = 0; i < matches.length; i++) {
      final match = matches.elementAt(i);
      final payload = match.group(1)!;
      final decoded = ToolCallParsingUtils.decodeJsonValue(payload);
      final parsedCalls =
          ToolCallParsingUtils.parseToolCallArray(
            decoded,
            startIndex: toolCalls.length,
            failOnInvalidItem: false,
            assignFallbackIds: true,
          ) ??
          _parsePythonStyleToolCallList(payload, startIndex: toolCalls.length);
      if (parsedCalls != null) {
        toolCalls.addAll(parsedCalls);
      }
      contentText = contentText.replaceAll(match.group(0)!, '');
    }

    final thinking = extractThinking(
      contentText,
      thinkingForcedOpen: thinkingForcedOpen,
    );

    return ChatParseResult(
      content: thinking.content.trim(),
      reasoningContent: thinking.reasoning,
      toolCalls: toolCalls,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return ToolCallGrammarUtils.buildWrappedArrayGrammar(
      tools: tools,
      prefix: '<|tool_call_start|>',
      suffix: '<|tool_call_end|>',
      idKey: 'id',
      allowParallelToolCalls: false,
    );
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
