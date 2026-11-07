import 'package:dinja/dinja.dart';

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
import '../tool_call_parsing_utils.dart';

/// Handler for Command R7B format.
///
/// Uses `<|START_ACTION|>` / `<|END_ACTION|>` for tool calls.
/// Tool call format: `<|START_ACTION|>{"tool_name": "fn", "parameters": {...}}<|END_ACTION|>`
///
/// Supports thinking with `<|START_THINKING|>` / `<|END_THINKING|>`.
class CommandR7BHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.commandR7B;

  @override
  TemplateToolCallSerialization get toolCallSerialization =>
      TemplateToolCallSerialization.normalizeOnly;

  @override
  String get thinkingStartTag => '<|START_THINKING|>';

  @override
  String get thinkingEndTag => '<|END_THINKING|>';

  @override
  List<String> get additionalStops => ['<|END_RESPONSE|>'];

  @override
  List<String> getStops({bool hasTools = false, bool enableThinking = true}) {
    return [...additionalStops, if (hasTools) '<|END_ACTION|>'];
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
        'messages': templateMessages(messages),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'bos_token':
            metadata['tokenizer.ggml.bos_token'] ?? '<|START_OF_TURN_TOKEN|>',
        'eos_token':
            metadata['tokenizer.ggml.eos_token'] ?? '<|END_OF_TURN_TOKEN|>',
        'enable_thinking': enableThinking,
        'reasoning': enableThinking,
        'skip_thinking': !enableThinking,
      },
    );

    // Handle enableThinking post-render logic
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
    final toolChoiceRequired = toolChoice == ToolChoice.required.name;
    return LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: buildGrammar(tools),
      grammarLazy: hasTools && !toolChoiceRequired,
      thinkingForcedOpen: thinkingForcedOpen,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: '<|START_ACTION|>')]
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
    final thinking = extractThinking(
      output,
      thinkingForcedOpen: thinkingForcedOpen,
      startTag: thinkingStartTag,
      endTag: thinkingEndTag,
    );
    final text = thinking.content;

    const startAction = '<|START_ACTION|>';
    const endAction = '<|END_ACTION|>';
    const startText = '<|START_TEXT|>';
    const endText = '<|END_TEXT|>';
    const startResponse = '<|START_RESPONSE|>';
    const endResponse = '<|END_RESPONSE|>';

    final textStart = text.indexOf(startText);
    if (textStart != -1) {
      final prelude = text.substring(0, textStart);
      final bodyStart = textStart + startText.length;
      final textEnd = text.indexOf(endText, bodyStart);
      final bodyEnd = textEnd == -1 ? text.length : textEnd;
      final trailing = textEnd == -1
          ? ''
          : text.substring(textEnd + endText.length).trim();
      if (trailing.isNotEmpty) {
        return ChatParseResult(
          content: text.trim(),
          reasoningContent: thinking.reasoning,
        );
      }

      return ChatParseResult(
        content: '$prelude${text.substring(bodyStart, bodyEnd)}'.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    if (!parseToolCalls) {
      return ChatParseResult(
        content: text.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    final actionStart = text.indexOf(startAction);
    if (actionStart != -1) {
      final prelude = text.substring(0, actionStart);
      final afterStart = text.substring(actionStart + startAction.length);
      final jsonSlice = ToolCallParsingUtils.extractLeadingJsonValue(
        afterStart,
        0,
      );
      if (jsonSlice == null) {
        return ChatParseResult(
          content: text.trim(),
          reasoningContent: thinking.reasoning,
        );
      }

      final decodedCalls = jsonSlice.value is List
          ? jsonSlice.value
          : <Object?>[jsonSlice.value];

      final toolCalls = ToolCallParsingUtils.parseToolCallArray(
        decodedCalls,
        nameKeys: const <String>['tool_name'],
        argumentKeys: const <String>['parameters'],
        idKeys: const <String>['tool_call_id'],
        assignFallbackIds: false,
      );
      if (toolCalls == null) {
        return ChatParseResult(
          content: text.trim(),
          reasoningContent: thinking.reasoning,
        );
      }

      final actionEndOffset = jsonSlice.end;
      var endCursor = actionEndOffset;
      while (endCursor < afterStart.length &&
          afterStart.codeUnitAt(endCursor) <= 0x20) {
        endCursor++;
      }
      if (!afterStart.startsWith(endAction, endCursor)) {
        return ChatParseResult(
          content: text.trim(),
          reasoningContent: thinking.reasoning,
        );
      }

      final trailing = afterStart.substring(endCursor + endAction.length);
      if (trailing.isNotEmpty) {
        return ChatParseResult(
          content: text.trim(),
          reasoningContent: thinking.reasoning,
        );
      }

      return ChatParseResult(
        content: prelude.trim(),
        reasoningContent: thinking.reasoning,
        toolCalls: toolCalls,
      );
    }

    final bareToolCalls = _parseBareActionPayload(text.trim());
    if (bareToolCalls != null) {
      return ChatParseResult(
        content: bareToolCalls.content,
        reasoningContent: thinking.reasoning,
        toolCalls: bareToolCalls.toolCalls,
      );
    }

    final responseStart = text.indexOf(startResponse);
    if (responseStart != -1) {
      final prelude = text.substring(0, responseStart);
      final responseBodyStart = responseStart + startResponse.length;
      final responseEnd = text.indexOf(endResponse, responseBodyStart);
      if (responseEnd == -1) {
        return ChatParseResult(
          content: text.trim(),
          reasoningContent: thinking.reasoning,
        );
      }

      final trailing = text.substring(responseEnd + endResponse.length);
      if (trailing.isNotEmpty) {
        return ChatParseResult(
          content: text.trim(),
          reasoningContent: thinking.reasoning,
        );
      }

      final responseBody = text.substring(responseBodyStart, responseEnd);
      return ChatParseResult(
        content: '$prelude$responseBody'.trim(),
        reasoningContent: thinking.reasoning,
      );
    }

    return ChatParseResult(
      content: text.trim(),
      reasoningContent: thinking.reasoning,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    if (tools == null || tools.isEmpty) return null;

    // Build GBNF for Command R7B style tool calls
    final toolRules = <String>[];
    final toolChoices = <String>[];

    for (final tool in tools) {
      final ruleName = _sanitizeName(tool.name);
      toolChoices.add('$ruleName-call');

      final schema = tool.toJsonSchema();
      final argsRule = _jsonSchemaToGbnf(schema, '$ruleName-args');
      toolRules.add(argsRule);
      toolRules.add(
        '$ruleName-call ::= "{\\"tool_name\\": \\"${tool.name}\\", \\"parameters\\": " $ruleName-args "}"',
      );
    }

    final choiceRule = 'tool-choice ::= ${toolChoices.join(' | ')}';
    final actionArray =
        'action-array ::= "[" space tool-choice ("," space tool-choice)* space "]"';
    final root =
        'root ::= "<|START_ACTION|>" space action-array space "<|END_ACTION|>" | action-array';

    return [
      root,
      actionArray,
      choiceRule,
      ...toolRules,
      _commonGbnfRules(),
    ].join('\n');
  }

  _CommandBareActionPayload? _parseBareActionPayload(String text) {
    if (text.isEmpty) {
      return null;
    }

    var searchEnd = text.length;
    while (searchEnd > 0) {
      final markerStart = text.lastIndexOf('[', searchEnd - 1);
      if (markerStart == -1) {
        break;
      }

      final jsonSlice = ToolCallParsingUtils.extractLeadingJsonValue(
        text,
        markerStart,
      );
      searchEnd = markerStart;
      if (jsonSlice == null) {
        continue;
      }

      if (text.substring(jsonSlice.end).trim().isNotEmpty) {
        continue;
      }

      final decodedCalls = jsonSlice.value is List
          ? jsonSlice.value
          : <Object?>[jsonSlice.value];
      final calls = ToolCallParsingUtils.parseToolCallArray(
        decodedCalls,
        nameKeys: const <String>['tool_name'],
        argumentKeys: const <String>['parameters'],
        idKeys: const <String>['tool_call_id'],
        assignFallbackIds: false,
      );
      if (calls != null && calls.isNotEmpty) {
        return _CommandBareActionPayload(
          content: text.substring(0, markerStart).trim(),
          toolCalls: calls,
        );
      }

      searchEnd = markerStart;
    }

    return null;
  }

  String _sanitizeName(String name) =>
      name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-').toLowerCase();

  String _jsonSchemaToGbnf(Map<String, dynamic> schema, String ruleName) {
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};

    if (properties.isEmpty) {
      return '$ruleName ::= "{" space "}"';
    }

    final parts = <String>[];
    var first = true;
    for (final entry in properties.entries) {
      final sep = first ? '' : '", " space ';
      first = false;
      final propType = (entry.value as Map<String, dynamic>)['type'] as String?;
      final valueRule = _typeToGbnf(propType);
      parts.add('$sep"\\"${entry.key}\\": " space $valueRule');
    }

    return '$ruleName ::= "{" space ${parts.join(' ')} space "}"';
  }

  String _typeToGbnf(String? type) {
    switch (type) {
      case 'string':
        return 'string';
      case 'number':
      case 'integer':
        return 'number';
      case 'boolean':
        return 'boolean';
      case 'array':
        return 'arr';
      default:
        return 'value';
    }
  }

  String _commonGbnfRules() {
    return r'''
space ::= " "?
string ::= "\"" ([^"\\] | "\\\\" .)* "\""
number ::= "-"? ([0-9] | [1-9] [0-9]*) ("." [0-9]+)? ([eE] [-+]? [0-9]+)?
boolean ::= "true" | "false"
null ::= "null"
value ::= string | number | boolean | null | arr | obj
arr ::= "[" space (value ("," space value)*)? space "]"
obj ::= "{" space (string ":" space value ("," space string ":" space value)*)? space "}"''';
  }
}

class _CommandBareActionPayload {
  const _CommandBareActionPayload({
    required this.content,
    required this.toolCalls,
  });

  final String content;
  final List<LlamaCompletionChunkToolCall> toolCalls;
}
