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
    );
  }
}
