import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import '../../../../core/models/enums.dart';
import 'connection_status_indicator.dart';
import 'server_icon_picker.dart';

class ServerCard extends StatelessWidget {
  final Server server;
  final bool isActive;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onSetDefault;

  const ServerCard({
    super.key,
    required this.server,
    this.isActive = false,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onSetDefault,
  });

  HugeIconData? get _serverIconData {
    if (server.iconName != null) {
      return getHugeIconByName(server.iconName);
    }
    return getDefaultServerIcon(server.type.name);
  }

  String get _serverTypeName {
    switch (server.type) {
      case ServerType.lmStudio:
        return 'LM Studio';
      case ServerType.openAICompatible:
        return 'OpenAI Compatible';
      case ServerType.ollama:
        return 'Ollama';
      case ServerType.openRouter:
        return 'OpenRouter';
    }
  }

  String get _serverAddress {
    if (server.type == ServerType.openRouter) {
      return 'openrouter.ai';
    }
    return '${server.host}:${server.port}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final activeGreen = const Color(0xFF22C55E);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isActive
            ? activeGreen.withValues(alpha: 0.08)
            : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? activeGreen.withValues(alpha: 0.5)
              : theme.dividerColor.withValues(alpha: 0.1),
          width: isActive ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            if (isActive)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: activeGreen,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(4),
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isActive
                          ? activeGreen.withValues(alpha: 0.1)
                          : theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isActive
                            ? activeGreen.withValues(alpha: 0.2)
                            : Colors.transparent,
                      ),
                    ),
                    child: _serverIconData != null
                        ? HugeIcon(
                            icon: _serverIconData!.icon,
                            size: 24,
                            color: isActive
                                ? activeGreen
                                : theme.colorScheme.onSurfaceVariant,
                          )
                        : Icon(
                            Icons.dns,
                            color: isActive
                                ? activeGreen
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                server.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                margin: const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  color: activeGreen,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Active',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            if (server.isDefault)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? activeGreen.withValues(alpha: 0.05)
                                      : theme.colorScheme.outline
                                          .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isActive
                                        ? activeGreen.withValues(alpha: 0.3)
                                        : theme.colorScheme.outline,
                                  ),
                                ),
                                child: Text(
                                  'Default',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: isActive
                                        ? activeGreen
                                        : theme.colorScheme.outline,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(_serverTypeName,
                                style: theme.textTheme.bodySmall),
                            const SizedBox(width: 8),
                            Text('•', style: theme.textTheme.bodySmall),
                            const SizedBox(width: 8),
                            Text(_serverAddress,
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ConnectionStatusIndicator(status: server.status),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          onEdit?.call();
                          break;
                        case 'delete':
                          onDelete?.call();
                          break;
                        case 'setDefault':
                          onSetDefault?.call();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      if (!server.isDefault)
                        const PopupMenuItem(
                          value: 'setDefault',
                          child: Row(
                            children: [
                              Icon(Icons.star, size: 18),
                              SizedBox(width: 8),
                              Text('Set as Default'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
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
