import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/providers/service_providers.dart';
import 'package:localmind/features/models/data/model_cache.dart';

final _modelCache = ModelCache();

final serversProvider = NotifierProvider<ServersNotifier, List<Server>>(() {
  return ServersNotifier();
});

final activeServerProvider = NotifierProvider<ActiveServerNotifier, Server?>(
  () {
    return ActiveServerNotifier();
  },
);

final connectionStatusProvider =
    NotifierProvider<ConnectionStatusNotifier, ConnectionStatus>(() {
      return ConnectionStatusNotifier();
    });

final availableModelsProvider = FutureProvider.family<List<dynamic>, String>((
  ref,
  serverId,
) async {
  final cached = _modelCache.get(serverId);
  if (cached != null) return cached;

  final servers = ref.watch(serversProvider);
  final server = servers.firstWhere(
    (s) => s.id == serverId,
    orElse: () => throw Exception('Server not found'),
  );
  final apiService = ref.watch(serverApiServiceProvider);
  final models = await apiService.fetchModels(server);
  _modelCache.put(serverId, models);
  return models;
});

class ServersNotifier extends Notifier<List<Server>> {
  @override
  List<Server> build() {
    final boxes = ref.watch(hiveBoxesProvider);
    return boxes.servers.values.toList().cast<Server>();
  }

  Future<void> addServer(Server server) async {
    final boxes = ref.read(hiveBoxesProvider);
    await boxes.servers.put(server.id, server);
    state = boxes.servers.values.toList().cast<Server>();
  }

  Future<void> updateServer(Server server) async {
    final boxes = ref.read(hiveBoxesProvider);
    await boxes.servers.put(server.id, server);
    state = boxes.servers.values.toList().cast<Server>();
  }

  Future<void> deleteServer(String serverId) async {
    final boxes = ref.read(hiveBoxesProvider);
    await boxes.servers.delete(serverId);
    state = boxes.servers.values.toList().cast<Server>();
  }

  Future<void> setDefault(String serverId) async {
    final boxes = ref.read(hiveBoxesProvider);
    final updatedServers = state.map((s) {
      return s.copyWith(isDefault: s.id == serverId);
    }).toList();

    for (final server in updatedServers) {
      await boxes.servers.put(server.id, server);
    }
    state = boxes.servers.values.toList().cast<Server>();
  }

  Future<ConnectionStatus> testConnection(
    String serverId,
    dynamic apiService,
  ) async {
    final server = state.firstWhere((s) => s.id == serverId);
    final isConnected = await apiService.testConnection(server);
    final status = isConnected
        ? ConnectionStatus.connected
        : ConnectionStatus.error;

    final updatedServer = server.copyWith(
      status: status,
      lastConnectedAt: DateTime.now(),
    );
    final boxes = ref.read(hiveBoxesProvider);
    await boxes.servers.put(serverId, updatedServer);
    state = boxes.servers.values.toList().cast<Server>();
    return status;
  }
}

class ActiveServerNotifier extends Notifier<Server?> {
  @override
  Server? build() {
    final servers = ref.watch(serversProvider);
    final boxes = ref.watch(hiveBoxesProvider);
    final defaultServerIdObj = boxes.settings.get('defaultServerId');

    String? defaultServerId;
    if (defaultServerIdObj is String && defaultServerIdObj.isNotEmpty) {
      defaultServerId = defaultServerIdObj;
    }

    if (defaultServerId != null) {
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
    final boxes = ref.read(hiveBoxesProvider);
    state = server;
    if (server != null) {
      boxes.settings.put('defaultServerId', server.id);
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
