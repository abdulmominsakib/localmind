import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logger/app_logger.dart';
import 'models/on_device_model.dart';

abstract interface class OnDeviceInferenceSession {
  Future<void> addQueryChunk(Message message);

  Stream<ModelResponse> generateChatResponseAsync();

  Future<void> stopGeneration();

  Future<void> close();
}

abstract interface class OnDeviceInferenceService {
  bool get isLoaded;
  bool get currentModelSupportsVision;
  bool get supportsChatSessionReuse;

  Future<OnDeviceInferenceSession> createChat({
    String? systemInstruction,
    List<Tool> tools,
    bool? supportImage,
  });

  /// Rebuilds the native engine after a failed inference left it unusable.
  Future<void> recoverAfterInferenceFailure();
}

/// Whether [error] indicates the native LiteRT engine is left in a broken
/// state (e.g. after the KV cache overflowed), so later chats on the same
/// model instance would keep failing until it is reloaded.
bool isCorruptedOnDeviceEngineError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('failed to invoke the compiled model') ||
      message.contains('per_layer_embedding_lookup') ||
      message.contains('failed_precondition') ||
      message.contains('internal: error');
}

/// How long a teardown waits for a stopped native generation to wind down
/// before closing its conversation anyway.
const onDeviceGenerationDrainTimeout = Duration(seconds: 5);

/// Keeps native teardown off a generation that is still running.
///
/// Closing a LiteRT conversation that is still decoding blocks the calling
/// thread in `ThreadedExecutionManager::WaitUntilSessionDone` until the decode
/// drains, which on the UI isolate is an ANR. Cancelling the consumer's
/// subscription doesn't wait either: native keeps decoding until it notices
/// the cancel. So a cancel or [close] here asks native to stop, keeps
/// listening until the stream really ends (or [drainTimeout] passes), and only
/// then lets the conversation be deleted.
@visibleForTesting
class DrainingInferenceSession implements OnDeviceInferenceSession {
  DrainingInferenceSession(
    this._inner, {
    this.drainTimeout = onDeviceGenerationDrainTimeout,
    this.onGeneratingChanged,
    this.onClosed,
  });

  final OnDeviceInferenceSession _inner;
  final Duration drainTimeout;
  final void Function(bool generating)? onGeneratingChanged;
  final VoidCallback? onClosed;
  _NativeGeneration? _generation;
  bool _isClosed = false;

  bool get isGenerating => _generation != null;

  @override
  Future<void> addQueryChunk(Message message) => _inner.addQueryChunk(message);

  @override
  Stream<ModelResponse> generateChatResponseAsync() {
    late final StreamController<ModelResponse> controller;
    _NativeGeneration? generation;

    void settle() {
      final current = generation;
      if (current == null || current.done.isCompleted) return;
      current.done.complete();
      if (identical(_generation, current)) _generation = null;
      onGeneratingChanged?.call(false);
    }

    controller = StreamController<ModelResponse>(
      onListen: () {
        final current = generation = _generation = _NativeGeneration(settle);
        onGeneratingChanged?.call(true);
        try {
          current.subscription = _inner.generateChatResponseAsync().listen(
            controller.add,
            onError: controller.addError,
            onDone: () {
              settle();
              controller.close();
            },
          );
        } catch (error, stackTrace) {
          settle();
          controller.addError(error, stackTrace);
          controller.close();
        }
      },
      // Returning the drain makes the consumer's `cancel()` wait for native to
      // stop, so whatever it closes next doesn't block on a live decode.
      onCancel: () {
        final current = generation;
        if (current == null || current.done.isCompleted) return null;
        return _drain(current);
      },
    );
    return controller.stream;
  }

  @override
  Future<void> stopGeneration() => _inner.stopGeneration();

  /// Stops a running generation and waits for native to wind it down.
  Future<void> drain() {
    final current = _generation;
    if (current == null) return Future.value();
    return _drain(current);
  }

  Future<void> _drain(_NativeGeneration generation) {
    return generation.draining ??= () async {
      try {
        await _inner.stopGeneration();
      } catch (error) {
        Log.warning('Error stopping on-device generation: $error');
      }
      try {
        await generation.done.future.timeout(drainTimeout);
      } on TimeoutException {
        Log.warning(
          'On-device generation did not stop within '
          '${drainTimeout.inSeconds}s; closing it anyway',
        );
        final subscription = generation.subscription;
        generation.subscription = null;
        generation.settle();
        await subscription?.cancel();
      }
    }();
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    try {
      await drain();
      await _inner.close();
    } finally {
      onClosed?.call();
    }
  }
}

class _NativeGeneration {
  _NativeGeneration(this.settle);

  final VoidCallback settle;
  final Completer<void> done = Completer<void>();
  StreamSubscription<ModelResponse>? subscription;
  Future<void>? draining;
}

class _GemmaInferenceSession implements OnDeviceInferenceSession {
  _GemmaInferenceSession(this._chat);

  final InferenceChat _chat;

  @override
  Future<void> addQueryChunk(Message message) => _chat.addQueryChunk(message);

  @override
  Stream<ModelResponse> generateChatResponseAsync() =>
      _chat.generateChatResponseAsync();

  @override
  Future<void> stopGeneration() => _chat.stopGeneration();

  @override
  Future<void> close() => _chat.close();
}

class OnDeviceGemmaService implements OnDeviceInferenceService {
  OnDeviceGemmaService({this.onNativeWorkChanged});

  /// Total token budget (prompt + history + output) used when the caller
  /// doesn't pass one.
  static const defaultMaxTokens = 4096;

  /// Called with true when a native generation starts while none was running,
  /// and with false once the last one has wound down. Android uses it to end
  /// the process before its Flutter engine is torn down under a live decode.
  final void Function(bool active)? onNativeWorkChanged;

  final Set<DrainingInferenceSession> _sessions = {};
  int _liveGenerations = 0;

  InferenceModel? _model;
  String? _currentModelId;
  PreferredBackend? _currentBackend;
  int _currentMaxTokens = defaultMaxTokens;
  bool _isDisposed = false;
  Future<void>? _recoveryFuture;

  InferenceModel? get activeModel => _model;
  String? get currentModelId => _currentModelId;
  @override
  bool get currentModelSupportsVision {
    final id = _currentModelId;
    if (id == null) return false;
    final model = OnDeviceModel.allCuratedModels
        .where((m) => m.id == id || m.fileName == id)
        .firstOrNull;
    return model?.supportsVision ?? false;
  }

  @override
  bool get isLoaded => _model != null && !_isDisposed;

  @override
  bool get supportsChatSessionReuse =>
      _model != null && _model!.fileType != ModelFileType.builtIn;
  bool get isDisposed => _isDisposed;

  /// The filename of the model restored by the native model manager on app
  /// restart (e.g. "Qwen3-0.6B.litertlm"), or null if no active model spec is
  /// set. This is a cheap synchronous read that does NOT load the engine.
  String? get restoredActiveModelName => FlutterGemma.activeModelSpec?.name;

  /// Syncs the service's internal tracking to the native restored active model
  /// spec so that [createChat] can lazy-load the model on first use after a
  /// restart. Sets both [_currentModelId] and [_currentBackend] so the
  /// lazy-load path in [createChat] can actually trigger.
  void syncFromRestoredSpec(PreferredBackend backend, {int? maxTokens}) {
    final specName = restoredActiveModelName;
    if (specName == null) return;

    final model = OnDeviceModel.allCuratedModels.firstWhere(
      (m) => m.fileName == specName || m.id == specName,
      orElse: () => throw StateError('No curated model for $specName'),
    );

    _currentModelId = model.id;
    _currentBackend = backend;
    if (maxTokens != null) _currentMaxTokens = maxTokens;
  }

  static Future<void> initialize({String? huggingFaceToken}) async {
    await FlutterGemma.initialize(
      inferenceEngines: const [LiteRtLmEngine(), BuiltInAiEngine()],
      huggingFaceToken: huggingFaceToken,
      maxDownloadRetries: 10,
    );
  }

  Future<void> installModel(
    OnDeviceModel model, {
    void Function(int)? onProgress,
    String? token,
  }) async {
    if (model.isBuiltIn) {
      Log.info('Installing built-in model ${model.id}');
      await BuiltInAi.ensureReady(onProgress: onProgress);
      await FlutterGemma.installModel(
        modelType: ModelType.general,
        fileType: ModelFileType.builtIn,
      ).fromBundled(model.fileName).install();
      Log.info('Built-in model ${model.id} ready');
      return;
    }

    Log.info('Installing model ${model.id} from ${model.huggingFaceUrl}');

    await FlutterGemma.installModel(
          modelType: model.flutterGemmaModelType,
          fileType: ModelFileType.litertlm,
        )
        .fromNetwork(model.huggingFaceUrl, token: token, foreground: true)
        .withProgress((progress) {
          onProgress?.call(progress);
        })
        .install();

    Log.info('Model ${model.id} installed successfully');
  }

  Future<bool> isModelInstalled(String modelId) async {
    final model = OnDeviceModel.allCuratedModels.firstWhere(
      (m) => m.id == modelId || m.fileName == modelId,
      orElse: () => throw Exception('Model not found: $modelId'),
    );
    if (model.isBuiltIn) {
      try {
        final availability = await BuiltInAi.availability();
        if (availability == BuiltInAiAvailability.available) {
          return true;
        }
      } catch (_) {}
    }
    return FlutterGemma.isModelInstalled(model.fileName);
  }

  Future<List<String>> getInstalledModelIds() async {
    final installed = await FlutterGemma.listInstalledModels();
    final installedSet = installed.toSet();
    final installedIds = <String>[];

    for (final model in OnDeviceModel.allCuratedModels) {
      if (installedSet.contains(model.fileName)) {
        installedIds.add(model.id);
      }
    }
    return installedIds;
  }

  Future<void> deleteModel(String modelId) async {
    final model = OnDeviceModel.allCuratedModels.firstWhere(
      (m) => m.id == modelId || m.fileName == modelId,
      orElse: () => throw Exception('Model not found: $modelId'),
    );
    await FlutterGemma.uninstallModel(model.fileName);

    if (model.isBuiltIn) {
      Log.info('Built-in model $modelId uninstalled');
      return;
    }

    // Also clean up old custom download location if it exists
    try {
      final dir = await getApplicationSupportDirectory();
      final oldFile = File('${dir.path}/on_device_models/$modelId.litertlm');
      if (await oldFile.exists()) {
        await oldFile.delete();
        Log.info('Cleaned up old model file: ${oldFile.path}');
      }
    } catch (e) {
      Log.error('Error cleaning up old model file: $e');
    }

    Log.info('Model $modelId deleted');
  }

  Future<void> loadModel(
    String modelId,
    PreferredBackend backend, {
    int? maxTokens,
  }) async {
    final effectiveMaxTokens = maxTokens ?? _currentMaxTokens;
    if (_isDisposed) {
      throw StateError('OnDeviceGemmaService has been disposed');
    }

    if (_model != null &&
        _currentModelId == modelId &&
        _currentBackend == backend &&
        _currentMaxTokens == effectiveMaxTokens) {
      return;
    }

    if (_model != null) {
      await unloadModel();
    }

    Log.info(
      'Loading model $modelId with backend=$backend, '
      'maxTokens=$effectiveMaxTokens',
    );

    final model = OnDeviceModel.allCuratedModels.firstWhere(
      (m) => m.id == modelId || m.fileName == modelId,
      orElse: () => throw Exception('Model not found: $modelId'),
    );

    final InferenceModelSpec spec;
    if (model.isBuiltIn) {
      await BuiltInAi.ensureReady();
      final installed = await FlutterGemma.isModelInstalled(model.fileName);
      if (!installed) {
        await FlutterGemma.installModel(
          modelType: ModelType.general,
          fileType: ModelFileType.builtIn,
        ).fromBundled(model.fileName).install();
      }
      spec = InferenceModelSpec(
        name: model.fileName,
        modelSource: ModelSource.bundled(model.fileName),
        modelType: ModelType.general,
        fileType: ModelFileType.builtIn,
      );
    } else {
      spec = InferenceModelSpec(
        name: model.fileName,
        modelSource: ModelSource.network(model.huggingFaceUrl),
        modelType: model.flutterGemmaModelType,
        fileType: ModelFileType.litertlm,
      );
    }

    FlutterGemmaPlugin.instance.modelManager.setActiveModel(spec);

    _model = await FlutterGemma.getActiveModel(
      maxTokens: effectiveMaxTokens,
      preferredBackend: backend,
      supportImage: model.supportsVision,
      maxNumImages: model.supportsVision ? 5 : null,
    );
    _currentModelId = modelId;
    _currentBackend = backend;
    _currentMaxTokens = effectiveMaxTokens;

    Log.info('Model $modelId loaded successfully');
  }

  @override
  Future<OnDeviceInferenceSession> createChat({
    String? systemInstruction,
    List<Tool> tools = const [],
    bool? supportImage,
  }) async {
    await _ensureModelLoaded();

    try {
      return await _openChat(
        systemInstruction: systemInstruction,
        tools: tools,
        supportImage: supportImage,
      );
    } catch (e) {
      if (!_isClosedClientError(e) && !isCorruptedOnDeviceEngineError(e)) {
        rethrow;
      }

      Log.warning(
        'Gemma model unusable while opening a chat ($e). '
        'Reloading the model once.',
      );
      await _recoverClosedModel();
      return _openChat(
        systemInstruction: systemInstruction,
        tools: tools,
        supportImage: supportImage,
      );
    }
  }

  Future<void> _ensureModelLoaded() async {
    if (_model != null) return;
    if (_currentModelId == null || _currentBackend == null) {
      throw StateError('Model not loaded. Call loadModel first.');
    }
    await loadModel(_currentModelId!, _currentBackend!);
  }

  Future<OnDeviceInferenceSession> _openChat({
    required String? systemInstruction,
    required List<Tool> tools,
    bool? supportImage,
  }) async {
    final visionEnabled = currentModelSupportsVision && (supportImage ?? true);
    // createChat() keeps one native conversation per model and deletes the
    // previous one first, so a reply still decoding there must stop before.
    if (_model!.fileType != ModelFileType.builtIn && visionEnabled) {
      await _drainGenerations();
    }
    final model = _model!;

    final InferenceChat chat;
    if (model.fileType == ModelFileType.builtIn) {
      chat = await model.createChat(
        systemInstruction: systemInstruction,
        tools: tools,
        supportsFunctionCalls: tools.isNotEmpty,
        supportImage: visionEnabled,
      );
    } else if (visionEnabled) {
      // Multimodal .litertlm models MUST use createChat() (single-session)
      // because openChat() (virtual concurrent session) rejects media.
      chat = await model.createChat(
        systemInstruction: systemInstruction,
        tools: tools,
        supportsFunctionCalls: tools.isNotEmpty,
        supportImage: true,
      );
    } else {
      chat = await model.openChat(
        systemInstruction: systemInstruction,
        tools: tools,
        supportsFunctionCalls: tools.isNotEmpty,
      );
    }
    late final DrainingInferenceSession session;
    session = DrainingInferenceSession(
      _GemmaInferenceSession(chat),
      onGeneratingChanged: _onGeneratingChanged,
      onClosed: () => _sessions.remove(session),
    );
    _sessions.add(session);
    return session;
  }

  void _onGeneratingChanged(bool generating) {
    final wasActive = _liveGenerations > 0;
    _liveGenerations += generating ? 1 : -1;
    if (_liveGenerations < 0) _liveGenerations = 0;
    final isActive = _liveGenerations > 0;
    if (wasActive != isActive) onNativeWorkChanged?.call(isActive);
  }

  /// Stops every running generation and waits for native to wind it down, so
  /// the conversation or engine close that follows doesn't block the UI
  /// isolate on a live decode.
  Future<void> _drainGenerations() async {
    await Future.wait(_sessions.toList().map((session) => session.drain()));
  }

  bool _isClosedClientError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('client shut down') ||
        message.contains('model is closed') ||
        message.contains('model was closed');
  }

  @override
  Future<void> recoverAfterInferenceFailure() {
    if (_isDisposed || _currentModelId == null || _currentBackend == null) {
      return Future.value();
    }
    Log.warning('Reloading on-device model after a native inference failure');
    return _recoverClosedModel();
  }

  Future<void> _recoverClosedModel() {
    final existing = _recoveryFuture;
    if (existing != null) return existing;

    final modelId = _currentModelId;
    final backend = _currentBackend;
    if (modelId == null || backend == null) {
      return Future.error(
        StateError('Cannot recover on-device model without a selected model'),
      );
    }

    final recovery = () async {
      final staleModel = _model;
      if (staleModel != null) {
        await _drainGenerations();
        _sessions.clear();
        try {
          await staleModel.close();
        } catch (error) {
          Log.warning('Error awaiting stale Gemma model shutdown: $error');
        }
      }
      _model = null;
      await loadModel(modelId, backend, maxTokens: _currentMaxTokens);
    }();

    _recoveryFuture = recovery;
    return recovery.whenComplete(() {
      if (identical(_recoveryFuture, recovery)) {
        _recoveryFuture = null;
      }
    });
  }

  Future<void> unloadModel() async {
    if (_model != null) {
      await _drainGenerations();
      _sessions.clear();
      try {
        await _model!.close();
      } catch (e) {
        Log.error('Error closing model: $e');
      }
      _model = null;
      _currentModelId = null;
      _currentBackend = null;
    }
  }

  void dispose() {
    _isDisposed = true;
    unloadModel();
  }

  /// Migrate models from old custom download location to flutter_gemma storage.
  /// Returns the number of models migrated.
  static Future<int> migrateOldModels() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final oldModelsDir = Directory('${dir.path}/on_device_models');
      if (!await oldModelsDir.exists()) return 0;

      int migrated = 0;
      final entities = await oldModelsDir.list().toList();
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.litertlm')) {
          final fileName = entity.path.split('/').last;
          final modelId = fileName.replaceAll('.litertlm', '');

          // Check if already registered in flutter_gemma
          final alreadyInstalled = await FlutterGemma.isModelInstalled(
            fileName,
          );
          if (alreadyInstalled) continue;

          // Register the existing file with flutter_gemma
          try {
            await FlutterGemma.installModel(
              modelType: _inferModelType(modelId),
              fileType: ModelFileType.litertlm,
            ).fromFile(entity.path).install();
            migrated++;
            Log.info('Migrated model $modelId from ${entity.path}');
          } catch (e) {
            Log.error('Failed to migrate model $modelId: $e');
          }
        }
      }

      if (migrated > 0) {
        Log.info('Migrated $migrated models from old storage');
      }
      return migrated;
    } catch (e) {
      Log.error('Error during model migration: $e');
      return 0;
    }
  }

  static ModelType _inferModelType(String modelId) {
    switch (modelId) {
      case 'qwen3-0.6b':
        return ModelType.qwen3;
      case 'qwen2.5-1.5b-instruct':
        return ModelType.qwen;
      case 'deepseek-r1-distill-qwen-1.5b':
        return ModelType.deepSeek;
      case 'gemma4-e2b-instruct':
        return ModelType.gemma4;
      default:
        return ModelType.general;
    }
  }
}
