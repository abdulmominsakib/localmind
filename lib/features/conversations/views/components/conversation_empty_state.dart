import 'package:flutter/material.dart';

class ConversationEmptyState extends StatelessWidget {
  const ConversationEmptyState({
    super.key,
    required this.isSearching,
  });

  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearching ? Icons.search_off : Icons.chat_bubble_outline,
              size: 48,
              color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E5E5),
            ),
            const SizedBox(height: 16),
            Text(
              isSearching ? 'No results found' : 'No conversations yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isSearching
                  ? 'Try a different search term'
                  : 'Start a new conversation',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? const Color(0xFF888888)
                    : const Color(0xFF666666),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
