import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../core/utils/safe_file_picker.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/models/on_device_model.dart';
import '../../providers/on_device_providers.dart';

class ImportedModelProjectorSetting extends ConsumerStatefulWidget {
  const ImportedModelProjectorSetting({super.key, required this.model});

  final OnDeviceModel model;

  @override
  ConsumerState<ImportedModelProjectorSetting> createState() =>
      _ImportedModelProjectorSettingState();
}

class _ImportedModelProjectorSettingState
    extends ConsumerState<ImportedModelProjectorSetting> {
  bool _busy = false;

  Future<void> _attachProjector() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);

    try {
      final result = await SafeFilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['gguf'],
      );
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null || !path.toLowerCase().endsWith('.gguf')) {
        messenger?.showSnackBar(
          SnackBar(content: Text(l10n.gguf_only_supported)),
        );
        return;
      }

      setState(() => _busy = true);
      await ref
          .read(importedGgufModelsProvider.notifier)
          .attachProjector(widget.model.id, path);

      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.gguf_projector_attached)),
      );
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeProjector() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);

    setState(() => _busy = true);
    try {
      await ref
          .read(importedGgufModelsProvider.notifier)
          .removeProjector(widget.model.id);

      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.gguf_projector_removed)),
      );
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hasProjector = widget.model.hasProjector;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.25,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedImage01,
              size: 16,
              color: hasProjector
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.gguf_vision_projector,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (hasProjector && widget.model.projectorFileName != null)
                    Text(
                      widget.model.projectorFileName!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (_busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (hasProjector) ...[
              IconButton(
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedEdit02,
                  size: 16,
                ),
                tooltip: l10n.gguf_change_projector,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: _attachProjector,
              ),
              IconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedDelete02,
                  size: 16,
                  color: theme.colorScheme.error,
                ),
                tooltip: l10n.gguf_remove_projector,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: _removeProjector,
              ),
            ] else
              TextButton.icon(
                onPressed: _attachProjector,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedImageAdd01,
                  size: 14,
                ),
                label: Text(
                  l10n.gguf_attach_projector,
                  style: theme.textTheme.labelSmall,
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
