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

/// Handler for Functionary v3.1 Llama 3.1 templates.
///
/// Supports `<function=name>{...}</function>` tool calls and
/// `<|python_tag|><code>` python fallback.
class FunctionaryV31Llama31Handler extends ChatTemplateHandler {
  static const String _pythonTag = '<|python_tag|>';

  @override
  ChatFormat get format => ChatFormat.functionaryV31Llama31;

  @override
  List<String> get additionalStops => ['<|eot_id|>', '<|eom_id|>'];

  @override
  List<String> get preservedTokens => const [_pythonTag];

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
    final activeTools = tools ?? const <ToolDefinition>[];
    final hasTools = activeTools.isNotEmpty;
    final toolChoice = metadata[internalToolChoiceMetadataKey];
    final toolChoiceRequired = toolChoice == ToolChoice.required.name;
    final parallelToolCalls =
        metadata[internalParallelToolCallsMetadataKey] == 'true';
    final hasRawPython = activeTools.any(
      (tool) => tool.name == 'python' || tool.name == 'ipython',
    );
    final grammar = _buildGrammarWithOptions(
      tools,
      parallelToolCalls: parallelToolCalls,
      hasRawPython: hasRawPython,
    );

    final prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': templateMessages(messages),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'bos_token':
            metadata['tokenizer.ggml.bos_token'] ?? '<|begin_of_text|>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '<|end_of_text|>',
      },
    );

    return LlamaChatTemplateResult(
      prompt: prompt,
      format: hasTools ? format.index : ChatFormat.contentOnly.index,
      grammar: grammar,
      grammarLazy: hasTools && !toolChoiceRequired,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      preservedTokens: hasTools ? preservedTokens : const [],
      grammarTriggers: hasTools
          ? [
              const GrammarTrigger(type: 0, value: '<function='),
              if (hasRawPython)
                const GrammarTrigger(type: 0, value: _pythonTag),
            ]
          : const [],
    );
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    if (!parseToolCalls) {
      return ChatParseResult(content: output.trim());
    }

    var text = output;
    final toolCalls = <LlamaCompletionChunkToolCall>[];

    final functionTag = RegExp(
      r'<function=([^>]+)>(.*?)</function>',
      dotAll: true,
    );
    for (final match in functionTag.allMatches(output)) {
      final name = match.group(1)?.trim();
      final body = match.group(2)?.trim() ?? '';
      if (name == null || name.isEmpty) {
        continue;
      }

      toolCalls.add(
        ToolCallParsingUtils.createFunctionToolCall(
          index: toolCalls.length,
          name: name,
          arguments: _normalizeArguments(body),
        ),
      );
      text = text.replaceAll(match.group(0)!, '');
    }

    final pythonIdx = text.indexOf(_pythonTag);
    if (pythonIdx != -1) {
      final before = text.substring(0, pythonIdx);
      final code = text.substring(pythonIdx + _pythonTag.length).trim();
      if (code.isNotEmpty) {
        toolCalls.add(
          ToolCallParsingUtils.createFunctionToolCall(
            index: toolCalls.length,
            name: 'python',
            arguments: <String, dynamic>{'code': code},
          ),
        );
      }
      text = before;
    } else if (isPartial && text.contains('<function=')) {
      final openIdx = text.indexOf('<function=');
      if (openIdx != -1) {
        final nameEnd = text.indexOf('>', openIdx + '<function='.length);
        if (nameEnd != -1) {
          final name = text
              .substring(openIdx + '<function='.length, nameEnd)
              .trim();
          final args = text.substring(nameEnd + 1).trim();
          if (name.isNotEmpty && args.isNotEmpty) {
            toolCalls.add(
              ToolCallParsingUtils.createFunctionToolCall(
                index: toolCalls.length,
                name: name,
                arguments: args,
              ),
            );
            text = text.substring(0, openIdx);
          }
        }
      }
    }

    return ChatParseResult(content: text.trim(), toolCalls: toolCalls);
  }

  String _normalizeArguments(String body) {
    return ToolCallParsingUtils.normalizeJsonArguments(
      body,
      wrapScalarsAsValue: true,
      emptyFallback: '{}',
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    final hasRawPython = (tools ?? const <ToolDefinition>[]).any(
      (tool) => tool.name == 'python' || tool.name == 'ipython',
    );
    return _buildGrammarWithOptions(
      tools,
      parallelToolCalls: true,
      hasRawPython: hasRawPython,
    );
  }

  String? _buildGrammarWithOptions(
    List<ToolDefinition>? tools, {
    required bool parallelToolCalls,
    required bool hasRawPython,
  }) {
    if (tools == null || tools.isEmpty) {
      return null;
    }

    final converter = JsonSchemaConverter();
    final toolRules = <String>[];

    for (var i = 0; i < tools.length; i++) {
      final tool = tools[i];
      final schema = tool.toJsonSchema();
      converter.resolveRefs(schema, schema);
      final argsRule = converter.visit(schema, 'tool-$i-args');
      final ruleName = 'tool-$i-call';
      converter.rules[ruleName] =
          '${ToolCallGrammarUtils.literal('<function=${tool.name}>')} $argsRule ${ToolCallGrammarUtils.literal('</function>')}';
      toolRules.add(ruleName);
    }

    if (hasRawPython) {
      converter.rules['raw-python-call'] =
          '${ToolCallGrammarUtils.literal(_pythonTag)} raw-python-code';
      converter.rules['raw-python-code'] = '[^\\x00]*';
      toolRules.add('raw-python-call');
    }

    final buffer = StringBuffer()
      ..writeln('tool-call ::= ${toolRules.join(' | ')}')
      ..writeln('root ::= ${parallelToolCalls ? 'tool-call+' : 'tool-call'}');

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
