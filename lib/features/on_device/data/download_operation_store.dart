import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/async_mutex.dart';
import '../../../core/providers/storage_providers.dart';
import 'models/download_operation.dart';

class DownloadOperationStore {
  DownloadOperationStore(this._prefs);

  static const _key = 'model_download_operations_v1';
  static const _version = 1;

  final SharedPreferences _prefs;
  final AsyncMutex _mutex = AsyncMutex();
  Map<String, DownloadOperation> _cache = const {};

  void loadSync() {
    try {
      final raw = _prefs.getString(_key);
      if (raw == null || raw.isEmpty) {
        _cache = const {};
        return;
      }
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final version = (decoded['version'] as num?)?.toInt() ?? 0;
      if (version != _version) {
        _cache = const {};
        return;
      }
      final ops = decoded['operations'] as Map<String, dynamic>? ?? {};
      final result = <String, DownloadOperation>{};
      for (final e in ops.entries) {
        try {
          result[e.key] = DownloadOperation.fromJson(
            e.value as Map<String, dynamic>,
          );
        } catch (_) {
          // Drop corrupt entries.
        }
      }
      _cache = result;
    } catch (_) {
      _cache = const {};
    }
  }

  DownloadOperation? forModel(String modelId) => _cache[modelId];

  List<DownloadOperation> all() => _cache.values.toList();

  Future<void> begin(DownloadOperation op) async {
    await _mutex.run(() async {
      final next = Map<String, DownloadOperation>.from(_cache);
      next[op.modelId] = op;
      _cache = next;
      await _persist();
    });
  }

  Future<void> enrich(
    String operationId, {
    String? taskId,
    String? baseRevision,
    String? targetRevision,
  }) async {
    await _mutex.run(() async {
      final entry = _cache.values
          .where((o) => o.operationId == operationId)
          .firstOrNull;
      if (entry == null) return;
      final updated = entry.copyWith(
        taskId: taskId,
        baseRevision: baseRevision,
        targetRevision: targetRevision,
        updatedAt: DateTime.now(),
      );
      final next = Map<String, DownloadOperation>.from(_cache);
      next[entry.modelId] = updated;
      _cache = next;
      await _persist();
    });
  }

  Future<void> markPhase(
    String operationId,
    DownloadOperationPhase phase,
  ) async {
    await _mutex.run(() async {
      final entry = _cache.values
          .where((o) => o.operationId == operationId)
          .firstOrNull;
      if (entry == null) return;
      final updated = entry.copyWith(phase: phase, updatedAt: DateTime.now());
      final next = Map<String, DownloadOperation>.from(_cache);
      next[entry.modelId] = updated;
      _cache = next;
      await _persist();
    });
  }

  Future<void> complete(String operationId) async {
    await _mutex.run(() async {
      final entry = _cache.values
          .where((o) => o.operationId == operationId)
          .firstOrNull;
      if (entry == null) return;
      final next = Map<String, DownloadOperation>.from(_cache);
      next.remove(entry.modelId);
      _cache = next;
      await _persist();
    });
  }

  Future<void> fail(String operationId) async {
    await complete(operationId);
  }

  Future<void> prune({required Set<String> liveModelIds}) async {
    await _mutex.run(() async {
      final next = Map<String, DownloadOperation>.from(_cache);
      next.removeWhere((modelId, _) => !liveModelIds.contains(modelId));
      _cache = next;
      await _persist();
    });
  }

  Future<void> _persist() async {
    final envelope = {
      'version': _version,
      'operations': _cache.map((k, v) => MapEntry(k, v.toJson())),
    };
    await _prefs.setString(_key, json.encode(envelope));
  }
}

final downloadOperationStoreProvider =
    Provider<DownloadOperationStore>((ref) {
  return DownloadOperationStore(ref.read(sharedPreferencesProvider));
});
