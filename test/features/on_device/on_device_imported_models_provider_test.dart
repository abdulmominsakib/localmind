import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/on_device/data/imported_gguf_model_repository.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/data/on_device_gemma_service.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const storageKey = 'imported_gguf_models_v1';

  test(
    'onDeviceModelsProvider merges curated and imported GGUF models',
    () async {
      final metadata = ImportedGgufModelMetadata(
        id: 'gguf-imported',
        name: 'Imported GGUF',
        filePath: '/tmp/imported.gguf',
        fileSizeBytes: 4096,
        importedAt: DateTime.utc(2026, 6, 21),
        source: OnDeviceImportedSource.localFile,
      );
      SharedPreferences.setMockInitialValues({
        storageKey: json.encode([metadata.toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final models = container.read(onDeviceModelsProvider);
      final imported = models.singleWhere((model) => model.id == metadata.id);

      expect(models.map((model) => model.id), contains('gemma4-e2b-instruct'));
      expect(imported.runtime, OnDeviceModelRuntime.llamaCpp);
      expect(imported.format, OnDeviceModelFormat.gguf);
      expect(imported.localPath, metadata.filePath);
      expect(imported.isImported, isTrue);
      expect(imported.importedSource, OnDeviceImportedSource.localFile);
    },
  );

  test(
    'downloadedModelsProvider treats imported GGUF models as local',
    () async {
      final downloadedFile = File('/tmp/downloaded.gguf');
      await downloadedFile.writeAsString('gguf bytes');
      final metadata = ImportedGgufModelMetadata(
        id: 'gguf-downloaded',
        name: 'Downloaded GGUF',
        filePath: downloadedFile.path,
        fileSizeBytes: 4096,
        importedAt: DateTime.utc(2026, 6, 21),
        source: OnDeviceImportedSource.localFile,
      );
      SharedPreferences.setMockInitialValues({
        storageKey: json.encode([metadata.toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          onDeviceGemmaServiceProvider.overrideWithValue(
            _FakeOnDeviceGemmaService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final downloaded = await container.read(downloadedModelsProvider.future);

      expect(downloaded, contains('gguf-downloaded'));
    },
  );
}

class _FakeOnDeviceGemmaService extends OnDeviceGemmaService {
  @override
  Future<List<String>> getInstalledModelIds() async {
    return ['gemma4-e2b-instruct'];
  }
}
