import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../data/models/mcp_integration.dart';
import '../../conversations/providers/conversation_providers.dart';

export '../data/models/mcp_integration.dart';

class ChatMcpConfigNotifier extends Notifier<ChatMcpConfig> {
  @override
  ChatMcpConfig build() {
    // We no longer watch settingsProvider here to avoid resetting per-chat state
    // when global settings change. Initial state is set via ChatNotifier.
    return const ChatMcpConfig(enabled: true);
  }

  void setConfig(ChatMcpConfig config) {
    state = config;
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
  }

  void toggleAutoExecute() {
    state = state.copyWith(autoExecuteTools: !state.autoExecuteTools);
  }

  void toggleEnabled() {
    state = state.copyWith(enabled: !state.enabled);
  }

  void clearAll() {
    final settings = ref.read(settingsProvider);
    state = ChatMcpConfig(enabled: settings.newChatMcpEnabled);
  }
}

final chatMcpConfigProvider =
    NotifierProvider<ChatMcpConfigNotifier, ChatMcpConfig>(() {
      return ChatMcpConfigNotifier();
    });
