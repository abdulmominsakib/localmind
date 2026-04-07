import 'package:hive_ce/hive.dart';
import 'package:localmind/core/models/enums.dart';

part 'server.g.dart';

@HiveType(typeId: 0)
class Server extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final ServerType type;

  @HiveField(3)
  final String host;

  @HiveField(4)
  final int port;

  @HiveField(5)
  final String? apiKey;

  @HiveField(6)
  final bool isDefault;

  @HiveField(7)
  final DateTime createdAt;

  @HiveField(8)
  final DateTime lastConnectedAt;

  @HiveField(9)
  final ConnectionStatus status;

  @HiveField(10)
  final String? iconName;

  Server({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    this.apiKey,
    this.isDefault = false,
    required this.createdAt,
    required this.lastConnectedAt,
    this.status = ConnectionStatus.disconnected,
    this.iconName,
  });

  String get baseUrl {
    if (type == ServerType.openRouter) {
      return 'https://openrouter.ai/api/v1';
    }
    return 'http://$host:$port';
  }

  String get chatEndpoint {
    switch (type) {
      case ServerType.lmStudio:
        return '$baseUrl/api/v1/chat';
      case ServerType.openAICompatible:
        return '$baseUrl/v1/chat/completions';
      case ServerType.ollama:
        return '$baseUrl/api/chat';
      case ServerType.openRouter:
        return '$baseUrl/chat/completions';
    }
  }

  String get modelsEndpoint {
    switch (type) {
      case ServerType.lmStudio:
        return '$baseUrl/api/v1/models';
      case ServerType.openAICompatible:
        return '$baseUrl/v1/models';
      case ServerType.ollama:
        return '$baseUrl/api/tags';
      case ServerType.openRouter:
        return '$baseUrl/models';
    }
  }

  String get runningModelsEndpoint {
    switch (type) {
      case ServerType.lmStudio:
        return '$baseUrl/api/v1/models';
      case ServerType.openAICompatible:
        return '$baseUrl/v1/models';
      case ServerType.ollama:
        return '$baseUrl/api/ps';
      case ServerType.openRouter:
        return '';
    }
  }

  String get loadModelEndpoint {
    switch (type) {
      case ServerType.lmStudio:
        return '$baseUrl/api/v1/models/load';
      case ServerType.openAICompatible:
        return '$baseUrl/v1/models/load';
      case ServerType.ollama:
        return '$baseUrl/api/generate';
      case ServerType.openRouter:
        return '';
    }
  }

  String get unloadModelEndpoint {
    switch (type) {
      case ServerType.lmStudio:
        return '$baseUrl/api/v1/models/unload';
      case ServerType.openAICompatible:
        return '$baseUrl/v1/models/unload';
      case ServerType.ollama:
        return '$baseUrl/api/generate';
      case ServerType.openRouter:
        return '';
    }
  }

  Server copyWith({
    String? id,
    String? name,
    ServerType? type,
    String? host,
    int? port,
    String? apiKey,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? lastConnectedAt,
    ConnectionStatus? status,
    String? iconName,
  }) {
    return Server(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      host: host ?? this.host,
      port: port ?? this.port,
      apiKey: apiKey ?? this.apiKey,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      status: status ?? this.status,
      iconName: iconName ?? this.iconName,
    );
  }
}
