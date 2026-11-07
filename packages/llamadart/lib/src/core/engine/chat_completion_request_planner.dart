import '../../backends/backend.dart';
import '../exceptions.dart';
import '../llama_logger.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/chat_role.dart';
import '../models/chat/chat_template_result.dart';
import '../models/chat/content_part.dart';
import '../models/inference/generation_params.dart';
import '../models/inference/tool_choice.dart';
import '../models/tools/tool_definition.dart';
import '../template/chat_template_engine.dart';

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

  /// Whether final streaming output should be parsed for tool calls.
  final bool parseToolCallsEnabled;

  /// Whether this plan should call the backend-native chat API.
  bool get usesNativeChatGeneration => nativeChatBackend != null;
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
    GenerationParams? params,
    List<ToolDefinition>? tools,
    Map<String, dynamic>? responseFormat,
  }) {
    final stops = {
      ...templateResult.stopSequences,
      ...?params?.stopSequences,
    }.toList();

    _logTemplateResult(templateResult, stops);

    final mediaParts = messages
        .expand((message) => message.parts)
        .toList(growable: false);
    final backendSupportsGrammarConstraints = _supportsGrammarConstraints(
      backend,
    );
    if (!backendSupportsGrammarConstraints && templateResult.grammar != null) {
      LlamaLogger.instance.debug(
        '  Template grammar skipped: backend does not support grammar constraints',
      );
    }
    if (!backendSupportsGrammarConstraints &&
        _hasStrictResponseFormat(responseFormat)) {
      throw LlamaUnsupportedException(
        'Strict responseFormat output requires '
        'grammar-constrained decoding, but the active backend does not '
        'support grammar constraints. For example, LiteRT-LM native and web '
        'currently do not expose public runtime wiring for JSON-schema/Lark '
        'constraints; '
        'use a grammar-capable backend such as llama.cpp, or omit '
        'responseFormat for best-effort JSON output.',
      );
    }

    final hasTemplateGrammar =
        templateResult.grammar != null && backendSupportsGrammarConstraints;
    final effectiveGrammar = hasTemplateGrammar
        ? templateResult.grammar
        : params?.grammar;
    final effectiveGrammarLazy = hasTemplateGrammar
        ? templateResult.grammarLazy
        : (params?.grammarLazy ?? false);
    final effectiveGrammarTriggers = hasTemplateGrammar
        ? templateResult.grammarTriggers
              .map(
                (trigger) => GenerationGrammarTrigger(
                  type: trigger.type,
                  value: trigger.value,
                  token: trigger.token,
                ),
              )
              .toList(growable: false)
        : (params?.grammarTriggers ?? const <GenerationGrammarTrigger>[]);
    final effectivePreservedTokens = {
      if (backendSupportsGrammarConstraints) ...templateResult.preservedTokens,
      ...?params?.preservedTokens,
    }.toList(growable: false);
    final requestedThinkingBudget = params?.thinkingBudget;
    final effectiveThinkingBudget = requestedThinkingBudget == null
        ? null
        : _resolveThinkingBudgetTags(requestedThinkingBudget, templateResult);

    final generationParams = (params ?? const GenerationParams()).copyWith(
      stopSequences: stops,
      grammar: effectiveGrammar,
      grammarLazy: effectiveGrammarLazy,
      thinkingBudget: effectiveThinkingBudget,
      grammarTriggers: effectiveGrammarTriggers,
      preservedTokens: effectivePreservedTokens,
    );

    final nativeChatBackend = _nativeChatBackendFor(
      backend,
      messages,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
    );
    final parseToolCallsEnabled =
        tools != null && tools.isNotEmpty && toolChoice != ToolChoice.none;

    return ChatCompletionRequestPlan(
      templateResult: templateResult,
      generationParams: generationParams,
      mediaParts: mediaParts,
      nativeChatBackend: nativeChatBackend,
      parseToolCallsEnabled: parseToolCallsEnabled,
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
    LlamaChatTemplateResult templateResult,
  ) {
    final tags = ChatTemplateEngine.thinkingTagsFor(templateResult.format);
    return ThinkingBudget(
      maxTokens: budget.maxTokens,
      startTag: budget.startTag ?? tags.startTag,
      endTag: budget.endTag ?? tags.endTag,
      forcedMessage: budget.forcedMessage,
    );
  }

  static bool _supportsGrammarConstraints(LlamaBackend backend) {
    if (backend is BackendGrammarConstraintsSupport) {
      return (backend as BackendGrammarConstraintsSupport)
          .supportsGrammarConstraints;
    }
    return true;
  }

  static bool _hasStrictResponseFormat(Map<String, dynamic>? responseFormat) {
    if (responseFormat == null) {
      return false;
    }
    final type = responseFormat['type'] as String?;
    return type == 'json_schema' || type == 'json_object';
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
