import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/device/device_memory_service.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/device_info_providers.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/chat/providers/model_selection_providers.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/voice_mode/views/voice_mode_overlay.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows the effective server and model without overflowing', (
    tester,
  ) async {
    final target = ActiveChatTarget(
      server: Server(
        id: 'on-device',
        name: 'On-Device',
        type: ServerType.onDevice,
        host: '',
        port: 0,
        createdAt: DateTime.utc(2026, 8, 13),
        lastConnectedAt: DateTime.utc(2026, 8, 13),
        status: ConnectionStatus.connected,
      ),
      selectedModel: null,
      effectiveModelId: 'smollm2-135m-instruct',
      modelLabel: 'SmolLM 135M Instruct',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [activeChatTargetProvider.overrideWith((ref) => target)],
        child: const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 210, child: VoiceTargetChip()),
            ),
          ),
        ),
      ),
    );

    expect(find.text('On-Device'), findsOneWidget);
    expect(find.text('SmolLM 135M Instruct'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline picker scrolls and selects without closing voice mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final model = OnDeviceModel.curatedModels.firstWhere(
      (candidate) => candidate.id == 'smollm2-135m-instruct',
    );

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        activeServerProvider.overrideWith(_OnDeviceServerNotifier.new),
        onDeviceEngineProvider.overrideWith(_LoadedEngineNotifier.new),
        onDeviceModelsProvider.overrideWith((ref) => [model]),
        downloadedModelsProvider.overrideWith((ref) async => {model.id}),
        deviceMemoryProvider.overrideWith(
          (ref) async => const DeviceMemoryInfo(
            totalMemoryMb: 8192,
            availableMemoryMb: 8192,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SizedBox(
              width: 390,
              height: 300,
              child: VoiceModelPickerPanel(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('voice-model-picker-panel')),
      findsOneWidget,
    );
    expect(find.byType(Scrollable), findsWidgets);

    await tester.tap(find.text('SmolLM 135M Instruct'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('voice-model-picker-panel')),
      findsOneWidget,
    );
    expect(container.read(selectedModelProvider)?.id, model.id);
    expect(tester.takeException(), isNull);
  });
}

class _OnDeviceServerNotifier extends ActiveServerNotifier {
  @override
  Server? build() => Server(
    id: 'on-device',
    name: 'On-Device',
    type: ServerType.onDevice,
    host: '',
    port: 0,
    createdAt: DateTime.utc(2026, 8, 13),
    lastConnectedAt: DateTime.utc(2026, 8, 13),
    status: ConnectionStatus.connected,
  );
}

class _LoadedEngineNotifier extends OnDeviceEngineNotifier {
  @override
  OnDeviceEngineState build() => const OnDeviceEngineState(
    status: OnDeviceEngineStatus.loaded,
    loadedModelId: 'smollm2-135m-instruct',
  );
}
