import 'package:flutter/material.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/views/components/message_action_bar.dart';
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
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: maxBubbleWidth < availableWidth ? maxBubbleWidth : availableWidth,
            ),
            margin: const EdgeInsetsDirectional.only(
              start: 48,
              end: 8,
              top: 4,
              bottom: 2,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurfaceCard : AppColors.lightSurface,
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
                SelectionArea(
                  child: ThemedGptMarkdown(
                    content: message.content,
                    isDark: isDark,
                    style: TextStyle(
                      color: isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText,
                      fontSize: 16,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
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
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12, bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkMutedText : AppColors.lightMutedText,
                  ),
                ),
                if (message.status == MessageStatus.error) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.error_outline, size: 14, color: Colors.red[200]),
                ],
                const SizedBox(width: 8),
                MessageActionBar(
                  content: message.content,
                  tokenCount: message.tokenCount,
                  messageId: message.id,
                  conversationId: message.conversationId,
                  onCopy: onCopy,
                  onDelete: onDelete,
                  onEdit: onEdit,
                  onBranch: onBranch,
                  onSave: onSave == null ? null : () => onSave!(message),
                  onShare: onShare,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
