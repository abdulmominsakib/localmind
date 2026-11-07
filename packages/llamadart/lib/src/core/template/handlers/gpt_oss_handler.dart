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
import '../template_internal_metadata.dart';
import '../tool_call_grammar_utils.dart';
import '../tool_call_parsing_utils.dart';

/// Handler for GPT-OSS format.
///
/// GPT-OSS responses are structured in `<|start|>assistant` message frames with
/// channel headers (`analysis`, `commentary`, `final`) and optional
/// `to=functions.<name>` tool-routing headers.
class GptOssHandler extends ChatTemplateHandler {
  static const String _assistantStart = '<|start|>assistant';
  static const String _messageTag = '<|message|>';
  static const String _endTag = '<|end|>';
  static const List<String> _gptOssPreservedTokens = <String>[
    '<|channel|>',
    '<|constrain|>',
    '<|message|>',
    '<|start|>',
    '<|end|>',
  ];

  @override
  ChatFormat get format => ChatFormat.gptOss;

  @override
  List<String> get additionalStops => [];

  @override
  LlamaChatTemplateResult render({
    required String templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    bool enableThinking = true,
  }) {
    final renderedMessages = messages.map((m) {
      final json = m.toJson();
      final reasoning = json['reasoning_content'];
      final toolCalls = json['tool_calls'];
      if (reasoning is String && toolCalls is List && toolCalls.isNotEmpty) {
        json['thinking'] = reasoning;
      }
      return json;
    }).toList();

    final template = Template(templateSource);
    final prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': renderedMessages,
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
      },
    );

    final hasTools = tools != null && tools.isNotEmpty;
    final toolChoice = metadata[internalToolChoiceMetadataKey];
    final toolChoiceRequired = toolChoice == ToolChoice.required.name;
    return LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: _buildGrammarWithOptions(
        tools,
        toolCallsRequired: toolChoiceRequired,
      ),
      grammarLazy: hasTools && !toolChoiceRequired,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      preservedTokens: _gptOssPreservedTokens,
      grammarTriggers: hasTools
          ? const <GrammarTrigger>[
              GrammarTrigger(type: 0, value: '<|channel|>commentary'),
              GrammarTrigger(type: 0, value: '<|channel|>analysis'),
              GrammarTrigger(
                type: 0,
                value: '<|start|>assistant to=functions.',
              ),
            ]
          : const <GrammarTrigger>[],
    );
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    final reasoningParts = <String>[];
    final contentParts = <String>[];
    final toolCalls = <LlamaCompletionChunkToolCall>[];

    var cursor = 0;
    while (cursor < output.length) {
      final start = output.indexOf(_assistantStart, cursor);
      if (start == -1) {
        final trailing = output.substring(cursor).trim();
        if (trailing.isNotEmpty) {
          contentParts.add(trailing);
        }
        break;
      }

      if (start > cursor) {
        final prelude = output.substring(cursor, start).trim();
        if (prelude.isNotEmpty) {
          contentParts.add(prelude);
        }
      }

      final headerStart = start + _assistantStart.length;
      final messageIdx = output.indexOf(_messageTag, headerStart);
      if (messageIdx == -1) {
        final trailing = output.substring(start).trim();
        if (trailing.isNotEmpty) {
          contentParts.add(trailing);
        }
        break;
      }

      final header = output.substring(headerStart, messageIdx);
      final bodyStart = messageIdx + _messageTag.length;
      final endIdx = output.indexOf(_endTag, bodyStart);

      final body = endIdx == -1
          ? output.substring(bodyStart)
          : output.substring(bodyStart, endIdx);

      _consumeFrame(
        header: header,
        body: body,
        parseToolCalls: parseToolCalls,
        reasoningParts: reasoningParts,
        contentParts: contentParts,
        toolCalls: toolCalls,
      );

      if (endIdx == -1) {
        break;
      }
      cursor = endIdx + _endTag.length;
    }

    return ChatParseResult(
      content: contentParts.join('\n').trim(),
      reasoningContent: reasoningParts.isEmpty
          ? null
          : reasoningParts.join('\n'),
      toolCalls: toolCalls,
    );
  }

  void _consumeFrame({
    required String header,
    required String body,
    required bool parseToolCalls,
    required List<String> reasoningParts,
    required List<String> contentParts,
    required List<LlamaCompletionChunkToolCall> toolCalls,
  }) {
    final normalizedBody = body.trim();
    if (normalizedBody.isEmpty) {
      return;
    }

    final channel = _extractChannel(header);
    final functionName = _extractFunctionRecipient(header);

    if (functionName != null && parseToolCalls) {
      toolCalls.add(
        ToolCallParsingUtils.createFunctionToolCall(
          index: toolCalls.length,
          name: functionName,
          arguments: _normalizeArguments(normalizedBody),
        ),
      );
      return;
    }

    if (channel == 'analysis') {
      reasoningParts.add(normalizedBody);
      return;
    }

    if (channel == 'final' || channel == 'commentary') {
      contentParts.add(normalizedBody);
      return;
    }

    contentParts.add(normalizedBody);
  }

  String? _extractChannel(String header) {
    final match = RegExp(r'<\|channel\|>([a-zA-Z0-9_-]+)').firstMatch(header);
    return match?.group(1);
  }

  String? _extractFunctionRecipient(String header) {
    final match = RegExp(r'to=functions\.([^<\s]+)').firstMatch(header);
    return match?.group(1);
  }

  String _normalizeArguments(String rawBody) {
    return ToolCallParsingUtils.normalizeJsonArguments(
      rawBody,
      trimInput: true,
      wrapScalarsAsValue: true,
      emptyFallback: '{}',
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return _buildGrammarWithOptions(tools, toolCallsRequired: false);
  }

  String? _buildGrammarWithOptions(
    List<ToolDefinition>? tools, {
    required bool toolCallsRequired,
  }) {
    if (tools == null || tools.isEmpty) {
      return null;
    }

    final converter = JsonSchemaConverter();
    final roleRules = <String>[];
    final channelRules = <String>[];

    converter.rules['channel'] =
        '${ToolCallGrammarUtils.literal('commentary')} | ${ToolCallGrammarUtils.literal('analysis')}';

    for (var i = 0; i < tools.length; i++) {
      final tool = tools[i];
      final schema = tool.toJsonSchema();
      converter.resolveRefs(schema, schema);
      final argsRule = converter.visit(schema, 'tool-$i-args');

      final roleRule = 'tool-$i-role-call';
      converter.rules[roleRule] =
          '${ToolCallGrammarUtils.literal('<|start|>assistant to=functions.${tool.name}<|channel|>')} channel ${ToolCallGrammarUtils.literal('<|message|>')} space $argsRule ${ToolCallGrammarUtils.literal('<|end|>')}';
      roleRules.add(roleRule);

      final channelRule = 'tool-$i-channel-call';
      converter.rules[channelRule] =
          '${ToolCallGrammarUtils.literal('<|channel|>')} channel ${ToolCallGrammarUtils.literal(' to=functions.${tool.name}<|message|>')} space $argsRule ${ToolCallGrammarUtils.literal('<|end|>')}';
      channelRules.add(channelRule);
    }

    final buffer = StringBuffer()
      ..writeln('tool-call-role ::= ${roleRules.join(' | ')}')
      ..writeln('tool-call-channel ::= ${channelRules.join(' | ')}');

    if (toolCallsRequired) {
      buffer.writeln('root ::= tool-call-role | tool-call-channel');
    } else {
      buffer.writeln('root ::= tool-call-role | tool-call-channel');
    }

    final otherRules = converter.rules.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in otherRules) {
      if (entry.key == 'root' ||
          entry.key == 'tool-call-role' ||
          entry.key == 'tool-call-channel') {
        continue;
      }
      buffer.writeln('${entry.key} ::= ${entry.value}');
    }

    return buffer.toString();
  }
}
