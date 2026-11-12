/// Serializes complete model-free transport fixtures with the actual Dart codec.
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart_validation/src/s24_litert_capture.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3 ||
      !['base64', 'compact'].contains(args[1]) ||
      !['lf', 'crlf'].contains(args[2])) {
    throw ArgumentError('Expected codepoint, base64/compact and lf/crlf');
  }
  final point = int.parse(args[0]);
  if (![0x85, 0x2028, 0x2029].contains(point)) {
    throw ArgumentError('Expected a Unicode JSONL framing regression fixture');
  }
  final rows = jsonDecode(await stdin.transform(utf8.decoder).join()) as List;
  final observation =
      rows.firstWhere((row) => row['event'] == 'public_observation') as Map;
  final raw = utf8.encode('native ${String.fromCharCode(point)} log\n');
  (observation['mappings'] as Map)['capture'] = encodeS24LiteRtCapture(
    raw,
    allowUtf8: args[1] == 'compact',
  );
  final ending = args[2] == 'lf' ? '\n' : '\r\n';
  for (final row in rows) {
    stdout.write('${jsonEncode(row)}$ending');
  }
}
