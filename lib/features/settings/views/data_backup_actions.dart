import 'package:hugeicons/hugeicons.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:localmind/l10n/app_localizations.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/storage_providers.dart';
import '../../../core/services/data_backup_service.dart';
import '../../../core/utils/safe_file_picker.dart';
import '../../conversations/providers/conversation_providers.dart';
import '../../personas/providers/personas_providers.dart';
import '../../saved_messages/providers/saved_message_providers.dart';
import '../../servers/providers/server_providers.dart';

class DataBackupActions extends ConsumerWidget {
  const DataBackupActions({super.key});

  Future<void> _saveJsonExport(
    BuildContext context,
    String dialogTitle,
    String fileName,
    String json,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final saved = await SafeFilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
      if (saved == null) return;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.export_data_success)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final msg = SafeFilePicker.getErrorMessage(e, l10n);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              SafeFilePicker.isExplorerNotFoundError(e)
                  ? msg
                  : l10n.export_data_failed(msg),
            ),
          ),
        );
      }
    }
  }

  Future<void> _saveZipExport(
    BuildContext context,
    WidgetRef ref,
    String dialogTitle,
    String fileName,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final db = ref.read(databaseProvider);
      final settings = ref.read(settingsProvider);
      final prefs = ref.read(sharedPreferencesProvider);
      final service = DataBackupService();
      final bytes = service.exportAllZip(
        db.store,
        settings.toJson(),
        prefs: prefs,
      );
      final saved = await SafeFilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        bytes: Uint8List.fromList(bytes),
      );
      if (saved == null) return;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.export_data_success)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final msg = SafeFilePicker.getErrorMessage(e, l10n);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              SafeFilePicker.isExplorerNotFoundError(e)
                  ? msg
                  : l10n.export_data_failed(msg),
            ),
          ),
        );
      }
    }
  }

  Future<bool> _confirmImport(BuildContext context, String message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final dialogL10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.import_all_data),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dialogL10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(dialogL10n.confirm),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _importJsonFile(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(String json) importer,
    String confirmMessage,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    if (!await _confirmImport(context, confirmMessage)) return;

    try {
      final result = await SafeFilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      final path = result?.files.single.path;
      if (path == null) return;

      final json = await File(path).readAsString();
      await importer(json);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.import_data_success)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final msg = SafeFilePicker.getErrorMessage(e, l10n);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              SafeFilePicker.isExplorerNotFoundError(e)
                  ? msg
                  : l10n.import_data_failed(msg),
            ),
          ),
        );
      }
    }
  }

  Future<void> _applySettingsPayload(
    WidgetRef ref,
    Map<String, dynamic> decoded,
  ) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final settingsMap = decoded['settings'];
    if (settingsMap is Map) {
      await prefs.setString('appSettings', jsonEncode(settingsMap));
    }
    final metadata = decoded['modelMetadata'];
    if (metadata is Map) {
      await prefs.setString('modelMetadata', jsonEncode(metadata));
    }
    ref.invalidate(settingsProvider);
    ref.invalidate(serversProvider);
  }

  Future<void> _importZipFile(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    if (!await _confirmImport(context, l10n.import_data_confirm)) return;

    try {
      final result = await SafeFilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      final path = result?.files.single.path;
      if (path == null) return;

      final bytes = await File(path).readAsBytes();
      final db = ref.read(databaseProvider);
      await DataBackupService().importZip(db.store, bytes);

      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive.files) {
        if (!file.isFile || file.name != 'settings.json') continue;
        final decoded = jsonDecode(utf8.decode(file.content as List<int>))
            as Map<String, dynamic>;
        await _applySettingsPayload(ref, decoded);
      }

      // Defer invalidations until after the current build frame so widgets that
      // watch these providers (e.g. SettingsViews) don't flush them during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.invalidate(conversationsProvider);
        ref.invalidate(personasNotifierProvider);
        ref.invalidate(savedMessagesProvider);
        ref.invalidate(savedMessageFoldersProvider);
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.import_data_success)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final msg = SafeFilePicker.getErrorMessage(e, l10n);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              SafeFilePicker.isExplorerNotFoundError(e)
                  ? msg
                  : l10n.import_data_failed(msg),
            ),
          ),
        );
      }
    }
  }

  Widget _categoryRow({
    required String label,
    required VoidCallback onExport,
    required VoidCallback onImport,
    required AppLocalizations l10n,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ShadButton.outline(
            onPressed: onExport,
            child: Text(l10n.export),
          ),
          const SizedBox(width: 8),
          ShadButton.outline(
            onPressed: onImport,
            child: Text(l10n.import),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final service = DataBackupService();
    final db = ref.watch(databaseProvider);
    final prefs = ref.watch(sharedPreferencesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _categoryRow(
          label: l10n.conversations_label,
          l10n: l10n,
          onExport: () => _saveJsonExport(
            context,
            l10n.export_conversations,
            'localmind_conversations_${DateTime.now().millisecondsSinceEpoch}.json',
            service.exportConversationsAsJson(db.store),
          ),
          onImport: () => _importJsonFile(
            context,
            ref,
            (json) async {
              await service.importFromJson(db.store, json);
              ref.invalidate(conversationsProvider);
              ref.invalidate(savedMessagesProvider);
            },
            l10n.import_data_confirm,
          ),
        ),
        _categoryRow(
          label: l10n.personas_label,
          l10n: l10n,
          onExport: () => _saveJsonExport(
            context,
            l10n.export_personas,
            'localmind_personas_${DateTime.now().millisecondsSinceEpoch}.json',
            service.exportPersonasAsJson(db.store),
          ),
          onImport: () => _importJsonFile(
            context,
            ref,
            (json) async {
              await service.importFromJson(db.store, json);
              ref.invalidate(personasNotifierProvider);
            },
            l10n.import_data_confirm,
          ),
        ),
        _categoryRow(
          label: l10n.settings_label,
          l10n: l10n,
          onExport: () => _saveJsonExport(
            context,
            l10n.export_settings,
            'localmind_settings_${DateTime.now().millisecondsSinceEpoch}.json',
            service.exportSettingsAsJson(
              ref.read(settingsProvider).toJson(),
              store: db.store,
              prefs: prefs,
            ),
          ),
          onImport: () => _importJsonFile(
            context,
            ref,
            (json) async {
              final decoded = jsonDecode(json) as Map<String, dynamic>;
              await service.importFromJson(db.store, json);
              await _applySettingsPayload(ref, decoded);
            },
            l10n.import_settings_confirm,
          ),
        ),
        const SizedBox(height: 8),
        ShadButton.outline(
          onPressed: () => _saveZipExport(
            context,
            ref,
            l10n.export_all_zip,
            'localmind_backup_${DateTime.now().millisecondsSinceEpoch}.zip',
          ),
          width: double.infinity,
          leading: const HugeIcon(icon: HugeIcons.strokeRoundedFolder01, size: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(l10n.export_all_zip),
          ),
        ),
        const SizedBox(height: 8),
        ShadButton.outline(
          onPressed: () => _importZipFile(context, ref),
          width: double.infinity,
          leading: const HugeIcon(icon: HugeIcons.strokeRoundedArchive, size: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(l10n.import_all_zip),
          ),
        ),
      ],
    );
  }
}