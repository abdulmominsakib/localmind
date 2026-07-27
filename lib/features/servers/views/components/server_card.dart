import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../../../core/models/enums.dart';
import '../../data/models/server.dart';
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

  static const _accent = Color(0xFF22C55E);
  static const _warning = Color(0xFFF59E0B);
  static const _error = Color(0xFFEF4444);
  static const _neutral = Color(0xFF71717A);

  HugeIconData? get _serverIconData {
    if (server.iconName != null) {
      return getHugeIconByName(server.iconName);
    }
    return getDefaultServerIcon(server.type.name);
  }

  String _serverTypeName(AppLocalizations l10n) {
    switch (server.type) {
      case ServerType.lmStudio:
        return l10n.server_type_lm_studio_display;
      case ServerType.openAICompatible:
        return l10n.server_type_openai_display;
      case ServerType.ollama:
        return l10n.server_type_ollama_display;
      case ServerType.openRouter:
        return l10n.server_type_openrouter_display;
      case ServerType.onDevice:
        return l10n.server_type_on_device_display;
    }
  }

  String _serverAddress(AppLocalizations l10n) {
    if (server.type == ServerType.openRouter) {
      return l10n.server_address_openrouter;
    }
    if (server.type == ServerType.onDevice) {
      return l10n.server_address_on_device;
    }
    return server.displayAddress;
  }

  String _statusLabel(AppLocalizations l10n) {
    switch (server.status) {
      case ConnectionStatus.connected:
        return l10n.connected;
      case ConnectionStatus.disconnected:
        return l10n.offline;
      case ConnectionStatus.checking:
        return l10n.checking;
      case ConnectionStatus.error:
        return l10n.error;
    }
  }

  Color _statusColor() {
    switch (server.status) {
      case ConnectionStatus.connected:
        return _accent;
      case ConnectionStatus.error:
        return _error;
      case ConnectionStatus.checking:
        return _warning;
      case ConnectionStatus.disconnected:
        return _neutral;
    }
  }

  List<List<dynamic>> _typeIcon() {
    switch (server.type) {
      case ServerType.lmStudio:
        return HugeIcons.strokeRoundedComputerTerminal01;
      case ServerType.openAICompatible:
        return HugeIcons.strokeRoundedAiChat01;
      case ServerType.ollama:
        return HugeIcons.strokeRoundedRobot01;
      case ServerType.openRouter:
        return HugeIcons.strokeRoundedCloud;
      case ServerType.onDevice:
        return HugeIcons.strokeRoundedHardDrive;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusColor = _statusColor();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: isActive
            ? (isDark
                  ? _accent.withValues(alpha: 0.10)
                  : _accent.withValues(alpha: 0.06))
            : theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? _accent.withValues(alpha: 0.45)
              : theme.dividerColor.withValues(alpha: isDark ? 0.12 : 0.08),
          width: isActive ? 1.5 : 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIcon(theme, isDark),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTitleRow(theme, isDark, l10n),
                      const SizedBox(height: 6),
                      _buildTypeChip(theme, isDark, l10n),
                      const SizedBox(height: 6),
                      _buildAddressRow(theme, l10n),
                      const SizedBox(height: 10),
                      _buildStatusRow(statusColor, l10n),
                    ],
                  ),
                ),
                _buildMenu(theme, l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(ThemeData theme, bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: isActive
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _accent.withValues(alpha: 0.20),
                  _accent.withValues(alpha: 0.06),
                ],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  isDark
                      ? Colors.white.withValues(alpha: 0.02)
                      : Colors.black.withValues(alpha: 0.01),
                ],
              ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: isActive
              ? _accent.withValues(alpha: 0.30)
              : theme.dividerColor.withValues(alpha: isDark ? 0.15 : 0.10),
          width: 1,
        ),
      ),
      child: Center(
        child: _serverIconData != null
            ? HugeIcon(
                icon: _serverIconData!.icon,
                size: 22,
                color: isActive ? _accent : theme.colorScheme.onSurfaceVariant,
              )
            : HugeIcon(
                icon: HugeIcons.strokeRoundedDatabase,
                size: 22,
                color: isActive ? _accent : theme.colorScheme.onSurfaceVariant,
              ),
      ),
    );
  }

  Widget _buildTitleRow(ThemeData theme, bool isDark, AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            server.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              height: 1.25,
              color: isActive
                  ? (isDark ? Colors.white : const Color(0xFF0A0A0A))
                  : theme.colorScheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        if (server.isDefault) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: l10n.default_badge,
            child: const HugeIcon(
              icon: HugeIcons.strokeRoundedStar,
              size: 14,
              color: _warning,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTypeChip(ThemeData theme, bool isDark, AppLocalizations l10n) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: _typeIcon(),
              size: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              _serverTypeName(l10n),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                fontSize: 11,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressRow(ThemeData theme, AppLocalizations l10n) {
    return Row(
      children: [
        HugeIcon(
          icon: HugeIcons.strokeRoundedLink01,
          size: 12,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            _serverAddress(l10n),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: -0.1,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusRow(Color statusColor, AppLocalizations l10n) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConnectionStatusIndicator(status: server.status, size: 8),
            const SizedBox(width: 5),
            Text(
              _statusLabel(l10n),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: statusColor,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenu(ThemeData theme, AppLocalizations l10n) {
    return SizedBox(
      width: 32,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        iconSize: 18,
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
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedPencilEdit02,
                  size: 18,
                  color: theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 8),
                Text(l10n.edit),
              ],
            ),
          ),
          if (!server.isDefault)
            PopupMenuItem(
              value: 'setDefault',
              child: Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedStar,
                    size: 18,
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Text(l10n.set_as_default),
                ],
              ),
            ),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const HugeIcon(
                  icon: HugeIcons.strokeRoundedDelete01,
                  size: 18,
                  color: Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.delete,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}