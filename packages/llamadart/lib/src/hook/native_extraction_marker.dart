/// The record `hook/build.dart` keeps beside a native bundle's `extracted/`
/// directory, so a later build reuses that directory only while it still holds
/// what the cached archive beside it extracted to.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'native_archive_digest.dart';

/// The marker of [extractedDir]: `extracted.json` beside `extracted/`, outside
/// the directory that is renamed into place.
File nativeExtractionMarkerFile(Directory extractedDir) =>
    File('${extractedDir.path}.json');

/// Records that [extractedDir] holds what [archive], whose verified SHA-256 is
/// [archiveSha256], extracted to: every file's relative path and size, and the
/// archive's digest, size and modification time.
Future<void> writeNativeExtractionMarker({
  required Directory extractedDir,
  required File archive,
  required String archiveSha256,
}) async {
  final stat = await archive.stat();
  final marker = nativeExtractionMarkerFile(extractedDir);
  final pending = File('${marker.path}.tmp');
  final record = jsonEncode({
    'archive': {
      'sha256': archiveSha256,
      'size': stat.size,
      'modified': stat.modified.millisecondsSinceEpoch,
    },
    'files': _extractedFiles(extractedDir),
  });
  try {
    await pending.writeAsString(record, flush: true);
    await pending.rename(marker.path);
  } on FileSystemException {
    try {
      await pending.delete();
    } on FileSystemException {
      // Best effort: the next write replaces a leftover .tmp.
    }
    rethrow;
  }
}

/// Whether the marker of [extractedDir] records an extraction of [archive]
/// and [extractedDir] still holds exactly the files it records.
///
/// An archive whose size and modification time match the marker is not
/// hashed again; one whose modification time differs must hash to the
/// recorded SHA-256, and then the marker takes the new modification time so
/// the next build does not hash it again.
Future<bool> nativeExtractionMatchesArchive({
  required Directory extractedDir,
  required File archive,
}) async {
  final Object? record;
  try {
    record = jsonDecode(
      await nativeExtractionMarkerFile(extractedDir).readAsString(),
    );
  } on FileSystemException {
    return false;
  } on FormatException {
    return false;
  }
  if (record case {
    'archive': {
      'sha256': final String sha256,
      'size': final int size,
      'modified': final int modified,
    },
    'files': final Map<String, Object?> files,
  }) {
    if (!archive.existsSync() ||
        !_sameFiles(files, _extractedFiles(extractedDir))) {
      return false;
    }
    final stat = await archive.stat();
    if (stat.size != size) return false;
    if (stat.modified.millisecondsSinceEpoch == modified) return true;
    if (await fileSha256(archive) != sha256) return false;
    try {
      await writeNativeExtractionMarker(
        extractedDir: extractedDir,
        archive: archive,
        archiveSha256: sha256,
      );
    } on FileSystemException {
      // A read-only or shared cache still reuses an extraction it verified.
    }
    return true;
  }
  return false;
}

/// Size of every file below [directory] by relative POSIX path, with `-1` for
/// a link, which extraction never creates.
Map<String, int> _extractedFiles(Directory directory) {
  if (!directory.existsSync()) return const {};
  final entries = <String, int>{
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    ))
      if (entity is! Directory)
        path.posix.joinAll(
          path.split(path.relative(entity.path, from: directory.path)),
        ): entity is File
            ? entity.lengthSync()
            : -1,
  };
  return {for (final key in entries.keys.toList()..sort()) key: entries[key]!};
}

bool _sameFiles(Map<String, Object?> recorded, Map<String, int> actual) =>
    recorded.length == actual.length &&
    actual.entries.every((entry) => recorded[entry.key] == entry.value);
