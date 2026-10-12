import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../data/models/mcp_integration.dart';
import '../../conversations/providers/conversation_providers.dart';
import 'tooling_providers.dart';

export '../data/models/mcp_integration.dart';

class ChatMcpConfigNotifier extends Notifier<ChatMcpConfig> {
  final Map<String, Future<void>> _connections = {};

  @override
  ChatMcpConfig build() {
    final savedIntegrations = ref.read(settingsProvider).savedMcpIntegrations;
    // The server manager only holds live connections, so saved servers have
    // to be reconnected on every launch or their tools never reach the model.
    for (final integration in savedIntegrations) {
      if (integration.enabled) _connect(integration);
    }
    return ChatMcpConfig(enabled: false, integrations: savedIntegrations);
  }

  /// Completes once every server connection started so far has settled,
  /// whether it succeeded or failed.
  Future<void> get connectionsReady => Future.wait(_connections.values);

  void _connect(McpIntegration integration) {
    final label = integration.serverLabel;
    final url = integration.serverUrl;
    if (label == null || url == null) return;

    late final Future<void> connection;
    connection = ref
        .read(mcpServerManagerProvider)
        .addServer(label, url, headers: integration.headers)
        .then<Object?>((_) => null, onError: (Object error) => error)
        .then((error) {
          if (!ref.mounted) return;
          if (!identical(_connections[label], connection)) {
            // Disconnected while connecting: drop the late connection. A
            // newer connection for the same label owns the server instead.
            if (error == null && !_connections.containsKey(label)) {
              unawaited(ref.read(mcpServerManagerProvider).removeServer(label));
            }
            return;
          }
          _setConnectionError(label, error?.toString());
          ref.invalidate(availableToolsProvider);
        });
    _connections[label] = connection;
  }

  void _disconnect(McpIntegration integration) {
    final label = integration.serverLabel;
    if (label == null) return;
    _connections.remove(label);
    _setConnectionError(label, null);
    ref.read(mcpServerManagerProvider).removeServer(label).whenComplete(() {
      if (ref.mounted) ref.invalidate(availableToolsProvider);
    });
  }

  void _setConnectionError(String label, String? error) {
    if (state.connectionErrors[label] == error) return;
    final errors = Map<String, String>.from(state.connectionErrors);
    if (error == null) {
      errors.remove(label);
    } else {
      errors[label] = error;
    }
    state = state.copyWith(connectionErrors: errors);
  }

  void setEnabled(bool enabled) {
    state = state.copyWith(enabled: enabled);
  }

  void updateEnabled(WidgetRef ref, String conversationId, bool enabled) {
    state = state.copyWith(enabled: enabled);
    ref
        .read(conversationsProvider.notifier)
        .updateMcpEnabled(conversationId, enabled);
  }

  void addIntegration(McpIntegration integration) {
    state = state.copyWith(
      integrations: [...state.integrations, integration],
      activeMcpServers:
          integration.serverLabel != null && integration.serverUrl != null
          ? {
              ...state.activeMcpServers,
              integration.serverLabel!: integration.serverUrl!,
            }
          : state.activeMcpServers,
    );
    if (integration.enabled) _connect(integration);
    ref.read(settingsProvider.notifier).addSavedMcpIntegration(integration);
  }

  bool addIntegrationFromInput({required String label, required String url}) {
    final trimmedLabel = label.trim();
    final trimmedUrl = url.trim();
    final uri = Uri.tryParse(trimmedUrl);
    final isRemoteMcpUrl =
        uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https');

    if (isRemoteMcpUrl) {
      if (trimmedLabel.isEmpty) return false;
      addIntegration(
        McpIntegration(
          type: McpIntegrationType.ephemeralMcp,
          serverLabel: trimmedLabel,
          serverUrl: trimmedUrl,
        ),
      );
      return true;
    }

    final pluginId = trimmedLabel.isNotEmpty ? trimmedLabel : trimmedUrl;
    final hasBothInputs = trimmedLabel.isNotEmpty && trimmedUrl.isNotEmpty;
    if (hasBothInputs || !pluginId.contains('/')) {
      return false;
    }

    addIntegration(
      McpIntegration(
        type: McpIntegrationType.plugin,
        pluginId: pluginId,
        serverLabel: trimmedLabel.isNotEmpty ? trimmedLabel : null,
      ),
    );
    return true;
  }

  void removeIntegration(int index) {
    final integration = state.integrations[index];
    final newIntegrations = List<McpIntegration>.from(state.integrations)
      ..removeAt(index);
    final newServers = Map<String, String>.from(state.activeMcpServers);
    if (integration.serverLabel != null) {
      newServers.remove(integration.serverLabel);
    }
    state = state.copyWith(
      integrations: newIntegrations,
      activeMcpServers: newServers,
    );
    _disconnect(integration);
    final saved = ref.read(settingsProvider).savedMcpIntegrations;
    final savedIdx = saved.indexWhere(
      (i) =>
          (integration.pluginId != null &&
              i.pluginId == integration.pluginId) ||
          (integration.serverUrl != null &&
              i.serverUrl == integration.serverUrl),
    );
    if (savedIdx != -1) {
      ref.read(settingsProvider.notifier).removeSavedMcpIntegration(savedIdx);
    }
  }

  void toggleIntegration(int index, bool enabled) {
    if (index < 0 || index >= state.integrations.length) return;
    final integration = state.integrations[index];
    final newIntegrations = List<McpIntegration>.from(state.integrations);
    newIntegrations[index] = newIntegrations[index].copyWith(enabled: enabled);
    state = state.copyWith(integrations: newIntegrations);
    if (enabled) {
      _connect(integration);
    } else {
      _disconnect(integration);
    }

    final saved = ref.read(settingsProvider).savedMcpIntegrations;
    final savedIdx = saved.indexWhere(
      (i) =>
          (integration.pluginId != null &&
              i.pluginId == integration.pluginId) ||
          (integration.serverUrl != null &&
              i.serverUrl == integration.serverUrl),
    );
    if (savedIdx != -1) {
      ref
          .read(settingsProvider.notifier)
          .toggleSavedMcpIntegration(savedIdx, enabled);
    }
  }

  int importIntegrationsFromJson(String jsonString) {
    dynamic decoded;
    try {
      decoded = jsonDecode(jsonString);
    } catch (_) {
      return 0;
    }

    final newIntegrations = <McpIntegration>[];

    String normalizePluginId(String rawId) {
      final trimmed = rawId.trim();
      if (trimmed.contains('/')) return trimmed;
      return 'mcp/$trimmed';
    }

    void processMcpServers(Map<String, dynamic> servers) {
      servers.forEach((key, value) {
        if (value is Map) {
          final url = value['url'] as String? ?? value['server_url'] as String?;
          if (url != null && url.isNotEmpty) {
            newIntegrations.add(
              McpIntegration(
                type: McpIntegrationType.ephemeralMcp,
                serverLabel: key,
                serverUrl: url,
                enabled: true,
              ),
            );
          } else {
            final pluginId = normalizePluginId(key);
            newIntegrations.add(
              McpIntegration(
                type: McpIntegrationType.plugin,
                pluginId: pluginId,
                serverLabel: key,
                enabled: true,
              ),
            );
          }
        }
      });
    }

    if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('mcpServers') && decoded['mcpServers'] is Map) {
        processMcpServers(decoded['mcpServers'] as Map<String, dynamic>);
      } else if (decoded.containsKey('integrations') &&
          decoded['integrations'] is List) {
        final list = decoded['integrations'] as List;
        for (final item in list) {
          if (item is String) {
            final pluginId = normalizePluginId(item);
            newIntegrations.add(
              McpIntegration(
                type: McpIntegrationType.plugin,
                pluginId: pluginId,
                enabled: true,
              ),
            );
          } else if (item is Map<String, dynamic>) {
            newIntegrations.add(McpIntegration.fromJson(item));
          }
        }
      } else {
        processMcpServers(decoded);
      }
    } else if (decoded is List) {
      for (final item in decoded) {
        if (item is String) {
          final pluginId = normalizePluginId(item);
          newIntegrations.add(
            McpIntegration(
              type: McpIntegrationType.plugin,
              pluginId: pluginId,
              enabled: true,
            ),
          );
        } else if (item is Map<String, dynamic>) {
          newIntegrations.add(McpIntegration.fromJson(item));
        }
      }
    }

    if (newIntegrations.isEmpty) return 0;

    int addedCount = 0;
    for (final integration in newIntegrations) {
      final exists = state.integrations.any((existing) {
        if (integration.type == McpIntegrationType.plugin) {
          return existing.pluginId == integration.pluginId;
        }
        return existing.serverUrl == integration.serverUrl &&
            existing.serverLabel == integration.serverLabel;
      });

      if (!exists) {
        addIntegration(integration);
        addedCount++;
      }
    }

    return addedCount;
  }

  void toggleEnabled() {
    state = state.copyWith(enabled: !state.enabled);
  }

  void clearAll() {
    final settings = ref.read(settingsProvider);
    state = ChatMcpConfig(
      enabled: settings.mcpEnabled && settings.newChatMcpEnabled,
      integrations: settings.savedMcpIntegrations,
    );
    _connections.clear();
    ref.read(mcpServerManagerProvider).clear();
  }
}

final chatMcpConfigProvider =
    NotifierProvider<ChatMcpConfigNotifier, ChatMcpConfig>(() {
      return ChatMcpConfigNotifier();
    });
