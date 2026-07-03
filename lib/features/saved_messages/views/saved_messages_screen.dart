import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/core/components/list_filter_button.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../chat/providers/chat_providers.dart';
import '../../conversations/data/models/conversation.dart';
import '../../conversations/providers/conversation_providers.dart';
import '../providers/saved_message_providers.dart';
import 'components/saved_message_folder_bar.dart';
import 'components/saved_message_folder_sheet.dart';
import 'components/saved_message_tile.dart';

class SavedMessagesScreen extends ConsumerWidget {
  const SavedMessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final messagesAsync = ref.watch(filteredSavedMessagesProvider);
    final topPadding = MediaQuery.of(context).padding.top;
    final selectionMode = ref.watch(savedMessageSelectionModeProvider);
    final selectedIds = ref.watch(savedMessageSelectedIdsProvider);

    return Column(
      children: [
        Container(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: topPadding + 8,
            bottom: 16,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? const Color(0xFF2A2A2A)
                    : const Color(0xFFE5E5E5),
              ),
            ),
          ),
          child: selectionMode
              ? Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => ref
                          .read(savedMessageSelectionModeProvider.notifier)
                          .disable(),
                    ),
                    Expanded(
                      child: Text(
                        l10n.selected_count(selectedIds.length),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.folder_outlined),
                      tooltip: l10n.move_to_folder,
                      onPressed: selectedIds.isEmpty
                          ? null
                          : () => showSavedMessagesBulkMoveToFolderSheet(
                              context, ref, selectedIds),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Builder(
                      builder: (context) => IconButton(
                        icon: const Icon(Icons.menu),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.saved_messages_title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.checklist_outlined),
                      tooltip: l10n.select,
                      onPressed: () => ref
                          .read(savedMessageSelectionModeProvider.notifier)
                          .enable(),
                    ),
                    ListFilterButton<SavedMessageListFilter>(
                      tooltip: l10n.filter_title,
                      selected: ref.watch(savedMessageListFilterProvider),
                      onChanged: (filter) => ref
                          .read(savedMessageListFilterProvider.notifier)
                          .setFilter(filter),
                      options: [
                        ListFilterOption(
                          value: SavedMessageListFilter.all,
                          label: l10n.all_chats,
                          icon: Icons.view_list_rounded,
                        ),
                        ListFilterOption(
                          value: SavedMessageListFilter.tempChats,
                          label: l10n.filter_temp_chats,
                          icon: Icons.bolt_outlined,
                        ),
                        ListFilterOption(
                          value: SavedMessageListFilter.user,
                          label: l10n.filter_user_messages,
                          icon: Icons.person_outline,
                        ),
                        ListFilterOption(
                          value: SavedMessageListFilter.assistant,
                          label: l10n.filter_assistant_messages,
                          icon: Icons.auto_awesome_outlined,
                        ),
                        ListFilterOption(
                          value: SavedMessageListFilter.archived,
                          label: l10n.filter_archived,
                          icon: Icons.archive_outlined,
                        ),
                      ],
                    ),
                  ],
                ),
        ),
        const SavedMessageFolderBar(),
        Expanded(
          child: messagesAsync.when(
            data: (messages) {
              if (messages.isEmpty) {
                return Center(
                  child: Text(
                    l10n.saved_messages_empty,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: messages.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: isDark
                      ? const Color(0xFF2A2A2A)
                      : const Color(0xFFE5E5E5),
                ),
                itemBuilder: (context, index) {
                  final saved = messages[index];
                  final role = MessageRole.values[saved.roleIndex];
                  return SavedMessageTile(
                    saved: saved,
                    isUser: role == MessageRole.user,
                    selectionMode: selectionMode,
                    isSelected: selectedIds.contains(saved.id),
                    onEnterSelectionMode: () {
                      ref
                          .read(savedMessageSelectionModeProvider.notifier)
                          .enable();
                      ref
                          .read(savedMessageSelectedIdsProvider.notifier)
                          .toggle(saved.id);
                    },
                    onTap: () async {
                      if (selectionMode) {
                        ref
                            .read(savedMessageSelectedIdsProvider.notifier)
                            .toggle(saved.id);
                        return;
                      }
                      if (saved.conversationId.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.saved_message_temp_snap_unavailable),
                          ),
                        );
                        return;
                      }
                      final conversations =
                          ref.read(conversationsProvider).value ?? [];
                      Conversation? conversation;
                      for (final conv in conversations) {
                        if (conv.id == saved.conversationId) {
                          conversation = conv;
                          break;
                        }
                      }
                      if (conversation == null) return;

                      ref
                          .read(scrollToMessageIdProvider.notifier)
                          .scrollTo(saved.sourceMessageId);
                      await ref
                          .read(chatProvider.notifier)
                          .loadConversation(conversation);
                      ref
                          .read(chatOriginProvider.notifier)
                          .set(ChatOrigin.savedMessages);
                      if (context.mounted) {
                        if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                          Navigator.pop(context);
                        }
                        context.go(AppRoutes.home);
                      }
                    },
                    onCopy: () async {
                      await Clipboard.setData(
                        ClipboardData(text: saved.content),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.copied_to_clipboard)),
                        );
                      }
                    },
                    onMoveToFolder: () => showSavedMessageMoveToFolderSheet(
                      context,
                      ref,
                      saved.id,
                    ),
                    onDelete: () => ref
                        .read(savedMessagesProvider.notifier)
                        .deleteSavedMessage(saved.id),
                    onArchive: () => ref
                        .read(savedMessagesProvider.notifier)
                        .setArchived(saved.id, !saved.isArchived),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text(err.toString())),
          ),
        ),
      ],
    );
  }
}
