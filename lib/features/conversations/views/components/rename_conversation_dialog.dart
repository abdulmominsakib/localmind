import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/l10n/app_localizations.dart';

import '../../../conversations/data/models/conversation.dart';
import '../../../conversations/providers/conversation_providers.dart';
import '../../../chat/providers/chat_providers.dart';

Future<void> showRenameConversationDialog(
  BuildContext context,
  WidgetRef ref, {
  required Conversation conversation,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController(text: conversation.title);
  var isGenerating = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> generateTitle() async {
            setState(() => isGenerating = true);
            try {
              final title = await ref
                  .read(chatProvider.notifier)
                  .generateTitleWithAi(conversation.id);
              if (!context.mounted) return;
              if (title != null && title.isNotEmpty) {
                controller.text = title;
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.generate_title_failed)),
                );
              }
            } finally {
              if (context.mounted) {
                setState(() => isGenerating = false);
              }
            }
          }

          return AlertDialog(
            title: Text(l10n.rename_conversation),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  enabled: !isGenerating,
                  decoration: InputDecoration(
                    hintText: l10n.enter_new_title,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: isGenerating ? null : generateTitle,
                  icon: isGenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const HugeIcon(
                          icon: HugeIcons.strokeRoundedSparkles,
                          size: 18,
                        ),
                  label: Text(
                    isGenerating
                        ? l10n.generating_title
                        : l10n.generate_title_with_ai,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isGenerating
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: isGenerating
                    ? null
                    : () {
                        final newTitle = controller.text.trim();
                        if (newTitle.isNotEmpty) {
                          ref
                              .read(conversationsProvider.notifier)
                              .renameConversation(conversation.id, newTitle);
                        }
                        Navigator.pop(dialogContext);
                      },
                child: Text(l10n.rename),
              ),
            ],
          );
        },
      );
    },
  );

  controller.dispose();
}
