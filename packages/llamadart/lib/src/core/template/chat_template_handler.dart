import 'dart:async';

import 'package:dinja/dinja.dart';

import '../exceptions.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/chat_template_result.dart';
import '../models/chat/content_part.dart';
import '../models/inference/tool_choice.dart';
import '../models/tools/tool_definition.dart';
import 'chat_format.dart';
import 'media_placeholders.dart';
import 'chat_parse_result.dart';
import 'template_caps.dart';
import 'template_internal_metadata.dart';
import 'template_render_context.dart';
import 'tool_call_grammar_utils.dart';

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
  /// render-context boundary. Pass the [templateSource] being rendered:
  /// tool-call arguments become objects when [TemplateCaps] detects that it
  /// reads them as objects, and string content becomes a text part when it
  /// reads content only as parts, as llama.cpp does. A handler that builds
  /// typed parts itself passes `typedContent: false` to keep string content.
  /// Inside [renderWithToolResultsAsUserTurns], tool results become user
  /// turns, with tool calls in `content` when [TemplateCaps] finds the
  /// template cannot render them. With
  /// [multimodal], each media part becomes [mediaMarker] in the message
  /// text.
  List<Map<String, dynamic>> templateMessages(
    List<LlamaChatMessage> messages, {
    bool multimodal = false,
    String mediaMarker = mtmdMediaMarker,
    String? templateSource,
    bool typedContent = true,
  }) {
    final caps = templateSource == null
        ? null
        : TemplateCaps.detect(templateSource);
    final polyfill =
        caps != null && Zone.current[_toolResultsAsUserTurns] == true;
    try {
      return TemplateRenderContext.messagesForTemplate(
        messages,
        toolCallSerialization: toolCallSerialization,
        multimodal: multimodal,
        mediaMarker: mediaMarker,
        objectArguments: caps?.supportsObjectArguments ?? false,
        typedContentOnly:
            typedContent &&
            caps != null &&
            caps.supportsTypedContent &&
            !caps.supportsStringContent,
        stringContentOnly:
            caps != null &&
            caps.supportsStringContent &&
            !caps.supportsTypedContent,
        toolResultsAsUser: polyfill,
        toolCallsAsContent: polyfill && !caps.supportsToolCalls,
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

  /// Returns [grammar], or for a [ToolChoice.required] request in [metadata]
  /// after a forced-open thought, [grammar] preceded by that thought and its
  /// [thinkingEndTag], so the parse finds the calls outside it.
  String? requiredGrammarAfterThought(
    String? grammar, {
    required Map<String, String> metadata,
    required bool thinkingForcedOpen,
  }) =>
      grammar != null &&
          thinkingForcedOpen &&
          metadata[internalToolChoiceMetadataKey] == ToolChoice.required.name
      ? ToolCallGrammarUtils.afterForcedOpenThought(grammar, thinkingEndTag)
      : grammar;

  /// Renders [template] with [context] plus llama.cpp-style extra globals.
  ///
  /// This injects `chat_template_kwargs` values encoded by
  /// [ChatTemplateEngine]/[LlamaEngine] through metadata. [context] overrides
  /// them, and they override [defaults]: template settings derived from
  /// `enableThinking` that a caller can set itself, as in llama-server.
  String renderTemplate(
    Template template, {
    required Map<String, String> metadata,
    required Map<String, dynamic> context,
    Map<String, dynamic> defaults = const {},
  }) {
    final templateNow = DateTime.tryParse(
      metadata[internalTemplateNowMetadataKey] ?? '',
    );
    return template.render(<String, dynamic>{
      ...defaults,
      ...chatTemplateKwargsFromMetadata(metadata),
      ...context,
      if (templateNow != null) 'strftime_now': strftimeNow(templateNow),
    });
  }

  /// Renders a request that carries media for a template that reads both
  /// string and typed content.
  ///
  /// Each image, audio or video part becomes [mediaMarker] in the message
  /// text, where the part was, as llama.cpp renders it. The template's own
  /// placeholder for a typed media part is not written, and a placeholder
  /// string in message text stays text. The request then goes through
  /// [render], so it gets the grammar, triggers, preserved tokens, parser and
  /// stops of the same text request: llama-server applies one chat format to
  /// both.
  LlamaChatTemplateResult renderWithMultimodalContent({
    required String templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    bool enableThinking = true,
    String mediaMarker = mtmdMediaMarker,
  }) {
    bool isMedia(LlamaContentPart part) =>
        part is LlamaImageContent ||
        part is LlamaAudioContent ||
        part is LlamaVideoContent;
    return render(
      templateSource: templateSource,
      messages: [
        for (final message in messages)
          message.parts.any(isMedia)
              ? message.copyWith(
                  parts: [
                    for (final part in message.parts)
                      isMedia(part) ? LlamaTextContent(mediaMarker) : part,
                  ],
                )
              : message,
      ],
      metadata: metadata,
      addAssistant: addAssistant,
      tools: tools,
      enableThinking: enableThinking,
    );
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

final Object _toolResultsAsUserTurns = Object();

/// Runs [render] so that [ChatTemplateHandler.templateMessages] sends tool
/// results as user turns to a template that rejects the `tool` role.
///
/// `ChatTemplateEngine` uses it only to retry a failed render for a template
/// whose [TemplateCaps.supportsToolResponses] is `false`, so a request the
/// template renders as given is never changed.
T renderWithToolResultsAsUserTurns<T>(T Function() render) =>
    runZoned(render, zoneValues: {_toolResultsAsUserTurns: true});

/// Optional handler contract for output formats whose argument decoding depends
/// on the tool JSON schemas supplied for the completion request.
///
/// [ChatTemplateEngine] uses this contract when schemas are available while
/// retaining [ChatTemplateHandler.parse] for callers that only have raw output.
abstract interface class ToolSchemaAwareChatTemplateHandler {
  /// Parses [output] using [tools] to validate names, required properties, and
  /// schema-directed argument types.
  ChatParseResult parseWithTools(
    String output, {
    List<ToolDefinition>? tools,
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  });
}
