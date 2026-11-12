import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/platform/io/model_download_manager_io.dart';

/// Waits for the file `<go file>` to exist, runs `clear()` on `<cache root>`
/// with a fresh [DefaultModelDownloadManager] and prints one JSON line with
/// the number of entries it reported in use.
///
/// Usage: `dart model_cache_clear_child.dart <cache root> <go file>`
Future<void> main(List<String> args) async {
  final manager = DefaultModelDownloadManager(defaultCacheDirectory: args[0]);
  stdout.writeln(jsonEncode(<String, Object?>{'event': 'ready'}));
  while (!File(args[1]).existsSync()) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  var inUse = 0;
  final errors = <String>[];
  try {
    await manager.clear();
  } on ModelCacheEntryInUseException catch (error) {
    inUse = error.entryDirectories.length;
  } on Object catch (error) {
    errors.add('$error');
  }
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'event': 'done',
      'inUse': inUse,
      'errors': errors,
    }),
  );
}
