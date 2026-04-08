import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/app_providers.dart';
import '../../data/models/mcp_integration.dart';

class ChatMcpConfigNotifier extends Notifier<ChatMcpConfig> {
  @override
  ChatMcpConfig build() {
    final settings = ref.watch(settingsProvider);
    return ChatMcpConfig(enabled: settings.mcpEnabled);
  }

  void setConfig(ChatMcpConfig config) {
    state = config;
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
    state = ChatMcpConfig(enabled: settings.mcpEnabled);
  }
}

final chatMcpConfigProvider =
    NotifierProvider<ChatMcpConfigNotifier, ChatMcpConfig>(() {
      return ChatMcpConfigNotifier();
    });

class McpConfigSheet extends ConsumerStatefulWidget {
  const McpConfigSheet({super.key});

  @override
  ConsumerState<McpConfigSheet> createState() => _McpConfigSheetState();
}

class _McpConfigSheetState extends ConsumerState<McpConfigSheet> {
  final _serverLabelController = TextEditingController();
  final _serverUrlController = TextEditingController();

  @override
  void dispose() {
    _serverLabelController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(chatMcpConfigProvider);
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isGloballyEnabled = settings.mcpEnabled;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF3A3A3A)
                    : const Color(0xFFE5E5E5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                Icons.extension,
                color: isGloballyEnabled
                    ? theme.colorScheme.primary
                    : (isDark
                          ? const Color(0xFF666666)
                          : const Color(0xFF999999)),
              ),
              const SizedBox(width: 8),
              Text(
                'MCP Servers',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
          if (!isGloballyEnabled) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.orange.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'MCP is disabled. Enable it in Settings to use MCP servers.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.orange[200] : Colors.orange[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SwitchListTile(
            title: Text(
              'Enable MCP for this chat',
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
            ),
            subtitle: Text(
              isGloballyEnabled
                  ? 'Toggle MCP functionality for this session'
                  : 'MCP is disabled globally in Settings',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? const Color(0xFF9CA3AF)
                    : const Color(0xFF6B7280),
              ),
            ),
            value: config.enabled,
            onChanged: isGloballyEnabled
                ? (value) {
                    ref.read(chatMcpConfigProvider.notifier).toggleEnabled();
                  }
                : null,
          ),
          if (config.enabled && isGloballyEnabled) ...[
            const Divider(),
            SwitchListTile(
              title: Text(
                'Auto-execute tools',
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
              subtitle: Text(
                'Automatically run MCP tools without asking',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF6B7280),
                ),
              ),
              value: config.autoExecuteTools,
              onChanged: (value) {
                ref.read(chatMcpConfigProvider.notifier).toggleAutoExecute();
              },
            ),
            const Divider(),
            Text(
              'Add Ephemeral MCP Server',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _serverLabelController,
              decoration: InputDecoration(
                labelText: 'Server Label',
                hintText: 'e.g., huggingface',
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF2A2A2A)
                    : const Color(0xFFF5F5F5),
              ),
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _serverUrlController,
              decoration: InputDecoration(
                labelText: 'Server URL',
                hintText: 'e.g., https://huggingface.co/mcp',
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF2A2A2A)
                    : const Color(0xFFF5F5F5),
              ),
              keyboardType: TextInputType.url,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _addServer,
                icon: const Icon(Icons.add),
                label: const Text('Add Server'),
              ),
            ),
            if (config.integrations.isNotEmpty) ...[
              const Divider(),
              Text(
                'Active Integrations',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: config.integrations.length,
                  itemBuilder: (context, index) {
                    final integration = config.integrations[index];
                    return ListTile(
                      leading: Icon(
                        Icons.extension,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        integration.serverLabel ?? integration.pluginId ?? '',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      subtitle: Text(
                        integration.serverUrl ?? integration.pluginId ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF6B7280),
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          ref
                              .read(chatMcpConfigProvider.notifier)
                              .removeIntegration(index);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _addServer() {
    final label = _serverLabelController.text.trim();
    final url = _serverUrlController.text.trim();
    if (label.isEmpty || url.isEmpty) return;

    final integration = McpIntegration(
      type: McpIntegrationType.ephemeralMcp,
      serverLabel: label,
      serverUrl: url,
    );

    ref.read(chatMcpConfigProvider.notifier).addIntegration(integration);

    _serverLabelController.clear();
    _serverUrlController.clear();
  }
}

void showMcpConfigSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const McpConfigSheet(),
  );
}
