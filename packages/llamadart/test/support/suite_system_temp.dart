import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

/// Name of the cache directory LiteRT-LM services create in the system temp
/// directory when `ModelParams.liteRtLmCacheDir` is unset.
const String liteRtLmTempCacheDirectoryName = 'llamadart_litert_lm';

/// Points [Directory.systemTemp] of this isolate at a directory the suite
/// owns, from `setUpAll` to `tearDownAll`, and returns a getter for it.
///
/// LiteRT-LM services prune the program caches of their default cache
/// directory in the system temp directory, which apps share; a suite that
/// loads models with no cache directory must never reach the real one. After
/// the suite, the real directory must still hold every file it held before.
/// Isolates the suite spawns keep the real system temp directory.
Directory Function() useSuiteSystemTemp() {
  final realCacheRoot = Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    '$liteRtLmTempCacheDirectoryName',
  );
  late Directory root;
  late Set<String> realCacheFiles;
  IOOverrides? previous;

  setUpAll(() {
    realCacheFiles = _fileNames(realCacheRoot);
    root = Directory.systemTemp.createTempSync('llamadart_suite_temp_');
    // The root zone sees only the global overrides, not those of a zone
    // the suite runs in, which must not become global.
    previous = Zone.root.run(() => IOOverrides.current);
    IOOverrides.global = _SystemTempOverrides(root);
  });

  tearDownAll(() {
    IOOverrides.global = previous;
    expect(
      realCacheFiles.difference(_fileNames(realCacheRoot)),
      isEmpty,
      reason: 'files deleted from ${realCacheRoot.path}',
    );
    deleteSuiteRoot(root);
  });

  return () => root;
}

/// Deletes [root], except on Windows the XNNPack caches that LiteRT-LM keeps
/// open after its engines are disposed, until the process exits: those and
/// [root] are left behind. Any other undeletable file throws.
///
/// [isWindows] and [delete] replace the host checks in tests.
void deleteSuiteRoot(
  Directory root, {
  bool? isWindows,
  void Function(FileSystemEntity entity) delete = _deleteRecursively,
}) {
  try {
    delete(root);
  } on FileSystemException {
    if (!(isWindows ?? Platform.isWindows)) rethrow;
    final undeletable = <String>[];
    for (final file
        in root
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()) {
      try {
        delete(file);
      } on FileSystemException {
        if (!file.path.endsWith('.xnnpack_cache')) undeletable.add(file.path);
      }
    }
    if (undeletable.isNotEmpty) rethrow;
  }
}

void _deleteRecursively(FileSystemEntity entity) =>
    entity.deleteSync(recursive: true);

Set<String> _fileNames(Directory dir) {
  if (!dir.existsSync()) return <String>{};
  return {
    for (final entry in dir.listSync(followLinks: false))
      if (entry is File) entry.uri.pathSegments.last,
  };
}

final class _SystemTempOverrides extends IOOverrides {
  _SystemTempOverrides(this.root);

  final Directory root;

  @override
  Directory getSystemTempDirectory() => root;
}
