import 'package:flutter/material.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import '../../../core/models/enums.dart';
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

    return Card(
      color: isActive
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _serverIconData != null
                    ? HugeIcon(
                        _serverIconData!.iconData,
                        size: 24,
                        color: theme.colorScheme.primary,
                      )
                    : Icon(Icons.dns, color: theme.colorScheme.primary),
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
                        if (server.isDefault)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Default',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(_serverTypeName, style: theme.textTheme.bodySmall),
                        const SizedBox(width: 8),
                        Text('•', style: theme.textTheme.bodySmall),
                        const SizedBox(width: 8),
                        Text(_serverAddress, style: theme.textTheme.bodySmall),
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
      ),
    );
  }
}
