import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';
import '../tool_call_parsing_utils.dart';
import '../tool_call_grammar_utils.dart';

/// Handler for Llama 3.x models.
///
/// Uses the ipython role for tool calls with `<|python_tag|>` trigger.
/// Tool call format: `{"name": "fn", "parameters": {...}}`
class Llama3Handler extends ChatTemplateHandler {
  static final RegExp _llama31FunctionPrefix = RegExp(
    r'^\s*\{\s*(?:"type"\s*:\s*"function"\s*,\s*)?"name"\s*:\s*"([^"]+)"\s*,\s*"parameters"\s*:\s*',
    dotAll: true,
  );

  static final RegExp _llama31CloseRegex = RegExp(r'\}\s*', dotAll: true);

  static final RegExp _builtinFunctionPrefix = RegExp(
    r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*call\(',
    dotAll: true,
  );

  static final RegExp _builtinArgName = RegExp(
    r'\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*',
    dotAll: true,
  );

  static const String _pythonTag = '<|python_tag|>';

  /// Finds a possible builtin-tool call opening for the stream's content gate.
  static int builtinCallOpening(String text, [int from = 0]) =>
      ToolCallParsingUtils.literalOpening(text, const [_pythonTag], from);

  static const Set<String> _builtinToolNames = {
    'wolfram_alpha',
    'web_search',
    'brave_search',
    'python',
    'code_interpreter',
  };

  @override
  ChatFormat get format => ChatFormat.llama3;

  @override
  TemplateToolCallSerialization get toolCallSerialization =>
      TemplateToolCallSerialization.normalizeOnly;

  @override
  List<String> get additionalStops => ['<|eot_id|>', '<|eom_id|>'];

  @override
  List<String> getStops({bool hasTools = false, bool enableThinking = true}) {
    return hasTools ? additionalStops : const ['<|eot_id|>'];
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
    final prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': templateMessages(messages, templateSource: templateSource),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'bos_token':
            metadata['tokenizer.ggml.bos_token'] ?? '<|begin_of_text|>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '<|end_of_text|>',
        'date_string': _formatDateString(resolveTemplateNow(metadata)),
      },
    );

    final hasTools = tools != null && tools.isNotEmpty;
    final hasBuiltinTools =
        hasTools && tools.any((tool) => _builtinToolNames.contains(tool.name));
    final supportsPythonTagBuiltins = templateSource.contains(_pythonTag);
    final resolvedFormat = hasTools
        ? (hasBuiltinTools && supportsPythonTagBuiltins
              ? ChatFormat.llama3BuiltinTools
              : format)
        : ChatFormat.contentOnly;

    final triggers = <GrammarTrigger>[];
    if (hasTools) {
      triggers.add(
        const GrammarTrigger(
          type: 3,
          value:
              r'(\{\s*(?:"type"\s*:\s*"function"\s*,\s*)?"name"\s*:\s*")[\s\S]*',
        ),
      );
      if (resolvedFormat == ChatFormat.llama3BuiltinTools) {
        triggers.add(const GrammarTrigger(type: 0, value: _pythonTag));
      }
    }

    final grammar = resolvedFormat == ChatFormat.llama3BuiltinTools
        ? null
        : buildGrammar(tools);

    return LlamaChatTemplateResult(
      prompt: prompt,
      format: resolvedFormat.index,
      grammar: grammar,
      grammarLazy: hasTools,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      grammarTriggers: triggers,
      preservedTokens: resolvedFormat == ChatFormat.llama3BuiltinTools
          ? const [_pythonTag]
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
    final thinking = extractThinking(
      output,
      thinkingForcedOpen: thinkingForcedOpen,
    );
    final trimmed = thinking.content.trim();

    if (!parseToolCalls) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    final builtinResult = _tryParseBuiltinPythonTag(trimmed);
    if (builtinResult.foundTag) {
      if (builtinResult.function == null ||
          (isPartial && !builtinResult.valid)) {
        return ChatParseResult(
          // An unfinished builtin call may still complete.
          content: isPartial
              ? trimmed.substring(0, trimmed.indexOf(_pythonTag))
              : trimmed,
          reasoningContent: thinking.reasoning,
        );
      }

      return ChatParseResult(
        content: builtinResult.content,
        reasoningContent: thinking.reasoning,
        toolCalls: [
          ToolCallParsingUtils.createFunctionToolCall(
            index: 0,
            name: builtinResult.function!.name!,
            arguments: builtinResult.function!.arguments,
          ),
        ],
      );
    }

    final prefix = _llama31FunctionPrefix.firstMatch(trimmed);
    if (prefix == null) {
      if (isPartial && _mayStartFunctionCall(trimmed)) {
        return ChatParseResult(
          content: '',
          reasoningContent: thinking.reasoning,
        );
      }
      return ChatParseResult(
        content: isPartial
            ? trimmed.substring(
                0,
                ToolCallParsingUtils.literalOpening(trimmed, const [
                  _pythonTag,
                ]),
              )
            : trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    final functionName = prefix.group(1);
    if (functionName == null || functionName.isEmpty) {
      return ChatParseResult(
        content: trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    final argsValue = ToolCallParsingUtils.extractLeadingJsonValue(
      trimmed,
      prefix.end,
    );
    if (argsValue == null) {
      return ChatParseResult(
        content: isPartial ? '' : trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    final close = _llama31CloseRegex.matchAsPrefix(trimmed, argsValue.end);
    if (close == null) {
      return ChatParseResult(
        content: isPartial && argsValue.end >= trimmed.length ? '' : trimmed,
        reasoningContent: thinking.reasoning,
      );
    }

    var contentStart = close.end;
    while (contentStart < trimmed.length &&
        trimmed.codeUnitAt(contentStart) <= 0x20) {
      contentStart++;
    }

    return ChatParseResult(
      // A later builtin tag makes the final content start at the JSON call,
      // so text after the call waits for the final parse.
      content: isPartial ? '' : trimmed.substring(contentStart),
      reasoningContent: thinking.reasoning,
      toolCalls: [
        ToolCallParsingUtils.createFunctionToolCall(
          index: 0,
          name: functionName,
          arguments: ToolCallParsingUtils.encodeArguments(argsValue.value),
        ),
      ],
    );
  }

  _BuiltinParseResult _tryParseBuiltinPythonTag(String output) {
    final pythonTagIndex = output.indexOf(_pythonTag);
    if (pythonTagIndex < 0) {
      return const _BuiltinParseResult(foundTag: false, valid: true);
    }

    final contentPrefix = output.substring(0, pythonTagIndex);
    final afterTag = output.substring(pythonTagIndex + _pythonTag.length);
    final functionPrefix = _builtinFunctionPrefix.matchAsPrefix(afterTag);
    if (functionPrefix == null) {
      return const _BuiltinParseResult(foundTag: true, valid: false);
    }

    final functionName = functionPrefix.group(1);
    if (functionName == null || functionName.isEmpty) {
      return const _BuiltinParseResult(foundTag: true, valid: false);
    }

    var cursor = functionPrefix.end;
    final arguments = <String, dynamic>{};

    while (true) {
      final argMatch = _builtinArgName.matchAsPrefix(afterTag, cursor);
      if (argMatch == null) {
        break;
      }

      final argName = argMatch.group(1);
      if (argName == null || argName.isEmpty) {
        return const _BuiltinParseResult(foundTag: true, valid: false);
      }

      cursor = argMatch.end;
      final value = ToolCallParsingUtils.extractLeadingJsonValue(
        afterTag,
        cursor,
      );
      if (value == null) {
        return const _BuiltinParseResult(foundTag: true, valid: false);
      }
      arguments[argName] = value.value;
      cursor = value.end;

      while (cursor < afterTag.length && afterTag.codeUnitAt(cursor) <= 0x20) {
        cursor++;
      }

      if (cursor < afterTag.length && afterTag.codeUnitAt(cursor) == 0x2C) {
        cursor++;
      } else {
        break;
      }
    }

    while (cursor < afterTag.length && afterTag.codeUnitAt(cursor) <= 0x20) {
      cursor++;
    }

    if (cursor >= afterTag.length || afterTag.codeUnitAt(cursor) != 0x29) {
      return const _BuiltinParseResult(foundTag: true, valid: false);
    }

    cursor++;
    while (cursor < afterTag.length && afterTag.codeUnitAt(cursor) <= 0x20) {
      cursor++;
    }

    if (cursor != afterTag.length) {
      return const _BuiltinParseResult(foundTag: true, valid: false);
    }

    return _BuiltinParseResult(
      foundTag: true,
      valid: true,
      content: contentPrefix,
      function: LlamaCompletionChunkFunction(
        name: functionName,
        arguments: ToolCallParsingUtils.encodeArguments(arguments),
      ),
    );
  }

  /// Whether [text] is a prefix of a call that [_llama31FunctionPrefix]
  /// would match once more output arrives.
  static bool _mayStartFunctionCall(String text) {
    bool matchesPrefix(List<String?> parts) {
      var i = 0;
      for (final part in parts) {
        // Matches the `\s` of [_llama31FunctionPrefix], including Unicode
        // whitespace.
        while (i < text.length && text[i].trim().isEmpty) {
          i++;
        }
        if (i >= text.length) return true;
        if (part == null) {
          if (text.codeUnitAt(i) != 0x22) return false;
          i++;
          final close = text.indexOf('"', i);
          if (close < 0) return true;
          if (close == i) return false;
          i = close + 1;
          continue;
        }
        if (text.length - i < part.length) {
          return part.startsWith(text.substring(i));
        }
        if (!text.startsWith(part, i)) return false;
        i += part.length;
      }
      return false;
    }

    const call = <String?>['"name"', ':', null, ',', '"parameters"', ':'];
    return matchesPrefix(['{', ...call]) ||
        matchesPrefix(['{', '"type"', ':', '"function"', ',', ...call]);
  }

  String _formatDateString(DateTime value) {
    final now = value.toLocal();
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day = now.day.toString().padLeft(2, '0');
    final month = months[now.month - 1];
    final year = now.year;
    return '$day $month $year';
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return ToolCallGrammarUtils.buildWrappedObjectGrammar(
      tools: tools,
      prefix: '',
      suffix: '',
      nameKey: 'name',
      argumentsKey: 'parameters',
    );
  }
}

final class _BuiltinParseResult {
  final bool foundTag;
  final bool valid;
  final String content;
  final LlamaCompletionChunkFunction? function;

  const _BuiltinParseResult({
    required this.foundTag,
    required this.valid,
    this.content = '',
    this.function,
  });
}
