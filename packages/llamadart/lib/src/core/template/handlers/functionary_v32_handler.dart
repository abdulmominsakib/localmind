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

/// Handler for Functionary v3.2 format.
///
/// Tool calls use `>>>name\n{...}` blocks, with `>>>all\n` as a content
/// channel and optional `>>>python\n<raw code>` output.
class FunctionaryV32Handler extends ChatTemplateHandler {
  static final RegExp _functionRegexStartOnly = RegExp(
    r'([A-Za-z0-9_]+\n\{|python\n|all\n)',
  );
  static final RegExp _functionRegex = RegExp(
    r'>>>([A-Za-z0-9_]+\n\{|python\n|all\n)',
  );

  @override
  ChatFormat get format => ChatFormat.functionaryV32;

  @override
  List<String> get additionalStops => ['<|eot_id|>'];

  @override
  List<String> get preservedTokens => const ['<|end_header_id|>'];

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

    final activeTools = tools ?? const <ToolDefinition>[];
    final hasTools = activeTools.isNotEmpty;
    final toolChoice = metadata[internalToolChoiceMetadataKey];
    final toolChoiceRequired = toolChoice == ToolChoice.required.name;
    final parallelToolCalls =
        metadata[internalParallelToolCallsMetadataKey] == 'true';
    final grammar = _buildGrammarWithOptions(
      tools,
      parallelToolCalls: parallelToolCalls,
    );
    final triggers = <GrammarTrigger>[];
    if (hasTools) {
      for (final tool in activeTools) {
        final escapedName = RegExp.escape(tool.name);
        triggers.add(
          GrammarTrigger(
            type: 3,
            value: '((?:[\\s\\S]+?>>>)?$escapedName\\n)\\{[\\s\\S]*',
          ),
        );
      }
      if (activeTools.any((tool) => tool.name == 'python')) {
        triggers.add(
          const GrammarTrigger(
            type: 3,
            value: '((?:[\\s\\S]+?>>>)?python\\n)[\\s\\S]*',
          ),
        );
      }
    }

    return LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: grammar,
      grammarLazy: hasTools && !toolChoiceRequired,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      preservedTokens: hasTools ? preservedTokens : const [],
      grammarTriggers: triggers,
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

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    final content = StringBuffer();

    var cursor = 0;
    var searchFrom = 0;
    var first = true;
    var parseFailed = false;

    while (true) {
      _FunctionMarker? marker;
      if (first) {
        final startOnly = _functionRegexStartOnly.matchAsPrefix(output, cursor);
        if (startOnly != null) {
          marker = _FunctionMarker(
            start: startOnly.start,
            end: startOnly.end,
            token: startOnly.group(1)!,
          );
        }
      }
      marker ??= _findNextFunctionMarker(output, searchFrom);

      if (marker == null) {
        break;
      }

      if (marker.start > cursor) {
        content.write(output.substring(cursor, marker.start));
      }

      cursor = marker.end;
      searchFrom = cursor;

      var name = marker.token;
      if (name.endsWith('{')) {
        cursor--;
        searchFrom = cursor;
      }
      name = name.replaceFirst(RegExp(r'[\n{]+$'), '');
      final atStart = marker.start == 0;

      // Keep behavior aligned with llama.cpp: leading `all` is a content channel.
      if (atStart && name == 'all') {
        first = false;
        searchFrom = marker.start + 1;
        continue;
      }

      final allowRawPython = name == 'python';
      final atJsonStart =
          cursor < output.length && output.codeUnitAt(cursor) == 0x7B;

      if (atJsonStart || !allowRawPython) {
        final jsonRange = _extractJsonObjectRange(output, cursor);
        if (jsonRange == null) {
          if (!isPartial) {
            parseFailed = true;
          }
          break;
        }

        final jsonText = output.substring(cursor, jsonRange.end);
        toolCalls.add(
          ToolCallParsingUtils.createFunctionToolCall(
            index: toolCalls.length,
            name: name,
            arguments: _normalizeArguments(jsonText),
          ),
        );
        cursor = jsonRange.end;
        while (cursor < output.length &&
            _isWhitespace(output.codeUnitAt(cursor))) {
          cursor++;
        }
        searchFrom = cursor;
        first = false;
        continue;
      }

      final rawCode = output.substring(cursor);
      toolCalls.add(
        ToolCallParsingUtils.createFunctionToolCall(
          index: toolCalls.length,
          name: 'python',
          arguments: <String, dynamic>{'code': rawCode},
        ),
      );
      cursor = output.length;
      first = false;
      break;
    }

    if (parseFailed && !isPartial) {
      return ChatParseResult(content: output.trim(), toolCalls: const []);
    }

    if (cursor < output.length) {
      content.write(output.substring(cursor));
    }

    return ChatParseResult(
      content: content.toString().trim(),
      toolCalls: toolCalls,
    );
  }

  _FunctionMarker? _findNextFunctionMarker(String text, int from) {
    final matches = _functionRegex.allMatches(text, from);
    if (matches.isEmpty) {
      return null;
    }
    final match = matches.first;
    return _FunctionMarker(
      start: match.start,
      end: match.end,
      token: match.group(1)!,
    );
  }

  ParsedJsonValueSlice? _extractJsonObjectRange(String text, int start) {
    final jsonSlice = ToolCallParsingUtils.extractLeadingJsonValue(text, start);
    if (jsonSlice == null || jsonSlice.value is! Map) {
      return null;
    }
    return jsonSlice;
  }

  String _normalizeArguments(String jsonText) {
    return ToolCallParsingUtils.normalizeJsonArguments(jsonText);
  }

  bool _isWhitespace(int codeUnit) =>
      codeUnit == 0x20 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D ||
      codeUnit == 0x09;

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
    final firstToolRules = <String>[];
    final subsequentToolRules = <String>[];

    for (var i = 0; i < tools.length; i++) {
      final tool = tools[i];
      final schema = tool.toJsonSchema();
      converter.resolveRefs(schema, schema);
      final argsRule = converter.visit(schema, 'tool-$i-args');
      final ruleName = 'tool-$i-call';

      converter.rules[ruleName] =
          '${ToolCallGrammarUtils.literal('${tool.name}\\n')} $argsRule';
      firstToolRules.add(ruleName);

      if (parallelToolCalls) {
        final subsequentRuleName = 'tool-$i-call2';
        converter.rules[subsequentRuleName] =
            '${ToolCallGrammarUtils.literal('>>>')} $ruleName';
        subsequentToolRules.add(subsequentRuleName);
      }
    }

    final buffer = StringBuffer()
      ..writeln('first-tool-call ::= ${firstToolRules.join(' | ')}')
      ..writeln(
        'root ::= ${parallelToolCalls ? 'first-tool-call space (subsequent-tool-call space)*' : 'first-tool-call space'}',
      );

    if (parallelToolCalls) {
      buffer.writeln(
        'subsequent-tool-call ::= ${subsequentToolRules.join(' | ')}',
      );
    }

    final otherRules = converter.rules.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in otherRules) {
      if (entry.key == 'root' ||
          entry.key == 'first-tool-call' ||
          entry.key == 'subsequent-tool-call') {
        continue;
      }
      buffer.writeln('${entry.key} ::= ${entry.value}');
    }

    return buffer.toString();
  }
}

final class _FunctionMarker {
  final int start;
  final int end;
  final String token;

  const _FunctionMarker({
    required this.start,
    required this.end,
    required this.token,
  });
}
