import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../chat/providers/chat_providers.dart';
import '../../data/models/conversation.dart';
import '../../providers/conversation_providers.dart';
import 'conversation_tile.dart';
import 'date_section_header.dart';

class ConversationList extends ConsumerWidget {
  const ConversationList({
    super.key,
    required this.groupedConversations,
    required this.activeConversation,
  });

  final Map<String, List<Conversation>> groupedConversations;
  final Conversation? activeConversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionOrder = [
      'PINNED',
      'TODAY',
      'YESTERDAY',
      'PREVIOUS 7 DAYS',
      'PREVIOUS 30 DAYS',
      'OLDER',
    ];
    final sortedSections = groupedConversations.keys.toList()
      ..sort((a, b) {
        final aIndex = sectionOrder.indexOf(a);
        final bIndex = sectionOrder.indexOf(b);
        return aIndex.compareTo(bIndex);
      });

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: sortedSections.length,
      itemBuilder: (context, sectionIndex) {
        final section = sortedSections[sectionIndex];
        final conversations = groupedConversations[section]!;

        if (section == 'PINNED' && conversations.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DateSectionHeader(title: section),
            ...conversations.map((conversation) {
              return ConversationTile(
                conversation: conversation,
                isActive: activeConversation?.id == conversation.id,
                onTap: () {
                  ref
                      .read(chatProvider.notifier)
                      .loadConversation(conversation);
                  if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                    Navigator.pop(context); // Close drawer if it was a drawer
                  }
                  context.go(AppRoutes.home);
                },
                onRename: () {
                  _showRenameDialog(context, ref, conversation);
                },
                onTogglePin: () {
                  ref
                      .read(conversationsProvider.notifier)
                      .togglePin(conversation.id);
                },
                onDelete: () {
                  _showDeleteConfirmation(context, ref, conversation);
                },
              );
            }),
          ],
        );
      },
    );
  }

  void _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    Conversation conversation,
  ) {
    final controller = TextEditingController(text: conversation.title);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename conversation'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter new title',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final newTitle = controller.text.trim();
                if (newTitle.isNotEmpty) {
                  ref
                      .read(conversationsProvider.notifier)
                      .renameConversation(conversation.id, newTitle);
                }
                Navigator.pop(context);
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    WidgetRef ref,
    Conversation conversation,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete conversation?'),
          content: Text(
            'Are you sure you want to delete "${conversation.title}"? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                ref
                    .read(conversationsProvider.notifier)
                    .deleteConversation(conversation.id);
                Navigator.pop(context);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}
