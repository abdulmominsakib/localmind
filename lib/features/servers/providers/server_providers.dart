import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/server.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers/storage_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/storage/entities.dart';
import '../../models/data/model_cache.dart';

import '../../../objectbox.g.dart';

final _modelCache = ModelCache();

bool _onDeviceServerEnsured = false;

final ensureOnDeviceServerProvider = FutureProvider<void>((ref) async {
  if (_onDeviceServerEnsured) return;

  final serversAsync = ref.watch(serversProvider);

  if (!serversAsync.hasValue) return;

  final servers = serversAsync.value!;
  final hasOnDevice = servers.any((s) => s.type == ServerType.onDevice);
  if (hasOnDevice) {
    _onDeviceServerEnsured = true;
    return;
  }

  final server = Server(
    id: 'on-device',
    name: 'On-Device',
    type: ServerType.onDevice,
    host: '',
    port: 0,
    isDefault: false,
    createdAt: DateTime.now(),
    lastConnectedAt: DateTime.now(),
    status: ConnectionStatus.connected,
    iconName: 'strokeRoundedSmartPhone01',
  );
  await ref.read(serversProvider.notifier).addServer(server);
  _onDeviceServerEnsured = true;
});

final serversProvider = AsyncNotifierProvider<ServersNotifier, List<Server>>(
  () {
    return ServersNotifier();
  },
);

final activeServerProvider = NotifierProvider<ActiveServerNotifier, Server?>(
  () {
    return ActiveServerNotifier();
  },
);

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
  final cached = _modelCache.get(serverId);
  if (cached != null) return cached;

  final serversAsync = ref.watch(serversProvider);
  final servers = serversAsync.value ?? [];
  final server = servers.firstWhere(
    (s) => s.id == serverId,
    orElse: () => throw Exception('Server not found'),
  );
  final apiService = ref.watch(serverApiServiceProvider);
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
    final db = ref.read(databaseProvider);
    final entities = db.serverBox.getAll();
    return entities.map((e) => e.toDomain()).toList();
  }

  Future<void> addServer(Server server) async {
    final db = ref.read(databaseProvider);
    db.serverBox.put(ServerEntity.fromDomain(server));
    state = AsyncData(await _loadAll());
  }

  Future<void> updateServer(Server server) async {
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
    state = AsyncData(await _loadAll());
  }

  Future<void> deleteServer(String serverId) async {
    final db = ref.read(databaseProvider);
    final query = db.serverBox.query(ServerEntity_.id.equals(serverId)).build();
    db.serverBox.removeMany(query.findIds());
    query.close();
    state = AsyncData(await _loadAll());
  }

  Future<void> setDefault(String serverId) async {
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
    }
    state = AsyncData(await _loadAll());
  }

  Future<ConnectionStatus> testConnection(
    String serverId,
    dynamic apiService,
  ) async {
    final servers = state.value ?? [];
    final server = servers.firstWhere((s) => s.id == serverId);
    final isConnected = await apiService.testConnection(server);
    final status = isConnected
        ? ConnectionStatus.connected
        : ConnectionStatus.error;

    final updatedServer = server.copyWith(
      status: status,
      lastConnectedAt: DateTime.now(),
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

    state = AsyncData(await _loadAll());
    return status;
  }
}

class ActiveServerNotifier extends Notifier<Server?> {
  @override
  Server? build() {
    final serversAsync = ref.watch(serversProvider);
    final servers = serversAsync.value ?? [];
    if (servers.isEmpty) return null;

    final prefs = ref.watch(sharedPreferencesProvider);
    final defaultServerId = prefs.getString('defaultServerId');

    if (defaultServerId != null && defaultServerId.isNotEmpty) {
      final matchingServer = servers.where((s) => s.id == defaultServerId);
      if (matchingServer.isNotEmpty) {
        return matchingServer.first;
      }
    }

    if (servers.isNotEmpty) {
      final defaultServer = servers.where((s) => s.isDefault);
      return defaultServer.isNotEmpty ? defaultServer.first : servers.first;
    }
    return null;
  }

  void setActiveServer(Server? server) {
    final prefs = ref.read(sharedPreferencesProvider);
    state = server;
    if (server != null) {
      prefs.setString('defaultServerId', server.id);
    } else {
      prefs.remove('defaultServerId');
    }
  }
}

class ConnectionStatusNotifier extends Notifier<ConnectionStatus> {
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

    _checkConnection(activeServer, apiService);
    return ConnectionStatus.checking;
  }

  Future<void> _checkConnection(Server server, dynamic apiService) async {
    try {
      final isConnected = await apiService.testConnection(server);
      state = isConnected ? ConnectionStatus.connected : ConnectionStatus.error;
    } catch (e) {
      state = ConnectionStatus.error;
    }
  }

  Future<void> refresh() async {
    final activeServer = ref.read(activeServerProvider);
    final apiService = ref.read(serverApiServiceProvider);
    if (activeServer != null) {
      state = ConnectionStatus.checking;
      await _checkConnection(activeServer, apiService);
    }
  }
}
