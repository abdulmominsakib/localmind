import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class DrawerNavItem extends StatelessWidget {
  const DrawerNavItem({
    super.key,
    required this.iconData,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final List<List<dynamic>> iconData;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        leading: HugeIcon(
          icon: iconData,
          size: 22,
          color: isSelected
              ? (isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB))
              : (isDark ? const Color(0xFF888888) : const Color(0xFF666666)),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? (isDark ? Colors.white : Colors.black)
                : (isDark ? const Color(0xFFA0A0A0) : const Color(0xFF666666)),
          ),
        ),
        selected: isSelected,
        selectedTileColor: isDark
            ? const Color(0xFF3B82F6).withAlpha(25)
            : const Color(0xFF2563EB).withAlpha(25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: onTap,
      ),
    );
  }
}
