import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/device/device_memory_service.dart';
import 'package:localmind/core/providers/device_info_providers.dart';
import 'package:localmind/features/on_device/components/on_device_picker_section.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/data/on_device_gemma_service.dart';
import 'package:localmind/features/on_device/data/on_device_mlx_service.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';

void main() {
  testWidgets('the chat picker deletes MLX models through the MLX service', (
    tester,
  ) async {
    final model = OnDeviceModel.curatedMlxModels.singleWhere(
      (model) => model.id == 'mlx-llama-3.2-1b',
    );
    final mlx = _RecordingMlxService();
    final gemma = _RecordingGemmaService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onDeviceModelsProvider.overrideWithValue([model]),
          onDeviceGemmaServiceProvider.overrideWithValue(gemma),
          onDeviceMlxServiceProvider.overrideWithValue(mlx),
          downloadedModelsProvider.overrideWith(
            (ref) async => mlx.deleted.isEmpty ? {model.id} : <String>{},
          ),
          deviceMemoryProvider.overrideWith(
            (ref) async => const DeviceMemoryInfo(
              totalMemoryMb: 8192,
              availableMemoryMb: 8192,
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: OnDevicePickerSection(selectedModelId: null, isDark: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(mlx.deleted, [model.id]);
    expect(gemma.deleted, isEmpty);
    expect(find.byTooltip('Download'), findsOneWidget);
  });
}

class _RecordingMlxService extends OnDeviceMlxService {
  _RecordingMlxService() : super(Dio(), nativeInferenceAvailable: false);

  final deleted = <String>[];

  @override
  Future<void> deleteModel(String modelId) async => deleted.add(modelId);
}

class _RecordingGemmaService extends OnDeviceGemmaService {
  final deleted = <String>[];

  @override
  String? get restoredActiveModelName => null;

  @override
  Future<void> deleteModel(String modelId) async => deleted.add(modelId);
}
