part of 'llama_cpp_service.dart';

/// Retention class of a startup diagnostic.
enum StartupDiagnosticCategory {
  /// Library discovery and backend probe results.
  causal,

  /// Cleanup failures, such as a failed Windows `FreeLibrary`.
  teardown,
}

/// Prefix of stored teardown entries.
const String startupTeardownDiagnosticPrefix = 'teardown: ';

/// Bounded buffer of sanitized startup diagnostics, in recorded order.
///
/// - Entries are cut to [maxEntryLength]; teardown entries start with
///   [startupTeardownDiagnosticPrefix].
/// - A message whose stored form equals a retained entry is ignored.
/// - At [maxEntries], recording evicts the oldest teardown entry. With none
///   retained, a teardown message is ignored and a causal one evicts the causal
///   entry at index [pinnedCausalEntries].
class StartupDiagnosticBuffer {
  /// Maximum retained entries.
  static const int maxEntries = 32;

  /// Leading causal entries that are never evicted.
  static const int pinnedCausalEntries = 16;

  /// Maximum stored characters per entry.
  static const int maxEntryLength = 2048;

  final List<String> _entries = <String>[];

  /// Retained entries in recorded order.
  List<String> get entries => List<String>.unmodifiable(_entries);

  /// Records [message] under [category].
  void record(
    String message, {
    StartupDiagnosticCategory category = StartupDiagnosticCategory.causal,
  }) {
    var entry = _sanitizeStartupDiagnostic(message);
    if (entry.isEmpty) {
      return;
    }
    final isTeardown = category == StartupDiagnosticCategory.teardown;
    if (isTeardown) {
      entry = '$startupTeardownDiagnosticPrefix$entry';
    }
    if (entry.length > maxEntryLength) {
      entry = _startupDiagnosticHead(entry, maxEntryLength - 3);
    }
    if (_entries.contains(entry)) {
      return;
    }
    if (_entries.length >= maxEntries) {
      final oldestTeardown = _entries.indexWhere(_isTeardownStartupDiagnostic);
      if (oldestTeardown != -1) {
        _entries.removeAt(oldestTeardown);
      } else if (isTeardown) {
        return;
      } else {
        _entries.removeAt(pinnedCausalEntries);
      }
    }
    _entries.add(entry);
  }

  /// Removes all entries.
  void clear() => _entries.clear();
}

bool _isTeardownStartupDiagnostic(String entry) =>
    entry.startsWith(startupTeardownDiagnosticPrefix);

String _startupDiagnosticHead(String text, int length) {
  var end = math.min(length, text.length);
  if (end > 0 &&
      end < text.length &&
      (text.codeUnitAt(end - 1) & 0xFC00) == 0xD800) {
    end -= 1;
  }
  return '${text.substring(0, end)}...';
}

/// Renders startup diagnostics as a suffix for a load-failure message.
///
/// Returns an empty string when nothing was recorded, so platforms that never
/// populate the buffer keep their existing message byte for byte. Control
/// characters are flattened and credential-bearing HTTP URL components are
/// redacted before the diagnostics are included in an exception. Outside HTTP
/// URLs, the token in `Bearer <token>` and the value in `<name>=<value>` are
/// replaced with `<redacted-secret>`: `Bearer` and `<name>` match
/// case-insensitively when not preceded by an ASCII letter or digit, `<name>`
/// is `token`, `key`, `secret`, `password`, `api_key` or `apikey`, and the
/// token or value is a double- or single-quoted string or a run of
/// non-whitespace characters, for `<value>` optionally after `Bearer` and
/// whitespace. An entry with a control-split credentialed URL is replaced
/// entirely rather than guessing whether the control was part of the URL or a
/// diagnostic boundary.
///
/// Entries render in the given order. When they exceed [maxLength], each entry
/// longer than half of [maxLength] is cut to that half, and entries are kept by
/// priority while they fit: first causal, last causal, other causal oldest
/// first, then those starting with [startupTeardownDiagnosticPrefix]. Each run
/// of omitted entries renders as `...`. The last causal entry is cut to the
/// remaining budget instead of being omitted; if even the first-ranked entry
/// does not fit, its head is rendered alone.
String formatStartupDiagnostics(List<String> entries, {int maxLength = 4096}) {
  if (maxLength < 0) {
    throw RangeError.range(maxLength, 0, null, 'maxLength');
  }
  if (maxLength == 0) {
    return '';
  }
  final sanitizedEntries = entries
      .map(_sanitizeStartupDiagnostic)
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
  if (sanitizedEntries.isEmpty) {
    return '';
  }
  var joined = sanitizedEntries.join('; ');
  if (joined.length > maxLength) {
    joined = _truncateStartupDiagnostics(sanitizedEntries, maxLength);
  }
  return ', startupDiagnostics=[$joined]';
}

String _truncateStartupDiagnostics(List<String> entries, int maxLength) {
  const marker = '...';
  const separator = '; ';
  if (maxLength <= marker.length) {
    return marker.substring(0, maxLength);
  }

  final entryCap = math.max(maxLength ~/ 2, marker.length + 1);
  final texts = <String>[
    for (final entry in entries)
      entry.length > entryCap
          ? _startupDiagnosticHead(entry, entryCap - marker.length)
          : entry,
  ];
  final causal = <int>[
    for (var i = 0; i < entries.length; i++)
      if (!_isTeardownStartupDiagnostic(entries[i])) i,
  ];
  final ranked = <int>[
    if (causal.isNotEmpty) causal.first,
    if (causal.length > 1) causal.last,
    if (causal.length > 2) ...causal.getRange(1, causal.length - 1),
    for (var i = 0; i < entries.length; i++)
      if (_isTeardownStartupDiagnostic(entries[i])) i,
  ];
  final finalOutcome = causal.length > 1 ? causal.last : -1;

  final kept = List<bool>.filled(entries.length, false);
  var keptCount = 0;
  var keptLength = 0;
  var omittedRuns = 1;
  for (final index in ranked) {
    final splitsLeft = index > 0 && !kept[index - 1];
    final splitsRight = index + 1 < entries.length && !kept[index + 1];
    final nextRuns =
        omittedRuns - 1 + (splitsLeft ? 1 : 0) + (splitsRight ? 1 : 0);
    final budget =
        maxLength -
        keptLength -
        nextRuns * marker.length -
        (keptCount + nextRuns) * separator.length;
    if (texts[index].length > budget) {
      if (keptCount == 0) {
        return _startupDiagnosticHead(
          entries[index],
          maxLength - marker.length,
        );
      }
      if (index != finalOutcome || budget <= marker.length) {
        continue;
      }
      texts[index] = _startupDiagnosticHead(
        texts[index],
        budget - marker.length,
      );
    }
    kept[index] = true;
    keptCount += 1;
    keptLength += texts[index].length;
    omittedRuns = nextRuns;
  }

  final parts = <String>[];
  var inOmittedRun = false;
  for (var i = 0; i < entries.length; i++) {
    if (kept[i]) {
      parts.add(texts[i]);
      inOmittedRun = false;
    } else if (!inOmittedRun) {
      parts.add(marker);
      inOmittedRun = true;
    }
  }
  return parts.join(separator);
}

String _sanitizeStartupDiagnostic(String entry) {
  final controlCharacters = RegExp(
    r'[\u0000-\u001f\u007f-\u009f\u2028\u2029]+',
  );
  if (_hasControlSplitSensitiveHttpUrl(entry, controlCharacters)) {
    return '<redacted-startup-diagnostic>';
  }
  final flattenedEntry = entry
      .replaceAll(controlCharacters, ' ')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
  final redacted = StringBuffer();
  var start = 0;
  for (final url in _startupDiagnosticHttpUrl.allMatches(flattenedEntry)) {
    redacted
      ..write(
        _redactStartupDiagnosticSecrets(
          flattenedEntry.substring(start, url.start),
        ),
      )
      ..write(_redactStartupDiagnosticUrl(url.group(0)!));
    start = url.end;
  }
  redacted.write(
    _redactStartupDiagnosticSecrets(flattenedEntry.substring(start)),
  );
  return redacted.toString().replaceAll(RegExp(r' {2,}'), ' ').trim();
}

final RegExp _startupDiagnosticHttpUrl = RegExp(
  r'https?://(?:(?!https?://)\S)+',
  caseSensitive: false,
);

const String _startupDiagnosticSecretValue = '''(?:"[^"]*"|'[^']*'|\\S+)''';

final RegExp _startupDiagnosticKeyValueSecret = RegExp(
  r'(?<![A-Za-z0-9])(token|key|secret|password|api_key|apikey)='
  r'(?:bearer\s+)?'
  '$_startupDiagnosticSecretValue',
  caseSensitive: false,
);

final RegExp _startupDiagnosticBearerToken = RegExp(
  r'(?<![A-Za-z0-9])(bearer)\s+'
  '$_startupDiagnosticSecretValue',
  caseSensitive: false,
);

String _redactStartupDiagnosticUrl(String text) {
  final uri = Uri.tryParse(text);
  final scheme = uri?.scheme.toLowerCase();
  if (uri == null || (scheme != 'http' && scheme != 'https')) {
    return '<redacted-url>';
  }
  return Uri(
    scheme: scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
}

String _redactStartupDiagnosticSecrets(String text) {
  return text
      .replaceAllMapped(
        _startupDiagnosticKeyValueSecret,
        (match) => '${match.group(1)}=<redacted-secret>',
      )
      .replaceAllMapped(
        _startupDiagnosticBearerToken,
        (match) => '${match.group(1)} <redacted-secret>',
      );
}

bool _hasControlSplitSensitiveHttpUrl(String entry, RegExp controlCharacters) {
  if (!controlCharacters.hasMatch(entry)) {
    return false;
  }
  final compacted = entry.replaceAll(controlCharacters, '');
  final candidates = RegExp(
    r'https?://(?:(?!https?://)\S)+',
    caseSensitive: false,
  ).allMatches(compacted);
  for (final candidate in candidates) {
    final text = candidate.group(0)!;
    final uri = Uri.tryParse(text);
    if (uri == null) {
      if (text.contains('@') || text.contains('?') || text.contains('#')) {
        return true;
      }
      continue;
    }
    final scheme = uri.scheme.toLowerCase();
    if ((scheme == 'http' || scheme == 'https') &&
        (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment)) {
      return true;
    }
  }
  return false;
}

/// The message thrown when `llama_model_load_from_file` returns null.
String describeModelLoadFailure({
  required int sizeBytes,
  required String backendDiagnostics,
  required List<String> startupDiagnostics,
}) =>
    'Failed to load model (size=$sizeBytes bytes, '
    'diagnostics=$backendDiagnostics)'
    '${formatStartupDiagnostics(startupDiagnostics)}';

/// The message thrown when a speculative draft model fails to load.
String describeDraftModelLoadFailure({
  required String label,
  required String path,
  required int sizeBytes,
  required String backendDiagnostics,
  required List<String> startupDiagnostics,
}) =>
    'Failed to load $label (size=$sizeBytes bytes, '
    'path=$path, diagnostics=$backendDiagnostics)'
    '${formatStartupDiagnostics(startupDiagnostics)}';
