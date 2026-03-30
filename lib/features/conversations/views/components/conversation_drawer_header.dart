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
                  color: isDark
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.psychology,
                  color: Colors.white,
                  size: 20,
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
              color: isDark
                  ? const Color(0xFF888888)
                  : const Color(0xFF666666),
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
