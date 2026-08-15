import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/service_providers.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/chat/providers/model_selection_providers.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/data/server_api_service.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('autoSelectFirstLoadedModelProvider', () {
    test('selects the configured default model when it is already loaded',
        () async {
      SharedPreferences.setMockInitialValues({
        'appSettings': AppSettings(
          defaultModelId: 'model-a',
          defaultModelServerId: 'server-1',
        ).toJson(),
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          activeServerProvider.overrideWith(_StubActiveServerNotifier.new),
          availableModelsProvider('server-1').overrideWith(
            (ref) async => _models(),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Mark the on-device engine as having the default model loaded.
      container.read(onDeviceEngineProvider.notifier).state =
          const OnDeviceEngineState(
        status: OnDeviceEngineStatus.loaded,
        loadedModelId: 'model-a',
      );

      await container.read(autoSelectFirstLoadedModelProvider.future);

      final selected = container.read(selectedModelProvider);
      expect(selected?.id, 'model-a');
    });

    test('selects the default model even when it is not loaded for LM Studio',
        () async {
      SharedPreferences.setMockInitialValues({
        'appSettings': AppSettings(
          defaultModelId: 'model-a',
          defaultModelServerId: 'server-1',
        ).toJson(),
      });
      final prefs = await SharedPreferences.getInstance();

      final api = _FakeServerApiService(loadedModelIds: const {});
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          activeServerProvider.overrideWith(_StubLmStudioActiveServer.new),
          connectionStatusProvider.overrideWith(
            _StubConnectedStatusNotifier.new,
          ),
          availableModelsProvider('server-1').overrideWith(
            (ref) async => _models(),
          ),
          serverApiServiceProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);

      await container.read(autoSelectFirstLoadedModelProvider.future);

      final selected = container.read(selectedModelProvider);
      expect(selected?.id, 'model-a');
      expect(api.loadedIds, contains('model-a'));
    });

    test('falls back to the first loaded model when no default is set',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final api = _FakeServerApiService(loadedModelIds: const {'model-b'});
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          activeServerProvider.overrideWith(_StubLmStudioActiveServer.new),
          connectionStatusProvider.overrideWith(
            _StubConnectedStatusNotifier.new,
          ),
          availableModelsProvider('server-1').overrideWith(
            (ref) async => _models(),
          ),
          serverApiServiceProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);

      await container.read(autoSelectFirstLoadedModelProvider.future);

      final selected = container.read(selectedModelProvider);
      expect(selected?.id, 'model-b');
    });

    test('selects the default model for cloud providers', () async {
      SharedPreferences.setMockInitialValues({
        'appSettings': AppSettings(
          defaultModelId: 'model-a',
          defaultModelServerId: 'server-1',
        ).toJson(),
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          activeServerProvider.overrideWith(_StubCloudActiveServer.new),
          connectionStatusProvider.overrideWith(
            _StubConnectedStatusNotifier.new,
          ),
          availableModelsProvider('server-1').overrideWith(
            (ref) async => _models(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(autoSelectFirstLoadedModelProvider.future);

      final selected = container.read(selectedModelProvider);
      expect(selected?.id, 'model-a');
    });

    test('does not throw or access disposed Ref when container is disposed during execution',
        () async {
      SharedPreferences.setMockInitialValues({
        'appSettings': AppSettings(
          defaultModelId: 'model-a',
          defaultModelServerId: 'server-1',
        ).toJson(),
      });
      final prefs = await SharedPreferences.getInstance();

      final api = _FakeServerApiService(loadedModelIds: const {});
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          activeServerProvider.overrideWith(_StubLmStudioActiveServer.new),
          connectionStatusProvider.overrideWith(
            _StubConnectedStatusNotifier.new,
          ),
          availableModelsProvider('server-1').overrideWith(
            (ref) async {
              await Future.delayed(const Duration(milliseconds: 50));
              return _models();
            },
          ),
          serverApiServiceProvider.overrideWithValue(api),
        ],
      );

      // Start the future and dispose container immediately
      final future = container.read(autoSelectFirstLoadedModelProvider.future);
      container.dispose();

      // Should complete without uncaught StateError
      expect(future, completes);
    });
  });
}
List<ModelInfo> _models() => [
      ModelInfo(
        id: 'model-a',
        name: 'Model A',
        serverType: ServerType.lmStudio,
        serverId: 'server-1',
      ),
      ModelInfo(
        id: 'model-b',
        name: 'Model B',
        serverType: ServerType.lmStudio,
        serverId: 'server-1',
      ),
    ];

class _StubActiveServerNotifier extends ActiveServerNotifier {
  @override
  Server? build() => _server(ServerType.onDevice);
}

class _StubLmStudioActiveServer extends ActiveServerNotifier {
  @override
  Server? build() => _server(ServerType.lmStudio);
}

class _StubCloudActiveServer extends ActiveServerNotifier {
  @override
  Server? build() => _server(ServerType.openAICompatible);
}

class _StubConnectedStatusNotifier extends ConnectionStatusNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

Server _server(ServerType type) {
  return Server(
    id: 'server-1',
    name: 'Server 1',
    type: type,
    host: 'localhost',
    port: 1234,
    createdAt: DateTime.utc(2026, 1, 1),
    lastConnectedAt: DateTime.utc(2026, 1, 1),
    status: ConnectionStatus.connected,
  );
}

class _FakeServerApiService extends ServerApiService {
  _FakeServerApiService({required this.loadedModelIds}) : super(Dio());

  final Set<String> loadedModelIds;
  final List<String> loadedIds = [];

  @override
  Future<Set<String>> fetchRunningModels(Server server) async => loadedModelIds;

  @override
  Future<String?> loadModelWithInstanceId(
    Server server,
    String modelId, {
    int? contextLength,
  }) async {
    loadedIds.add(modelId);
    return 'instance-1';
  }

  @override
  Future<void> unloadAllInstances(Server server, Set<String> instanceIds) async {}
}
