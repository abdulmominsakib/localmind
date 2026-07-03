import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
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
    final mutedColor =
        isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    return Dismissible(
      key: Key(saved.id),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsetsDirectional.only(start: 16),
        color: Colors.blue,
        child: Icon(
          saved.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
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
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showContextMenu(context, l10n, isDark),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectionMode)
                Checkbox(value: isSelected, onChanged: (_) => onTap())
              else
                Icon(
                  isUser
                      ? Icons.person_outline
                      : Icons.auto_awesome_outlined,
                  size: 20,
                  color: mutedColor,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isFromTempChat)
                      Text(
                        l10n.temporary_chat,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          fontStyle: FontStyle.italic,
                          color: mutedColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else if (saved.conversationTitle.isNotEmpty)
                      Text(
                        saved.conversationTitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkPrimaryText
                              : AppColors.lightPrimaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (isFromTempChat || saved.conversationTitle.isNotEmpty)
                      const SizedBox(height: 2),
                    Text(
                      saved.content,
                      style: TextStyle(
                        fontSize: 13,
                        color: mutedColor,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => _showContextMenu(context, l10n, isDark),
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedMoreVertical,
                  size: 18,
                  color: mutedColor,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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

  void _showContextMenu(
    BuildContext context,
    AppLocalizations l10n,
    bool isDark,
  ) {
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
                leading: const Icon(Icons.copy_outlined),
                title: Text(l10n.copy),
                onTap: () {
                  Navigator.pop(ctx);
                  onCopy();
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
                leading: Icon(
                  saved.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                title: Text(
                  saved.isArchived ? l10n.unarchive_chat : l10n.archive_chat,
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
