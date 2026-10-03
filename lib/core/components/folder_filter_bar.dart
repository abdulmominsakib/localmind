import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/l10n/app_localizations.dart';

class FolderFilterItem {
  const FolderFilterItem({required this.id, required this.name});

  final String id;
  final String name;
}

class FolderFilterBar extends StatelessWidget {
  const FolderFilterBar({
    super.key,
    required this.folders,
    required this.selectedFolderId,
    required this.onFilterChanged,
    required this.onCreateFolder,
    this.onFolderAction,
    this.isLoading = false,
    this.showCreateFolder = true,
    this.leading,
  });

  /// Shown before the folder chips, e.g. an active list filter.
  final Widget? leading;

  /// `null` = all, `''` = unfiled, otherwise folder id.
  final List<FolderFilterItem> folders;
  final String? selectedFolderId;
  final ValueChanged<String?> onFilterChanged;
  final VoidCallback onCreateFolder;

  /// Called when the user invokes a secondary action on a folder chip
  /// (long-press on touch devices, right-click on desktop). When `null`,
  /// folder chips are not interactive for management actions.
  final void Function(FolderFilterItem folder, Offset globalPosition)?
  onFolderAction;
  final bool isLoading;
  final bool showCreateFolder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (isLoading) {
      return const SizedBox(height: 50);
    }

    // Full width so the row starts at the leading edge rather than being
    // centred by a parent Column.
    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(
          spacing: 8,
          children: [
            ?leading,
            FolderPill(
              key: const ValueKey('folder_all'),
              label: l10n.all_chats,
              selected: selectedFolderId == null,
              onTap: () => onFilterChanged(null),
            ),
            FolderPill(
              key: const ValueKey('folder_unfiled'),
              label: l10n.unfiled_chats,
              selected: selectedFolderId != null && selectedFolderId!.isEmpty,
              onTap: () => onFilterChanged(''),
            ),
            for (final folder in folders)
              _FolderActionWrapper(
                onAction: onFolderAction == null
                    ? null
                    : (globalPos) => onFolderAction!(folder, globalPos),
                child: FolderPill(
                  key: ValueKey('folder_${folder.id}'),
                  label: folder.name,
                  icon: HugeIcons.strokeRoundedFolder01,
                  selected: selectedFolderId == folder.id,
                  onTap: () => onFilterChanged(folder.id),
                ),
              ),
            if (showCreateFolder)
              FolderPill(
                key: const ValueKey('folder_create'),
                label: l10n.new_folder,
                icon: HugeIcons.strokeRoundedAdd01,
                selected: false,
                isAction: true,
                onTap: onCreateFolder,
              ),
          ],
        ),
      ),
    );
  }
}

/// A folder filter: filled when selected, outlined otherwise.
class FolderPill extends StatelessWidget {
  const FolderPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.isAction = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final List<List<dynamic>>? icon;

  /// A quieter style for the "new folder" action at the end of the row.
  final bool isAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final strong = isDark
        ? AppColors.darkPrimaryText
        : AppColors.lightPrimaryText;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final background = isDark
        ? AppColors.darkBackground
        : AppColors.lightBackground;
    final foreground = selected ? background : (isAction ? muted : strong);

    return Material(
      color: selected ? strong : Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: selected ? strong : border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(icon == null ? 14 : 10, 7, 14, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                HugeIcon(icon: icon!, size: 15, color: foreground),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps a folder chip with secondary-action gestures (long-press on touch
/// devices, right-click on desktop/web). When [onAction] is null the wrapper
/// is a no-op pass-through so callers can disable the feature cheaply.
class _FolderActionWrapper extends StatelessWidget {
  const _FolderActionWrapper({required this.child, required this.onAction});

  final Widget child;
  final void Function(Offset globalPosition)? onAction;

  @override
  Widget build(BuildContext context) {
    if (onAction == null) return child;
    return GestureDetector(
      // Translucent lets taps fall through to the FilterChip so the primary
      // selection callback still fires. Only long-press and secondary tap
      // are claimed by this detector.
      behavior: HitTestBehavior.translucent,
      // Long-press for touch: standard mobile affordance.
      onLongPressStart: (details) => onAction!(details.globalPosition),
      // Secondary (right-click) tap for desktop, web and macOS trackpad.
      onSecondaryTapDown: (details) => onAction!(details.globalPosition),
      // Tap is intentionally not intercepted — the FilterChip's own tap
      // continues to fire, so primary selection still works.
      child: child,
    );
  }
}
