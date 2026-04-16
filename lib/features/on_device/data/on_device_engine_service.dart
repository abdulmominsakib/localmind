import 'dart:async';
import 'dart:io';

import 'package:flutter_litert_lm/flutter_litert_lm.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';

class OnDeviceEngineService {
  LiteLmEngine? _engine;
  String? _currentModelPath;
  LiteLmBackendType? _currentBackend;
  bool _isDisposed = false;

  LiteLmEngine? get engine => _engine;
  String? get currentModelPath => _currentModelPath;
  bool get isLoaded => _engine != null && !_isDisposed;
  bool get isDisposed => _isDisposed;

  Future<LiteLmEngine> createEngine(
    String modelPath,
    LiteLmBackendType backendType,
  ) async {
    if (_isDisposed) {
      throw StateError('OnDeviceEngineService has been disposed');
    }

    if (_engine != null &&
        _currentModelPath == modelPath &&
        _currentBackend == backendType) {
      return _engine!;
    }

    if (_engine != null) {
      await disposeEngine();
    }

    final backend = _mapBackendType(backendType);

    Log.info(
      'Creating LiteLmEngine with modelPath=$modelPath, backend=$backendType',
    );

    final config = LiteLmEngineConfig(modelPath: modelPath, backend: backend);

    _engine = await LiteLmEngine.create(config);
    _currentModelPath = modelPath;
    _currentBackend = backendType;

    Log.info('LiteLmEngine created successfully');
    return _engine!;
  }

  Future<LiteLmConversation> createConversation({
    String? systemInstruction,
    LiteLmSamplerConfig? samplerConfig,
    List<LiteLmTool>? tools,
  }) async {
    if (_engine == null) {
      throw StateError('Engine not loaded. Call createEngine first.');
    }

    final config = LiteLmConversationConfig(
      systemInstruction: systemInstruction,
      samplerConfig: samplerConfig,
      tools: tools,
    );

    return await _engine!.createConversation(config);
  }

  Future<void> disposeEngine() async {
    if (_engine != null) {
      try {
        await _engine!.dispose();
      } catch (e) {
        Log.error('Error disposing engine: $e');
      }
      _engine = null;
      _currentModelPath = null;
      _currentBackend = null;
    }
  }

  void dispose() {
    _isDisposed = true;
    disposeEngine();
  }

  LiteLmBackend _mapBackendType(LiteLmBackendType type) {
    switch (type) {
      case LiteLmBackendType.cpu:
        return LiteLmBackend.cpu;
      case LiteLmBackendType.gpu:
        return LiteLmBackend.gpu;
      case LiteLmBackendType.npu:
        return LiteLmBackend.npu;
    }
  }

  static Future<String> getModelDirectory() async {
    final dir = await getApplicationSupportDirectory();
    final modelsDir = Directory('${dir.path}/on_device_models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir.path;
  }

  static Future<String?> getModelPath(String modelId) async {
    final dir = await getModelDirectory();
    final file = File('$dir/$modelId.litertlm');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  static Future<bool> isModelDownloaded(String modelId) async {
    final path = await getModelPath(modelId);
    return path != null;
  }

  static Future<void> deleteModel(String modelId) async {
    final dir = await getModelDirectory();
    final file = File('$dir/$modelId.litertlm');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
