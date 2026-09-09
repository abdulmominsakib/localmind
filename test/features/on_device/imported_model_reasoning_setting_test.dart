import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/on_device/data/imported_gguf_model_repository.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/on_device/views/components/imported_model_reasoning_setting.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'editing thinking persists off/on/default and survives provider recreation',
    (tester) async {
      final file = (await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('reasoning-editor');
        addTearDown(() => dir.delete(recursive: true));
        return File('${dir.path}/test.gguf').writeAsString('GGUF');
      }))!;
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = ImportedGgufModelRepository(prefs, Dio());
      final metadata = ImportedGgufModelMetadata(
        id: 'test',
        name: 'Test',
        filePath: file.path,
        fileSizeBytes: 4,
        importedAt: DateTime.utc(2026),
        source: OnDeviceImportedSource.localFile,
      );
      await repository.saveAll([metadata]);
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, child) {
                  final model = ref.watch(importedGgufModelsProvider).single;
                  return ImportedModelReasoningSetting(model: model);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final entry in {
        'Off': false,
        'On': true,
        'Model default': null,
      }.entries) {
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(repository.load().single.reasoningEnabled, entry.value);
        expect(
          container.read(importedGgufModelsProvider).single.reasoningEnabled,
          entry.value,
        );
        final restored = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        expect(
          restored.read(importedGgufModelsProvider).single.reasoningEnabled,
          entry.value,
        );
        restored.dispose();
      }
      expect(tester.takeException(), isNull);
    },
  );
}
