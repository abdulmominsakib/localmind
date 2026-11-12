import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// File name suffix of the LiteRT-LM GPU program cache.
const String liteRtLmProgramCacheSuffix = '_mldrift_program_cache.bin';

/// File name suffix of the LiteRT-LM GPU weight cache.
const String liteRtLmGpuWeightCacheSuffix = '_mldrift_weight_cache.bin';

/// Cache directory value that makes the LiteRT-LM runtime keep no cache.
const String liteRtLmNoCacheDirectory = ':nocache';

/// File name prefix of the files a [LiteRtLmCacheLease] keeps in a cache
/// directory.
const String liteRtLmCacheLeasePrefix = '.llamadart_litert_lm_lease_';

const String _leaseLockSuffix = '.lock';

const String _leaseStagingSuffix = '.tmp';

/// Age after which a `.lock` or `.tmp` file without a held lock is left over
/// from a process that ended, rather than one a lease is being taken with.
const Duration _orphanedLeaseFileAge = Duration(hours: 1);

final RegExp _leaseName = RegExp(
  '^${RegExp.escape(liteRtLmCacheLeasePrefix)}([0-9]{1,10})_[0-9a-f]{16}'
  '(${RegExp.escape(_leaseLockSuffix)}|'
  '${RegExp.escape(_leaseStagingSuffix)})?\$',
);

typedef _ProgramCache = ({File file, String name, int size, DateTime modified});

/// Marks the GPU program caches of one model file in a cache directory as in
/// use, so [pruneLiteRtLmProgramCaches] in this or another process leaves
/// them alone until [release].
///
/// A lease is two files in the directory: one holding the model file name the
/// runtime names its caches after, and a `.lock` file whose lock the holder
/// keeps. A lease of another process counts while that lock is held, so the
/// lease of a process that ended stops protecting anything. POSIX record
/// locks belong to the process and are dropped when any of its descriptors
/// for the file closes, so the lock files of this process are never opened
/// again here; its leases count until released.
final class LiteRtLmCacheLease {
  LiteRtLmCacheLease._(this.path, this._lock);

  /// Path of the lease file that names the model file.
  final String path;

  final RandomAccessFile _lock;
  bool _released = false;

  /// Takes a lease on the caches of [modelName] in [directory].
  ///
  /// Throws [FileSystemException] when the lease files cannot be written.
  static LiteRtLmCacheLease acquire(String directory, String modelName) {
    final random = Random.secure();
    final token = [
      for (var i = 0; i < 8; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    final path = p.join(directory, '$liteRtLmCacheLeasePrefix${pid}_$token');
    final lockFile = File('$path$_leaseLockSuffix');
    final staged = File('$path$_leaseStagingSuffix');
    final lock = lockFile.openSync(mode: FileMode.writeOnly);
    try {
      lock.lockSync(FileLock.exclusive);
      // The name file appears only once the lock is held and the name is
      // complete, so a pruner never takes a lease being created for one of a
      // process that ended.
      staged.writeAsStringSync(modelName, flush: true);
      staged.renameSync(path);
    } catch (_) {
      lock.closeSync();
      _deleteQuietly(lockFile);
      _deleteQuietly(staged);
      rethrow;
    }
    return LiteRtLmCacheLease._(path, lock);
  }

  /// Releases the lease and deletes its files. Calling it again does nothing.
  void release() {
    if (_released) return;
    _released = true;
    _deleteQuietly(File(path));
    try {
      _lock.closeSync();
    } on FileSystemException {
      // The descriptor is unusable either way.
    }
    _deleteQuietly(File('$path$_leaseLockSuffix'));
  }
}

void _deleteQuietly(File file) {
  try {
    file.deleteSync();
  } on FileSystemException {
    // Already gone, or left for a later prune to remove.
  }
}

/// Deletes LiteRT-LM GPU program cache files in [directory] until their total
/// size is at most [maxBytes].
///
/// Only regular files directly inside [directory] whose name ends with
/// [liteRtLmProgramCacheSuffix] are considered; links are skipped. Files of a
/// model with a [LiteRtLmCacheLease] in [directory], other than [ownLease],
/// are neither deleted nor counted. Files larger than [maxBytes] on their own
/// are deleted first, then the least recently modified ones until the rest
/// fit. Leases of processes that ended are removed, as are lease files they
/// left behind for more than an hour.
///
/// Each deletion is reported through [onDeleted] with the file path and its
/// size in bytes. File system errors are reported through [onError] and never
/// thrown. Nothing is deleted when a lease cannot be read, since the files it
/// protects are then unknown.
void pruneLiteRtLmProgramCaches(
  String directory,
  int maxBytes, {
  LiteRtLmCacheLease? ownLease,
  void Function(String path, int bytes)? onDeleted,
  void Function(String path, Object error)? onError,
}) {
  final List<FileSystemEntity> entries;
  try {
    final dir = Directory(directory);
    if (!dir.existsSync()) {
      return;
    }
    entries = dir.listSync(followLinks: false);
  } on FileSystemException catch (error) {
    onError?.call(directory, error);
    return;
  }

  // The directory may be spelled with trailing separators the listing drops.
  final ownLeaseName = ownLease == null ? null : p.basename(ownLease.path);
  final leasedModels = <String>[];
  final caches = <_ProgramCache>[];
  for (final entry in entries) {
    if (entry is! File) continue;
    final name = entry.uri.pathSegments.last;
    final lease = _leaseName.firstMatch(name);
    if (lease != null) {
      final ofThisProcess = int.parse(lease.group(1)!) == pid;
      final suffix = lease.group(2);
      if (suffix != null) {
        if (!ofThisProcess) _deleteOrphanedLeaseFile(entry, suffix);
        continue;
      }
      if (name == ownLeaseName) continue;
      if (!ofThisProcess && !_isLeaseHeld(entry.path)) {
        _deleteQuietly(entry);
        _deleteQuietly(File('${entry.path}$_leaseLockSuffix'));
        continue;
      }
      try {
        leasedModels.add(entry.readAsStringSync());
      } on PathNotFoundException {
        // Released after the listing.
      } on FileSystemException catch (error) {
        onError?.call(entry.path, error);
        return;
      }
      continue;
    }
    if (!name.endsWith(liteRtLmProgramCacheSuffix)) continue;
    try {
      final stat = entry.statSync();
      if (stat.type != FileSystemEntityType.file) continue;
      caches.add((
        file: entry,
        name: name,
        size: stat.size,
        modified: stat.modified,
      ));
    } on FileSystemException catch (error) {
      onError?.call(entry.path, error);
    }
  }

  bool isLeased(String name) => leasedModels.any(
    (model) =>
        model.isNotEmpty &&
        name.length > model.length &&
        name.startsWith(model) &&
        (name[model.length] == '_' || name[model.length] == '.'),
  );

  final candidates = [
    for (final cache in caches)
      if (!isLeased(cache.name)) cache,
  ]..sort((a, b) => a.modified.compareTo(b.modified));
  var total = candidates.fold<int>(0, (sum, cache) => sum + cache.size);
  for (final cache in [
    ...candidates.where((cache) => cache.size > maxBytes),
    ...candidates.where((cache) => cache.size <= maxBytes),
  ]) {
    if (total <= maxBytes) break;
    if (cache.size == 0) continue;
    // A file that cannot be deleted no longer counts, so its failure does
    // not cost every other cache in the directory.
    total -= cache.size;
    try {
      cache.file.deleteSync();
      onDeleted?.call(cache.file.path, cache.size);
    } on PathNotFoundException {
      // Deleted by another pruner after the listing.
    } on FileSystemException catch (error) {
      onError?.call(cache.file.path, error);
    }
  }
}

/// Deletes [file], the [suffix] file of a lease of another process, when it
/// is old and no process holds the lock of its lease.
///
/// A `.lock` file exists for a moment before its holder locks it, so a young
/// one is kept.
void _deleteOrphanedLeaseFile(File file, String suffix) {
  final leasePath = file.path.substring(0, file.path.length - suffix.length);
  try {
    final age = DateTime.now().difference(file.statSync().modified);
    if (age < _orphanedLeaseFileAge) return;
  } on FileSystemException {
    return;
  }
  if (!_isLeaseHeld(leasePath)) _deleteQuietly(file);
}

/// Whether a process holds the lock of the lease at [leasePath].
///
/// A lock file that cannot be opened counts as held unless it is missing,
/// since the files a lease protects must never be deleted in error.
///
/// Never call this for a lease of this process: closing the descriptor would
/// drop the lock its holder keeps.
bool _isLeaseHeld(String leasePath) {
  final RandomAccessFile lock;
  try {
    lock = File('$leasePath$_leaseLockSuffix').openSync();
  } on PathNotFoundException {
    return false;
  } on FileSystemException {
    return true;
  }
  try {
    lock.lockSync(FileLock.shared);
    lock.unlockSync();
    return false;
  } on FileSystemException {
    return true;
  } finally {
    lock.closeSync();
  }
}
