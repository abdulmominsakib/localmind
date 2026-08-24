import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../providers/saved_message_providers.dart';

Future<void> showSaveMessageSheet(
  BuildContext context,
  WidgetRef ref,
  Message message, {
  bool isTemporaryChat = false,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final foldersAsync = ref.read(savedMessageFoldersProvider);
  final folders = foldersAsync.value ?? [];
  final existing = await ref
      .read(savedMessagesProvider.notifier)
      .getBySourceMessageId(message.id);
  String? selectedFolderId = existing?.folderId;

  if (!context.mounted) return;

  await showShadSheet(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) {
        return ShadSheet(
          title: Text(l10n.save_message_folders),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (existing != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    l10n.message_already_saved,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ListTile(
                leading: HugeIcon(
                  icon: selectedFolderId == null
                      ? HugeIcons.strokeRoundedCheckmarkCircle01
                      : HugeIcons.strokeRoundedCircle,
                ),
                title: Text(l10n.unfiled_chats),
                onTap: () => setState(() => selectedFolderId = null),
              ),
              ...folders.map(
                (folder) => ListTile(
                  leading: HugeIcon(
                    icon: selectedFolderId == folder.id
                        ? HugeIcons.strokeRoundedCheckmarkCircle01
                        : HugeIcons.strokeRoundedCircle,
                  ),
                  title: Text(folder.name),
                  onTap: () => setState(() => selectedFolderId = folder.id),
                ),
              ),
              const SizedBox(height: 8),
              if (existing != null)
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref
                        .read(savedMessagesProvider.notifier)
                        .removeBySourceMessageId(message.id);
                    ref.invalidate(isMessageSavedProvider(message.id));
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedBookmarkRemove01,
                  ),
                  label: Text(l10n.remove_from_saved),
                ),
              const SizedBox(height: 8),
              ShadButton(
                width: double.infinity,
                onPressed: () async {
                  await ref
                      .read(savedMessagesProvider.notifier)
                      .saveMessage(
                        message,
                        folderId: selectedFolderId,
                        isTemporaryChat: isTemporaryChat,
                      );
                  ref.invalidate(isMessageSavedProvider(message.id));
                  if (context.mounted) Navigator.pop(context);
                },
                child: Text(l10n.save),
              ),
            ],
          ),
        );
      },
    ),
  );
}
