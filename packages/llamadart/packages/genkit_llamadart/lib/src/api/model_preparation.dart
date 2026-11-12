import 'dart:async';

import 'package:genkit/plugin.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;

import 'media_resolver.dart';
import 'prepared_model.dart';

/// High-level stage for preparing a `llamadart` model for Genkit.
enum LlamaModelPreparationStage {
  /// No work has started yet.
  idle,

  /// The source and load options are being resolved.
  resolving,

  /// The package-managed cache is being inspected.
  checkingCache,

  /// Remote model bytes are being downloaded.
  downloading,

  /// The resolved file is being verified or promoted into cache metadata.
  verifying,

  /// The Genkit plugin, model definition, and typed refs are being created.
  ///
  /// This stage does not load the native model; warm-up or inspection does.
  loading,

  /// Source resolution finished and a [LlamaPreparedModel] can be registered.
  ///
  /// Native model loading remains lazy until a request, warm-up, inspection
  /// or raw-text tokenization/counting.
  ready,

  /// Preparation failed.
  failed,

  /// Preparation was cancelled.
  cancelled,
}

/// Identifies which source a preparation snapshot is currently describing.
enum LlamaModelPreparationSourceRole {
  /// Primary model source.
  model,

  /// Optional multimodal projector source.
  mmproj,
}

/// Immutable state emitted by [LlamaModelPreparationTask.snapshots].
class LlamaModelPreparationSnapshot {
  /// Creates a preparation snapshot.
  const LlamaModelPreparationSnapshot({
    required this.stage,
    this.sourceRole,
    this.source,
    this.modelEntry,
    this.mmprojEntry,
    this.progress,
    this.preparedModel,
    this.errorMessage,
  });

  /// Initial idle snapshot.
  const LlamaModelPreparationSnapshot.idle()
    : stage = LlamaModelPreparationStage.idle,
      sourceRole = null,
      source = null,
      modelEntry = null,
      mmprojEntry = null,
      progress = null,
      preparedModel = null,
      errorMessage = null;

  /// Current lifecycle stage.
  final LlamaModelPreparationStage stage;

  /// Source role currently being resolved, downloaded, or verified.
  final LlamaModelPreparationSourceRole? sourceRole;

  /// Active model source for [sourceRole], when the stage is source-specific.
  final llama.ModelSource? source;

  /// Resolved primary model cache entry, when available.
  final llama.ModelCacheEntry? modelEntry;

  /// Resolved multimodal projector cache entry, when available.
  final llama.ModelCacheEntry? mmprojEntry;

  /// Latest byte-level progress from `llamadart`, when available.
  final llama.ModelDownloadProgress? progress;

  /// Prepared Genkit handle, set only when [stage] is
  /// [LlamaModelPreparationStage.ready].
  final LlamaPreparedModel? preparedModel;

  /// Redacted user-facing failure or cancellation message.
  ///
  /// Other snapshot fields can contain source URLs and local paths; select
  /// fields deliberately before logging or exporting a snapshot.
  final String? errorMessage;

  /// Whether this snapshot represents active asynchronous work.
  bool get isRunning {
    return switch (stage) {
      LlamaModelPreparationStage.resolving ||
      LlamaModelPreparationStage.checkingCache ||
      LlamaModelPreparationStage.downloading ||
      LlamaModelPreparationStage.verifying ||
      LlamaModelPreparationStage.loading => true,
      _ => false,
    };
  }

  /// Current source's download fraction, or null when unknown.
  ///
  /// This is not an aggregate across the model and projector. A ready task
  /// reports 1.0 even when the source was already cached.
  double? get fraction {
    if (stage == LlamaModelPreparationStage.ready) {
      return 1.0;
    }
    return progress?.fraction;
  }
}

/// Observable task for preparing a source-backed `llamadart` model.
///
/// The task starts on the next microtask after creation so callers can attach a
/// listener to [snapshots] before the first resolving snapshot is emitted.
/// The returned [result] owns the generated plugin/runtime resources; dispose
/// the resulting [LlamaPreparedModel] when the app is done using it.
class LlamaModelPreparationTask {
  LlamaModelPreparationTask._({
    required this._name,
    required this._source,
    required this._modelParams,
    required llama.ModelSource? mmprojSource,
    required this._options,
    required this._mmprojOptions,
    required llama.ModelDownloadManager manager,
    required this._supportsEmbeddings,
    required this._supportsTools,
    required this._supportsConstrainedOutput,
    required this._modelInfo,
    required Iterable<llama.LlamaEngineObserver> observers,
    required this._mediaResolver,
  }) : _mmprojSource = mmprojSource,
       _observers = List<llama.LlamaEngineObserver>.unmodifiable(observers),
       _modelController = llama.ModelDownloadController(manager: manager),
       _mmprojController = mmprojSource == null
           ? null
           : llama.ModelDownloadController(manager: manager) {
    _modelSubscription = _modelController.snapshots.listen(
      (snapshot) => _emitDownloadSnapshot(
        LlamaModelPreparationSourceRole.model,
        snapshot,
      ),
    );
    _mmprojSubscription = _mmprojController?.snapshots.listen(
      (snapshot) => _emitDownloadSnapshot(
        LlamaModelPreparationSourceRole.mmproj,
        snapshot,
      ),
    );
    scheduleMicrotask(_run);
  }

  final String _name;
  final llama.ModelSource _source;
  final llama.ModelParams _modelParams;
  final llama.ModelSource? _mmprojSource;
  final llama.ModelLoadOptions _options;
  final llama.ModelLoadOptions _mmprojOptions;
  final bool _supportsEmbeddings;
  final bool _supportsTools;
  final bool _supportsConstrainedOutput;
  final genkit.ModelInfo? _modelInfo;
  final LlamaDartMediaResolver? _mediaResolver;
  final List<llama.LlamaEngineObserver> _observers;
  final llama.ModelDownloadController _modelController;
  final llama.ModelDownloadController? _mmprojController;
  final Completer<LlamaPreparedModel> _completer =
      Completer<LlamaPreparedModel>();
  final StreamController<LlamaModelPreparationSnapshot> _snapshots =
      StreamController<LlamaModelPreparationSnapshot>.broadcast(sync: true);

  /// Future that completes with the prepared model or rethrows preparation
  /// failure/cancellation errors.
  late final Future<LlamaPreparedModel> result = _completer.future;
  late final StreamSubscription<llama.ModelDownloadTaskSnapshot>
  _modelSubscription;
  StreamSubscription<llama.ModelDownloadTaskSnapshot>? _mmprojSubscription;

  LlamaModelPreparationSnapshot _snapshot =
      const LlamaModelPreparationSnapshot.idle();
  llama.ModelCacheEntry? _modelEntry;
  llama.ModelCacheEntry? _mmprojEntry;
  bool _cancelRequested = false;
  bool _isDisposed = false;

  /// Latest snapshot, synchronously updated before stream events are emitted.
  LlamaModelPreparationSnapshot get snapshot => _snapshot;

  /// Broadcast stream of future preparation snapshots.
  ///
  /// This stream does not replay the latest value to new listeners. Read
  /// [snapshot] for initial UI state, then listen for changes.
  Stream<LlamaModelPreparationSnapshot> get snapshots => _snapshots.stream;

  /// Requests cooperative cancellation for the active preparation.
  void cancel() {
    _cancelRequested = true;
    _modelController.cancel();
    _mmprojController?.cancel();
  }

  /// Cancels active preparation and closes snapshot resources.
  ///
  /// Idempotent. Does not dispose a successfully returned [LlamaPreparedModel];
  /// the caller must dispose that handle separately. Pending [result] completes
  /// with a [StateError] when disposal interrupts preparation.
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    cancel();
    if (!_completer.isCompleted) {
      _completer.completeError(StateError('Model preparation task disposed.'));
    }
    _isDisposed = true;
    await _modelSubscription.cancel();
    await _mmprojSubscription?.cancel();
    await _modelController.dispose();
    await _mmprojController?.dispose();
    await _snapshots.close();
  }

  Future<void> _run() async {
    try {
      _throwIfCancelled();
      _modelEntry = await _modelController.start(_source, options: _options);
      _throwIfCancelled();

      final mmprojSource = _mmprojSource;
      if (mmprojSource != null) {
        final controller = _mmprojController!;
        _mmprojEntry = await controller.start(
          mmprojSource,
          options: _mmprojOptions,
        );
        _throwIfCancelled();
      }

      _emit(
        LlamaModelPreparationSnapshot(
          stage: LlamaModelPreparationStage.loading,
          modelEntry: _modelEntry,
          mmprojEntry: _mmprojEntry,
        ),
      );
      _throwIfCancelled();

      final preparedModel = createLlamaPreparedModel(
        name: _name,
        modelEntry: _modelEntry!,
        modelParams: _modelParams,
        mmprojEntry: _mmprojEntry,
        supportsEmbeddings: _supportsEmbeddings,
        supportsTools: _supportsTools,
        supportsConstrainedOutput: _supportsConstrainedOutput,
        modelInfo: _modelInfo,
        observers: _observers,
        mediaResolver: _mediaResolver,
      );

      _emit(
        LlamaModelPreparationSnapshot(
          stage: LlamaModelPreparationStage.ready,
          modelEntry: _modelEntry,
          mmprojEntry: _mmprojEntry,
          preparedModel: preparedModel,
        ),
      );
      if (!_completer.isCompleted) {
        _completer.complete(preparedModel);
      }
    } catch (error, stackTrace) {
      if (!_completer.isCompleted) {
        _completer.completeError(error, stackTrace);
      }
      if (!_isDisposed &&
          _snapshot.stage != LlamaModelPreparationStage.failed &&
          _snapshot.stage != LlamaModelPreparationStage.cancelled) {
        _emit(
          LlamaModelPreparationSnapshot(
            stage: _cancelRequested
                ? LlamaModelPreparationStage.cancelled
                : LlamaModelPreparationStage.failed,
            modelEntry: _modelEntry,
            mmprojEntry: _mmprojEntry,
            errorMessage: _cancelRequested
                ? 'Model preparation was cancelled.'
                : _redactedPreparationErrorMessage(error),
          ),
        );
      }
    }
  }

  void _emitDownloadSnapshot(
    LlamaModelPreparationSourceRole role,
    llama.ModelDownloadTaskSnapshot snapshot,
  ) {
    _emit(
      LlamaModelPreparationSnapshot(
        stage: _toPreparationStage(snapshot.stage),
        sourceRole: role,
        source: snapshot.source,
        modelEntry: role == LlamaModelPreparationSourceRole.model
            ? snapshot.entry ?? _modelEntry
            : _modelEntry,
        mmprojEntry: role == LlamaModelPreparationSourceRole.mmproj
            ? snapshot.entry ?? _mmprojEntry
            : _mmprojEntry,
        progress: snapshot.progress,
        errorMessage: _redactedNullableMessage(snapshot.errorMessage),
      ),
    );
  }

  void _emit(LlamaModelPreparationSnapshot snapshot) {
    if (_isDisposed || _snapshots.isClosed) {
      return;
    }
    _snapshot = snapshot;
    _snapshots.add(snapshot);
  }

  void _throwIfCancelled() {
    if (_cancelRequested) {
      throw llama.LlamaStateException('Model preparation was cancelled.');
    }
  }
}

LlamaModelPreparationStage _toPreparationStage(
  llama.ModelDownloadTaskStage stage,
) {
  return switch (stage) {
    llama.ModelDownloadTaskStage.idle => LlamaModelPreparationStage.idle,
    llama.ModelDownloadTaskStage.resolving =>
      LlamaModelPreparationStage.resolving,
    llama.ModelDownloadTaskStage.checkingCache =>
      LlamaModelPreparationStage.checkingCache,
    llama.ModelDownloadTaskStage.downloading =>
      LlamaModelPreparationStage.downloading,
    llama.ModelDownloadTaskStage.verifying ||
    llama.ModelDownloadTaskStage.ready => LlamaModelPreparationStage.verifying,
    llama.ModelDownloadTaskStage.failed => LlamaModelPreparationStage.failed,
    llama.ModelDownloadTaskStage.cancelled =>
      LlamaModelPreparationStage.cancelled,
  };
}

String _redactedPreparationErrorMessage(Object error) {
  final message = error is llama.LlamaException
      ? error.message
      : error.toString();
  return _redactSensitiveText(message);
}

String? _redactedNullableMessage(String? message) {
  if (message == null) {
    return null;
  }
  return _redactSensitiveText(message);
}

String _redactSensitiveText(String message) {
  final redactedFields = message
      .replaceAllMapped(_authorizationFieldPattern, _redactFieldMatch)
      .replaceAll(_bearerTokenPattern, 'Bearer <redacted>')
      .replaceAllMapped(_sensitiveFieldPattern, _redactFieldMatch);
  final redactedUrls = redactedFields.replaceAllMapped(_urlPattern, (match) {
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
  return redactedUrls.isEmpty ? 'Model preparation failed.' : redactedUrls;
}

String _redactFieldMatch(Match match) {
  return '${match.group(1)}${match.group(2)}<redacted>';
}

final RegExp _urlPattern = RegExp(r'https?:\/\/\S+');
final RegExp _trailingPunctuation = RegExp(r'[.?!:\)\]\}>]+$');
final RegExp _authorizationFieldPattern = RegExp(
  r'\b(authorization)\b(\s*[:=]\s*)[^,\]\}\r\n]+',
  caseSensitive: false,
);
final RegExp _bearerTokenPattern = RegExp(
  r'\bBearer\s+[A-Za-z0-9._~+/=-]+',
  caseSensitive: false,
);
final RegExp _sensitiveFieldPattern = RegExp(
  r'\b(cookie|set-cookie|x-api-key|api[-_]?key|access[-_]?token|refresh[-_]?token|id[-_]?token|token|sig|signature)\b(\s*[:=]\s*)[^,\s\]\}]+',
  caseSensitive: false,
);

/// Creates an observable model preparation task.
LlamaModelPreparationTask createLlamaModelPreparationTask({
  required String name,
  required llama.ModelSource source,
  llama.ModelParams modelParams = const llama.ModelParams(),
  llama.ModelSource? mmprojSource,
  llama.ModelLoadOptions options = llama.ModelLoadOptions.defaults,
  llama.ModelLoadOptions mmprojOptions = llama.ModelLoadOptions.defaults,
  llama.ModelDownloadManager? downloadManager,
  bool supportsEmbeddings = true,
  bool supportsTools = true,
  bool supportsConstrainedOutput = true,
  genkit.ModelInfo? modelInfo,
  Iterable<llama.LlamaEngineObserver> observers = const [],
  LlamaDartMediaResolver? mediaResolver,
}) {
  if (name.isEmpty) {
    throw ArgumentError.value(name, 'name', 'Model name must not be empty.');
  }

  return LlamaModelPreparationTask._(
    name: name,
    source: source,
    modelParams: modelParams,
    mmprojSource: mmprojSource,
    options: options,
    mmprojOptions: mmprojOptions,
    manager: downloadManager ?? llama.DefaultModelDownloadManager(),
    supportsEmbeddings: supportsEmbeddings,
    supportsTools: supportsTools,
    supportsConstrainedOutput: supportsConstrainedOutput,
    modelInfo: modelInfo,
    observers: observers,
    mediaResolver: mediaResolver,
  );
}
