import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/components/action_sheet.dart';
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
    this.isGenerating = false,
  });

  /// A reply for this chat is still generating (possibly in the background).
  final bool isGenerating;

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
      return l10n.conversation_date(
        dateTime.month,
        dateTime.day,
        dateTime.year,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;
    // Previews can start with blank lines or carry line breaks; show one
    // tidy line.
    final preview = (conversation.lastMessagePreview ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return Dismissible(
      key: Key(conversation.id),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsetsDirectional.only(start: 16),
        color: Colors.blue,
        child: HugeIcon(
          icon: conversation.isArchived
              ? HugeIcons.strokeRoundedArchive
              : HugeIcons.strokeRoundedArchive,
          color: Colors.white,
        ),
      ),
      secondaryBackground: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 16),
        color: Colors.red,
        child: const HugeIcon(
          icon: HugeIcons.strokeRoundedDelete01,
          color: Colors.white,
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onArchive();
        } else {
          onDelete();
        }
        return false;
      },
      // Title and time on one line, the last message underneath. Actions
      // live behind long-press / right-click and the swipe gestures above,
      // rather than an icon, a stats line and a menu button on every row.
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('conversation_${conversation.id}'),
          onTap: onTap,
          onLongPress: () => _showContextMenu(context, l10n, isDark),
          onSecondaryTap: () => _showContextMenu(context, l10n, isDark),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: isActive
                  ? (isDark
                        ? AppColors.darkSurfaceCard
                        : AppColors.lightBorder.withValues(alpha: 0.6))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                if (selectionMode) ...[
                  Checkbox(value: isSelected, onChanged: (_) => onTap()),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isGenerating) ...[
                            SizedBox.square(
                              dimension: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: isDark
                                    ? AppColors.darkAccent
                                    : AppColors.lightAccent,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ] else if (conversation.isPinned) ...[
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedPin,
                              size: 14,
                              color: muted,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              conversation.title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isDark
                                    ? AppColors.darkPrimaryText
                                    : AppColors.lightPrimaryText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _formatTimestamp(l10n, conversation.updatedAt),
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          preview,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            color: muted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showContextMenu(
    BuildContext context,
    AppLocalizations l10n,
    bool isDark,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ConversationActionsSheet(
        conversation: conversation,
        onEnterSelectionMode: onEnterSelectionMode,
        onTogglePin: onTogglePin,
        onRename: onRename,
        onDuplicate: onDuplicate,
        onMoveToFolder: onMoveToFolder,
        onExport: onExport,
        onArchive: onArchive,
        onDelete: onDelete,
      ),
    );
  }
}

/// Everything you can do with one chat: what it is up top, then grouped
/// actions — organise, share, and (last, in red) archive or delete.
class ConversationActionsSheet extends StatelessWidget {
  const ConversationActionsSheet({
    super.key,
    required this.conversation,
    required this.onTogglePin,
    required this.onRename,
    required this.onDuplicate,
    required this.onMoveToFolder,
    required this.onExport,
    required this.onArchive,
    required this.onDelete,
    this.onEnterSelectionMode,
  });

  final Conversation conversation;
  final VoidCallback onTogglePin;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onMoveToFolder;
  final VoidCallback onExport;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback? onEnterSelectionMode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    void run(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conversation.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.darkPrimaryText
                        : AppColors.lightPrimaryText,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    l10n.conversation_message_count(conversation.messageCount),
                    l10n.conversation_character_count(
                      conversation.characterCount,
                    ),
                    if (conversation.totalTokenCount != null)
                      l10n.total_tokens_count(conversation.totalTokenCount!),
                  ].join(' · '),
                  style: TextStyle(fontSize: 13, color: muted),
                ),
              ],
            ),
          ),
          ActionSheetGroup(
            children: [
              ActionSheetTile(
                key: const ValueKey('conversation_action_pin'),
                icon: HugeIcons.strokeRoundedPin,
                label: conversation.isPinned ? l10n.unpin : l10n.pin,
                onTap: () => run(onTogglePin),
              ),
              ActionSheetTile(
                key: const ValueKey('conversation_action_rename'),
                icon: HugeIcons.strokeRoundedPencilEdit02,
                label: l10n.rename,
                onTap: () => run(onRename),
              ),
              ActionSheetTile(
                key: const ValueKey('conversation_action_move'),
                icon: HugeIcons.strokeRoundedFolder01,
                label: l10n.move_to_folder,
                onTap: () => run(onMoveToFolder),
              ),
              ActionSheetTile(
                key: const ValueKey('conversation_action_duplicate'),
                icon: HugeIcons.strokeRoundedCopy01,
                label: l10n.duplicate_chat,
                onTap: () => run(onDuplicate),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ActionSheetGroup(
            children: [
              ActionSheetTile(
                key: const ValueKey('conversation_action_export'),
                icon: HugeIcons.strokeRoundedUpload01,
                label: l10n.export_conversation,
                onTap: () => run(onExport),
              ),
              if (onEnterSelectionMode != null)
                ActionSheetTile(
                  key: const ValueKey('conversation_action_select'),
                  icon: HugeIcons.strokeRoundedCheckList,
                  label: l10n.select,
                  onTap: () => run(onEnterSelectionMode!),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ActionSheetGroup(
            children: [
              ActionSheetTile(
                key: const ValueKey('conversation_action_archive'),
                icon: HugeIcons.strokeRoundedArchive,
                label: conversation.isArchived
                    ? l10n.unarchive_chat
                    : l10n.archive_chat,
                onTap: () => run(onArchive),
              ),
              ActionSheetTile(
                key: const ValueKey('conversation_action_delete'),
                icon: HugeIcons.strokeRoundedDelete01,
                label: l10n.delete,
                isDestructive: true,
                onTap: () => run(onDelete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
