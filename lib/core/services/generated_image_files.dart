import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../storage/entities.dart';
import '../../objectbox.g.dart';

class GeneratedImageFiles {
  GeneratedImageFiles(Directory appDirectory)
    : directory = Directory(p.join(appDirectory.path, 'attachments'));

  final Directory directory;

  static final _generatedName = RegExp(
    r'^(?:[A-Za-z0-9_-]+-)?generated-image-[a-fA-F0-9-]+\.(?:png|jpg|webp)$',
  );

  static bool isStoredPath(String path) =>
      p.isAbsolute(path) &&
      p.basename(p.dirname(path)) == 'attachments' &&
      _generatedName.hasMatch(p.basename(path));

  /// App updates and restores can relocate the sandbox's Documents directory.
  /// The generated filename stays stable when the OS moves the files.
  String resolvePath(String path) =>
      isStoredPath(path) ? p.join(directory.path, p.basename(path)) : path;

  Future<File?> write({
    required String messageId,
    required Uint8List bytes,
    required String extension,
    required bool Function() isCancelled,
  }) async {
    await directory.create(recursive: true);
    final staging = await directory.createTemp('.generated-image-');
    File? result;
    try {
      if (isCancelled()) return null;
      final pending = File(p.join(staging.path, 'image'));
      await pending.writeAsBytes(bytes, flush: true);
      if (isCancelled()) return null;
      result = await pending.rename(
        p.join(directory.path, 'generated-image-$messageId.$extension'),
      );
      if (isCancelled()) {
        await discard(result);
        return null;
      }
      return result;
    } finally {
      try {
        await staging.delete(recursive: true);
      } on FileSystemException {
        // The finalized file, if any, lives outside the staging directory.
      }
    }
  }

  static Future<void> discard(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // A missing file or failed cleanup should not mask the request result.
    }
  }

  static Future<void> prune(
    Box<MessageEntity> box,
    Iterable<String> paths,
  ) async {
    final generated = paths.where(isStoredPath).toSet();
    if (generated.isEmpty) return;
    try {
      final appDirectory = await getApplicationDocumentsDirectory();
      GeneratedImageFiles(appDirectory).removeUnreferenced(box, generated);
    } catch (_) {
      // Deletion of a database row should succeed even if a file is unavailable.
    }
  }

  /// Remove only generated files with no remaining message references,
  /// including inactive variants and branches.
  void removeUnreferenced(Box<MessageEntity> box, Iterable<String> paths) {
    final candidates = paths.where(isStoredPath).map(resolvePath).toSet();
    if (candidates.isEmpty) return;
    final query = box
        .query(MessageEntity_.attachmentPathsJson.notNull())
        .build();
    try {
      for (final entity in query.find()) {
        candidates.removeAll(
          (entity.toDomain().attachmentPaths ?? const <String>[]).map(
            resolvePath,
          ),
        );
        if (candidates.isEmpty) return;
      }
      for (final path in candidates) {
        try {
          File(path).deleteSync();
        } on FileSystemException {
          // A file can already be absent after restore or manual deletion.
        }
      }
    } finally {
      query.close();
    }
  }
}
