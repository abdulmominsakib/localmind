import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart';

class SidebarSearchButton extends ConsumerWidget {
  const SidebarSearchButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: InkWell(
        onTap: () {
          if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
            Navigator.pop(context);
          }
          context.go(AppRoutes.chatHistory);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(focusHistorySearchProvider.notifier).requestFocus();
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceInput : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          child: Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedSearch01,
                size: 18,
                color: isDark
                    ? AppColors.darkMutedText
                    : AppColors.lightMutedText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Search conversations...',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppColors.darkMutedText
                        : AppColors.lightMutedText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '⌘K',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.darkMutedText
                      : AppColors.lightMutedText,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
