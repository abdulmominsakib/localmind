import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../providers/saved_message_providers.dart';

Future<void> showSavedMessageMoveToFolderSheet(
  BuildContext context,
  WidgetRef ref,
  String savedMessageId,
) {
  return showSavedMessagesBulkMoveToFolderSheet(context, ref, {savedMessageId});
}

Future<void> showSavedMessagesBulkMoveToFolderSheet(
  BuildContext context,
  WidgetRef ref,
  Set<String> savedMessageIds,
) async {
  final l10n = AppLocalizations.of(context)!;
  final folders = ref.read(savedMessageFoldersProvider).value ?? [];

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
                for (final id in savedMessageIds) {
                  await ref
                      .read(savedMessagesProvider.notifier)
                      .moveToFolder(id, null);
                }
              },
            ),
            ...folders.map(
              (folder) => ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.name),
                onTap: () async {
                  Navigator.pop(ctx);
                  for (final id in savedMessageIds) {
                    await ref
                        .read(savedMessagesProvider.notifier)
                        .moveToFolder(id, folder.id);
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
