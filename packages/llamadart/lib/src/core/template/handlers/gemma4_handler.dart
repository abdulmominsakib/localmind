import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_role.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/chat/completion_chunk.dart';
import '../../models/chat/content_part.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../thinking_utils.dart';
import '../tool_call_fallback_parser.dart';
import '../tool_call_parsing_utils.dart';

/// Handler for Gemma 4 chat templates.
///
/// Gemma 4 uses `<|turn>/<turn|>` message frames, optional
/// `<|channel>thought...<channel|>` reasoning blocks, and
/// `<|tool_call>call:name{args}<tool_call|>` tool-call envelopes.
class Gemma4Handler extends ChatTemplateHandler {
  static const String _turnEnd = '<turn|>';
  static const String _toolCallStart = '<|tool_call>';
  static const String _toolCallEnd = '<tool_call|>';
  static const String _channelStart = '<|channel>';
  static const String _channelEnd = '<channel|>';
  static const List<String> _customQuoteTokens = <String>['<|\\"|>', '<|"|>'];
  static const Set<String> _invalidToolNames = <String>{
    'func_name',
    'function_name',
    'name',
  };

  @override
  ChatFormat get format => ChatFormat.gemma4;

  @override
  String get thinkingStartTag => '<|channel>thought\n';

  @override
  String get thinkingEndTag => _channelEnd;

  @override
  List<String> get additionalStops => const [_turnEnd, _toolCallEnd];

  @override
  List<String> getStops({bool hasTools = false, bool enableThinking = true}) {
    return hasTools ? const [_toolCallEnd, _turnEnd] : const <String>[_turnEnd];
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
    return _renderInternal(
      templateSource: templateSource,
      messages: messages,
      metadata: metadata,
      addAssistant: addAssistant,
      tools: tools,
      enableThinking: enableThinking,
      multimodalContent: false,
    );
  }

  @override
  LlamaChatTemplateResult renderWithMultimodalContent({
    required String templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    bool enableThinking = true,
  }) {
    return _renderInternal(
      templateSource: templateSource,
      messages: messages,
      metadata: metadata,
      addAssistant: addAssistant,
      tools: tools,
      enableThinking: enableThinking,
      multimodalContent: true,
    );
  }

  LlamaChatTemplateResult _renderInternal({
    required String templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    required bool addAssistant,
    required List<ToolDefinition>? tools,
    required bool enableThinking,
    required bool multimodalContent,
  }) {
    final template = Template(templateSource);
    var prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': _serializeMessages(
          messages,
          multimodalContent: multimodalContent,
        ),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'enable_thinking': enableThinking,
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<bos>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? _turnEnd,
      },
    );

    var thinkingForcedOpen = false;
    if (isThinkingForcedOpen(prompt, startTag: thinkingStartTag.trimRight())) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}$_channelEnd\n';
      } else {
        thinkingForcedOpen = true;
      }
    }

    final hasTools = tools != null && tools.isNotEmpty;
    return LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: buildGrammar(tools),
      grammarLazy: false,
      thinkingForcedOpen: thinkingForcedOpen,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      grammarTriggers: const [],
    );
  }

  List<Map<String, dynamic>> _serializeMessages(
    List<LlamaChatMessage> messages, {
    required bool multimodalContent,
  }) {
    return messages
        .map((message) {
          if (message.role == LlamaChatRole.tool) {
            return _serializeToolMessage(message);
          }

          return multimodalContent
              ? message.toJsonMultimodal()
              : message.toJson();
        })
        .toList(growable: false);
  }

  Map<String, dynamic> _serializeToolMessage(LlamaChatMessage message) {
    final toolResults = message.parts
        .whereType<LlamaToolResultContent>()
        .toList();
    if (toolResults.isEmpty) {
      return message.toJson();
    }

    return {
      'role': 'tool',
      'content': null,
      'tool_responses': toolResults
          .map(
            (result) => {
              'name': result.name,
              'response': _normalizeToolResponse(result.result),
            },
          )
          .toList(growable: false),
    };
  }

  Map<String, dynamic> _normalizeToolResponse(Object? result) {
    if (result == null) {
      return {'value': null};
    }

    final map = ToolCallParsingUtils.coerceMap(result);
    if (map != null) {
      return map;
    }

    if (result is String) {
      final decoded = ToolCallParsingUtils.decodeJsonObject(result);
      if (decoded != null) {
        return decoded;
      }
      return {'value': result};
    }

    return {'value': result};
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    final reasoning = _extractReasoning(
      output,
      isPartial: isPartial,
      thinkingForcedOpen: thinkingForcedOpen,
    );

    if (!parseToolCalls) {
      return ChatParseResult(
        content: reasoning.content.trim(),
        reasoningContent: reasoning.reasoning,
      );
    }

    final parsed = _extractToolCalls(reasoning.content, isPartial: isPartial);
    if (parsed.toolCalls.isEmpty) {
      final fallback = parseToolCallsFromLooseText(parsed.content);
      if (fallback.toolCalls.isNotEmpty) {
        return ChatParseResult(
          content: fallback.content.trim(),
          reasoningContent: reasoning.reasoning,
          toolCalls: fallback.toolCalls,
        );
      }
    }
    return ChatParseResult(
      content: parsed.content.trim(),
      reasoningContent: reasoning.reasoning,
      toolCalls: parsed.toolCalls,
    );
  }

  ({String content, String? reasoning}) _extractReasoning(
    String output, {
    required bool isPartial,
    required bool thinkingForcedOpen,
  }) {
    final reasoningParts = <String>[];
    final content = StringBuffer();
    var cursor = 0;

    while (cursor < output.length) {
      final start = output.indexOf(_channelStart, cursor);
      if (start == -1) {
        if (thinkingForcedOpen) {
          final end = output.indexOf(_channelEnd, cursor);
          if (end == -1) {
            final reasoning = output.substring(cursor);
            if (reasoning.isNotEmpty) {
              reasoningParts.add(reasoning);
            }
          } else {
            final reasoning = output.substring(cursor, end);
            if (reasoning.isNotEmpty) {
              reasoningParts.add(reasoning);
            }
            content.write(output.substring(end + _channelEnd.length));
            thinkingForcedOpen = false;
          }
        } else {
          content.write(output.substring(cursor));
        }
        break;
      }

      final end = output.indexOf(_channelEnd, start + _channelStart.length);
      if (end == -1) {
        content.write(output.substring(cursor, start));
        final partial = _parseChannelBlock(
          output.substring(start),
          isPartial: true,
        );
        if (isPartial && partial != null && partial.channel == 'thought') {
          if (partial.body.isNotEmpty) {
            reasoningParts.add(partial.body);
          }
        } else {
          content.write(output.substring(start));
        }
        break;
      }

      content.write(output.substring(cursor, start));
      final parsed = _parseChannelBlock(
        output.substring(start, end + _channelEnd.length),
        isPartial: false,
      );
      final channel = parsed?.channel;
      final body = parsed?.body ?? '';

      if (channel == 'thought') {
        if (body.isNotEmpty) {
          reasoningParts.add(body);
        }
      } else {
        content.write(output.substring(start, end + _channelEnd.length));
      }

      cursor = end + _channelEnd.length;
    }

    return (
      content: content.toString(),
      reasoning: reasoningParts.isEmpty ? null : reasoningParts.join('\n'),
    );
  }

  ({String channel, String body})? _parseChannelBlock(
    String input, {
    required bool isPartial,
  }) {
    if (!input.startsWith(_channelStart)) {
      return null;
    }

    final blockEnd = isPartial
        ? input.length
        : input.indexOf(_channelEnd, _channelStart.length);
    if (blockEnd == -1) {
      return null;
    }

    final block = input.substring(_channelStart.length, blockEnd);
    final newline = block.indexOf('\n');
    if (newline == -1) {
      return isPartial
          ? (channel: block.trim(), body: '')
          : (channel: block.trim(), body: '');
    }

    return (
      channel: block.substring(0, newline).trim(),
      body: block.substring(newline + 1).trim(),
    );
  }

  ({String content, List<LlamaCompletionChunkToolCall> toolCalls})
  _extractToolCalls(String output, {required bool isPartial}) {
    final toolCalls = <LlamaCompletionChunkToolCall>[];
    final content = StringBuffer();
    var cursor = 0;

    while (cursor < output.length) {
      final start = output.indexOf(_toolCallStart, cursor);
      if (start == -1) {
        content.write(output.substring(cursor));
        break;
      }

      content.write(output.substring(cursor, start));
      final parsed = _parseToolCall(output, start, toolCalls.length);
      if (parsed == null) {
        if (!isPartial) {
          content.write(output.substring(start));
        }
        break;
      }

      toolCalls.add(parsed.toolCall);
      cursor = parsed.end;
    }

    return (content: content.toString(), toolCalls: toolCalls);
  }

  ({int end, LlamaCompletionChunkToolCall toolCall})? _parseToolCall(
    String output,
    int start,
    int index,
  ) {
    var cursor = _skipWhitespace(output, start + _toolCallStart.length);

    if (output.startsWith('call', cursor)) {
      cursor += 4;
      cursor = _skipWhitespace(output, cursor);
      if (cursor < output.length && output.codeUnitAt(cursor) == 0x3A) {
        cursor++;
      }
      cursor = _skipWhitespace(output, cursor);
    }

    final nameStart = cursor;
    while (cursor < output.length &&
        _isIdentifierChar(output.codeUnitAt(cursor))) {
      cursor++;
    }

    final name = output.substring(nameStart, cursor).trim();
    if (name.isEmpty || _invalidToolNames.contains(name)) {
      return null;
    }

    cursor = _skipWhitespace(output, cursor);

    if (cursor >= output.length || output.codeUnitAt(cursor) != 0x7B) {
      return null;
    }

    final endBrace = _findMatchingBrace(output, cursor);
    if (endBrace == -1) {
      return null;
    }

    var end = _skipWhitespace(output, endBrace + 1);
    if (output.startsWith(_toolCallEnd, end)) {
      end += _toolCallEnd.length;
    }

    final arguments = _normalizePseudoJson(
      output.substring(cursor, endBrace + 1),
    );
    final decodedArguments = normalizeFallbackToolArguments(
      decodeToolArgumentsObject(arguments),
    );
    final normalizedName = normalizeFallbackToolName(
      name,
      arguments: decodedArguments,
    );

    return (
      end: end,
      toolCall: ToolCallParsingUtils.createFunctionToolCall(
        index: index,
        name: normalizedName,
        arguments: decodedArguments,
      ),
    );
  }

  String _normalizePseudoJson(String input) {
    final normalizedQuotes = input
        .replaceAll(RegExp(r'<\|\\?"\|>'), '"')
        .replaceAll('<escape>', '"');

    return normalizedQuotes.replaceAllMapped(
      RegExp(r'(^|[{,])\s*([a-zA-Z_][\w\.-]*)\s*:'),
      (match) => '${match.group(1)}"${match.group(2)}":',
    );
  }

  int _findMatchingBrace(String text, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = start; i < text.length; i++) {
      final quoteTokenLength = _customQuoteTokenLengthAt(text, i);

      if (inString) {
        if (quoteTokenLength != null) {
          inString = false;
          i += quoteTokenLength - 1;
          continue;
        }

        final codeUnit = text.codeUnitAt(i);
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

      if (quoteTokenLength != null) {
        inString = true;
        i += quoteTokenLength - 1;
        continue;
      }

      final codeUnit = text.codeUnitAt(i);
      if (codeUnit == 0x22) {
        inString = true;
      } else if (codeUnit == 0x7B) {
        depth++;
      } else if (codeUnit == 0x7D) {
        depth--;
        if (depth == 0) {
          return i;
        }
      }
    }
    return -1;
  }

  int? _customQuoteTokenLengthAt(String text, int index) {
    for (final token in _customQuoteTokens) {
      if (text.startsWith(token, index)) {
        return token.length;
      }
    }
    return null;
  }

  int _skipWhitespace(String text, int start) {
    var offset = start;
    while (offset < text.length && _isWhitespace(text.codeUnitAt(offset))) {
      offset++;
    }
    return offset;
  }

  bool _isIdentifierChar(int codeUnit) {
    return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7A) ||
        codeUnit == 0x5F ||
        codeUnit == 0x2D ||
        codeUnit == 0x2E;
  }

  bool _isWhitespace(int codeUnit) {
    return codeUnit == 0x20 ||
        codeUnit == 0x0A ||
        codeUnit == 0x0D ||
        codeUnit == 0x09;
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }
}
