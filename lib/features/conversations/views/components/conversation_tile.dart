import 'package:flutter/material.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.isActive,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
  });

  final Conversation conversation;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dismissible(
      key: Key(conversation.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        onDelete();
        return false;
      },
      child: Material(
        color: isActive
            ? (isDark
                  ? const Color(0xFF3B82F6).withValues(alpha: 0.2)
                  : const Color(0xFF2563EB).withValues(alpha: 0.1))
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  conversation.isPinned
                      ? Icons.push_pin
                      : Icons.chat_bubble_outline,
                  size: 20,
                  color: isActive
                      ? (isDark
                            ? const Color(0xFF3B82F6)
                            : const Color(0xFF2563EB))
                      : (isDark
                            ? const Color(0xFF888888)
                            : const Color(0xFF666666)),
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
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (conversation.lastMessagePreview != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          conversation.lastMessagePreview!,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? const Color(0xFF888888)
                                : const Color(0xFF666666),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatTimestamp(conversation.updatedAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? const Color(0xFF666666)
                        : const Color(0xFF999999),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
