import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/components/action_sheet.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../data/models/saved_message.dart';

class SavedMessageTile extends StatelessWidget {
  const SavedMessageTile({
    super.key,
    required this.saved,
    required this.isUser,
    required this.onTap,
    required this.onCopy,
    required this.onMoveToFolder,
    required this.onDelete,
    required this.onArchive,
    this.selectionMode = false,
    this.isSelected = false,
    this.onEnterSelectionMode,
  });

  final SavedMessage saved;
  final bool isUser;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onMoveToFolder;
  final VoidCallback onDelete;
  final VoidCallback onArchive;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onEnterSelectionMode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isFromTempChat = saved.conversationId.isEmpty;
    final mutedColor = isDark
        ? AppColors.darkMutedText
        : AppColors.lightMutedText;

    return Dismissible(
      key: Key(saved.id),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsetsDirectional.only(start: 16),
        color: Colors.blue,
        child: HugeIcon(
          icon: saved.isArchived
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
      // Where it came from on top, the message underneath. Actions live
      // behind long-press / right-click and the swipe gestures above.
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('saved_${saved.id}'),
          onTap: onTap,
          onLongPress: () => _showActions(context),
          onSecondaryTap: () => _showActions(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                          HugeIcon(
                            icon: isUser
                                ? HugeIcons.strokeRoundedUser
                                : HugeIcons.strokeRoundedSparkles,
                            size: 14,
                            color: mutedColor,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isFromTempChat
                                  ? l10n.temporary_chat
                                  : saved.conversationTitle,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: mutedColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (saved.isArchived) ...[
                            const SizedBox(width: 6),
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedArchive,
                              size: 14,
                              color: mutedColor,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        saved.content.trim(),
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.4,
                          color: isDark
                              ? AppColors.darkPrimaryText
                              : AppColors.lightPrimaryText,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
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

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SavedMessageActionsSheet(
        saved: saved,
        onCopy: onCopy,
        onMoveToFolder: onMoveToFolder,
        onArchive: onArchive,
        onDelete: onDelete,
        onEnterSelectionMode: onEnterSelectionMode,
      ),
    );
  }
}

class SavedMessageActionsSheet extends StatelessWidget {
  const SavedMessageActionsSheet({
    super.key,
    required this.saved,
    required this.onCopy,
    required this.onMoveToFolder,
    required this.onArchive,
    required this.onDelete,
    this.onEnterSelectionMode,
  });

  final SavedMessage saved;
  final VoidCallback onCopy;
  final VoidCallback onMoveToFolder;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback? onEnterSelectionMode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            child: Text(
              saved.content.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.4,
                color: isDark
                    ? AppColors.darkPrimaryText
                    : AppColors.lightPrimaryText,
              ),
            ),
          ),
          ActionSheetGroup(
            children: [
              ActionSheetTile(
                key: const ValueKey('saved_action_copy'),
                icon: HugeIcons.strokeRoundedCopy01,
                label: l10n.copy,
                onTap: () => run(onCopy),
              ),
              ActionSheetTile(
                key: const ValueKey('saved_action_move'),
                icon: HugeIcons.strokeRoundedFolder01,
                label: l10n.move_to_folder,
                onTap: () => run(onMoveToFolder),
              ),
              if (onEnterSelectionMode != null)
                ActionSheetTile(
                  key: const ValueKey('saved_action_select'),
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
                key: const ValueKey('saved_action_archive'),
                icon: HugeIcons.strokeRoundedArchive,
                label: saved.isArchived
                    ? l10n.unarchive_chat
                    : l10n.archive_chat,
                onTap: () => run(onArchive),
              ),
              ActionSheetTile(
                key: const ValueKey('saved_action_delete'),
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
