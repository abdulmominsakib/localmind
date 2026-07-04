import '../../../../core/models/enums.dart';

bool _hasExplicitHttpScheme(String input) {
  final trimmed = input.trim().toLowerCase();
  return trimmed.startsWith('http://') || trimmed.startsWith('https://');
}

Uri? parseServerAddressInput(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  final candidate = _hasExplicitHttpScheme(trimmed) ? trimmed : 'http://$trimmed';
  final uri = Uri.tryParse(candidate);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.path.isNotEmpty && uri.path != '/') return null;
  return uri;
}

bool isHttpsAddressInput(String input) {
  return input.trim().toLowerCase().startsWith('https://');
}

Uri _normalizeNetworkUri(Uri uri, {int? port}) {
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: port ?? (uri.hasPort ? uri.port : null),
  );
}

String displayServerAddress(String host, int port, ServerType type) {
  if (type == ServerType.openRouter) {
    return 'openrouter.ai';
  }
  if (type == ServerType.onDevice) {
    return 'Local inference';
  }

  final trimmedHost = host.trim();
  if (trimmedHost.isEmpty) {
    return port > 0 ? 'localhost:$port' : 'localhost';
  }

  if (_hasExplicitHttpScheme(trimmedHost)) {
    final uri = parseServerAddressInput(trimmedHost);
    if (uri != null) {
      return _normalizeNetworkUri(
        uri,
        port: uri.hasPort || port <= 0 ? null : port,
      ).toString();
    }
    return trimmedHost;
  }

  if (trimmedHost.contains(':')) {
    return trimmedHost;
  }

  return port > 0 ? '$trimmedHost:$port' : trimmedHost;
}

String buildServerBaseUrl(String host, int port, ServerType type) {
  if (type == ServerType.openRouter) {
    return 'https://openrouter.ai/api/v1';
  }
  if (type == ServerType.onDevice) {
    return 'on-device';
  }

  final trimmedHost = host.trim();
  final uri = parseServerAddressInput(trimmedHost);
  if (uri != null) {
    return _normalizeNetworkUri(
      uri,
      port: uri.hasPort || port <= 0 ? null : port,
    ).toString();
  }

  if (trimmedHost.isEmpty) {
    return '';
  }

  if (port <= 0) {
    return 'http://$trimmedHost';
  }

  final protocol = (port == 443) ? 'https' : 'http';
  return '$protocol://$trimmedHost:$port';
}

/// Authorization header for [server], or an empty map when no key is set so
/// callers can spread it unconditionally into their headers map.
Map<String, String> buildServerAuthHeaders(Server server) {
  if (server.apiKey?.isNotEmpty ?? false) {
    return {'Authorization': 'Bearer ${server.apiKey}'};
  }
  return const {};
}

String normalizeServerPathPrefix(String? raw) {
  if (raw == null) return '';
  var value = raw.trim();
  if (value.isEmpty) return '';
  if (!value.startsWith('/')) value = '/$value';
  while (value.endsWith('/') && value.length > 1) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

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
  final String? pathPrefix;
  /// Optional system RAM in GB for model compatibility hints in the browser.
  final int? availableRamGb;
  /// Optional GPU VRAM in GB for model compatibility hints in the browser.
  final int? availableVramGb;

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
    this.pathPrefix,
    this.availableRamGb,
    this.availableVramGb,
  });

  String get apiPathPrefix => normalizeServerPathPrefix(pathPrefix);

  String _apiPath(String suffix) {
    if (type != ServerType.ollama || apiPathPrefix.isEmpty) {
      return suffix;
    }
    return '$apiPathPrefix$suffix';
  }

  String get baseUrl {
    return buildServerBaseUrl(host, port, type);
  }

  Map<String, String> get authHeaders => buildServerAuthHeaders(this);

  String get chatEndpoint {
    switch (type) {
      case ServerType.lmStudio:
        return '$baseUrl/v1/chat/completions';
      case ServerType.openAICompatible:
        return '$baseUrl/v1/chat/completions';
      case ServerType.ollama:
        return '$baseUrl${_apiPath('/api/chat')}';
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
        return '$baseUrl${_apiPath('/api/tags')}';
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
        return '$baseUrl${_apiPath('/api/ps')}';
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
        return '$baseUrl${_apiPath('/api/generate')}';
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
        return '$baseUrl${_apiPath('/api/generate')}';
      case ServerType.openRouter:
        return '';
      case ServerType.onDevice:
        return '';
    }
  }

  bool get isOnDevice => type == ServerType.onDevice;

  String get displayAddress => displayServerAddress(host, port, type);

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
    String? pathPrefix,
    int? availableRamGb,
    int? availableVramGb,
    bool clearPathPrefix = false,
    bool clearAvailableRamGb = false,
    bool clearAvailableVramGb = false,
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
      pathPrefix: clearPathPrefix ? null : (pathPrefix ?? this.pathPrefix),
      availableRamGb:
          clearAvailableRamGb ? null : (availableRamGb ?? this.availableRamGb),
      availableVramGb:
          clearAvailableVramGb ? null : (availableVramGb ?? this.availableVramGb),
    );
  }
}
