import '../../../../core/models/enums.dart';

class Server {
  final String id;
  final String name;
  final ServerType type;
  final String host;
  final int port;
  final String? apiKey;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime lastConnectedAt;
  final ConnectionStatus status;
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
    if (type == ServerType.onDevice) {
      return 'on-device';
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
      case ServerType.onDevice:
        return '';
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
      case ServerType.onDevice:
        return '';
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
      case ServerType.onDevice:
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
      case ServerType.onDevice:
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
      case ServerType.onDevice:
        return '';
    }
  }

  bool get isOnDevice => type == ServerType.onDevice;

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
