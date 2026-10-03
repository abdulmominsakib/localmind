import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/theme/colors.dart';

enum _EntryKind { item, divider, header }

/// One row in an [AnchoredMenu]: an action, a divider, or a small section
/// header.
class AnchoredMenuEntry {
  const AnchoredMenuEntry({
    required String this.value,
    required this.icon,
    required this.label,
    this.isDestructive = false,
    this.isChecked,
  }) : _kind = _EntryKind.item;

  const AnchoredMenuEntry.divider()
    : value = null,
      icon = const [],
      label = '',
      isDestructive = false,
      isChecked = null,
      _kind = _EntryKind.divider;

  const AnchoredMenuEntry.header(this.label)
    : value = null,
      icon = const [],
      isDestructive = false,
      isChecked = null,
      _kind = _EntryKind.header;

  final String? value;
  final List<List<dynamic>> icon;
  final String label;
  final bool isDestructive;

  /// Non-null for an option in a choice group; true shows a check mark.
  final bool? isChecked;
  final _EntryKind _kind;
}

const _menuWidth = 248.0;

/// Opens a menu anchored under the widget at [context] and returns the
/// chosen entry's value. It's a route, so Back closes it like any other
/// popup; it grows out of the anchor's top-right corner.
Future<String?> showAnchoredMenu(
  BuildContext context,
  List<AnchoredMenuEntry> entries,
) {
  final box = context.findRenderObject()! as RenderBox;
  final anchor = box.localToGlobal(Offset.zero) & box.size;
  HapticFeedback.selectionClick();

  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.04),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, _, _) {
      final screen = MediaQuery.sizeOf(dialogContext);
      return Stack(
        children: [
          Positioned(
            top: anchor.bottom + 2,
            right: (screen.width - anchor.right + 4).clamp(8.0, screen.width),
            child: AnchoredMenu(entries: entries),
          ),
        ],
      );
    },
    transitionBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          alignment: Alignment.topRight,
          scale: Tween(begin: 0.9, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class AnchoredMenu extends StatelessWidget {
  const AnchoredMenu({super.key, required this.entries});

  final List<AnchoredMenuEntry> entries;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    // The shadow sits on a box outside the clipped card; inside the clip it
    // would tint the menu itself.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: isDark ? AppColors.darkSurfaceCard : AppColors.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: SizedBox(
            width: _menuWidth,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in entries)
                    switch (entry._kind) {
                      _EntryKind.divider => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Divider(height: 1, thickness: 1, color: border),
                      ),
                      _EntryKind.header => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                        child: Text(
                          entry.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: muted,
                          ),
                        ),
                      ),
                      _EntryKind.item => AnchoredMenuItem(entry: entry),
                    },
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AnchoredMenuItem extends StatelessWidget {
  const AnchoredMenuItem({super.key, required this.entry});

  final AnchoredMenuEntry entry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final destructive = isDark ? Colors.red[300]! : const Color(0xFFB91C1C);
    final primaryText = isDark
        ? AppColors.darkPrimaryText
        : AppColors.lightPrimaryText;
    final textColor = entry.isDestructive ? destructive : primaryText;
    final iconColor = entry.isDestructive
        ? destructive
        : (isDark ? AppColors.darkMutedText : AppColors.lightMutedText);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        key: ValueKey('menu_${entry.value}'),
        borderRadius: BorderRadius.circular(9),
        onTap: () => Navigator.of(context).pop(entry.value),
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                HugeIcon(icon: entry.icon, size: 18, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: textColor),
                  ),
                ),
                if (entry.isChecked ?? false)
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedTick02,
                    size: 18,
                    color: primaryText,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
