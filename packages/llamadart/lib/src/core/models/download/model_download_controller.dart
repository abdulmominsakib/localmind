import 'dart:async';

import '../../exceptions.dart';
import '../model_load_options.dart';
import '../model_source.dart';
import 'model_download_manager_base.dart';
import 'model_download_manager_stub.dart'
    if (dart.library.io) '../../../platform/io/model_download_manager_io.dart';

/// High-level lifecycle stage for an app-facing model download task.
enum ModelDownloadTaskStage {
  /// No task has started yet.
  idle,

  /// The source and task options are being prepared.
  resolving,

  /// The package-managed cache is being checked before network work starts.
  checkingCache,

  /// Remote bytes are being downloaded or cached by the manager.
  downloading,

  /// The manager is finalizing, verifying, or promoting the resolved file.
  verifying,

  /// The model is available as a [ModelCacheEntry].
  ready,

  /// The task failed with an actionable, redacted [ModelDownloadTaskSnapshot.errorMessage].
  failed,

  /// The task was cancelled cooperatively.
  cancelled,
}

/// Immutable app-facing state for a [ModelDownloadController].
class ModelDownloadTaskSnapshot {
  /// Creates a model download task snapshot.
  const ModelDownloadTaskSnapshot({
    required this.stage,
    this.source,
    this.entry,
    this.progress,
    this.errorMessage,
  });

  /// Initial idle snapshot.
  const ModelDownloadTaskSnapshot.idle()
    : stage = ModelDownloadTaskStage.idle,
      source = null,
      entry = null,
      progress = null,
      errorMessage = null;

  /// Current lifecycle stage.
  final ModelDownloadTaskStage stage;

  /// Source being resolved or downloaded, when a task has started.
  final ModelSource? source;

  /// Resolved cache entry after [stage] becomes [ModelDownloadTaskStage.ready].
  final ModelCacheEntry? entry;

  /// Latest byte-level progress reported by the underlying manager.
  final ModelDownloadProgress? progress;

  /// Redacted user-facing failure/cancellation message, when available.
  final String? errorMessage;

  /// Whether the task is actively doing asynchronous work.
  bool get isRunning {
    return switch (stage) {
      ModelDownloadTaskStage.resolving ||
      ModelDownloadTaskStage.checkingCache ||
      ModelDownloadTaskStage.downloading ||
      ModelDownloadTaskStage.verifying => true,
      _ => false,
    };
  }

  /// Whether [ModelDownloadController.retry] can retry this snapshot's source.
  bool get canRetry {
    return source != null &&
        (stage == ModelDownloadTaskStage.failed ||
            stage == ModelDownloadTaskStage.cancelled);
  }

  /// Best-known completion fraction, or null when unknown.
  double? get fraction {
    if (stage == ModelDownloadTaskStage.ready) {
      return 1.0;
    }
    return progress?.fraction;
  }
}

/// Small, dependency-free controller for app model download/cache UX.
///
/// The controller wraps a [ModelDownloadManager] and converts low-level cache
/// and byte progress callbacks into stable app states: resolving, cache check,
/// downloading, verifying, ready, failed, and cancelled. It intentionally uses
/// `dart:async` streams rather than Flutter types so it can be adapted to
/// `ValueNotifier`, `ChangeNotifier`, BLoC, Riverpod, or any other UI layer.
class ModelDownloadController {
  /// Creates a model download controller.
  ///
  /// When [manager] is omitted the platform default manager is used. On
  /// platforms without package-managed download support, starting a task emits a
  /// failed snapshot with the manager's unsupported-operation message.
  ModelDownloadController({ModelDownloadManager? manager})
    : manager = manager ?? DefaultModelDownloadManager();

  /// Low-level manager used to inspect caches and resolve/download models.
  final ModelDownloadManager manager;

  final StreamController<ModelDownloadTaskSnapshot> _snapshots =
      StreamController<ModelDownloadTaskSnapshot>.broadcast(sync: true);

  ModelDownloadTaskSnapshot _snapshot = const ModelDownloadTaskSnapshot.idle();
  ModelDownloadCancelToken? _cancelToken;
  ModelSource? _lastSource;
  ModelLoadOptions _lastOptions = ModelLoadOptions.defaults;
  bool _isDisposed = false;
  int _generation = 0;

  /// Latest snapshot, synchronously updated before each stream event is emitted.
  ModelDownloadTaskSnapshot get snapshot => _snapshot;

  /// Broadcast stream of task snapshots.
  Stream<ModelDownloadTaskSnapshot> get snapshots => _snapshots.stream;

  /// Starts resolving [source] with [options].
  ///
  /// Throws [StateError] when another task is already running. The returned
  /// future completes with the ready [ModelCacheEntry] or rethrows the manager's
  /// failure after emitting a failed/cancelled snapshot.
  Future<ModelCacheEntry> start(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
  }) {
    _throwIfDisposed();
    if (options.cancelToken != null) {
      throw ArgumentError.value(
        options.cancelToken,
        'options.cancelToken',
        'ModelDownloadController owns cancellation; call cancel() on the controller instead.',
      );
    }
    if (_snapshot.isRunning) {
      throw StateError('A model download task is already running.');
    }
    _lastSource = source;
    _lastOptions = options;
    final generation = _generation + 1;
    _generation = generation;
    final cancelToken = ModelDownloadCancelToken();
    _cancelToken = cancelToken;
    final effectiveOptions = _withCancelToken(options, cancelToken);
    return _run(generation, source, options, effectiveOptions, cancelToken);
  }

  /// Retries the last source with the last options passed to [start].
  Future<ModelCacheEntry> retry() {
    final source = _lastSource;
    if (source == null) {
      throw StateError('No model download task is available to retry.');
    }
    return start(source, options: _lastOptions);
  }

  /// Requests cooperative cancellation for the active task.
  void cancel() {
    _cancelToken?.cancel();
  }

  /// Cancels any active task and closes the snapshot stream.
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    cancel();
    await _snapshots.close();
  }

  Future<ModelCacheEntry> _run(
    int generation,
    ModelSource source,
    ModelLoadOptions originalOptions,
    ModelLoadOptions effectiveOptions,
    ModelDownloadCancelToken cancelToken,
  ) async {
    ModelDownloadProgress? latestProgress;
    try {
      _emit(
        generation,
        ModelDownloadTaskSnapshot(
          stage: ModelDownloadTaskStage.resolving,
          source: source,
        ),
      );
      _throwIfCancelled(cancelToken);

      final shouldCheckCache =
          source.isRemote &&
          originalOptions.cachePolicy != ModelCachePolicy.refresh &&
          originalOptions.cachePolicy != ModelCachePolicy.noCache;
      var cacheHit = false;
      if (shouldCheckCache) {
        _emit(
          generation,
          ModelDownloadTaskSnapshot(
            stage: ModelDownloadTaskStage.checkingCache,
            source: source,
          ),
        );
        final cached = await manager.get(
          source.cacheKey,
          cacheDirectory: originalOptions.cacheDirectory,
        );
        _throwIfCancelled(cancelToken);
        if (cached != null) {
          cacheHit = true;
        }
      }

      final shouldReportDownload =
          source.isRemote &&
          !cacheHit &&
          originalOptions.cachePolicy != ModelCachePolicy.cacheOnly;
      if (shouldReportDownload) {
        _emit(
          generation,
          ModelDownloadTaskSnapshot(
            stage: ModelDownloadTaskStage.downloading,
            source: source,
          ),
        );
      } else {
        _emit(
          generation,
          ModelDownloadTaskSnapshot(
            stage: ModelDownloadTaskStage.verifying,
            source: source,
          ),
        );
      }

      final entry = await manager.ensureModel(
        source,
        options: effectiveOptions,
        onProgress: (progress) {
          latestProgress = progress;
          _emit(
            generation,
            ModelDownloadTaskSnapshot(
              stage: ModelDownloadTaskStage.downloading,
              source: source,
              progress: progress,
            ),
          );
        },
      );
      _throwIfCancelled(cancelToken);

      if (_snapshot.stage != ModelDownloadTaskStage.verifying) {
        _emit(
          generation,
          ModelDownloadTaskSnapshot(
            stage: ModelDownloadTaskStage.verifying,
            source: source,
            progress: latestProgress,
          ),
        );
      }
      _emit(
        generation,
        ModelDownloadTaskSnapshot(
          stage: ModelDownloadTaskStage.ready,
          source: source,
          entry: entry,
          progress: latestProgress,
        ),
      );
      return entry;
    } catch (error) {
      if (_isCancelledError(cancelToken)) {
        _emit(
          generation,
          ModelDownloadTaskSnapshot(
            stage: ModelDownloadTaskStage.cancelled,
            source: source,
            progress: latestProgress,
            errorMessage: 'Download cancelled for ${source.displayName}.',
          ),
        );
      } else {
        _emit(
          generation,
          ModelDownloadTaskSnapshot(
            stage: ModelDownloadTaskStage.failed,
            source: source,
            progress: latestProgress,
            errorMessage: _redactedErrorMessage(error),
          ),
        );
      }
      rethrow;
    } finally {
      if (generation == _generation) {
        _cancelToken = null;
      }
    }
  }

  void _emit(int generation, ModelDownloadTaskSnapshot snapshot) {
    if (_isDisposed || generation != _generation) {
      return;
    }
    _snapshot = snapshot;
    _snapshots.add(snapshot);
  }

  void _throwIfDisposed() {
    if (_isDisposed) {
      throw StateError('ModelDownloadController has been disposed.');
    }
  }
}

ModelLoadOptions _withCancelToken(
  ModelLoadOptions options,
  ModelDownloadCancelToken cancelToken,
) {
  return ModelLoadOptions(
    cachePolicy: options.cachePolicy,
    cacheDirectory: options.cacheDirectory,
    sha256: options.sha256,
    bearerToken: options.bearerToken,
    headers: options.headers,
    cancelToken: cancelToken,
    resume: options.resume,
    maxRetries: options.maxRetries,
  );
}

void _throwIfCancelled(ModelDownloadCancelToken cancelToken) {
  if (cancelToken.isCancelled) {
    throw LlamaStateException('Model download was cancelled.');
  }
}

bool _isCancelledError(ModelDownloadCancelToken cancelToken) {
  return cancelToken.isCancelled;
}

String _redactedErrorMessage(Object error) {
  return error.toString().replaceAllMapped(_urlPattern, (match) {
    final value = match.group(0)!;
    final trailing = _trailingPunctuation.firstMatch(value)?.group(0) ?? '';
    final candidate = trailing.isEmpty
        ? value
        : value.substring(0, value.length - trailing.length);
    final uri = Uri.tryParse(candidate);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return '<redacted-url>$trailing';
    }
    final redacted = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    );
    return '${redacted.toString()}$trailing';
  });
}

final RegExp _urlPattern = RegExp(r'https?:\/\/\S+');
final RegExp _trailingPunctuation = RegExp(r'[.?!:\)\]\}>]+$');
