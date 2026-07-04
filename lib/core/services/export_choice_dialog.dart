import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import 'share_service.dart';

enum _ExportChoice { clipboard, share }

/// Prompts the user to choose between copying [content] to the clipboard
/// or sharing it to another app, instead of committing to one path.
Future<void> showExportChoiceDialog(
  BuildContext context, {
  required String content,
  String? subject,
}) async {
  final l10n = AppLocalizations.of(context)!;

  final choice = await showDialog<_ExportChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.export_choice_title),
      content: Text(l10n.export_choice_body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, _ExportChoice.clipboard),
          child: Text(l10n.copy_to_clipboard),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, _ExportChoice.share),
          child: Text(l10n.share),
        ),
      ],
    ),
  );

  if (choice == null) return;

  if (choice == _ExportChoice.clipboard) {
    await Clipboard.setData(ClipboardData(text: content));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.copied_to_clipboard)),
      );
    }
  } else {
    await ShareService.shareText(content, subject: subject);
  }
}
