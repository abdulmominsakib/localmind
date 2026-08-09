import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../l10n/app_localizations.dart';
import '../../providers/server_providers.dart';
import 'server_icon_picker.dart';

void showServerPickerSheet(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;
  final activeServer = ref.read(activeServerProvider);
  final serversAsync = ref.read(serversProvider);
  final servers = serversAsync.value ?? [];

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withAlpha(50),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.switch_server,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.switch_server_subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 20),
                  visualDensity: VisualDensity.compact,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.6,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (activeServer == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        l10n.no_server_selected,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ...servers.map((server) {
                    final isCurrentlyActive = server.id == activeServer?.id;
                    final serverIconName = server.iconName;
                    final currentServerIcon = serverIconName != null
                        ? (getHugeIconByName(serverIconName)?.icon ??
                              getDefaultServerIcon(server.type.name)?.icon)
                        : getDefaultServerIcon(server.type.name)?.icon;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: isCurrentlyActive
                            ? null
                            : () {
                                ref
                                    .read(activeServerIdProvider.notifier)
                                    .setActiveServer(server);
                                Navigator.pop(context);
                              },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isCurrentlyActive
                                ? (isDark
                                      ? colorScheme.primary.withAlpha(30)
                                      : colorScheme.primary.withAlpha(20))
                                : (isDark
                                      ? Colors.white.withAlpha(10)
                                      : Colors.black.withAlpha(5)),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isCurrentlyActive
                                  ? colorScheme.primary.withAlpha(100)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            children: [
                              HugeIcon(
                                icon: currentServerIcon ??
                                    HugeIcons.strokeRoundedServerStack01,
                                size: 20,
                                color: isCurrentlyActive
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      server.name,
                                      style: TextStyle(
                                        fontWeight: isCurrentlyActive
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: isCurrentlyActive
                                            ? colorScheme.primary
                                            : colorScheme.onSurface,
                                      ),
                                    ),
                                    Text(
                                      isCurrentlyActive
                                          ? l10n.active
                                          : (server.host.isEmpty
                                                ? 'Local'
                                                : server.host),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isCurrentlyActive
                                            ? colorScheme.primary.withAlpha(150)
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isCurrentlyActive)
                                HugeIcon(icon: 
                                  HugeIcons.strokeRoundedCheckmarkCircle01,
                                  size: 20,
                                  color: colorScheme.primary,
                                )
                              else
                                const HugeIcon(icon: 
                                  HugeIcons.strokeRoundedArrowRight01,
                                  size: 20,
                                  color: Colors.grey,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  const ShadSeparator.horizontal(),
                  const SizedBox(height: 12),
                  ShadButton.ghost(
                    width: double.infinity,
                    leading: const HugeIcon(icon: HugeIcons.strokeRoundedSettings01, size: 18),
                    onPressed: () {
                      Navigator.pop(context);
                      context.go(AppRoutes.servers);
                    },
                    child: Text(l10n.manage_servers),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}
