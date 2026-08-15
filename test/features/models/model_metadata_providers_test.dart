import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/models/providers/model_metadata_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ModelMetadataNotifier (Issue #50)', () {
    test('loads metadata for server and toggles favorite', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(modelMetadataProvider.notifier);
      notifier.loadForServer('server-1');

      expect(container.read(modelMetadataProvider), isEmpty);

      await notifier.toggleFavorite('model-1');
      expect(container.read(modelMetadataProvider)['model-1']?.isFavorite, isTrue);

      await notifier.setNote('model-1', 'My favorite model');
      expect(container.read(modelMetadataProvider)['model-1']?.note, 'My favorite model');
    });

    test('does not throw or access disposed Ref when disposed during async write', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );

      final notifier = container.read(modelMetadataProvider.notifier);
      notifier.loadForServer('server-1');

      // Start async toggleFavorite and dispose container immediately
      final future = notifier.toggleFavorite('model-1');
      container.dispose();

      // Completing without throwing StateError confirms ref.mounted guard works
      await expectLater(future, completes);
    });
  });
}
