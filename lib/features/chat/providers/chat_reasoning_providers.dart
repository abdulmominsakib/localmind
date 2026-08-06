import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/data/models/model_info.dart';

/// How hard a reasoning-capable model should think, sent as the server's
/// `reasoning.effort` / `reasoning_effort` fields when thinking is enabled.
///
/// Ordered from lightest to heaviest. OpenRouter advertises a per-model
/// subset (e.g. `["minimal","low","medium","high","xhigh"]`) plus a default
/// and whether reasoning is mandatory; non-OpenRouter providers don't, so
/// callers fall back to [low]/[medium]/[high] via [effortsForModel].
enum ReasoningEffort {
  minimal,
  low,
  medium,
  high,
  xhigh,
  max;

  String get apiValue => name;

  /// Parses an OpenRouter effort string. Falls back to [medium] for unknown
  /// values so a request never sends an effort the enum can't represent.
  factory ReasoningEffort.fromApiValue(String value) {
    for (final e in ReasoningEffort.values) {
      if (e.apiValue == value) return e;
    }
    return ReasoningEffort.medium;
  }
}

/// Returns the effort levels to offer for a model, in lightest→heaviest
/// order. When [supported] is null/empty (non-OpenRouter providers, or an
/// OpenRouter model that didn't advertise efforts) the classic
/// low/medium/high set is returned so existing behaviour is preserved.
List<ReasoningEffort> effortsForModel(List<String>? supported) {
  if (supported == null || supported.isEmpty) {
    return const [ReasoningEffort.low, ReasoningEffort.medium, ReasoningEffort.high];
  }
  final list = ReasoningEffort.values
      .where((e) => supported.contains(e.apiValue))
      .toList(growable: false);
  // Shouldn't happen (an OpenRouter model advertising only efforts we don't
  // model), but fall back to the classic set rather than rendering nothing.
  if (list.isEmpty) {
    return const [ReasoningEffort.low, ReasoningEffort.medium, ReasoningEffort.high];
  }
  return list;
}

/// Resolves the effort to actually send for [model], snapping [current] to
/// the model's advertised default when [current] isn't supported. Used when
/// building request params so a stale UI config never produces an invalid
/// `reasoning_effort` (e.g. `low` for a model that only supports `high`).
ReasoningEffort resolveEffortForModel(ModelInfo? model, ReasoningEffort current) {
  final supported = model?.supportedReasoningEfforts;
  if (supported == null || supported.isEmpty) return current;
  if (supported.contains(current.apiValue)) return current;
  final defaultVal = model?.defaultReasoningEffort;
  if (defaultVal != null && supported.contains(defaultVal)) {
    return ReasoningEffort.fromApiValue(defaultVal);
  }
  // Pick the heaviest supported effort we model, else the first advertised.
  for (final e in ReasoningEffort.values.reversed) {
    if (supported.contains(e.apiValue)) return e;
  }
  return ReasoningEffort.fromApiValue(supported.first);
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
