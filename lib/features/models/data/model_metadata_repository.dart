import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ModelMetadata {
  const ModelMetadata({this.isFavorite = false, this.note});

  final bool isFavorite;
  final String? note;

  ModelMetadata copyWith({
    bool? isFavorite,
    String? note,
    bool clearNote = false,
  }) {
    return ModelMetadata(
      isFavorite: isFavorite ?? this.isFavorite,
      note: clearNote ? null : (note ?? this.note),
    );
  }
}

class ModelMetadataRepository {
  ModelMetadataRepository(this._prefs);

  final SharedPreferences _prefs;
  static const _storageKey = 'modelMetadata';

  String _entryKey(String serverId, String modelId) => '$serverId::$modelId';

  Map<String, dynamic> _readAll() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeAll(Map<String, dynamic> data) async {
    await _prefs.setString(_storageKey, jsonEncode(data));
  }

  ModelMetadata getMetadata(String serverId, String modelId) {
    final entry = _readAll()[_entryKey(serverId, modelId)];
    if (entry is! Map) return const ModelMetadata();
    return ModelMetadata(
      isFavorite: entry['favorite'] == true,
      note: entry['note'] as String?,
    );
  }

  Map<String, ModelMetadata> getAllForServer(String serverId) {
    final prefix = '$serverId::';
    final result = <String, ModelMetadata>{};
    for (final entry in _readAll().entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final modelId = entry.key.substring(prefix.length);
      final value = entry.value;
      if (value is! Map) continue;
      result[modelId] = ModelMetadata(
        isFavorite: value['favorite'] == true,
        note: value['note'] as String?,
      );
    }
    return result;
  }

  Future<void> setFavorite(
    String serverId,
    String modelId,
    bool isFavorite,
  ) async {
    final all = _readAll();
    final key = _entryKey(serverId, modelId);
    final existing = Map<String, dynamic>.from(
      (all[key] as Map?)?.cast<String, dynamic>() ?? {},
    );
    existing['favorite'] = isFavorite;
    all[key] = existing;
    await _writeAll(all);
  }

  Future<void> setNote(String serverId, String modelId, String? note) async {
    final all = _readAll();
    final key = _entryKey(serverId, modelId);
    final existing = Map<String, dynamic>.from(
      (all[key] as Map?)?.cast<String, dynamic>() ?? {},
    );
    if (note == null || note.trim().isEmpty) {
      existing.remove('note');
    } else {
      existing['note'] = note.trim();
    }
    if (existing.isEmpty) {
      all.remove(key);
    } else {
      all[key] = existing;
    }
    await _writeAll(all);
  }
}
