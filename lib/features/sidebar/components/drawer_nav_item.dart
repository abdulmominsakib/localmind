import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/theme/colors.dart';

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
  final String? badgeText;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withAlpha(30)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              HugeIcon(
                icon: iconData,
                size: 20,
                color: isSelected
                    ? accent
                    : (isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? accent
                        : (isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badgeText != null && badgeText!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badgeText!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: isSelected
                          ? accent
                          : (isDark ? AppColors.darkPrimaryText : accent),
                    ),
                  ),
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
    );
  }
}
