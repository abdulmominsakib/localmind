import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/server.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers/storage_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/storage/entities.dart';
import '../../models/data/model_cache.dart';

import '../../../objectbox.g.dart';
import '../../models/data/models/model_info.dart';
import '../../on_device/providers/on_device_providers.dart';
import '../../on_device/data/models/on_device_model.dart';

final _modelCache = ModelCache();

void invalidateAvailableModelsCache(String serverId) {
  _modelCache.invalidate(serverId);
}

void invalidateAllAvailableModelsCache() {
  _modelCache.invalidateAll();
}

final serversProvider = AsyncNotifierProvider<ServersNotifier, List<Server>>(
  () {
    return ServersNotifier();
  },
);

final activeServerIdProvider =
    NotifierProvider<ActiveServerIdNotifier, String?>(() {
      return ActiveServerIdNotifier();
    });

class ActiveServerIdNotifier extends Notifier<String?> {
  static const _key = 'defaultServerId';

  @override
  String? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getString(_key);
  }

  void setActiveServerId(String? id) {
    state = id;
    final prefs = ref.read(sharedPreferencesProvider);
    if (id != null) {
      prefs.setString(_key, id);
    } else {
      prefs.remove(_key);
    }
  }

  void setActiveServer(Server? server) {
    setActiveServerId(server?.id);
  }
}

final activeServerProvider = NotifierProvider<ActiveServerNotifier, Server?>(
  () {
    return ActiveServerNotifier();
  },
);

class ActiveServerNotifier extends Notifier<Server?> {
  @override
  Server? build() {
    final activeId = ref.watch(activeServerIdProvider);
    final servers = ref.watch(serversProvider).value ?? [];
    return _resolveServer(servers, activeId);
  }

  Server? _resolveServer(List<Server> servers, String? defaultServerId) {
    if (servers.isEmpty) return null;

    if (defaultServerId != null && defaultServerId.isNotEmpty) {
      final matching = servers.where((s) => s.id == defaultServerId);
      if (matching.isNotEmpty) return matching.first;
    }

    final defaults = servers.where((s) => s.isDefault);
    return defaults.isNotEmpty ? defaults.first : servers.first;
  }

  void setActiveServer(Server? server) {
    ref.read(activeServerIdProvider.notifier).setActiveServer(server);
    state = server;
  }
}

final connectionStatusProvider =
    NotifierProvider<ConnectionStatusNotifier, ConnectionStatus>(() {
      return ConnectionStatusNotifier();
    });

final loadedModelsRefreshProvider =
    NotifierProvider<LoadedModelsRefreshNotifier, int>(() {
      return LoadedModelsRefreshNotifier();
    });

class LoadedModelsRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void refresh() {
    state++;
  }
}

final loadedModelsProvider = FutureProvider.family<Set<String>, Server>((
  ref,
  server,
) async {
  ref.watch(loadedModelsRefreshProvider);

  if (server.type == ServerType.onDevice) {
    final engineState = ref.watch(onDeviceEngineProvider);
    return engineState.loadedModelId != null
        ? {engineState.loadedModelId!}
        : {};
  }

  if (server.type == ServerType.openAICompatible ||
      server.type == ServerType.openRouter) {
    return <String>{};
  }

  final apiService = ref.watch(serverApiServiceProvider);
  try {
    return await apiService.fetchRunningModels(server);
  } catch (e) {
    return {};
  }
});

final availableModelsProvider = FutureProvider.family<List<dynamic>, String>((
  ref,
  serverId,
) async {
  final serversAsync = ref.watch(serversProvider);
  final servers = serversAsync.value ?? [];
  final server = servers.firstWhere(
    (s) => s.id == serverId,
    orElse: () => throw Exception('Server not found'),
  );
  final apiService = ref.watch(serverApiServiceProvider);

  if (server.type == ServerType.onDevice) {
    final models = ref
        .watch(onDeviceModelsProvider)
        .map(
          (m) => ModelInfo(
            id: m.id,
            name: m.name,
            description: m.description,
            parameterCount: double.tryParse(
              m.parameterLabel.replaceAll(RegExp(r'[^0-9\.]'), ''),
            ),
            fileSize: m.fileSizeBytes,
            quantization: m.format == OnDeviceModelFormat.gguf
                ? 'GGUF'
                : m.format == OnDeviceModelFormat.mlx
                ? 'MLX 4-bit'
                : m.format == OnDeviceModelFormat.builtIn
                ? 'System AI'
                : null,
            architecture: m.runtime == OnDeviceModelRuntime.llamaCpp
                ? 'llama.cpp'
                : m.runtime == OnDeviceModelRuntime.mlx
                ? 'Apple MLX'
                : m.isBuiltIn
                ? 'Built-in OS AI'
                : null,
            serverType: ServerType.onDevice,
            serverId: server.id,
            modifiedAt: m.importedAt,
            onDeviceRuntime: m.runtime,
            onDeviceFormat: m.format,
            localPath: m.localPath,
            supportsVision: m.supportsVision,
            supportsReasoning: m.supportsThinking,
            supportsToolUse: m.supportsFunctionCalling,
          ),
        )
        .toList();
    _modelCache.put(serverId, models);
    return models;
  }

  final cached = _modelCache.get(serverId);
  if (cached != null) return cached;

  final models = await apiService.fetchModels(server);
  _modelCache.put(serverId, models);
  return models;
});

class ServersNotifier extends AsyncNotifier<List<Server>> {
  @override
  Future<List<Server>> build() async {
    return _loadAll();
  }

  Future<List<Server>> _loadAll() async {
    if (!ref.mounted) return [];
    final db = ref.read(databaseProvider);
    final entities = db.serverBox.getAll();
    return entities.map((e) => e.toDomain()).toList();
  }

  Future<void> addServer(Server server) async {
    if (!ref.mounted) return;
    final db = ref.read(databaseProvider);
    db.serverBox.put(ServerEntity.fromDomain(server));
    invalidateAvailableModelsCache(server.id);
    final data = await _loadAll();
    if (ref.mounted) {
      state = AsyncData(data);
    }
  }

  Future<void> updateServer(Server server) async {
    if (!ref.mounted) return;
    final db = ref.read(databaseProvider);
    final query = db.serverBox
        .query(ServerEntity_.id.equals(server.id))
        .build();
    final existing = query.findFirst();
    query.close();

    final entity = ServerEntity.fromDomain(server);
    if (existing != null) {
      entity.internalId = existing.internalId;
    }
    db.serverBox.put(entity);
    invalidateAvailableModelsCache(server.id);
    final data = await _loadAll();
    if (ref.mounted) {
      state = AsyncData(data);
    }
  }

  Future<void> deleteServer(String serverId) async {
    if (!ref.mounted) return;
    final db = ref.read(databaseProvider);
    final query = db.serverBox.query(ServerEntity_.id.equals(serverId)).build();
    db.serverBox.removeMany(query.findIds());
    query.close();
    invalidateAvailableModelsCache(serverId);
    final data = await _loadAll();
    if (ref.mounted) {
      state = AsyncData(data);
    }
  }

  Future<void> setDefault(String serverId) async {
    if (!ref.mounted) return;
    final db = ref.read(databaseProvider);
    final servers = state.value ?? [];
    final updatedServers = servers.map((s) {
      return s.copyWith(isDefault: s.id == serverId);
    }).toList();

    for (final server in updatedServers) {
      final query = db.serverBox
          .query(ServerEntity_.id.equals(server.id))
          .build();
      final existing = query.findFirst();
      query.close();

      final entity = ServerEntity.fromDomain(server);
      if (existing != null) {
        entity.internalId = existing.internalId;
      }
      db.serverBox.put(entity);
      invalidateAvailableModelsCache(server.id);
    }
    final data = await _loadAll();
    if (ref.mounted) {
      state = AsyncData(data);
    }
  }

  Future<void> updateServerStatus(
    String serverId,
    ConnectionStatus status,
  ) async {
    final servers = state.value ?? [];
    final index = servers.indexWhere((s) => s.id == serverId);
    if (index == -1) return;
    final server = servers[index];
    if (server.status == status) return;

    final updatedServer = server.copyWith(
      status: status,
      lastConnectedAt: status == ConnectionStatus.connected
          ? DateTime.now()
          : server.lastConnectedAt,
    );
    final db = ref.read(databaseProvider);

    final query = db.serverBox
        .query(ServerEntity_.id.equals(updatedServer.id))
        .build();
    final existing = query.findFirst();
    query.close();

    final entity = ServerEntity.fromDomain(updatedServer);
    if (existing != null) {
      entity.internalId = existing.internalId;
    }
    db.serverBox.put(entity);
    invalidateAvailableModelsCache(updatedServer.id);

    if (!ref.mounted) return;
    state = AsyncData(await _loadAll());
  }

  Future<ConnectionStatus> testConnection(
    String serverId,
    dynamic apiService,
  ) async {
    final servers = state.value ?? [];
    final index = servers.indexWhere((s) => s.id == serverId);
    if (index == -1) return ConnectionStatus.disconnected;
    final server = servers[index];

    if (server.type == ServerType.onDevice) {
      await updateServerStatus(serverId, ConnectionStatus.connected);
      return ConnectionStatus.connected;
    }

    final isConnected = await apiService.testConnection(server);
    if (!ref.mounted) {
      return isConnected
          ? ConnectionStatus.connected
          : ConnectionStatus.disconnected;
    }
    final status = isConnected
        ? ConnectionStatus.connected
        : ConnectionStatus.disconnected;

    await updateServerStatus(serverId, status);
    return status;
  }

  Future<void> testAllConnections(dynamic apiService) async {
    final servers = state.value ?? [];
    for (final server in servers) {
      if (!ref.mounted) return;
      await testConnection(server.id, apiService);
    }
  }
}

class ConnectionStatusNotifier extends Notifier<ConnectionStatus> {
  int _checkGeneration = 0;

  @override
  ConnectionStatus build() {
    final activeServer = ref.watch(activeServerProvider);
    final apiService = ref.watch(serverApiServiceProvider);

    if (activeServer == null) {
      return ConnectionStatus.disconnected;
    }

    if (activeServer.type == ServerType.onDevice) {
      return ConnectionStatus.connected;
    }

    final generation = ++_checkGeneration;
    Future.microtask(
      () => _checkConnection(activeServer, apiService, generation),
    );
    return ConnectionStatus.checking;
  }

  Future<void> _checkConnection(
    Server server,
    dynamic apiService,
    int generation,
  ) async {
    try {
      final isConnected = await apiService.testConnection(server);
      if (!ref.mounted || generation != _checkGeneration) return;
      state = isConnected
          ? ConnectionStatus.connected
          : ConnectionStatus.disconnected;
    } catch (e) {
      if (!ref.mounted || generation != _checkGeneration) return;
      state = ConnectionStatus.error;
    }
  }

  Future<void> refresh() async {
    if (!ref.mounted) return;
    final activeServer = ref.read(activeServerProvider);
    final apiService = ref.read(serverApiServiceProvider);
    if (activeServer != null) {
      state = ConnectionStatus.checking;
      final generation = ++_checkGeneration;
      await _checkConnection(activeServer, apiService, generation);
    }
  }
}
