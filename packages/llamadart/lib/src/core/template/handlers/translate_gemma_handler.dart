import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';

/// Handler for TranslateGemma templates.
///
/// TranslateGemma expects user message content in list form with
/// `source_lang_code` and `target_lang_code` fields per text item.
///
/// Matches llama.cpp behavior:
/// - no tool calling support
/// - no reasoning format
/// - default language codes to `en-GB` when not provided
class TranslateGemmaHandler extends ChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.translateGemma;

  @override
  List<String> get additionalStops => const [];

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
    final sourceLangCode = metadata['source_lang_code'] ?? 'en-GB';
    final targetLangCode = metadata['target_lang_code'] ?? 'en-GB';

    final normalizedMessages = messages
        .map((message) => message.toJson())
        .map(
          (message) => _normalizeUserContent(
            message,
            sourceLangCode: sourceLangCode,
            targetLangCode: targetLangCode,
          ),
        )
        .toList();

    final prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': normalizedMessages,
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
      },
    );

    return LlamaChatTemplateResult(prompt: prompt, format: format.index);
  }

  Map<String, dynamic> _normalizeUserContent(
    Map<String, dynamic> message, {
    required String sourceLangCode,
    required String targetLangCode,
  }) {
    final role = message['role'];
    if (role != 'user') {
      return message;
    }

    if (!message.containsKey('content') || message['content'] == null) {
      message['content'] = <Map<String, dynamic>>[];
      return message;
    }

    final content = message['content'];
    if (content is List) {
      return message;
    }

    message['content'] = [
      {
        'type': 'text',
        'text': content.toString(),
        'source_lang_code': sourceLangCode,
        'target_lang_code': targetLangCode,
      },
    ];

    return message;
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    return ChatParseResult(content: output.trim());
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }
}
