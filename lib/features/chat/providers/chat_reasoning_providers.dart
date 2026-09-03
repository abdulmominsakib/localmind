import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/data/models/model_info.dart';

/// How hard a reasoning-capable model should think, sent as the server's
/// `reasoning.effort` / `reasoning_effort` fields when thinking is enabled.
///
/// Ordered from lightest to heaviest. OpenRouter advertises a per-model
/// subset (e.g. `["minimal","low","medium","high","xhigh"]`) plus a default
/// and whether reasoning is mandatory; LM Studio advertises
/// `capabilities.reasoning.allowed_options` (e.g. `["off","on"]`,
/// `["low","medium","high","xhigh"]`) plus a default. Providers without
/// per-model data fall back to [low]/[medium]/[high] via [effortsForModel].
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
/// order. When [supported] is null/empty (provider didn't advertise efforts)
/// the classic low/medium/high set is returned so existing behaviour is
/// preserved. LM Studio `allowed_options` entries `off`/`on` are not efforts
/// and are filtered out; a binary `["off","on"]` model yields a single
/// placeholder (the picker should be hidden via [hasGranularReasoningChoice]
/// — the request layer sends literal `"on"` for those models).
List<ReasoningEffort> effortsForModel(List<String>? supported) {
  if (supported == null || supported.isEmpty) {
    return const [
      ReasoningEffort.low,
      ReasoningEffort.medium,
      ReasoningEffort.high,
    ];
  }
  final normalized = supported.map((e) => e.trim().toLowerCase()).toSet();
  final list = ReasoningEffort.values
      .where((e) => normalized.contains(e.apiValue))
      .toList(growable: false);
  if (list.isNotEmpty) return list;
  if (normalized.contains('on')) {
    // Binary on/off model (e.g. LM Studio ["off","on"]): no granular choice.
    return const [ReasoningEffort.medium];
  }
  // Shouldn't happen (a model advertising only efforts we don't
  // model), but fall back to the classic set rather than rendering nothing.
  return const [
    ReasoningEffort.low,
    ReasoningEffort.medium,
    ReasoningEffort.high,
  ];
}

/// True when [supported] advertises at least one granular effort
/// (`minimal`/`low`/`medium`/`high`/`xhigh`/`max`). Binary LM Studio models
/// (`["off","on"]`) return false — the UI should hide the effort picker and
/// offer only the on/off toggle.
bool hasGranularReasoningChoice(List<String>? supported) {
  if (supported == null || supported.isEmpty) return true;
  final normalized = supported.map((e) => e.trim().toLowerCase()).toSet();
  return ReasoningEffort.values.any((e) => normalized.contains(e.apiValue));
}

/// Resolves the effort to actually send for [model], snapping [current] to
/// the model's advertised default when [current] isn't supported. Used when
/// building request params so a stale UI config never produces an invalid
/// `reasoning_effort` (e.g. `low` for a model that only supports `high`).
/// Comparison is case-insensitive so LM Studio `allowed_options` (which may
/// include `off`/`on`) interoperate with OpenRouter `supported_efforts`.
/// Binary on/off models (no granular effort advertised) keep [current]
/// unchanged — the effort value is irrelevant there because the request
/// layer sends literal `"on"`.
ReasoningEffort resolveEffortForModel(
  ModelInfo? model,
  ReasoningEffort current,
) {
  final supported = model?.supportedReasoningEfforts;
  if (supported == null || supported.isEmpty) return current;
  final normalized = supported.map((e) => e.trim().toLowerCase()).toSet();
  if (normalized.contains(current.apiValue)) return current;
  if (!hasGranularReasoningChoice(supported)) return current;
  final defaultVal = model?.defaultReasoningEffort?.trim().toLowerCase();
  if (defaultVal != null && normalized.contains(defaultVal)) {
    // Default may be "on"/"off" for LM Studio binary models; only snap to
    // it when it is an actual effort value.
    for (final e in ReasoningEffort.values) {
      if (e.apiValue == defaultVal) return e;
    }
  }
  // Pick the heaviest supported effort we model, else the first advertised.
  for (final e in ReasoningEffort.values.reversed) {
    if (normalized.contains(e.apiValue)) return e;
  }
  return ReasoningEffort.fromApiValue(supported.first);
}

/// Resolves the exact `reasoning` string for LM Studio's native
/// `/api/v1/chat`, or null when the key should be omitted (server default).
///
/// - [enabled] null (model doesn't support reasoning) → null (omit).
/// - Disabled + `off` advertised (or unknown caps) → `'off'`.
/// - Disabled + `off` NOT advertised (e.g. `meta/muse-glimmer` with
///   `["low","medium","high","xhigh"]`) → null (omit). Sending `'off'`
///   there yields HTTP 400, so omitting lets the server use its default
///   instead of failing the whole request (fixes #75 follow-up).
/// - Enabled → the granular effort when advertised; literal `'on'` for
///   binary `["off","on"]` models; `minimal`→`low` and `max`→`xhigh`
///   normalization for LM Studio, which never advertises those two.
String? resolveLmStudioReasoningValue({
  required bool? enabled,
  required ReasoningEffort effort,
  List<String>? allowedOptions,
  String? defaultOption,
}) {
  if (enabled == null) return null;
  final allowed = allowedOptions
      ?.map((e) => e.trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .toSet();
  final def = defaultOption?.trim().toLowerCase();

  if (!enabled) {
    if (allowed == null || allowed.isEmpty) return 'off';
    if (allowed.contains('off')) return 'off';
    return null;
  }

  // Map the two efforts LM Studio never advertises to the nearest value it
  // does understand.
  var candidate = effort.apiValue;
  if (effort == ReasoningEffort.minimal) candidate = 'low';
  if (effort == ReasoningEffort.max) candidate = 'xhigh';

  if (allowed == null || allowed.isEmpty) return candidate;
  if (allowed.contains(candidate)) return candidate;

  final granularAllowed = ReasoningEffort.values
      .where((e) => allowed.contains(e.apiValue))
      .toList(growable: false);

  if (granularAllowed.isNotEmpty) {
    // Snap out-of-range choices to the nearest advertised end; prefer the
    // server default when it is granular.
    if (candidate == 'low') return granularAllowed.first.apiValue;
    if (candidate == 'xhigh') return granularAllowed.last.apiValue;
    if (def != null && def != 'on' && def != 'off' && allowed.contains(def)) {
      return def;
    }
    // Rare non-contiguous case (e.g. medium requested, only low+high
    // allowed): fall back to the heaviest, matching resolveEffortForModel.
    return granularAllowed.last.apiValue;
  }

  if (allowed.contains('on')) return 'on';
  if (def != null && allowed.contains(def)) return def;
  return null;
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
