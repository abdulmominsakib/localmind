import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/theme/colors.dart';

/// Shows a non-default list filter (e.g. "Pinned") with a one-tap clear,
/// so a filtered history doesn't look like an empty one.
class ActiveFilterChip extends StatelessWidget {
  const ActiveFilterChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onClear,
    required this.clearTooltip,
  });

  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback onClear;
  final String clearTooltip;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark
        ? AppColors.darkPrimaryText
        : AppColors.lightPrimaryText;

    return Material(
      color: isDark ? AppColors.darkSurfaceCard : const Color(0xFFEDEDEF),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('history_clear_filter'),
        onTap: onClear,
        child: Tooltip(
          message: clearTooltip,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HugeIcon(icon: icon, size: 14, color: foreground),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: 6),
                HugeIcon(
                  icon: HugeIcons.strokeRoundedCancel01,
                  size: 14,
                  color: foreground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
