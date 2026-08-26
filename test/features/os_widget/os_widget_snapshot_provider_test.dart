import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/os_widget/providers/os_widget_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';

class _TestSettingsNotifier extends SettingsNotifier {
  _TestSettingsNotifier({this.customSettings});
  final AppSettings? customSettings;

  @override
  AppSettings build() => customSettings ?? AppSettings();
}

class _StubServersNotifier extends ServersNotifier {
  _StubServersNotifier([this.servers = const []]);
  final List<Server> servers;

  @override
  Future<List<Server>> build() async => servers;
}

void main() {
  group('osWidgetSnapshotProvider', () {
    test(
      'returns unconfigured snapshot when no default model is set',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            settingsProvider.overrideWith(_TestSettingsNotifier.new),
            serversProvider.overrideWith(_StubServersNotifier.new),
          ],
        );
        addTearDown(container.dispose);

        // Force settings to build
        container.read(settingsProvider);

        final snapshot = container.read(osWidgetSnapshotProvider);
        expect(snapshot.isConfigured, isFalse);
        expect(snapshot.modelName, isNull);
      },
    );

    test('returns configured snapshot with model display name', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final server = Server(
        id: 'srv-1',
        name: 'Test Server',
        host: 'http://localhost',
        port: 11434,
        type: ServerType.ollama,
        createdAt: DateTime.now(),
        lastConnectedAt: DateTime.now(),
      );
      final model = ModelInfo(
        id: 'llama3:8b',
        name: 'Llama 3 8B',
        serverId: server.id,
        serverType: ServerType.ollama,
      );

      final settings = AppSettings(
        defaultModelId: model.id,
        defaultModelServerId: server.id,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          settingsProvider.overrideWith(
            () => _TestSettingsNotifier(customSettings: settings),
          ),
          serversProvider.overrideWith(() => _StubServersNotifier([server])),
          availableModelsProvider(
            server.id,
          ).overrideWith((ref) async => [model]),
        ],
      );
      addTearDown(container.dispose);

      // Touch the future to force it to resolve before we read the snapshot.
      await container.read(availableModelsProvider(server.id).future);

      final snapshot = container.read(osWidgetSnapshotProvider);
      expect(snapshot.isConfigured, isTrue);
      expect(snapshot.modelName, 'Llama 3 8B');
    });

    test(
      'falls back to model id when model is missing from available list',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        final server = Server(
          id: 'srv-1',
          name: 'Test Server',
          host: 'http://localhost',
          port: 11434,
          type: ServerType.ollama,
          createdAt: DateTime.now(),
          lastConnectedAt: DateTime.now(),
        );

        final settings = AppSettings(
          defaultModelId: 'missing-model',
          defaultModelServerId: server.id,
        );

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            settingsProvider.overrideWith(
              () => _TestSettingsNotifier(customSettings: settings),
            ),
            serversProvider.overrideWith(() => _StubServersNotifier([server])),
            availableModelsProvider(server.id).overrideWith((ref) async => []),
          ],
        );
        addTearDown(container.dispose);

        await container.read(availableModelsProvider(server.id).future);

        final snapshot = container.read(osWidgetSnapshotProvider);
        expect(snapshot.isConfigured, isTrue);
        expect(snapshot.modelName, 'missing-model');
      },
    );
  });
}
