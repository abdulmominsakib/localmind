import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/src/core/models/model_source.dart';
import 'package:llamadart/src/platform/io/model_download_manager_io.dart';

/// Downloads `<url>` as `<file name>` into `<cache root>` with a fresh
/// [DefaultModelDownloadManager] and prints one JSON line with the returned
/// entry's byte count and the SHA-256 of its file at the moment it returned.
///
/// Usage: `dart model_cache_download_child.dart <cache root> <url> <file name>`
Future<void> main(List<String> args) async {
  final manager = DefaultModelDownloadManager(defaultCacheDirectory: args[0]);
  final source = ModelSource.url(Uri.parse(args[1]), fileName: args[2]);
  stdout.writeln(jsonEncode(<String, Object?>{'event': 'started'}));
  final entry = await manager.ensureModel(source);
  final bytes = await File(entry.filePath).readAsBytes();
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'event': 'done',
      'bytes': entry.bytes,
      'fileBytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
    }),
  );
}
