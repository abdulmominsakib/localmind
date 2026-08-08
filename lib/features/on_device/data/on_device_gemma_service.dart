import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logger/app_logger.dart';
import 'models/on_device_model.dart';

class OnDeviceGemmaService {
  InferenceModel? _model;
  String? _currentModelId;
  PreferredBackend? _currentBackend;
  bool _isDisposed = false;

  InferenceModel? get activeModel => _model;
  String? get currentModelId => _currentModelId;
  bool get isLoaded => _model != null && !_isDisposed;
  bool get isDisposed => _isDisposed;

  static Future<void> initialize({String? huggingFaceToken}) async {
    await FlutterGemma.initialize(
      inferenceEngines: const [LiteRtLmEngine()],
      huggingFaceToken: huggingFaceToken,
      maxDownloadRetries: 10,
    );
  }

  Future<void> installModel(
    OnDeviceModel model, {
    void Function(int)? onProgress,
    String? token,
  }) async {
    Log.info('Installing model ${model.id} from ${model.huggingFaceUrl}');

    await FlutterGemma.installModel(
      modelType: model.flutterGemmaModelType,
      fileType: ModelFileType.litertlm,
    )
        .fromNetwork(
          model.huggingFaceUrl,
          token: token,
          foreground: true,
        )
        .withProgress((progress) {
      onProgress?.call(progress);
    }).install();

    Log.info('Model ${model.id} installed successfully');
  }

  Future<bool> isModelInstalled(String modelId) async {
    final model = OnDeviceModel.curatedModels.firstWhere(
      (m) => m.id == modelId,
      orElse: () => throw Exception('Model not found: $modelId'),
    );
    return FlutterGemma.isModelInstalled(model.fileName);
  }

  Future<List<String>> getInstalledModelIds() async {
    final installed = await FlutterGemma.listInstalledModels();
    final installedSet = installed.toSet();
    final installedIds = <String>[];

    for (final model in OnDeviceModel.curatedModels) {
      if (installedSet.contains(model.fileName)) {
        installedIds.add(model.id);
      }
    }
    return installedIds;
  }

  Future<void> deleteModel(String modelId) async {
    final model = OnDeviceModel.curatedModels.firstWhere(
      (m) => m.id == modelId,
      orElse: () => throw Exception('Model not found: $modelId'),
    );
    await FlutterGemma.uninstallModel(model.fileName);

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

    final model = OnDeviceModel.curatedModels.firstWhere(
      (m) => m.id == modelId,
      orElse: () => throw Exception('Model not found: $modelId'),
    );

    final spec = InferenceModelSpec(
      name: model.fileName,
      modelSource: ModelSource.network(model.huggingFaceUrl),
      modelType: model.flutterGemmaModelType,
      fileType: ModelFileType.litertlm,
    );
    FlutterGemmaPlugin.instance.modelManager.setActiveModel(spec);

    _model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: backend,
    );
    _currentModelId = modelId;
    _currentBackend = backend;

    Log.info('Model $modelId loaded successfully');
  }

  Future<InferenceChat?> createChat({
    String? systemInstruction,
    List<Tool> tools = const [],
  }) async {
    if (_model == null) {
      throw StateError('Model not loaded. Call loadModel first.');
    }

    return _model!.createChat(
      systemInstruction: systemInstruction,
      tools: tools,
      supportsFunctionCalls: tools.isNotEmpty,
    );
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
          final alreadyInstalled =
              await FlutterGemma.isModelInstalled(fileName);
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
