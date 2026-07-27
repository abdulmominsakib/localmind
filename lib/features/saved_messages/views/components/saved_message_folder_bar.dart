import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/components/folder_filter_bar.dart';
import 'package:localmind/core/components/folder_management_dialogs.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../providers/saved_message_providers.dart';

class SavedMessageFolderBar extends ConsumerWidget {
  const SavedMessageFolderBar({super.key, this.showCreateFolder = true});

  final bool showCreateFolder;

  Future<void> _createFolder(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.create_folder),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.folder_name_hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.create),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await ref.read(savedMessageFoldersProvider.notifier).createFolder(name);
  }

  Future<void> _showFolderActions(
    BuildContext context,
    WidgetRef ref,
    FolderFilterItem folder,
    Offset tapPosition,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final relativePosition = overlay != null
        ? overlay.globalToLocal(tapPosition)
        : tapPosition;

    final action = await showMenu<_FolderAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        relativePosition.dx,
        relativePosition.dy,
        overlay != null ? overlay.size.width - relativePosition.dx : 0,
        overlay != null ? overlay.size.height - relativePosition.dy : 0,
      ),
      items: [
        PopupMenuItem(
          value: _FolderAction.rename,
          child: Row(
            children: [
              const HugeIcon(icon: HugeIcons.strokeRoundedPencilEdit02),
              const SizedBox(width: 12),
              Text(l10n.rename_folder),
            ],
          ),
        ),
        PopupMenuItem(
          value: _FolderAction.delete,
          child: Row(
            children: [
              const HugeIcon(
                icon: HugeIcons.strokeRoundedDelete01,
                color: Colors.red,
              ),
              const SizedBox(width: 12),
              Text(
                l10n.delete_folder,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      ],
    );

    if (action == null || !context.mounted) return;

    final notifier = ref.read(savedMessageFoldersProvider.notifier);
    switch (action) {
      case _FolderAction.rename:
        final newName = await showRenameFolderDialog(
          context,
          currentName: folder.name,
        );
        if (newName == null || newName == folder.name) return;
        await notifier.renameFolder(folder.id, newName);
      case _FolderAction.delete:
        final confirmed = await showDeleteFolderConfirmation(
          context,
          folderName: folder.name,
        );
        if (!confirmed) return;
        final filter = ref.read(savedMessageFolderFilterProvider);
        if (filter == folder.id) {
          ref.read(savedMessageFolderFilterProvider.notifier).setFilter(null);
        }
        await notifier.deleteFolder(folder.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(savedMessageFoldersProvider);
    final selected = ref.watch(savedMessageFolderFilterProvider);

    return foldersAsync.when(
      data: (folders) => FolderFilterBar(
        folders: folders
            .map((f) => FolderFilterItem(id: f.id, name: f.name))
            .toList(),
        selectedFolderId: selected,
        onFilterChanged: (id) =>
            ref.read(savedMessageFolderFilterProvider.notifier).setFilter(id),
        onCreateFolder: () => _createFolder(context, ref),
        showCreateFolder: showCreateFolder,
        onFolderAction: (folder, pos) =>
            _showFolderActions(context, ref, folder, pos),
      ),
      loading: () => const SizedBox(height: 44),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

enum _FolderAction { rename, delete }
