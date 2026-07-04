import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/service_providers.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';

final selectedModelProvider =
    NotifierProvider<SelectedModelNotifier, ModelInfo?>(() {
  return SelectedModelNotifier();
});

class SelectedModelNotifier extends Notifier<ModelInfo?> {
  @override
  ModelInfo? build() => null;

  void setModel(ModelInfo? model) {
    state = model;
  }

  void clear() {
    state = null;
  }
}

final autoSelectFirstLoadedModelProvider = FutureProvider<void>((ref) async {
  final activeServer = ref.watch(activeServerProvider);
  final status = ref.watch(connectionStatusProvider);

  if (activeServer == null) {
    await Future.value();
    ref.read(selectedModelProvider.notifier).clear();
    return;
  }

  if (status != ConnectionStatus.connected) return;

  final selectedModel = ref.read(selectedModelProvider);

  if (selectedModel != null && selectedModel.serverId != activeServer.id) {
    await Future.value();
    ref.read(selectedModelProvider.notifier).clear();
  } else if (selectedModel != null) {
    return;
  }

  if (activeServer.type == ServerType.openRouter ||
      activeServer.type == ServerType.openAICompatible) {
    return;
  }

  try {
    final Set<String> loadedModels;
    if (activeServer.type == ServerType.onDevice) {
      final engine = ref.watch(onDeviceEngineProvider);
      loadedModels = engine.loadedModelId != null
          ? {engine.loadedModelId!}
          : {};
    } else {
      final apiService = ref.read(serverApiServiceProvider);
      loadedModels = await apiService.fetchRunningModels(activeServer);
    }

    if (loadedModels.isEmpty) return;

    final availableModels = await ref.read(
      availableModelsProvider(activeServer.id).future,
    );
    if (availableModels.isEmpty) return;

    final typedModels = availableModels.cast<ModelInfo>();

    final firstLoadedModel = typedModels
        .where((m) => loadedModels.contains(m.id))
        .firstOrNull;

    if (firstLoadedModel != null) {
      ref.read(selectedModelProvider.notifier).setModel(firstLoadedModel);
    }
  } catch (e) {
    // Silently fail auto-selection
  }
});

/// The actual context length the active model was loaded with, fetched
/// live from the server (currently only LM Studio reports this — see
/// [ServerApiService.fetchLoadedContextLength]). Re-fetches whenever the
/// active server or selected model changes.
final activeModelContextLengthProvider = FutureProvider<int?>((ref) async {
  final server = ref.watch(activeServerProvider);
  final model = ref.watch(selectedModelProvider);
  if (server == null || model == null) return null;

  final apiService = ref.read(serverApiServiceProvider);
  return apiService.fetchLoadedContextLength(server, model.id);
});

final isStreamingProvider = NotifierProvider<IsStreamingNotifier, bool>(() {
  return IsStreamingNotifier();
});

class IsStreamingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setStreaming(bool streaming) {
    state = streaming;
  }
}
