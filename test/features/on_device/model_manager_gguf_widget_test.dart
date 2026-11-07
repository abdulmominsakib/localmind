import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/device/device_memory_service.dart';
import 'package:localmind/core/providers/device_info_providers.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/theme/app_theme.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/data/on_device_gemma_service.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/on_device/views/model_manager_screen.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('model manager shows Import GGUF and imported model actions', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final importedModel = OnDeviceModel(
        id: 'gguf-widget',
        name: 'Widget GGUF',
        huggingFaceUrl: '',
        fileSizeBytes: 4096,
        license: 'Local file',
        description: 'Imported GGUF model for local llama.cpp inference.',
        minRamMb: 2048,
        parameterLabel: 'GGUF',
        bestFor: 'Local GGUF inference',
        languagesLabel: 'Local',
        backendNote: 'llama.cpp',
        isCpuOnly: true,
        runtime: OnDeviceModelRuntime.llamaCpp,
        format: OnDeviceModelFormat.gguf,
        localPath: '/tmp/widget.gguf',
        importedAt: DateTime.utc(2026, 6, 21),
        isImported: true,
        importedSource: OnDeviceImportedSource.localFile,
      );

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            onDeviceGemmaServiceProvider.overrideWithValue(
              _FakeOnDeviceGemmaService(),
            ),
            onDeviceModelsProvider.overrideWith(
              (ref) => [...OnDeviceModel.curatedModels, importedModel],
            ),
            downloadedModelsProvider.overrideWith(
              (ref) async => {'gguf-widget'},
            ),
            deviceMemoryProvider.overrideWith(
              (ref) async => const DeviceMemoryInfo(
                totalMemoryMb: 8192,
                availableMemoryMb: 8192,
              ),
            ),
          ],
          child: ShadTheme(
            data: AppTheme.lightShadTheme,
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: OnDeviceModelManagerScreen()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('Add models'), findsWidgets);
      expect(find.text('On-Device Models'), findsWidgets);

      await tester.scrollUntilVisible(find.text('Widget GGUF'), 400);
      await tester.pump();
      expect(find.text('Local file'), findsWidgets);
      expect(find.text('GGUF'), findsWidgets);
      expect(find.text('llama.cpp'), findsWidgets);
      expect(find.text('Load'), findsWidgets);
      expect(find.text('Delete'), findsWidgets);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

class _FakeOnDeviceGemmaService extends OnDeviceGemmaService {
  @override
  Future<List<String>> getInstalledModelIds() async {
    return [];
  }
}
