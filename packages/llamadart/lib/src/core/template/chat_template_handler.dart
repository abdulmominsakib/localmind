import 'package:dinja/dinja.dart';

import '../exceptions.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/chat_template_result.dart';
import '../models/tools/tool_definition.dart';
import 'chat_format.dart';
import 'chat_parse_result.dart';
import 'template_internal_metadata.dart';
import 'template_render_context.dart';
import 'thinking_utils.dart';
import 'tool_call_parsing_utils.dart';

export 'template_render_context.dart' show TemplateToolCallSerialization;

/// Abstract base class for per-format chat template handlers.
///
/// Each handler encapsulates format-specific logic for:
/// - Rendering messages into a prompt (via Jinja template)
/// - Parsing raw LLM output into structured content + tool calls
/// - Building GBNF grammar strings for constrained generation
///
/// Handlers are stateless singletons — all state lives in the arguments.
abstract class ChatTemplateHandler {
  /// The chat format this handler supports.
  ChatFormat get format;

  /// Start tag used for reasoning/thinking extraction.
  String get thinkingStartTag => '<think>';

  /// End tag used for reasoning/thinking extraction.
  String get thinkingEndTag => '</think>';

  /// Static additional stop sequences for backward compatibility.
  ///
  /// Prefer [getStops] for context-aware stop sequences.
  List<String> get additionalStops;

  /// Tool-call serialization shape expected by this handler's Jinja template.
  TemplateToolCallSerialization get toolCallSerialization =>
      TemplateToolCallSerialization.none;

  /// Builds the `messages` value passed to Jinja.
  ///
  /// Handlers should use this instead of calling [LlamaChatMessage.toJson]
  /// directly so template-specific tool-call shapes are applied only at the
  /// render-context boundary.
  List<Map<String, dynamic>> templateMessages(
    List<LlamaChatMessage> messages, {
    bool multimodal = false,
  }) {
    try {
      return TemplateRenderContext.messagesForTemplate(
        messages,
        toolCallSerialization: toolCallSerialization,
        multimodal: multimodal,
      );
    } catch (e, stackTrace) {
      if (toolCallSerialization.isEmpty) rethrow;
      final wrapped = LlamaInferenceException(
        'Failed to build render context for $format chat template while '
        'applying template-specific tool-call serialization. Verify tool-call '
        'arguments are JSON objects compatible with the selected template.',
        {'causeType': e.runtimeType.toString(), 'cause': e.toString()},
      );
      Error.throwWithStackTrace(wrapped, stackTrace);
    }
  }

  /// Returns context-aware stop sequences for this format.
  ///
  /// Matches llama.cpp's per-handler stop logic where stops vary based on
  /// whether tools are provided and whether thinking is enabled.
  ///
  /// Override in handlers that need context-dependent stops.
  List<String> getStops({bool hasTools = false, bool enableThinking = true}) {
    return additionalStops;
  }

  /// Returns preserved tokens for this format.
  ///
  /// Preserved tokens prevent grammar-constrained generation from consuming
  /// format-critical tokens. Override in handlers that need them.
  List<String> get preservedTokens => const [];

  /// Renders messages into a complete [LlamaChatTemplateResult].
  ///
  /// This calls the Jinja template with format-specific context setup,
  /// and optionally generates grammar + trigger info for tool calls.
  ///
  /// Parameters:
  /// - [templateSource]: The Jinja template string from model metadata
  /// - [messages]: The conversation history
  /// - [metadata]: Model metadata (for bos/eos tokens, etc.)
  /// - [addAssistant]: Whether to add generation prompt
  /// - [tools]: Optional tool definitions for function calling
  /// - [enableThinking]: Whether thinking/reasoning is enabled
  LlamaChatTemplateResult render({
    required String templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    bool enableThinking = true,
  });

  /// Parses raw LLM output into structured [ChatParseResult].
  ///
  /// Extracts content, reasoning/thinking, and tool calls from the
  /// raw text using format-specific delimiters and patterns.
  ///
  /// Parameters:
  /// - [output]: The raw LLM output text
  /// - [isPartial]: Whether this is a partial/streaming result
  /// - [parseToolCalls]: Whether to extract tool calls (false = content only)
  /// - [thinkingForcedOpen]: Whether thinking was force-opened in prompt
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  });

  /// Builds a GBNF grammar string for constraining tool call output.
  ///
  /// Returns `null` if [tools] is null/empty (no grammar needed).
  /// Each format wraps tool call JSON differently (e.g., `<tool_call>` tags
  /// for Hermes, `[TOOL_CALLS]` prefix for Mistral).
  String? buildGrammar(List<ToolDefinition>? tools);

  /// Renders [template] with [context] plus llama.cpp-style extra globals.
  ///
  /// This injects `chat_template_kwargs` values encoded by
  /// [ChatTemplateEngine]/[LlamaEngine] through metadata.
  String renderTemplate(
    Template template, {
    required Map<String, String> metadata,
    required Map<String, dynamic> context,
  }) {
    return template.render(<String, dynamic>{
      ..._templateContextFromMetadata(metadata),
      ...context,
    });
  }

  /// Re-renders with content always in list-of-parts format.
  ///
  /// Some templates (e.g. SmolVLM) expect `content` to be
  /// `[{type: 'text', text: '...'}, {type: 'image'}]` rather than a string.
  /// This method converts messages to multimodal format and re-renders.
  ///
  /// After rendering, replaces model-specific image placeholders with
  /// the mtmd marker `<__media__>` so the native tokenizer can find them.
  LlamaChatTemplateResult renderWithMultimodalContent({
    required String templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    bool enableThinking = true,
  }) {
    final template = Template(templateSource);
    var prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': templateMessages(messages, multimodal: true),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'enable_thinking': enableThinking,
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '',
      },
    );

    var thinkingForcedOpen = false;
    if (isThinkingForcedOpen(prompt, startTag: thinkingStartTag.trimRight())) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}$thinkingEndTag\n';
      } else {
        thinkingForcedOpen = true;
      }
    }

    // Post-process: replace model-specific image placeholders with
    // the mtmd marker so the native tokenizer can match bitmaps to markers.
    const mtmdMarker = '<__media__>';
    const imagePlaceholders = [
      '<image>', // SmolVLM, InternVL, etc.
      '[IMG]', // Some CLIP-based models
      '<|image|>', // Phi-3 vision
      '<|audio|>',
      '<|video|>',
      '<image_soft_token>',
      '<audio_soft_token>',
      '<video_soft_token>',
    ];
    for (final placeholder in imagePlaceholders) {
      prompt = prompt.replaceAll(placeholder, mtmdMarker);
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
      thinkingForcedOpen: thinkingForcedOpen,
    );
  }

  Map<String, dynamic> _templateContextFromMetadata(
    Map<String, String> metadata,
  ) {
    final context = <String, dynamic>{};

    final rawKwargs = metadata[internalChatTemplateKwargsMetadataKey];
    if (rawKwargs != null && rawKwargs.trim().isNotEmpty) {
      try {
        final decoded = ToolCallParsingUtils.decodeJsonValue(rawKwargs);
        final kwargs = ToolCallParsingUtils.coerceMap(decoded);
        if (kwargs != null) {
          context.addAll(kwargs);
        }
      } catch (_) {
        // Ignore invalid internal metadata payloads and render without extras.
      }
    }

    return context;
  }

  /// Resolves a caller-provided template `now` value or falls back to current
  /// wall-clock time.
  DateTime resolveTemplateNow(Map<String, String> metadata) {
    final rawNow = metadata[internalTemplateNowMetadataKey];
    if (rawNow != null && rawNow.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(rawNow);
      if (parsed != null) {
        return parsed;
      }
    }
    return DateTime.now();
  }
}
