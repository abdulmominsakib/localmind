import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/core/components/list_filter_button.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../providers/conversation_providers.dart';
import 'components/conversation_folder_bar.dart';
import 'components/conversation_empty_state.dart';
import 'components/conversation_list.dart';
import 'components/conversation_search_bar.dart';
import 'components/message_search_results_list.dart';

class ChatHistoryScreen extends ConsumerWidget {
  const ChatHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final groupedConversations = ref.watch(groupedConversationsProvider);
    final activeConversation = ref.watch(activeConversationProvider);
    final searchQuery = ref.watch(conversationSearchProvider);
    final messageSearchHits = ref.watch(messageSearchResultsProvider);
    final topPadding = MediaQuery.of(context).padding.top;
    final selectionMode = ref.watch(historySelectionModeProvider);
    final selectedIds = ref.watch(historySelectedIdsProvider);
    final currentFolder = ref.watch(historyFolderFilterProvider);

    return Stack(
      children: [
        Column(
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
                              .read(historySelectionModeProvider.notifier)
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
                              : () => showBulkMoveToFolderSheet(
                                  context, ref, selectedIds),
                        ),
                        IconButton(
                          icon: const Icon(Icons.ios_share),
                          tooltip: l10n.export_conversation,
                          onPressed: selectedIds.isEmpty
                              ? null
                              : () => runBulkExportConversations(
                                  context, ref, selectedIds),
                        ),
                        IconButton(
                          icon: const Icon(Icons.auto_awesome_outlined),
                          tooltip: l10n.ai_rename_tooltip,
                          onPressed: selectedIds.isEmpty
                              ? null
                              : () async {
                                  final ids = selectedIds.toList();
                                  ref
                                      .read(historySelectionModeProvider.notifier)
                                      .disable();
                                  await runBulkAiRename(context, ref, ids);
                                },
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
                          l10n.chat_history_title,
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
                              .read(historySelectionModeProvider.notifier)
                              .enable(),
                        ),
                        ListFilterButton<HistorySortOption>(
                          tooltip: l10n.sort_title,
                          icon: Icons.sort,
                          showBadgeWhenNotDefault: false,
                          selected: ref.watch(historySortOptionProvider),
                          onChanged: (option) => ref
                              .read(historySortOptionProvider.notifier)
                              .setOption(option),
                          options: [
                            ListFilterOption(
                              value: HistorySortOption.modified,
                              label: l10n.sort_by_modified_date,
                              icon: Icons.edit_calendar_outlined,
                            ),
                            ListFilterOption(
                              value: HistorySortOption.created,
                              label: l10n.sort_by_created_date,
                              icon: Icons.calendar_today_outlined,
                            ),
                          ],
                        ),
                        ListFilterButton<HistoryListFilter>(
                          tooltip: l10n.filter_title,
                          selected: ref.watch(historyListFilterProvider),
                          onChanged: (filter) => ref
                              .read(historyListFilterProvider.notifier)
                              .setFilter(filter),
                          options: [
                            ListFilterOption(
                              value: HistoryListFilter.all,
                              label: l10n.all_chats,
                              icon: Icons.view_list_rounded,
                            ),
                            ListFilterOption(
                              value: HistoryListFilter.pinned,
                              label: l10n.filter_pinned,
                              icon: Icons.push_pin_outlined,
                            ),
                            ListFilterOption(
                              value: HistoryListFilter.archived,
                              label: l10n.filter_archived,
                              icon: Icons.archive_outlined,
                            ),
                          ],
                        ),
                      ],
                    ),
            ),

            const ConversationSearchBar(),
            const ConversationFolderBar(),
            if (messageSearchHits.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (MediaQuery.sizeOf(context).height * 0.35)
                      .clamp(120.0, 280.0),
                ),
                child: const SingleChildScrollView(
                  child: MessageSearchResultsList(),
                ),
              ),

            Expanded(
              child: groupedConversations.when(
                data: (grouped) => grouped.isEmpty
                    ? ConversationEmptyState(isSearching: searchQuery.isNotEmpty)
                    : ConversationList(
                        groupedConversations: grouped,
                        activeConversation: activeConversation,
                      ),
                loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (err, stack) => Center(
                  child: Text(
                    l10n.error_with_message(err.toString()),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (!selectionMode)
          PositionedDirectional(
            bottom: 24,
            end: 24,
            child: FloatingActionButton(
              tooltip: l10n.new_chat_in_folder_tooltip,
              onPressed: () {
                final folderId = (currentFolder != null && currentFolder.isNotEmpty)
                    ? currentFolder
                    : null;
                ref
                    .read(pendingNewChatFolderIdProvider.notifier)
                    .set(folderId);
                ref.read(chatProvider.notifier).startNewConversation();
                context.go(AppRoutes.home);
              },
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }
}
