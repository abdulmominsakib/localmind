import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/core/components/anchored_menu.dart';
import 'package:localmind/core/theme/colors.dart';
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
    final listFilter = ref.watch(historyListFilterProvider);

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: 8,
                right: 8,
                top: topPadding + 4,
                bottom: 4,
              ),
              child: selectionMode
                  ? Row(
                      children: [
                        IconButton(
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedCancel01,
                          ),
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
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedFolder01,
                          ),
                          tooltip: l10n.move_to_folder,
                          onPressed: selectedIds.isEmpty
                              ? null
                              : () => showBulkMoveToFolderSheet(
                                  context,
                                  ref,
                                  selectedIds,
                                ),
                        ),
                        IconButton(
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedShare01,
                          ),
                          tooltip: l10n.export_conversation,
                          onPressed: selectedIds.isEmpty
                              ? null
                              : () => runBulkExportConversations(
                                  context,
                                  ref,
                                  selectedIds,
                                ),
                        ),
                        IconButton(
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedSparkles,
                          ),
                          tooltip: l10n.ai_rename_tooltip,
                          onPressed: selectedIds.isEmpty
                              ? null
                              : () async {
                                  final ids = selectedIds.toList();
                                  ref
                                      .read(
                                        historySelectionModeProvider.notifier,
                                      )
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
                            icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedMenu01,
                            ),
                            onPressed: () =>
                                Scaffold.maybeOf(context)?.openDrawer(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.chat_history_title,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.darkPrimaryText
                                : AppColors.lightPrimaryText,
                          ),
                        ),
                        const Spacer(),
                        const ChatHistoryMenuButton(),
                      ],
                    ),
            ),

            const ConversationSearchBar(),
            const ConversationFolderBar(),
            if (messageSearchHits.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (MediaQuery.sizeOf(context).height * 0.35).clamp(
                    120.0,
                    280.0,
                  ),
                ),
                child: const SingleChildScrollView(
                  child: MessageSearchResultsList(),
                ),
              ),

            Expanded(
              child: groupedConversations.when(
                data: (grouped) => grouped.isEmpty
                    ? ConversationEmptyState(
                        isSearching:
                            searchQuery.isNotEmpty ||
                            listFilter != HistoryListFilter.all,
                      )
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
            child: FloatingActionButton.extended(
              key: const ValueKey('history_new_chat'),
              tooltip: l10n.new_chat_in_folder_tooltip,
              elevation: 2,
              shape: const StadiumBorder(),
              onPressed: () {
                final folderId =
                    (currentFolder != null && currentFolder.isNotEmpty)
                    ? currentFolder
                    : null;
                ref.read(pendingNewChatFolderIdProvider.notifier).set(folderId);
                ref.read(chatProvider.notifier).startNewConversation();
                context.go(AppRoutes.home);
              },
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedAdd01,
                size: 20,
              ),
              label: Text(l10n.nav_new_chat),
            ),
          ),
      ],
    );
  }
}

/// Select, sort, filter and search-in-messages, in one menu — three
/// unlabelled icons used to share the header, one of them identical to the
/// chat-parameters icon. A dot marks a filter other than "All".
class ChatHistoryMenuButton extends ConsumerWidget {
  const ChatHistoryMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final sort = ref.watch(historySortOptionProvider);
    final filter = ref.watch(historyListFilterProvider);
    final searchContents = ref.watch(searchMessageContentsProvider);

    Future<void> open(BuildContext buttonContext) async {
      final action = await showAnchoredMenu(buttonContext, [
        AnchoredMenuEntry(
          value: 'select',
          icon: HugeIcons.strokeRoundedCheckList,
          label: l10n.select,
        ),
        AnchoredMenuEntry(
          value: 'search_contents',
          icon: HugeIcons.strokeRoundedSearchList01,
          label: l10n.search_message_contents,
          isChecked: searchContents,
        ),
        const AnchoredMenuEntry.divider(),
        AnchoredMenuEntry.header(l10n.sort_title),
        AnchoredMenuEntry(
          value: 'sort_modified',
          icon: HugeIcons.strokeRoundedClock01,
          label: l10n.sort_by_modified_date,
          isChecked: sort == HistorySortOption.modified,
        ),
        AnchoredMenuEntry(
          value: 'sort_created',
          icon: HugeIcons.strokeRoundedCalendar01,
          label: l10n.sort_by_created_date,
          isChecked: sort == HistorySortOption.created,
        ),
        const AnchoredMenuEntry.divider(),
        AnchoredMenuEntry.header(l10n.filter_title),
        AnchoredMenuEntry(
          value: 'filter_all',
          icon: HugeIcons.strokeRoundedChatting01,
          label: l10n.all_chats,
          isChecked: filter == HistoryListFilter.all,
        ),
        AnchoredMenuEntry(
          value: 'filter_pinned',
          icon: HugeIcons.strokeRoundedPin,
          label: l10n.filter_pinned,
          isChecked: filter == HistoryListFilter.pinned,
        ),
        AnchoredMenuEntry(
          value: 'filter_archived',
          icon: HugeIcons.strokeRoundedArchive,
          label: l10n.filter_archived,
          isChecked: filter == HistoryListFilter.archived,
        ),
      ]);
      switch (action) {
        case 'select':
          ref.read(historySelectionModeProvider.notifier).enable();
        case 'search_contents':
          ref.read(searchMessageContentsProvider.notifier).toggle();
        case 'sort_modified':
          ref
              .read(historySortOptionProvider.notifier)
              .setOption(HistorySortOption.modified);
        case 'sort_created':
          ref
              .read(historySortOptionProvider.notifier)
              .setOption(HistorySortOption.created);
        case 'filter_all':
          ref
              .read(historyListFilterProvider.notifier)
              .setFilter(HistoryListFilter.all);
        case 'filter_pinned':
          ref
              .read(historyListFilterProvider.notifier)
              .setFilter(HistoryListFilter.pinned);
        case 'filter_archived':
          ref
              .read(historyListFilterProvider.notifier)
              .setFilter(HistoryListFilter.archived);
      }
    }

    return Builder(
      builder: (buttonContext) => IconButton(
        key: const ValueKey('history_menu'),
        tooltip: l10n.options_tooltip,
        onPressed: () => open(buttonContext),
        icon: Badge(
          isLabelVisible: filter != HistoryListFilter.all,
          smallSize: 7,
          child: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical),
        ),
      ),
    );
  }
}
