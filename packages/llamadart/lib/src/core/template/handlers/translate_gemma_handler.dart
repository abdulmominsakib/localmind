import 'package:dinja/dinja.dart';

import '../../exceptions.dart';
import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../template_internal_metadata.dart';

const String _sourceLangCodeKey = 'source_lang_code';
const String _targetLangCodeKey = 'target_lang_code';
const String _defaultLangCode = 'en-GB';

/// Adds the deprecated `sourceLangCode` and `targetLangCode` arguments to
/// [chatTemplateKwargs], where [TranslateGemmaHandler] reads them.
///
/// A non-empty code replaces the same key in [chatTemplateKwargs]; null or
/// empty codes leave it unchanged.
Map<String, dynamic>? chatTemplateKwargsWithLanguageCodes(
  Map<String, dynamic>? chatTemplateKwargs, {
  String? sourceLangCode,
  String? targetLangCode,
}) {
  final hasSource = sourceLangCode != null && sourceLangCode.isNotEmpty;
  final hasTarget = targetLangCode != null && targetLangCode.isNotEmpty;
  if (!hasSource && !hasTarget) return chatTemplateKwargs;
  return <String, dynamic>{
    ...?chatTemplateKwargs,
    if (hasSource) _sourceLangCodeKey: sourceLangCode,
    if (hasTarget) _targetLangCodeKey: targetLangCode,
  };
}

/// Handler for TranslateGemma templates.
///
/// TranslateGemma expects user message content in list form with
/// `source_lang_code` and `target_lang_code` fields per text item.
///
/// Matches llama.cpp behavior:
/// - no tool calling support
/// - no reasoning format
/// - language codes come from `chat_template_kwargs`, then from the
///   `source_lang_code`/`target_lang_code` metadata keys, then `en-GB`
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
    final kwargs = chatTemplateKwargsFromMetadata(metadata);
    final sourceLangCode = _languageCode(_sourceLangCodeKey, kwargs, metadata);
    final targetLangCode = _languageCode(_targetLangCodeKey, kwargs, metadata);

    // Only user turns become typed parts, which carry the language codes.
    // Other turns keep string content: the template prints it whole, and a
    // list would print as its repr.
    final normalizedMessages =
        templateMessages(
              messages,
              templateSource: templateSource,
              typedContent: false,
            )
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

  String _languageCode(
    String key,
    Map<String, dynamic> kwargs,
    Map<String, String> metadata,
  ) {
    final value = kwargs[key];
    if (value == null) return metadata[key] ?? _defaultLangCode;
    if (value is String) return value;
    throw LlamaArgumentException(
      'chatTemplateKwargs["$key"] must be a String language code, '
      'got ${value.runtimeType}.',
      name: 'chatTemplateKwargs',
    );
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
        _sourceLangCodeKey: sourceLangCode,
        _targetLangCodeKey: targetLangCode,
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
