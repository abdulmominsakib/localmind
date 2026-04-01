import 'package:flutter/material.dart';
import 'package:localmind/core/routes/app_routes.dart';

class ConversationDrawerHeader extends StatelessWidget {
  const ConversationDrawerHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.asset(
                  'assets/images/logo.webp',
                  width: 24,
                  height: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'LocalMind',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
          IconButton(
            icon: Icon(
              Icons.settings,
              color: isDark ? const Color(0xFF888888) : const Color(0xFF666666),
            ),
            onPressed: () {
              Navigator.pop(context); // Close drawer
              Navigator.of(context).pushNamed(AppRoutes.settings);
            },
          ),
        ],
      ),
    );
  }
}
