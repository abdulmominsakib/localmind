import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/l10n/app_localizations.dart';

import '../../../conversations/providers/conversation_providers.dart' as conv;
import '../../providers/chat_providers.dart';

/// Shown above the input while another chat's reply is still generating in
/// the background (#94). Tapping it opens that chat.
class BackgroundGenerationNotice extends ConsumerWidget {
  const BackgroundGenerationNotice({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final conversation = ref.watch(
      conv.conversationsProvider.select(
        (value) =>
            value.value?.where((c) => c.id == conversationId).firstOrNull,
      ),
    );
    final title = conversation?.title.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: conversation == null
              ? null
              : () => ref
                    .read(chatProvider.notifier)
                    .loadConversation(conversation),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title == null || title.isEmpty
                        ? l10n.background_generation_notice_untitled
                        : l10n.background_generation_notice(title),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (conversation != null)
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowRight01,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
