import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/storage_providers.dart';
import 'on_device_providers.dart';

const String kLastUpdateCheckPref = 'on_device_last_update_check';

class ImportedModelUpdateNotifier extends Notifier<AsyncValue<int>> {
  @override
  AsyncValue<int> build() => const AsyncValue.data(0);

  Future<int> checkForUpdates() async {
    state = const AsyncValue.loading();
    try {
      final token = ref.read(settingsProvider).huggingFaceToken;
      final ggufRepo = ref.read(importedGgufModelsProvider.notifier).repository;
      final litertRepo = ref.read(importedLitertModelsProvider.notifier).repository;
      final ggufCount = await ggufRepo.checkForUpdates(token: token);
      final litertCount = await litertRepo.checkForUpdates(token: token);
      final total = ggufCount + litertCount;
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString(kLastUpdateCheckPref, DateTime.now().toIso8601String());
      state = AsyncValue.data(total);
      return total;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return 0;
    }
  }
}

final importedModelUpdateProvider =
    NotifierProvider<ImportedModelUpdateNotifier, AsyncValue<int>>(
  ImportedModelUpdateNotifier.new,
);

