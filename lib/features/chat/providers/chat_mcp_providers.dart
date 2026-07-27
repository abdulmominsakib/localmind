import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../data/models/mcp_integration.dart';
import '../../conversations/providers/conversation_providers.dart';
import 'tooling_providers.dart';

export '../data/models/mcp_integration.dart';

class ChatMcpConfigNotifier extends Notifier<ChatMcpConfig> {
  @override
  ChatMcpConfig build() {
    // We no longer watch settingsProvider here to avoid resetting per-chat state
    // when global settings change. Initial state is set via ChatNotifier.
    // Default to disabled so a fresh app launch does not silently enable MCP.
    return const ChatMcpConfig(enabled: false);
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
  }


  void toggleEnabled() {
    state = state.copyWith(enabled: !state.enabled);
  }

  void clearAll() {
    final settings = ref.read(settingsProvider);
    state = ChatMcpConfig(
      enabled: settings.mcpEnabled && settings.newChatMcpEnabled,
    );
    ref.read(mcpServerManagerProvider).clear();
  }
}

final chatMcpConfigProvider =
    NotifierProvider<ChatMcpConfigNotifier, ChatMcpConfig>(() {
      return ChatMcpConfigNotifier();
    });
