import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/storage_providers.dart';
import 'models/model_info.dart';

const _prefsKey = 'modelVisionOverrides';

/// Per-model manual "supports vision" overrides for servers that don't
/// advertise capability metadata (e.g. plain OpenAI-compatible / vLLM
/// endpoints, where the app would otherwise treat every model as text-only).
/// Keys pair the server and model ids so the same model on different servers
/// can be flagged differently.
class ModelVisionOverridesNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value == true));
    } catch (e) {
      // Tests or unusual embedding contexts may not provide storage; the
      // feature degrades to in-memory-only behavior.
      if (e is UnimplementedError) return const {};
      return const {};
    }
  }

  static String key(String serverId, String modelId) => '$serverId///$modelId';

  /// Sets the override for a model. `null` restores server-declared behavior.
  Future<void> setVision(String serverId, String modelId, bool? value) async {
    final next = Map.of(state);
    final modelKey = key(serverId, modelId);
    if (value == null) {
      next.remove(modelKey);
    } else {
      next[modelKey] = value;
    }
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_prefsKey, jsonEncode(next));
  }
}

final modelVisionOverridesProvider =
    NotifierProvider<ModelVisionOverridesNotifier, Map<String, bool>>(
      ModelVisionOverridesNotifier.new,
    );

/// Applies a manual per-model vision override. Returns the same instance
/// when the map has no matching override or it already agrees with the
/// server-declared value.
ModelInfo applyVisionOverride(ModelInfo model, Map<String, bool> overrides) {
  final forced =
      overrides[ModelVisionOverridesNotifier.key(model.serverId, model.id)];
  if (forced == null || forced == model.supportsVision) return model;
  return model.copyWith(supportsVision: forced);
}
