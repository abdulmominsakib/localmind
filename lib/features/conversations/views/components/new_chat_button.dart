import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';

class NewChatButton extends ConsumerWidget {
  const NewChatButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () {
            ref.read(chatProvider.notifier).startNewConversation();
            context.go(AppRoutes.home);
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New Chat'),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDark
                ? const Color(0xFF3B82F6)
                : const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}
