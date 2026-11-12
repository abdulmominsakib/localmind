import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../../core/exceptions.dart';
import '../../core/models/download/model_download_manager_base.dart';
import '../../core/models/model_load_options.dart';
import '../../core/models/model_source.dart';
import '../../core/models/model_target_file.dart';
import '../../core/url_redaction.dart';
import 'mobile_app_cache_directory.dart';
import 'model_cache_entry_lock.dart';
import 'windows_delete_refusal.dart';

const String _metadataFileName = 'metadata.json';
const String _lockDirectoryName = '.locks';
// Entry directory names end in `-<12 hex digits>`, so only a stray
// `_strayRemovalDirectoryName` directory has an entry lock file by this name.
const String _removalLockFileName = '.removal.lock';
const String _strayRemovalDirectoryName = '.removal';
const int _metadataSchemaVersion = 1;

/// Native file-backed package-managed model download manager.
class DefaultModelDownloadManager implements ModelDownloadManager {
  /// Creates a native model download/cache manager.
  ///
  /// When [defaultCacheDirectory] is omitted, the manager uses
  /// [globalCacheDirectory] if set, else the platform default:
  /// desktop/server platforms use the same per-user shared model cache as
  /// [DefaultModelDownloadManager.auto], and Android and iOS use
  /// `llamadart/models` in the app's cache directory (the one Flutter's
  /// `getApplicationCacheDirectory()` returns). The default is resolved the
  /// first time the manager needs it.
  DefaultModelDownloadManager({String? defaultCacheDirectory})
    : _explicitDefaultCacheDirectory = defaultCacheDirectory;

  /// Creates a manager using the recommended cache root for the current platform.
  ///
  /// Pass [cacheDirectory] to force a specific root on every platform,
  /// including an OS-granted mobile model library directory. Otherwise,
  /// desktop/server platforms use [globalCacheDirectory] when set, else
  /// [defaultSharedCacheDirectory] with [namespace], [environment], and
  /// [homeDirectory]. Android and iOS use, in order, their platform-specific
  /// app-private directory argument, [appPrivateCacheDirectory],
  /// [globalCacheDirectory], or `<namespace>/models` in the running app's
  /// cache directory. Only when that directory cannot be found (or [platform]
  /// is not the host) do they fall back to the temporary directory, with a
  /// one-time warning through `LlamaLogger`.
  ///
  /// Use [androidAppPrivateCacheDirectory] and [iosAppPrivateCacheDirectory]
  /// when an app resolves both platform directories up front and wants one
  /// branch-free `auto(...)` call. Use [appPrivateCacheDirectory] when a storage
  /// abstraction such as Flutter `path_provider` has already returned the
  /// current platform's app-private model directory.
  ///
  /// Throws [LlamaUnsupportedException] on web because browser caches are
  /// origin-scoped instead of file-backed, and on unknown platforms where no
  /// implicit cache root is known.
  factory DefaultModelDownloadManager.auto({
    String namespace = 'llamadart',
    String? cacheDirectory,
    String? appPrivateCacheDirectory,
    String? androidAppPrivateCacheDirectory,
    String? iosAppPrivateCacheDirectory,
    ModelCachePlatform? platform,
    Map<String, String>? environment,
    String? homeDirectory,
  }) {
    final explicitCacheDirectory = _nonEmpty(cacheDirectory);
    if (explicitCacheDirectory != null) {
      return DefaultModelDownloadManager(
        defaultCacheDirectory: explicitCacheDirectory,
      );
    }

    final effectivePlatform =
        platform ?? ModelCachePlatform.parse(Platform.operatingSystem);
    if (effectivePlatform.supportsImplicitSharedModelCache) {
      final globalCacheDirectory = _globalCacheDirectory();
      if (globalCacheDirectory != null) {
        return DefaultModelDownloadManager(
          defaultCacheDirectory: globalCacheDirectory,
        );
      }
      return DefaultModelDownloadManager.sharedCache(
        namespace: namespace,
        platform: effectivePlatform,
        environment: environment,
        homeDirectory: homeDirectory,
      );
    }

    if (effectivePlatform.isMobile) {
      return DefaultModelDownloadManager.appPrivate(
        cacheDirectory:
            _mobileAppPrivateCacheDirectory(
              effectivePlatform,
              appPrivateCacheDirectory: appPrivateCacheDirectory,
              androidAppPrivateCacheDirectory: androidAppPrivateCacheDirectory,
              iosAppPrivateCacheDirectory: iosAppPrivateCacheDirectory,
            ) ??
            _defaultImplicitCacheDirectoryFor(
              effectivePlatform,
              namespace: namespace,
            ),
      );
    }

    if (effectivePlatform == ModelCachePlatform.web) {
      throw LlamaUnsupportedException(
        'DefaultModelDownloadManager.auto cannot create a file-backed shared '
        'cache on web. Web model caches are origin-scoped browser/runtime '
        'caches.',
      );
    }

    throw LlamaUnsupportedException(
      'DefaultModelDownloadManager.auto cannot choose a model cache directory '
      'for ${effectivePlatform.name}. Pass cacheDirectory explicitly.',
    );
  }

  /// Creates a manager rooted at a per-user shared model cache.
  ///
  /// On desktop/server platforms this resolves to a conventional per-user cache
  /// directory. On Android and iOS no implicit cross-app shared folder is
  /// available: pass [cacheDirectory] after your app obtains an OS-supported
  /// shared/user-selected directory, or use [DefaultModelDownloadManager.appPrivate]
  /// for app-private mobile storage.
  ///
  /// When [cacheDirectory] is omitted, this uses [defaultSharedCacheDirectory].
  /// That means Linux resolves under `$XDG_CACHE_HOME` or `$HOME/.cache`, macOS
  /// resolves under `$HOME/Library/Caches`, and Windows resolves under
  /// `%LOCALAPPDATA%`, `%APPDATA%`, or `%USERPROFILE%\AppData\Local`.
  factory DefaultModelDownloadManager.sharedCache({
    String namespace = 'llamadart',
    String? cacheDirectory,
    ModelCachePlatform? platform,
    Map<String, String>? environment,
    String? homeDirectory,
  }) {
    return DefaultModelDownloadManager(
      defaultCacheDirectory:
          cacheDirectory ??
          defaultSharedCacheDirectory(
            namespace: namespace,
            platform: platform,
            environment: environment,
            homeDirectory: homeDirectory,
          ),
    );
  }

  /// Creates a manager rooted at an app-private model cache directory.
  ///
  /// Flutter apps typically pass an application cache directory for
  /// re-downloadable models, or an application-support directory when the app
  /// owns the platform backup/no-backup policy. This avoids cross-app storage
  /// claims on mobile while still deduping model downloads within the app.
  factory DefaultModelDownloadManager.appPrivate({
    required String cacheDirectory,
  }) {
    return DefaultModelDownloadManager(defaultCacheDirectory: cacheDirectory);
  }

  /// Creates a manager rooted at a user-selected model library directory.
  ///
  /// This is the intended Android cross-developer sharing shape: the user grants
  /// each app access to the same model library using platform APIs such as the
  /// Storage Access Framework. The returned manager is file-backed; apps that
  /// receive only content URIs must first bridge them to a local file path or a
  /// future file-descriptor-backed loader.
  factory DefaultModelDownloadManager.userSelected({
    required String cacheDirectory,
  }) {
    return DefaultModelDownloadManager(defaultCacheDirectory: cacheDirectory);
  }

  /// Creates a manager rooted at an app-group shared container directory.
  ///
  /// This supports iOS/macOS apps that are explicitly configured into the same
  /// App Group. It is not a cross-developer global model cache.
  factory DefaultModelDownloadManager.appGroup({
    required String cacheDirectory,
  }) {
    return DefaultModelDownloadManager(defaultCacheDirectory: cacheDirectory);
  }

  /// Cache root for every manager whose directory would otherwise be the
  /// platform default: the default constructor without
  /// `defaultCacheDirectory`, and [DefaultModelDownloadManager.auto] without
  /// an explicit or mobile directory. Engines build such a manager unless you
  /// pass one, so setting this once at startup moves every default model
  /// download, for example to Flutter's `getApplicationSupportDirectory()`.
  ///
  /// Set it before the first model load; a manager keeps the directory it
  /// resolved first. `null` (the default) or a blank value means the platform
  /// default. Like any static, it is per isolate: set it in each isolate that
  /// creates engines or managers.
  static String? globalCacheDirectory;

  final String? _explicitDefaultCacheDirectory;

  /// Default cache root used when [ModelLoadOptions.cacheDirectory] is absent.
  late final String defaultCacheDirectory =
      _explicitDefaultCacheDirectory ?? _defaultImplicitCacheDirectory();

  static final Map<String, Future<void>> _cacheLocks = <String, Future<void>>{};
  static final Map<String, Future<void>> _removalLocks =
      <String, Future<void>>{};

  /// Returns the default per-user shared model cache directory for desktop/CLI.
  ///
  /// The default [namespace] is `llamadart`, producing these roots:
  ///
  /// - Linux: `$XDG_CACHE_HOME/llamadart/models`, or
  ///   `$HOME/.cache/llamadart/models` when `XDG_CACHE_HOME` is unset.
  /// - macOS: `$HOME/Library/Caches/llamadart/models`.
  /// - Windows: `%LOCALAPPDATA%\llamadart\models`, then
  ///   `%APPDATA%\llamadart\models`, then
  ///   `%USERPROFILE%\AppData\Local\llamadart\models`.
  ///
  /// Android, iOS, web, and unknown platforms throw because `llamadart` cannot
  /// safely choose a cross-app shared folder without explicit platform grants.
  /// [environment], [homeDirectory], and [platform] are optional overrides for
  /// deterministic tests and custom embedders; omitted values use the current
  /// process platform and environment.
  static String defaultSharedCacheDirectory({
    String namespace = 'llamadart',
    ModelCachePlatform? platform,
    Map<String, String>? environment,
    String? homeDirectory,
  }) {
    final cacheNamespace = _validateCacheNamespace(namespace);
    final effectivePlatform =
        platform ?? ModelCachePlatform.parse(Platform.operatingSystem);
    final effectiveEnvironment = environment ?? Platform.environment;
    final effectiveHomeDirectory =
        homeDirectory ??
        _homeDirectoryFor(effectivePlatform, effectiveEnvironment);

    return _defaultSharedCacheDirectoryFor(
      platform: effectivePlatform,
      namespace: cacheNamespace,
      environment: effectiveEnvironment,
      homeDirectory: effectiveHomeDirectory,
    );
  }

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    _throwIfCancelled(options);
    if (source.isLocal || options.cachePolicy == ModelCachePolicy.noCache) {
      return _ensureModelUnlocked(source, options, onProgress);
    }

    final root = _rootDirectory(options.cacheDirectory);
    final cacheDir = _cacheDirectory(source, options);
    Future<void> checkDirectory() async {
      final type = await FileSystemEntity.type(
        cacheDir.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          await _cacheEntryDirectory(cacheDir, root) == null) {
        throw LlamaStateException(
          'Model cache entry must be a directory directly under its cache root.',
        );
      }
    }

    return _withCacheLock(_cacheLockKey(cacheDir), () async {
      await checkDirectory();
      if (options.cachePolicy == ModelCachePolicy.cacheOnly &&
          (await FileSystemEntity.type(
                    path.join(cacheDir.path, source.fileName),
                    followLinks: false,
                  ) !=
                  FileSystemEntityType.file ||
              !await File(
                path.join(cacheDir.path, source.fileName),
              ).exists())) {
        // A miss needs no lock directory, which a read-only cache root could
        // not hold. Checked after this isolate's earlier calls for the entry,
        // so a download they finish counts; reading an entry that appears
        // later without the entry lock would race its writer.
        throw LlamaStateException(
          'No cached model is available for ${_redactedSourceName(source)}.',
        );
      }
      return _withEntryLock(cacheDir, options, (locked) async {
        await checkDirectory();
        return _ensureModelUnlocked(
          source,
          options,
          onProgress,
          ownsPartFiles: locked,
        );
      });
    });
  }

  /// [ownsPartFiles] is true while this call holds the entry's cross-process
  /// lock, so no other process can be writing a part file of the entry.
  Future<ModelCacheEntry> _ensureModelUnlocked(
    ModelSource source,
    ModelLoadOptions options,
    ModelDownloadProgressCallback? onProgress, {
    bool ownsPartFiles = false,
  }) async {
    _throwIfCancelled(options);
    if (source.isLocal) {
      return _localEntry(source, options);
    }

    final cachePolicy = options.cachePolicy;
    final cacheDir = _cacheDirectory(source, options);
    final finalFile = File(path.join(cacheDir.path, source.fileName));
    final partFile = File('${finalFile.path}.part');
    final metadataFile = File(path.join(cacheDir.path, _metadataFileName));

    if (cachePolicy != ModelCachePolicy.refresh &&
        cachePolicy != ModelCachePolicy.noCache) {
      final cached = await _readCompletedEntry(
        source,
        metadataFile,
        finalFile,
        options,
      );
      if (cached != null) {
        return cached;
      }
      if (cachePolicy == ModelCachePolicy.cacheOnly) {
        throw LlamaStateException(
          'No cached model is available for ${_redactedSourceName(source)}.',
        );
      }
    }

    if (cachePolicy == ModelCachePolicy.noCache) {
      final transientDir = await _createTransientCacheDirectory(
        source,
        options,
      );
      final transientFile = File(path.join(transientDir.path, source.fileName));
      final transientPartFile = File('${transientFile.path}.part');
      try {
        final entry = await _download(
          source,
          options,
          transientFile,
          transientPartFile,
          onProgress,
        );
        await _writeMetadata(
          File(path.join(transientDir.path, _metadataFileName)),
          entry,
        );
        return entry;
      } catch (_) {
        if (await transientDir.exists()) {
          await transientDir.delete(recursive: true);
        }
        rethrow;
      }
    }

    await _createCacheDirectory(cacheDir);
    if (ownsPartFiles) {
      await _adoptOrphanedAttempts(cacheDir, finalFile, partFile);
    }
    // Each attempt writes its own file and renames it onto the final path
    // only when complete, so even without the entry lock no reader sees a
    // file another attempt is still writing. The shared part file is only a
    // resume point between attempts.
    final attemptFile = File('${finalFile.path}.${_newAttemptId()}.part');
    await _movePartFile(partFile, attemptFile);
    final ModelCacheEntry entry;
    try {
      entry = await _download(
        source,
        options,
        finalFile,
        attemptFile,
        onProgress,
      );
    } catch (_) {
      await _movePartFile(attemptFile, partFile);
      rethrow;
    }
    await _writeMetadata(metadataFile, entry);
    return entry;
  }

  Future<T> _withEntryLock<T>(
    Directory cacheDir,
    ModelLoadOptions options,
    Future<T> Function(bool locked) action,
  ) async {
    final lock = await _lockEntry(
      cacheDir,
      throwIfBusy: () => _throwIfCancelled(options),
    );
    try {
      return await action(lock != null);
    } finally {
      await lock?.release();
    }
  }

  /// Takes [cacheDir]'s cross-process entry lock, calling [throwIfBusy]
  /// whenever another holder has it, or returns null when the cache root
  /// cannot be locked.
  Future<ModelCacheEntryLock?> _lockEntry(
    Directory cacheDir, {
    required void Function() throwIfBusy,
  }) => _lockInCacheRoot(
    cacheDir.parent,
    '${path.basename(cacheDir.path)}.lock',
    throwIfBusy: throwIfBusy,
  );

  Future<ModelCacheEntryLock?> _lockInCacheRoot(
    Directory root,
    String lockFileName, {
    required void Function() throwIfBusy,
  }) async {
    // Lock files live outside the entry directories, which remove(), prune()
    // and clear() delete, and are never deleted themselves: a waiter that
    // opened a lock file before it was unlinked would take a lock that no
    // longer excludes a process that recreates the file.
    final lockDirectory = Directory(path.join(root.path, _lockDirectoryName));
    ModelCacheEntryLock? lock;
    try {
      await lockDirectory.create(recursive: true);
      lock = await modelCacheEntryLocker(
        path.join(lockDirectory.path, lockFileName),
        throwIfCancelled: throwIfBusy,
      );
    } on FileSystemException {
      lock = null;
    }
    if (lock == null) {
      warnModelCacheLockUnavailableOnce(root.path);
    }
    return lock;
  }

  /// Runs [action] holding [cacheDir]'s isolate and entry locks, without
  /// waiting for them: returns false, and does not run [action], while
  /// another caller in any isolate or process holds either.
  Future<bool> _tryWithEntryLocks(
    Directory cacheDir,
    Future<void> Function() action,
  ) async {
    final key = _cacheLockKey(cacheDir);
    if (_cacheLocks.containsKey(key)) {
      return false;
    }
    final current = Completer<void>();
    _cacheLocks[key] = current.future;
    try {
      final ModelCacheEntryLock? lock;
      try {
        lock = await _lockEntry(
          cacheDir,
          throwIfBusy: () => throw const _EntryBusy(),
        );
      } on _EntryBusy {
        return false;
      }
      try {
        await action();
      } finally {
        await lock?.release();
      }
      return true;
    } finally {
      if (identical(_cacheLocks[key], current.future)) {
        _cacheLocks.remove(key);
      }
      current.complete();
    }
  }

  /// Keeps the largest part file left by earlier attempts of [finalFile] as
  /// its resume point and deletes the rest, with orphaned metadata temp files.
  ///
  /// Call it only while holding the entry lock: without it another process
  /// may still be writing one of these files.
  Future<void> _adoptOrphanedAttempts(
    Directory cacheDir,
    File finalFile,
    File partFile,
  ) async {
    final fileName = RegExp.escape(path.basename(finalFile.path));
    final attemptPart = RegExp('^$fileName\\.[0-9a-f]{16}\\.part\$');
    final attemptPartMetadata = RegExp(
      '^$fileName\\.[0-9a-f]{16}\\.part\\.json\$',
    );
    final metadataTemp = RegExp(
      '^${RegExp.escape(_metadataFileName)}\\.[0-9a-f]{16}\\.tmp\$',
    );
    final parts = <File>[];
    final orphanedFiles = <File>[];
    await for (final entity in cacheDir.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final name = path.basename(entity.path);
      if (name == path.basename(partFile.path) || attemptPart.hasMatch(name)) {
        parts.add(entity);
      } else if (attemptPartMetadata.hasMatch(name) ||
          metadataTemp.hasMatch(name)) {
        orphanedFiles.add(entity);
      }
    }

    File? resumePoint;
    var resumeBytes = -1;
    for (final part in parts) {
      try {
        final bytes = await part.length();
        if (bytes > resumeBytes) {
          resumePoint = part;
          resumeBytes = bytes;
        }
      } on FileSystemException {
        continue;
      }
    }
    for (final part in parts) {
      if (part != resumePoint) {
        await _deleteIfExists(part);
      }
    }
    if (resumePoint == null) {
      await _deleteIfExists(_partMetadataFile(partFile));
    } else if (resumePoint.path != partFile.path) {
      await _movePartFile(resumePoint, partFile);
    }
    for (final file in orphanedFiles) {
      await _deleteIfExists(file);
    }
  }

  Future<T> _withCacheLock<T>(
    String key,
    Future<T> Function() action, {
    Map<String, Future<void>>? locks,
  }) async {
    final held = locks ?? _cacheLocks;
    final previous = held[key];
    final current = Completer<void>();
    held[key] = current.future;

    if (previous != null) {
      await previous;
    }

    try {
      return await action();
    } finally {
      if (identical(held[key], current.future)) {
        held.remove(key);
      }
      current.complete();
    }
  }

  /// Runs [action] as the only remover of [root] in any isolate or process.
  ///
  /// Removers hold an entry's locks only while deleting it, so they wait for
  /// each other: an entry lock another remover holds would otherwise read as
  /// in use. Downloads never take this lock, so a remover holding it and
  /// finding an entry lock busy knows a download or cache hit holds it.
  Future<T> _withRemovalLock<T>(Directory root, Future<T> Function() action) =>
      _withCacheLock(_cacheLockKey(root), () async {
        final lock = await _lockInCacheRoot(
          root,
          _removalLockFileName,
          throwIfBusy: () {},
        );
        try {
          return await action();
        } finally {
          await lock?.release();
        }
      }, locks: _removalLocks);

  @override
  Future<List<ModelCacheEntry>> list({String? cacheDirectory}) async => [
    for (final snapshot in await _listEntries(cacheDirectory: cacheDirectory))
      snapshot.entry,
  ];

  Future<List<_ManagedCacheEntry>> _listEntries({
    String? cacheDirectory,
  }) async {
    final root = _rootDirectory(cacheDirectory);
    if (!await root.exists()) {
      return <_ManagedCacheEntry>[];
    }
    final entries = <_ManagedCacheEntry>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final metadataFile = File(path.join(entity.path, _metadataFileName));
      try {
        final snapshot = await _readManagedEntry(metadataFile, root);
        if (snapshot != null) {
          entries.add(snapshot);
        }
      } catch (_) {
        // Ignore malformed cache entries so one corrupt metadata file does not
        // make cache inspection unusable.
      }
    }
    entries.sort((a, b) => b.entry.updatedAt.compareTo(a.entry.updatedAt));
    return entries;
  }

  @override
  Future<ModelCacheEntry?> get(
    String cacheKey, {
    String? cacheDirectory,
  }) async {
    final entries = <ModelCacheEntry>[];
    for (final metadataFile in await _candidateMetadataFiles(
      cacheKey,
      cacheDirectory: cacheDirectory,
    )) {
      try {
        final snapshot = await _readManagedEntry(
          metadataFile,
          metadataFile.parent.parent,
        );
        if (snapshot != null && snapshot.entry.cacheKey == cacheKey) {
          entries.add(snapshot.entry);
        }
      } catch (_) {
        // Ignore malformed candidates so a corrupt entry does not make cache
        // inspection unusable.
      }
    }
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries.isEmpty ? null : entries.first;
  }

  /// Removes the entries for [cacheKey] under [cacheDirectory].
  ///
  /// Throws [ModelCacheEntryInUseException], after removing the others, when
  /// an entry is in use: another isolate or process downloads or verifies it
  /// under its entry lock, or on Windows a process has its model file open or
  /// mapped. Removals from the same cache root take turns, so overlapping
  /// [remove], [prune] and [clear] calls do not report each other's entries,
  /// except across isolates or processes on a file system without file locks.
  ///
  /// A file the platform refuses to delete for good throws its
  /// [FileSystemException] and stops the call. On Windows that includes a
  /// read-only model file, which is not unlinked as it is on other platforms:
  /// clear its read-only attribute first. A [prune] that throws keeps the
  /// entries it already removed, but does not return them.
  @override
  Future<void> remove(String cacheKey, {String? cacheDirectory}) async {
    final inUse = <String>[];
    await _removeByCacheKey(
      cacheKey,
      cacheDirectory: cacheDirectory,
      inUse: inUse,
    );
    _throwIfInUse(inUse);
  }

  /// Removes every entry under [cacheDirectory] and keeps its `.locks`
  /// directory.
  ///
  /// Throws [ModelCacheEntryInUseException], after removing the others, when
  /// an entry is in use; see [remove].
  @override
  Future<void> clear({String? cacheDirectory}) async {
    final root = _rootDirectory(cacheDirectory);
    if (!await root.exists()) {
      return;
    }
    final inUse = <String>[];
    for (final entity in await root.list(followLinks: false).toList()) {
      final name = path.basename(entity.path);
      if (name == _lockDirectoryName) {
        continue;
      }
      if (entity is! Directory) {
        await _withRemovalLock(root, () async {
          if (await entity.exists()) {
            await entity.delete(recursive: true);
          }
        });
        continue;
      }
      final result = await _removeCacheDirectory(
        entity,
        cacheDirectory: cacheDirectory,
      );
      if (result == _Removal.inUse) {
        inUse.add(entity.path);
      }
    }
    _throwIfInUse(inUse);
  }

  void _throwIfInUse(List<String> entryDirectories) {
    if (entryDirectories.isEmpty) {
      return;
    }
    throw ModelCacheEntryInUseException(
      '${entryDirectories.length} model cache '
      '${entryDirectories.length == 1 ? 'entry is' : 'entries are'} in use '
      'and ${entryDirectories.length == 1 ? 'was' : 'were'} not removed.',
      entryDirectories: entryDirectories,
    );
  }

  /// Prunes entries under [cacheDirectory] and returns the removed ones.
  ///
  /// Skips an entry that is in use (see [remove]) or that was used after
  /// this call listed it.
  @override
  Future<List<ModelCacheEntry>> prune({
    Duration? maxAge,
    int? maxBytes,
    String? cacheDirectory,
  }) async {
    final entries = await _listEntries(cacheDirectory: cacheDirectory);
    final removed = await _removeStaleMetadataEntries(cacheDirectory);
    final now = DateTime.now().toUtc();

    for (final snapshot in entries) {
      final entry = snapshot.entry;
      if (maxAge != null && now.difference(entry.updatedAt.toUtc()) > maxAge) {
        if (await _removeEntry(snapshot, cacheDirectory: cacheDirectory)) {
          removed.add(entry);
        }
      }
    }

    if (maxBytes != null) {
      final remaining =
          (await _listEntries(cacheDirectory: cacheDirectory)).toList()
            ..sort((a, b) => a.entry.updatedAt.compareTo(b.entry.updatedAt));
      final sizes = <int>[
        for (final snapshot in remaining) await _entrySize(snapshot.entry),
      ];
      var total = sizes.fold(0, (sum, size) => sum + size);
      for (var i = 0; i < remaining.length && total > maxBytes; i += 1) {
        final snapshot = remaining[i];
        final entry = snapshot.entry;
        if (await _removeEntry(snapshot, cacheDirectory: cacheDirectory)) {
          removed.add(entry);
          total -= sizes[i];
        } else if (!await Directory(path.dirname(entry.filePath)).exists()) {
          // Another prune removed it, so its bytes no longer count.
          total -= sizes[i];
        }
      }
    }

    return removed;
  }

  Directory _cacheDirectory(ModelSource source, ModelLoadOptions options) {
    return Directory(
      path.join(
        options.cacheDirectory ?? defaultCacheDirectory,
        source.cacheDirectoryName,
      ),
    );
  }

  Directory _rootDirectory(String? cacheDirectory) {
    return Directory(cacheDirectory ?? defaultCacheDirectory);
  }

  Future<Directory> _resolvedRootDirectory(String? cacheDirectory) async {
    final root = _rootDirectory(cacheDirectory).absolute;
    try {
      return Directory(await root.resolveSymbolicLinks());
    } on FileSystemException {
      return root;
    }
  }

  // A path whose resolution is denied (errno 5) and whose type also reads as
  // `notFound` (for example a parent ACL denial) is walked past like a missing
  // one. The operation then fails later, as an access denial on create or
  // write, or a cache miss for cacheOnly; it never reports success.
  String _cacheLockKey(Directory cacheDirectory) {
    var ancestor = path.normalize(path.absolute(cacheDirectory.path));
    final missing = <String>[];
    try {
      while (true) {
        try {
          final resolved = Directory(ancestor).resolveSymbolicLinksSync();
          if (FileSystemEntity.typeSync(resolved, followLinks: false) ==
              FileSystemEntityType.directory) {
            return path.normalize(
              path.joinAll([resolved, ...missing.reversed]),
            );
          }
          // Let directory creation report a file occupying part of the root.
          missing.add(path.basename(ancestor));
          ancestor = path.dirname(ancestor);
        } on FileSystemException catch (error) {
          final missingPath =
              error.osError?.errorCode == 2 ||
              error.osError?.errorCode == 20 ||
              (Platform.isWindows &&
                  (error.osError?.errorCode == 3 ||
                      error.osError?.errorCode == 267)) ||
              _mayBeWindowsDeletePending(error);
          // A new cache root must keep its identity after it is created.
          // Resolve its existing ancestor instead of using alias spelling.
          if (!missingPath ||
              FileSystemEntity.typeSync(ancestor, followLinks: false) !=
                  FileSystemEntityType.notFound) {
            rethrow;
          }
          final parent = path.dirname(ancestor);
          if (path.equals(parent, ancestor)) {
            rethrow;
          }
          missing.add(path.basename(ancestor));
          ancestor = parent;
        }
      }
    } on FileSystemException {
      throw LlamaStateException(
        'Cannot resolve the model cache directory for locking.',
      );
    }
  }

  void _rejectUnsupportedLocalOptions(ModelLoadOptions options) {
    if (options.cachePolicy != ModelCachePolicy.preferCached) {
      throw LlamaUnsupportedException(
        'Local ModelSource.path loads do not use package-managed cache policies.',
      );
    }
    if (options.cacheDirectory != null) {
      throw LlamaUnsupportedException(
        'Local ModelSource.path loads do not use cacheDirectory.',
      );
    }
    if (options.bearerToken != null || options.headers.isNotEmpty) {
      throw LlamaUnsupportedException(
        'Local ModelSource.path loads do not use remote authentication headers.',
      );
    }
    if (!options.resume) {
      throw LlamaUnsupportedException(
        'Local ModelSource.path loads do not use download resume options.',
      );
    }
    if (options.maxRetries != ModelLoadOptions.defaults.maxRetries) {
      throw LlamaUnsupportedException(
        'Local ModelSource.path loads do not use download retry options.',
      );
    }
  }

  Future<List<File>> _candidateMetadataFiles(
    String cacheKey, {
    String? cacheDirectory,
  }) async {
    final root = _rootDirectory(cacheDirectory);
    if (!await root.exists()) {
      return const <File>[];
    }
    final prefixLength = cacheKey.length < 12 ? cacheKey.length : 12;
    final directoryKeyPrefix = cacheKey.substring(0, prefixLength);
    final files = <File>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final name = path.basename(entity.path);
      if (name.endsWith('-$directoryKeyPrefix') ||
          name.contains('-$directoryKeyPrefix-nocache-')) {
        files.add(File(path.join(entity.path, _metadataFileName)));
      }
    }
    return files;
  }

  Future<Directory> _createTransientCacheDirectory(
    ModelSource source,
    ModelLoadOptions options,
  ) async {
    final root = Directory(options.cacheDirectory ?? defaultCacheDirectory);
    await _createCacheDirectory(root);
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final directory = Directory(
      path.join(root.path, '${source.cacheDirectoryName}-nocache-$timestamp'),
    );
    await _createCacheDirectory(directory);
    return directory;
  }

  Future<void> _createCacheDirectory(Directory directory) async {
    try {
      await directory.create(recursive: true);
    } on FileSystemException catch (error) {
      final reason = error.osError?.message;
      throw LlamaModelException(
        'Cannot create the model cache directory ${directory.path}'
            '${reason == null || reason.isEmpty ? '' : ': $reason'}. Make sure '
            'the directory and its parents are writable, or set '
            'ModelLoadOptions.cacheDirectory to a writable directory.',
        '$error',
      );
    }
  }

  Future<ModelCacheEntry> _localEntry(
    ModelSource source,
    ModelLoadOptions options,
  ) async {
    _rejectUnsupportedLocalOptions(options);
    final file = File(path.normalize(path.absolute(source.path!)));
    final stat = await file.stat();
    if (stat.type == FileSystemEntityType.notFound) {
      throw LlamaModelException(
        'Local model file does not exist: ${source.path}.',
      );
    }
    if (stat.type != FileSystemEntityType.file) {
      throw LlamaModelException(
        'Local model path is not a file: ${source.path}.',
      );
    }
    String? verifiedSha256;
    if (options.sha256 != null) {
      final actual = await _sha256File(file);
      if (actual != options.sha256) {
        throw LlamaModelException(
          'Checksum mismatch for local model file: ${source.path}.',
        );
      }
      verifiedSha256 = actual;
    }
    try {
      return await _entryForFile(
        source,
        file,
        DateTime.now().toUtc(),
        sha256Digest: verifiedSha256,
      );
    } on ArgumentError {
      // ModelCacheEntry rejects names that %2e, %2f and %5c escapes would turn
      // into traversal for a reader that percent-decodes them.
      throw UncacheableLocalModelFileException(
        'Local model path ${source.path} has a file name containing %2F or '
        '%5C, or a directory named %2e or %2e%2e, which a ModelCacheEntry '
        'cannot hold; load the file with LlamaEngine.load or setModel '
        'instead.',
        filePath: file.path,
        bytes: stat.size,
      );
    }
  }

  Future<ModelCacheEntry?> _readCompletedEntry(
    ModelSource source,
    File metadataFile,
    File finalFile,
    ModelLoadOptions options,
  ) async {
    try {
      if (await FileSystemEntity.type(finalFile.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      final metadataType = await FileSystemEntity.type(
        metadataFile.path,
        followLinks: false,
      );
      if (metadataType == FileSystemEntityType.link) {
        return null;
      }
      if (metadataType == FileSystemEntityType.notFound) {
        return await _recoverMetadataEntry(
          source,
          metadataFile,
          finalFile,
          options,
        );
      }
    } on FileSystemException {
      return _recoverMetadataEntry(source, metadataFile, finalFile, options);
    } on IOException {
      return _recoverMetadataEntry(source, metadataFile, finalFile, options);
    }

    final ModelCacheEntry entry;
    try {
      entry = await _readMetadata(metadataFile);
    } on FormatException {
      return _recoverMetadataEntry(source, metadataFile, finalFile, options);
    } on ArgumentError {
      return _recoverMetadataEntry(source, metadataFile, finalFile, options);
    } on FileSystemException {
      return _recoverMetadataEntry(source, metadataFile, finalFile, options);
    } on IOException {
      return _recoverMetadataEntry(source, metadataFile, finalFile, options);
    }

    // The stored path is not compared: an iOS app update moves the app's
    // container, and this cache with it, to a new path. [finalFile] comes
    // from the current root and is verified against the recorded length and
    // checksum instead.
    if (entry.cacheKey != source.cacheKey ||
        entry.fileName != source.fileName) {
      return null;
    }
    final verification = await _verifyCompletedFile(
      finalFile,
      metadataFile,
      entry,
      options,
    );
    if (!verification.isValid) {
      return null;
    }
    final refreshed = ModelCacheEntry(
      sourceCanonicalKey: entry.sourceCanonicalKey,
      cacheKey: entry.cacheKey,
      fileName: entry.fileName,
      filePath: finalFile.path,
      bytes: verification.bytes!,
      sha256: verification.sha256 ?? entry.sha256,
      etag: entry.etag,
      lastModified: entry.lastModified,
      createdAt: entry.createdAt,
      updatedAt: DateTime.now().toUtc(),
      expiresAt: entry.expiresAt,
    );
    await _tryWriteMetadata(metadataFile, refreshed);
    return refreshed;
  }

  /// Writes [entry] to [metadataFile] when it can. A verified entry stays a
  /// cache hit when its metadata cannot be written, as in a read-only cache
  /// root.
  Future<void> _tryWriteMetadata(
    File metadataFile,
    ModelCacheEntry entry,
  ) async {
    try {
      await _writeMetadata(metadataFile, entry);
    } on IOException {
      // The previous metadata, if any, is still intact: it is only replaced
      // by a rename.
    }
  }

  Future<ModelCacheEntry?> _recoverMetadataEntry(
    ModelSource source,
    File metadataFile,
    File finalFile,
    ModelLoadOptions options,
  ) async {
    try {
      final verifiedSha256 = await _verifyRecoveredFile(
        finalFile,
        metadataFile,
        options,
      );
      if (options.sha256 != null && verifiedSha256 == null) {
        return null;
      }
      final now = DateTime.now().toUtc();
      final recovered = await _entryForFile(
        source,
        finalFile,
        now,
        sha256Digest: verifiedSha256,
      );
      await _tryWriteMetadata(metadataFile, recovered);
      return recovered;
    } on FileSystemException {
      await _deleteIfExists(metadataFile);
      return null;
    } on IOException {
      await _deleteIfExists(metadataFile);
      return null;
    }
  }

  Future<({bool isValid, int? bytes, String? sha256})> _verifyCompletedFile(
    File finalFile,
    File metadataFile,
    ModelCacheEntry entry,
    ModelLoadOptions options,
  ) async {
    try {
      final actualBytes = await finalFile.length();
      final recordedBytes = entry.bytes;
      if (recordedBytes != null && actualBytes != recordedBytes) {
        await _deleteStaleCompletedEntry(finalFile, metadataFile);
        return (isValid: false, bytes: null, sha256: null);
      }
      final storedSha256 = entry.sha256;
      final expectedSha256 = options.sha256;
      if (storedSha256 == null && expectedSha256 == null) {
        return (isValid: true, bytes: actualBytes, sha256: null);
      }
      final actual = await _sha256File(finalFile);
      if ((storedSha256 != null && actual != storedSha256) ||
          (expectedSha256 != null && actual != expectedSha256)) {
        await _deleteStaleCompletedEntry(finalFile, metadataFile);
        return (isValid: false, bytes: null, sha256: null);
      }
      return (isValid: true, bytes: actualBytes, sha256: actual);
    } on FileSystemException {
      await _deleteIfExists(metadataFile);
      return (isValid: false, bytes: null, sha256: null);
    } on IOException {
      await _deleteIfExists(metadataFile);
      return (isValid: false, bytes: null, sha256: null);
    }
  }

  Future<String?> _verifyRecoveredFile(
    File finalFile,
    File metadataFile,
    ModelLoadOptions options,
  ) async {
    try {
      final expectedSha256 = options.sha256;
      if (expectedSha256 == null) {
        return null;
      }
      final actual = await _sha256File(finalFile);
      if (actual != expectedSha256) {
        await _deleteStaleCompletedEntry(finalFile, metadataFile);
        return null;
      }
      return actual;
    } on FileSystemException {
      await _deleteIfExists(metadataFile);
      return null;
    } on IOException {
      await _deleteIfExists(metadataFile);
      return null;
    }
  }

  Future<void> _deleteStaleCompletedEntry(
    File finalFile,
    File metadataFile,
  ) async {
    await _deleteIfExists(finalFile);
    await _deleteIfExists(metadataFile);
  }

  Future<ModelCacheEntry> _download(
    ModelSource source,
    ModelLoadOptions options,
    File finalFile,
    File? partFile,
    ModelDownloadProgressCallback? onProgress,
  ) async {
    final uri = source.resolvedUri;
    if (uri == null) {
      throw LlamaModelException('Remote model source has no resolved URL.');
    }

    Object? lastError;
    for (var attempt = 0; attempt <= options.maxRetries; attempt += 1) {
      _throwIfCancelled(options);
      try {
        return await _downloadOnce(
          source,
          options,
          uri,
          finalFile,
          partFile,
          onProgress,
        );
      } on LlamaStateException {
        rethrow;
      } on LlamaModelException catch (error) {
        lastError = error;
        if (!_isRetryable(error) || attempt == options.maxRetries) {
          rethrow;
        }
      } on IOException catch (error) {
        lastError = error;
        if (attempt == options.maxRetries) {
          throw LlamaModelException(
            'Failed to download ${_redactedSourceName(source)}.',
            redactUrlSecrets('$error', sourceUrls: <String>['$uri']),
          );
        }
      }
    }
    throw LlamaModelException(
      'Failed to download ${_redactedSourceName(source)}.',
      lastError,
    );
  }

  Future<ModelCacheEntry> _downloadOnce(
    ModelSource source,
    ModelLoadOptions options,
    Uri uri,
    File finalFile,
    File? partFile,
    ModelDownloadProgressCallback? onProgress, {
    int restartDepth = 0,
  }) async {
    // Bound the restart recursion (validator-mismatch / HTTP 416 restarts) so a
    // server that keeps flapping its validator cannot drive unbounded recursion
    // or repeated full re-downloads.
    if (restartDepth > 3) {
      throw LlamaModelException(
        'Exceeded download restart attempts for ${_redactedSourceName(source)}.',
      );
    }
    await finalFile.parent.create(recursive: true);
    final downloadFile = partFile ?? File('${finalFile.path}.download');
    final partMetadataFile = partFile == null
        ? null
        : _partMetadataFile(partFile);
    final partMetadata = partMetadataFile == null
        ? null
        : await _readPartMetadata(partMetadataFile);
    var existingBytes = 0;
    // Only resume when we have a stored validator (ETag/Last-Modified) to send
    // as If-Range. Resuming on sha256 alone risks appending a fresh tail onto
    // stale leading bytes if the remote changed, wasting a full re-download
    // before the checksum catches it.
    final hasResumeValidator =
        partMetadata != null &&
        (partMetadata.etag != null || partMetadata.lastModified != null);
    final canResumePartial =
        partFile != null &&
        options.resume &&
        await partFile.exists() &&
        hasResumeValidator;
    if (canResumePartial) {
      existingBytes = await partFile.length();
    } else {
      await _deleteIfExists(downloadFile);
      if (partMetadataFile != null) {
        await _deleteIfExists(partMetadataFile);
      }
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    final requestUrls = <String>{uri.toString()};
    try {
      var requestUri = uri;
      late HttpClientResponse response;
      for (var redirectCount = 0; ; redirectCount += 1) {
        final request = await client.getUrl(requestUri);
        request.followRedirects = false;
        final includeCallerHeaders = _sameOrigin(uri, requestUri);
        if (includeCallerHeaders) {
          for (final header in options.headers.entries) {
            request.headers.set(header.key, header.value);
          }
          final bearerToken = options.bearerToken;
          if (bearerToken != null) {
            request.headers.set(
              HttpHeaders.authorizationHeader,
              'Bearer $bearerToken',
            );
          }
        }
        if (existingBytes > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
          final validator = partMetadata?.etag ?? partMetadata?.lastModified;
          if (validator != null) {
            request.headers.set(HttpHeaders.ifRangeHeader, validator);
          }
        }

        // Bound the wait for response headers too: a server can accept the
        // connection (passing connectionTimeout) yet never send headers, which
        // would hang before the body idle-read timeout is even installed.
        response = await request.close().timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw const HttpException(
            'Timed out waiting for download response headers.',
          ),
        );
        if (!_isRedirectStatus(response.statusCode)) {
          break;
        }
        if (redirectCount >= 10) {
          await response.drain<void>();
          throw LlamaModelException(
            'Too many redirects while downloading ${_redactedSourceName(source)}.',
          );
        }
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null || location.isEmpty) {
          await response.drain<void>();
          throw LlamaModelException(
            'Redirect missing Location while downloading ${_redactedSourceName(source)}.',
          );
        }
        requestUrls.add(location);
        requestUri = requestUri.resolve(location);
        requestUrls.add(requestUri.toString());
        await response.drain<void>();
      }
      final statusCode = response.statusCode;
      final responsePartMetadata = _PartMetadata.fromResponse(response);
      final append =
          existingBytes > 0 && statusCode == HttpStatus.partialContent;
      if (existingBytes > 0 && statusCode == HttpStatus.partialContent) {
        try {
          _validateContentRange(response, existingBytes, source);
          _validateResumeValidator(partMetadata, responsePartMetadata, source);
        } on LlamaModelException {
          await response.drain<void>();
          await _deleteIfExists(downloadFile);
          if (partMetadataFile != null) {
            await _deleteIfExists(partMetadataFile);
          }
          return await _downloadOnce(
            source,
            options,
            uri,
            finalFile,
            partFile,
            onProgress,
            restartDepth: restartDepth + 1,
          );
        }
      } else if (existingBytes > 0 && statusCode == HttpStatus.ok) {
        existingBytes = 0;
        await _deleteIfExists(downloadFile);
        if (partMetadataFile != null) {
          await _deleteIfExists(partMetadataFile);
        }
      } else if (existingBytes > 0 &&
          statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        await response.drain<void>();
        await _deleteIfExists(downloadFile);
        if (partMetadataFile != null) {
          await _deleteIfExists(partMetadataFile);
        }
        return await _downloadOnce(
          source,
          options,
          uri,
          finalFile,
          partFile,
          onProgress,
          restartDepth: restartDepth + 1,
        );
      } else if (statusCode != HttpStatus.ok) {
        throw LlamaModelException(
          'Failed to download ${_redactedSourceName(source)}: HTTP $statusCode.',
          statusCode,
        );
      }

      if (partMetadataFile != null) {
        await _writePartMetadata(partMetadataFile, responsePartMetadata);
      }

      final output = await downloadFile.open(
        mode: append ? FileMode.append : FileMode.write,
      );
      if (append) {
        // Write at the offset the Range request asked for, not at the file's
        // current end: a writer without the entry lock may have extended the
        // file during the round trip, and its bytes there match the entity.
        await output.setPosition(existingBytes);
      }
      var receivedBytes = existingBytes;
      final totalBytes = _totalBytes(response, existingBytes);
      // Guard against a server that accepts the connection then stalls: an idle
      // read timeout surfaces as an IOException so the retry loop can react,
      // instead of hanging indefinitely (cooperative cancel only fires when a
      // chunk arrives).
      final body = response.timeout(
        const Duration(seconds: 60),
        onTimeout: (sink) {
          sink.addError(
            const HttpException('Timed out waiting for download data.'),
          );
          sink.close();
        },
      );
      try {
        await for (final chunk in body) {
          _throwIfCancelled(options);
          await output.writeFrom(chunk);
          receivedBytes += chunk.length;
          onProgress?.call(
            ModelDownloadProgress(
              receivedBytes: receivedBytes,
              totalBytes: totalBytes,
            ),
          );
        }
      } finally {
        await output.close();
      }
      _throwIfCancelled(options);

      // A body can end early, and a writer that does not take the entry lock
      // (an older llamadart, or a process that could not lock) can still be
      // writing a part file this attempt resumed. A short file stays as the
      // resume point; a longer one holds bytes from elsewhere.
      final downloadedBytes = await downloadFile.length();
      if (totalBytes != null && downloadedBytes != totalBytes) {
        if (downloadedBytes > totalBytes) {
          await _deleteIfExists(downloadFile);
          if (partMetadataFile != null) {
            await _deleteIfExists(partMetadataFile);
          }
        }
        throw HttpException(
          'Downloaded $downloadedBytes bytes but the server reported '
          '$totalBytes.',
        );
      }

      String? verifiedSha256;
      if (options.sha256 != null) {
        final actual = await _sha256File(downloadFile);
        if (actual != options.sha256) {
          await _deleteIfExists(downloadFile);
          // Drop the stale validator too, so the next attempt restarts cleanly
          // instead of resuming onto bytes we just rejected.
          if (partMetadataFile != null) {
            await _deleteIfExists(partMetadataFile);
          }
          throw LlamaModelException(
            'Checksum mismatch for ${_redactedSourceName(source)}.',
          );
        }
        verifiedSha256 = actual;
      }
      await _replaceFile(downloadFile, finalFile);
      if (partMetadataFile != null) {
        await _deleteIfExists(partMetadataFile);
      }
      final entry = await _entryForFile(
        source,
        finalFile,
        DateTime.now().toUtc(),
        etag: responsePartMetadata.etag,
        lastModified: responsePartMetadata.lastModified,
        sha256Digest: verifiedSha256,
      );
      onProgress?.call(
        ModelDownloadProgress(
          receivedBytes: entry.bytes ?? 0,
          totalBytes: entry.bytes,
        ),
      );
      return entry;
    } on TlsException catch (error) {
      final details = redactUrlSecrets('$error', sourceUrls: requestUrls);
      if (!_isPermanentTlsFailure(error)) {
        throw HttpException(details);
      }
      // A LlamaModelException without an HTTP status is not retried: a
      // certificate or handshake failure fails the same way every time.
      throw LlamaModelException(_tlsFailureMessage(source, error), details);
    } on IOException catch (error) {
      // Preserve the outer download retry policy while sanitizing every hop.
      throw HttpException(redactUrlSecrets('$error', sourceUrls: requestUrls));
    } on ArgumentError catch (error) {
      throw LlamaModelException(
        'Failed to download ${_redactedSourceName(source)}.',
        redactUrlSecrets('$error', sourceUrls: requestUrls),
      );
    } on FormatException catch (error) {
      throw LlamaModelException(
        'Failed to download ${_redactedSourceName(source)}.',
        redactUrlSecrets('$error', sourceUrls: requestUrls),
      );
    } finally {
      client.close(force: true);
      if (partFile == null) {
        await _deleteIfExists(downloadFile);
      }
    }
  }

  Future<ModelCacheEntry> _entryForFile(
    ModelSource source,
    File file,
    DateTime timestamp, {
    String? etag,
    String? lastModified,
    String? sha256Digest,
  }) async {
    final bytes = await file.length();
    final digest = sha256Digest;
    return ModelCacheEntry(
      sourceCanonicalKey: source.metadataSourceKey,
      cacheKey: source.cacheKey,
      fileName: source.fileName,
      filePath: file.path,
      bytes: bytes,
      sha256: digest,
      etag: etag,
      lastModified: lastModified,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  Future<ModelCacheEntry> _readMetadata(File metadataFile) async {
    final decoded = jsonDecode(await metadataFile.readAsString());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Model cache metadata must be an object.');
    }
    final schemaVersion = decoded['schema_version'];
    if (schemaVersion != _metadataSchemaVersion) {
      throw FormatException(
        'Unsupported model cache metadata schema: $schemaVersion.',
      );
    }
    return ModelCacheEntry.fromJson(decoded);
  }

  Future<void> _writeMetadata(File metadataFile, ModelCacheEntry entry) async {
    await metadataFile.parent.create(recursive: true);
    final tempFile = File('${metadataFile.path}.${_newAttemptId()}.tmp');
    final json = <String, Object?>{
      'schema_version': _metadataSchemaVersion,
      ...entry.toJson(),
    };
    await tempFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(json)}\n',
    );
    await _replaceFile(tempFile, metadataFile);
  }

  Future<List<ModelCacheEntry>> _removeStaleMetadataEntries(
    String? cacheDirectory,
  ) async {
    final root = _rootDirectory(cacheDirectory);
    if (!await root.exists()) {
      return <ModelCacheEntry>[];
    }

    final removed = <ModelCacheEntry>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final metadataFile = File(path.join(entity.path, _metadataFileName));
      try {
        final snapshot = await _readManagedEntry(
          metadataFile,
          root,
          requireFile: false,
        );
        if (snapshot != null && !await File(snapshot.entry.filePath).exists()) {
          final result = await _removeCacheDirectory(
            entity,
            cacheDirectory: cacheDirectory,
            stillRemovable: () async {
              final current = await _readManagedEntry(
                metadataFile,
                root,
                requireFile: false,
              );
              return current != null &&
                  current.recordedFilePath == snapshot.recordedFilePath &&
                  current.entry.cacheKey == snapshot.entry.cacheKey &&
                  current.entry.fileName == snapshot.entry.fileName &&
                  current.entry.updatedAt == snapshot.entry.updatedAt &&
                  !await File(current.entry.filePath).exists();
            },
          );
          if (result == _Removal.removed) {
            removed.add(snapshot.entry);
          }
        }
      } catch (_) {
        // Ignore malformed cache entries so one corrupt metadata file does not
        // make cache pruning unusable.
      }
    }
    return removed;
  }

  Future<void> _removeByCacheKey(
    String cacheKey, {
    required List<String> inUse,
    String? cacheDirectory,
  }) async {
    final root = await _resolvedRootDirectory(cacheDirectory);
    for (final metadataFile in await _candidateMetadataFiles(
      cacheKey,
      cacheDirectory: root.path,
    )) {
      final _ManagedCacheEntry? snapshot;
      try {
        snapshot = await _readManagedEntry(
          metadataFile,
          root,
          requireFile: false,
        );
      } catch (_) {
        // Ignore malformed metadata so a corrupt entry does not block removing
        // other cache directories with the same key prefix.
        continue;
      }
      if (snapshot == null || snapshot.entry.cacheKey != cacheKey) {
        continue;
      }
      final result = await _removeCacheDirectory(
        metadataFile.parent,
        cacheDirectory: root.path,
        stillRemovable: () async {
          try {
            final current = await _readManagedEntry(
              metadataFile,
              root,
              requireFile: false,
            );
            return current?.entry.cacheKey == cacheKey;
          } catch (_) {
            return false;
          }
        },
      );
      if (result == _Removal.inUse) {
        inUse.add(metadataFile.parent.path);
      }
    }
  }

  Future<Directory?> _cacheEntryDirectory(
    Directory directory,
    Directory root,
  ) async {
    final directoryPath = path.normalize(path.absolute(directory.path));
    final rootPath = path.normalize(path.absolute(root.path));
    if (!path.equals(path.dirname(directoryPath), rootPath)) {
      return null;
    }
    try {
      if (await FileSystemEntity.type(directoryPath, followLinks: false) !=
          FileSystemEntityType.directory) {
        return null;
      }
      final resolvedRoot = await root.resolveSymbolicLinks();
      final resolvedDirectory = await directory.resolveSymbolicLinks();
      return path.equals(path.dirname(resolvedDirectory), resolvedRoot)
          ? Directory(resolvedDirectory)
          : null;
    } on FileSystemException catch (error) {
      // Another remover can delete a listed entry before we take its lock.
      // A dangling/replaced link is unsafe, rather than an already-gone entry.
      if ((error.osError?.errorCode == 2 ||
              (Platform.isWindows && error.osError?.errorCode == 3) ||
              _mayBeWindowsDeletePending(error)) &&
          await FileSystemEntity.type(directoryPath, followLinks: false) ==
              FileSystemEntityType.notFound) {
        return null;
      }
      rethrow;
    }
  }

  Future<_ManagedCacheEntry?> _readManagedEntry(
    File metadataFile,
    Directory root, {
    bool requireFile = true,
  }) async {
    final directory = metadataFile.parent;
    if (await _cacheEntryDirectory(directory, root) == null ||
        await FileSystemEntity.type(metadataFile.path, followLinks: false) !=
            FileSystemEntityType.file) {
      return null;
    }
    final entry = await _readMetadata(metadataFile);
    final prefixLength = entry.cacheKey.length < 12
        ? entry.cacheKey.length
        : 12;
    final prefix = RegExp.escape(entry.cacheKey.substring(0, prefixLength));
    if (!RegExp(
      '-$prefix(?:-nocache-[0-9]+)?\$',
    ).hasMatch(path.basename(directory.path))) {
      return null;
    }
    // filePath is historical: an app update can move the whole container.
    // Only the current entry directory and the validated basename select a file.
    final file = File(path.join(directory.path, entry.fileName));
    if (!path.equals(
      path.dirname(path.normalize(path.absolute(file.path))),
      path.normalize(path.absolute(directory.path)),
    )) {
      return null;
    }
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        (requireFile || type != FileSystemEntityType.notFound)) {
      return null;
    }
    return (
      recordedFilePath: entry.filePath,
      entry: ModelCacheEntry(
        sourceCanonicalKey: entry.sourceCanonicalKey,
        cacheKey: entry.cacheKey,
        fileName: entry.fileName,
        filePath: file.path,
        bytes: entry.bytes,
        sha256: entry.sha256,
        etag: entry.etag,
        lastModified: entry.lastModified,
        createdAt: entry.createdAt,
        updatedAt: entry.updatedAt,
        expiresAt: entry.expiresAt,
      ),
    );
  }

  /// Removes the entry in [snapshot] unless it is in use or its metadata changed
  /// listed: a cache hit refreshes `updatedAt` under the entry lock.
  Future<bool> _removeEntry(
    _ManagedCacheEntry snapshot, {
    String? cacheDirectory,
  }) async {
    final entry = snapshot.entry;
    final directory = await _cacheEntryDirectory(
      Directory(path.dirname(entry.filePath)),
      _rootDirectory(cacheDirectory),
    );
    if (directory == null) {
      return false;
    }
    final result = await _removeCacheDirectory(
      directory,
      cacheDirectory: directory.parent.path,
      stillRemovable: () async {
        try {
          final current = await _readManagedEntry(
            File(path.join(directory.path, _metadataFileName)),
            directory.parent,
          );
          return current != null &&
              current.recordedFilePath == snapshot.recordedFilePath &&
              current.entry.cacheKey == entry.cacheKey &&
              current.entry.fileName == entry.fileName &&
              current.entry.updatedAt == entry.updatedAt;
        } catch (_) {
          return false;
        }
      },
    );
    return result == _Removal.removed;
  }

  Future<_Removal> _removeCacheDirectory(
    Directory directory, {
    String? cacheDirectory,
    Future<bool> Function()? stillRemovable,
  }) async {
    final cacheDirectoryToRemove = await _cacheEntryDirectory(
      directory,
      _rootDirectory(cacheDirectory),
    );
    if (cacheDirectoryToRemove == null) {
      return _Removal.skipped;
    }
    final root = cacheDirectoryToRemove.parent;
    final rootPath = root.path;
    final directoryPath = cacheDirectoryToRemove.path;
    if (path.equals(directoryPath, rootPath) ||
        !path.isWithin(rootPath, directoryPath) ||
        path.basename(directoryPath) == _lockDirectoryName) {
      return _Removal.skipped;
    }
    var result = _Removal.skipped;
    Future<void> remove() async {
      if (await _cacheEntryDirectory(cacheDirectoryToRemove, root) == null ||
          (stillRemovable != null && !await stillRemovable())) {
        return;
      }
      result = await _deleteEntryDirectory(cacheDirectoryToRemove);
    }

    // noCache downloads take no entry lock, and a lock file per transient
    // directory would never be deleted. A stray `.removal` directory is no
    // entry, and its entry lock would be the removal lock; file systems that
    // ignore case also read `.REMOVAL` as it. Both still wait for the removal
    // lock, so overlapping removers do not delete one directory twice.
    final name = path.basename(directoryPath);
    final takesEntryLocks =
        !_transientDirectoryName.hasMatch(name) &&
        name.toLowerCase() != _strayRemovalDirectoryName;
    return _withRemovalLock(Directory(rootPath), () async {
      if (!takesEntryLocks) {
        await remove();
      } else if (!await _tryWithEntryLocks(cacheDirectoryToRemove, remove)) {
        return _Removal.inUse;
      }
      return result;
    });
  }

  /// Deletes the model files first, so an entry whose model file Windows
  /// refuses to delete, because a process has it open or mapped, keeps its
  /// metadata and stays usable.
  Future<_Removal> _deleteEntryDirectory(Directory directory) async {
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File && path.basename(entity.path) != _metadataFileName) {
          try {
            await entity.delete();
          } on FileSystemException catch (error) {
            if (Platform.isWindows &&
                await isWindowsDeleteRefusedForOpenFile(
                  entity,
                  error.osError?.errorCode,
                )) {
              return _Removal.inUse;
            }
            rethrow;
          }
        }
      }
      await directory.delete(recursive: true);
      return _Removal.removed;
    } on FileSystemException catch (error) {
      if (Platform.isWindows &&
          windowsFileInUseErrors.contains(error.osError?.errorCode)) {
        return _Removal.inUse;
      }
      rethrow;
    }
  }
}

enum _Removal { removed, inUse, skipped }

/// Whether [error] may come from opening a directory that is pending delete
/// on Windows: one that another process or isolate is deleting, between
/// setting its delete disposition and closing that handle, or, without POSIX
/// delete semantics, until every handle to it closes. Opening it then fails
/// with `ERROR_ACCESS_DENIED`, and so does the attribute query behind
/// [FileSystemEntity.type], which reports that failure as
/// [FileSystemEntityType.notFound]; callers tell it from a real denial by
/// that type. A different ACL denial can read as `notFound` too; see
/// `_cacheLockKey` for what happens then.
bool _mayBeWindowsDeletePending(FileSystemException error) =>
    Platform.isWindows && error.osError?.errorCode == 5;

/// Thrown from a lock wait to give up instead of waiting.
final class _EntryBusy implements Exception {
  const _EntryBusy();
}

final RegExp _transientDirectoryName = RegExp(r'-[0-9a-f]{12}-nocache-\d+$');

class _PartMetadata {
  const _PartMetadata({this.etag, this.lastModified});

  factory _PartMetadata.fromResponse(HttpClientResponse response) {
    return _PartMetadata(
      etag: response.headers.value(HttpHeaders.etagHeader),
      lastModified: response.headers.value(HttpHeaders.lastModifiedHeader),
    );
  }

  factory _PartMetadata.fromJson(Map<String, Object?> json) {
    return _PartMetadata(
      etag: json['etag'] as String?,
      lastModified: json['last_modified'] as String?,
    );
  }

  final String? etag;
  final String? lastModified;

  bool get hasValidator => etag != null || lastModified != null;

  Map<String, Object?> toJson() => <String, Object?>{
    if (etag != null) 'etag': etag,
    if (lastModified != null) 'last_modified': lastModified,
  };
}

File _partMetadataFile(File partFile) => File('${partFile.path}.json');

final Random _attemptIds = Random.secure();

String _newAttemptId() => List<String>.generate(
  8,
  (_) => _attemptIds.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

/// Moves the part file [from], with its resume validator, to [to].
///
/// Does nothing when [from] does not exist. A part file without a validator
/// drops any validator left at [to], which would otherwise describe other
/// bytes.
Future<void> _movePartFile(File from, File to) async {
  if (!await from.exists()) {
    return;
  }
  try {
    await _replaceFile(from, to);
  } on FileSystemException {
    return;
  }
  final fromMetadata = _partMetadataFile(from);
  final toMetadata = _partMetadataFile(to);
  if (await fromMetadata.exists()) {
    try {
      await _replaceFile(fromMetadata, toMetadata);
      return;
    } on FileSystemException {
      await _deleteIfExists(fromMetadata);
    }
  }
  await _deleteIfExists(toMetadata);
}

Future<_PartMetadata?> _readPartMetadata(File file) async {
  try {
    if (!await file.exists()) {
      return null;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final metadata = _PartMetadata.fromJson(decoded);
    return metadata.hasValidator ? metadata : null;
  } catch (_) {
    return null;
  }
}

Future<void> _writePartMetadata(File file, _PartMetadata metadata) async {
  if (!metadata.hasValidator) {
    await _deleteIfExists(file);
    return;
  }
  await file.writeAsString('${jsonEncode(metadata.toJson())}\n');
}

void _throwIfCancelled(ModelLoadOptions options) {
  if (options.cancelToken?.isCancelled ?? false) {
    throw LlamaStateException('Model download was cancelled.');
  }
}

// A handshake that the connection cut short can succeed on a retry, and so
// can a TLS error after the handshake, such as one in the body stream.
bool _isPermanentTlsFailure(TlsException error) =>
    error is CertificateException ||
    (error is HandshakeException &&
        !(error.osError == null &&
            error.message.contains('Connection terminated during handshake')));

String _tlsFailureMessage(ModelSource source, TlsException error) {
  final name = _redactedSourceName(source);
  if (error is CertificateException || _isCertificateVerifyFailure(error)) {
    return 'Failed to download $name: the server\'s TLS certificate could not '
        'be verified. The certificate may be invalid, or this machine may be '
        'missing the root certificate that issued it. A certificate failure '
        'is not retried.';
  }
  return 'Failed to download $name: the TLS handshake with the server failed. '
      'A TLS handshake failure is not retried.';
}

// BoringSSL reports a failed verification of the server's certificate as
// CERTIFICATE_VERIFY_FAILED; OpenSSL-style builds spell it in lower case.
// Alerts such as SSLV3_ALERT_BAD_CERTIFICATE come from the server instead.
bool _isCertificateVerifyFailure(TlsException error) {
  final cause = '${error.message} ${error.osError?.message ?? ''}'
      .toLowerCase();
  return cause.contains('certificate_verify_failed') ||
      cause.contains('certificate verify failed');
}

bool _isRetryable(LlamaModelException error) {
  final details = error.details;
  return details is int && details >= 500;
}

bool _isRedirectStatus(int statusCode) {
  return statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;
}

bool _sameOrigin(Uri first, Uri second) {
  return first.scheme == second.scheme &&
      first.host == second.host &&
      first.port == second.port;
}

int? _totalBytes(HttpClientResponse response, int existingBytes) {
  final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
  if (contentRange != null) {
    final totalPart = contentRange.split('/').last;
    final total = int.tryParse(totalPart);
    if (total != null) {
      return total;
    }
  }
  // A decompressed body is longer than the Content-Length, which counts the
  // encoded bytes.
  if (response.compressionState ==
      HttpClientResponseCompressionState.decompressed) {
    return null;
  }
  final length = response.contentLength;
  if (length >= 0) {
    return existingBytes + length;
  }
  return null;
}

void _validateContentRange(
  HttpClientResponse response,
  int expectedStart,
  ModelSource source,
) {
  final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
  if (contentRange == null ||
      !contentRange.startsWith('bytes $expectedStart-')) {
    throw LlamaModelException(
      'Server returned an invalid resume range for ${_redactedSourceName(source)}.',
    );
  }
}

void _validateResumeValidator(
  _PartMetadata? previous,
  _PartMetadata current,
  ModelSource source,
) {
  if (previous == null) {
    return;
  }
  final previousEtag = previous.etag;
  if (previousEtag != null) {
    if (current.etag != previousEtag) {
      throw LlamaModelException(
        'Server returned a different entity validator while resuming ${_redactedSourceName(source)}.',
      );
    }
    return;
  }
  final previousLastModified = previous.lastModified;
  if (previousLastModified != null &&
      current.lastModified != previousLastModified) {
    throw LlamaModelException(
      'Server returned a different modification timestamp while resuming ${_redactedSourceName(source)}.',
    );
  }
}

Future<String> _sha256File(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

Future<int> _entrySize(ModelCacheEntry entry) async {
  final bytes = entry.bytes;
  if (bytes != null) {
    return bytes;
  }
  try {
    return await File(entry.filePath).length();
  } on FileSystemException {
    return 0;
  }
}

Future<void> _replaceFile(File source, File destination) async {
  try {
    await source.rename(destination.path);
    return;
  } on FileSystemException {
    if (!await destination.exists()) {
      rethrow;
    }
  }

  final backup = File(
    '${destination.path}.replace-${DateTime.now().toUtc().microsecondsSinceEpoch}.bak',
  );
  var backedUp = false;
  try {
    await destination.rename(backup.path);
    backedUp = true;
    await source.rename(destination.path);
    await _deleteIfExists(backup);
  } catch (error) {
    if (backedUp && await backup.exists() && !await destination.exists()) {
      try {
        await backup.rename(destination.path);
      } on FileSystemException {
        // Preserve the original replacement failure; later cache operations can
        // surface the backup path if manual recovery is needed.
      }
    }
    if (error is FileSystemException) {
      rethrow;
    }
    throw FileSystemException(
      'Failed to replace ${destination.path}: $error.',
      source.path,
    );
  }
}

Future<void> _deleteIfExists(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } on FileSystemException {
    // Best effort cleanup; later file operations surface actionable errors.
  }
}

String _defaultSharedCacheDirectoryFor({
  required ModelCachePlatform platform,
  required String namespace,
  required Map<String, String> environment,
  required String? homeDirectory,
}) {
  final context = _pathContextFor(platform);
  switch (platform) {
    case ModelCachePlatform.linux:
      final xdgCacheHome = _nonEmpty(environment['XDG_CACHE_HOME']);
      if (xdgCacheHome != null) {
        return context.join(xdgCacheHome, namespace, 'models');
      }
      final home = _requiredHomeDirectory(platform, homeDirectory);
      return context.join(home, '.cache', namespace, 'models');
    case ModelCachePlatform.macos:
      final home = _requiredHomeDirectory(platform, homeDirectory);
      return context.join(home, 'Library', 'Caches', namespace, 'models');
    case ModelCachePlatform.windows:
      final localAppData =
          _nonEmpty(environment['LOCALAPPDATA']) ??
          _nonEmpty(environment['APPDATA']);
      if (localAppData != null) {
        return context.join(localAppData, namespace, 'models');
      }
      final home = _requiredHomeDirectory(platform, homeDirectory);
      return context.join(home, 'AppData', 'Local', namespace, 'models');
    case ModelCachePlatform.android:
      throw LlamaUnsupportedException(
        'Android has no implicit cross-app shared model cache directory. '
        'Use app-private storage with DefaultModelDownloadManager.appPrivate, '
        'or pass a user-granted model library directory to '
        'DefaultModelDownloadManager.userSelected.',
      );
    case ModelCachePlatform.ios:
      throw LlamaUnsupportedException(
        'iOS has no implicit cross-app shared model cache directory. '
        'Use app-private storage with DefaultModelDownloadManager.appPrivate, '
        'or pass an App Group container path to '
        'DefaultModelDownloadManager.appGroup for same-group apps.',
      );
    case ModelCachePlatform.web:
      throw LlamaUnsupportedException(
        'Web model caches are origin-scoped browser/runtime caches; there is no '
        'file-backed shared cache directory.',
      );
    case ModelCachePlatform.fuchsia:
    case ModelCachePlatform.unknown:
      throw LlamaUnsupportedException(
        'No implicit shared model cache directory is known for '
        '${platform.name}. Pass an explicit cacheDirectory.',
      );
  }
}

path.Context _pathContextFor(ModelCachePlatform platform) {
  if (platform == ModelCachePlatform.windows) {
    return path.Context(style: path.Style.windows);
  }
  return path.Context(style: path.Style.posix);
}

String? _homeDirectoryFor(
  ModelCachePlatform platform,
  Map<String, String> environment,
) {
  if (platform == ModelCachePlatform.windows) {
    final userProfile = _nonEmpty(environment['USERPROFILE']);
    if (userProfile != null) {
      return userProfile;
    }
    final homeDrive = _nonEmpty(environment['HOMEDRIVE']);
    final homePath = _nonEmpty(environment['HOMEPATH']);
    if (homeDrive != null && homePath != null) {
      return path.Context(style: path.Style.windows).join(homeDrive, homePath);
    }
  }
  return _nonEmpty(environment['HOME']);
}

String _requiredHomeDirectory(
  ModelCachePlatform platform,
  String? homeDirectory,
) {
  final home = _nonEmpty(homeDirectory);
  if (home != null) {
    return home;
  }
  throw LlamaUnsupportedException(
    'Cannot resolve a shared model cache directory for ${platform.name}: '
    'no home directory was available. Pass cacheDirectory explicitly.',
  );
}

String? _nonEmpty(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return value;
}

String _defaultImplicitCacheDirectory() {
  final platform = ModelCachePlatform.parse(Platform.operatingSystem);
  try {
    return _defaultImplicitCacheDirectoryFor(platform);
  } on LlamaUnsupportedException {
    // Keep the default constructor non-throwing for compatibility with older
    // embedders and unusual host environments that do not expose a home/cache
    // environment. Explicit auto/sharedCache calls still surface the actionable
    // resolution error.
    return _temporaryCacheDirectory();
  }
}

String _defaultImplicitCacheDirectoryFor(
  ModelCachePlatform platform, {
  String namespace = 'llamadart',
}) {
  final globalCacheDirectory = _globalCacheDirectory();
  if (globalCacheDirectory != null) {
    return globalCacheDirectory;
  }
  if (platform.supportsImplicitSharedModelCache) {
    return DefaultModelDownloadManager.defaultSharedCacheDirectory(
      platform: platform,
      namespace: namespace,
    );
  }
  if (platform.isMobile) {
    final appCacheDirectory = mobileAppCacheDirectoryResolver(platform);
    if (appCacheDirectory != null) {
      return path.posix.join(
        appCacheDirectory,
        _validateCacheNamespace(namespace),
        'models',
      );
    }
    final fallback = _temporaryCacheDirectory(namespace: namespace);
    warnMobileTemporaryCacheOnce(platform, fallback);
    return fallback;
  }
  return _temporaryCacheDirectory(namespace: namespace);
}

String? _globalCacheDirectory() =>
    _nonEmpty(DefaultModelDownloadManager.globalCacheDirectory);

String _temporaryCacheDirectory({String namespace = 'llamadart'}) {
  return path.join(
    Directory.systemTemp.path,
    _validateCacheNamespace(namespace),
    'models',
  );
}

String? _mobileAppPrivateCacheDirectory(
  ModelCachePlatform platform, {
  required String? appPrivateCacheDirectory,
  required String? androidAppPrivateCacheDirectory,
  required String? iosAppPrivateCacheDirectory,
}) {
  final platformPrivateDirectory = switch (platform) {
    ModelCachePlatform.android => _nonEmpty(androidAppPrivateCacheDirectory),
    ModelCachePlatform.ios => _nonEmpty(iosAppPrivateCacheDirectory),
    _ => null,
  };
  return platformPrivateDirectory ?? _nonEmpty(appPrivateCacheDirectory);
}

String _validateCacheNamespace(String namespace) {
  final trimmed = namespace.trim();
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(trimmed)) {
    throw ArgumentError.value(
      namespace,
      'namespace',
      'Cache namespace must contain only letters, numbers, dot, underscore, '
          'or dash, and must not include path separators.',
    );
  }
  return trimmed;
}

String _redactedSourceName(ModelSource source) => redactUrlSecrets(
  source.displayName,
  sourceUrls: <String>[
    source.canonicalKey,
    if (source.resolvedUri case final uri?) uri.toString(),
  ],
);

// The historical path is a metadata-change token, never a file-system target.
typedef _ManagedCacheEntry = ({ModelCacheEntry entry, String recordedFilePath});
