import 'package:flutter/material.dart';

class DateSectionHeader extends StatelessWidget {
  const DateSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0xFF666666) : const Color(0xFF999999),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
