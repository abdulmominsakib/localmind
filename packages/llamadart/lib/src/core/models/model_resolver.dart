import '../exceptions.dart';
import 'model_load_options.dart';
import 'model_source.dart';
import 'download/model_download_manager_base.dart';

/// Request data passed to a [ModelResolver].
class ModelResolveRequest {
  /// Creates a resolver request.
  const ModelResolveRequest({required this.options, this.onProgress});

  /// Load options for this resolution.
  final ModelLoadOptions options;

  /// Optional progress callback.
  final ModelDownloadProgressCallback? onProgress;
}

/// Resolves a [ModelSource] to a concrete load target for the engine.
abstract interface class ModelResolver {
  /// Resolves [source] using [request].
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  );
}

/// Concrete model target after source resolution.
sealed class ModelLoadTarget {
  const ModelLoadTarget();

  /// Whether this target points at a local model file.
  bool get isLocal;

  /// Whether this target points at a remote model URL.
  bool get isRemote => !isLocal;
}

/// A resolved local model file path.
class LocalModelFile extends ModelLoadTarget {
  /// Creates a local model file target.
  const LocalModelFile(this.path);

  /// Local filesystem path to pass to the native backend.
  final String path;

  @override
  bool get isLocal => true;
}

/// A resolved remote model URL.
class RemoteModelUrl extends ModelLoadTarget {
  /// Creates a remote model URL target.
  const RemoteModelUrl(this.url, {this.useBrowserCache = true});

  /// Remote URL suitable for backends that support URL loading.
  final Uri url;

  /// Whether web runtimes should allow the browser cache to participate.
  final bool useBrowserCache;

  @override
  bool get isLocal => false;
}

/// Minimal default resolver for Task 1-3 API foundation.
class DefaultModelResolver implements ModelResolver {
  /// Creates the default model resolver.
  const DefaultModelResolver();

  @override
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  ) async {
    if (request.options.cancelToken?.isCancelled ?? false) {
      throw LlamaStateException('Model source resolution was cancelled.');
    }
    if (source.isLocal) {
      return LocalModelFile(source.path!);
    }
    return RemoteModelUrl(source.resolvedUri!, useBrowserCache: true);
  }
}
