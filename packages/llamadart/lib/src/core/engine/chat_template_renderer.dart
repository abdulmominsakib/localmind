import '../exceptions.dart';
import '../llama_logger.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/chat_template_result.dart';
import '../models/chat/tool_result_parts.dart';
import '../models/inference/tool_choice.dart';
import '../models/tools/tool_definition.dart';
import '../template/chat_template_engine.dart';
import '../template/media_placeholders.dart';
import '../template/template_internal_metadata.dart';
import '../template/thinking_utils.dart';

/// Metadata key of the template llamadart parses with when a runtime
/// renders another one, which `tokenizer.chat_template` then holds.
const String parsingChatTemplateMetadataKey = 'llamadart.chat_template.parsing';

/// Loads model metadata for chat-template rendering.
typedef ChatTemplateMetadataLoader = Future<Map<String, String>> Function();

/// Tokenizes rendered prompts when callers request a token count.
typedef ChatTemplateTokenizer =
    Future<List<int>> Function(String text, {bool addSpecial});

/// Tokenizes a prompt as the runtime that renders it prefills it.
typedef ChatTemplateRuntimePromptTokenizer =
    Future<List<int>> Function(String prompt);

/// Renders model chat templates for [LlamaEngine].
///
/// The public API stays on [LlamaEngine], while this helper owns metadata
/// preparation, response-format normalization, and optional token counting.
class ChatTemplateRenderer {
  const ChatTemplateRenderer._();

  /// Whether [messages] carry an image, audio or video part, including one
  /// in a tool result's `content`.
  static bool carriesMedia(List<LlamaChatMessage> messages) =>
      messages.any((message) => partsInPromptOrder(message).any(isMediaPart));

  /// Names the template [render] uses when no `tool_use` variant or
  /// `customTemplate` applies, for render-failure messages.
  ///
  /// A non-empty [modelTemplate] is `ModelParams.chatTemplate`; otherwise
  /// a non-null [parsingTemplate] is the model's
  /// [parsingChatTemplateMetadataKey], and a non-empty [metadataTemplate] its
  /// `tokenizer.chat_template`. Otherwise the built-in ChatML fallback is
  /// used.
  static String templateSourceName({
    String? modelTemplate,
    String? metadataTemplate,
    String? parsingTemplate,
  }) {
    if (modelTemplate != null && modelTemplate.isNotEmpty) {
      return 'ModelParams.chatTemplate';
    }
    if (parsingTemplate != null) {
      return "the model's $parsingChatTemplateMetadataKey";
    }
    if (metadataTemplate != null && metadataTemplate.isNotEmpty) {
      return "the model's tokenizer.chat_template";
    }
    return 'the built-in ChatML fallback template';
  }

  /// Renders a chat template and optionally counts prompt tokens.
  ///
  /// A non-empty [modelTemplate] replaces the model's `tokenizer.chat_template`
  /// and its `tool_use` variant, as llama.cpp's `--chat-template` does;
  /// [customTemplate] still takes precedence over both. Without either, a
  /// [parsingChatTemplateMetadataKey] in the metadata comes before
  /// `tokenizer.chat_template`.
  ///
  /// With [renderRuntimePrompt] and no [customTemplate], a model whose
  /// metadata has a [parsingChatTemplateMetadataKey] gets the prompt and
  /// token count of its `tokenizer.chat_template`, the template its runtime
  /// renders, rendered as plain Jinja; every other field still comes from
  /// the parsing template. When that render fails, the parsing render's
  /// prompt is kept and a warning logged. A runtime prompt is counted with
  /// [tokenizeRuntimePrompt] when given, every other prompt with [tokenize]
  /// and no special tokens added.
  ///
  /// A request that carries media is rendered with [chatPromptMediaMarker]
  /// where each part was. With [keepChatMarker] the prompt keeps it, for a
  /// backend that takes chat prompts. Otherwise the prompt is one that reads
  /// the same through `generate`: `<__media__>` where each part was, and a
  /// zero-width space in every other string `generate` would read as a part.
  /// A request without media is rendered as it is.
  static Future<LlamaChatTemplateResult> render({
    required ChatTemplateMetadataLoader loadMetadata,
    required ChatTemplateTokenizer tokenize,
    ChatTemplateRuntimePromptTokenizer? tokenizeRuntimePrompt,
    required List<LlamaChatMessage> messages,
    bool addAssistant = true,
    Map<String, dynamic>? jsonSchema,
    List<ToolDefinition>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? responseFormat,
    String? customTemplate,
    String? modelTemplate,
    bool includeTokenCount = true,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
    bool keepChatMarker = false,
    bool renderRuntimePrompt = false,
  }) async {
    Map<String, String> metadata = {};
    try {
      metadata = {...await loadMetadata()};
    } catch (error) {
      LlamaLogger.instance.warning('Failed to read metadata: $error');
    }
    final parsingTemplate = metadata[parsingChatTemplateMetadataKey];
    final runtimeTemplate = parsingTemplate == null
        ? null
        : metadata['tokenizer.chat_template'];
    final String? templateSource;
    if (modelTemplate != null && modelTemplate.isNotEmpty) {
      templateSource = modelTemplate;
      metadata.remove('tokenizer.chat_template.tool_use');
    } else {
      templateSource = parsingTemplate ?? metadata['tokenizer.chat_template'];
    }
    metadata[internalTemplateSourceNameMetadataKey] = templateSourceName(
      modelTemplate: modelTemplate,
      metadataTemplate: metadata['tokenizer.chat_template'],
      parsingTemplate: parsingTemplate,
    );

    final effectiveResponseFormat =
        responseFormat ??
        (jsonSchema == null
            ? null
            : {
                'type': 'json_schema',
                'json_schema': {'schema': jsonSchema},
              });

    final hasMedia = carriesMedia(messages);
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
      mediaMarker: hasMedia ? chatPromptMediaMarker : mtmdMediaMarker,
    );
    final runtimePrompt =
        renderRuntimePrompt && customTemplate == null && runtimeTemplate != null
        ? _runtimePrompt(
            runtimeTemplate,
            messages: messages,
            metadata: metadata,
            addAssistant: addAssistant,
            tools: tools,
            toolChoice: toolChoice,
            enableThinking: enableThinking,
            chatTemplateKwargs: chatTemplateKwargs,
            templateNow: templateNow,
            mediaMarker: hasMedia ? chatPromptMediaMarker : mtmdMediaMarker,
          )
        : null;
    final renderedPrompt = runtimePrompt ?? result.prompt;
    final prompt = hasMedia && !keepChatMarker
        ? chatPromptAsCallerPrompt(
            renderedPrompt,
            chatMarker: chatPromptMediaMarker,
          )
        : renderedPrompt;

    int? tokenCount;
    if (includeTokenCount) {
      try {
        final tokens = runtimePrompt != null && tokenizeRuntimePrompt != null
            ? await tokenizeRuntimePrompt(prompt)
            : await tokenize(prompt, addSpecial: false);
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

    final copy = LlamaChatTemplateResult(
      prompt: prompt,
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
    return withThoughtMarksOf(copy, result);
  }

  static String? _runtimePrompt(
    String template, {
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    required bool addAssistant,
    required List<ToolDefinition>? tools,
    required ToolChoice toolChoice,
    required bool enableThinking,
    required Map<String, dynamic>? chatTemplateKwargs,
    required DateTime? templateNow,
    required String mediaMarker,
  }) {
    // Templates also raise Errors, such as UnsupportedError for integer
    // division by zero; showing a prompt must not fail on either.
    try {
      return renderPlainChatTemplatePrompt(
        templateSource: template,
        templateName: "the model's tokenizer.chat_template",
        messages: messages,
        metadata: metadata,
        addAssistant: addAssistant,
        tools: tools,
        toolChoice: toolChoice,
        enableThinking: enableThinking,
        chatTemplateKwargs: chatTemplateKwargs,
        now: templateNow,
        mediaMarker: mediaMarker,
      );
    } on Object catch (error) {
      LlamaLogger.instance.warning(
        'Showing the prompt of the parsing chat template: the model '
        'runtime template did not render in Dart: $error',
      );
      return null;
    }
  }
}
