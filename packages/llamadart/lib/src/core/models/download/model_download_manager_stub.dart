import '../../exceptions.dart';
import 'model_download_manager_base.dart';

/// Non-IO placeholder for the package-managed model download manager.
class DefaultModelDownloadManager extends ThrowingModelDownloadManager {
  /// Creates a non-IO placeholder download manager.
  const DefaultModelDownloadManager({String? defaultCacheDirectory});

  /// Creates a non-IO placeholder for an automatic model cache manager.
  const DefaultModelDownloadManager.auto({
    String namespace = 'llamadart',
    String? cacheDirectory,
    String? appPrivateCacheDirectory,
    String? androidAppPrivateCacheDirectory,
    String? iosAppPrivateCacheDirectory,
    ModelCachePlatform? platform,
    Map<String, String>? environment,
    String? homeDirectory,
  });

  /// Creates a non-IO placeholder for a shared model cache manager.
  const DefaultModelDownloadManager.sharedCache({
    String namespace = 'llamadart',
    String? cacheDirectory,
    ModelCachePlatform? platform,
    Map<String, String>? environment,
    String? homeDirectory,
  });

  /// Creates a non-IO placeholder for an app-private model cache manager.
  const DefaultModelDownloadManager.appPrivate({
    required String cacheDirectory,
  });

  /// Creates a non-IO placeholder for a user-selected model library manager.
  const DefaultModelDownloadManager.userSelected({
    required String cacheDirectory,
  });

  /// Creates a non-IO placeholder for an app-group model cache manager.
  const DefaultModelDownloadManager.appGroup({required String cacheDirectory});

  /// Non-IO platforms do not expose a file-backed shared cache directory.
  static String defaultSharedCacheDirectory({
    String namespace = 'llamadart',
    ModelCachePlatform? platform,
    Map<String, String>? environment,
    String? homeDirectory,
  }) {
    throw LlamaUnsupportedException(
      'File-backed shared model cache directories are not supported on this platform.',
    );
  }

  /// Default cache root used when a per-call cache directory is absent.
  String get defaultCacheDirectory => throw LlamaUnsupportedException(
    'File-backed model cache directories are not supported on this platform.',
  );

  @override
  Object unsupported(String operation) => LlamaUnsupportedException(
    'Model download manager $operation is not supported on this platform.',
  );
}
