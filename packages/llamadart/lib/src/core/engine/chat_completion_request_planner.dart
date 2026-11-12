import 'dart:convert';

import '../../backends/backend.dart';
import 'json_schema_chat_request.dart';
import '../exceptions.dart';
import '../grammar/llama_cpp_grammar_limits.dart';
import '../llama_logger.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/chat_role.dart';
import '../models/chat/chat_template_result.dart';
import '../models/chat/content_part.dart';
import '../models/chat/tool_result_parts.dart';
import '../models/inference/generation_params.dart';
import '../models/inference/tool_choice.dart';
import '../models/tools/tool_definition.dart';
import '../template/chat_format.dart';
import '../template/chat_template_engine.dart';
import '../template/template_internal_metadata.dart';
import '../template/response_format.dart';

/// Prepared generation inputs for a chat-completion request.
///
/// This is internal engine plumbing: it combines template grammar, caller
/// generation parameters, media parts, and backend-native chat eligibility into
/// one immutable request plan.
class ChatCompletionRequestPlan {
  /// Creates a prepared chat-completion request plan.
  const ChatCompletionRequestPlan({
    required this.templateResult,
    required this.generationParams,
    required this.mediaParts,
    required this.nativeChatBackend,
    required this.parseToolCallsEnabled,
    this.excludesPromptFromPenalties = false,
    this.includesPromptInPenalties = false,
    this.jsonSchemaBackend,
    this.jsonSchema,
  });

  /// Rendered template and parser metadata.
  final LlamaChatTemplateResult templateResult;

  /// Effective generation parameters after template grammar and stops are
  /// merged with caller-provided parameters.
  final GenerationParams generationParams;

  /// Media content parts that should be forwarded to rendered-prompt backends.
  final List<LlamaContentPart> mediaParts;

  /// Backend-native chat generator to use, or null for rendered-prompt
  /// generation.
  final BackendNativeChatGeneration? nativeChatBackend;

  /// Optional direct-schema generator; its payload is never GBNF.
  final BackendJsonSchemaChatGeneration? jsonSchemaBackend;

  /// Validated immutable request snapshot for the direct-schema route.
  final Map<String, dynamic>? jsonSchema;

  /// Whether final streaming output should be parsed for tool calls.
  final bool parseToolCallsEnabled;

  /// Whether the plan dropped a lazy template grammar the backend cannot
  /// apply, so the backend should keep the prompt out of its penalty window as
  /// llama.cpp does under that grammar.
  final bool excludesPromptFromPenalties;

  /// Whether new LFM2 Python-auto grammar must retain prompt penalties.
  final bool includesPromptInPenalties;

  /// Whether this plan should call the backend-native chat API.
  bool get usesNativeChatGeneration =>
      nativeChatBackend != null || jsonSchemaBackend != null;
}

/// Builds backend-specific generation inputs for chat-completion requests.
class ChatCompletionRequestPlanner {
  const ChatCompletionRequestPlanner._();

  /// Builds an immutable request plan for [templateResult].
  static ChatCompletionRequestPlan build({
    required LlamaBackend backend,
    required LlamaChatTemplateResult templateResult,
    required List<LlamaChatMessage> messages,
    required ToolChoice toolChoice,
    required bool parallelToolCalls,
    bool enableThinking = false,
    GenerationParams? params,
    List<ToolDefinition>? tools,
    Map<String, dynamic>? responseFormat,
  }) {
    final strictResponseFormat = rejectUnsupportedResponseFormat(
      backend,
      responseFormat,
    );
    final schemaBackend =
        strictResponseFormat && !supportsGrammarConstraints(backend)
        ? backend as BackendJsonSchemaChatGeneration
        : null;
    Map<String, dynamic>? nativeSchema;
    if (schemaBackend != null) {
      validateJsonSchemaChatRequest(
        messages,
        params ?? const GenerationParams(),
        hasTools: tools?.isNotEmpty ?? false,
        requiredTools: toolChoice == ToolChoice.required,
        parallelToolCalls: parallelToolCalls,
        enableThinking:
            enableThinking && !supportsJsonSchemaChatThinking(backend),
      );
      if (templateResult.thinkingForcedOpen) {
        throw LlamaUnsupportedException(
          'Native JSON Schema chat cannot use a forced-open thinking template.',
        );
      }
      nativeSchema =
          jsonDecode(
                jsonSchemaChatPayload(responseFormatSchema(responseFormat)!),
              )
              as Map<String, dynamic>;
    }
    final stops = schemaBackend != null
        ? <String>[]
        : {...templateResult.stopSequences, ...?params?.stopSequences}.toList();

    _logTemplateResult(templateResult, stops);

    final mediaParts = messages
        .expand(partsInPromptOrder)
        .toList(growable: false);
    final backendSupportsGrammarConstraints = supportsGrammarConstraints(
      backend,
    );
    if (!backendSupportsGrammarConstraints && templateResult.grammar != null) {
      LlamaLogger.instance.debug(
        '  Template grammar skipped: backend does not support grammar constraints',
      );
    }
    if (!backendSupportsGrammarConstraints &&
        toolChoice == ToolChoice.required &&
        tools != null &&
        tools.isNotEmpty &&
        templateResult.format == ChatFormat.hermes.index) {
      throw LlamaUnsupportedException(
        'ToolChoice.required for Hermes/Qwen tool calling requires '
        'grammar-constrained decoding, but the active backend does not '
        'support grammar constraints. The active backend cannot enforce the '
        'declared tool schema before generation; use '
        'ToolChoice.auto for best-effort tool calling, or use a '
        'grammar-capable backend such as llama.cpp.',
      );
    }

    final skipsLazyTemplateGrammar =
        backendSupportsGrammarConstraints &&
        templateResult.grammar != null &&
        templateResult.grammarLazy &&
        !supportsLazyGrammar(backend);
    final requiresLfmAutoGrammar = isLfm2AutoGrammar(templateResult);
    if (requiresLfmAutoGrammar &&
        (!backendSupportsGrammarConstraints ||
            !supportsLazyGrammar(backend) ||
            backend is! BackendPromptPenaltyGeneration ||
            !(backend as BackendPromptPenaltyGeneration)
                .supportsPromptPenaltiesWithGrammar)) {
      throw LlamaUnsupportedException(
        'LFM2 auto tool calling requires schema-directed lazy grammar and '
        'prompt-penalty preservation. The active backend/runtime does not '
        'report both capabilities; use a supported native llama.cpp runtime '
        'or ToolChoice.required. Web requires bridge assets v0.1.82+ whose '
        'loaded core reports lazyGrammar and penaltyPromptTokensWithGrammar.',
      );
    }
    if (requiresLfmAutoGrammar &&
        backend is BackendChatMessageValidation &&
        (backend as BackendChatMessageValidation).requiresStructuredChatInput) {
      throw LlamaUnsupportedException(
        'LFM2 auto Python-call grammar requires the rendered prompt-penalty '
        'generation route, but the active backend requires structured chat '
        'input. Use a compatible rendered-prompt backend or ToolChoice.required.',
      );
    }
    if (skipsLazyTemplateGrammar) {
      if (strictResponseFormat) {
        throw LlamaUnsupportedException(
          'Strict responseFormat output with tools needs a lazy grammar, but '
          'the active backend applies grammars from the first token (for '
          'example, WebGPU). Omit tools or responseFormat on this backend.',
        );
      }
      if (toolChoice == ToolChoice.required) {
        throw LlamaUnsupportedException(
          'ToolChoice.required for ${_formatName(templateResult)} tool calling '
          'needs a lazy tool-call grammar, but the active backend applies '
          'grammars from the first token (for example, WebGPU). Use '
          'ToolChoice.auto for best-effort tool calling, or use native '
          'llama.cpp.',
        );
      }
      LlamaLogger.instance.debug(
        '  Lazy template grammar skipped: backend does not support lazy '
        'grammar; tool calls are parsed best-effort',
      );
    }
    final hasTemplateGrammar =
        templateResult.grammar != null &&
        backendSupportsGrammarConstraints &&
        !skipsLazyTemplateGrammar;
    final schemaTools =
        toolChoice != ToolChoice.none &&
        (tools?.any(toolUsesJsonSchema) ?? false);
    if (schemaTools && !hasTemplateGrammar) {
      throw LlamaUnsupportedException(
        'Canonical JSON Schema tools require an active tool grammar. This backend/runtime cannot enforce the selected format and tool choice; use a grammar-capable backend or a supported non-lazy required-tool format.',
      );
    }
    if (hasTemplateGrammar) {
      checkTemplateGrammarLimits(templateResult.grammar!);
    }
    final effectiveGrammar = hasTemplateGrammar
        ? templateResult.grammar
        : params?.grammar;
    final effectiveGrammarLazy = hasTemplateGrammar
        ? templateResult.grammarLazy
        : (params?.grammarLazy ?? false);
    final effectiveGrammarTriggers = hasTemplateGrammar
        ? templateResult.grammarTriggers
              .map(
                (trigger) => GenerationGrammarTrigger.typed(
                  type: GrammarTriggerType.fromWireValue(trigger.type),
                  value: trigger.value,
                  token: trigger.token,
                ),
              )
              .toList(growable: false)
        : (params?.grammarTriggers ?? const <GenerationGrammarTrigger>[]);
    final effectivePreservedTokens = {
      if (backendSupportsGrammarConstraints && !skipsLazyTemplateGrammar)
        ...templateResult.preservedTokens,
      ...?params?.preservedTokens,
    }.toList(growable: false);
    final nativeChatBackend = schemaTools || requiresLfmAutoGrammar
        ? null
        : _nativeChatBackendFor(
            backend,
            messages,
            toolChoice: toolChoice,
            parallelToolCalls: parallelToolCalls,
          );
    final requestedThinkingBudget = params?.thinkingBudget;
    final effectiveThinkingBudget = requestedThinkingBudget == null
        ? null
        : _resolveThinkingBudgetTags(
            requestedThinkingBudget,
            templateResult,
            rendersPrompt: nativeChatBackend == null && schemaBackend == null,
          );

    final generationParams = (params ?? const GenerationParams()).copyWith(
      stopSequences: stops,
      grammar: effectiveGrammar,
      grammarLazy: effectiveGrammarLazy,
      thinkingBudget: effectiveThinkingBudget,
      grammarTriggers: effectiveGrammarTriggers,
      preservedTokens: effectivePreservedTokens,
    );

    final parseToolCallsEnabled =
        tools != null && tools.isNotEmpty && toolChoice != ToolChoice.none;

    return ChatCompletionRequestPlan(
      templateResult: templateResult,
      generationParams: generationParams,
      mediaParts: mediaParts,
      nativeChatBackend: nativeChatBackend,
      parseToolCallsEnabled: parseToolCallsEnabled,
      excludesPromptFromPenalties: skipsLazyTemplateGrammar,
      includesPromptInPenalties: requiresLfmAutoGrammar,
      jsonSchemaBackend: schemaBackend,
      jsonSchema: nativeSchema,
    );
  }

  static void _logTemplateResult(
    LlamaChatTemplateResult templateResult,
    List<String> stops,
  ) {
    LlamaLogger.instance.debug('Chat template result:');
    LlamaLogger.instance.debug('  Format: ${templateResult.format}');
    LlamaLogger.instance.debug('  Prompt: ${templateResult.prompt}');
    LlamaLogger.instance.debug('  Stop sequences: $stops');
    LlamaLogger.instance.debug(
      '  Grammar present: ${templateResult.grammar != null}',
    );
    LlamaLogger.instance.debug('  Grammar lazy: ${templateResult.grammarLazy}');
    LlamaLogger.instance.debug(
      '  Grammar triggers: ${templateResult.grammarTriggers.length}',
    );
    LlamaLogger.instance.debug(
      '  Thinking forced open: ${templateResult.thinkingForcedOpen}',
    );
  }

  static ThinkingBudget _resolveThinkingBudgetTags(
    ThinkingBudget budget,
    LlamaChatTemplateResult templateResult, {
    required bool rendersPrompt,
  }) {
    return ChatTemplateEngine.resolveThinkingBudget(
      templateResult.format,
      budget,
      rendersPrompt: rendersPrompt,
    );
  }

  /// Admits an optional native provider before rendering or session edits.
  static Future<void> prepareResponseFormat(
    LlamaBackend backend,
    Map<String, dynamic>? responseFormat,
  ) async {
    final schema = responseFormatSchema(responseFormat);
    if (schema != null &&
        !supportsGrammarConstraints(backend) &&
        backend is BackendJsonSchemaChatGeneration) {
      jsonSchemaChatPayload(schema);
      await (backend as BackendJsonSchemaChatGeneration)
          .prepareJsonSchemaChat();
    }
    rejectUnsupportedResponseFormat(backend, responseFormat);
  }

  /// Whether [responseFormat] requests strict structured output.
  ///
  /// Throws [LlamaUnsupportedException] for an unrecognised shape, or for a
  /// strict format when [backend] has no grammar-constrained decoding. Both
  /// depend only on the request and backend, so callers can check them before
  /// rendering or changing any state.
  static bool rejectUnsupportedResponseFormat(
    LlamaBackend backend,
    Map<String, dynamic>? responseFormat,
  ) {
    if (responseFormatSchema(responseFormat) == null) return false;
    if (!supportsGrammarConstraints(backend) &&
        !(backend is BackendJsonSchemaChatGeneration &&
            (backend as BackendJsonSchemaChatGeneration)
                .supportsJsonSchemaChatGeneration)) {
      throw LlamaUnsupportedException(
        'Strict responseFormat output requires '
        'grammar-constrained decoding, but the active backend does not '
        'support grammar constraints or an admitted native JSON Schema provider. '
        'LiteRT-LM Web has no qualified schema constraint API; '
        'use a grammar-capable backend such as llama.cpp, or omit '
        'responseFormat for best-effort JSON output.',
      );
    }
    return true;
  }

  /// Whether [backend] admitted its loaded model to reason before a
  /// schema-constrained reply.
  static bool supportsJsonSchemaChatThinking(LlamaBackend backend) =>
      backend is BackendJsonSchemaThinkingChatGeneration &&
      (backend as BackendJsonSchemaThinkingChatGeneration)
          .supportsJsonSchemaChatThinking;

  /// Whether [backend] applies grammar constraints; true unless it reports
  /// otherwise.
  static bool supportsGrammarConstraints(LlamaBackend backend) {
    if (backend is BackendGrammarConstraintsSupport) {
      return (backend as BackendGrammarConstraintsSupport)
          .supportsGrammarConstraints;
    }
    return true;
  }

  static String _formatName(LlamaChatTemplateResult templateResult) {
    return templateResult.format < ChatFormat.values.length
        ? ChatFormat.values[templateResult.format].name
        : 'this chat format';
  }

  /// Whether [backend] applies lazy grammars; true unless it reports
  /// otherwise.
  static bool supportsLazyGrammar(LlamaBackend backend) {
    if (backend is BackendLazyGrammarSupport) {
      return (backend as BackendLazyGrammarSupport).supportsLazyGrammar;
    }
    return true;
  }

  static BackendNativeChatGeneration? _nativeChatBackendFor(
    LlamaBackend backend,
    List<LlamaChatMessage> messages, {
    required ToolChoice toolChoice,
    required bool parallelToolCalls,
  }) {
    if (backend is! BackendNativeChatGeneration) {
      return null;
    }
    final nativeBackend = backend as BackendNativeChatGeneration;
    if (backend is BackendChatMessageValidation &&
        (backend as BackendChatMessageValidation).requiresStructuredChatInput &&
        nativeBackend.supportsNativeChatGeneration) {
      return nativeBackend;
    }
    return _canUseNativeChatGeneration(
          nativeBackend,
          messages,
          toolChoice: toolChoice,
          parallelToolCalls: parallelToolCalls,
        )
        ? nativeBackend
        : null;
  }

  static bool _canUseNativeChatGeneration(
    BackendNativeChatGeneration backend,
    List<LlamaChatMessage> messages, {
    required ToolChoice toolChoice,
    required bool parallelToolCalls,
  }) {
    if (!backend.supportsNativeChatGeneration || messages.isEmpty) {
      return false;
    }
    if (messages.last.role == LlamaChatRole.system) {
      return false;
    }
    if (toolChoice == ToolChoice.required || parallelToolCalls) {
      return false;
    }
    return true;
  }
}
