import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
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
  });

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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (isLoading) {
      return const SizedBox(height: 44);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          SystemFolderFilterChip(
            label: l10n.all_chats,
            icon: HugeIcons.strokeRoundedView,
            selected: selectedFolderId == null,
            isDark: isDark,
            onSelected: (_) => onFilterChanged(null),
          ),
          const SizedBox(width: 6),
          SystemFolderFilterChip(
            label: l10n.unfiled_chats,
            icon: HugeIcons.strokeRoundedInbox,
            selected: selectedFolderId != null && selectedFolderId!.isEmpty,
            isDark: isDark,
            outlined: true,
            onSelected: (_) => onFilterChanged(''),
          ),
          ...folders.map(
            (folder) => Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _FolderActionWrapper(
                onAction: onFolderAction == null
                    ? null
                    : (globalPos) => onFolderAction!(folder, globalPos),
                child: FilterChip(
                  avatar: HugeIcon(icon: 
                    HugeIcons.strokeRoundedFolder01,
                    size: 16,
                    color: selectedFolderId == folder.id
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.primary,
                  ),
                  label: Text(folder.name),
                  selected: selectedFolderId == folder.id,
                  showCheckmark: false,
                  onSelected: (_) => onFilterChanged(folder.id),
                ),
              ),
            ),
          ),
          if (showCreateFolder) ...[
            const SizedBox(width: 6),
            ActionChip(
              avatar: HugeIcon(icon: 
                HugeIcons.strokeRoundedFolderAdd,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              label: Text(l10n.new_folder),
              side: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
                style: BorderStyle.solid,
              ),
              onPressed: onCreateFolder,
            ),
          ],
        ],
      ),
    );
  }
}

class SystemFolderFilterChip extends StatelessWidget {
  const SystemFolderFilterChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.isDark,
    required this.onSelected,
    this.outlined = false,
  });

  final String label;
  final List<List<dynamic>> icon;
  final bool selected;
  final bool isDark;
  final bool outlined;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = selected
        ? (outlined
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.secondaryContainer)
        : Colors.transparent;
    final borderColor = outlined
        ? (isDark ? const Color(0xFF444444) : const Color(0xFFCCCCCC))
        : (selected
            ? theme.colorScheme.secondaryContainer
            : (isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0)));

    return FilterChip(
      avatar: HugeIcon(icon: 
        icon,
        size: 16,
        color: selected
            ? theme.colorScheme.onSecondaryContainer
            : theme.colorScheme.onSurfaceVariant,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontWeight: outlined ? FontWeight.normal : FontWeight.w600,
          fontStyle: outlined ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      selected: selected,
      showCheckmark: false,
      backgroundColor: bgColor,
      side: BorderSide(color: borderColor),
      onSelected: onSelected,
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
