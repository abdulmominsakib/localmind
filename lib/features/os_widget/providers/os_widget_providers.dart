import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../models/data/models/model_info.dart';
import '../../servers/providers/server_providers.dart';
import '../data/os_widget_service.dart';

final osWidgetServiceProvider = Provider<OsWidgetService>((ref) {
  final service = OsWidgetService();
  ref.onDispose(service.dispose);
  return service;
});

class WidgetPendingPromptNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setPrompt(String? prompt) {
    state = prompt;
  }

  String? consumePrompt() {
    final prompt = state;
    state = null;
    return prompt;
  }
}

final widgetPendingPromptProvider =
    NotifierProvider<WidgetPendingPromptNotifier, String?>(
      WidgetPendingPromptNotifier.new,
    );

final osWidgetSnapshotSyncProvider = Provider<void>((ref) {
  final settings = ref.watch(settingsProvider);
  final defaultModelId = settings.defaultModelId;
  final defaultModelServerId = settings.defaultModelServerId;
  final service = ref.watch(osWidgetServiceProvider);

  if (!service.isSupportedPlatform) return;

  final isConfigured =
      defaultModelId != null &&
      defaultModelId.isNotEmpty &&
      defaultModelServerId != null &&
      defaultModelServerId.isNotEmpty;

  if (!isConfigured) {
    service.updateWidgetSnapshot(modelName: null, isConfigured: false);
    return;
  }

  final availableAsync = ref.watch(
    availableModelsProvider(defaultModelServerId),
  );
  final models = availableAsync.value ?? const <ModelInfo>[];
  final model = models.where((m) => m.id == defaultModelId).firstOrNull;
  final modelName = model?.displayName ?? defaultModelId;

  service.updateWidgetSnapshot(modelName: modelName, isConfigured: true);
});
