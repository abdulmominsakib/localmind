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

/// Pure selector for the model name + configured flag that should be shown on
/// the home-screen widget. Pure function of Riverpod state — no side effects.
///
/// Side effects (calling out to the home_widget plugin) live in
/// `OsWidgetInvocationHost` via `ref.listen`, so this stays declarative.
class OsWidgetSnapshot {
  final String? modelName;
  final bool isConfigured;

  const OsWidgetSnapshot({this.modelName, required this.isConfigured});
}

final osWidgetSnapshotProvider = Provider<OsWidgetSnapshot>((ref) {
  final settings = ref.watch(settingsProvider);
  final defaultModelId = settings.defaultModelId;
  final defaultModelServerId = settings.defaultModelServerId;

  final isConfigured =
      defaultModelId != null &&
      defaultModelId.isNotEmpty &&
      defaultModelServerId != null &&
      defaultModelServerId.isNotEmpty;

  if (!isConfigured) {
    return const OsWidgetSnapshot(modelName: null, isConfigured: false);
  }

  final availableAsync = ref.watch(
    availableModelsProvider(defaultModelServerId),
  );
  final models = availableAsync.value ?? const <ModelInfo>[];
  final model = models.where((m) => m.id == defaultModelId).firstOrNull;
  return OsWidgetSnapshot(
    modelName: model?.displayName ?? defaultModelId,
    isConfigured: true,
  );
});

/// Push the snapshot to the native widget. Convenience for `ref.listen`
/// callbacks that have a WidgetRef handy; reads the service for the caller.
Future<void> pushOsWidgetSnapshot(
  WidgetRef ref, {
  required String? modelName,
  required bool isConfigured,
}) async {
  final service = ref.read(osWidgetServiceProvider);
  if (!service.isSupportedPlatform) return;
  await service.updateWidgetSnapshot(
    modelName: modelName,
    isConfigured: isConfigured,
  );
}
