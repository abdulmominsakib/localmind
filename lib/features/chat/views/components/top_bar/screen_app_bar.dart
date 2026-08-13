import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:auto_size_text_plus/auto_size_text_plus.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:localmind/core/services/export_choice_dialog.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/chat/views/components/chat_settings_sheet.dart';
import 'package:localmind/features/chat/providers/chat_mcp_providers.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/chat/data/export_service.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';

class ScreenAppBar extends ConsumerWidget {
  const ScreenAppBar({
    super.key,
    required this.activeConversation,
    required this.isDark,
    required this.hasPersonas,
    required this.isTemporary,
    required this.hasMessages,
    required this.onMenuAction,
    required this.onPersonaPicker,
    required this.onChatModeAction,
  });

  final Conversation? activeConversation;
  final bool isDark;
  final bool hasPersonas;
  final bool isTemporary;
  final bool hasMessages;
  final void Function(String) onMenuAction;
  final VoidCallback onPersonaPicker;
  final VoidCallback onChatModeAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);
    final mcpConfig = ref.watch(chatMcpConfigProvider);
    final isMcpEnabled = settings.mcpEnabled && mcpConfig.enabled;
    final messageSelectionMode = ref.watch(messageSelectionModeProvider);
    final selectedMessageIds = ref.watch(selectedMessageIdsProvider);

    if (messageSelectionMode) {
      return SafeArea(
        top: true,
        bottom: false,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              IconButton(
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01),
                onPressed: () =>
                    ref.read(messageSelectionModeProvider.notifier).disable(),
              ),
              Expanded(
                child: Text(
                  l10n.selected_count(selectedMessageIds.length),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedShare01),
                tooltip: l10n.export_conversation,
                onPressed: selectedMessageIds.isEmpty
                    ? null
                    : () => _shareSelectedMessages(
                        context,
                        ref,
                        selectedMessageIds,
                      ),
              ),
              IconButton(
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedDelete01,
                  color: Colors.red,
                ),
                tooltip: l10n.delete,
                onPressed: selectedMessageIds.isEmpty
                    ? null
                    : () => _deleteSelectedMessages(
                        context,
                        ref,
                        selectedMessageIds,
                      ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: true,
      bottom: false,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            ShadResponsiveBuilder(
              builder: (context, breakpoint) {
                final isDesktop =
                    breakpoint >= ShadTheme.of(context).breakpoints.md;
                if (isDesktop) return const SizedBox.shrink();
                return IconButton(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedMenu01),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                );
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TitleBlock(title: _appBarTitle(l10n), isDark: isDark),
            ),
            Stack(
              children: [
                IconButton(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedFilterHorizontal,
                    size: 24,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  onPressed: () =>
                      showChatSettingsSheet(context, initialTab: 'parameters'),
                  tooltip: l10n.chat_parameters_tooltip,
                ),
                PositionedDirectional(
                  top: 4,
                  end: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isMcpEnabled ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                    child: const HugeIcon(
                      icon: HugeIcons.strokeRoundedTools,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            ChatModeIconButton(
              hasMessages: hasMessages,
              isTemporary: isTemporary,
              isDark: isDark,
              onPressed: onChatModeAction,
            ),
            PopupMenuButton<String>(
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical),
              onSelected: onMenuAction,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'new_chat',
                  child: ListTile(
                    leading: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01),
                    title: Text(l10n.nav_new_chat),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (activeConversation != null && !isTemporary) ...[
                  PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      leading: const HugeIcon(
                        icon: HugeIcons.strokeRoundedPencilEdit02,
                      ),
                      title: Text(l10n.rename_conversation),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'move_to_folder',
                    child: ListTile(
                      leading: const HugeIcon(
                        icon: HugeIcons.strokeRoundedFolder01,
                      ),
                      title: Text(l10n.move_to_folder),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
                if (hasMessages) ...[
                  PopupMenuItem(
                    value: 'export_chat',
                    child: ListTile(
                      leading: const HugeIcon(
                        icon: HugeIcons.strokeRoundedUpload01,
                      ),
                      title: Text(l10n.export_conversation),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share_chat',
                    child: ListTile(
                      leading: const HugeIcon(
                        icon: HugeIcons.strokeRoundedShare01,
                      ),
                      title: Text(l10n.share_conversation),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
                PopupMenuItem(
                  value: 'persona',
                  child: ListTile(
                    leading: HugeIcon(
                      icon: hasPersonas
                          ? HugeIcons.strokeRoundedExchange01
                          : HugeIcons.strokeRoundedRobot01,
                    ),
                    title: Text(
                      hasPersonas ? l10n.change_persona : l10n.set_persona,
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                    leading: const HugeIcon(
                      icon: HugeIcons.strokeRoundedDelete01,
                    ),
                    title: Text(l10n.clear_conversation),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _appBarTitle(AppLocalizations l10n) {
    if (isTemporary) return l10n.temporary_chat;
    if (activeConversation?.title.isNotEmpty == true) {
      final title = activeConversation!.title;
      if (title.length > 30) {
        return '${title.substring(0, 30)}...';
      }
      return title;
    }
    return l10n.nav_new_chat;
  }

  Future<void> _shareSelectedMessages(
    BuildContext context,
    WidgetRef ref,
    Set<String> selectedIds,
  ) async {
    final messages = ref
        .read(chatProvider)
        .messages
        .where((m) => selectedIds.contains(m.id))
        .toList();
    if (messages.isEmpty) return;
    final text = ExportService.exportAsText(messages);
    ref.read(messageSelectionModeProvider.notifier).disable();
    if (!context.mounted) return;
    await showExportChoiceDialog(context, content: text);
  }

  void _deleteSelectedMessages(
    BuildContext context,
    WidgetRef ref,
    Set<String> selectedIds,
  ) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.delete_message_title),
          content: Text(l10n.selected_count(selectedIds.length)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                for (final id in selectedIds) {
                  await ref.read(chatProvider.notifier).deleteMessage(id);
                }
                ref.read(messageSelectionModeProvider.notifier).disable();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
  }
}

class ChatModeIconButton extends StatelessWidget {
  const ChatModeIconButton({
    super.key,
    required this.hasMessages,
    required this.isTemporary,
    required this.isDark,
    required this.onPressed,
  });

  final bool hasMessages;
  final bool isTemporary;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showGhost = !hasMessages || isTemporary;
    final ghostActive = isTemporary;

    if (showGhost) {
      final activeColor = isDark
          ? const Color(0xFFE6C35C)
          : const Color(0xFF9A7B1A);
      final inactiveColor = isDark ? Colors.white54 : Colors.black45;

      return IconButton(
        onPressed: onPressed,
        tooltip: ghostActive
            ? l10n.exit_temporary_chat_title
            : l10n.temporary_chat,
        icon: ghostActive
            ? Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: activeColor.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedIncognito,
                  size: 20,
                  color: activeColor,
                ),
              )
            : HugeIcon(
                icon: HugeIcons.strokeRoundedIncognito,
                size: 22,
                color: inactiveColor,
              ),
      );
    }

    return IconButton(
      onPressed: onPressed,
      tooltip: l10n.nav_new_chat,
      icon: HugeIcon(
        icon: HugeIcons.strokeRoundedMessageAdd01,
        size: 22,
        color: isDark ? Colors.white70 : Colors.black87,
      ),
    );
  }
}

/// Title block shown in the chat app bar — conversation title on top and the
/// active server name below. Model selection is already visible and editable
/// from the model picker near the composer.
class _TitleBlock extends ConsumerWidget {
  const _TitleBlock({required this.title, required this.isDark});

  final String title;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeServer = ref.watch(activeServerProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);
    final mutedColor = isDark
        ? AppColors.darkMutedText
        : AppColors.lightMutedText;
    final isConnected = connectionStatus == ConnectionStatus.connected;
    final statusColor = isConnected ? Colors.green : Colors.grey;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AutoSizeText(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (activeServer != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    activeServer.name,
                    style: TextStyle(fontSize: 11, color: mutedColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          else
            Text('', style: TextStyle(fontSize: 11, color: mutedColor)),
        ],
      ),
    );
  }
}
