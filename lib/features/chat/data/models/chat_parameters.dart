import '../../../../core/constants/app_constants.dart';
import '../../providers/chat_reasoning_providers.dart';

class ChatParameters {
  final double temperature;
  final double topP;
  final int maxTokens;
  final int contextLength;
  final String? systemPrompt;
  final int? topK;
  final double? minP;
  final double? repeatPenalty;

  /// Null when the active model doesn't support reasoning (no reasoning
  /// control fields should be sent); otherwise reflects the Think toggle.
  final bool? reasoningEnabled;
  final ReasoningEffort reasoningEffort;

  /// Raw LM Studio `allowed_options` for the active model (e.g.
  /// `["low","medium","high","xhigh"]`, `["off","on"]`). Null when unknown
  /// (legacy servers) or for non-LM-Studio providers. Lets
  /// [LMStudioChatService] send exactly what the server advertises and omit
  /// the key when `off` isn't allowed instead of triggering HTTP 400.
  final List<String>? reasoningAllowedOptions;

  /// Raw LM Studio `reasoning.default` for the active model. Used as a
  /// tie-breaker when snapping efforts.
  final String? reasoningDefaultOption;

  const ChatParameters({
    required this.temperature,
    required this.topP,
    required this.maxTokens,
    required this.contextLength,
    this.systemPrompt,
    this.topK,
    this.minP,
    this.repeatPenalty,
    this.reasoningEnabled,
    this.reasoningEffort = ReasoningEffort.low,
    this.reasoningAllowedOptions,
    this.reasoningDefaultOption,
  });

  factory ChatParameters.defaults() => const ChatParameters(
    temperature: AppConstants.defaultTemperature,
    topP: AppConstants.defaultTopP,
    maxTokens: AppConstants.defaultMaxTokens,
    contextLength: AppConstants.defaultContextLength,
  );

  ChatParameters copyWith({
    double? temperature,
    double? topP,
    int? maxTokens,
    int? contextLength,
    String? systemPrompt,
    int? topK,
    double? minP,
    double? repeatPenalty,
    bool? reasoningEnabled,
    ReasoningEffort? reasoningEffort,
    List<String>? reasoningAllowedOptions,
    String? reasoningDefaultOption,
  }) {
    return ChatParameters(
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      maxTokens: maxTokens ?? this.maxTokens,
      contextLength: contextLength ?? this.contextLength,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      topK: topK ?? this.topK,
      minP: minP ?? this.minP,
      repeatPenalty: repeatPenalty ?? this.repeatPenalty,
      reasoningEnabled: reasoningEnabled ?? this.reasoningEnabled,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      reasoningAllowedOptions:
          reasoningAllowedOptions ?? this.reasoningAllowedOptions,
      reasoningDefaultOption:
          reasoningDefaultOption ?? this.reasoningDefaultOption,
    );
  }
}
