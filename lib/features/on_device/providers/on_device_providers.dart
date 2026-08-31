import 'dart:io';

import 'package:apple_mlx/apple_mlx.dart';
import 'package:dio/dio.dart';
import 'package:flutter_gemma/flutter_gemma.dart' show PreferredBackend;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/chat_background_service_provider.dart';
import '../../../core/providers/review_prompt_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/providers/storage_providers.dart';
import '../data/imported_gguf_model_repository.dart';
import '../data/models/on_device_model.dart';
import '../data/notification_permission_service.dart';
import '../data/on_device_gemma_service.dart';
import '../data/on_device_llama_service.dart';
import '../data/on_device_mlx_service.dart';
import '../../servers/providers/server_providers.dart';

final notificationPermissionServiceProvider =
    Provider<NotificationPermissionService>((ref) {
      return NotificationPermissionService();
    });

final onDeviceGemmaServiceProvider = Provider<OnDeviceGemmaService>((ref) {
  final service = OnDeviceGemmaService();
  ref.onDispose(() => service.dispose());
  return service;
});

final onDeviceLlamaServiceProvider = Provider<OnDeviceLlamaService>((ref) {
  final service = OnDeviceLlamaService();
  ref.onDispose(() => service.dispose());
  return service;
});

final onDeviceMlxServiceProvider = Provider<OnDeviceMlxService>((ref) {
  final service = OnDeviceMlxService(ref.read(dioProvider));
  ref.onDispose(() => service.dispose());
  return service;
});

final importedGgufModelRepositoryProvider =
    Provider<ImportedGgufModelRepository>((ref) {
      return ImportedGgufModelRepository(
        ref.read(sharedPreferencesProvider),
        ref.read(dioProvider),
      );
    });

final importedGgufModelsProvider =
    NotifierProvider<ImportedGgufModelsNotifier, List<OnDeviceModel>>(() {
      return ImportedGgufModelsNotifier();
    });

final onDeviceEngineProvider =
    NotifierProvider<OnDeviceEngineNotifier, OnDeviceEngineState>(() {
      return OnDeviceEngineNotifier();
    });

List<OnDeviceModel> availableCuratedMlxModels({required bool isIOS}) {
  if (!isIOS || !AppleMlxCapabilities.nativeLlmInferenceAvailable) {
    return const <OnDeviceModel>[];
  }
  return OnDeviceModel.curatedMlxModels;
}

final onDeviceModelsProvider = Provider<List<OnDeviceModel>>((ref) {
  final imported = ref.watch(importedGgufModelsProvider);
  final mlxModels = availableCuratedMlxModels(isIOS: Platform.isIOS);
  return [...mlxModels, ...OnDeviceModel.curatedModels, ...imported];
});

final downloadedModelsProvider = FutureProvider<Set<String>>((ref) async {
  final gemmaService = ref.read(onDeviceGemmaServiceProvider);
  final installed = await gemmaService.getInstalledModelIds();
  final mlxService = ref.read(onDeviceMlxServiceProvider);
  final mlxInstalled = Platform.isIOS
      ? await mlxService.getInstalledModelIds()
      : const <String>{};
  final imported = ref.watch(importedGgufModelsProvider);
  return {...installed, ...mlxInstalled, ...imported.map((model) => model.id)};
});

final onDeviceModelStateProvider =
    NotifierProvider<
      OnDeviceModelStateNotifier,
      Map<String, OnDeviceModelStateInfo>
    >(() {
      return OnDeviceModelStateNotifier();
    });

class OnDeviceEngineState {
  static const _unset = Object();

  final OnDeviceEngineStatus status;
  final String? loadedModelId;
  final OnDeviceModelRuntime? loadedRuntime;
  final PreferredBackend? backend;
  final String? error;

  const OnDeviceEngineState({
    this.status = OnDeviceEngineStatus.notLoaded,
    this.loadedModelId,
    this.loadedRuntime,
    this.backend,
    this.error,
  });

  OnDeviceEngineState copyWith({
    OnDeviceEngineStatus? status,
    Object? loadedModelId = _unset,
    Object? loadedRuntime = _unset,
    Object? backend = _unset,
    Object? error = _unset,
  }) {
    return OnDeviceEngineState(
      status: status ?? this.status,
      loadedModelId: identical(loadedModelId, _unset)
          ? this.loadedModelId
          : loadedModelId as String?,
      loadedRuntime: identical(loadedRuntime, _unset)
          ? this.loadedRuntime
          : loadedRuntime as OnDeviceModelRuntime?,
      backend: identical(backend, _unset)
          ? this.backend
          : backend as PreferredBackend?,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

class ImportedGgufModelsNotifier extends Notifier<List<OnDeviceModel>> {
  bool _hasScheduledInitialPrune = false;

  ImportedGgufModelRepository get _repository =>
      ref.read(importedGgufModelRepositoryProvider);

  @override
  List<OnDeviceModel> build() {
    if (!_hasScheduledInitialPrune) {
      _hasScheduledInitialPrune = true;
      Future.microtask(() async {
        if (ref.mounted) {
          await pruneMissing();
        }
      });
    }
    return _repository.load().map((model) => model.toOnDeviceModel()).toList();
  }

  Future<OnDeviceModel> importModel(String sourcePath) async {
    final metadata = await _repository.importFromPath(sourcePath);
    final model = metadata.toOnDeviceModel();
    if (ref.mounted) {
      state = [...state, model];
    }
    return model;
  }

  Future<OnDeviceModel> importModelFromHuggingFaceUrl(
    String sourceUrl, {
    String? huggingFaceToken,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final metadata = await _repository.importFromHuggingFaceUrl(
      sourceUrl,
      token: huggingFaceToken,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
    final model = metadata.toOnDeviceModel();
    if (ref.mounted) {
      state = [...state, model];
    }
    return model;
  }

  Future<void> deleteModel(String modelId) async {
    await _repository.delete(modelId);
    if (!ref.mounted) return;
    state = state.where((model) => model.id != modelId).toList();
  }

  /// Removes a single missing model from the list. Used when we try to load
  /// a specific imported GGUF and discover its file is gone, so other valid
  /// imports are not collateral damage.
  Future<void> removeMissingModel(String modelId) async {
    final hadModel = state.any((m) => m.id == modelId);
    if (!hadModel) return;
    await _repository.delete(modelId);
    if (!ref.mounted) return;
    state = state.where((model) => model.id != modelId).toList();
  }

  /// Prunes any imported models whose backing files have disappeared from
  /// disk. Intended to be called explicitly (e.g. when entering the model
  /// manager screen) rather than from `build()` so it never runs against a
  /// disposed provider container.
  Future<void> pruneMissing() async {
    final existing = await _repository.loadExisting();
    if (!ref.mounted) return;

    final keptIds = existing.map((m) => m.id).toSet();
    if (keptIds.length == state.length &&
        state.every((m) => keptIds.contains(m.id))) {
      return;
    }
    state = existing.map((m) => m.toOnDeviceModel()).toList();
  }
}

class OnDeviceEngineNotifier extends Notifier<OnDeviceEngineState> {
  bool _hasScheduledRestore = false;

  @override
  OnDeviceEngineState build() {
    if (!_hasScheduledRestore) {
      _hasScheduledRestore = true;
      Future.microtask(() => _restoreActiveModel());
    }
    return const OnDeviceEngineState();
  }

  /// After an app restart, the native model manager restores the last active
  /// inference model spec (logged as "[ModelManager] restored active inference
  /// model: ..."). The spec alone does NOT mean the model is loaded in memory,
  /// so we only sync the service's tracking (enabling lazy-load on first chat)
  /// without flipping the engine state to `loaded`. This keeps the model
  /// manager and model picker from showing a not-yet-loaded model as active.
  Future<void> _restoreActiveModel() async {
    if (!ref.mounted) return;

    final specName = _gemmaService.restoredActiveModelName;
    if (specName == null) return;

    final models = ref.read(onDeviceModelsProvider);
    final model = models.where((m) => m.fileName == specName).firstOrNull;
    if (model == null) return;

    final settings = ref.read(settingsProvider);
    final backend = model.isCpuOnly
        ? PreferredBackend.cpu
        : settings.preferredBackend;

    // Sync the service so createChat can lazy-load on first use.
    _gemmaService.syncFromRestoredSpec(backend);

    Log.info(
      'Restored active inference model spec: ${model.id} (${model.fileName})',
    );
  }

  OnDeviceGemmaService get _gemmaService =>
      ref.read(onDeviceGemmaServiceProvider);
  OnDeviceLlamaService get _llamaService =>
      ref.read(onDeviceLlamaServiceProvider);
  OnDeviceMlxService get _mlxService => ref.read(onDeviceMlxServiceProvider);

  Future<void> loadModel(String modelId, PreferredBackend backend) async {
    if (!ref.mounted) return;
    final models = ref.read(onDeviceModelsProvider);
    final model = models.firstWhere(
      (m) => m.id == modelId,
      orElse: () => throw Exception('Model not found: $modelId'),
    );

    state = state.copyWith(
      status: OnDeviceEngineStatus.loading,
      loadedModelId: modelId,
      loadedRuntime: model.runtime,
      error: null,
    );

    // Protect the heavy native model-load from Android CPU throttling
    final bgService = ref.read(chatBackgroundServiceProvider);
    await bgService.start();
    if (!ref.mounted) return;

    try {
      final effectiveBackend = model.isCpuOnly ? PreferredBackend.cpu : backend;

      // Yield control to the event loop so the UI has time to draw the loading indicator
      // and stabilize before the native platform thread begins heavy model loading.
      await Future.delayed(const Duration(milliseconds: 100));
      if (!ref.mounted) return;

      if (model.runtime == OnDeviceModelRuntime.llamaCpp) {
        final file = File(model.localPath ?? '');
        if (!await file.exists()) {
          if (!ref.mounted) return;
          await ref
              .read(importedGgufModelsProvider.notifier)
              .removeMissingModel(modelId);
          if (!ref.mounted) return;
          state = state.copyWith(
            status: OnDeviceEngineStatus.error,
            loadedModelId: null,
            loadedRuntime: null,
            error: 'Imported GGUF file is missing. Please re-import it.',
          );
          return;
        }

        final settings = ref.read(settingsProvider);
        await _gemmaService.unloadModel();
        await _mlxService.unloadModel();
        if (!ref.mounted) return;
        await _llamaService.loadModel(
          model,
          contextLength: settings.contextLength,
          useGpu: !model.isCpuOnly && effectiveBackend == PreferredBackend.gpu,
        );
        if (!ref.mounted) return;
      } else if (model.runtime == OnDeviceModelRuntime.mlx) {
        final isInstalled = await _mlxService.isModelInstalled(modelId);
        if (!ref.mounted) return;
        if (!isInstalled) {
          state = state.copyWith(
            status: OnDeviceEngineStatus.error,
            loadedModelId: null,
            loadedRuntime: null,
            error: 'MLX Model not found. Please download it first.',
          );
          return;
        }

        await _gemmaService.unloadModel();
        await _llamaService.unloadModel();
        if (!ref.mounted) return;
        await _mlxService.loadModel(model);
        if (!ref.mounted) return;
      } else {
        final isInstalled = await _gemmaService.isModelInstalled(modelId);
        if (!ref.mounted) return;
        if (!isInstalled) {
          state = state.copyWith(
            status: OnDeviceEngineStatus.error,
            loadedModelId: null,
            loadedRuntime: null,
            error: 'Model not found. Please download it first.',
          );
          return;
        }

        await _llamaService.unloadModel();
        await _mlxService.unloadModel();
        if (!ref.mounted) return;
        await _gemmaService.loadModel(modelId, effectiveBackend);
        if (!ref.mounted) return;
      }

      state = state.copyWith(
        status: OnDeviceEngineStatus.loaded,
        loadedModelId: modelId,
        loadedRuntime: model.runtime,
        backend: effectiveBackend,
      );

      final activeServer = ref.read(activeServerProvider);
      if (activeServer?.type != ServerType.onDevice) {
        final servers = await ref.read(serversProvider.future);
        if (!ref.mounted) return;
        final onDeviceServer = servers
            .where((s) => s.type == ServerType.onDevice)
            .firstOrNull;
        if (onDeviceServer != null && ref.mounted) {
          Future.microtask(() {
            if (ref.mounted) {
              ref
                  .read(activeServerIdProvider.notifier)
                  .setActiveServer(onDeviceServer);
            }
          });
        }
      }

      Log.info(
        'Model $modelId loaded successfully with ${effectiveBackend.name}',
      );

      try {
        if (ref.mounted) {
          await ref
              .read(reviewPromptServiceProvider)
              .markOnDeviceModelLoaded(modelId);
        }
      } catch (e) {
        Log.error('Failed to record model load review signal: $e');
      }
    } catch (e) {
      if (!ref.mounted) return;
      Log.error('Failed to load model $modelId: $e');
      state = state.copyWith(
        status: OnDeviceEngineStatus.error,
        loadedModelId: null,
        loadedRuntime: null,
        error: 'Failed to load model: ${e.toString()}',
      );
    } finally {
      await bgService.stop();
    }
  }

  Future<void> unloadModel() async {
    final gemma = ref.mounted ? _gemmaService : null;
    final llama = ref.mounted ? _llamaService : null;
    final mlx = ref.mounted ? _mlxService : null;
    if (gemma != null) {
      try {
        await gemma.unloadModel();
      } catch (e) {
        Log.error('Failed to unload gemma model: $e');
      }
    }
    if (llama != null) {
      try {
        await llama.unloadModel();
      } catch (e) {
        Log.error('Failed to unload llama.cpp model: $e');
      }
    }
    if (mlx != null) {
      try {
        await mlx.unloadModel();
      } catch (e) {
        Log.error('Failed to unload MLX model: $e');
      }
    }
    if (ref.mounted) {
      state = const OnDeviceEngineState();
    }
  }

  Future<void> disposeService() async {
    _gemmaService.dispose();
    _llamaService.dispose();
    _mlxService.dispose();
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
    PreferredBackend? backend,
    OnDeviceEngineStatus? engineStatus,
  }) {
    final current = state[modelId] ?? OnDeviceModelStateInfo(modelId: modelId);
    state = {
      ...state,
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
  return Platform.isAndroid || Platform.isIOS;
});
