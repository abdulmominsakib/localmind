import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/theme/colors.dart';

/// One compact menu row: icon, label, and an optional count or widget at
/// the end. The current page sits on a soft grey fill.
class DrawerNavItem extends StatelessWidget {
  const DrawerNavItem({
    super.key,
    required this.iconData,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badgeText,
    this.trailing,
  });

  final List<List<dynamic>> iconData;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  /// A short count or status shown in muted text at the end of the row.
  final String? badgeText;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;
    final selectedFill = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: isSelected ? selectedFill : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 42,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  HugeIcon(icon: iconData, size: 20, color: fg),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: fg,
                      ),
                    ),
                  ),
                  if (badgeText != null && badgeText!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      badgeText!,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ],
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small muted heading over a group of menu rows.
class DrawerSectionLabel extends StatelessWidget {
  const DrawerSectionLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.darkMutedText : AppColors.lightMutedText,
        ),
      ),
    );
  }
}
