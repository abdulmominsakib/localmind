import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../../chat/providers/chat_providers.dart';
import '../../data/models/conversation.dart';
import '../../providers/conversation_providers.dart';

class MessageSearchResultsList extends ConsumerWidget {
  const MessageSearchResultsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hits = ref.watch(messageSearchResultsProvider);
    if (hits.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            l10n.message_search_results,
            style: theme.textTheme.titleSmall,
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: hits.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
          itemBuilder: (context, index) {
            final hit = hits[index];
            return ListTile(
              leading: HugeIcon(
                icon: hit.role == MessageRole.user
                    ? HugeIcons.strokeRoundedUser
                    : HugeIcons.strokeRoundedRobot01,
              ),
              title: Text(
                hit.conversationTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                hit.snippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () async {
                final conversations =
                    ref.read(conversationsProvider).value ?? [];
                Conversation? conversation;
                for (final conv in conversations) {
                  if (conv.id == hit.conversationId) {
                    conversation = conv;
                    break;
                  }
                }
                if (conversation == null) return;

                ref
                    .read(scrollToMessageIdProvider.notifier)
                    .scrollTo(hit.messageId);
                await ref
                    .read(chatProvider.notifier)
                    .loadConversation(conversation);
                if (context.mounted) {
                  if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                    Navigator.pop(context);
                  }
                  context.go(AppRoutes.home);
                }
              },
            );
          },
        ),
        const Divider(height: 16),
      ],
    );
  }
}
