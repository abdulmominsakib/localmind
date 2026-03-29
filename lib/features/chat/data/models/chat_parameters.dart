import 'package:localmind/core/constants/app_constants.dart';

class ChatParameters {
  final double temperature;
  final double topP;
  final int maxTokens;
  final int contextLength;

  const ChatParameters({
    required this.temperature,
    required this.topP,
    required this.maxTokens,
    required this.contextLength,
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
  }) {
    return ChatParameters(
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      maxTokens: maxTokens ?? this.maxTokens,
      contextLength: contextLength ?? this.contextLength,
    );
  }
}
