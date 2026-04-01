enum McpIntegrationType { ephemeralMcp, plugin }

class McpIntegration {
  final McpIntegrationType type;
  final String? serverLabel;
  final String? serverUrl;
  final String? pluginId;
  final List<String>? allowedTools;
  final Map<String, String>? headers;

  const McpIntegration({
    required this.type,
    this.serverLabel,
    this.serverUrl,
    this.pluginId,
    this.allowedTools,
    this.headers,
  });

  Map<String, dynamic> toJson() {
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
    );
  }

  McpIntegration copyWith({
    McpIntegrationType? type,
    String? serverLabel,
    String? serverUrl,
    String? pluginId,
    List<String>? allowedTools,
    Map<String, String>? headers,
  }) {
    return McpIntegration(
      type: type ?? this.type,
      serverLabel: serverLabel ?? this.serverLabel,
      serverUrl: serverUrl ?? this.serverUrl,
      pluginId: pluginId ?? this.pluginId,
      allowedTools: allowedTools ?? this.allowedTools,
      headers: headers ?? this.headers,
    );
  }
}

class ChatMcpConfig {
  final List<McpIntegration> integrations;
  final bool autoExecuteTools;
  final Map<String, String> activeMcpServers;
  final bool enabled;

  const ChatMcpConfig({
    this.integrations = const [],
    this.autoExecuteTools = true,
    this.activeMcpServers = const {},
    this.enabled = true,
  });

  ChatMcpConfig copyWith({
    List<McpIntegration>? integrations,
    bool? autoExecuteTools,
    Map<String, String>? activeMcpServers,
    bool? enabled,
  }) {
    return ChatMcpConfig(
      integrations: integrations ?? this.integrations,
      autoExecuteTools: autoExecuteTools ?? this.autoExecuteTools,
      activeMcpServers: activeMcpServers ?? this.activeMcpServers,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'integrations': integrations.map((i) => i.toJson()).toList(),
      'autoExecuteTools': autoExecuteTools,
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
      autoExecuteTools: json['autoExecuteTools'] as bool? ?? true,
      activeMcpServers:
          (json['activeMcpServers'] as Map?)?.cast<String, String>() ?? {},
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}
