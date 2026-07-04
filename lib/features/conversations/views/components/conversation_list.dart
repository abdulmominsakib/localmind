import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/services/data_backup_service.dart';
import 'package:localmind/core/services/export_choice_dialog.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../chat/providers/chat_providers.dart';
import '../../data/models/conversation.dart';
import '../../providers/conversation_providers.dart';
import 'rename_conversation_dialog.dart';
import 'date_section_header.dart';
import 'conversation_tile.dart';

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
    final l10n = AppLocalizations.of(context)!;
    final selectionMode = ref.watch(historySelectionModeProvider);
    final selectedIds = ref.watch(historySelectedIdsProvider);
    final sectionOrder = [
      l10n.pinned_section,
      l10n.today_section,
      l10n.yesterday_section,
      l10n.previous_7_days,
      l10n.previous_30_days,
      l10n.older_section,
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

        if (section == l10n.pinned_section && conversations.isEmpty) {
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
                selectionMode: selectionMode,
                isSelected: selectedIds.contains(conversation.id),
                onEnterSelectionMode: () {
                  ref.read(historySelectionModeProvider.notifier).enable();
                  ref
                      .read(historySelectedIdsProvider.notifier)
                      .toggle(conversation.id);
                },
                onTap: () {
                  if (selectionMode) {
                    ref
                        .read(historySelectedIdsProvider.notifier)
                        .toggle(conversation.id);
                    return;
                  }
                  ref
                      .read(chatProvider.notifier)
                      .loadConversation(conversation);
                  ref
                      .read(chatOriginProvider.notifier)
                      .set(ChatOrigin.history);
                  if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                    Navigator.pop(context);
                  }
                  context.go(AppRoutes.home);
                },
                onRename: () {
                  _showRenameDialog(context, ref, l10n, conversation);
                },
                onTogglePin: () {
                  ref
                      .read(conversationsProvider.notifier)
                      .togglePin(conversation.id);
                },
                onDelete: () {
                  _showDeleteConfirmation(context, ref, l10n, conversation);
                },
                onDuplicate: () {
                  ref
                      .read(conversationsProvider.notifier)
                      .duplicateConversation(conversation.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.duplicate_chat_success)),
                  );
                },
                onMoveToFolder: () {
                  showMoveToFolderSheet(context, ref, l10n, conversation);
                },
                onExport: () {
                  _exportConversation(context, ref, l10n, conversation);
                },
                onArchive: () {
                  ref.read(conversationsProvider.notifier).setArchived(
                        conversation.id,
                        !conversation.isArchived,
                      );
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
    AppLocalizations l10n,
    Conversation conversation,
  ) {
    showRenameConversationDialog(context, ref, conversation: conversation);
  }

  void _showDeleteConfirmation(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Conversation conversation,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.delete_conversation_title),
          content: Text(l10n.delete_conversation_body(conversation.title)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                ref
                    .read(conversationsProvider.notifier)
                    .deleteConversation(conversation.id);
                Navigator.pop(context);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportConversation(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Conversation conversation,
  ) async {
    final db = ref.read(databaseProvider);
    final json = DataBackupService()
        .exportConversationAsJson(db.store, conversation.id);
    if (!context.mounted) return;
    await showExportChoiceDialog(
      context,
      content: json,
      subject: conversation.title,
    );
  }
}

/// Shown from a single conversation's overflow menu (in history, or from
/// the chat screen itself) to move it into a folder or remove it from one.
void showMoveToFolderSheet(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  Conversation conversation,
) {
  final folders = ref.read(conversationFoldersProvider).value ?? [];

  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: Text(l10n.remove_from_folder),
              onTap: () async {
                Navigator.pop(ctx);
                await ref
                    .read(conversationsProvider.notifier)
                    .moveConversationToFolder(conversation.id, null);
              },
            ),
            ...folders.map(
              (folder) => ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.name),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref
                      .read(conversationsProvider.notifier)
                      .moveConversationToFolder(conversation.id, folder.id);
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> showBulkMoveToFolderSheet(
  BuildContext context,
  WidgetRef ref,
  Set<String> conversationIds,
) async {
  final l10n = AppLocalizations.of(context)!;
  final folders = ref.read(conversationFoldersProvider).value ?? [];

  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: Text(l10n.remove_from_folder),
              onTap: () async {
                Navigator.pop(ctx);
                for (final id in conversationIds) {
                  await ref
                      .read(conversationsProvider.notifier)
                      .moveConversationToFolder(id, null);
                }
              },
            ),
            ...folders.map(
              (folder) => ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.name),
                onTap: () async {
                  Navigator.pop(ctx);
                  for (final id in conversationIds) {
                    await ref
                        .read(conversationsProvider.notifier)
                        .moveConversationToFolder(id, folder.id);
                  }
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> runBulkExportConversations(
  BuildContext context,
  WidgetRef ref,
  Set<String> conversationIds,
) async {
  final l10n = AppLocalizations.of(context)!;
  final db = ref.read(databaseProvider);
  final json = DataBackupService()
      .exportConversationsForIdsAsJson(db.store, conversationIds);
  if (!context.mounted) return;
  await showExportChoiceDialog(
    context,
    content: json,
    subject: l10n.bulk_export_conversations_success(conversationIds.length),
  );
}

Future<void> runBulkAiRename(
  BuildContext context,
  WidgetRef ref,
  List<String> conversationIds,
) async {
  final l10n = AppLocalizations.of(context)!;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.bulk_ai_rename_confirm_title),
      content: Text(
        l10n.bulk_ai_rename_confirm_body(conversationIds.length),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.confirm),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;

  final progress = ValueNotifier<int>(0);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      content: ValueListenableBuilder<int>(
        valueListenable: progress,
        builder: (context, done, _) => Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                l10n.bulk_ai_rename_progress(done, conversationIds.length),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  for (final id in conversationIds) {
    final title = await ref.read(chatProvider.notifier).generateTitleWithAi(id);
    if (title != null && title.isNotEmpty) {
      await ref.read(conversationsProvider.notifier).renameConversation(id, title);
    }
    progress.value += 1;
  }

  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
}
