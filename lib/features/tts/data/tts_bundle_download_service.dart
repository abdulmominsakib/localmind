import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/downloads/download_engine.dart';
import '../../../core/downloads/download_task.dart';
import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';
import 'kokoro_tts_model.dart';
import 'melo_tts_model.dart';
import 'sherpa_bundle_downloader.dart';
import 'tts_bundle.dart';

/// Downloads and publishes sherpa-onnx Chinese TTS bundles (Melo, Kokoro)
/// through the shared download engine, so 100-170 MB archives get the same
/// resume/pause/queue/OS-background semantics as GGUF imports. The
/// registered post-transfer hook extracts the tar.bz2 into
/// `tts_models/<engine>/<bundle>/` and validates it before the task is
/// allowed to complete; the archive itself is scratch and deleted on success.
class TtsBundleDownloadService {
  TtsBundleDownloadService({required DownloadEngine engine}) : _engine = engine {
    engine.registerPostTransfer(_handleTtsBundleTask);
  }

  final DownloadEngine _engine;

  final List<TtsBundleDescriptor> descriptors = const [
    MeloTtsModel.instance,
    KokoroTtsModel.instance,
  ];

  TtsBundleDescriptor? descriptorFor(EngineId engine) {
    for (final descriptor in descriptors) {
      if (descriptor.engine == engine) return descriptor;
    }
    return null;
  }

  TtsBundleDescriptor? _descriptorForGroup(String groupId) {
    for (final descriptor in descriptors) {
      if (_groupIdFor(descriptor) == groupId) return descriptor;
    }
    return null;
  }

  String _groupIdFor(TtsBundleDescriptor descriptor) =>
      'tts-${descriptor.bundleDirName}';

  /// Scratch directory for in-flight archives. Kept outside the engine's
  /// work directory so its orphan cleanup never touches archives whose tasks
  /// are merely paused; the hook deletes archives on success and
  /// [_clearArchiveLineage] on explicit cancel/delete.
  Future<Directory> _archiveDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory('${supportDir.path}/tts_bundle_archives');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> engineDirFor(TtsBundleDescriptor descriptor) async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory('${supportDir.path}/tts_models/${descriptor.engine.name}');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> bundleDirFor(TtsBundleDescriptor descriptor) async {
    final engineDir = await engineDirFor(descriptor);
    return Directory('${engineDir.path}/${descriptor.bundleDirName}');
  }

  /// Enqueues the archive download. Fails with [StateError] while a
  /// non-failed task for the same bundle already exists (engine dedup).
  Future<void> enqueue(TtsBundleDescriptor descriptor) async {
    final archiveDir = await _archiveDir();
    final finalPath = '${archiveDir.path}/${descriptor.bundleDirName}.tar.bz2';
    await _engine.enqueue(
      kind: DownloadTaskKind.ttsBundle,
      groupId: _groupIdFor(descriptor),
      url: descriptor.tarballUrl,
      finalPath: finalPath,
      partPath: '$finalPath.part',
    );
  }

  /// The live engine task for [descriptor], if any (any state).
  Future<DownloadTask?> taskFor(TtsBundleDescriptor descriptor) async {
    await _engine.ready;
    final groupId = _groupIdFor(descriptor);
    for (final task in _engine.tasks) {
      if (task.kind == DownloadTaskKind.ttsBundle && task.groupId == groupId) {
        return task;
      }
    }
    return null;
  }

  Future<void> cancel(TtsBundleDescriptor descriptor) async {
    final task = await taskFor(descriptor);
    if (task == null) return;
    if (!task.state.isTerminalState) {
      await _engine.cancel(task.id);
    }
    await _clearArchiveLineage(descriptor);
  }

  Future<bool> isDownloaded(TtsBundleDescriptor descriptor) async {
    final bundleDir = await bundleDirFor(descriptor);
    for (final fileName in descriptor.requiredFileNames) {
      final file = File('${bundleDir.path}/$fileName');
      if (!await file.exists() || await file.length() == 0) {
        return false;
      }
    }
    for (final dirName in descriptor.requiredDirNames) {
      if (!await Directory('${bundleDir.path}/$dirName').exists()) {
        return false;
      }
    }
    return true;
  }

  Future<void> deleteBundle(TtsBundleDescriptor descriptor) async {
    final task = await taskFor(descriptor);
    if (task != null && !task.state.isTerminalState) {
      await _engine.cancel(task.id);
    }
    await deleteDirectoryIfExists(await bundleDirFor(descriptor));
    await _clearArchiveLineage(descriptor);
    Log.info('TTS bundle ${descriptor.bundleDirName} deleted');
  }

  /// Absolute path of an extracted bundle file, or null when missing/empty.
  Future<String?> filePath(
    TtsBundleDescriptor descriptor,
    String fileName,
  ) async {
    final file = File('${(await bundleDirFor(descriptor)).path}/$fileName');
    if (await file.exists() && await file.length() > 0) return file.path;
    return null;
  }

  /// Absolute path of an extracted bundle directory (existence verified).
  Future<String?> dirPath(
    TtsBundleDescriptor descriptor,
    String dirName,
  ) async {
    final dir = Directory('${(await bundleDirFor(descriptor)).path}/$dirName');
    if (await dir.exists()) return dir.path;
    return null;
  }

  /// Comma-joined absolute paths of the rule FST files actually present —
  /// the `ruleFsts` argument for the native config.
  Future<String> ruleFstsArg(TtsBundleDescriptor descriptor) async {
    final bundleDir = (await bundleDirFor(descriptor)).path;
    final paths = <String>[];
    for (final fileName in descriptor.ruleFstFileNames) {
      final file = File('$bundleDir/$fileName');
      if (await file.exists()) paths.add(file.path);
    }
    return paths.join(',');
  }

  /// Comma-joined absolute paths for a fixed file-name list (Kokoro's
  /// per-language lexicons; order matters to the native config).
  Future<String> joinedFilesArg(
    TtsBundleDescriptor descriptor,
    List<String> fileNames,
  ) async {
    final bundleDir = (await bundleDirFor(descriptor)).path;
    return fileNames.map((name) => '$bundleDir/$name').join(',');
  }

  Future<void> _handleTtsBundleTask(DownloadTask task) async {
    if (task.kind != DownloadTaskKind.ttsBundle) return;
    final descriptor = _descriptorForGroup(task.groupId);
    if (descriptor == null) return;

    final archive = File(task.partPath);
    try {
      await extractTarBz2(
        archivePath: archive.path,
        targetDir: await engineDirFor(descriptor),
      );
      if (!await isDownloaded(descriptor)) {
        throw StateError(
          'Extracted TTS bundle is incomplete: ${descriptor.bundleDirName}. '
          'Delete the voice and download it again.',
        );
      }
      if (await archive.exists()) {
        await archive.delete();
      }
      Log.info('TTS bundle ${descriptor.bundleDirName} published');
    } catch (e) {
      // Keep the archive (retryable bytes) but drop the half-extracted
      // bundle so a retry starts extraction from a clean slate.
      await deleteDirectoryIfExists(await bundleDirFor(descriptor));
      rethrow;
    }
  }

  Future<void> _clearArchiveLineage(TtsBundleDescriptor descriptor) async {
    final archiveDir = await _archiveDir();
    final base = '${archiveDir.path}/${descriptor.bundleDirName}.tar.bz2';
    for (final path in [base, '$base.part', '$base.part.json']) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}

extension on DownloadTaskState {
  bool get isTerminalState =>
      this == DownloadTaskState.completed ||
      this == DownloadTaskState.failed ||
      this == DownloadTaskState.canceled;
}
