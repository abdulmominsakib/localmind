import 'dart:convert';

import '../grammar/tool_grammar_generator.dart' as grammar;
import '../llama_logger.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/chat_role.dart';
import '../models/chat/chat_template_result.dart';
import '../models/chat/content_part.dart';
import '../models/inference/tool_choice.dart';
import '../models/tools/tool_definition.dart';
import 'chat_format.dart';
import 'chat_parse_result.dart';
import 'peg_chat_parser.dart';
import 'chat_template_handler.dart';
import 'handlers/cohere2_moe_handler.dart';
import 'handlers/command_r7b_handler.dart';
import 'handlers/deepseek_r1_handler.dart';
import 'handlers/deepseek_v3_handler.dart';
import 'handlers/apertus_handler.dart';
import 'handlers/apriel15_handler.dart';
import 'handlers/exaone_moe_handler.dart';
import 'handlers/firefunction_v2_handler.dart';
import 'handlers/function_gemma_handler.dart';
import 'handlers/functionary_v31_llama31_handler.dart';
import 'handlers/functionary_v32_handler.dart';
import 'handlers/gemma_handler.dart';
import 'handlers/gemma4_handler.dart';
import 'handlers/generic_handler.dart';
import 'handlers/glm45_handler.dart';
import 'handlers/gpt_oss_handler.dart';
import 'handlers/granite_handler.dart';
import 'handlers/hermes_handler.dart';
import 'handlers/hunyuan_v3_handler.dart';
import 'handlers/kimi_k2_handler.dart';
import 'handlers/lfm2_handler.dart';
import 'handlers/llama3_handler.dart';
import 'handlers/magistral_handler.dart';
import 'handlers/minimax_m2_handler.dart';
import 'handlers/ministral_handler.dart';
import 'handlers/mistral_handler.dart';
import 'handlers/minicpm5_handler.dart';
import 'handlers/nemotron_v2_handler.dart';
import 'handlers/qwen3_coder_xml_handler.dart';
import 'handlers/seed_oss_handler.dart';
import 'handlers/solar_open_handler.dart';
import 'handlers/translate_gemma_handler.dart';
import 'handlers/xiaomi_mimo_handler.dart';
import 'template_caps.dart';
import 'template_internal_metadata.dart';
import 'template_render_context.dart';

/// Orchestrates chat template detection, rendering, and output parsing.
///
/// This is the main entry point for the template module. It:
/// 1. Detects the chat format from the Jinja template source
/// 2. Delegates to the appropriate per-format handler for rendering
/// 3. Provides output parsing via the detected format's handler
///
/// Usage:
/// ```dart
/// final engine = ChatTemplateEngine();
/// final result = engine.render(
///   templateSource: metadata['tokenizer.chat_template'],
///   messages: messages,
///   metadata: metadata,
///   tools: tools,
///   enableThinking: true,
/// );
/// // Later, parse the output:
/// final parsed = engine.parse(result.format, rawOutput);
/// ```
class ChatTemplateEngine {
  static const String _genericToolSystemInstruction =
      'Respond in JSON format, either with `tool_call` '
      '(a request to call tools) or with `response` reply '
      'to the user\'s request';

  /// Singleton handler instances, lazily initialized.
  static final Map<ChatFormat, ChatTemplateHandler> _handlers = {};

  static const Set<ChatFormat> _schemaDisabledFormats = {
    ChatFormat.deepseekV3,
    ChatFormat.deepseekR1,
    ChatFormat.commandR7B,
    ChatFormat.cohere2Moe,
    ChatFormat.glm45,
    ChatFormat.hermes,
  };

  static const Set<ChatFormat> _requiredKeepsLazyFormats = {
    ChatFormat.apertus,
    ChatFormat.nemotronV2,
    ChatFormat.lfm2,
  };

  static const Set<ChatFormat> _toolCallGenericFormats = {ChatFormat.gemma};

  // Match llama.cpp routing when tools are provided with `tool_choice=none`.
  // These formats fall through to the content-only path in llama.cpp's
  // jinja dispatcher, unless a response schema forces generic routing.
  static const Set<ChatFormat> _toolChoiceNoneContentOnlyFormats = {
    ChatFormat.contentOnly,
    ChatFormat.generic,
    ChatFormat.mistralNemo,
  };

  /// Returns the handler for the given [format].
  static ChatTemplateHandler handlerFor(ChatFormat format) {
    return _handlers.putIfAbsent(format, () => _createHandler(format));
  }

  /// Detects the [ChatFormat] from a template source string.
  static ChatFormat detectFormat(String? templateSource) {
    return detectChatFormat(templateSource);
  }

  /// Full rendering pipeline: detect format → get handler → render.
  ///
  /// If the template source is null/empty, uses the ChatML fallback.
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
  }) {
    // 1. Select template source (default vs tool_use variant)
    final hasTools = tools != null && tools.isNotEmpty;
    final allowToolCalls = hasTools && toolChoice != ToolChoice.none;
    final effectiveTools = allowToolCalls ? tools : null;
    var metadataTemplate = templateSource;

    if (allowToolCalls &&
        metadata.containsKey('tokenizer.chat_template.tool_use')) {
      metadataTemplate = metadata['tokenizer.chat_template.tool_use'];
      LlamaLogger.instance.debug(
        'ChatTemplateEngine: Using tool_use template variant',
      );
    }

    var effectiveTemplate = customTemplate;
    if (effectiveTemplate != null) {
      LlamaLogger.instance.debug(
        'ChatTemplateEngine: Using per-call custom template override',
      );
    } else {
      effectiveTemplate = metadataTemplate;
    }

    final hasSchemaResponseFormat = _hasSchemaResponseFormat(responseFormat);

    final format = detectFormat(effectiveTemplate);
    LlamaLogger.instance.debug(
      'ChatTemplateEngine: Detected format=$format from template',
    );

    ChatFormat effectiveFormat;
    // Match llama.cpp schema-aware routing: tools + schema falls back to
    // generic routing, and some format handlers are disabled with schema.
    if (allowToolCalls && hasSchemaResponseFormat) {
      effectiveFormat = ChatFormat.generic;
    } else if (hasTools &&
        toolChoice == ToolChoice.none &&
        _toolChoiceNoneContentOnlyFormats.contains(format)) {
      effectiveFormat = ChatFormat.contentOnly;
    } else if (allowToolCalls && _toolCallGenericFormats.contains(format)) {
      // Match llama.cpp server behavior: Gemma tool-call requests route
      // through generic JSON tool-calling semantics.
      effectiveFormat = ChatFormat.generic;
    } else if (format == ChatFormat.gemma) {
      // llama.cpp does not have a dedicated Gemma Jinja handler.
      // Gemma routes to content-only (no tools) or generic (tools).
      effectiveFormat = allowToolCalls
          ? ChatFormat.generic
          : ChatFormat.contentOnly;
    } else if (hasSchemaResponseFormat &&
        _schemaDisabledFormats.contains(format)) {
      effectiveFormat = allowToolCalls
          ? ChatFormat.generic
          : ChatFormat.contentOnly;
    } else {
      effectiveFormat = format;
    }

    // Use generic handler fallback when template is missing, or when tool
    // calling is requested for an unknown/unclassified template.
    if (effectiveFormat == ChatFormat.contentOnly &&
        (effectiveTemplate == null || allowToolCalls)) {
      effectiveFormat = ChatFormat.generic;
    }

    final handler = handlerFor(effectiveFormat);

    // 3. Prepare template capabilities and render context matching llama.cpp
    final caps = TemplateCaps.detect(effectiveTemplate ?? '');
    final effectiveParallelToolCalls =
        allowToolCalls && parallelToolCalls && caps.supportsParallelToolCalls;
    if (parallelToolCalls && !effectiveParallelToolCalls) {
      LlamaLogger.instance.debug(
        'ChatTemplateEngine: Disabling parallelToolCalls because template '
        'does not support parallel tool calls or tool calls are disabled.',
      );
    }

    final handlerMetadata = _withInternalMetadata(
      metadata,
      toolChoice: toolChoice,
      parallelToolCalls: effectiveParallelToolCalls,
      chatTemplateKwargs: chatTemplateKwargs,
      now: now,
    );
    var effectiveMessages = messages;

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

    // Proactively detect templates that access content as a list
    // (e.g. SmolVLM's `message['content'][0]['type']`)
    final hasMediaParts = effectiveMessages.any(
      (message) => message.parts.any(
        (part) => part is LlamaImageContent || part is LlamaAudioContent,
      ),
    );
    final needsTypedContent = caps.supportsTypedContent && hasMediaParts;

    if (needsTypedContent) {
      LlamaLogger.instance.debug(
        'ChatTemplateEngine: Using multimodal content format '
        'for template that accesses content as list',
      );
      var rendered = handler.renderWithMultimodalContent(
        templateSource: effectiveTemplate ?? GenericHandler.chatMlTemplate,
        messages: effectiveMessages,
        metadata: handlerMetadata,
        addAssistant: addAssistant,
        tools: effectiveTools,
        enableThinking: enableThinking,
      );
      if (effectiveFormat == ChatFormat.contentOnly) {
        rendered = _withFormat(rendered, ChatFormat.contentOnly.index);
      }

      final withGrammar = _applyGrammar(
        rendered,
        effectiveTools,
        toolChoice,
        responseFormat,
      );
      return _normalizeGrammarLazyForToolChoice(withGrammar, toolChoice);
    }

    var baseResult = handler.render(
      templateSource: effectiveTemplate ?? GenericHandler.chatMlTemplate,
      messages: effectiveMessages,
      metadata: handlerMetadata,
      addAssistant: addAssistant,
      tools: effectiveTools,
      enableThinking: enableThinking,
    );

    if (effectiveFormat == ChatFormat.contentOnly) {
      baseResult = _withFormat(baseResult, ChatFormat.contentOnly.index);
    }

    // Apply grammar constraints for tool calls or response format
    final withGrammar = _applyGrammar(
      baseResult,
      effectiveTools,
      toolChoice,
      responseFormat,
    );
    return _normalizeGrammarLazyForToolChoice(withGrammar, toolChoice);
  }

  /// Apply grammar constraints based on tool definitions and response format.
  static LlamaChatTemplateResult _applyGrammar(
    LlamaChatTemplateResult result,
    List<ToolDefinition>? tools,
    ToolChoice toolChoice,
    Map<String, dynamic>? responseFormat,
  ) {
    // If response_format is json_object/json_schema, generate grammar for it
    if (responseFormat != null) {
      final type = responseFormat['type'] as String?;
      if (type == 'json_schema') {
        final schema =
            responseFormat['json_schema']?['schema'] as Map<String, dynamic>?;
        if (schema != null) {
          final grammarText = grammar.ToolGrammarGenerator.generateForSchema(
            schema,
          );
          return LlamaChatTemplateResult(
            prompt: result.prompt,
            format: result.format,
            grammar: grammarText,
            grammarLazy: result.grammarLazy,
            additionalStops: result.additionalStops,
            preservedTokens: result.preservedTokens,
            grammarTriggers: result.grammarTriggers,
            thinkingForcedOpen: result.thinkingForcedOpen,
            parser: result.parser,
            tokenCount: result.tokenCount,
          );
        }
      } else if (type == 'json_object') {
        final grammarText = grammar.ToolGrammarGenerator.generateForSchema({
          'type': 'object',
        });
        return LlamaChatTemplateResult(
          prompt: result.prompt,
          format: result.format,
          grammar: grammarText,
          grammarLazy: result.grammarLazy,
          additionalStops: result.additionalStops,
          preservedTokens: result.preservedTokens,
          grammarTriggers: result.grammarTriggers,
          thinkingForcedOpen: result.thinkingForcedOpen,
          parser: result.parser,
          tokenCount: result.tokenCount,
        );
      }
    }

    final resultFormat = result.format < ChatFormat.values.length
        ? ChatFormat.values[result.format]
        : ChatFormat.generic;

    if (toolChoice == ToolChoice.none &&
        resultFormat == ChatFormat.ministral &&
        result.grammar != null) {
      return LlamaChatTemplateResult(
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
        return LlamaChatTemplateResult(
          prompt: result.prompt,
          format: result.format,
          grammar: grammarResult.grammar,
          grammarLazy: false,
          additionalStops: result.additionalStops,
          preservedTokens: result.preservedTokens,
          grammarTriggers: const [],
          thinkingForcedOpen: result.thinkingForcedOpen,
          parser: result.parser,
          tokenCount: result.tokenCount,
        );
      }
    }

    return result;
  }

  static LlamaChatTemplateResult _normalizeGrammarLazyForToolChoice(
    LlamaChatTemplateResult result,
    ToolChoice toolChoice,
  ) {
    if (toolChoice != ToolChoice.required || !result.grammarLazy) {
      return result;
    }
    if (result.grammar == null || result.grammar!.isEmpty) {
      return result;
    }

    final resultFormat = result.format < ChatFormat.values.length
        ? ChatFormat.values[result.format]
        : ChatFormat.generic;
    if (_requiredKeepsLazyFormats.contains(resultFormat)) {
      return result;
    }

    return LlamaChatTemplateResult(
      prompt: result.prompt,
      format: result.format,
      grammar: result.grammar,
      grammarLazy: false,
      additionalStops: result.additionalStops,
      preservedTokens: result.preservedTokens,
      grammarTriggers: result.grammarTriggers,
      thinkingForcedOpen: result.thinkingForcedOpen,
      parser: result.parser,
      tokenCount: result.tokenCount,
    );
  }

  /// Parses raw LLM output using the format's handler.
  ///
  /// The [formatIndex] should come from [LlamaChatTemplateResult.format].
  static ChatParseResult parse(
    int formatIndex,
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
    String? parser,
  }) {
    final resolved = _resolveHandlerForParse(formatIndex: formatIndex);
    final handler = resolved.handler;
    final format = resolved.format;

    final hasPegParser = parser != null && parser.trim().isNotEmpty;
    final isPegFormat =
        format == ChatFormat.pegSimple ||
        format == ChatFormat.pegNative ||
        format == ChatFormat.pegConstructed;
    final pegFormat = switch (format) {
      ChatFormat.pegSimple => ChatFormat.pegSimple,
      ChatFormat.pegNative => ChatFormat.pegNative,
      ChatFormat.pegConstructed => ChatFormat.pegConstructed,
      ChatFormat.ministral => hasPegParser ? ChatFormat.pegNative : null,
      ChatFormat.solarOpen => hasPegParser ? ChatFormat.pegNative : null,
      ChatFormat.qwen3CoderXml =>
        hasPegParser ? ChatFormat.pegConstructed : null,
      _ => null,
    };

    if (pegFormat != null && (isPegFormat || hasPegParser)) {
      return PegChatParser.parse(
        parser: parser ?? '',
        format: pegFormat,
        output: output,
        isPartial: isPartial,
        parseToolCalls: parseToolCalls,
      );
    }

    return handler.parse(
      output,
      isPartial: isPartial,
      parseToolCalls: parseToolCalls,
      thinkingForcedOpen: thinkingForcedOpen,
    );
  }

  /// Returns the thinking tags used by the selected parser handler.
  static ({String startTag, String endTag}) thinkingTagsFor(int formatIndex) {
    final resolved = _resolveHandlerForParse(formatIndex: formatIndex);
    return (
      startTag: resolved.handler.thinkingStartTag,
      endTag: resolved.handler.thinkingEndTag,
    );
  }

  /// Creates a handler instance for the given format.
  static ChatTemplateHandler _createHandler(ChatFormat format) {
    switch (format) {
      case ChatFormat.hermes:
        return HermesHandler();
      case ChatFormat.llama3:
      case ChatFormat.llama3BuiltinTools:
        return Llama3Handler();
      case ChatFormat.firefunctionV2:
        return FirefunctionV2Handler();
      case ChatFormat.functionaryV32:
        return FunctionaryV32Handler();
      case ChatFormat.functionaryV31Llama31:
        return FunctionaryV31Llama31Handler();
      case ChatFormat.mistralNemo:
        return MistralHandler();
      case ChatFormat.ministral:
        return MinistralHandler();
      case ChatFormat.magistral:
        return MagistralHandler();
      case ChatFormat.lfm2:
        return Lfm2Handler();
      case ChatFormat.deepseekR1:
        return DeepseekR1Handler();
      case ChatFormat.deepseekV3:
        return DeepseekV3Handler();
      case ChatFormat.functionGemma:
        return FunctionGemmaHandler();
      case ChatFormat.gemma:
        return GemmaHandler();
      case ChatFormat.gemma4:
        return Gemma4Handler();
      case ChatFormat.commandR7B:
        return CommandR7BHandler();
      case ChatFormat.cohere2Moe:
        return Cohere2MoeHandler();
      case ChatFormat.granite:
        return GraniteHandler();
      case ChatFormat.glm45:
        return Glm45Handler();
      case ChatFormat.kimiK2:
        return KimiK2Handler();
      case ChatFormat.qwen3CoderXml:
        return Qwen3CoderXmlHandler();
      case ChatFormat.minimaxM2:
        return MinimaxM2Handler();
      case ChatFormat.minicpm5:
        return MiniCpm5Handler();
      case ChatFormat.hunyuanV3:
        return HunyuanV3Handler();
      case ChatFormat.gptOss:
        return GptOssHandler();
      case ChatFormat.seedOss:
        return SeedOssHandler();
      case ChatFormat.nemotronV2:
        return NemotronV2Handler();
      case ChatFormat.apertus:
        return ApertusHandler();
      case ChatFormat.xiaomiMimo:
        return XiaomiMimoHandler();
      case ChatFormat.apriel15:
        return Apriel15Handler();
      case ChatFormat.solarOpen:
        return SolarOpenHandler();
      case ChatFormat.exaoneMoe:
        return ExaoneMoeHandler();
      case ChatFormat.translateGemma:
        return TranslateGemmaHandler();
      case ChatFormat.pegSimple:
        return GenericHandler(
          format: ChatFormat.pegSimple,
          toolCallSerialization: TemplateToolCallSerialization.none,
        );
      case ChatFormat.pegNative:
        return GenericHandler(
          format: ChatFormat.pegNative,
          toolCallSerialization: TemplateToolCallSerialization.none,
        );
      case ChatFormat.pegConstructed:
        return GenericHandler(
          format: ChatFormat.pegConstructed,
          toolCallSerialization: TemplateToolCallSerialization.none,
        );
      case ChatFormat.generic:
        return GenericHandler();
      case ChatFormat.contentOnly:
        return GenericHandler(
          format: ChatFormat.contentOnly,
          toolCallSerialization: TemplateToolCallSerialization.none,
        );
    }
  }

  static bool _hasSchemaResponseFormat(Map<String, dynamic>? responseFormat) {
    if (responseFormat == null) {
      return false;
    }

    final type = responseFormat['type'] as String?;
    return type == 'json_schema' || type == 'json_object';
  }

  static LlamaChatTemplateResult _withFormat(
    LlamaChatTemplateResult result,
    int format,
  ) {
    if (result.format == format) {
      return result;
    }

    return LlamaChatTemplateResult(
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
