import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

Future<int> directorySize(Directory dir) async {
  var total = 0;
  if (!await dir.exists()) {
    return total;
  }

  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      total += await entity.length();
    }
  }
  return total;
}

Future<void> extractTarBz2({
  required String archivePath,
  required Directory targetDir,
}) async {
  await Isolate.run(() => _extractTarBz2Sync(archivePath, targetDir.path));
}

/// Extracts into a staging folder beside [targetDirPath] and moves each
/// top-level entry into place only once every file is written, so a full
/// disk or a killed app never leaves a half-written model that looks
/// installed.
void _extractTarBz2Sync(String archivePath, String targetDirPath) {
  final archiveBytes = File(archivePath).readAsBytesSync();
  final tarBytes = BZip2Decoder().decodeBytes(archiveBytes);
  final archive = TarDecoder().decodeBytes(tarBytes);

  final targetDir = Directory(targetDirPath)..createSync(recursive: true);
  // Staging left by an extraction the app was killed in.
  for (final entity in targetDir.listSync(followLinks: false)) {
    if (entity is Directory &&
        p.basename(entity.path).startsWith('.extracting-')) {
      entity.deleteSync(recursive: true);
    }
  }
  final stagingDir = targetDir.createTempSync('.extracting-');
  try {
    extractArchiveInto(archive, stagingDir.path);
    for (final entity in stagingDir.listSync(followLinks: false)) {
      final destination = p.join(targetDirPath, p.basename(entity.path));
      final existing = FileSystemEntity.typeSync(
        destination,
        followLinks: false,
      );
      if (existing == FileSystemEntityType.directory) {
        Directory(destination).deleteSync(recursive: true);
      } else if (existing != FileSystemEntityType.notFound) {
        File(destination).deleteSync();
      }
      entity.renameSync(destination);
    }
  } finally {
    if (stagingDir.existsSync()) stagingDir.deleteSync(recursive: true);
  }
}

@visibleForTesting
void extractArchiveInto(Archive archive, String targetDirPath) {
  final normalizedTargetDir = p.normalize(targetDirPath);

  for (final file in archive) {
    final relativePath = file.name;
    if (relativePath.isEmpty) continue;

    final outputPath = p.normalize(p.join(targetDirPath, relativePath));
    // Reject any entry whose resolved path would land outside the target
    // directory (e.g. a `../` traversal sequence in the archive entry name)
    // rather than trusting the archive's own file names.
    if (outputPath != normalizedTargetDir &&
        !p.isWithin(normalizedTargetDir, outputPath)) {
      continue;
    }

    if (file.isFile) {
      final outputFile = File(outputPath);
      outputFile.createSync(recursive: true);
      outputFile.writeAsBytesSync(file.content as List<int>, flush: true);
    } else {
      Directory(outputPath).createSync(recursive: true);
    }
  }
}

/// Synchronous [extractTarBz2] for tests.
@visibleForTesting
void extractTarBz2Sync(String archivePath, String targetDirPath) =>
    _extractTarBz2Sync(archivePath, targetDirPath);

Future<void> deleteDirectoryIfExists(Directory dir) async {
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}
