import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../chat/data/mcp_server_manager.dart';
import '../../chat/data/tools/calendar_service.dart';
import '../../chat/data/tools/tool_definition.dart';
import '../../chat/providers/chat_mcp_providers.dart';
import '../../chat/providers/tooling_providers.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/colors.dart';
import '../../../core/utils/system_insets.dart';

class McpToolsScreen extends ConsumerStatefulWidget {
  const McpToolsScreen({super.key});

  @override
  ConsumerState<McpToolsScreen> createState() => _McpToolsScreenState();
}

class _McpToolsScreenState extends ConsumerState<McpToolsScreen> {
  Future<List<ToolDefinition>>? _toolsFuture;

  @override
  void initState() {
    super.initState();
    _toolsFuture = _loadTools();
  }

  Future<List<ToolDefinition>> _loadTools() {
    return ref.read(toolRegistryProvider).listTools();
  }

  void _refreshTools() {
    ref.invalidate(toolRegistryProvider);
    setState(() {
      _toolsFuture = _loadTools();
    });
  }

  void _toggleExampleServer() {
    final manager = ref.read(mcpServerManagerProvider);
    if (manager.hasExampleServer()) {
      manager.removeServer(exampleMcpServerLabel);
    } else {
      manager.addExampleServer();
    }
    _refreshTools();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);
    final manager = ref.watch(mcpServerManagerProvider);
    final hasExampleServer = manager.hasExampleServer();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomInset = bottomSystemInset(context);

    return Column(
      children: [
        Container(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: topPadding + 8,
            bottom: 16,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? const Color(0xFF2A2A2A)
                    : const Color(0xFFE5E5E5),
              ),
            ),
          ),
          child: Row(
            children: [
              Builder(
                builder: (context) => IconButton(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedMenu01),
                  onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.mcp_tools_title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useTwoColumns = constraints.maxWidth >= 1080;
              final contentMaxWidth = useTwoColumns ? 1120.0 : 720.0;
              final horizontalPadding = constraints.maxWidth >= 720
                  ? 20.0
                  : 12.0;

              final mcpCard = _McpSectionCard(
                title: l10n.mcp_tools_title,
                children: [
                  _McpToggleSetting(
                    label: l10n.enable_mcp,
                    value: settings.mcpEnabled,
                    badges: [_FeatureBadge(label: l10n.experimental_label)],
                    onChanged: (value) {
                      ref.read(settingsProvider.notifier).setMcpEnabled(value);
                      _refreshTools();
                    },
                  ),
                  if (settings.mcpEnabled) ...[
                    _McpToggleSetting(
                      label: l10n.new_chat_mcp_default,
                      value: settings.newChatMcpEnabled,
                      onChanged: (value) => ref
                          .read(settingsProvider.notifier)
                          .setNewChatMcpEnabled(value),
                    ),
                    _McpToggleSetting(
                      label: l10n.calendar_access,
                      description: l10n.calendar_access_desc,
                      value: settings.calendarToolsEnabled,
                      onChanged: (value) async {
                        if (value) {
                          final cal = CalendarService.instance;
                          final granted = await cal.requestAccess();
                          if (granted) {
                            ref
                                .read(settingsProvider.notifier)
                                .setCalendarToolsEnabled(true);
                            _refreshTools();
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    l10n.calendar_permission_denied,
                                  ),
                                ),
                              );
                            }
                          }
                        } else {
                          ref
                              .read(settingsProvider.notifier)
                              .setCalendarToolsEnabled(false);
                          _refreshTools();
                        }
                      },
                    ),
                    _McpToggleSetting(
                      label: l10n.enable_example_server,
                      description: l10n.example_mcp_server_desc,
                      value: hasExampleServer,
                      onChanged: (_) => _toggleExampleServer(),
                    ),
                  ],
                ],
              );

              final toolsCard = _McpSectionCard(
                title: l10n.available_tools,
                accent: const Color(0xFF22C55E),
                icon: HugeIcons.strokeRoundedPuzzle,
                children: [_buildToolsContent(l10n, settings.mcpEnabled)],
              );

              return ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  12,
                  horizontalPadding,
                  24 + bottomInset,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: contentMaxWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          mcpCard,
                          if (settings.mcpEnabled) ...[
                            const SizedBox(height: 16),
                            _ConfiguredMcpServersCard(
                              onServersChanged: _refreshTools,
                            ),
                          ],
                          const SizedBox(height: 16),
                          toolsCard,
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildToolsContent(AppLocalizations l10n, bool mcpEnabled) {
    if (!mcpEnabled) {
      return _StatusPanel(
        icon: HugeIcons.strokeRoundedAlertCircle,
        title: l10n.mcp_disabled_warning,
        body: l10n.no_tools_registered_desc,
      );
    }

    return FutureBuilder<List<ToolDefinition>>(
      future: _toolsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _McpPanel(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return _StatusPanel(
            icon: HugeIcons.strokeRoundedInformationCircle,
            title: l10n.unable_load_tools,
            body: snapshot.error.toString(),
          );
        }

        final tools = snapshot.data ?? const <ToolDefinition>[];
        if (tools.isEmpty) {
          return _StatusPanel(
            icon: HugeIcons.strokeRoundedPuzzle,
            title: l10n.no_tools_registered,
            body: l10n.no_tools_registered_desc,
          );
        }

        return Column(
          children: tools
              .map((tool) => _ToolRow(tool: tool))
              .toList(growable: false),
        );
      },
    );
  }
}

class _McpSectionCard extends StatelessWidget {
  const _McpSectionCard({
    required this.title,
    required this.children,
    this.icon = HugeIcons.strokeRoundedMcpServer,
    this.accent = const Color(0xFF8B5CF6),
    this.trailing,
  });

  final String title;
  final List<List<dynamic>> icon;
  final Color accent;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _outlineColor(context, alpha: 0.9)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: HugeIcon(icon: icon, color: accent, size: 16),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
            const SizedBox(height: 12),
            ..._withVerticalSpacing(children, gap: 10),
          ],
        ),
      ),
    );
  }
}

class _McpPanel extends StatelessWidget {
  const _McpPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panelColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _outlineColor(context)),
      ),
      child: child,
    );
  }
}

class _McpToggleSetting extends StatelessWidget {
  const _McpToggleSetting({
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.badges = const [],
  });

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final List<Widget> badges;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _McpPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    ...badges,
                  ],
                ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.tool});

  final ToolDefinition tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isMcp = tool.providerType == ToolProviderType.mcp;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _McpPanel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HugeIcon(
              icon: isMcp
                  ? HugeIcons.strokeRoundedShare01
                  : (tool.name.startsWith('calendar.')
                        ? HugeIcons.strokeRoundedCalendar01
                        : HugeIcons.strokeRoundedCalculate),
              size: 18,
              color: isMcp
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tool.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (tool.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      tool.description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ToolBadge(
                        label: isMcp ? 'MCP' : l10n.built_in_label,
                        color: isMcp
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                      if (tool.providerRef != null)
                        _ToolBadge(
                          label: tool.providerRef!,
                          color: theme.colorScheme.secondary,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolBadge extends StatelessWidget {
  const _ToolBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.icon,
    required this.title,
    required this.body,
  });

  final List<List<dynamic>> icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _McpPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            HugeIcon(icon: icon, size: 28, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  const _FeatureBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.22)),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFFB45309),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.45,
        ),
      ),
    );
  }
}

// Visual helpers, kept in sync with settings_screen.dart to ensure the
// MCP screen matches the rest of the app's settings surfaces.
List<Widget> _withVerticalSpacing(List<Widget> children, {double gap = 12}) {
  if (children.isEmpty) return const [];
  return [
    for (var index = 0; index < children.length; index++) ...[
      children[index],
      if (index != children.length - 1) SizedBox(height: gap),
    ],
  ];
}

Color _panelColor(BuildContext context) {
  return ShadTheme.of(context).colorScheme.secondary;
}

Color _surfaceColor(BuildContext context) {
  return ShadTheme.of(context).colorScheme.card;
}

Color _outlineColor(BuildContext context, {double alpha = 0.6}) {
  return ShadTheme.of(context).colorScheme.border.withValues(alpha: alpha);
}

class _ConfiguredMcpServersCard extends ConsumerStatefulWidget {
  const _ConfiguredMcpServersCard({required this.onServersChanged});

  final VoidCallback onServersChanged;

  @override
  ConsumerState<_ConfiguredMcpServersCard> createState() =>
      __ConfiguredMcpServersCardState();
}

class __ConfiguredMcpServersCardState
    extends ConsumerState<_ConfiguredMcpServersCard> {
  final _serverLabelController = TextEditingController();
  final _serverUrlController = TextEditingController();

  @override
  void dispose() {
    _serverLabelController.dispose();
    _serverUrlController.dispose();
    super.dispose();
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

    ref.read(settingsProvider.notifier).addSavedMcpIntegration(integration);
    ref.read(chatMcpConfigProvider.notifier).addIntegration(integration);
    _serverLabelController.clear();
    _serverUrlController.clear();
    widget.onServersChanged();
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
              const HugeIcon(icon: HugeIcons.strokeRoundedFileImport, size: 22),
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
            padding: EdgeInsets.zero,
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
                  final count = ref
                      .read(chatMcpConfigProvider.notifier)
                      .importIntegrationsFromJson(jsonStr);
                  Navigator.of(dialogContext).pop();
                  widget.onServersChanged();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        count > 0
                            ? l10n.mcp_import_success(count)
                            : l10n.mcp_import_failed,
                      ),
                      backgroundColor: count > 0 ? Colors.green : Colors.red,
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);
    final savedIntegrations = settings.savedMcpIntegrations;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _McpSectionCard(
      title: l10n.active_integrations,
      accent: const Color(0xFF3B82F6),
      icon: HugeIcons.strokeRoundedMcpServer,
      trailing: ShadButton.outline(
        size: ShadButtonSize.sm,
        onPressed: () => _showImportJsonDialog(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HugeIcon(icon: HugeIcons.strokeRoundedFileImport, size: 16),
            const SizedBox(width: 4),
            Text(l10n.import_mcp_json),
          ],
        ),
      ),
      children: [
        if (savedIntegrations.isNotEmpty) ...[
          ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: savedIntegrations.length,
            itemBuilder: (context, index) {
              final integration = savedIntegrations[index];
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
                    color: integration.enabled ? null : Colors.grey,
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
                        onChanged: (v) {
                          ref
                              .read(settingsProvider.notifier)
                              .toggleSavedMcpIntegration(index, v);
                          ref
                              .read(chatMcpConfigProvider.notifier)
                              .toggleIntegration(index, v);
                        },
                      ),
                      const SizedBox(width: 4),
                      ShadIconButton.ghost(
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedDelete01,
                          size: 18,
                          color: Colors.red,
                        ),
                        onPressed: () {
                          ref
                              .read(settingsProvider.notifier)
                              .removeSavedMcpIntegration(index);
                          ref
                              .read(chatMcpConfigProvider.notifier)
                              .removeIntegration(index);
                          widget.onServersChanged();
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
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
      ],
    );
  }
}
