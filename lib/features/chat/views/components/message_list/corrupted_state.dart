import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'debug_row.dart';

class CorruptedChatState extends ConsumerWidget {
  const CorruptedChatState({
    super.key,
    required this.conversation,
    this.errorMessage,
    required this.onStartNewChat,
  });

  final Conversation conversation;
  final String? errorMessage;
  final VoidCallback onStartNewChat;

  void _showDebugInfo(BuildContext context, WidgetRef ref) {
    final debugL10n = AppLocalizations.of(context)!;
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: Text(debugL10n.technical_details),
        description: Text(debugL10n.debug_dialog_desc),
        actions: [
          ShadButton.outline(
            onPressed: () {
              final data =
                  '''
ID: ${conversation.id}
Title: ${conversation.title}
Expected: ${conversation.messageCount}
Error: $errorMessage
''';
              Clipboard.setData(ClipboardData(text: data));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(debugL10n.copied_to_clipboard)),
              );
            },
            child: Text(debugL10n.copy_info),
          ),
          ShadButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(debugL10n.close),
          ),
        ],
        child: Container(
          width: 400,
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DebugRow(
                label: debugL10n.conversation_id,
                value: conversation.id,
              ),
              DebugRow(
                label: debugL10n.created_at,
                value: conversation.createdAt.toIso8601String(),
              ),
              DebugRow(
                label: debugL10n.expected_messages,
                value: '${conversation.messageCount}',
              ),
              if (errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        debugL10n.last_error,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          errorMessage!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const HugeIcon(
                icon: HugeIcons.strokeRoundedClock01,
                size: 48,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.history_missing_title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.history_missing_desc,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ShadButton(
                  onPressed: onStartNewChat,
                  leading: const HugeIcon(
                    icon: HugeIcons.strokeRoundedAdd01,
                    size: 20,
                  ),
                  child: Text(l10n.start_new_chat),
                ),
                const SizedBox(width: 12),
                ShadButton.outline(
                  onPressed: () => _showDebugInfo(context, ref),
                  child: Text(l10n.technical_details),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
