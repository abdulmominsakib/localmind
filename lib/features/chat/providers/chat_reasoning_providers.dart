import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How hard a reasoning-capable model should think, sent as the server's
/// `reasoning.effort` / `reasoning_effort` fields when thinking is enabled.
enum ReasoningEffort {
  low,
  medium,
  high;

  String get apiValue => name;
}

class ChatReasoningConfig {
  const ChatReasoningConfig({
    this.enabled = true,
    this.effort = ReasoningEffort.low,
  });

  final bool enabled;
  final ReasoningEffort effort;

  ChatReasoningConfig copyWith({bool? enabled, ReasoningEffort? effort}) {
    return ChatReasoningConfig(
      enabled: enabled ?? this.enabled,
      effort: effort ?? this.effort,
    );
  }
}

class ChatReasoningConfigNotifier extends Notifier<ChatReasoningConfig> {
  @override
  ChatReasoningConfig build() => const ChatReasoningConfig();

  void setEnabled(bool enabled) => state = state.copyWith(enabled: enabled);

  void setEffort(ReasoningEffort effort) =>
      state = state.copyWith(effort: effort);
}

final chatReasoningConfigProvider =
    NotifierProvider<ChatReasoningConfigNotifier, ChatReasoningConfig>(() {
      return ChatReasoningConfigNotifier();
    });
