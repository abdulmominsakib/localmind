import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../chat/providers/chat_providers.dart';
import '../../conversations/providers/conversation_providers.dart' as conv;
import '../../models/data/models/model_info.dart';
import '../../on_device/data/models/on_device_model.dart';
import '../../on_device/providers/on_device_providers.dart';
import '../../servers/providers/server_providers.dart';
import '../../voice_mode/providers/voice_mode_provider.dart';
import '../../voice_mode/views/voice_mode_overlay.dart';
import '../data/models/os_widget_models.dart';
import '../providers/os_widget_providers.dart';
import 'components/model_loading_overlay.dart';

class OsWidgetInvocationHost extends ConsumerStatefulWidget {
  const OsWidgetInvocationHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<OsWidgetInvocationHost> createState() =>
      _OsWidgetInvocationHostState();
}

class _OsWidgetInvocationHostState
    extends ConsumerState<OsWidgetInvocationHost> {
  StreamSubscription<OsWidgetInvocation>? _subscription;

  bool _isLoadingModel = false;
  String _loadingModelName = '';
  String? _loadingServerName;
  String _loadingStatusMessage = 'Loading model into memory...';
  bool _isShowingVoiceMode = false;
  bool _isCanceled = false;

  @override
  void initState() {
    super.initState();
    final service = ref.read(osWidgetServiceProvider);
    if (!service.isSupportedPlatform) return;

    _subscription = service.invocations.listen(_handleInvocation);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(service.initialize());
      // Initialize widget snapshot sync
      ref.read(osWidgetSnapshotSyncProvider);
    });
  }

  Future<void> _handleInvocation(OsWidgetInvocation invocation) async {
    Log.info('Handling OS Widget invocation: ${invocation.action}');

    switch (invocation.action) {
      case OsWidgetAction.voice:
        await _handleVoiceInvocation();
        break;
      case OsWidgetAction.newChat:
        await _handleChatInvocation(
          prompt: invocation.prompt,
          startNewChat: true,
        );
        break;
      case OsWidgetAction.chat:
      case OsWidgetAction.unknown:
        await _handleChatInvocation(
          prompt: invocation.prompt,
          startNewChat: false,
        );
        break;
    }
  }

  Future<void> _handleVoiceInvocation() async {
    if (!mounted || _isShowingVoiceMode) return;
    if (ref.read(voiceModeProvider).isActive) return;

    _isShowingVoiceMode = true;
    try {
      await VoiceModeOverlay.show(context);
    } finally {
      _isShowingVoiceMode = false;
    }
  }

  Future<void> _handleChatInvocation({
    String? prompt,
    required bool startNewChat,
  }) async {
    if (!mounted) return;

    final settings = ref.read(settingsProvider);
    final defaultModelId = settings.defaultModelId;
    final defaultModelServerId = settings.defaultModelServerId;

    if (defaultModelId == null ||
        defaultModelId.isEmpty ||
        defaultModelServerId == null ||
        defaultModelServerId.isEmpty) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(
            title: const Text('Default Model Required'),
            description: const Text(
              'Please configure a default model in Settings to use Quick Widget.',
            ),
          ),
        );
      }
      if (prompt != null && prompt.isNotEmpty) {
        ref.read(widgetPendingPromptProvider.notifier).setPrompt(prompt);
      }
      return;
    }

    final servers = await ref.read(serversProvider.future);
    final defaultServer = servers
        .where((s) => s.id == defaultModelServerId)
        .firstOrNull;

    if (defaultServer == null) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Server Not Found'),
            description: const Text(
              'The server configured for the default model is no longer available.',
            ),
          ),
        );
      }
      return;
    }

    // Determine model display name
    String modelDisplayName = defaultModelId;
    if (defaultServer.type == ServerType.onDevice) {
      final curated = OnDeviceModel.curatedModels
          .where((m) => m.id == defaultModelId)
          .firstOrNull;
      if (curated != null) {
        modelDisplayName = curated.name;
      }
    } else {
      try {
        final availableModels = await ref.read(
          availableModelsProvider(defaultServer.id).future,
        );
        final found = availableModels
            .where((m) => m.id == defaultModelId)
            .firstOrNull;
        if (found != null) {
          modelDisplayName = found.displayName;
        }
      } catch (_) {
        // Fallback to ID
      }
    }

    _isCanceled = false;
    setState(() {
      _isLoadingModel = true;
      _loadingModelName = modelDisplayName;
      _loadingServerName = defaultServer.name;
      _loadingStatusMessage = 'Loading model into memory...';
    });

    try {
      // 1. Set active server
      ref.read(activeServerIdProvider.notifier).setActiveServer(defaultServer);

      // 2. Load model if needed
      if (defaultServer.type == ServerType.onDevice) {
        final engineNotifier = ref.read(onDeviceEngineProvider.notifier);
        final engineState = ref.read(onDeviceEngineProvider);

        if (engineState.loadedModelId != defaultModelId ||
            engineState.status != OnDeviceEngineStatus.loaded) {
          setState(() {
            _loadingStatusMessage = 'Initializing on-device engine...';
          });
          await engineNotifier.loadModel(
            defaultModelId,
            settings.preferredBackend,
          );
        }
      } else if (defaultServer.type == ServerType.lmStudio) {
        final apiService = ref.read(serverApiServiceProvider);
        setState(() {
          _loadingStatusMessage = 'Checking LM Studio instance...';
        });
        final running = await apiService.fetchRunningModels(defaultServer);
        if (!running.contains(defaultModelId) && !_isCanceled) {
          setState(() {
            _loadingStatusMessage = 'Loading model in LM Studio...';
          });
          if (settings.unloadModelsBeforeLoad) {
            final instances = await ref.read(
              loadedModelsProvider(defaultServer).future,
            );
            await apiService.unloadAllInstances(defaultServer, instances);
          }
          await apiService.loadModelWithInstanceId(
            defaultServer,
            defaultModelId,
            contextLength: ref.read(chatParamsProvider).contextLength,
          );
        }
      }

      if (_isCanceled || !mounted) return;

      // 3. Set selected model
      final available = await ref.read(
        availableModelsProvider(defaultServer.id).future,
      );
      final targetModel =
          available.where((m) => m.id == defaultModelId).firstOrNull ??
          ModelInfo(
            id: defaultModelId,
            name: modelDisplayName,
            serverId: defaultServer.id,
            serverType: defaultServer.type,
          );
      ref.read(selectedModelProvider.notifier).setModel(targetModel);

      // 4. Handle new chat if requested
      if (startNewChat) {
        ref
            .read(conv.activeConversationIdProvider.notifier)
            .setActiveConversationId(null);
      }

      // 5. Pre-fill prompt if provided
      if (prompt != null && prompt.isNotEmpty) {
        ref.read(widgetPendingPromptProvider.notifier).setPrompt(prompt);
      }
    } catch (e) {
      Log.error('Error loading default model from widget: $e');
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Model Loading Failed'),
            description: Text('Failed to load $modelDisplayName: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingModel = false;
        });
      }
    }
  }

  void _cancelLoading() {
    _isCanceled = true;
    setState(() {
      _isLoadingModel = false;
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep widget snapshot synced with active settings
    ref.watch(osWidgetSnapshotSyncProvider);

    return Stack(
      children: [
        widget.child,
        if (_isLoadingModel)
          Positioned.fill(
            child: ModelLoadingOverlay(
              modelName: _loadingModelName,
              serverName: _loadingServerName,
              statusMessage: _loadingStatusMessage,
              onCancel: _cancelLoading,
            ),
          ),
      ],
    );
  }
}
