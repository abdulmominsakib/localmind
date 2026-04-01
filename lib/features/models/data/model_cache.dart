import 'package:localmind/features/models/data/models/model_info.dart';

class ModelCache {
  final _cache = <String, _CacheEntry>{};
  static const Duration ttl = Duration(minutes: 5);

  List<ModelInfo>? get(String serverId) {
    final entry = _cache[serverId];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.timestamp) > ttl) {
      _cache.remove(serverId);
      return null;
    }
    return entry.models;
  }

  void put(String serverId, List<ModelInfo> models) {
    _cache[serverId] = _CacheEntry(models: models, timestamp: DateTime.now());
  }

  void invalidate(String serverId) {
    _cache.remove(serverId);
  }

  void invalidateAll() {
    _cache.clear();
  }
}

class _CacheEntry {
  final List<ModelInfo> models;
  final DateTime timestamp;

  _CacheEntry({required this.models, required this.timestamp});
}
