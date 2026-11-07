import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../../core/exceptions.dart';
import '../../core/models/download/model_download_manager_base.dart';
import '../../core/models/model_load_options.dart';
import '../../core/models/model_source.dart';

const String _metadataFileName = 'metadata.json';
const int _metadataSchemaVersion = 1;

/// Native file-backed package-managed model download manager.
class DefaultModelDownloadManager implements ModelDownloadManager {
  /// Creates a native model download/cache manager.
  ///
  /// When [defaultCacheDirectory] is omitted, desktop/server platforms use the
  /// same per-user shared model cache as [DefaultModelDownloadManager.auto].
  /// Android and iOS use an app-private temporary/cache directory so constructing
  /// the manager stays non-throwing; apps that need durable mobile storage should
  /// pass an explicit directory or use [DefaultModelDownloadManager.appPrivate].
  DefaultModelDownloadManager({String? defaultCacheDirectory})
    : defaultCacheDirectory =
          defaultCacheDirectory ?? _defaultImplicitCacheDirectory();

  /// Creates a manager using the recommended cache root for the current platform.
  ///
  /// Pass [cacheDirectory] to force a specific root on every platform,
  /// including an OS-granted mobile model library directory. Otherwise,
  /// desktop/server platforms use [defaultSharedCacheDirectory] with
  /// [namespace], [environment], and [homeDirectory]. Android and iOS use, in
  /// order, their platform-specific app-private directory argument,
  /// [appPrivateCacheDirectory], or an app-private temporary/cache fallback.
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

  /// Default cache root used when [ModelLoadOptions.cacheDirectory] is absent.
  final String defaultCacheDirectory;

  static final Map<String, Future<void>> _cacheLocks = <String, Future<void>>{};

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

    final cacheDir = _cacheDirectory(source, options);
    return _withCacheLock(
      _cacheLockKey(cacheDir),
      () => _ensureModelUnlocked(source, options, onProgress),
    );
  }

  Future<ModelCacheEntry> _ensureModelUnlocked(
    ModelSource source,
    ModelLoadOptions options,
    ModelDownloadProgressCallback? onProgress,
  ) async {
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
          'No cached model is available for ${source.displayName}.',
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

    await cacheDir.create(recursive: true);
    final entry = await _download(
      source,
      options,
      finalFile,
      partFile,
      onProgress,
    );
    await _writeMetadata(metadataFile, entry);
    return entry;
  }

  Future<T> _withCacheLock<T>(String key, Future<T> Function() action) async {
    final previous = _cacheLocks[key];
    final current = Completer<void>();
    _cacheLocks[key] = current.future;

    if (previous != null) {
      await previous;
    }

    try {
      return await action();
    } finally {
      if (identical(_cacheLocks[key], current.future)) {
        _cacheLocks.remove(key);
      }
      current.complete();
    }
  }

  @override
  Future<List<ModelCacheEntry>> list({String? cacheDirectory}) async {
    final root = _rootDirectory(cacheDirectory);
    if (!await root.exists()) {
      return <ModelCacheEntry>[];
    }
    final entries = <ModelCacheEntry>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final metadataFile = File(path.join(entity.path, _metadataFileName));
      if (!await metadataFile.exists()) {
        continue;
      }
      try {
        final entry = await _readMetadata(metadataFile);
        final entryFile = _entryFileInCacheDirectory(entry, entity);
        if (entryFile != null && await entryFile.exists()) {
          entries.add(entry);
        }
      } catch (_) {
        // Ignore malformed cache entries so one corrupt metadata file does not
        // make cache inspection unusable.
      }
    }
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
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
        final entry = await _readMetadata(metadataFile);
        final entryFile = _entryFileInCacheDirectory(
          entry,
          metadataFile.parent,
        );
        if (entry.cacheKey == cacheKey &&
            entryFile != null &&
            await entryFile.exists()) {
          entries.add(entry);
        }
      } catch (_) {
        // Ignore malformed candidates so a corrupt entry does not make cache
        // inspection unusable.
      }
    }
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries.isEmpty ? null : entries.first;
  }

  @override
  Future<void> remove(String cacheKey, {String? cacheDirectory}) async {
    await _removeByCacheKey(cacheKey, cacheDirectory: cacheDirectory);
  }

  @override
  Future<void> clear({String? cacheDirectory}) async {
    final root = _rootDirectory(cacheDirectory);
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }

  @override
  Future<List<ModelCacheEntry>> prune({
    Duration? maxAge,
    int? maxBytes,
    String? cacheDirectory,
  }) async {
    final entries = await list(cacheDirectory: cacheDirectory);
    final removed = await _removeStaleMetadataEntries(cacheDirectory);
    final now = DateTime.now().toUtc();

    for (final entry in entries) {
      if (maxAge != null && now.difference(entry.updatedAt.toUtc()) > maxAge) {
        if (await _removeEntry(entry, cacheDirectory: cacheDirectory)) {
          removed.add(entry);
        }
      }
    }

    if (maxBytes != null) {
      final remaining = (await list(cacheDirectory: cacheDirectory)).toList()
        ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      var total = 0;
      for (final entry in remaining) {
        total += await _entrySize(entry);
      }
      for (final entry in remaining) {
        if (total <= maxBytes) {
          break;
        }
        final size = await _entrySize(entry);
        if (await _removeEntry(entry, cacheDirectory: cacheDirectory)) {
          removed.add(entry);
          total -= size;
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

  String _cacheLockKey(Directory cacheDirectory) {
    return path.normalize(path.absolute(cacheDirectory.path));
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
    await root.create(recursive: true);
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final directory = Directory(
      path.join(root.path, '${source.cacheDirectoryName}-nocache-$timestamp'),
    );
    await directory.create(recursive: true);
    return directory;
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
    return _entryForFile(
      source,
      file,
      DateTime.now().toUtc(),
      sha256Digest: verifiedSha256,
    );
  }

  Future<ModelCacheEntry?> _readCompletedEntry(
    ModelSource source,
    File metadataFile,
    File finalFile,
    ModelLoadOptions options,
  ) async {
    try {
      if (!await finalFile.exists()) {
        return null;
      }
      if (!await metadataFile.exists()) {
        return _recoverMetadataEntry(source, metadataFile, finalFile, options);
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

    if (entry.cacheKey != source.cacheKey ||
        entry.fileName != source.fileName ||
        entry.filePath != finalFile.path) {
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
    try {
      final refreshed = ModelCacheEntry(
        sourceCanonicalKey: entry.sourceCanonicalKey,
        cacheKey: entry.cacheKey,
        fileName: entry.fileName,
        filePath: entry.filePath,
        bytes: verification.bytes!,
        sha256: verification.sha256 ?? entry.sha256,
        etag: entry.etag,
        lastModified: entry.lastModified,
        createdAt: entry.createdAt,
        updatedAt: DateTime.now().toUtc(),
        expiresAt: entry.expiresAt,
      );
      await _writeMetadata(metadataFile, refreshed);
      return refreshed;
    } on FileSystemException {
      await _deleteIfExists(metadataFile);
      return null;
    } on IOException {
      await _deleteIfExists(metadataFile);
      return null;
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
      await _writeMetadata(metadataFile, recovered);
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
            'Failed to download ${source.displayName}.',
            error,
          );
        }
      }
    }
    throw LlamaModelException(
      'Failed to download ${source.displayName}.',
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
        'Exceeded download restart attempts for ${source.displayName}.',
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
            'Too many redirects while downloading ${source.displayName}.',
          );
        }
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null || location.isEmpty) {
          await response.drain<void>();
          throw LlamaModelException(
            'Redirect missing Location while downloading ${source.displayName}.',
          );
        }
        requestUri = requestUri.resolve(location);
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
          return _downloadOnce(
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
        return _downloadOnce(
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
          'Failed to download ${source.displayName}: HTTP $statusCode.',
          statusCode,
        );
      }

      if (partMetadataFile != null) {
        await _writePartMetadata(partMetadataFile, responsePartMetadata);
      }

      final sink = downloadFile.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );
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
          sink.add(chunk);
          receivedBytes += chunk.length;
          onProgress?.call(
            ModelDownloadProgress(
              receivedBytes: receivedBytes,
              totalBytes: totalBytes,
            ),
          );
        }
      } finally {
        await sink.close();
      }
      _throwIfCancelled(options);

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
            'Checksum mismatch for ${source.displayName}.',
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
    final tempFile = File('${metadataFile.path}.tmp');
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
      if (!await metadataFile.exists()) {
        continue;
      }
      try {
        final entry = await _readMetadata(metadataFile);
        final entryFile = _entryFileInCacheDirectory(entry, entity);
        if (entryFile != null && !await entryFile.exists()) {
          if (await _removeCacheDirectory(
            entity,
            cacheDirectory: cacheDirectory,
          )) {
            removed.add(entry);
          }
        }
      } catch (_) {
        // Ignore malformed cache entries so one corrupt metadata file does not
        // make cache pruning unusable.
      }
    }
    return removed;
  }

  Future<List<ModelCacheEntry>> _removeByCacheKey(
    String cacheKey, {
    String? cacheDirectory,
  }) async {
    final removed = <ModelCacheEntry>[];
    for (final metadataFile in await _candidateMetadataFiles(
      cacheKey,
      cacheDirectory: cacheDirectory,
    )) {
      try {
        final entry = await _readMetadata(metadataFile);
        if (entry.cacheKey != cacheKey ||
            _entryFileInCacheDirectory(entry, metadataFile.parent) == null) {
          continue;
        }
        if (await _removeCacheDirectory(
          metadataFile.parent,
          cacheDirectory: cacheDirectory,
        )) {
          removed.add(entry);
        }
      } catch (_) {
        // Ignore malformed metadata so a corrupt entry does not block removing
        // other cache directories with the same key prefix.
      }
    }
    return removed;
  }

  File? _entryFileInCacheDirectory(ModelCacheEntry entry, Directory directory) {
    final directoryPath = path.normalize(path.absolute(directory.path));
    final filePath = path.normalize(path.absolute(entry.filePath));
    if (!path.isWithin(directoryPath, filePath) ||
        !path.equals(path.dirname(filePath), directoryPath)) {
      return null;
    }
    return File(filePath);
  }

  Future<bool> _removeEntry(
    ModelCacheEntry entry, {
    String? cacheDirectory,
  }) async {
    return _removeCacheDirectory(
      Directory(path.dirname(entry.filePath)),
      cacheDirectory: cacheDirectory,
    );
  }

  Future<bool> _removeCacheDirectory(
    Directory directory, {
    String? cacheDirectory,
  }) async {
    final rootPath = path.normalize(
      path.absolute(_rootDirectory(cacheDirectory).path),
    );
    final directoryPath = path.normalize(path.absolute(directory.path));
    if (path.equals(directoryPath, rootPath) ||
        !path.isWithin(rootPath, directoryPath)) {
      return false;
    }
    final cacheDirectoryToRemove = Directory(directoryPath);
    if (!await cacheDirectoryToRemove.exists()) {
      return false;
    }
    await cacheDirectoryToRemove.delete(recursive: true);
    return true;
  }
}

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
      'Server returned an invalid resume range for ${source.displayName}.',
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
        'Server returned a different entity validator while resuming ${source.displayName}.',
      );
    }
    return;
  }
  final previousLastModified = previous.lastModified;
  if (previousLastModified != null &&
      current.lastModified != previousLastModified) {
    throw LlamaModelException(
      'Server returned a different modification timestamp while resuming ${source.displayName}.',
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
  if (platform.supportsImplicitSharedModelCache) {
    return DefaultModelDownloadManager.defaultSharedCacheDirectory(
      platform: platform,
      namespace: namespace,
    );
  }
  return _temporaryCacheDirectory(namespace: namespace);
}

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
