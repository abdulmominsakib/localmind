import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/theme/colors.dart';

/// A rounded group of [ActionSheetTile]s with hairline separators.
class ActionSheetGroup extends StatelessWidget {
  const ActionSheetGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = isDark ? AppColors.darkBorder : const Color(0xFFE9E9EC);
    return Material(
      color: isDark ? AppColors.darkSurfaceCard : const Color(0xFFF4F4F5),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: divider),
            children[i],
          ],
        ],
      ),
    );
  }
}

class ActionSheetTile extends StatelessWidget {
  const ActionSheetTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDestructive
        ? (isDark ? Colors.red[300]! : const Color(0xFFB91C1C))
        : (isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 50,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              HugeIcon(icon: icon, size: 19, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
