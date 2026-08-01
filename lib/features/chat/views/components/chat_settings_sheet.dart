import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:localmind/core/theme/colors.dart';
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
  late String _currentTab;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
  }

  @override
  void dispose() {
    _serverLabelController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);
    final activeConv = ref.watch(conv.activeConversationProvider);
    final mcpConfig = ref.watch(chatMcpConfigProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Parameters
    final temperature = activeConv?.temperature ?? settings.temperature;
    final topP = activeConv?.topP ?? settings.topP;
    final maxTokens = activeConv?.maxTokens ?? settings.maxTokens;

    final hasOverrides =
        activeConv?.temperature != null ||
        activeConv?.topP != null ||
        activeConv?.maxTokens != null;

    final isGloballyEnabled = settings.mcpEnabled;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : AppColors.lightSurface,
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
                      ? AppColors.darkSurfaceCard
                      : AppColors.lightBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  l10n.chat_settings_title,
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
                    leading: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 16),
                    child: Text(l10n.reset_defaults),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            ShadTabs<String>(
              value: _currentTab,
              onChanged: (v) => setState(() => _currentTab = v),
              tabs: [
                ShadTab(
                  value: 'parameters',
                  content: _buildParametersTab(
                    context,
                    l10n,
                    temperature,
                    topP,
                    maxTokens,
                    activeConv?.id,
                    isDark,
                  ),
                  child: Row(
                    children: [
                      const HugeIcon(
                        icon: HugeIcons.strokeRoundedSlidersHorizontal,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(l10n.parameters_tab),
                    ],
                  ),
                ),
                ShadTab(
                  value: 'mcp',
                  content: _buildMcpTab(
                    context,
                    l10n,
                    mcpConfig,
                    isGloballyEnabled,
                    isDark,
                  ),
                  child: Row(
                    children: [
                      const HugeIcon(
                        icon: HugeIcons.strokeRoundedPuzzle,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(l10n.mcp_tab),
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
    AppLocalizations l10n,
    double temperature,
    double topP,
    int maxTokens,
    String? conversationId,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          _ParamSlider(
            label: l10n.temperature,
            value: temperature,
            min: 0,
            max: 2,
            divisions: 20,
            description: l10n.temperature_desc,
            onChanged: (v) => _updateParam(ref, conversationId, temperature: v),
            isDark: isDark,
          ),
          const SizedBox(height: 24),
          _ParamSlider(
            label: l10n.top_p,
            value: topP,
            min: 0,
            max: 1,
            divisions: 10,
            description: l10n.top_p_desc,
            onChanged: (v) => _updateParam(ref, conversationId, topP: v),
            isDark: isDark,
          ),
          const SizedBox(height: 24),
          _ParamInput(
            label: l10n.max_tokens,
            value: maxTokens,
            description: l10n.max_tokens_desc,
            onChanged: (v) => _updateParam(ref, conversationId, maxTokens: v),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildMcpTab(
    BuildContext context,
    AppLocalizations l10n,
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
                  const HugeIcon(icon: 
                    HugeIcons.strokeRoundedAlertCircle,
                    color: Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.mcp_disabled_warning,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ShadSwitch(
            value: mcpConfig.enabled,
            onChanged: isGloballyEnabled
                ? (v) {
                    final convId = ref
                        .read(conv.activeConversationProvider)
                        ?.id;
                    if (convId != null) {
                      ref
                          .read(chatMcpConfigProvider.notifier)
                          .updateEnabled(ref, convId, v);
                    } else {
                      ref.read(chatMcpConfigProvider.notifier).setEnabled(v);
                    }
                  }
                : null,
            label: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l10n.mcp_enable_chat),
                _McpBadge(label: l10n.experimental_label, isDark: isDark),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (mcpConfig.enabled && isGloballyEnabled) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    l10n.add_ephemeral_mcp,
                    style: theme.textTheme.list,
                  ),
                ),
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: () => _showImportJsonDialog(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const HugeIcon(
                        icon: HugeIcons.strokeRoundedFileImport,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(l10n.import_mcp_json),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ShadInput(
                    controller: _serverLabelController,
                    placeholder: Text(l10n.mcp_label_placeholder),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ShadInput(
                    controller: _serverUrlController,
                    placeholder: Text(l10n.mcp_url_placeholder),
                    keyboardType: TextInputType.url,
                  ),
                ),
                const SizedBox(width: 8),
                ShadIconButton(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01),
                  onPressed: _addServer,
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (mcpConfig.integrations.isNotEmpty) ...[
              Text(l10n.active_integrations, style: theme.textTheme.list),
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
                        color: isDark
                            ? AppColors.darkBackground
                            : AppColors.lightSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkSurfaceCard
                              : AppColors.lightBorder,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: HugeIcon(
                          icon: HugeIcons.strokeRoundedPuzzle,
                          size: 18,
                          color: integration.enabled
                              ? null
                              : Colors.grey,
                        ),
                        title: Text(
                          integration.serverLabel ?? integration.pluginId ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration: integration.enabled
                                ? TextDecoration.none
                                : TextDecoration.lineThrough,
                            color: integration.enabled
                                ? null
                                : (isDark
                                    ? AppColors.darkMutedText
                                    : AppColors.lightMutedText),
                          ),
                        ),
                        subtitle: Text(
                          integration.type == McpIntegrationType.plugin
                              ? 'Plugin (${integration.pluginId})'
                              : (integration.serverUrl ?? ''),
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ShadSwitch(
                              value: integration.enabled,
                              onChanged: (v) => ref
                                  .read(chatMcpConfigProvider.notifier)
                                  .toggleIntegration(index, v),
                            ),
                            const SizedBox(width: 4),
                            ShadIconButton.ghost(
                              icon: const HugeIcon(
                                icon: HugeIcons.strokeRoundedDelete01,
                                size: 18,
                                color: Colors.red,
                              ),
                              onPressed: () => ref
                                  .read(chatMcpConfigProvider.notifier)
                                  .removeIntegration(index),
                            ),
                          ],
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

  void _showImportJsonDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final jsonController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const HugeIcon(
                icon: HugeIcons.strokeRoundedFileImport,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.import_mcp_json_dialog_title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkBackground
                        : AppColors.lightSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkSurfaceCard
                          : AppColors.lightBorder,
                    ),
                  ),
                  child: Text(
                    l10n.import_mcp_json_instructions,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.darkMutedText
                          : AppColors.lightMutedText,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ShadInput(
                  controller: jsonController,
                  maxLines: 8,
                  placeholder: Text(
                    l10n.import_mcp_json_placeholder,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ShadButton.ghost(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            ShadButton(
              onPressed: () {
                final jsonStr = jsonController.text.trim();
                if (jsonStr.isNotEmpty) {
                  final importedCount = ref
                      .read(chatMcpConfigProvider.notifier)
                      .importIntegrationsFromJson(jsonStr);
                  Navigator.of(dialogContext).pop();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        importedCount > 0
                            ? l10n.mcp_import_success(importedCount)
                            : l10n.mcp_import_failed,
                      ),
                      backgroundColor:
                          importedCount > 0 ? Colors.green : Colors.red,
                    ),
                  );
                }
              },
              child: Text(l10n.import_mcp_json),
            ),
          ],
        );
      },
    );
  }

  void _addServer() {
    final label = _serverLabelController.text.trim();
    final url = _serverUrlController.text.trim();
    if (label.isEmpty && url.isEmpty) return;

    final McpIntegration integration;
    if (label.contains('/') || url.contains('/')) {
      final raw = label.isNotEmpty ? label : url;
      final pluginId = raw.contains('/') ? raw : 'mcp/$raw';
      integration = McpIntegration(
        type: McpIntegrationType.plugin,
        pluginId: pluginId,
        serverLabel: label.isNotEmpty ? label : null,
      );
    } else {
      if (label.isEmpty || url.isEmpty) return;
      integration = McpIntegration(
        type: McpIntegrationType.ephemeralMcp,
        serverLabel: label,
        serverUrl: url,
      );
    }

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

    ref
        .read(conv.conversationsProvider.notifier)
        .updateChatParams(
          conversationId,
          temperature: temperature,
          topP: topP,
          maxTokens: maxTokens,
          contextLength: contextLength,
        );
  }

  void _resetToDefaults(WidgetRef ref, String? conversationId) {
    if (conversationId == null) return;
    ref
        .read(conv.conversationsProvider.notifier)
        .updateChatParams(
          conversationId,
          clearTemperature: true,
          clearTopP: true,
          clearMaxTokens: true,
        );
  }
}

class _McpBadge extends StatelessWidget {
  const _McpBadge({required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: isDark ? 0.18 : 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFFB45309),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
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

void showChatSettingsSheet(
  BuildContext context, {
  String initialTab = 'parameters',
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ChatSettingsSheet(initialTab: initialTab),
  );
}
