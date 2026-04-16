import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/routes/app_routes.dart';
import '../../chat/providers/chat_providers.dart';

class ConversationDrawerHeader extends ConsumerWidget {
  const ConversationDrawerHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
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
          ShadIconButton.outline(
            icon: const Icon(LucideIcons.plus, size: 20),
            onPressed: () {
              ref.read(chatProvider.notifier).startNewConversation();
              context.go(AppRoutes.home);
              if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }
}
