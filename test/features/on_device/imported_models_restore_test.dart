import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/on_device/data/imported_gguf_model_repository.dart';
import 'package:localmind/features/on_device/data/imported_litert_model_repository.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ggufKey = 'imported_gguf_models_v1';
  const litertKey = 'imported_litert_models_v1';

  test('GGUF provider restores models from prefs on build', () async {
    final file = File('${Directory.systemTemp.path}/restore_gguf.gguf');
    await file.writeAsString('bytes');
    final metadata = ImportedGgufModelMetadata(
      id: 'restore-gguf',
      name: 'Restore GGUF',
      filePath: file.path,
      fileSizeBytes: 4,
      importedAt: DateTime.utc(2026, 6, 21),
      source: OnDeviceImportedSource.localFile,
    );
    SharedPreferences.setMockInitialValues({
      ggufKey: json.encode([metadata.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final models = container.read(importedGgufModelsProvider);
    expect(models.map((m) => m.id), contains('restore-gguf'));

    // Allow pruneMissing microtask to settle.
    await Future.delayed(const Duration(milliseconds: 50));
    final after = container.read(importedGgufModelsProvider);
    expect(after.map((m) => m.id), contains('restore-gguf'));

    await file.delete();
  });

  test('GGUF provider pruneMissing drops stale entries', () async {
    final metadata = ImportedGgufModelMetadata(
      id: 'stale-gguf',
      name: 'Stale GGUF',
      filePath: '${Directory.systemTemp.path}/does_not_exist_gguf.gguf',
      fileSizeBytes: 4,
      importedAt: DateTime.utc(2026, 6, 21),
      source: OnDeviceImportedSource.localFile,
    );
    SharedPreferences.setMockInitialValues({
      ggufKey: json.encode([metadata.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    // build returns stale initially
    expect(container.read(importedGgufModelsProvider).map((m) => m.id),
        contains('stale-gguf'));

    await container
        .read(importedGgufModelsProvider.notifier)
        .pruneMissing();
    expect(container.read(importedGgufModelsProvider).map((m) => m.id),
        isNot(contains('stale-gguf')));
  });

  test('LiteRT provider restores models from prefs on build', () async {
    final metadata = ImportedLitertModelMetadata(
      id: 'restore-litert',
      name: 'Restore LiteRT',
      filePath: '/tmp/restore.litertlm',
      fileSizeBytes: 4,
      importedAt: DateTime.utc(2026, 6, 21),
      source: OnDeviceImportedSource.localFile,
    );
    SharedPreferences.setMockInitialValues({
      litertKey: json.encode([metadata.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final models = container.read(importedLitertModelsProvider);
    expect(models.map((m) => m.id), contains('restore-litert'));
  });

  test('legacy collision: multiple entries share fileName', () async {
    // Two imported LiteRT entries with the same fileName -> collision.
    final a = ImportedLitertModelMetadata(
      id: 'coll-a',
      name: 'Coll A',
      fileSizeBytes: 4,
      importedAt: DateTime.utc(2026, 6, 21),
      source: OnDeviceImportedSource.localFile,
      installFileName: 'shared.litertlm',
    );
    final b = ImportedLitertModelMetadata(
      id: 'coll-b',
      name: 'Coll B',
      fileSizeBytes: 4,
      importedAt: DateTime.utc(2026, 6, 21),
      source: OnDeviceImportedSource.localFile,
      installFileName: 'shared.litertlm',
    );
    SharedPreferences.setMockInitialValues({
      litertKey: json.encode([a.toJson(), b.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final models = container.read(importedLitertModelsProvider);
    expect(models, hasLength(2));
    // downloadedModelsProvider filters collisions; verify at least both present.
    expect(models.map((m) => m.id), containsAll(['coll-a', 'coll-b']));
  });
}
