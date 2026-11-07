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
import '../thinking_utils.dart';
import '../tool_call_grammar_utils.dart';
import '../tool_call_parsing_utils.dart';

/// Handler for EXAONE MoE format.
///
/// EXAONE MoE uses `<think>` tags and `<tool_call>{...}</tool_call>` blocks.
class ExaoneMoeHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.exaoneMoe;

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
    final template = Template(templateSource);
    var prompt = renderTemplate(
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

    var thinkingForcedOpen = false;
    if (isThinkingForcedOpen(prompt)) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}</think>';
      } else {
        thinkingForcedOpen = true;
      }
    }

    final hasTools = tools != null && tools.isNotEmpty;
    final toolChoice = metadata[internalToolChoiceMetadataKey];
    final toolChoiceRequired = toolChoice == ToolChoice.required.name;
    final parallelToolCalls =
        metadata[internalParallelToolCallsMetadataKey] == 'true';
    return LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: _buildGrammarWithOptions(
        tools,
        parallelToolCalls: parallelToolCalls,
      ),
      grammarLazy: hasTools && !toolChoiceRequired,
      thinkingForcedOpen: thinkingForcedOpen,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: '<tool_call>')]
          : [],
    );
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    final shouldTreatAsContent =
        thinkingForcedOpen && !isPartial && !output.contains('</think>');

    final extracted = shouldTreatAsContent
        ? (content: output, reasoning: null)
        : extractThinking(output, thinkingForcedOpen: thinkingForcedOpen);

    if (!parseToolCalls) {
      return ChatParseResult(
        content: extracted.content.trim(),
        reasoningContent: extracted.reasoning,
      );
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    var contentText = extracted.content;

    final regex = RegExp(
      r'<tool_call[^>]*>([\s\S]*?)</tool_call>',
      dotAll: true,
    );
    final matches = regex.allMatches(extracted.content);

    for (final match in matches) {
      final body = match.group(1);
      if (body == null) {
        continue;
      }

      final payload = _stripCodeFence(body.trim());

      final decoded = ToolCallParsingUtils.decodeJsonValue(payload);
      final toolCall = _toToolCall(decoded, toolCalls.length);
      if (toolCall == null) {
        continue;
      }
      toolCalls.add(toolCall);
      contentText = contentText.replaceFirst(match.group(0)!, '');
    }

    return ChatParseResult(
      content: contentText.trim(),
      reasoningContent: extracted.reasoning,
      toolCalls: toolCalls,
    );
  }

  LlamaCompletionChunkToolCall? _toToolCall(Object? value, int index) {
    final map = ToolCallParsingUtils.coerceMap(value);
    if (map == null) {
      return null;
    }

    String? name;
    String? id;
    Object? arguments;

    if (map['name'] is String) {
      name = map['name'] as String;
      arguments = map['arguments'];
      id = map['id'] as String?;
    } else {
      final function = ToolCallParsingUtils.coerceMap(map['function']);
      if (function == null) {
        return null;
      }
      name = function['name'] as String?;
      arguments = function['arguments'];
      id = map['id'] as String?;
    }

    if (name == null || name.isEmpty) {
      return null;
    }

    return ToolCallParsingUtils.createFunctionToolCall(
      index: index,
      name: name,
      id: id,
      arguments: arguments ?? <String, dynamic>{},
      type: (map['type'] as String?) ?? 'function',
    );
  }

  String _stripCodeFence(String value) {
    var text = value;
    if (text.startsWith('```json')) {
      text = text.substring('```json'.length).trim();
    } else if (text.startsWith('```')) {
      text = text.substring('```'.length).trim();
    }

    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3).trim();
    }
    return text;
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return _buildGrammarWithOptions(tools, parallelToolCalls: true);
  }

  String? _buildGrammarWithOptions(
    List<ToolDefinition>? tools, {
    required bool parallelToolCalls,
  }) {
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
          '"{" space "\\"name\\"" space ":" space ${ToolCallGrammarUtils.literal(tool.name)} space "," space "\\"arguments\\"" space ":" space $argsRule "}" space';
      toolRuleNames.add(ruleName);
    }

    final buffer = StringBuffer()
      ..writeln(
        'tool-call ::= "<tool_call>" space tool-choice "</tool_call>" space',
      )
      ..writeln('tool-choice ::= ${toolRuleNames.join(' | ')}')
      ..writeln('root ::= ${parallelToolCalls ? 'tool-call+' : 'tool-call'}');

    final otherRules = converter.rules.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in otherRules) {
      if (entry.key == 'root' ||
          entry.key == 'tool-call' ||
          entry.key == 'tool-choice') {
        continue;
      }
      buffer.writeln('${entry.key} ::= ${entry.value}');
    }

    return buffer.toString();
  }
}
