import 'dart:collection';
import 'dart:convert';

/// Holds only bytes that could still complete a caller stop sequence.
///
/// Matching UTF-8 bytes avoids decoding incomplete token pieces. A completed
/// marker and everything after it are suppressed, even within the same piece.
class StopSequenceBuffer {
  /// Creates a per-generation buffer, ignoring empty and duplicate markers.
  StopSequenceBuffer(List<String> stops)
    : _stops = stops
          .where((stop) => stop.isNotEmpty)
          .toSet()
          .map((stop) => _StopPattern(utf8.encode(stop)))
          .toList(growable: false);

  final List<_StopPattern> _stops;
  final ListQueue<int> _pending = ListQueue<int>();

  /// Whether a complete marker has been consumed.
  bool get isStopped => _isStopped;
  bool _isStopped = false;

  /// Consumes a token piece and returns bytes safe to expose immediately.
  List<int> add(List<int> bytes) {
    if (_isStopped) return const [];
    if (_stops.isEmpty) return bytes;
    final previousLength = _pending.length;
    _pending.addAll(bytes);
    var stopIndex = _pending.length;
    var retainedLength = 0;
    for (final stop in _stops) {
      for (var i = 0; i < bytes.length; i++) {
        if (stop.advance(bytes[i])) {
          final start = previousLength + i + 1 - stop.bytes.length;
          if (start < stopIndex) stopIndex = start;
        }
      }
      if (stop.matched > retainedLength) retainedLength = stop.matched;
    }
    if (stopIndex < _pending.length) {
      final visible = _pending.take(stopIndex).toList();
      _pending.clear();
      _isStopped = true;
      return visible;
    }
    final safeLength = _pending.length - retainedLength;
    return List.generate(
      safeLength,
      (_) => _pending.removeFirst(),
      growable: false,
    );
  }

  /// Releases an unfinished marker prefix when generation ends without a match.
  List<int> finish() {
    final remaining = _pending.toList();
    _pending.clear();
    for (final stop in _stops) {
      stop.matched = 0;
    }
    return remaining;
  }
}

// KMP prefix state processes only newly received bytes. Repeated prefixes in
// long caller markers must not cause rescans of the entire pending suffix on
// every token. Work is linear in incoming bytes per stop (amortized).
class _StopPattern {
  _StopPattern(this.bytes) : fallback = List.filled(bytes.length, 0) {
    var prefix = 0;
    for (var i = 1; i < bytes.length; i++) {
      while (prefix > 0 && bytes[i] != bytes[prefix]) {
        prefix = fallback[prefix - 1];
      }
      if (bytes[i] == bytes[prefix]) prefix++;
      fallback[i] = prefix;
    }
  }

  final List<int> bytes;
  final List<int> fallback;
  int matched = 0;

  bool advance(int byte) {
    while (matched > 0 && byte != bytes[matched]) {
      matched = fallback[matched - 1];
    }
    if (byte == bytes[matched]) matched++;
    if (matched != bytes.length) return false;
    matched = fallback[matched - 1];
    return true;
  }
}
