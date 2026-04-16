import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/enums.dart';
import '../../../core/routes/app_routes.dart';
import '../../servers/providers/server_providers.dart';
import '../../servers/views/components/server_icon_picker.dart';

class ActiveServerIndicator extends ConsumerWidget {
  const ActiveServerIndicator({super.key});

  Color _getStatusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.error:
        return Colors.red;
      case ConnectionStatus.checking:
        return Colors.orange;
      case ConnectionStatus.disconnected:
        return Colors.grey;
    }
  }

  String _getStatusText(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return 'Online';
      case ConnectionStatus.error:
        return 'Error';
      case ConnectionStatus.checking:
        return 'Checking...';
      case ConnectionStatus.disconnected:
        return 'Offline';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final activeServer = ref.watch(activeServerProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);
    final serversAsync = ref.watch(serversProvider);

    if (activeServer == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(50),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedServerStack01,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No server selected',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final statusColor = _getStatusColor(connectionStatus);
    final iconName = activeServer.iconName;
    final serverIcon = iconName != null
        ? (getHugeIconByName(iconName)?.icon ??
              getDefaultServerIcon(activeServer.type.name)?.icon)
        : getDefaultServerIcon(activeServer.type.name)?.icon;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: InkWell(
        onTap: () {
          final servers = serversAsync.value ?? [];

          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  // Drag Handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withAlpha(50),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Header
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
                                'Switch Server',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Choose a server to connect to',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 20),
                          visualDensity: VisualDensity.compact,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Content
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...servers.asMap().entries.map((entry) {
                            final index = entry.key;
                            final server = entry.value;
                            final isCurrentlyActive =
                                server.id == activeServer.id;
                            final serverIconName = server.iconName;
                            final currentServerIcon = serverIconName != null
                                ? (getHugeIconByName(serverIconName)?.icon ??
                                      getDefaultServerIcon(
                                        server.type.name,
                                      )?.icon)
                                : getDefaultServerIcon(server.type.name)?.icon;

                            return TweenAnimationBuilder<double>(
                              duration: Duration(
                                milliseconds: 300 + (index * 50),
                              ),
                              curve: Curves.easeOutQuart,
                              tween: Tween(begin: 0.0, end: 1.0),
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: value,
                                  child: Transform.translate(
                                    offset: Offset(0, 20 * (1 - value)),
                                    child: child,
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: InkWell(
                                  onTap: isCurrentlyActive
                                      ? null
                                      : () {
                                          ref
                                              .read(
                                                activeServerProvider.notifier,
                                              )
                                              .setActiveServer(server);
                                          Navigator.pop(context);
                                        },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isCurrentlyActive
                                          ? (isDark
                                                ? colorScheme.primary.withAlpha(
                                                    30,
                                                  )
                                                : colorScheme.primary.withAlpha(
                                                    20,
                                                  ))
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
                                          icon:
                                              currentServerIcon ??
                                              HugeIcons
                                                  .strokeRoundedServerStack01,
                                          size: 20,
                                          color: isCurrentlyActive
                                              ? colorScheme.primary
                                              : colorScheme.onSurface,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
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
                                                    ? 'Active'
                                                    : (server.host.isEmpty
                                                          ? 'Local'
                                                          : server.host),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isCurrentlyActive
                                                      ? colorScheme.primary
                                                            .withAlpha(150)
                                                      : colorScheme
                                                            .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isCurrentlyActive)
                                          Icon(
                                            Icons.check_circle,
                                            size: 20,
                                            color: colorScheme.primary,
                                          )
                                        else
                                          const Icon(
                                            Icons.chevron_right,
                                            size: 20,
                                            color: Colors.grey,
                                          ),
                                      ],
                                    ),
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
                            leading: const Icon(Icons.settings, size: 18),
                            onPressed: () {
                              Navigator.pop(context);
                              context.go(AppRoutes.servers);
                              if (Scaffold.maybeOf(context)?.isDrawerOpen ??
                                  false) {
                                Navigator.pop(context);
                              }
                            },
                            child: const Text('Manage Servers'),
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
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withAlpha(15)
                : Colors.black.withAlpha(10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withAlpha(20)
                  : Colors.black.withAlpha(10),
            ),
          ),
          child: Row(
            children: [
              HugeIcon(
                icon: serverIcon ?? HugeIcons.strokeRoundedServerStack01,
                size: 18,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      activeServer.name,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _getStatusText(connectionStatus),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor.withAlpha(200),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.unfold_more, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
