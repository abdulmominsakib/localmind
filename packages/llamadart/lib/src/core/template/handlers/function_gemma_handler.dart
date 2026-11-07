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
import '../tool_call_fallback_parser.dart';
import '../tool_call_parsing_utils.dart';

/// Handler for FunctionGemma format.
///
/// Uses `<start_function_call>call:name{args}<end_function_call>` format
/// with `<escape>` tokens instead of double quotes.
///
/// Tool declarations use `<start_function_declaration>` / `<end_function_declaration>`.
class FunctionGemmaHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.functionGemma;

  @override
  List<String> get additionalStops => ['<end_of_turn>', '<end_function_call>'];

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
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<bos>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '<eos>',
      },
    );

    if (multimodalContent) {
      prompt = prompt.replaceAll('<start_of_image>', '<__media__>');
    }

    final hasTools = tools != null && tools.isNotEmpty;
    return LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: buildGrammar(tools),
      grammarLazy: hasTools,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      grammarTriggers: hasTools
          ? [const GrammarTrigger(type: 0, value: '<start_function_call>')]
          : [],
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

    if (toolResults.length == 1) {
      final result = toolResults.first;
      return {
        'role': 'tool',
        'content': {
          'name': result.name,
          'response': _normalizeToolResponse(result.result),
        },
      };
    }

    return {
      'role': 'tool',
      'content': toolResults
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
    if (!parseToolCalls) {
      return ChatParseResult(content: output.trim());
    }

    final toolCalls = <LlamaCompletionChunkToolCall>[];
    var contentText = output;

    // Parse <start_function_call>call:name{args}<end_function_call>
    final regex = RegExp(
      r'<start_function_call>\s*(?:call(?:\s*:\s*|\s+))?([a-zA-Z0-9_\.]+)\s*\{(.*?)\}(?:\s*<end_function_call>)?',
      dotAll: true,
    );

    final matches = regex.allMatches(output);
    for (var i = 0; i < matches.length; i++) {
      final match = matches.elementAt(i);
      final name = match.group(1)?.trim() ?? '';
      var arguments = match.group(2)?.trim() ?? '{}';

      // Filter out common hallucinations
      if (name == 'func_name' ||
          name == 'function_name' ||
          name == 'name' ||
          arguments == 'args' ||
          arguments == 'arguments') {
        continue;
      }

      // FunctionGemma uses <escape> for double quotes
      arguments = arguments.replaceAll('<escape>', '"');

      // FunctionGemma outputs unquoted keys like {location:"London"}
      // Convert to valid JSON by quoting unquoted keys
      arguments = _toValidJson(arguments);

      final normalizedArguments = decodeToolArgumentsObject(arguments);
      final normalizedName = normalizeFallbackToolName(
        name,
        arguments: normalizedArguments,
      );

      toolCalls.add(
        ToolCallParsingUtils.createFunctionToolCall(
          index: i,
          name: normalizedName,
          arguments: normalizedArguments,
        ),
      );
      contentText = contentText.replaceAll(match.group(0)!, '');
    }

    return ChatParseResult(content: contentText.trim(), toolCalls: toolCalls);
  }

  /// Converts FunctionGemma pseudo-JSON (unquoted keys) to valid JSON.
  ///
  /// Input:  `{location:"London",unit:"celsius"}`
  /// Output: `{"location":"London","unit":"celsius"}`
  String _toValidJson(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return '{}';
    }

    final normalized = trimmed.replaceAllMapped(
      RegExp(r'(^|[{,])\s*([a-zA-Z_]\w*)\s*:'),
      (m) => '${m.group(1)}"${m.group(2)}":',
    );

    if (normalized.startsWith('{') && normalized.endsWith('}')) {
      return normalized;
    }

    return '{$normalized}';
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }
}
