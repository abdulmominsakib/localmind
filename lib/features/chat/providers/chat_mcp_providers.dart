import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../data/models/mcp_integration.dart';
import '../../conversations/providers/conversation_providers.dart';
import 'tooling_providers.dart';

export '../data/models/mcp_integration.dart';

class ChatMcpConfigNotifier extends Notifier<ChatMcpConfig> {
  @override
  ChatMcpConfig build() {
    final savedIntegrations = ref.read(settingsProvider).savedMcpIntegrations;
    return ChatMcpConfig(
      enabled: false,
      integrations: savedIntegrations,
    );
  }

  void setConfig(ChatMcpConfig config) {
    state = config;
    final manager = ref.read(mcpServerManagerProvider);
    manager.clear();
    for (final integration in config.integrations) {
      if (integration.serverLabel != null && integration.serverUrl != null) {
        manager.addServer(
          integration.serverLabel!,
          integration.serverUrl!,
          headers: integration.headers,
        ).catchError((_) {});
      }
    }
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
    if (integration.serverLabel != null && integration.serverUrl != null) {
      ref.read(mcpServerManagerProvider).addServer(
        integration.serverLabel!,
        integration.serverUrl!,
        headers: integration.headers,
      ).catchError((_) {});
    }
    ref.read(settingsProvider.notifier).addSavedMcpIntegration(integration);
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
    if (integration.serverLabel != null) {
      ref.read(mcpServerManagerProvider).removeServer(integration.serverLabel!);
    }
    final saved = ref.read(settingsProvider).savedMcpIntegrations;
    final savedIdx = saved.indexWhere((i) =>
        (integration.pluginId != null && i.pluginId == integration.pluginId) ||
        (integration.serverUrl != null && i.serverUrl == integration.serverUrl));
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

    final saved = ref.read(settingsProvider).savedMcpIntegrations;
    final savedIdx = saved.indexWhere((i) =>
        (integration.pluginId != null && i.pluginId == integration.pluginId) ||
        (integration.serverUrl != null && i.serverUrl == integration.serverUrl));
    if (savedIdx != -1) {
      ref.read(settingsProvider.notifier).toggleSavedMcpIntegration(savedIdx, enabled);
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
      } else if (decoded.containsKey('integrations') && decoded['integrations'] is List) {
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
    ref.read(mcpServerManagerProvider).clear();
  }
}

final chatMcpConfigProvider =
    NotifierProvider<ChatMcpConfigNotifier, ChatMcpConfig>(() {
      return ChatMcpConfigNotifier();
    });
