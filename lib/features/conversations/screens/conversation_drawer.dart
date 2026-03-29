import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../core/routes/app_routes.dart';
import '../../../features/chat/providers/chat_providers.dart';
import '../data/models/conversation.dart';
import '../providers/conversation_providers.dart';
import '../views/components/conversation_search_bar.dart';
import '../views/components/conversation_tile.dart';
import '../views/components/date_section_header.dart';

class ConversationDrawer extends ConsumerWidget {
  const ConversationDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final groupedConversations = ref.watch(groupedConversationsProvider);
    final activeConversation = ref.watch(activeConversationProvider);
    final searchQuery = ref.watch(conversationSearchProvider);

    return Drawer(
      backgroundColor: isDark
          ? const Color(0xFF0A0A0A)
          : const Color(0xFFFAFAFA),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF3B82F6)
                              : const Color(0xFF2563EB),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.psychology,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'LocalMind',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.settings,
                      color: isDark
                          ? const Color(0xFF888888)
                          : const Color(0xFF666666),
                    ),
                    onPressed: () {
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      Future.delayed(const Duration(milliseconds: 300), () {
                        navigator.pushNamed(AppRoutes.settings);
                      });
                    },
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    ref.read(chatProvider.notifier).startNewConversation();
                    context.go(AppRoutes.home);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Chat'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const ConversationSearchBar(),
            const Divider(height: 1),
            Expanded(
              child: groupedConversations.isEmpty
                  ? _buildEmptyState(context, isDark, searchQuery.isNotEmpty)
                  : _buildConversationList(
                      context,
                      ref,
                      groupedConversations,
                      activeConversation,
                      isDark,
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavButton(
                    icon: HugeIcons.strokeRoundedServerStack01,
                    label: 'Servers',
                    isDark: isDark,
                    onTap: () {
                      context.go(AppRoutes.servers);
                    },
                  ),
                  _NavButton(
                    icon: HugeIcons.strokeRoundedCompass01,
                    label: 'Personas',
                    isDark: isDark,
                    onTap: () {
                      context.go(AppRoutes.personas);
                    },
                  ),
                  _NavButton(
                    icon: HugeIcons.strokeRoundedSettings01,
                    label: 'Settings',
                    isDark: isDark,
                    onTap: () {
                      context.go(AppRoutes.settings);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark, bool isSearching) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearching ? Icons.search_off : Icons.chat_bubble_outline,
              size: 48,
              color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E5E5),
            ),
            const SizedBox(height: 16),
            Text(
              isSearching ? 'No results found' : 'No conversations yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isSearching
                  ? 'Try a different search term'
                  : 'Start a new conversation',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? const Color(0xFF888888)
                    : const Color(0xFF666666),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationList(
    BuildContext context,
    WidgetRef ref,
    Map<String, List<Conversation>> groupedConversations,
    Conversation? activeConversation,
    bool isDark,
  ) {
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
                  context.go(AppRoutes.home);
                },
                onLongPress: () {
                  _showConversationOptions(context, ref, conversation);
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

  void _showConversationOptions(
    BuildContext context,
    WidgetRef ref,
    Conversation conversation,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  conversation.isPinned
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                ),
                title: Text(conversation.isPinned ? 'Unpin' : 'Pin'),
                onTap: () {
                  Navigator.pop(context);
                  ref
                      .read(conversationsProvider.notifier)
                      .togglePin(conversation.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Rename'),
                onTap: () {
                  Navigator.pop(context);
                  _showRenameDialog(context, ref, conversation);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation(context, ref, conversation);
                },
              ),
            ],
          ),
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

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  final List<List<dynamic>> icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: icon,
              size: 20,
              color: isDark ? const Color(0xFF888888) : const Color(0xFF666666),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? const Color(0xFF888888)
                    : const Color(0xFF666666),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
