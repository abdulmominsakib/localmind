import 'dart:collection';

import 'template_caps.dart';

/// Least-recently-used cache of [TemplateCaps] keyed by exact template source.
///
/// Holds at most [capacity] entries and retains each key string until its
/// entry is evicted or [clear] is called. Entries never expire otherwise.
class TemplateCapsCache {
  /// Capacity of [shared].
  static const int sharedCapacity = 16;

  /// Cache used by [TemplateCaps.detect].
  ///
  /// Static state is per isolate, so each isolate has its own instance.
  static final TemplateCapsCache shared = TemplateCapsCache(sharedCapacity);

  /// Maximum number of entries held at once.
  final int capacity;

  final LinkedHashMap<String, TemplateCaps> _entries =
      LinkedHashMap<String, TemplateCaps>();

  /// Creates an empty cache holding at most [capacity] entries.
  ///
  /// Throws an [ArgumentError] when [capacity] is less than 1.
  TemplateCapsCache(this.capacity) {
    if (capacity < 1) {
      throw ArgumentError.value(capacity, 'capacity', 'must be at least 1');
    }
  }

  /// Number of entries currently held.
  int get length => _entries.length;

  /// Cached template sources, least recently used first.
  List<String> get sources => List<String>.unmodifiable(_entries.keys);

  /// Returns the entry for [templateSource] and marks it most recently used,
  /// or returns `null` when there is none.
  TemplateCaps? lookup(String templateSource) {
    final caps = _entries.remove(templateSource);
    if (caps != null) {
      _entries[templateSource] = caps;
    }
    return caps;
  }

  /// Stores [caps] for [templateSource] as the most recently used entry,
  /// replacing any existing entry for it, then evicts least recently used
  /// entries until [length] is at most [capacity].
  void store(String templateSource, TemplateCaps caps) {
    _entries.remove(templateSource);
    _entries[templateSource] = caps;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Removes every entry.
  void clear() => _entries.clear();
}
