import '../../exceptions.dart';
import '../model_load_options.dart';
import '../model_source.dart';

/// Callback invoked with model download progress.
typedef ModelDownloadProgressCallback =
    void Function(ModelDownloadProgress progress);

/// Operating-system families relevant to model cache directory selection.
enum ModelCachePlatform {
  /// Android apps use app-specific storage by default and require explicit user
  /// or app-managed grants for cross-app model libraries.
  android,

  /// Fuchsia has no implicit package-defined shared model cache.
  fuchsia,

  /// iOS apps use sandboxed storage by default and require App Groups or
  /// user-picked files for sharing.
  ios,

  /// Linux desktop/server processes can use a per-user shared cache.
  linux,

  /// macOS desktop/server processes can use a per-user shared cache.
  macos,

  /// Windows desktop/server processes can use a per-user shared cache.
  windows,

  /// Browser runtimes use origin-scoped browser/runtime cache storage.
  web,

  /// Unknown platforms must not claim an implicit shared model cache.
  unknown;

  /// Parses a Dart `Platform.operatingSystem` style value.
  static ModelCachePlatform parse(String operatingSystem) {
    switch (operatingSystem.toLowerCase()) {
      case 'android':
        return ModelCachePlatform.android;
      case 'fuchsia':
        return ModelCachePlatform.fuchsia;
      case 'ios':
        return ModelCachePlatform.ios;
      case 'linux':
        return ModelCachePlatform.linux;
      case 'macos':
        return ModelCachePlatform.macos;
      case 'windows':
        return ModelCachePlatform.windows;
      case 'web':
        return ModelCachePlatform.web;
      default:
        return ModelCachePlatform.unknown;
    }
  }

  /// Whether this platform is a phone/tablet OS with app sandboxing by default.
  bool get isMobile {
    return this == ModelCachePlatform.android || this == ModelCachePlatform.ios;
  }

  /// Whether `llamadart` can choose a per-user shared cache root without app or
  /// user-specific storage grants.
  bool get supportsImplicitSharedModelCache {
    return this == ModelCachePlatform.linux ||
        this == ModelCachePlatform.macos ||
        this == ModelCachePlatform.windows;
  }
}

/// Progress information for a package-managed model download.
class ModelDownloadProgress {
  /// Creates download progress information.
  const ModelDownloadProgress({required this.receivedBytes, this.totalBytes})
    : _fraction = null;

  /// Creates progress information when only a completion fraction is known.
  const ModelDownloadProgress.fraction(double fraction)
    : receivedBytes = 0,
      totalBytes = null,
      _fraction = fraction;

  /// Bytes received so far.
  final int receivedBytes;

  /// Total expected bytes, when known.
  final int? totalBytes;

  final double? _fraction;

  /// Download completion fraction clamped to `[0, 1]`, or null if unknown.
  double? get fraction {
    final knownFraction = _fraction;
    if (knownFraction != null) {
      if (knownFraction < 0) {
        return 0;
      }
      if (knownFraction > 1) {
        return 1;
      }
      return knownFraction;
    }
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    final value = receivedBytes / total;
    if (value < 0) {
      return 0;
    }
    if (value > 1) {
      return 1;
    }
    return value;
  }
}

/// Metadata describing a package-managed cached model file.
class ModelCacheEntry {
  /// Creates cache metadata for a model file.
  factory ModelCacheEntry({
    /// Raw canonical source key used to derive [cacheKey].
    ///
    /// The stored [sourceCanonicalKey] value is sanitized for metadata by
    /// redacting URL secrets and appending the deterministic cache key.
    required String sourceCanonicalKey,
    required String cacheKey,
    required String fileName,
    required String filePath,
    required DateTime createdAt,
    required DateTime updatedAt,
    int? bytes,
    String? sha256,
    String? etag,
    String? lastModified,
    DateTime? expiresAt,
  }) {
    return ModelCacheEntry._(
      sourceCanonicalKey: _metadataSafeSourceKey(sourceCanonicalKey, cacheKey),
      cacheKey: cacheKey,
      fileName: _validatedCacheFileName(fileName),
      filePath: _validatedCacheFilePath(filePath),
      bytes: bytes,
      sha256: sha256,
      etag: etag,
      lastModified: lastModified,
      createdAt: createdAt,
      updatedAt: updatedAt,
      expiresAt: expiresAt,
    );
  }

  const ModelCacheEntry._({
    required this.sourceCanonicalKey,
    required this.cacheKey,
    required this.fileName,
    required this.filePath,
    required this.createdAt,
    required this.updatedAt,
    this.bytes,
    this.sha256,
    this.etag,
    this.lastModified,
    this.expiresAt,
  });

  /// Creates cache metadata from a JSON map using snake_case keys.
  factory ModelCacheEntry.fromJson(Map<String, Object?> json) {
    return ModelCacheEntry(
      sourceCanonicalKey: _requiredString(json, 'source_canonical_key'),
      cacheKey: _requiredString(json, 'cache_key'),
      fileName: _requiredString(json, 'file_name'),
      filePath: _requiredString(json, 'file_path'),
      bytes: _optionalInt(json['bytes']),
      sha256: json['sha256'] as String?,
      etag: json['etag'] as String?,
      lastModified: json['last_modified'] as String?,
      createdAt: _requiredDateTime(json, 'created_at'),
      updatedAt: _requiredDateTime(json, 'updated_at'),
      expiresAt: _optionalDateTime(json['expires_at']),
    );
  }

  /// Metadata-safe source identity that produced this cached model.
  ///
  /// For URL-backed sources this is not the raw canonical key: query strings,
  /// fragments, and user info are redacted before persistence, and [cacheKey]
  /// is appended so distinct secret-bearing URLs remain distinguishable without
  /// leaking those secrets into cache metadata.
  final String sourceCanonicalKey;

  /// Deterministic cache key derived from the raw canonical source key.
  final String cacheKey;

  /// Cached model file name.
  final String fileName;

  /// Full path to the cached model file.
  final String filePath;

  /// Optional model file byte length.
  final int? bytes;

  /// Optional model file SHA-256 checksum.
  final String? sha256;

  /// Optional HTTP ETag associated with this model.
  final String? etag;

  /// Optional HTTP Last-Modified value associated with this model.
  final String? lastModified;

  /// Creation timestamp for this cache entry.
  final DateTime createdAt;

  /// Last update timestamp for this cache entry.
  final DateTime updatedAt;

  /// Optional expiration timestamp for this cache entry.
  final DateTime? expiresAt;

  /// Converts this entry to JSON using snake_case keys.
  Map<String, Object?> toJson() => <String, Object?>{
    'source_canonical_key': sourceCanonicalKey,
    'cache_key': cacheKey,
    'file_name': fileName,
    'file_path': filePath,
    if (bytes != null) 'bytes': bytes,
    if (sha256 != null) 'sha256': sha256,
    if (etag != null) 'etag': etag,
    if (lastModified != null) 'last_modified': lastModified,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
  };
}

/// Public API for package-managed model cache/download implementations.
abstract interface class ModelDownloadManager {
  /// Ensures [source] is available as a local cache entry.
  ///
  /// Implementations may serialize stable remote downloads for the same cache
  /// entry so concurrent callers do not race on shared partial files or
  /// metadata. Cancelling one waiting caller must not cancel another caller's
  /// active download; cooperative cancellation may be observed after the active
  /// same-entry operation finishes.
  ///
  /// Local path sources are already available as files. Native/file-backed
  /// implementations may verify a caller-provided SHA-256 checksum before
  /// returning metadata, but should reject remote/cache-only options that cannot
  /// affect local files instead of silently ignoring them.
  ///
  /// Native/file-backed implementations may recover package-managed metadata
  /// when the completed model file is still present in the deterministic cache
  /// directory, but should treat missing files, source mismatches, byte-count
  /// mismatches, and checksum mismatches as cache misses rather than returning
  /// stale entries.
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  });

  /// Lists all known package-managed cache entries under [cacheDirectory],
  /// including transient `noCache` entries that remain until explicitly
  /// cleared or pruned.
  ///
  /// Malformed or unsupported metadata entries may be ignored so one corrupt
  /// cache directory does not make cache inspection unusable.
  ///
  /// When [cacheDirectory] is omitted, the manager's default cache root is used.
  Future<List<ModelCacheEntry>> list({String? cacheDirectory});

  /// Gets a cached model entry by [cacheKey], if present under [cacheDirectory].
  ///
  /// Malformed or unsupported metadata entries may be ignored so one corrupt
  /// cache directory does not block lookup of other candidates.
  ///
  /// When [cacheDirectory] is omitted, the manager's default cache root is used.
  Future<ModelCacheEntry?> get(String cacheKey, {String? cacheDirectory});

  /// Removes cached model entries by [cacheKey] under [cacheDirectory].
  ///
  /// When [cacheDirectory] is omitted, the manager's default cache root is used.
  Future<void> remove(String cacheKey, {String? cacheDirectory});

  /// Clears all package-managed cached model entries under [cacheDirectory],
  /// including transient `noCache` entries.
  ///
  /// When [cacheDirectory] is omitted, the manager's default cache root is used.
  Future<void> clear({String? cacheDirectory});

  /// Prunes cached model entries, including transient `noCache` entries, and
  /// returns removed entries.
  ///
  /// When [cacheDirectory] is omitted, the manager's default cache root is used.
  Future<List<ModelCacheEntry>> prune({
    Duration? maxAge,
    int? maxBytes,
    String? cacheDirectory,
  });
}

/// Base implementation for download managers that do not implement IO yet.
abstract class ThrowingModelDownloadManager implements ModelDownloadManager {
  /// Creates a throwing model download manager.
  const ThrowingModelDownloadManager();

  /// Exception thrown by unsupported operations.
  Object unsupported(String operation) => LlamaUnsupportedException(
    'Model downloads are not supported by this implementation: $operation.',
  );

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    throw unsupported('ensureModel');
  }

  @override
  Future<List<ModelCacheEntry>> list({String? cacheDirectory}) async {
    throw unsupported('list');
  }

  @override
  Future<ModelCacheEntry?> get(
    String cacheKey, {
    String? cacheDirectory,
  }) async {
    throw unsupported('get');
  }

  @override
  Future<void> remove(String cacheKey, {String? cacheDirectory}) async {
    throw unsupported('remove');
  }

  @override
  Future<void> clear({String? cacheDirectory}) async {
    throw unsupported('clear');
  }

  @override
  Future<List<ModelCacheEntry>> prune({
    Duration? maxAge,
    int? maxBytes,
    String? cacheDirectory,
  }) async {
    throw unsupported('prune');
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw ArgumentError.value(json, 'json', 'Missing required string: $key.');
  }
  return value;
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw ArgumentError.value(
      json,
      'json',
      'Missing required timestamp: $key.',
    );
  }
  return DateTime.parse(value);
}

DateTime? _optionalDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw ArgumentError.value(value, 'value', 'Expected ISO-8601 timestamp.');
  }
  return DateTime.parse(value);
}

int? _optionalInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! int) {
    throw ArgumentError.value(value, 'value', 'Expected integer.');
  }
  return value;
}

String _metadataSafeSourceKey(String sourceCanonicalKey, String cacheKey) {
  final isUrlKey = sourceCanonicalKey.startsWith('url:');
  final candidate = isUrlKey
      ? sourceCanonicalKey
            .substring('url:'.length)
            .split('#')
            .first
            .split(RegExp(r'\s'))
            .first
      : sourceCanonicalKey;

  final uri = Uri.tryParse(candidate);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return isUrlKey ? 'url:<redacted>#cacheKey=$cacheKey' : sourceCanonicalKey;
  }

  final redactedUri = Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  );
  return 'url:${redactedUri.toString()}#cacheKey=$cacheKey';
}

String _validatedCacheFileName(String fileName) {
  final decoded = _decodeCacheComponent(fileName, 'fileName');
  if (decoded.isEmpty ||
      decoded == '.' ||
      decoded == '..' ||
      decoded.contains('/') ||
      decoded.contains('\\')) {
    throw ArgumentError.value(
      fileName,
      'fileName',
      'Cache fileName must be a safe basename.',
    );
  }
  return decoded;
}

String _decodeCacheComponent(String value, String name) {
  try {
    return Uri.decodeComponent(value);
  } on FormatException catch (error) {
    throw ArgumentError.value(
      value,
      name,
      'Cache $name contains invalid percent-encoding: ${error.message}',
    );
  }
}

String _validatedCacheFilePath(String filePath) {
  if (filePath.isEmpty) {
    throw ArgumentError.value(
      filePath,
      'filePath',
      'Cache filePath must not be empty.',
    );
  }
  final decodedPath = _decodeCacheComponent(filePath, 'filePath');
  final normalizedForValidation = decodedPath.replaceAll('\\', '/');
  for (final segment in normalizedForValidation.split('/')) {
    if (segment.isEmpty) {
      continue;
    }
    if (segment == '.' || segment == '..') {
      throw ArgumentError.value(
        filePath,
        'filePath',
        'Cache filePath must not contain traversal segments.',
      );
    }
  }
  return decodedPath;
}
