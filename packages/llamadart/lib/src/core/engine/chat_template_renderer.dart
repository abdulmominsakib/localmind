import '../exceptions.dart';
import '../llama_logger.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/chat_template_result.dart';
import '../models/inference/tool_choice.dart';
import '../models/tools/tool_definition.dart';
import '../template/chat_template_engine.dart';

/// Loads model metadata for chat-template rendering.
typedef ChatTemplateMetadataLoader = Future<Map<String, String>> Function();

/// Tokenizes rendered prompts when callers request a token count.
typedef ChatTemplateTokenizer =
    Future<List<int>> Function(String text, {bool addSpecial});

/// Renders model chat templates for [LlamaEngine].
///
/// The public API stays on [LlamaEngine], while this helper owns metadata
/// preparation, response-format normalization, and optional token counting.
class ChatTemplateRenderer {
  const ChatTemplateRenderer._();

  /// Renders a chat template and optionally counts prompt tokens.
  static Future<LlamaChatTemplateResult> render({
    required ChatTemplateMetadataLoader loadMetadata,
    required ChatTemplateTokenizer tokenize,
    required List<LlamaChatMessage> messages,
    bool addAssistant = true,
    Map<String, dynamic>? jsonSchema,
    List<ToolDefinition>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? responseFormat,
    String? customTemplate,
    String? sourceLangCode,
    String? targetLangCode,
    bool includeTokenCount = true,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async {
    String? templateSource;
    Map<String, String> metadata = {};
    try {
      metadata = await loadMetadata();
      templateSource = metadata['tokenizer.chat_template'];
    } catch (error) {
      LlamaLogger.instance.warning('Failed to read metadata: $error');
    }

    if (sourceLangCode != null && sourceLangCode.isNotEmpty) {
      metadata['source_lang_code'] = sourceLangCode;
    }
    if (targetLangCode != null && targetLangCode.isNotEmpty) {
      metadata['target_lang_code'] = targetLangCode;
    }

    final effectiveResponseFormat =
        responseFormat ??
        (jsonSchema == null
            ? null
            : {
                'type': 'json_schema',
                'json_schema': {'schema': jsonSchema},
              });

    final result = ChatTemplateEngine.render(
      templateSource: templateSource,
      messages: messages,
      metadata: metadata,
      addAssistant: addAssistant,
      tools: tools,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      responseFormat: effectiveResponseFormat,
      customTemplate: customTemplate,
      chatTemplateKwargs: chatTemplateKwargs,
      now: templateNow,
    );

    int? tokenCount;
    if (includeTokenCount) {
      try {
        final tokens = await tokenize(result.prompt, addSpecial: false);
        tokenCount = tokens.length;
      } on UnsupportedError catch (error) {
        LlamaLogger.instance.debug(
          'Skipping chat template token count because backend tokenization '
          'is unsupported: $error',
        );
      } on LlamaUnsupportedException catch (error) {
        LlamaLogger.instance.debug(
          'Skipping chat template token count because backend tokenization '
          'is unsupported: $error',
        );
      }
    }

    return LlamaChatTemplateResult(
      prompt: result.prompt,
      format: result.format,
      grammar: result.grammar,
      grammarLazy: result.grammarLazy,
      additionalStops: result.additionalStops,
      grammarTriggers: result.grammarTriggers,
      thinkingForcedOpen: result.thinkingForcedOpen,
      preservedTokens: result.preservedTokens,
      parser: result.parser,
      tokenCount: tokenCount,
    );
  }
}
