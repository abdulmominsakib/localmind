import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';
import '../data/models/on_device_model.dart';
import '../data/on_device_engine_service.dart';
import '../data/on_device_model_download_service.dart';
import '../data/foreground_download_service.dart';

final onDeviceEngineProvider =
    NotifierProvider<OnDeviceEngineNotifier, OnDeviceEngineState>(() {
      return OnDeviceEngineNotifier();
    });

final onDeviceModelsProvider = Provider<List<OnDeviceModel>>((ref) {
  return OnDeviceModel.curatedModels;
});

final onDeviceDownloadServiceProvider = Provider<OnDeviceModelDownloadService>((
  ref,
) {
  return OnDeviceModelDownloadService();
});

final foregroundDownloadServiceProvider = Provider<ForegroundDownloadService>((
  ref,
) {
  return ForegroundDownloadService(ref.read(onDeviceDownloadServiceProvider));
});

final downloadedModelsProvider = FutureProvider<Set<String>>((ref) async {
  final downloadService = ref.read(onDeviceDownloadServiceProvider);
  final models = await downloadService.getDownloadedModels();
  return models.map((m) => m.modelId).toSet();
});

final onDeviceModelStateProvider =
    NotifierProvider<
      OnDeviceModelStateNotifier,
      Map<String, OnDeviceModelStateInfo>
    >(() {
      return OnDeviceModelStateNotifier();
    });

class OnDeviceEngineState {
  final EngineStatus status;
  final String? loadedModelId;
  final String? loadedModelPath;
  final LiteLmBackendType? backend;
  final String? error;

  const OnDeviceEngineState({
    this.status = EngineStatus.notLoaded,
    this.loadedModelId,
    this.loadedModelPath,
    this.backend,
    this.error,
  });

  OnDeviceEngineState copyWith({
    EngineStatus? status,
    String? loadedModelId,
    String? loadedModelPath,
    LiteLmBackendType? backend,
    String? error,
  }) {
    return OnDeviceEngineState(
      status: status ?? this.status,
      loadedModelId: loadedModelId ?? this.loadedModelId,
      loadedModelPath: loadedModelPath ?? this.loadedModelPath,
      backend: backend ?? this.backend,
      error: error ?? this.error,
    );
  }
}

class OnDeviceEngineNotifier extends Notifier<OnDeviceEngineState> {
  OnDeviceEngineService? _engineService;

  @override
  OnDeviceEngineState build() {
    return const OnDeviceEngineState();
  }

  OnDeviceEngineService get engineService {
    _engineService ??= OnDeviceEngineService();
    return _engineService!;
  }

  Future<void> loadModel(String modelId, LiteLmBackendType backend) async {
    state = state.copyWith(status: EngineStatus.loading, error: null);

    try {
      final modelPath = await OnDeviceEngineService.getModelPath(modelId);
      if (modelPath == null) {
        state = state.copyWith(
          status: EngineStatus.error,
          error: 'Model not found. Please download it first.',
        );
        return;
      }

      await engineService.createEngine(modelPath, backend);

      state = state.copyWith(
        status: EngineStatus.loaded,
        loadedModelId: modelId,
        loadedModelPath: modelPath,
        backend: backend,
      );

      Log.info('Model $modelId loaded successfully with ${backend.name}');
    } catch (e) {
      Log.error('Failed to load model $modelId: $e');
      state = state.copyWith(
        status: EngineStatus.error,
        error: 'Failed to load model: ${e.toString()}',
      );
    }
  }

  Future<void> unloadModel() async {
    try {
      await engineService.disposeEngine();
    } catch (_) {}
    state = const OnDeviceEngineState();
  }

  Future<void> dispose() async {
    engineService.dispose();
    state = const OnDeviceEngineState();
  }
}

class OnDeviceModelStateNotifier
    extends Notifier<Map<String, OnDeviceModelStateInfo>> {
  @override
  Map<String, OnDeviceModelStateInfo> build() {
    return {};
  }

  void updateModelState(
    String modelId, {
    OnDeviceModelState? modelState,
    double? downloadProgress,
    String? error,
    LiteLmBackendType? backend,
    EngineStatus? engineStatus,
  }) {
    final current =
        this.state[modelId] ?? OnDeviceModelStateInfo(modelId: modelId);
    this.state = {
      ...this.state,
      modelId: current.copyWith(
        state: modelState ?? current.state,
        downloadProgress: downloadProgress ?? current.downloadProgress,
        error: error ?? current.error,
        backend: backend ?? current.backend,
        engineStatus: engineStatus ?? current.engineStatus,
      ),
    };
  }

  void setDownloading(String modelId, double progress) {
    updateModelState(
      modelId,
      modelState: OnDeviceModelState.downloading,
      downloadProgress: progress,
    );
  }

  void setDownloaded(String modelId) {
    updateModelState(
      modelId,
      modelState: OnDeviceModelState.downloaded,
      downloadProgress: 1.0,
    );
  }

  void setDownloadError(String modelId, String error) {
    updateModelState(
      modelId,
      modelState: OnDeviceModelState.error,
      error: error,
    );
  }

  void removeModel(String modelId) {
    final newState = Map<String, OnDeviceModelStateInfo>.from(state);
    newState.remove(modelId);
    state = newState;
  }
}

final isOnDevicePlatformSupportedProvider = Provider<bool>((ref) {
  return Platform.isAndroid;
});
