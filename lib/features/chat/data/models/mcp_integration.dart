enum McpIntegrationType { ephemeralMcp, plugin }

class McpIntegration {
  final McpIntegrationType type;
  final String? serverLabel;
  final String? serverUrl;
  final String? pluginId;
  final List<String>? allowedTools;
  final Map<String, String>? headers;
  final bool enabled;

  const McpIntegration({
    required this.type,
    this.serverLabel,
    this.serverUrl,
    this.pluginId,
    this.allowedTools,
    this.headers,
    this.enabled = true,
  });

  /// Returns the clean API payload expected by LM Studio native endpoint.
  Map<String, dynamic> toApiJson() {
    if (type == McpIntegrationType.plugin) {
      return {
        'type': 'plugin',
        'id': pluginId,
        if (allowedTools != null) 'allowed_tools': allowedTools,
      };
    }
    return {
      'type': 'ephemeral_mcp',
      'server_label': serverLabel,
      'server_url': serverUrl,
      if (allowedTools != null) 'allowed_tools': allowedTools,
      if (headers != null) 'headers': headers,
    };
  }

  Map<String, dynamic> toJson() {
    final map = toApiJson();
    map['enabled'] = enabled;
    return map;
  }

  factory McpIntegration.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = typeStr == 'plugin'
        ? McpIntegrationType.plugin
        : McpIntegrationType.ephemeralMcp;

    return McpIntegration(
      type: type,
      serverLabel: json['server_label'] as String?,
      serverUrl: json['server_url'] as String?,
      pluginId: json['id'] as String?,
      allowedTools: (json['allowed_tools'] as List?)?.cast<String>(),
      headers: (json['headers'] as Map?)?.cast<String, String>(),
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  McpIntegration copyWith({
    McpIntegrationType? type,
    String? serverLabel,
    String? serverUrl,
    String? pluginId,
    List<String>? allowedTools,
    Map<String, String>? headers,
    bool? enabled,
  }) {
    return McpIntegration(
      type: type ?? this.type,
      serverLabel: serverLabel ?? this.serverLabel,
      serverUrl: serverUrl ?? this.serverUrl,
      pluginId: pluginId ?? this.pluginId,
      allowedTools: allowedTools ?? this.allowedTools,
      headers: headers ?? this.headers,
      enabled: enabled ?? this.enabled,
    );
  }
}

class ChatMcpConfig {
  final List<McpIntegration> integrations;
  final Map<String, String> activeMcpServers;
  final bool enabled;

  const ChatMcpConfig({
    this.integrations = const [],
    this.activeMcpServers = const {},
    this.enabled = true,
  });

  ChatMcpConfig copyWith({
    List<McpIntegration>? integrations,
    Map<String, String>? activeMcpServers,
    bool? enabled,
  }) {
    return ChatMcpConfig(
      integrations: integrations ?? this.integrations,
      activeMcpServers: activeMcpServers ?? this.activeMcpServers,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'integrations': integrations.map((i) => i.toJson()).toList(),
      'activeMcpServers': activeMcpServers,
    };
  }

  factory ChatMcpConfig.fromJson(Map<String, dynamic> json) {
    return ChatMcpConfig(
      integrations:
          (json['integrations'] as List?)
              ?.map((i) => McpIntegration.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      activeMcpServers:
          (json['activeMcpServers'] as Map?)?.cast<String, String>() ?? {},
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}
