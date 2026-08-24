import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';

class RecentConversationItem extends ConsumerWidget {
  const RecentConversationItem({super.key, required this.conversation});

  final dynamic conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        ref.read(chatProvider.notifier).loadConversation(conversation);
      },
      child: Container(
        width: 300,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBackground : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? AppColors.darkSurfaceCard : AppColors.lightBorder,
          ),
        ),
        child: Row(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedChatting01,
              size: 18,
              color: isDark
                  ? AppColors.darkMutedText
                  : AppColors.lightMutedText,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (conversation.lastMessagePreview != null)
                    Text(
                      conversation.lastMessagePreview!,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkMutedText
                            : AppColors.lightMutedText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            HugeIcon(
              icon: Directionality.of(context) == TextDirection.rtl
                  ? HugeIcons.strokeRoundedArrowLeft01
                  : HugeIcons.strokeRoundedArrowRight01,
              size: 18,
              color: isDark
                  ? AppColors.darkMutedText
                  : AppColors.lightMutedText,
            ),
          ],
        ),
      ),
    );
  }
}
