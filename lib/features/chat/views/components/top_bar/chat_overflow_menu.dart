import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/theme/colors.dart';

/// One row in [ChatOverflowMenu]. A null [value] makes it a divider.
class ChatMenuEntry {
  const ChatMenuEntry({
    required this.value,
    required this.icon,
    required this.label,
    this.isDestructive = false,
  });

  const ChatMenuEntry.divider()
    : value = null,
      icon = const [],
      label = '',
      isDestructive = false;

  final String? value;
  final List<List<dynamic>> icon;
  final String label;
  final bool isDestructive;
}

const _menuWidth = 248.0;

/// Opens the chat overflow menu anchored under the widget at [context], and
/// returns the chosen entry's value. It's a route, so Back closes it like
/// any other popup; it grows out of the button's corner.
Future<String?> showChatOverflowMenu(
  BuildContext context,
  List<ChatMenuEntry> entries,
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
            child: ChatOverflowMenu(entries: entries),
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

class ChatOverflowMenu extends StatelessWidget {
  const ChatOverflowMenu({super.key, required this.entries});

  final List<ChatMenuEntry> entries;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;

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
        child: SizedBox(
          width: _menuWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in entries)
                  if (entry.value == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Divider(height: 1, thickness: 1, color: border),
                    )
                  else
                    ChatMenuItem(entry: entry),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChatMenuItem extends StatelessWidget {
  const ChatMenuItem({super.key, required this.entry});

  final ChatMenuEntry entry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final destructive = isDark ? Colors.red[300]! : const Color(0xFFB91C1C);
    final textColor = entry.isDestructive
        ? destructive
        : (isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText);
    final iconColor = entry.isDestructive
        ? destructive
        : (isDark ? AppColors.darkMutedText : AppColors.lightMutedText);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        key: ValueKey('chat_menu_${entry.value}'),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
