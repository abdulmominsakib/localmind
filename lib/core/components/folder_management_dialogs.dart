import 'package:flutter/material.dart';
import 'package:localmind/l10n/app_localizations.dart';

/// Generic helpers used by both chat-history folders and saved-message folders
/// to rename or delete a folder. The caller is responsible for invoking the
/// underlying repository method on confirmation.

/// Shows a dialog asking the user to enter a new folder name. Returns the
/// trimmed new name, or `null` if cancelled. Rejects empty names.
Future<String?> showRenameFolderDialog(
  BuildContext context, {
  required String currentName,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController(text: currentName);
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: currentName.length,
  );
  String? errorText;

  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: Text(l10n.rename_folder),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.folder_name_hint,
                errorText: errorText,
              ),
              onSubmitted: (_) {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setState(() => errorText = l10n.folder_name_required);
                  return;
                }
                Navigator.pop(ctx, value);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.isEmpty) {
                    setState(() => errorText = l10n.folder_name_required);
                    return;
                  }
                  Navigator.pop(ctx, value);
                },
                child: Text(l10n.save),
              ),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  return result;
}

/// Shows a confirmation dialog asking the user whether they really want to
/// delete the folder. Returns `true` if confirmed, `false` (or `null`) otherwise.
Future<bool> showDeleteFolderConfirmation(
  BuildContext context, {
  required String folderName,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(l10n.delete_folder_title),
        content: Text(l10n.delete_folder_body(folderName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      );
    },
  );
  return result ?? false;
}