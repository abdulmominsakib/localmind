import 'dart:io';

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

  Future<OnDeviceInferenceSession> createChat({
    String? systemInstruction,
    List<Tool> tools,
  });
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
  InferenceModel? _model;
  String? _currentModelId;
  PreferredBackend? _currentBackend;
  bool _isDisposed = false;
  Future<void>? _recoveryFuture;

  InferenceModel? get activeModel => _model;
  String? get currentModelId => _currentModelId;
  @override
  bool get isLoaded => _model != null && !_isDisposed;
  bool get isDisposed => _isDisposed;

  /// The filename of the model restored by the native model manager on app
  /// restart (e.g. "Qwen3-0.6B.litertlm"), or null if no active model spec is
  /// set. This is a cheap synchronous read that does NOT load the engine.
  String? get restoredActiveModelName => FlutterGemma.activeModelSpec?.name;

  /// Syncs the service's internal tracking to the native restored active model
  /// spec so that [createChat] can lazy-load the model on first use after a
  /// restart. Sets both [_currentModelId] and [_currentBackend] so the
  /// lazy-load path in [createChat] can actually trigger.
  void syncFromRestoredSpec(PreferredBackend backend) {
    final specName = restoredActiveModelName;
    if (specName == null) return;

    final model = OnDeviceModel.allCuratedModels.firstWhere(
      (m) => m.fileName == specName || m.id == specName,
      orElse: () => throw StateError('No curated model for $specName'),
    );

    _currentModelId = model.id;
    _currentBackend = backend;
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
    int maxTokens = 2048,
  }) async {
    if (_isDisposed) {
      throw StateError('OnDeviceGemmaService has been disposed');
    }

    if (_model != null &&
        _currentModelId == modelId &&
        _currentBackend == backend) {
      return;
    }

    if (_model != null) {
      await unloadModel();
    }

    Log.info(
      'Loading model $modelId with backend=$backend, maxTokens=$maxTokens',
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
      maxTokens: maxTokens,
      preferredBackend: backend,
    );
    _currentModelId = modelId;
    _currentBackend = backend;

    Log.info('Model $modelId loaded successfully');
  }

  @override
  Future<OnDeviceInferenceSession> createChat({
    String? systemInstruction,
    List<Tool> tools = const [],
  }) async {
    await _ensureModelLoaded();

    try {
      return await _openChat(
        systemInstruction: systemInstruction,
        tools: tools,
      );
    } catch (e) {
      if (!_isClosedClientError(e)) rethrow;

      Log.warning(
        'Gemma FFI model closed while opening an independent chat ($e). '
        'Reloading the model once.',
      );
      await _recoverClosedModel();
      return _openChat(systemInstruction: systemInstruction, tools: tools);
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
  }) async {
    final model = _model!;
    final InferenceChat chat;
    if (model.fileType == ModelFileType.builtIn) {
      chat = await model.createChat(
        systemInstruction: systemInstruction,
        tools: tools,
        supportsFunctionCalls: tools.isNotEmpty,
      );
    } else {
      chat = await model.openChat(
        systemInstruction: systemInstruction,
        tools: tools,
        supportsFunctionCalls: tools.isNotEmpty,
      );
    }
    return _GemmaInferenceSession(chat);
  }

  bool _isClosedClientError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('client shut down') ||
        message.contains('model is closed') ||
        message.contains('model was closed');
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
        try {
          await staleModel.close();
        } catch (error) {
          Log.warning('Error awaiting stale Gemma model shutdown: $error');
        }
      }
      _model = null;
      await loadModel(modelId, backend);
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
