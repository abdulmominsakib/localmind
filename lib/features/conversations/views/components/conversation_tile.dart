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
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        l10n.conversation_message_count(
                          conversation.messageCount,
                        ),
                        l10n.conversation_character_count(
                          conversation.characterCount,
                        ),
                        if (conversation.totalTokenCount != null)
                          l10n.total_tokens_count(
                            conversation.totalTokenCount!,
                          ),
                      ].join(' · '),
                      style: TextStyle(fontSize: 12.5, color: muted),
                    ),
                  ],
                ),
              ),
              if (onEnterSelectionMode != null)
                ListTile(
                  leading: const HugeIcon(
                    icon: HugeIcons.strokeRoundedCheckList,
                  ),
                  title: Text(l10n.select),
                  onTap: () {
                    Navigator.pop(ctx);
                    onEnterSelectionMode!();
                  },
                ),
              ListTile(
                leading: HugeIcon(
                  icon: conversation.isPinned
                      ? HugeIcons.strokeRoundedPin
                      : HugeIcons.strokeRoundedPin,
                ),
                title: Text(conversation.isPinned ? l10n.unpin : l10n.pin),
                onTap: () {
                  Navigator.pop(ctx);
                  onTogglePin();
                },
              ),
              ListTile(
                leading: const HugeIcon(
                  icon: HugeIcons.strokeRoundedPencilEdit02,
                ),
                title: Text(l10n.rename),
                onTap: () {
                  Navigator.pop(ctx);
                  onRename();
                },
              ),
              ListTile(
                leading: const HugeIcon(icon: HugeIcons.strokeRoundedCopy),
                title: Text(l10n.duplicate_chat),
                onTap: () {
                  Navigator.pop(ctx);
                  onDuplicate();
                },
              ),
              ListTile(
                leading: const HugeIcon(icon: HugeIcons.strokeRoundedFolder01),
                title: Text(l10n.move_to_folder),
                onTap: () {
                  Navigator.pop(ctx);
                  onMoveToFolder();
                },
              ),
              ListTile(
                leading: const HugeIcon(icon: HugeIcons.strokeRoundedUpload01),
                title: Text(l10n.export_conversation),
                onTap: () {
                  Navigator.pop(ctx);
                  onExport();
                },
              ),
              ListTile(
                leading: HugeIcon(
                  icon: conversation.isArchived
                      ? HugeIcons.strokeRoundedArchive
                      : HugeIcons.strokeRoundedArchive,
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
                leading: const HugeIcon(
                  icon: HugeIcons.strokeRoundedDelete01,
                  color: Colors.red,
                ),
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
