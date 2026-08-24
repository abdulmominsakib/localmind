import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../providers/saved_message_providers.dart';
import 'saved_message_folder_bar.dart';
import 'saved_message_picker_tile.dart';

Future<String?> showSavedMessagePickerSheet(BuildContext context) async {
  return showShadSheet<String>(
    context: context,
    builder: (ctx) => const _SavedMessagePickerSheet(),
  );
}

class _SavedMessagePickerSheet extends ConsumerWidget {
  const _SavedMessagePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final messagesAsync = ref.watch(filteredSavedMessagesProvider);

    return ShadSheet(
      title: Text(l10n.insert_saved_message),
      description: Text(l10n.insert_saved_message_desc),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SavedMessageFolderBar(showCreateFolder: false),
            Expanded(
              child: messagesAsync.when(
                data: (messages) {
                  if (messages.isEmpty) {
                    return Center(child: Text(l10n.saved_messages_empty));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: messages.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: isDark
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFFE5E5E5),
                    ),
                    itemBuilder: (context, index) {
                      final saved = messages[index];
                      return SavedMessagePickerTile(
                        saved: saved,
                        onTap: () => Navigator.pop(context, saved.content),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(e.toString())),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
