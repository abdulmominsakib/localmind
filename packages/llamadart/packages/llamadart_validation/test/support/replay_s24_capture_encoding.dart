/// Replays only capture encoding into a new analysis directory, never execution.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart_validation/src/s24_litert_capture.dart';

bool equal(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && equal(a[key], b[key]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!equal(a[index], b[index])) return false;
    }
    return true;
  }
  return a == b;
}

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('Expected retained journal and NEW analysis directory');
  }
  final input = File(args[0]);
  final output = Directory(args[1]);
  if (output.existsSync() || input.lengthSync() > 20 * 1024 * 1024) {
    throw StateError('New output and bounded retained input required');
  }
  final stream = input.openSync();
  final List<int> raw;
  try {
    raw = stream.readSync(20 * 1024 * 1024 + 1);
  } finally {
    stream.closeSync();
  }
  if (raw.length > 20 * 1024 * 1024) {
    throw StateError('Retained input grew beyond analysis bound');
  }
  final rows = const LineSplitter()
      .convert(utf8.decode(raw))
      .map(jsonDecode)
      .toList();
  final baseline = utf8.encode('${rows.map(jsonEncode).join('\n')}\n');
  if (!equal(baseline, raw)) {
    throw StateError(
      'Baseline serialization differs from retained source bytes',
    );
  }
  var captures = 0;
  Object? rewrite(Object? value, {required bool originalEncoding}) {
    if (value is Map) {
      final result = <String, dynamic>{
        for (final entry in value.entries)
          entry.key as String: rewrite(
            entry.value,
            originalEncoding: originalEncoding,
          ),
      };
      if (result.containsKey('bytes') &&
          result.containsKey('sha256') &&
          (result.containsKey('base64') || result.containsKey('utf8'))) {
        final bytes = decodeS24LiteRtCapture(result);
        if (!originalEncoding) captures++;
        result.remove('base64');
        result.remove('utf8');
        if (originalEncoding) {
          result['base64'] = base64Encode(bytes);
        } else {
          result.addAll(encodeS24LiteRtCapture(bytes));
        }
      }
      return result;
    }
    if (value is List) {
      return value
          .map((v) => rewrite(v, originalEncoding: originalEncoding))
          .toList();
    }
    return value;
  }

  final converted = rewrite(rows, originalEncoding: false) as List;
  if (!equal(rows, rewrite(converted, originalEncoding: true))) {
    throw StateError('A raw capture or event changed during encoding replay');
  }
  final encoded = utf8.encode('${converted.map(jsonEncode).join('\n')}\n');
  output.createSync();
  File('${output.path}/derived-encoding-only.jsonl').writeAsBytesSync(encoded);
  final report = {
    'schema': 's24.capture-encoding-analysis.v1',
    'source_sha256': sha256.convert(raw).toString(),
    'source_bytes': raw.length,
    'source_events': rows.length,
    'decoded_capture_occurrences': captures,
    'baseline_serialization_byte_identical': true,
    'all_original_events_and_capture_bytes_size_SHA_preserved': true,
    'derived_bytes': encoded.length,
    'derived_sha256': sha256.convert(encoded).toString(),
    'journal_limit_bytes': 16777216,
    'old_representation_exceeds_original_limit': raw.length > 16777216,
    'derived_representation_fits_original_limit': encoded.length <= 16777216,
    'saved_bytes': raw.length - encoded.length,
    'runtime_completion_or_qualification_claim': false,
    'source_journal_modified': false,
  };
  File(
    '${output.path}/analysis.json',
  ).writeAsStringSync('${jsonEncode(report)}\n');
  stdout.writeln(jsonEncode(report));
}
