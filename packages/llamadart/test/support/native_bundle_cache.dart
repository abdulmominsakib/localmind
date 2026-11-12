import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:llamadart/src/hook/native_extraction_marker.dart';
import 'package:path/path.dart' as path;

/// Makes [extractedDir], a hook cache `<tag>/<bundle>/extracted` directory a
/// test filled with fake libraries, one the hook reuses: writes the release
/// archive beside it, holding the same files, and the extraction marker.
Future<void> markExtractedBundle(Directory extractedDir) async {
  final cacheDir = extractedDir.parent;
  final bundle = path.basename(cacheDir.path);
  final tag = path.basename(cacheDir.parent.path);
  final archive = Archive();
  for (final entity in extractedDir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final bytes = entity.readAsBytesSync();
    archive.addFile(
      ArchiveFile(
        path.posix.joinAll(
          path.split(path.relative(entity.path, from: extractedDir.path)),
        ),
        bytes.length,
        bytes,
      ),
    );
  }
  final archiveBytes = GZipEncoder().encode(TarEncoder().encode(archive));
  final archiveFile = File(
    path.join(cacheDir.path, 'llamadart-native-$bundle-$tag.tar.gz'),
  );
  await archiveFile.writeAsBytes(archiveBytes);
  await writeNativeExtractionMarker(
    extractedDir: extractedDir,
    archive: archiveFile,
    archiveSha256: sha256.convert(archiveBytes).toString(),
  );
}
