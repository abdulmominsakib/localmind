import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:localmind/core/theme/colors.dart';
import '../../data/models/conversation.dart';

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.isActive,
    required this.onTap,
    required this.onRename,
    required this.onTogglePin,
    required this.onDelete,
    required this.onDuplicate,
    required this.onMoveToFolder,
    required this.onExport,
    required this.onArchive,
    this.selectionMode = false,
    this.isSelected = false,
    this.onEnterSelectionMode,
  });

  final Conversation conversation;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onMoveToFolder;
  final VoidCallback onExport;
  final VoidCallback onArchive;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onEnterSelectionMode;

  String _formatTimestamp(AppLocalizations l10n, DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) {
      return l10n.conversation_just_now;
    } else if (diff.inHours < 1) {
      return l10n.conversation_minutes_ago(diff.inMinutes);
    } else if (diff.inHours < 24) {
      return l10n.conversation_hours_ago(diff.inHours);
    } else if (diff.inDays == 1) {
      return l10n.conversation_yesterday;
    } else if (diff.inDays < 7) {
      return l10n.conversation_days_ago(diff.inDays);
    } else {
      return l10n.conversation_date(dateTime.month, dateTime.day, dateTime.year);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dismissible(
      key: Key(conversation.id),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsetsDirectional.only(start: 16),
        color: Colors.blue,
        child: Icon(
          conversation.isArchived
              ? Icons.unarchive_outlined
              : Icons.archive_outlined,
          color: Colors.white,
        ),
      ),
      secondaryBackground: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 16),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onArchive();
        } else {
          onDelete();
        }
        return false;
      },
      child: Material(
        color: isActive
            ? (isDark
                  ? AppColors.darkAccent.withValues(alpha: 0.2)
                  : AppColors.lightAccent.withValues(alpha: 0.1))
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: () => _showContextMenu(context, l10n, isDark),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (selectionMode)
                  Checkbox(value: isSelected, onChanged: (_) => onTap())
                else
                  Icon(
                    conversation.isPinned
                        ? Icons.push_pin
                        : Icons.chat_bubble_outline,
                    size: 20,
                    color: isActive
                        ? (isDark
                              ? AppColors.darkAccent
                              : AppColors.lightAccent)
                        : (isDark
                              ? AppColors.darkMutedText
                              : AppColors.lightMutedText),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (conversation.lastMessagePreview != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          conversation.lastMessagePreview!,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkMutedText
                                : AppColors.lightMutedText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        [
                          l10n.conversation_message_count(conversation.messageCount),
                          l10n.conversation_character_count(conversation.characterCount),
                          if (conversation.totalTokenCount != null)
                            l10n.total_tokens_count(conversation.totalTokenCount!),
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.darkMutedText
                              : AppColors.lightMutedText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatTimestamp(l10n, conversation.updatedAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkMutedText
                        : AppColors.lightMutedText,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _showContextMenu(context, l10n, isDark),
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedMoreVertical,
                    size: 18,
                    color: isDark
                        ? AppColors.darkMutedText
                        : AppColors.lightMutedText,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.options_tooltip,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, AppLocalizations l10n, bool isDark) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onEnterSelectionMode != null)
                ListTile(
                  leading: const Icon(Icons.checklist_outlined),
                  title: Text(l10n.select),
                  onTap: () {
                    Navigator.pop(ctx);
                    onEnterSelectionMode!();
                  },
                ),
              ListTile(
                leading: Icon(
                  conversation.isPinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin,
                ),
                title: Text(conversation.isPinned ? l10n.unpin : l10n.pin),
                onTap: () {
                  Navigator.pop(ctx);
                  onTogglePin();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.rename),
                onTap: () {
                  Navigator.pop(ctx);
                  onRename();
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: Text(l10n.duplicate_chat),
                onTap: () {
                  Navigator.pop(ctx);
                  onDuplicate();
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(l10n.move_to_folder),
                onTap: () {
                  Navigator.pop(ctx);
                  onMoveToFolder();
                },
              ),
              ListTile(
                leading: const Icon(Icons.upload_outlined),
                title: Text(l10n.export_conversation),
                onTap: () {
                  Navigator.pop(ctx);
                  onExport();
                },
              ),
              ListTile(
                leading: Icon(
                  conversation.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                title: Text(
                  conversation.isArchived
                      ? l10n.unarchive_chat
                      : l10n.archive_chat,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onArchive();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(
                  l10n.delete,
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
