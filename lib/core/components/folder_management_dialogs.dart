import 'package:flutter/material.dart';
import 'package:localmind/l10n/app_localizations.dart';

/// Generic helpers used by both chat-history folders and saved-message folders
/// to rename or delete a folder. The caller is responsible for invoking the
/// underlying repository method on confirmation.

/// Shows a dialog asking the user to enter a new folder name. Returns the
/// trimmed new name, or `null` if cancelled. Rejects empty names.
///
/// The controller lives inside [_RenameFolderDialog]'s state so it is only
/// disposed once the dialog element is actually unmounted — disposing it as
/// soon as `showDialog` resolves is unsafe because the exit animation keeps
/// the TextField alive (and rebuilding) for a short while.
Future<String?> showRenameFolderDialog(
  BuildContext context, {
  required String currentName,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _RenameFolderDialog(currentName: currentName),
  );
}

class _RenameFolderDialog extends StatefulWidget {
  const _RenameFolderDialog({required this.currentName});

  final String currentName;

  @override
  State<_RenameFolderDialog> createState() => _RenameFolderDialogState();
}

class _RenameFolderDialogState extends State<_RenameFolderDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.currentName.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() {
        _errorText = AppLocalizations.of(context)!.folder_name_required;
      });
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.rename_folder),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: l10n.folder_name_hint,
          errorText: _errorText,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }
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