/// Controls how model source resolution should interact with caches.
enum ModelCachePolicy {
  /// Use a cached model when available and download only when missing.
  preferCached,

  /// Refresh remote metadata/content even when a cached model exists.
  refresh,

  /// Require a cached model and fail when it is unavailable.
  cacheOnly,

  /// Do not reuse stable package-managed cache entries.
  ///
  /// File-backed download managers may still write the resolved model into a
  /// transient package-managed directory so native loaders can receive a local
  /// path and later cleanup can remove the temporary entry.
  noCache,
}

/// Cooperative cancellation token for model downloads and resolution.
class ModelDownloadCancelToken {
  bool _isCancelled = false;

  /// Whether [cancel] has been requested.
  bool get isCancelled => _isCancelled;

  /// Requests cancellation. Calling this method more than once is safe.
  void cancel() {
    _isCancelled = true;
  }
}

/// Options used when resolving and loading model sources.
///
/// Native/file-backed backends use the package-managed download/cache manager
/// for remote HTTP(S) and Hugging Face sources. Local [ModelSource.path(...)]
/// values are already files: only [sha256] verification and cancellation are
/// meaningful for them. Remote/download-only options such as authenticated
/// headers, explicit cache policies, cache directories, resume, and retries are
/// rejected for local paths. URL-loading web backends can load remote URLs
/// directly and reject options that require native cache IO, such as
/// authenticated headers, checksum verification, and explicit cache policy
/// changes.
class ModelLoadOptions {
  /// Creates model load options.
  factory ModelLoadOptions({
    ModelCachePolicy cachePolicy = ModelCachePolicy.preferCached,
    String? cacheDirectory,
    String? sha256,
    String? bearerToken,
    Map<String, String> headers = const <String, String>{},
    ModelDownloadCancelToken? cancelToken,
    bool resume = true,
    int maxRetries = 3,
  }) {
    if (maxRetries < 0) {
      throw ArgumentError.value(
        maxRetries,
        'maxRetries',
        'Maximum retry attempts must not be negative.',
      );
    }
    final normalizedSha256 = _normalizeSha256(sha256);
    return ModelLoadOptions._(
      cachePolicy: cachePolicy,
      cacheDirectory: cacheDirectory,
      sha256: normalizedSha256,
      bearerToken: bearerToken,
      headers: Map<String, String>.unmodifiable(headers),
      cancelToken: cancelToken,
      resume: resume,
      maxRetries: maxRetries,
    );
  }

  const ModelLoadOptions._({
    required this.cachePolicy,
    required this.headers,
    required this.resume,
    required this.maxRetries,
    this.cacheDirectory,
    this.sha256,
    this.bearerToken,
    this.cancelToken,
  });

  /// Compile-time default options for API default parameters.
  static const ModelLoadOptions defaults = ModelLoadOptions._(
    cachePolicy: ModelCachePolicy.preferCached,
    headers: <String, String>{},
    resume: true,
    maxRetries: 3,
  );

  /// Cache behavior for this load.
  final ModelCachePolicy cachePolicy;

  /// Optional package-managed cache directory override.
  final String? cacheDirectory;

  /// Optional expected SHA-256 checksum for the model file.
  ///
  /// Non-null values are validated as 64-character hexadecimal digests and
  /// normalized to lowercase.
  final String? sha256;

  /// Optional bearer token for authenticated remote model access.
  final String? bearerToken;

  /// Additional HTTP headers for remote model access.
  final Map<String, String> headers;

  /// Optional cancellation token for cooperative cancellation.
  final ModelDownloadCancelToken? cancelToken;

  /// Whether interrupted native downloads may be resumed with HTTP Range.
  final bool resume;

  /// Maximum retry attempts for native downloads.
  final int maxRetries;
}

String? _normalizeSha256(String? sha256) {
  if (sha256 == null) {
    return null;
  }
  final normalized = sha256.toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
    throw ArgumentError.value(
      sha256,
      'sha256',
      'SHA-256 checksum must be a 64-character hexadecimal string.',
    );
  }
  return normalized;
}
