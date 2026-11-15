import 'package:hugeicons/hugeicons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/utils/safe_file_picker.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:localmind/core/downloads/download_providers.dart';
import 'package:localmind/core/downloads/download_task.dart';
import 'package:localmind/features/on_device/data/imported_gguf_model_repository.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/providers/foreground_download_providers.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/on_device/components/memory_stats_panel.dart';
import 'package:localmind/features/on_device/components/model_card.dart';
import 'package:url_launcher/url_launcher.dart';

enum _ImportAction { localFile, huggingFace }

class OnDeviceModelManagerScreen extends ConsumerStatefulWidget {
  const OnDeviceModelManagerScreen({super.key});

  @override
  ConsumerState<OnDeviceModelManagerScreen> createState() =>
      _OnDeviceModelManagerScreenState();
}

class _OnDeviceModelManagerScreenState
    extends ConsumerState<OnDeviceModelManagerScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      // The microtask runs on the next event loop tick — by then the State
      // may already be deactivated, so we must guard the ref access.
      if (!mounted) return;
      ref.read(importedGgufModelsProvider.notifier).pruneMissing();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final models = ref.watch(onDeviceModelsProvider);
    final downloadedAsync = ref.watch(downloadedModelsProvider);
    final engineState = ref.watch(onDeviceEngineProvider);
    final downloadProgress = ref.watch(foregroundDownloadNotifierProvider);
    final importTasks = ref.watch(downloadTasksProvider);

    final importedModels = models.where((model) => model.isImported).toList()
      ..sort(
        (a, b) => (b.importedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.importedAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
    final curatedModels = models.where((model) => !model.isImported).toList();

    return Column(
      children: [
        _ManagerHeader(
          l10n: l10n,
          theme: theme,
          onImportLocalGguf: () => _importLocalGguf(context),
          onImportFromHuggingFace: () => _importFromHuggingFace(context),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const MemoryStatsPanel(),
              if (importTasks.isNotEmpty)
                _DownloadTasksSection(tasks: importTasks),
              _ImportOverviewCard(
                importedModels: importedModels,
                onImportLocalGguf: () => _importLocalGguf(context),
                onImportFromHuggingFace: () => _importFromHuggingFace(context),
              ),
              _EngineStatusCard(
                engineState: engineState,
                models: models,
                l10n: l10n,
                theme: theme,
              ),
              const SizedBox(height: 4),
              _SectionHeader(
                title: l10n.gguf_imported_models_title,
                subtitle: importedModels.isEmpty
                    ? l10n.gguf_imported_models_empty_subtitle
                    : '${importedModels.length} ${l10n.gguf_imported_models_ready}',
              ),
              if (importedModels.isEmpty)
                _EmptyImportedModelsCard(
                  onImportLocalGguf: () => _importLocalGguf(context),
                  onImportFromHuggingFace: () =>
                      _importFromHuggingFace(context),
                )
              else
                ...importedModels.map(
                  (model) => ModelCard(
                    model: model,
                    downloadedAsync: downloadedAsync,
                    downloadProgress: downloadProgress[model.id],
                    engineState: engineState,
                  ),
                ),
              const SizedBox(height: 8),
              _SectionHeader(
                title: l10n.available_models,
                subtitle: l10n.gguf_curated_models_subtitle,
              ),
              const SizedBox(height: 4),
              ...curatedModels.map(
                (model) => ModelCard(
                  model: model,
                  downloadedAsync: downloadedAsync,
                  downloadProgress: downloadProgress[model.id],
                  engineState: engineState,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _importLocalGguf(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context)!;
    try {
      final result = await SafeFilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['gguf'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;

      final paths = result.files
          .map((f) => f.path)
          .whereType<String>()
          .where((p) => p.toLowerCase().endsWith('.gguf'))
          .toList();

      if (paths.isEmpty) {
        if (!mounted) return;
        messenger?.showSnackBar(
          SnackBar(content: Text(l10n.gguf_only_supported)),
        );
        return;
      }

      if (paths.length == 1) {
        final path = paths.single;
        if (ImportedGgufModelRepository.isProjectorFileName(p.basename(path))) {
          if (!mounted) return;
          messenger?.showSnackBar(
            SnackBar(content: Text(l10n.gguf_is_projector_file)),
          );
          return;
        }

        final model = await ref
            .read(importedGgufModelsProvider.notifier)
            .importModel(path);
        if (!mounted) return;
        final msg = model.hasProjector
            ? '${model.name} ${l10n.gguf_imported_from_local_file} (${l10n.gguf_projector_auto_detected(model.projectorFileName ?? "")})'
            : '${model.name} ${l10n.gguf_imported_from_local_file}';
        messenger?.showSnackBar(SnackBar(content: Text(msg)));
      } else {
        final models = await ref
            .read(importedGgufModelsProvider.notifier)
            .importModels(paths);
        if (!mounted) return;
        final names = models.map((m) => m.name).join(', ');
        messenger?.showSnackBar(
          SnackBar(
            content: Text('$names ${l10n.gguf_imported_from_local_file}'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.gguf_import_failed}: ${_friendlyErrorForL10n(l10n, e)}',
          ),
        ),
      );
    }
  }

  Future<void> _importFromHuggingFace(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context)!;
    final importedModel = await showDialog<OnDeviceModel>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _HuggingFaceGgufImportDialog(),
    );

    if (!mounted || importedModel == null) return;
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          '${importedModel.name} ${l10n.gguf_imported_from_huggingface}',
        ),
      ),
    );
  }

  String _friendlyErrorForL10n(AppLocalizations l10n, Object error) {
    if (SafeFilePicker.isExplorerNotFoundError(error)) {
      return l10n.file_explorer_not_found;
    }
    final message = error.toString();
    final normalized = message
        .replaceFirst('HttpException: ', '')
        .replaceFirst('FormatException: ', '')
        .replaceFirst('FileSystemException: ', '')
        .replaceFirst('PlatformException: ', '');

    switch (normalized) {
      case 'GGUF import canceled.':
        return l10n.gguf_import_canceled;
      case 'Enter a Hugging Face GGUF URL.':
        return l10n.gguf_enter_huggingface_url;
      case 'Only official Hugging Face GGUF URLs are supported.':
        return l10n.gguf_only_official_huggingface_urls;
      case 'Use an HTTPS Hugging Face URL for GGUF import.':
        return l10n.gguf_use_https_url;
      case 'The Hugging Face URL must point directly to a .gguf file.':
        return l10n.gguf_url_must_point_to_file;
      case 'Unable to determine the GGUF file name.':
        return l10n.gguf_unable_to_detect_file_name;
      case 'The downloaded GGUF file was empty or missing.':
        return l10n.gguf_download_empty;
      case 'Selected model file does not exist':
        return l10n.gguf_selected_file_missing;
      default:
        return SafeFilePicker.getErrorMessage(
          error,
          l10n,
          fallbackMessage: normalized,
        );
    }
  }
}

class _ManagerHeader extends StatelessWidget {
  const _ManagerHeader({
    required this.l10n,
    required this.theme,
    required this.onImportLocalGguf,
    required this.onImportFromHuggingFace,
  });

  final AppLocalizations l10n;
  final ThemeData theme;
  final VoidCallback onImportLocalGguf;
  final VoidCallback onImportFromHuggingFace;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: topPadding + 8,
        bottom: 16,
      ),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF0A0A0A)
            : const Color(0xFFFAFAFA),
        border: Border(
          bottom: BorderSide(
            color: theme.brightness == Brightness.dark
                ? const Color(0xFF2A2A2A)
                : const Color(0xFFE5E5E5),
          ),
        ),
      ),
      child: Row(
        children: [
          Builder(
            builder: (context) => IconButton(
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedMenu01),
              onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.on_device_models_title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: theme.brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
            ),
          ),
          if (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)
            PopupMenuButton<_ImportAction>(
              tooltip: l10n.gguf_import_action,
              onSelected: (value) {
                switch (value) {
                  case _ImportAction.localFile:
                    onImportLocalGguf();
                  case _ImportAction.huggingFace:
                    onImportFromHuggingFace();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<_ImportAction>(
                  value: _ImportAction.localFile,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const HugeIcon(
                      icon: HugeIcons.strokeRoundedFolder01,
                    ),
                    title: Text(l10n.gguf_import_local_title),
                    subtitle: Text(l10n.gguf_import_local_subtitle),
                  ),
                ),
                PopupMenuItem<_ImportAction>(
                  value: _ImportAction.huggingFace,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCloudDownload,
                    ),
                    title: Text(l10n.gguf_import_huggingface_title),
                    subtitle: Text(l10n.gguf_import_huggingface_subtitle),
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedAddCircle,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(l10n.gguf_import_action),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImportOverviewCard extends StatelessWidget {
  const _ImportOverviewCard({
    required this.importedModels,
    required this.onImportLocalGguf,
    required this.onImportFromHuggingFace,
  });

  final List<OnDeviceModel> importedModels;
  final VoidCallback onImportLocalGguf;
  final VoidCallback onImportFromHuggingFace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final localImports = importedModels
        .where((model) => model.isImportedFromLocalFile)
        .length;
    final huggingFaceImports = importedModels
        .where((model) => model.isImportedFromHuggingFace)
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedCpu,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.gguf_overview_title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.gguf_overview_subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryPill(
                icon: HugeIcons.strokeRoundedLayers01,
                label:
                    '${importedModels.length} ${l10n.gguf_imported_count_label}',
              ),
              _SummaryPill(
                icon: HugeIcons.strokeRoundedFolder01,
                label: '$localImports ${l10n.gguf_local_files_label}',
              ),
              _SummaryPill(
                icon: HugeIcons.strokeRoundedCloudDownload,
                label: '$huggingFaceImports ${l10n.gguf_huggingface_label}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onImportLocalGguf,
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedFolder01),
                label: Text(l10n.gguf_import_local_title),
              ),
              OutlinedButton.icon(
                onPressed: onImportFromHuggingFace,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedCloudDownload,
                ),
                label: Text(l10n.gguf_import_huggingface_title),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.icon, required this.label});

  final List<List<dynamic>> icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(icon: icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyImportedModelsCard extends StatelessWidget {
  const _EmptyImportedModelsCard({
    required this.onImportLocalGguf,
    required this.onImportFromHuggingFace,
  });

  final VoidCallback onImportLocalGguf;
  final VoidCallback onImportFromHuggingFace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.gguf_no_imported_title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.gguf_no_imported_subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onImportLocalGguf,
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedFolder01),
                label: Text(l10n.gguf_import_local_title),
              ),
              OutlinedButton.icon(
                onPressed: onImportFromHuggingFace,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedCloudDownload,
                ),
                label: Text(l10n.gguf_import_huggingface_title),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


/// Live download-engine task list shown on the model manager screen.
class _DownloadTasksSection extends ConsumerWidget {
  const _DownloadTasksSection({required this.tasks});

  final List<DownloadTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: l10n.download_tasks_title,
          subtitle: l10n.download_tasks_subtitle,
        ),
        const SizedBox(height: 4),
        ...tasks.map((task) => _DownloadTaskCard(task: task, ref: ref)),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _DownloadTaskCard extends ConsumerWidget {
  const _DownloadTaskCard({required this.task, required this.ref});

  final DownloadTask task;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fileName = p.basename(task.finalPath);
    final progress =
        (task.totalBytes > 0 && task.receivedBytes <= task.totalBytes)
            ? task.receivedBytes / task.totalBytes
            : null;
    final stateLabel = switch (task.state) {
      DownloadTaskState.queued => l10n.download_state_queued,
      DownloadTaskState.running => l10n.download_state_running,
      DownloadTaskState.paused => l10n.download_state_paused,
      DownloadTaskState.failed => l10n.download_state_failed,
      DownloadTaskState.completed => l10n.download_state_completed,
      DownloadTaskState.canceled => l10n.download_state_canceled,
    };

    final actions = <Widget>[];
    switch (task.state) {
      case DownloadTaskState.running:
        actions.add(_TaskAction(
          icon: HugeIcons.strokeRoundedPause,
          tooltip: l10n.download_action_pause,
          onPressed: () =>
              ref.read(downloadEngineProvider).pause(task.id),
        ));
        actions.add(_TaskAction(
          icon: HugeIcons.strokeRoundedCancel01,
          tooltip: l10n.download_action_cancel,
          onPressed: () =>
              ref.read(downloadEngineProvider).cancel(task.id),
        ));
      case DownloadTaskState.paused:
      case DownloadTaskState.canceled:
        actions.add(_TaskAction(
          icon: HugeIcons.strokeRoundedPlay,
          tooltip: l10n.download_action_resume,
          onPressed: () =>
              ref.read(downloadEngineProvider).resume(task.id),
        ));
        actions.add(_TaskAction(
          icon: HugeIcons.strokeRoundedDelete02,
          tooltip: l10n.download_action_delete,
          onPressed: () =>
              ref.read(downloadEngineProvider).delete(task.id),
        ));
      case DownloadTaskState.failed:
        actions.add(_TaskAction(
          icon: HugeIcons.strokeRoundedRefresh,
          tooltip: l10n.download_action_retry,
          onPressed: () =>
              ref.read(downloadEngineProvider).retry(task.id),
        ));
        actions.add(_TaskAction(
          icon: HugeIcons.strokeRoundedDelete02,
          tooltip: l10n.download_action_delete,
          onPressed: () =>
              ref.read(downloadEngineProvider).delete(task.id),
        ));
      case DownloadTaskState.queued:
        actions.add(_TaskAction(
          icon: HugeIcons.strokeRoundedCancel01,
          tooltip: l10n.download_action_cancel,
          onPressed: () =>
              ref.read(downloadEngineProvider).cancel(task.id),
        ));
      case DownloadTaskState.completed:
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: task.state == DownloadTaskState.failed
                        ? Colors.red.withValues(alpha: 0.12)
                        : theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    stateLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: task.state == DownloadTaskState.failed
                          ? Colors.red.shade700
                          : theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (task.state == DownloadTaskState.running && progress != null)
              LinearProgressIndicator(value: progress.clamp(0.0, 1.0))
            else if (task.state == DownloadTaskState.failed &&
                task.error != null)
              Text(
                task.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.red.shade700,
                ),
              )
            else
              LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${_formatDownloadBytes(task.receivedBytes)} / '
                  '${_formatDownloadBytes(task.totalBytes)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const Spacer(),
                ...actions,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskAction extends StatelessWidget {
  const _TaskAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final List<List<dynamic>> icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: HugeIcon(icon: icon, size: 20),
    );
  }
}

String _formatDownloadBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}

class _HuggingFaceGgufImportDialog extends ConsumerStatefulWidget {
  const _HuggingFaceGgufImportDialog();

  @override
  ConsumerState<_HuggingFaceGgufImportDialog> createState() =>
      _HuggingFaceGgufImportDialogState();
}

class _HuggingFaceGgufImportDialogState
    extends ConsumerState<_HuggingFaceGgufImportDialog> {
  static final Uri _huggingFaceModelsUri = Uri.parse(
    'https://huggingface.co/models?search=gguf',
  );

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _projectorUrlController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    _projectorUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final hasHuggingFaceToken = ref.watch(
      settingsProvider.select(
        (settings) => settings.huggingFaceToken?.trim().isNotEmpty == true,
      ),
    );
    final input = _urlController.text.trim();
    final preview = _ImportUrlPreview.fromInput(input);
    final dialogWidth = MediaQuery.of(context).size.width > 560
        ? 520.0
        : MediaQuery.of(context).size.width * 0.82;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedCloudDownload,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(l10n.gguf_import_huggingface_dialog_title)),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.gguf_import_huggingface_dialog_subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _urlController,
                maxLines: 2,
                minLines: 1,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (_error != null) {
                    setState(() => _error = null);
                  } else {
                    setState(() {});
                  }
                },
                onSubmitted: (_) => _startImport(),
                decoration: InputDecoration(
                  labelText: l10n.gguf_url_or_repo_path,
                  hintText:
                      'owner/repo/blob/main/model.gguf\nhttps://huggingface.co/owner/repo/resolve/main/model.gguf',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Center(
                    widthFactor: 1.0,
                    heightFactor: 1.0,
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedLink01,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pasteFromClipboard,
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedClipboard,
                      size: 18,
                    ),
                    label: Text(l10n.paste),
                  ),
                  OutlinedButton.icon(
                    onPressed: input.isEmpty ? null : _clearInput,
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCancel01,
                      size: 18,
                    ),
                    label: Text(l10n.clear_huggingface_token),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openHuggingFace(context),
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedShare01,
                      size: 18,
                    ),
                    label: Text(l10n.gguf_browse),
                  ),
                ],
              ),
              if (preview != null) ...[
                const SizedBox(height: 14),
                _ImportPreviewCard(preview: preview),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _projectorUrlController,
                maxLines: 1,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: l10n.gguf_projector_url_label,
                  hintText: l10n.gguf_projector_url_hint,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Center(
                    widthFactor: 1.0,
                    heightFactor: 1.0,
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedImage01,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HugeIcon(
                      icon: hasHuggingFaceToken
                          ? HugeIcons.strokeRoundedCheckmarkBadge01
                          : HugeIcons.strokeRoundedInformationCircle,
                      size: 18,
                      color: hasHuggingFaceToken
                          ? Colors.green
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasHuggingFaceToken
                                ? l10n.gguf_huggingface_token_ready
                                : l10n.gguf_huggingface_token_optional,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasHuggingFaceToken
                                ? l10n.gguf_huggingface_token_ready_desc
                                : l10n.gguf_huggingface_token_optional_desc,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const HugeIcon(
                        icon: HugeIcons.strokeRoundedInformationCircle,
                        color: Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ElevatedButton.icon(
          onPressed: input.isEmpty ? null : _startImport,
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedDownload01,
            size: 18,
          ),
          label: Text(l10n.gguf_import_action),
        ),
      ],
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.clipboard_empty)),
      );
      return;
    }
    setState(() {
      _urlController.text = text;
      _error = null;
    });
  }

  void _clearInput() {
    setState(() {
      _urlController.clear();
      _projectorUrlController.clear();
      _error = null;
    });
  }

  Future<void> _openHuggingFace(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final launched = await launchUrl(
        _huggingFaceModelsUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.could_not_open_huggingface,
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.could_not_open_huggingface,
            ),
          ),
        );
      }
    }
  }

  Future<void> _startImport() async {
    final l10n = AppLocalizations.of(context)!;
    final sourceUrl = _urlController.text.trim();
    if (sourceUrl.isEmpty) {
      setState(() {
        _error = AppLocalizations.of(context)!.gguf_paste_url_error;
      });
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final huggingFaceToken = ref.read(
        settingsProvider.select((settings) => settings.huggingFaceToken),
      );
      final projectorUrl = _projectorUrlController.text.trim();
      final group = await ref
          .read(importedGgufModelsProvider.notifier)
          .enqueueHuggingFaceImport(
            sourceUrl: sourceUrl,
            projectorUrl: projectorUrl.isNotEmpty ? projectorUrl : null,
            token: huggingFaceToken,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            '${group.name} ${l10n.gguf_import_queued_message}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object error) {
    final l10n = AppLocalizations.of(context)!;
    final message = error.toString();
    final normalized = message
        .replaceFirst('HttpException: ', '')
        .replaceFirst('FormatException: ', '')
        .replaceFirst('Exception: ', '')
        .replaceFirst('FileSystemException: ', '');
    switch (normalized) {
      case 'GGUF import canceled.':
        return l10n.gguf_import_canceled;
      case 'Enter a Hugging Face GGUF URL.':
        return l10n.gguf_enter_huggingface_url;
      case 'Only official Hugging Face GGUF URLs are supported.':
        return l10n.gguf_only_official_huggingface_urls;
      case 'Use an HTTPS Hugging Face URL for GGUF import.':
        return l10n.gguf_use_https_url;
      case 'The Hugging Face URL must point directly to a .gguf file.':
        return l10n.gguf_url_must_point_to_file;
      case 'Unable to determine the GGUF file name.':
        return l10n.gguf_unable_to_detect_file_name;
      case 'The downloaded GGUF file was empty or missing.':
        return l10n.gguf_download_empty;
      case 'Selected model file does not exist':
        return l10n.gguf_selected_file_missing;
      default:
        return normalized;
    }
  }

}

class _ImportPreviewCard extends StatelessWidget {
  const _ImportPreviewCard({required this.preview});

  final _ImportUrlPreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PreviewPill(
                icon: preview.isBlobLink
                    ? HugeIcons.strokeRoundedRefresh
                    : HugeIcons.strokeRoundedLink01,
                label: preview.isBlobLink
                    ? l10n.gguf_blob_link
                    : preview.inputStyleLabel,
              ),
              if (preview.fileName != null)
                _PreviewPill(
                  icon: HugeIcons.strokeRoundedFile01,
                  label: preview.fileName!,
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (preview.repoPath != null)
            _PreviewRow(
              label: l10n.gguf_repository_label,
              value: preview.repoPath!,
            ),
          if (preview.normalizedDisplay != null)
            _PreviewRow(
              label: l10n.gguf_detected_path_label,
              value: preview.normalizedDisplay!,
            ),
        ],
      ),
    );
  }
}

class _PreviewPill extends StatelessWidget {
  const _PreviewPill({required this.icon, required this.label});

  final List<List<dynamic>> icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(icon: icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportUrlPreview {
  const _ImportUrlPreview({
    required this.inputStyleLabel,
    required this.isBlobLink,
    this.repoPath,
    this.fileName,
    this.normalizedDisplay,
  });

  final String inputStyleLabel;
  final bool isBlobLink;
  final String? repoPath;
  final String? fileName;
  final String? normalizedDisplay;

  static _ImportUrlPreview? fromInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final hasScheme =
        trimmed.startsWith('https://') || trimmed.startsWith('http://');
    final displayUri = hasScheme ? Uri.tryParse(trimmed) : null;
    final pathSource = displayUri != null && displayUri.pathSegments.isNotEmpty
        ? displayUri.pathSegments
        : trimmed.split('/').where((part) => part.isNotEmpty).toList();

    if (pathSource.isEmpty) {
      return const _ImportUrlPreview(
        inputStyleLabel: 'Manual path',
        isBlobLink: false,
      );
    }

    final blobIndex = pathSource.indexOf('blob');
    final resolveIndex = pathSource.indexOf('resolve');
    final fileName =
        pathSource.isNotEmpty && pathSource.last.toLowerCase().endsWith('.gguf')
        ? pathSource.last
        : null;
    final repoPath = pathSource.length >= 2
        ? '${pathSource[0]}/${pathSource[1]}'
        : null;

    String? normalizedDisplay;
    if (blobIndex != -1) {
      final normalized = [...pathSource]..[blobIndex] = 'resolve';
      normalizedDisplay = normalized.join('/');
    } else if (resolveIndex != -1 || fileName != null) {
      normalizedDisplay = pathSource.join('/');
    }

    return _ImportUrlPreview(
      inputStyleLabel: hasScheme ? 'Direct URL' : 'Repo path',
      isBlobLink: blobIndex != -1,
      repoPath: repoPath,
      fileName: fileName,
      normalizedDisplay: normalizedDisplay,
    );
  }
}

class _EngineStatusCard extends StatelessWidget {
  const _EngineStatusCard({
    required this.engineState,
    required this.models,
    required this.l10n,
    required this.theme,
  });

  final OnDeviceEngineState engineState;
  final List<OnDeviceModel> models;
  final AppLocalizations l10n;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (engineState.status == OnDeviceEngineStatus.loaded) {
      final loadedId = engineState.loadedModelId;
      final loadedName = loadedId == null
          ? 'Unknown'
          : models.where((m) => m.id == loadedId).map((m) => m.name).followedBy(
              [loadedId],
            ).first;

      return Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green),
        ),
        child: Row(
          children: [
            const HugeIcon(
              icon: HugeIcons.strokeRoundedCpu,
              color: Colors.green,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.model_loaded(
                  loadedName,
                  engineState.backend?.name ?? 'CPU',
                ),
                style: const TextStyle(color: Colors.green),
              ),
            ),
          ],
        ),
      );
    }

    if (engineState.status == OnDeviceEngineStatus.loading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: LinearProgressIndicator(),
      );
    }

    if (engineState.status == OnDeviceEngineStatus.error) {
      return Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red),
        ),
        child: Text(
          engineState.error ?? l10n.unknown_error,
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
