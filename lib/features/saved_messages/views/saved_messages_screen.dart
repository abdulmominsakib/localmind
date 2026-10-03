import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/core/components/active_filter_chip.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../chat/providers/chat_providers.dart';
import '../../conversations/data/models/conversation.dart';
import '../../conversations/providers/conversation_providers.dart';
import '../providers/saved_message_providers.dart';
import 'components/saved_message_folder_bar.dart';
import 'components/saved_message_folder_sheet.dart';
import 'components/saved_message_tile.dart';
import 'components/saved_messages_empty_state.dart';
import 'components/saved_messages_filters.dart';
import 'components/saved_messages_menu_button.dart';

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
    final listFilter = ref.watch(savedMessageListFilterProvider);
    final folderFilter = ref.watch(savedMessageFolderFilterProvider);

    return Column(
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
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedFolder01,
                      ),
                      tooltip: l10n.move_to_folder,
                      onPressed: selectedIds.isEmpty
                          ? null
                          : () => showSavedMessagesBulkMoveToFolderSheet(
                              context,
                              ref,
                              selectedIds,
                            ),
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
                      l10n.saved_messages_title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.darkPrimaryText
                            : AppColors.lightPrimaryText,
                      ),
                    ),
                    const Spacer(),
                    const SavedMessagesMenuButton(),
                  ],
                ),
        ),
        SavedMessageFolderBar(
          leading: listFilter == SavedMessageListFilter.all
              ? null
              : ActiveFilterChip(
                  icon: listFilter.icon,
                  label: listFilter.label(l10n),
                  clearTooltip: l10n.all_chats,
                  onClear: () => ref
                      .read(savedMessageListFilterProvider.notifier)
                      .setFilter(SavedMessageListFilter.all),
                ),
        ),
        Expanded(
          child: messagesAsync.when(
            data: (messages) {
              if (messages.isEmpty) {
                return SavedMessagesEmptyState(
                  isFiltered:
                      listFilter != SavedMessageListFilter.all ||
                      folderFilter != null,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(top: 4, bottom: 24),
                itemCount: messages.length,
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
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(
                            content: Text(
                              l10n.saved_message_temp_snap_unavailable,
                            ),
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
                      // Guard every ref access post-await — the user can pop
                      // this screen while loadConversation is running.
                      if (!context.mounted) return;
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
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
