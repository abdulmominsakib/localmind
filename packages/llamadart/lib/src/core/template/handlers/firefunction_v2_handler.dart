import 'dart:convert';

import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/inference/tool_choice.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../template_internal_metadata.dart';
import '../tool_call_parsing_utils.dart';
import '../tool_call_grammar_utils.dart';

/// Handler for FireFunction v2 templates.
///
/// Tool calls are emitted as a JSON array prefixed with `functools`:
/// `functools[{"name":"tool","arguments":{...}}]`.
class FirefunctionV2Handler extends ChatTemplateHandler {
  static const String _prefix = ' functools[';
  static const List<String> _firefunctionPreservedTokens = <String>[
    ' functools[',
  ];

  @override
  ChatFormat get format => ChatFormat.firefunctionV2;

  @override
  List<String> get additionalStops => ['<|eot_id|>'];

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
    final toolJson = hasTools
        ? const JsonEncoder.withIndent(
            '  ',
          ).convert(tools.map((tool) => tool.toJson()).toList())
        : '';

    final prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': templateMessages(messages),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'functions': toolJson,
        'datetime': _formatNowLikeLlamaCpp(resolveTemplateNow(metadata)),
        'bos_token':
            metadata['tokenizer.ggml.bos_token'] ?? '<|begin_of_text|>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '<|end_of_text|>',
      },
    );

    return LlamaChatTemplateResult(
      prompt: prompt,
      format: hasTools ? format.index : ChatFormat.contentOnly.index,
      grammar: hasTools
          ? _buildGrammarWithOptions(
              tools,
              parallelToolCalls:
                  metadata[internalParallelToolCallsMetadataKey] == 'true',
            )
          : null,
      grammarLazy:
          hasTools &&
          metadata[internalToolChoiceMetadataKey] != ToolChoice.required.name,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      preservedTokens: hasTools ? _firefunctionPreservedTokens : const [],
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: _prefix)]
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

    final prefixIdx = output.indexOf(_prefix);
    if (prefixIdx == -1) {
      return ChatParseResult(content: output.trim());
    }

    final contentBefore = output.substring(0, prefixIdx);
    final arrayStart = prefixIdx + _prefix.length - 1;
    if (arrayStart < 0 ||
        arrayStart >= output.length ||
        output.codeUnitAt(arrayStart) != 0x5B) {
      return ChatParseResult(content: output.trim());
    }

    final extracted = _extractJsonArray(output, arrayStart);
    if (extracted == null || extracted.end != output.length) {
      return ChatParseResult(content: output.trim());
    }

    final decoded = ToolCallParsingUtils.decodeJsonValue(extracted.json);
    final toolCalls = ToolCallParsingUtils.parseToolCallArray(
      decoded,
      assignFallbackIds: false,
    );
    if (toolCalls == null) {
      return ChatParseResult(content: output.trim());
    }

    return ChatParseResult(content: contentBefore.trim(), toolCalls: toolCalls);
  }

  _JsonExtraction? _extractJsonArray(String input, int startIndex) {
    if (startIndex >= input.length || input.codeUnitAt(startIndex) != 0x5B) {
      return null;
    }

    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = startIndex; i < input.length; i++) {
      final codeUnit = input.codeUnitAt(i);

      if (inString) {
        if (escaped) {
          escaped = false;
          continue;
        }
        if (codeUnit == 0x5C) {
          escaped = true;
          continue;
        }
        if (codeUnit == 0x22) {
          inString = false;
        }
        continue;
      }

      if (codeUnit == 0x22) {
        inString = true;
        continue;
      }

      if (codeUnit == 0x5B) {
        depth++;
      } else if (codeUnit == 0x5D) {
        depth--;
        if (depth == 0) {
          return _JsonExtraction(
            json: input.substring(startIndex, i + 1),
            end: i + 1,
          );
        }
      }
    }

    return null;
  }

  String _formatNowLikeLlamaCpp(DateTime value) {
    // llama.cpp formats this with std::localtime while still appending GMT.
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

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    final month = months[now.month - 1];
    final day = twoDigits(now.day);
    final year = now.year;
    final hour = twoDigits(now.hour);
    final minute = twoDigits(now.minute);
    final second = twoDigits(now.second);
    return '$month $day $year $hour:$minute:$second GMT';
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

    final base = ToolCallGrammarUtils.buildWrappedArrayGrammar(
      tools: tools,
      prefix: '',
      suffix: '',
      nameKey: 'name',
      argumentsKey: 'arguments',
      idKey: 'id',
      allowParallelToolCalls: parallelToolCalls,
    );
    if (base == null) {
      return null;
    }
    return _rewriteRootWithOptionalPrefix(base, ' functools');
  }

  String _rewriteRootWithOptionalPrefix(String grammar, String prefix) {
    final lines = grammar.trimRight().split('\n');
    final rootIndex = lines.indexWhere((line) => line.startsWith('root ::= '));
    if (rootIndex == -1) {
      return grammar;
    }
    final rootExpr = lines[rootIndex].substring('root ::= '.length).trim();
    lines[rootIndex] =
        'root ::= (${ToolCallGrammarUtils.literal(prefix)})? $rootExpr';
    return '${lines.join('\n')}\n';
  }
}

final class _JsonExtraction {
  final String json;
  final int end;

  const _JsonExtraction({required this.json, required this.end});
}
