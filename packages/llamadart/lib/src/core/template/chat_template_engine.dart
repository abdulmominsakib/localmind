import 'dart:convert';

import '../exceptions.dart';
import '../grammar/tool_grammar_generator.dart' as grammar;
import '../llama_logger.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/chat_role.dart';
import '../models/chat/chat_template_result.dart';
import '../models/chat/content_part.dart';
import '../models/chat/tool_result_parts.dart';
import '../models/inference/generation_params.dart';
import '../models/inference/tool_choice.dart';
import '../models/tools/tool_definition.dart';
import 'chat_format.dart';
import 'chat_format_registry.dart';
import 'chat_parse_result.dart';
import 'peg_chat_parser.dart';
import 'chat_template_handler.dart';
import 'media_placeholders.dart';
import 'handlers/cohere2_moe_handler.dart';
import 'handlers/generic_handler.dart';
import 'handlers/deepseek_v3_handler.dart';
import 'handlers/ling3_handler.dart';
import 'handlers/hermes_handler.dart';
import 'handlers/qwen3_coder_xml_handler.dart';
import 'response_format.dart';
import 'tool_call_grammar_utils.dart';
import 'tool_schema_utils.dart';
import 'template_caps.dart';
import 'template_internal_metadata.dart';
import 'template_render_context.dart';
import 'thinking_utils.dart';

/// Orchestrates chat template detection, rendering, and output parsing.
///
/// This is the main entry point for the template module. It:
/// 1. Detects the chat format from the Jinja template source
/// 2. Delegates to the appropriate per-format handler for rendering
/// 3. Provides output parsing via the detected format's handler
///
/// Usage:
/// ```dart
/// final result = ChatTemplateEngine.render(
///   templateSource: metadata['tokenizer.chat_template'],
///   messages: messages,
///   metadata: metadata,
///   tools: tools,
///   toolChoice: toolChoice,
///   enableThinking: true,
/// );
/// // Later, parse the output:
/// final parsed = ChatTemplateEngine.parseRendered(
///   result,
///   rawOutput,
///   tools: tools,
///   parseToolCalls: tools.isNotEmpty && toolChoice != ToolChoice.none,
/// );
/// ```
class ChatTemplateEngine {
  static const String _genericToolSystemInstruction =
      'Respond in JSON format, either with `tool_call` '
      '(a request to call tools) or with `response` reply '
      'to the user\'s request';

  /// Singleton handler instances, lazily initialized.
  static final Map<ChatFormat, ChatTemplateHandler> _handlers = {};

  /// Returns the handler for the given [format].
  static ChatTemplateHandler handlerFor(ChatFormat format) {
    return _handlers.putIfAbsent(
      format,
      () => chatFormatRegistration(format).createHandler(),
    );
  }

  /// Detects the [ChatFormat] from a template source string.
  static ChatFormat detectFormat(String? templateSource) {
    return detectChatFormat(templateSource);
  }

  /// Full rendering pipeline: detect format → get handler → render.
  ///
  /// If the template source is null/empty, uses the ChatML fallback.
  /// [responseFormat] takes the shapes documented on `LlamaEngine.create`;
  /// any other shape throws `LlamaUnsupportedException`.
  ///
  /// A template that fails to render, by raising, through invalid syntax or
  /// by overflowing the stack on the Dart VM or JavaScript, throws
  /// `LlamaInferenceException` with the template's message. The message names
  /// [customTemplate], the `tool_use` variant in [metadata], or [templateSource].
  /// On dart2wasm, stack overflow cannot be caught and may trap or hang
  /// instead of throwing this exception.
  ///
  /// A boolean `enable_thinking` in [chatTemplateKwargs], or failing that a
  /// boolean `thinking`, overrides [enableThinking], as in llama-server.
  ///
  /// [mediaMarker] is written where each image, audio or video part was.
  /// Pass one that message text cannot hold to tell the parts from a
  /// placeholder string a message quotes.
  static LlamaChatTemplateResult render({
    required String? templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? responseFormat,
    String? customTemplate,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? now,
    String mediaMarker = mtmdMediaMarker,
  }) => _render(
    templateSource: templateSource,
    messages: messages,
    metadata: metadata,
    addAssistant: addAssistant,
    tools: tools,
    toolChoice: toolChoice,
    parallelToolCalls: parallelToolCalls,
    enableThinking: enableThinking,
    responseFormat: responseFormat,
    customTemplate: customTemplate,
    chatTemplateKwargs: chatTemplateKwargs,
    now: now,
    mediaMarker: mediaMarker,
    plainTemplate: false,
  );

  static LlamaChatTemplateResult _render({
    required String? templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    required bool addAssistant,
    required List<ToolDefinition>? tools,
    required ToolChoice toolChoice,
    required bool parallelToolCalls,
    required bool enableThinking,
    required Map<String, dynamic>? responseFormat,
    required String? customTemplate,
    required Map<String, dynamic>? chatTemplateKwargs,
    required DateTime? now,
    required String mediaMarker,
    required bool plainTemplate,
  }) {
    enableThinking = effectiveEnableThinking(
      enableThinking,
      chatTemplateKwargs,
    );
    final responseSchema = responseFormatSchema(responseFormat);

    // 1. Select template source (default vs tool_use variant)
    final hasTools = tools != null && tools.isNotEmpty;
    final allowToolCalls = hasTools && toolChoice != ToolChoice.none;
    final effectiveTools = allowToolCalls ? tools : null;
    var metadataTemplate = templateSource;
    var templateName =
        metadata[internalTemplateSourceNameMetadataKey] ?? 'templateSource';

    if (!plainTemplate &&
        allowToolCalls &&
        metadata.containsKey('tokenizer.chat_template.tool_use')) {
      metadataTemplate = metadata['tokenizer.chat_template.tool_use'];
      templateName = "the model's tokenizer.chat_template.tool_use";
      LlamaLogger.instance.debug(
        'ChatTemplateEngine: Using tool_use template variant',
      );
    }

    var effectiveTemplate = customTemplate;
    if (effectiveTemplate != null) {
      templateName = 'customTemplate';
      LlamaLogger.instance.debug(
        'ChatTemplateEngine: Using per-call custom template override',
      );
    } else {
      effectiveTemplate = metadataTemplate;
    }

    final hasSchemaResponseFormat = responseSchema != null;

    final format = plainTemplate
        ? ChatFormat.contentOnly
        : detectFormat(effectiveTemplate);
    LlamaLogger.instance.debug(
      'ChatTemplateEngine: Detected format=$format from template',
    );

    final traits = chatFormatRegistration(format).traits;
    ChatFormat effectiveFormat;
    // Match llama.cpp schema-aware routing: tools + schema falls back to
    // generic routing, and some format handlers are disabled with schema.
    if (plainTemplate) {
      effectiveFormat = ChatFormat.contentOnly;
    } else if (allowToolCalls && hasSchemaResponseFormat) {
      effectiveFormat = ChatFormat.generic;
    } else if (hasTools &&
        toolChoice == ToolChoice.none &&
        traits.toolChoiceNoneRendersContentOnly) {
      effectiveFormat = ChatFormat.contentOnly;
    } else if (traits.routesThroughGeneric) {
      effectiveFormat = allowToolCalls
          ? ChatFormat.generic
          : ChatFormat.contentOnly;
    } else if (hasSchemaResponseFormat && traits.disabledByResponseSchema) {
      effectiveFormat = allowToolCalls
          ? ChatFormat.generic
          : ChatFormat.contentOnly;
    } else {
      effectiveFormat = format;
    }

    // Use generic handler fallback when template is missing, or when tool
    // calling is requested for an unknown/unclassified template.
    if (!plainTemplate &&
        effectiveFormat == ChatFormat.contentOnly &&
        (effectiveTemplate == null || allowToolCalls)) {
      effectiveFormat = ChatFormat.generic;
    }

    if (!plainTemplate && (effectiveTools?.any(toolUsesJsonSchema) ?? false)) {
      if (!chatFormatRegistration(
        effectiveFormat,
      ).traits.qualifiesJsonSchemaTools) {
        throw LlamaUnsupportedException(
          'Canonical JSON Schema tools are not qualified for $effectiveFormat. Use a supported JSON-envelope format or the legacy ToolParam API.',
        );
      }
    }

    if (carriesToolResultContent(messages)) {
      validateToolResultContent(messages);
      if (!plainTemplate &&
          !chatFormatRegistration(
            effectiveFormat,
          ).traits.rendersToolResultContent) {
        throw LlamaUnsupportedException(
          'LlamaToolResultContent.content is not qualified for '
          '$effectiveFormat chat templates. Only Hermes-style <tool_call> '
          'templates, smoke-tested with the Qwen3-VL template, render it; '
          'return a text or JSON result without content for this template.',
        );
      }
    }

    final handler = handlerFor(effectiveFormat);

    // 3. Prepare template capabilities and render context matching llama.cpp
    final caps = TemplateCaps.detect(effectiveTemplate ?? '');
    // Capability probes describe history rendering; the caller selects the
    // output protocol's parallel bound, as in llama.cpp.
    final effectiveParallelToolCalls = allowToolCalls && parallelToolCalls;
    if (parallelToolCalls && !effectiveParallelToolCalls) {
      LlamaLogger.instance.debug(
        'ChatTemplateEngine: Disabling parallelToolCalls because tool calls '
        'are disabled.',
      );
    }

    final handlerMetadata = _withInternalMetadata(
      metadata,
      toolChoice: toolChoice,
      parallelToolCalls: effectiveParallelToolCalls,
      // llama.cpp gives every template `enable_thinking`, as resolved above.
      chatTemplateKwargs: {
        ...?chatTemplateKwargs,
        'enable_thinking': enableThinking,
      },
      now: now,
    );
    // A tool result's content becomes text in the result, with the marker at
    // each media part, as llama.cpp's server renders an array tool message.
    var effectiveMessages = carriesToolResultContent(messages)
        ? [
            for (final message in messages)
              TemplateRenderContext.withToolResultMediaMarkers(
                message,
                mediaMarker,
              ),
          ]
        : messages;
    final toolResultMediaCount = toolResultMediaIn(messages).isEmpty
        ? null
        : messages.expand(partsInPromptOrder).where(isMediaPart).length;

    if (allowToolCalls && caps.supportsToolCalls && !caps.supportsTools) {
      LlamaLogger.instance.warning(
        'ChatTemplateEngine: Template appears to support tool-call output but '
        'does not advertise tool definitions. Results may be unreliable; '
        'consider overriding the chat template.',
      );
    }

    // Apply typed message preparation before render-context serialization.
    if (!caps.supportsSystemRole) {
      effectiveMessages = TemplateRenderContext.mergeLeadingSystemMessage(
        effectiveMessages,
        supportsSystemRole: caps.supportsSystemRole,
      );
    }

    if (allowToolCalls && effectiveFormat == ChatFormat.generic) {
      effectiveMessages = _injectSystemInstructionLikeLlamaCpp(
        effectiveMessages,
        _genericToolSystemInstruction,
        supportsSystemRole: caps.supportsSystemRole,
      );
    }

    final retryWithToolResultsAsUser =
        !caps.supportsToolResponses &&
        effectiveMessages.any(
          (message) =>
              message.role == LlamaChatRole.tool ||
              message.parts.any((part) => part is LlamaToolResultContent),
        );

    // No template gets a media part: each becomes the media marker in the
    // message text, as llama.cpp renders it. Templates that also read string
    // content take it through renderWithMultimodalContent. Templates that
    // read only typed parts (e.g. SmolVLM's `message['content'][0]['type']`)
    // get it in a text part.
    // Tool-result media are already marker text in their result.
    final hasMediaParts = effectiveMessages.any(
      (message) => message.parts.any(
        (part) => part is LlamaImageContent || part is LlamaAudioContent,
      ),
    );
    final needsTypedContent =
        caps.supportsTypedContent &&
        caps.supportsStringContent &&
        hasMediaParts;

    if (needsTypedContent) {
      LlamaLogger.instance.debug(
        'ChatTemplateEngine: Using multimodal content format '
        'for template that accesses content as list',
      );
      var rendered = _renderTemplate(
        templateName,
        retryWithToolResultsAsUser: retryWithToolResultsAsUser,
        () => handler.renderWithMultimodalContent(
          templateSource: effectiveTemplate ?? GenericHandler.chatMlTemplate,
          messages: effectiveMessages,
          metadata: handlerMetadata,
          addAssistant: addAssistant,
          tools: effectiveTools,
          enableThinking: enableThinking,
          mediaMarker: mediaMarker,
        ),
      );
      rendered = withTemplateOpenedThought(
        _withCohereThoughtClosed(
          rendered,
          format: format,
          effectiveFormat: effectiveFormat,
          enableThinking: enableThinking,
        ),
        startTag: handler.thinkingStartTag,
      );
      if (effectiveFormat == ChatFormat.contentOnly) {
        rendered = _withFormat(rendered, ChatFormat.contentOnly.index);
      }
      _requireMediaMarkers(
        rendered.prompt,
        mediaMarker: mediaMarker,
        expected: toolResultMediaCount,
        templateName: templateName,
      );
      if (plainTemplate) return rendered;

      final withGrammar = _applyGrammar(
        rendered,
        effectiveTools,
        toolChoice,
        responseSchema,
        thinkingEndTag: handler.thinkingEndTag,
      );
      return _normalizeGrammarLazyForToolChoice(withGrammar, toolChoice);
    }

    // Other templates cannot consume transport objects. Keep media in the
    // original request for the backend and render only its placeholder here,
    // in content order, as llama.cpp does for media_marker parts.
    bool isTransport(LlamaContentPart part) =>
        part is LlamaImageContent ||
        part is LlamaAudioContent ||
        part is LlamaVideoContent;
    if (effectiveMessages.any((message) => message.parts.any(isTransport))) {
      effectiveMessages = effectiveMessages
          .map((message) {
            return message.copyWith(
              parts: message.parts
                  .map((part) {
                    return isTransport(part)
                        ? LlamaTextContent(mediaMarker)
                        : part;
                  })
                  .toList(growable: false),
            );
          })
          .toList(growable: false);
    }

    var baseResult = _renderTemplate(
      templateName,
      retryWithToolResultsAsUser: retryWithToolResultsAsUser,
      () => handler.render(
        templateSource: effectiveTemplate ?? GenericHandler.chatMlTemplate,
        messages: effectiveMessages,
        metadata: handlerMetadata,
        addAssistant: addAssistant,
        tools: effectiveTools,
        enableThinking: enableThinking,
      ),
    );

    baseResult = withTemplateOpenedThought(
      _withCohereThoughtClosed(
        baseResult,
        format: format,
        effectiveFormat: effectiveFormat,
        enableThinking: enableThinking,
      ),
      startTag: handler.thinkingStartTag,
    );
    if (effectiveFormat == ChatFormat.contentOnly) {
      baseResult = _withFormat(baseResult, ChatFormat.contentOnly.index);
    }
    _requireMediaMarkers(
      baseResult.prompt,
      mediaMarker: mediaMarker,
      expected: toolResultMediaCount,
      templateName: templateName,
    );
    if (plainTemplate) return baseResult;

    // Apply grammar constraints for tool calls or response format
    final withGrammar = _applyGrammar(
      baseResult,
      effectiveTools,
      toolChoice,
      responseSchema,
      thinkingEndTag: handler.thinkingEndTag,
    );
    return _normalizeGrammarLazyForToolChoice(withGrammar, toolChoice);
  }

  /// [result], with thinking off, closing the thought that a Cohere2 MoE
  /// template opens when another handler renders it, as for a response
  /// schema, the way [Cohere2MoeHandler] closes it.
  static LlamaChatTemplateResult _withCohereThoughtClosed(
    LlamaChatTemplateResult result, {
    required ChatFormat format,
    required ChatFormat effectiveFormat,
    required bool enableThinking,
  }) {
    final cohere = handlerFor(ChatFormat.cohere2Moe);
    if (format != ChatFormat.cohere2Moe ||
        effectiveFormat == format ||
        enableThinking ||
        !isThinkingForcedOpen(
          result.prompt,
          startTag: cohere.thinkingStartTag,
        )) {
      return result;
    }
    return withThoughtMarksOf(
      LlamaChatTemplateResult(
        prompt: '${result.prompt.trimRight()}${cohere.thinkingEndTag}',
        format: result.format,
        grammar: result.grammar,
        grammarLazy: result.grammarLazy,
        additionalStops: result.additionalStops,
        preservedTokens: result.preservedTokens,
        grammarTriggers: result.grammarTriggers,
        thinkingForcedOpen: result.thinkingForcedOpen,
        parser: result.parser,
        tokenCount: result.tokenCount,
      ),
      result,
    );
  }

  /// Runs a handler [render], turning an [Exception] that is not already a
  /// [LlamaException] (a template's own `raise_exception`, a failure the
  /// Jinja runtime throws as an `Exception`, invalid template syntax) into a
  /// [LlamaInferenceException] that names the template by [templateName].
  /// A [StackOverflowError] from a recursive template is also wrapped;
  /// other [Error]s are left as they are.
  ///
  /// With [retryWithToolResultsAsUser], a render that throws an [Exception]
  /// other than [LlamaException] is retried once with tool results as user
  /// turns if the template rejects the `tool` role
  /// (see [renderWithToolResultsAsUserTurns]). A request the template renders
  /// as given is never changed. When the retry fails in any way, the first
  /// failure is reported.
  static LlamaChatTemplateResult _renderTemplate(
    String templateName,
    LlamaChatTemplateResult Function() render, {
    required bool retryWithToolResultsAsUser,
  }) {
    try {
      return render();
    } on LlamaException {
      rethrow;
    } on StackOverflowError catch (error, stackTrace) {
      Error.throwWithStackTrace(
        LlamaInferenceException(
          'The chat template from $templateName failed to render: $error',
        ),
        stackTrace,
      );
    } on Exception catch (error, stackTrace) {
      if (retryWithToolResultsAsUser) {
        try {
          return renderWithToolResultsAsUserTurns(render);
        } catch (_) {
          // Report the template's error for the request as given.
        }
      }
      final cause = error.toString();
      const prefix = 'Exception: ';
      Error.throwWithStackTrace(
        LlamaInferenceException(
          'The chat template from $templateName failed to render: '
          '${cause.startsWith(prefix) ? cause.substring(prefix.length) : cause}',
        ),
        stackTrace,
      );
    }
  }

  /// Apply grammar constraints based on tool definitions and response format.
  ///
  /// After a forced-open thought, a grammar added here first takes the rest of
  /// the thought and [thinkingEndTag], as llama.cpp's reasoning parser does:
  /// it applies from the first token, and unclosed output parses as
  /// reasoning.
  static LlamaChatTemplateResult _applyGrammar(
    LlamaChatTemplateResult result,
    List<ToolDefinition>? tools,
    ToolChoice toolChoice,
    Map<String, dynamic>? responseSchema, {
    required String thinkingEndTag,
  }) {
    String afterThought(String grammar) => result.thinkingForcedOpen
        ? ToolCallGrammarUtils.afterForcedOpenThought(grammar, thinkingEndTag)
        : grammar;
    if (responseSchema != null) {
      if (toolChoice != ToolChoice.none &&
          (tools?.any(toolUsesJsonSchema) ?? false)) {
        throw LlamaUnsupportedException(
          'Canonical schema tools cannot be combined with responseFormat: the response grammar would replace the tool grammar. Use separate requests.',
        );
      }
      final copy = LlamaChatTemplateResult(
        prompt: result.prompt,
        format: result.format,
        grammar: afterThought(responseFormatGrammar(responseSchema)),
        grammarLazy: result.grammarLazy,
        additionalStops: result.additionalStops,
        preservedTokens: result.preservedTokens,
        grammarTriggers: result.grammarTriggers,
        thinkingForcedOpen: result.thinkingForcedOpen,
        parser: result.parser,
        tokenCount: result.tokenCount,
      );
      return withThoughtMarksOf(copy, result);
    }

    final resultFormat = result.format < ChatFormat.values.length
        ? ChatFormat.values[result.format]
        : ChatFormat.generic;

    if (toolChoice == ToolChoice.none &&
        resultFormat == ChatFormat.ministral &&
        result.grammar != null) {
      final copy = LlamaChatTemplateResult(
        prompt: result.prompt,
        format: result.format,
        grammar: null,
        grammarLazy: false,
        additionalStops: result.additionalStops,
        preservedTokens: result.preservedTokens,
        grammarTriggers: const [],
        thinkingForcedOpen: result.thinkingForcedOpen,
        parser: result.parser,
        tokenCount: result.tokenCount,
      );
      return withThoughtMarksOf(copy, result);
    }

    // If tools are provided and grammar wasn't set by handler, generate it
    // only for generic/content-only routing. Format-specific handlers should
    // provide their own grammar semantics (or leave unconstrained), matching
    // llama.cpp behavior more closely.
    final allowGenericToolGrammar =
        resultFormat == ChatFormat.generic ||
        resultFormat == ChatFormat.contentOnly;

    if (tools != null &&
        tools.isNotEmpty &&
        toolChoice != ToolChoice.none &&
        result.grammar == null &&
        allowGenericToolGrammar) {
      final grammarResult = grammar.ToolGrammarGenerator.generate(
        tools,
        toolChoice: _toGrammarToolChoice(toolChoice),
      );
      if (grammarResult != null) {
        // Match llama.cpp generic/content-only behavior: tool grammar is
        // eagerly applied (non-lazy) for auto/required selection.
        final copy = LlamaChatTemplateResult(
          prompt: result.prompt,
          format: result.format,
          grammar: afterThought(grammarResult.grammar),
          grammarLazy: false,
          additionalStops: result.additionalStops,
          preservedTokens: result.preservedTokens,
          grammarTriggers: const [],
          thinkingForcedOpen: result.thinkingForcedOpen,
          parser: result.parser,
          tokenCount: result.tokenCount,
        );
        return withThoughtMarksOf(copy, result);
      }
    }

    return result;
  }

  static LlamaChatTemplateResult _normalizeGrammarLazyForToolChoice(
    LlamaChatTemplateResult result,
    ToolChoice toolChoice,
  ) {
    if (toolChoice != ToolChoice.required) {
      return result;
    }
    if (result.grammar == null || result.grammar!.isEmpty) {
      return result;
    }

    final resultFormat = result.format < ChatFormat.values.length
        ? ChatFormat.values[result.format]
        : ChatFormat.generic;
    if (chatFormatRegistration(resultFormat).traits.requiredKeepsLazyGrammar &&
        result.grammarLazy) {
      return result;
    }

    final copy = LlamaChatTemplateResult(
      prompt: result.prompt,
      format: result.format,
      grammar: result.grammar,
      grammarLazy: false,
      additionalStops: result.additionalStops,
      preservedTokens: result.preservedTokens,
      grammarTriggers: const [],
      thinkingForcedOpen: result.thinkingForcedOpen,
      parser: result.parser,
      tokenCount: result.tokenCount,
    );
    return withThoughtMarksOf(copy, result);
  }

  /// Parses raw LLM output using the format's handler.
  ///
  /// The [formatIndex] should come from [LlamaChatTemplateResult.format].
  /// [tools] supplies the schemas needed by formats whose wire representation
  /// does not encode enough type information to reconstruct arguments safely.
  ///
  /// Content that ends [output] keeps the whitespace after it, as llama.cpp
  /// does, unless [isPartial] is true: more output may follow a partial one.
  ///
  /// On [cancelled], Hermes withholds unfinished tool envelopes. Other endings
  /// retain the format's normal final-output behavior.
  ///
  /// A leading unterminated Ministral `[THINK]` block without `[TOOL_CALLS]`
  /// remains reasoning at EOF if the final parser accepts a reply without calls.
  ///
  /// With [thinkingForcedClosed], for a prompt that ends with a closed
  /// thought, as templates render with thinking off, DeepSeek V3, Hermes and
  /// Qwen3-Coder XML output has no reasoning: its thinking tags are content,
  /// as in llama.cpp. Other formats still return the reasoning.
  ///
  /// Without [thinkingForcedOpen], a Seed-OSS reply has a thought when it
  /// starts with `<seed:think>`, as in llama.cpp, or, as after a template that
  /// opens the thought, before a `</seed:think>` in a reply that does not.
  ///
  /// Output that a PEG [parser] cannot parse, or that is nested too deeply to
  /// parse, throws [LlamaInferenceException].
  static ChatParseResult parse(
    int formatIndex,
    String output, {
    bool isPartial = false,
    bool cancelled = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
    bool thinkingForcedClosed = false,
    String? parser,
    List<ToolDefinition>? tools,
  }) => _parseOutput(
    formatIndex,
    output,
    isPartial: isPartial,
    cancelled: cancelled,
    parseToolCalls: parseToolCalls,
    thinkingForcedOpen:
        thinkingForcedOpen || _endsUnopenedSeedOssThought(formatIndex, output),
    thinkingForcedClosed: thinkingForcedClosed,
    parser: parser,
    tools: tools,
  );

  /// Parses raw LLM output generated from [rendered], as `LlamaEngine.create`
  /// parses its final message.
  ///
  /// [rendered] must be the unchanged result of [render] or
  /// `LlamaEngine.chatTemplate`: besides its format, parser and
  /// [LlamaChatTemplateResult.thinkingForcedOpen], the parse uses how the
  /// render left the prompt's thought, which a copy of the result loses.
  /// The reply then parses as llama.cpp parses it after that prompt, which
  /// [parse] cannot tell: thinking tags after the template's own empty thought
  /// are content for DeepSeek V3, Hermes and Qwen3-Coder XML; after a prompt
  /// that opens no thought, most formats take a thought only at the start of
  /// the reply, and DeepSeek V3 keeps an end tag before any start tag as
  /// content, where [parse] takes them as thoughts; a Seed-OSS reply
  /// to a prompt that opens no thought has one only when it starts with
  /// `<seed:think>`; and a Seed-OSS or Cohere2 MoE thought closed because
  /// thinking is off still ends at a thinking tag or, for Cohere2 MoE, at the
  /// start of a text or action.
  ///
  /// [isPartial], [cancelled], [parseToolCalls] and [tools] behave as in
  /// [parse]. Output that a PEG parser cannot parse, or that is nested too
  /// deeply to parse, throws [LlamaInferenceException].
  ///
  /// To match the engine's message:
  /// - Pass `parseToolCalls: false` unless [tools] is non-empty and the
  ///   request's tool choice is not `none`; the default parses tool calls.
  /// - After that exception on a cancelled or length-limited reply, the engine
  ///   parses again with `isPartial: true`; do the same.
  /// - The marks live on the instance, so a copy loses them: a new result built
  ///   with the constructor or `fromJson`, and transfer to another isolate.
  /// - With thinking off the engine drops reasoning chunks from the stream,
  ///   while this still returns `reasoningContent`.
  static ChatParseResult parseRendered(
    LlamaChatTemplateResult rendered,
    String output, {
    bool isPartial = false,
    bool cancelled = false,
    bool parseToolCalls = true,
    List<ToolDefinition>? tools,
  }) => parseRenderedOutput(
    rendered.format,
    output,
    thoughtClosedForThinkingOff: thoughtClosedForThinkingOffOf(rendered),
    isPartial: isPartial,
    cancelled: cancelled,
    parseToolCalls: parseToolCalls,
    thinkingForcedOpen: rendered.thinkingForcedOpen,
    thinkingForcedClosed: thinkingForcedClosedOf(rendered),
    singleToolCall: singleToolCallOf(rendered),
    bareFirstCall: bareFirstCallOf(rendered),
    parser: rendered.parser,
    tools: tools,
  );

  /// Whether [output] is a Seed-OSS reply that ends a thought it did not
  /// open. The caller of [parse] cannot say whether the template opened the
  /// thought, so this parses as if it did.
  static bool _endsUnopenedSeedOssThought(int formatIndex, String output) {
    if (formatIndex != ChatFormat.seedOss.index) return false;
    final tags = thinkingTagsFor(formatIndex);
    return output.contains(tags.endTag) &&
        !trimLeftAsciiSpace(output).startsWith(tags.startTag);
  }

  static ChatParseResult _parseOutput(
    int formatIndex,
    String output, {
    required bool isPartial,
    required bool cancelled,
    required bool parseToolCalls,
    required bool thinkingForcedOpen,
    required bool thinkingForcedClosed,
    bool promptOpensNoThought = false,
    bool singleToolCall = false,
    bool bareFirstCall = false,
    String? parser,
    List<ToolDefinition>? tools,
  }) {
    ChatParseResult parse() => _parse(
      formatIndex,
      output,
      isPartial: isPartial,
      cancelled: cancelled,
      parseToolCalls: parseToolCalls,
      thinkingForcedOpen: thinkingForcedOpen,
      thinkingForcedClosed: thinkingForcedClosed,
      promptOpensNoThought: promptOpensNoThought,
      singleToolCall: singleToolCall,
      bareFirstCall: bareFirstCall,
      parser: parser,
      tools: tools,
    );
    final ChatParseResult result;
    try {
      result =
          promptOpensNoThought &&
              !thinkingForcedOpen &&
              takesThoughtOnlyAtReplyStart(formatIndex)
          ? withThoughtOnlyAtReplyStart(
              parse,
              exact: _traitsOf(formatIndex).thoughtStartsReplyExactly,
            )
          : parse();
    } on StackOverflowError catch (_, stackTrace) {
      // PEG rules recurse once per nesting level of model-controlled output.
      Error.throwWithStackTrace(
        LlamaInferenceException(
          'The model output is nested too deeply to parse.',
        ),
        stackTrace,
      );
    }
    return isPartial ? result : _withTrailingWhitespace(result, output);
  }

  /// Returns [result] with the whitespace that ends [output] added to content
  /// that a handler trimmed it from.
  static ChatParseResult _withTrailingWhitespace(
    ChatParseResult result,
    String output,
  ) {
    final body = output.trimRight();
    if (body.length == output.length ||
        result.content.isEmpty ||
        !body.endsWith(result.content)) {
      return result;
    }
    return ChatParseResult(
      content: result.content + output.substring(body.length),
      reasoningContent: result.reasoningContent,
      toolCalls: result.toolCalls,
    );
  }

  static ChatParseResult _parse(
    int formatIndex,
    String output, {
    required bool isPartial,
    required bool cancelled,
    required bool parseToolCalls,
    required bool thinkingForcedOpen,
    required bool thinkingForcedClosed,
    required bool promptOpensNoThought,
    required bool singleToolCall,
    required bool bareFirstCall,
    String? parser,
    List<ToolDefinition>? tools,
  }) {
    final resolved = _resolveHandlerForParse(formatIndex: formatIndex);
    final handler = resolved.handler;
    final format = resolved.format;
    // llama.cpp takes a thought only where the prompt opened one or at the
    // start of the reply, so an end tag before any start tag is text there.
    final thoughtTagsAreText =
        !thinkingForcedOpen &&
        (thinkingForcedClosed ||
            (promptOpensNoThought &&
                endsUnopenedThought(
                  output,
                  startTag: handler.thinkingStartTag,
                  endTag: handler.thinkingEndTag,
                )));

    final pegFormat = pegParseFormat(format, parser);
    final ChatParseResult result;
    if (pegFormat != null) {
      final strictResult = PegChatParser.parse(
        parser: parser ?? '',
        format: pegFormat,
        output: output,
        isPartial: isPartial,
        parseToolCalls: parseToolCalls,
        accumulateContent: chatFormatRegistration(
          format,
        ).traits.hasRepeatedContentChannels,
      );
      // Preserve strict required-tool failures and tool-call fallback parsing.
      // Only a terminal thought without a tool marker needs upstream leniency.
      result =
          !isPartial &&
              format == ChatFormat.ministral &&
              output.startsWith('[THINK]') &&
              !output.contains('[/THINK]') &&
              !output.contains('[TOOL_CALLS]')
          ? PegChatParser.parse(
              parser: parser ?? '',
              format: pegFormat,
              output: output,
              isPartial: true,
              parseToolCalls: parseToolCalls,
            )
          : strictResult;
    } else if (handler is HermesHandler) {
      result = handler.parseWithTools(
        output,
        tools: tools,
        isPartial: isPartial,
        cancelled: cancelled,
        parseToolCalls: parseToolCalls,
        thinkingForcedOpen: thinkingForcedOpen,
        thoughtTagsAreText: thoughtTagsAreText,
      );
    } else if (handler is Qwen3CoderXmlHandler) {
      result = handler.parseWithTools(
        output,
        tools: tools,
        isPartial: isPartial,
        parseToolCalls: parseToolCalls,
        thinkingForcedOpen: thinkingForcedOpen,
        thoughtTagsAreText: thoughtTagsAreText,
        singleToolCall: singleToolCall,
        bareFirstCall: bareFirstCall,
      );
    } else if (handler is Ling3Handler) {
      result = handler.parseWithTools(
        output,
        tools: tools,
        isPartial: isPartial,
        parseToolCalls: parseToolCalls,
        thinkingForcedOpen: thinkingForcedOpen,
        singleToolCall: singleToolCall,
      );
    } else if (handler is DeepseekV3Handler) {
      result = handler.parse(
        output,
        isPartial: isPartial,
        parseToolCalls: parseToolCalls,
        thinkingForcedOpen: thinkingForcedOpen,
        thoughtTagsAreText: thoughtTagsAreText,
      );
    } else if (handler is ToolSchemaAwareChatTemplateHandler) {
      result = (handler as ToolSchemaAwareChatTemplateHandler).parseWithTools(
        output,
        tools: tools,
        isPartial: isPartial,
        parseToolCalls: parseToolCalls,
        thinkingForcedOpen: thinkingForcedOpen,
      );
    } else {
      result = handler.parse(
        output,
        isPartial: isPartial,
        parseToolCalls: parseToolCalls,
        thinkingForcedOpen: thinkingForcedOpen,
      );
    }
    if (!isPartial && tools != null && tools.any(toolUsesJsonSchema)) {
      final leavesIncompleteToolCall = chatFormatRegistration(
        format,
      ).traits.leavesIncompleteToolCall;
      if (parseToolCalls &&
          leavesIncompleteToolCall != null &&
          leavesIncompleteToolCall(
            result,
            output,
            thinkingForcedOpen: thinkingForcedOpen,
          )) {
        throw LlamaInferenceException(
          'The model returned a malformed or incomplete tool call.',
        );
      }
      final declared = {for (final tool in tools) tool.name: tool};
      for (final call in result.toolCalls) {
        final tool = declared[call.function?.name];
        if (tool == null) {
          throw LlamaInferenceException(
            'The model returned an undeclared tool call.',
          );
        }
        if (!toolUsesJsonSchema(tool)) continue;
        final Object? arguments;
        try {
          arguments = jsonDecode(call.function?.arguments ?? '{}');
        } on FormatException {
          throw LlamaInferenceException(
            'The model returned malformed tool arguments.',
          );
        }
        if (!validateToolSchemaValue(arguments, tool.toJsonSchema()).valid) {
          throw LlamaInferenceException(
            'Tool arguments do not match the input schema for "${tool.name}".',
          );
        }
      }
    }
    return result;
  }

  /// Returns the thinking tags used by the selected parser handler.
  ///
  /// A [formatIndex] past the end of [ChatFormat] takes the generic handler's
  /// `<think>` and `</think>`, and a negative one throws [RangeError].
  static ({String startTag, String endTag}) thinkingTagsFor(int formatIndex) {
    final resolved = _resolveHandlerForParse(formatIndex: formatIndex);
    return (
      startTag: resolved.handler.thinkingStartTag,
      endTag: resolved.handler.thinkingEndTag,
    );
  }

  /// Fills the tags and close prefix that [budget] omits for [formatIndex].
  ///
  /// An omitted [ThinkingBudget.startTag] or [ThinkingBudget.endTag] takes
  /// the [thinkingTagsFor] value. With [ThinkingBudget.endTag] omitted, a
  /// format whose template closes a thought with a line break, such as
  /// Qwen3-Coder XML, appends that prefix to [ThinkingBudget.forcedMessage],
  /// as llama.cpp does. A caller-set end tag is left as given.
  ///
  /// Set [rendersPrompt] to false for a backend that takes chat messages and
  /// closes the thought itself, which rejects a forced message: only the
  /// line-break prefix is skipped, and a [ThinkingBudget.forcedMessage] you
  /// set is kept as given. [formatIndex] follows the [thinkingTagsFor] rules.
  static ThinkingBudget resolveThinkingBudget(
    int formatIndex,
    ThinkingBudget budget, {
    bool rendersPrompt = true,
  }) {
    final tags = thinkingTagsFor(formatIndex);
    final closePrefix = rendersPrompt && budget.endTag == null
        ? budgetThoughtClosePrefix(formatIndex)
        : '';
    return ThinkingBudget(
      maxTokens: budget.maxTokens,
      startTag: budget.startTag ?? tags.startTag,
      endTag: budget.endTag ?? tags.endTag,
      forcedMessage: closePrefix.isEmpty
          ? budget.forcedMessage
          : '${budget.forcedMessage ?? ''}$closePrefix',
    );
  }

  /// Throws unless [prompt] holds [mediaMarker] exactly [expected] times.
  ///
  /// A template that drops or repeats a tool result's media marker would
  /// leave a backend to place that media in another turn.
  static void _requireMediaMarkers(
    String prompt, {
    required String mediaMarker,
    required int? expected,
    required String templateName,
  }) {
    if (expected == null) return;
    final rendered = mediaMarker.allMatches(prompt).length;
    if (rendered != expected) {
      throw LlamaUnsupportedException(
        'The chat template ($templateName) rendered $rendered media markers '
        'for $expected media parts, so tool-result media would not stay in '
        'their tool turn. Use a template that renders each tool result once.',
      );
    }
  }

  static LlamaChatTemplateResult _withFormat(
    LlamaChatTemplateResult result,
    int format,
  ) {
    if (result.format == format) {
      return result;
    }

    final copy = LlamaChatTemplateResult(
      prompt: result.prompt,
      format: format,
      grammar: result.grammar,
      grammarLazy: result.grammarLazy,
      thinkingForcedOpen: result.thinkingForcedOpen,
      additionalStops: result.additionalStops,
      preservedTokens: result.preservedTokens,
      grammarTriggers: result.grammarTriggers,
      parser: result.parser,
      tokenCount: result.tokenCount,
    );
    return withThoughtMarksOf(copy, result);
  }

  static ({ChatTemplateHandler handler, ChatFormat format})
  _resolveHandlerForParse({required int formatIndex}) {
    final format = formatIndex < ChatFormat.values.length
        ? ChatFormat.values[formatIndex]
        : ChatFormat.generic;
    return (handler: handlerFor(format), format: format);
  }

  static grammar.ToolChoice _toGrammarToolChoice(ToolChoice toolChoice) {
    switch (toolChoice) {
      case ToolChoice.none:
        return grammar.ToolChoice.none;
      case ToolChoice.required:
        return grammar.ToolChoice.required;
      case ToolChoice.auto:
        return grammar.ToolChoice.auto;
    }
  }

  static Map<String, String> _withInternalMetadata(
    Map<String, String> metadata, {
    required ToolChoice toolChoice,
    required bool parallelToolCalls,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? now,
  }) {
    final toolChoiceValue = toolChoice.name;
    final parallelToolCallsValue = parallelToolCalls.toString();
    final chatTemplateKwargsValue =
        (chatTemplateKwargs == null || chatTemplateKwargs.isEmpty)
        ? null
        : jsonEncode(chatTemplateKwargs);
    final nowValue = now?.toUtc().toIso8601String();
    if (metadata[internalToolChoiceMetadataKey] == toolChoiceValue &&
        metadata[internalParallelToolCallsMetadataKey] ==
            parallelToolCallsValue &&
        metadata[internalChatTemplateKwargsMetadataKey] ==
            chatTemplateKwargsValue &&
        metadata[internalTemplateNowMetadataKey] == nowValue) {
      return metadata;
    }
    final merged = <String, String>{
      ...metadata,
      internalToolChoiceMetadataKey: toolChoiceValue,
      internalParallelToolCallsMetadataKey: parallelToolCallsValue,
    };
    if (chatTemplateKwargsValue != null) {
      merged[internalChatTemplateKwargsMetadataKey] = chatTemplateKwargsValue;
    } else {
      merged.remove(internalChatTemplateKwargsMetadataKey);
    }
    if (nowValue != null) {
      merged[internalTemplateNowMetadataKey] = nowValue;
    } else {
      merged.remove(internalTemplateNowMetadataKey);
    }
    return merged;
  }

  static List<LlamaChatMessage> _injectSystemInstructionLikeLlamaCpp(
    List<LlamaChatMessage> messages,
    String instruction, {
    required bool supportsSystemRole,
  }) {
    if (supportsSystemRole) {
      if (messages.isNotEmpty && messages.first.role == LlamaChatRole.system) {
        final first = messages.first;
        if (first.content.trim() == instruction.trim()) {
          return messages;
        }

        return <LlamaChatMessage>[
          first.copyWith(content: instruction),
          ...messages.skip(1),
        ];
      }

      return <LlamaChatMessage>[
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: instruction,
        ),
        ...messages,
      ];
    }

    if (messages.isNotEmpty && messages.first.content.contains(instruction)) {
      return messages;
    }

    if (messages.isEmpty) {
      return <LlamaChatMessage>[
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: instruction),
      ];
    }

    return TemplateRenderContext.mergeLeadingSystemMessage(<LlamaChatMessage>[
      LlamaChatMessage.fromText(
        role: LlamaChatRole.system,
        text: instruction.trim(),
      ),
      ...messages,
    ], supportsSystemRole: false);
  }
}

/// Whether, after a prompt that opens no thought, the parse of [formatIndex]
/// takes a thought only at the start of the reply and keeps other thinking
/// tags as content, as llama.cpp does.
bool takesThoughtOnlyAtReplyStart(int formatIndex) =>
    formatIndex < ChatFormat.values.length &&
    chatFormatRegistration(
      ChatFormat.values[formatIndex],
    ).traits.takesThoughtOnlyAtReplyStart;

/// The markers that show where a reply ends a thought that a handler closed
/// for thinking off: the format's thinking tags and its
/// [ChatFormatTraits.forcedThoughtContentOpenings], such as where a Cohere2
/// MoE text or action starts, as llama.cpp ends the thought it keeps open.
List<String> closedThoughtMarkers(int formatIndex) {
  final tags = ChatTemplateEngine.thinkingTagsFor(formatIndex);
  return [
    tags.startTag,
    tags.endTag,
    ..._traitsOf(formatIndex).forcedThoughtContentOpenings,
  ];
}

/// Whether llama.cpp keeps open the thought that a [formatIndex] handler
/// closed for thinking off, so that a reply showing one of
/// [closedThoughtMarkers] parses as after a forced-open prompt.
bool reopensClosedThought(int formatIndex) =>
    _traitsOf(formatIndex).reopensThoughtClosedForThinkingOff;

/// The text a thinking budget forces before the [formatIndex] end tag.
String budgetThoughtClosePrefix(int formatIndex) =>
    _traitsOf(formatIndex).budgetThoughtClosePrefix;

ChatFormatTraits _traitsOf(int formatIndex) =>
    formatIndex < ChatFormat.values.length
    ? chatFormatRegistration(ChatFormat.values[formatIndex]).traits
    : ChatFormatTraits.none;

/// Parses [output] of a render of this engine, whose internal thought mark
/// [ChatTemplateEngine.parse] cannot see.
///
/// llama.cpp keeps open the thought a Seed-OSS, Cohere2 MoE or Qwen3-Coder XML
/// handler closed for thinking off ([thoughtClosedForThinkingOff]), so a reply
/// that shows one of [closedThoughtMarkers] parses as after a forced-open
/// prompt. Without it
/// or [thinkingForcedOpen] the prompt opened no thought, so a Seed-OSS end tag
/// in a reply that does not start with a thought is content, a format with
/// [ChatFormatTraits.takesThoughtOnlyAtReplyStart] takes a thought only at the
/// start of the reply, and a DeepSeek V3 reply with an end tag before any
/// start tag keeps its thinking tags as content. With [singleToolCall], a
/// Qwen3-Coder XML reply has at most one tool call, and with [bareFirstCall]
/// its first call may leave out `<tool_call>`.
ChatParseResult parseRenderedOutput(
  int formatIndex,
  String output, {
  required bool thoughtClosedForThinkingOff,
  bool isPartial = false,
  bool cancelled = false,
  bool parseToolCalls = true,
  bool thinkingForcedOpen = false,
  bool thinkingForcedClosed = false,
  bool singleToolCall = false,
  bool bareFirstCall = false,
  String? parser,
  List<ToolDefinition>? tools,
}) => ChatTemplateEngine._parseOutput(
  formatIndex,
  output,
  isPartial: isPartial,
  cancelled: cancelled,
  parseToolCalls: parseToolCalls,
  thinkingForcedOpen:
      thinkingForcedOpen ||
      (thoughtClosedForThinkingOff &&
          reopensClosedThought(formatIndex) &&
          closedThoughtMarkers(formatIndex).any(output.contains)),
  thinkingForcedClosed: thinkingForcedClosed,
  promptOpensNoThought: !thoughtClosedForThinkingOff,
  singleToolCall: singleToolCall,
  bareFirstCall: bareFirstCall,
  parser: parser,
  tools: tools,
);

/// The prompt [templateSource] renders as Jinja alone, as a runtime that
/// applies the template itself does: [tools] reach the template as `tools`,
/// with no format detection, tool-call instruction, format gates or grammar.
///
/// Media parts and tool-result media become [mediaMarker] as in
/// [ChatTemplateEngine.render]. Template failures throw as there.
String renderPlainChatTemplatePrompt({
  required String templateSource,
  required String templateName,
  required List<LlamaChatMessage> messages,
  required Map<String, String> metadata,
  bool addAssistant = true,
  List<ToolDefinition>? tools,
  ToolChoice toolChoice = ToolChoice.auto,
  bool enableThinking = true,
  Map<String, dynamic>? chatTemplateKwargs,
  DateTime? now,
  String mediaMarker = mtmdMediaMarker,
}) => ChatTemplateEngine._render(
  templateSource: templateSource,
  messages: messages,
  metadata: {...metadata, internalTemplateSourceNameMetadataKey: templateName},
  addAssistant: addAssistant,
  tools: tools,
  toolChoice: toolChoice,
  parallelToolCalls: false,
  enableThinking: enableThinking,
  responseFormat: null,
  customTemplate: null,
  chatTemplateKwargs: chatTemplateKwargs,
  now: now,
  mediaMarker: mediaMarker,
  plainTemplate: true,
).prompt;
