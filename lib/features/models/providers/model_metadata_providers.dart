import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/storage_providers.dart';
import '../data/model_metadata_repository.dart';

final modelMetadataRepositoryProvider = Provider<ModelMetadataRepository>((ref) {
  return ModelMetadataRepository(ref.watch(sharedPreferencesProvider));
});

final modelMetadataProvider =
    NotifierProvider<ModelMetadataNotifier, Map<String, ModelMetadata>>(() {
      return ModelMetadataNotifier();
    });

class ModelMetadataNotifier extends Notifier<Map<String, ModelMetadata>> {
  String? _serverId;

  @override
  Map<String, ModelMetadata> build() {
    return {};
  }

  void loadForServer(String serverId) {
    _serverId = serverId;
    if (!ref.mounted) return;
    state = ref.read(modelMetadataRepositoryProvider).getAllForServer(serverId);
  }

  Future<void> toggleFavorite(String modelId) async {
    final serverId = _serverId;
    if (serverId == null) return;
    final current = state[modelId]?.isFavorite ?? false;
    await ref
        .read(modelMetadataRepositoryProvider)
        .setFavorite(serverId, modelId, !current);
    if (!ref.mounted) return;
    loadForServer(serverId);
  }

  Future<void> setNote(String modelId, String? note) async {
    final serverId = _serverId;
    if (serverId == null) return;
    await ref
        .read(modelMetadataRepositoryProvider)
        .setNote(serverId, modelId, note);
    if (!ref.mounted) return;
    loadForServer(serverId);
  }
}
