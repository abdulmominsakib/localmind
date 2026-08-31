import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/providers/service_providers.dart';
import 'package:localmind/features/chat/providers/chat_params_providers.dart';
import 'package:localmind/features/chat/providers/chat_reasoning_providers.dart';
import 'package:localmind/features/chat/providers/model_loading_providers.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/models/utils/model_instance_utils.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';

const modelSelectionRequiredMessage = 'You need to select a model first';

class ActiveChatTarget {
  final Server? server;
  final ModelInfo? selectedModel;
  final String? effectiveModelId;
  final String modelLabel;

  const ActiveChatTarget({
    required this.server,
    required this.selectedModel,
    required this.effectiveModelId,
    required this.modelLabel,
  });

  bool get isReady => server != null && effectiveModelId != null;
}

/// The server/model pair that a message will actually use.
///
/// A loaded on-device model remains usable even before the model picker has
/// recreated its [ModelInfo]. A native restored spec is deliberately excluded:
/// it is metadata for lazy loading, not proof that a model is in memory.
/// Remote servers retain their existing `default` model routing when no
/// explicit model is selected.
final activeChatTargetProvider = Provider<ActiveChatTarget>((ref) {
  final server = ref.watch(activeServerProvider);
  if (server == null) {
    return const ActiveChatTarget(
      server: null,
      selectedModel: null,
      effectiveModelId: null,
      modelLabel: 'No model',
    );
  }

  final selected = ref.watch(selectedModelProvider);
  final selectedForServer = selected?.serverId == server.id ? selected : null;
  if (selectedForServer != null) {
    return ActiveChatTarget(
      server: server,
      selectedModel: selectedForServer,
      effectiveModelId: selectedForServer.id,
      modelLabel: selectedForServer.displayName,
    );
  }

  if (server.type != ServerType.onDevice) {
    return ActiveChatTarget(
      server: server,
      selectedModel: null,
      effectiveModelId: 'default',
      modelLabel: 'Default model',
    );
  }

  final engine = ref.watch(onDeviceEngineProvider);
  final modelId = engine.status == OnDeviceEngineStatus.loaded
      ? engine.loadedModelId
      : null;
  final model = modelId == null
      ? null
      : OnDeviceModel.allCuratedModels
            .where((candidate) => candidate.id == modelId)
            .firstOrNull;

  return ActiveChatTarget(
    server: server,
    selectedModel: null,
    effectiveModelId: modelId,
    modelLabel: model?.name ?? modelId ?? 'No model',
  );
});

final selectedModelProvider =
    NotifierProvider<SelectedModelNotifier, ModelInfo?>(() {
      return SelectedModelNotifier();
    });

class SelectedModelNotifier extends Notifier<ModelInfo?> {
  @override
  ModelInfo? build() => null;

  void setModel(ModelInfo? model) {
    state = model;
    if (model != null) {
      if (model.serverType == ServerType.onDevice) {
        final engineState = ref.read(onDeviceEngineProvider);
        if (engineState.loadedModelId != null &&
            engineState.status == OnDeviceEngineStatus.loaded) {
          final activeServer = ref.read(activeServerProvider);
          if (activeServer?.type != ServerType.onDevice) {
            final servers = ref.read(serversProvider).value ?? [];
            final onDeviceServer = servers
                .where((s) => s.type == ServerType.onDevice)
                .firstOrNull;
            if (onDeviceServer != null) {
              ref
                  .read(activeServerIdProvider.notifier)
                  .setActiveServer(onDeviceServer);
            }
          }
        }
      }
      _normalizeReasoningForModel(model);
    }
  }

  /// Snaps the reasoning config to a value the newly selected model actually
  /// supports, so the next request never carries an invalid `reasoning_effort`
  /// (e.g. `low` for a model that only advertises `high`). Also forces
  /// reasoning on for mandatory-reasoning models, since they can't run with
  /// it disabled.
  void _normalizeReasoningForModel(ModelInfo model) {
    final reasoning = ref.read(chatReasoningConfigProvider);
    final notifier = ref.read(chatReasoningConfigProvider.notifier);
    if (model.reasoningMandatory && !reasoning.enabled) {
      notifier.setEnabled(true);
    }
    final supported = model.supportedReasoningEfforts;
    if (supported != null && !supported.contains(reasoning.effort.apiValue)) {
      notifier.setEffort(resolveEffortForModel(model, reasoning.effort));
    }
  }

  void clear() {
    state = null;
  }
}

final autoSelectFirstLoadedModelProvider = FutureProvider<void>((ref) async {
  final activeServer = ref.watch(activeServerProvider);
  final status = ref.watch(connectionStatusProvider);

  // Re-run whenever the configured default model changes so a newly chosen
  // default is applied to the next new chat (the notifier only seeds the
  // selection when no model is already picked).
  ref.watch(
    settingsProvider.select((s) => (s.defaultModelId, s.defaultModelServerId)),
  );

  if (activeServer == null) {
    await Future.value();
    if (!ref.mounted) return;
    ref.read(selectedModelProvider.notifier).clear();
    return;
  }

  if (status != ConnectionStatus.connected) return;

  final selectedModel = ref.read(selectedModelProvider);

  if (selectedModel != null && selectedModel.serverId != activeServer.id) {
    await Future.value();
    if (!ref.mounted) return;
    ref.read(selectedModelProvider.notifier).clear();
  } else if (selectedModel != null) {
    return;
  }

  final settings = ref.read(settingsProvider);
  final defaultModelId = settings.defaultModelId;
  final defaultModelServerId = settings.defaultModelServerId;
  final hasDefaultForServer =
      defaultModelId != null && defaultModelServerId == activeServer.id;

  // Cloud providers have no "loaded" notion, so without a configured
  // default there's nothing to auto-select for them (avoids an extra model
  // list fetch for users who never set one).
  if (!hasDefaultForServer &&
      (activeServer.type == ServerType.openRouter ||
          activeServer.type == ServerType.openAICompatible)) {
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
      if (!ref.mounted) return;
    }

    final availableModels = await ref.read(
      availableModelsProvider(activeServer.id).future,
    );
    if (!ref.mounted) return;

    final typedModels = availableModels.cast<ModelInfo>();
    if (typedModels.isEmpty) return;

    if (hasDefaultForServer) {
      final defaultModel = typedModels
          .where((m) => m.id == defaultModelId)
          .firstOrNull;
      if (defaultModel != null) {
        if (activeServer.type == ServerType.onDevice) {
          // On-device inference runs one engine instance at a time, so only
          // auto-select the default when it's the model the engine already
          // has loaded; otherwise fall through to the loaded-model logic.
          if (isModelKeyLoaded(loadedModels, defaultModel.id)) {
            if (!ref.mounted) return;
            ref.read(selectedModelProvider.notifier).setModel(defaultModel);
            return;
          }
        } else {
          // LM Studio models must be running before a request can use them;
          // if the default isn't loaded yet, load it exactly like tapping it
          // in the model picker would so the user can start chatting right
          // away. Ollama and cloud providers load on demand, so selecting is
          // enough for them.
          if (!isModelKeyLoaded(loadedModels, defaultModel.id) &&
              activeServer.type == ServerType.lmStudio) {
            await _loadDefaultModel(ref, activeServer, defaultModel);
            if (!ref.mounted) return;
          }
          ref.read(selectedModelProvider.notifier).setModel(defaultModel);
          return;
        }
      }
    }

    // Cloud providers fall back to no selection when the configured default
    // isn't among the available models.
    if (activeServer.type == ServerType.openRouter ||
        activeServer.type == ServerType.openAICompatible) {
      return;
    }

    if (loadedModels.isEmpty) {
      if (activeServer.type == ServerType.onDevice) {
        final downloadedAsync = await ref.read(downloadedModelsProvider.future);
        if (!ref.mounted) return;
        if (hasDefaultForServer) {
          final defaultModel = typedModels
              .where(
                (m) =>
                    m.id == defaultModelId && downloadedAsync.contains(m.id),
              )
              .firstOrNull;
          if (defaultModel != null && ref.mounted) {
            ref.read(selectedModelProvider.notifier).setModel(defaultModel);
            return;
          }
        }
        final firstAvailableModel = typedModels
            .where((m) => downloadedAsync.contains(m.id))
            .firstOrNull;
        if (firstAvailableModel != null && ref.mounted) {
          ref
              .read(selectedModelProvider.notifier)
              .setModel(firstAvailableModel);
        }
      }
      return;
    }

    final firstLoadedModel = typedModels
        .where((m) => isModelKeyLoaded(loadedModels, m.id))
        .firstOrNull;

    if (firstLoadedModel != null && ref.mounted) {
      ref.read(selectedModelProvider.notifier).setModel(firstLoadedModel);
    }
  } catch (e) {
    // Silently fail auto-selection
  }
});

/// Loads an LM Studio model via the server API and reflects the busy state in
/// [modelLoadingProvider], mirroring what tapping a model in the picker does.
Future<void> _loadDefaultModel(
  Ref ref,
  Server activeServer,
  ModelInfo model,
) async {
  if (!ref.mounted) return;
  final apiService = ref.read(serverApiServiceProvider);
  final settings = ref.read(settingsProvider);
  final contextLength = ref.read(chatParamsProvider).contextLength;

  ref.read(modelLoadingProvider.notifier).setLoading(model.id);
  try {
    if (settings.unloadModelsBeforeLoad) {
      final instances = await ref.read(
        loadedModelsProvider(activeServer).future,
      );
      if (!ref.mounted) return;
      await apiService.unloadAllInstances(activeServer, instances);
      if (!ref.mounted) return;
    }
    await apiService.loadModelWithInstanceId(
      activeServer,
      model.id,
      contextLength: contextLength,
    );
    if (!ref.mounted) return;
    ref.invalidate(loadedModelsProvider(activeServer));
  } finally {
    if (ref.mounted) {
      ref.read(modelLoadingProvider.notifier).setLoaded();
    }
  }
}

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
