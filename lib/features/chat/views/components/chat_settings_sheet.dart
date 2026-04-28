import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../conversations/providers/conversation_providers.dart' as conv;
import '../../providers/chat_mcp_providers.dart';

class ChatSettingsSheet extends ConsumerStatefulWidget {
  const ChatSettingsSheet({super.key, this.initialTab = 'parameters'});

  final String initialTab;

  @override
  ConsumerState<ChatSettingsSheet> createState() => _ChatSettingsSheetState();
}

class _ChatSettingsSheetState extends ConsumerState<ChatSettingsSheet> {
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
    final settings = ref.watch(settingsProvider);
    final activeConv = ref.watch(conv.activeConversationProvider);
    final mcpConfig = ref.watch(chatMcpConfigProvider);
    // final theme = ShadTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Parameters
    final temperature = activeConv?.temperature ?? settings.temperature;
    final topP = activeConv?.topP ?? settings.topP;
    final maxTokens = activeConv?.maxTokens ?? settings.maxTokens;
    final contextLength = activeConv?.contextLength ?? settings.contextLength;

    final hasOverrides = activeConv?.temperature != null ||
        activeConv?.topP != null ||
        activeConv?.maxTokens != null ||
        activeConv?.contextLength != null;

    final isGloballyEnabled = settings.mcpEnabled;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2A2A2A)
                      : const Color(0xFFE5E5E5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Chat Settings',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const Spacer(),
                if (hasOverrides)
                  ShadButton.ghost(
                    onPressed: () => _resetToDefaults(ref, activeConv?.id),
                    leading: const Icon(Icons.restore, size: 16),
                    child: const Text('Reset Defaults'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            ShadTabs<String>(
              value: widget.initialTab,
              tabs: [
                ShadTab(
                  value: 'parameters',
                  content: _buildParametersTab(
                    context,
                    temperature,
                    topP,
                    maxTokens,
                    contextLength,
                    activeConv?.id,
                    isDark,
                  ),
                  child: const Row(
                    children: [
                      HugeIcon(icon: HugeIcons.strokeRoundedSlidersHorizontal, size: 16),
                      SizedBox(width: 8),
                      Text('Parameters'),
                    ],
                  ),
                ),
                ShadTab(
                  value: 'mcp',
                  content: _buildMcpTab(
                    context,
                    mcpConfig,
                    isGloballyEnabled,
                    isDark,
                  ),
                  child: const Row(
                    children: [
                      HugeIcon(icon: HugeIcons.strokeRoundedPuzzle, size: 16),
                      SizedBox(width: 8),
                      Text('MCP'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParametersTab(
    BuildContext context,
    double temperature,
    double topP,
    int maxTokens,
    int contextLength,
    String? conversationId,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          _ParamSlider(
            label: 'Temperature',
            value: temperature,
            min: 0,
            max: 2,
            divisions: 20,
            description: 'Controls randomness: Higher = Creative, Lower = Focused',
            onChanged: (v) => _updateParam(ref, conversationId, temperature: v),
            isDark: isDark,
          ),
          const SizedBox(height: 24),
          _ParamSlider(
            label: 'Top P',
            value: topP,
            min: 0,
            max: 1,
            divisions: 10,
            description: 'Nucleus sampling threshold',
            onChanged: (v) => _updateParam(ref, conversationId, topP: v),
            isDark: isDark,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _ParamInput(
                  label: 'Max Tokens',
                  value: maxTokens,
                  description: 'Response limit',
                  onChanged: (v) => _updateParam(ref, conversationId, maxTokens: v),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ParamInput(
                  label: 'Context Length',
                  value: contextLength,
                  description: 'History window',
                  onChanged: (v) => _updateParam(ref, conversationId, contextLength: v),
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMcpTab(
    BuildContext context,
    ChatMcpConfig mcpConfig,
    bool isGloballyEnabled,
    bool isDark,
  ) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isGloballyEnabled)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'MCP is disabled globally. Enable it in Settings to use these features.',
                      style: TextStyle(fontSize: 13, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ShadSwitch(
            value: mcpConfig.enabled,
            onChanged: isGloballyEnabled
                ? (v) => ref.read(chatMcpConfigProvider.notifier).toggleEnabled()
                : null,
            label: const Text('Enable MCP for this chat'),
          ),
          const SizedBox(height: 16),
          if (mcpConfig.enabled && isGloballyEnabled) ...[
            ShadSwitch(
              value: mcpConfig.autoExecuteTools,
              onChanged: (v) =>
                  ref.read(chatMcpConfigProvider.notifier).toggleAutoExecute(),
              label: const Text('Auto-execute tools'),
            ),
            const SizedBox(height: 24),
            Text(
              'Add Ephemeral MCP Server',
              style: theme.textTheme.list,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ShadInput(
                    controller: _serverLabelController,
                    placeholder: const Text('Label'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ShadInput(
                    controller: _serverUrlController,
                    placeholder: const Text('URL (https://...)'),
                    keyboardType: TextInputType.url,
                  ),
                ),
                const SizedBox(width: 8),
                ShadIconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addServer,
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (mcpConfig.integrations.isNotEmpty) ...[
              Text(
                'Active Integrations',
                style: theme.textTheme.list,
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: mcpConfig.integrations.length,
                  itemBuilder: (context, index) {
                    final integration = mcpConfig.integrations[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: const HugeIcon(icon: HugeIcons.strokeRoundedPuzzle, size: 18),
                        title: Text(
                          integration.serverLabel ?? integration.pluginId ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          integration.serverUrl ?? '',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: ShadIconButton.ghost(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          onPressed: () => ref
                              .read(chatMcpConfigProvider.notifier)
                              .removeIntegration(index),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
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
    FocusScope.of(context).unfocus();
  }

  void _updateParam(
    WidgetRef ref,
    String? conversationId, {
    double? temperature,
    double? topP,
    int? maxTokens,
    int? contextLength,
  }) {
    if (conversationId == null) {
      final notifier = ref.read(settingsProvider.notifier);
      if (temperature != null) notifier.setTemperature(temperature);
      if (topP != null) notifier.setTopP(topP);
      if (maxTokens != null) notifier.setMaxTokens(maxTokens);
      if (contextLength != null) notifier.setContextLength(contextLength);
      return;
    }

    ref.read(conv.conversationsProvider.notifier).updateChatParams(
      conversationId,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      contextLength: contextLength,
    );
  }

  void _resetToDefaults(WidgetRef ref, String? conversationId) {
    if (conversationId == null) return;
    ref.read(conv.conversationsProvider.notifier).updateChatParams(
      conversationId,
      clearTemperature: true,
      clearTopP: true,
      clearMaxTokens: true,
      clearContextLength: true,
    );
  }
}

class _ParamSlider extends StatelessWidget {
  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.description,
    required this.onChanged,
    required this.isDark,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String description;
  final ValueChanged<double> onChanged;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ShadSlider(
          initialValue: value,
          min: min,
          max: max,
          onChanged: onChanged,
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
      ],
    );
  }
}

class _ParamInput extends StatelessWidget {
  const _ParamInput({
    required this.label,
    required this.value,
    required this.description,
    required this.onChanged,
    required this.isDark,
  });

  final String label;
  final int value;
  final String description;
  final ValueChanged<int> onChanged;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 8),
        ShadInput(
          initialValue: value.toString(),
          keyboardType: TextInputType.number,
          onChanged: (v) {
            final val = int.tryParse(v);
            if (val != null) onChanged(val);
          },
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
      ],
    );
  }
}

void showChatSettingsSheet(BuildContext context, {String initialTab = 'parameters'}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ChatSettingsSheet(initialTab: initialTab),
  );
}
