import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/views/components/message_actions_sheet.dart';
import 'package:localmind/features/chat/views/components/message_variant_navigator.dart';
import 'markdown/themed_gpt_markdown.dart';
import 'attachment_list.dart';

class UserBubble extends StatelessWidget {
  const UserBubble({
    super.key,
    required this.message,
    this.onCopy,
    this.onDelete,
    this.onEdit,
    this.onBranch,
    this.onCycleVariant,
    this.onSave,
    this.onShare,
    this.allMessages = const [],
  });

  final Message message;
  final List<Message> allMessages;
  final VoidCallback? onCopy;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onBranch;
  final void Function(int direction)? onCycleVariant;
  final void Function(Message message)? onSave;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final double maxBubbleWidth = 768;
    final double availableWidth = MediaQuery.of(context).size.width * 0.75;
    final actions = MessageActions(
      content: message.content,
      messageId: message.id,
      conversationId: message.conversationId,
      createdAt: message.createdAt,
      tokenCount: message.tokenCount,
      onCopy: onCopy,
      onDelete: onDelete,
      onEdit: onEdit,
      onBranch: onBranch,
      onSave: onSave == null ? null : () => onSave!(message),
      onShare: onShare,
    );
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Long-press opens every action for this message; the bubble has
          // no inline action row, so it isn't wrapped in a SelectionArea
          // (whose long-press would select text instead). Copy is in the
          // sheet.
          GestureDetector(
            key: ValueKey('user_bubble_${message.id}'),
            onLongPress: () => showMessageActionsSheet(context, actions),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: maxBubbleWidth < availableWidth
                    ? maxBubbleWidth
                    : availableWidth,
              ),
              margin: const EdgeInsetsDirectional.only(
                start: 48,
                end: 8,
                top: 4,
                bottom: 2,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceCard
                    : AppColors.lightSurface,
                borderRadius: BorderRadiusDirectional.only(
                  topStart: Radius.circular(18),
                  topEnd: Radius.circular(18),
                  bottomStart: Radius.circular(18),
                  bottomEnd: const Radius.circular(4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (message.attachmentPaths != null &&
                      message.attachmentPaths!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AttachmentList(
                        paths: message.attachmentPaths!,
                        isUser: true,
                      ),
                    ),
                  ThemedGptMarkdown(
                    content: message.content,
                    isDark: isDark,
                    style: TextStyle(
                      color: isDark
                          ? AppColors.darkPrimaryText
                          : AppColors.lightPrimaryText,
                      fontSize: 16,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onCycleVariant != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: MessageVariantNavigator(
                message: message,
                allMessages: allMessages,
                onCycle: onCycleVariant!,
              ),
            ),
          if (message.status == MessageStatus.error)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12, bottom: 4),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedInformationCircle,
                size: 14,
                color: Colors.red[300],
              ),
            ),
        ],
      ),
    );
  }
}
