import 'package:hugeicons/hugeicons.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:localmind/core/device/device_memory_service.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/data/models/download_progress_info.dart';
import 'package:localmind/features/on_device/data/models/download_status.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/on_device/providers/foreground_download_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:localmind/features/models/components/ram_warning_dialog.dart';

class ModelCard extends ConsumerWidget {
  const ModelCard({
    super.key,
    required this.model,
    required this.downloadedAsync,
    required this.downloadProgress,
    required this.engineState,
    this.deviceMemory,
  });

  final OnDeviceModel model;
  final AsyncValue<Set<String>> downloadedAsync;
  final DownloadProgressInfo? downloadProgress;
  final OnDeviceEngineState engineState;
  final DeviceMemoryInfo? deviceMemory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDownloaded = downloadedAsync.when(
      data: (set) => set.contains(model.id),
      loading: () => false,
      error: (_, _) => false,
    );

    final isLoading =
        engineState.status == OnDeviceEngineStatus.loading &&
        engineState.loadedModelId == model.id;

    final isDownloading =
        downloadProgress != null &&
        (downloadProgress!.status == DownloadStatus.running ||
            downloadProgress!.status == DownloadStatus.pending);

    final isPaused =
        downloadProgress?.status == DownloadStatus.paused ||
        downloadProgress?.status == DownloadStatus.canceled;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDownloaded
                ? Colors.green.withValues(alpha: 0.5)
                : theme.colorScheme.outline.withValues(alpha: 0.3),
            width: isDownloaded ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ModelCardHeader(model: model, theme: theme, l10n: l10n),
            if (!Platform.isIOS &&
                deviceMemory != null &&
                deviceMemory!.isOversized(model.minRamMb))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _MemoryWarningBadge(l10n: l10n, theme: theme),
              ),
            const SizedBox(height: 4),
            Text(
              model.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            _CapabilityChips(model: model, theme: theme),
            const SizedBox(height: 8),
            _ModelMetaRow(model: model, theme: theme, l10n: l10n),
            const SizedBox(height: 8),
            _ModelCardActions(
              model: model,
              isDownloaded: isDownloaded,
              isLoading: isLoading,
              isDownloading: isDownloading,
              isPaused: isPaused,
              downloadProgress: downloadProgress,
              theme: theme,
              l10n: l10n,
              engineState: engineState,
              deviceMemory: deviceMemory,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelCardHeader extends StatelessWidget {
  const _ModelCardHeader({
    required this.model,
    required this.theme,
    required this.l10n,
  });

  final OnDeviceModel model;
  final ThemeData theme;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            model.name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (model.isRecommended)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              l10n.recommended,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        if (model.isImported)
          Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              model.importedSourceLabel ?? 'Imported',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}

class _MemoryWarningBadge extends StatelessWidget {
  const _MemoryWarningBadge({required this.l10n, required this.theme});
  final AppLocalizations l10n;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HugeIcon(
            icon: HugeIcons.strokeRoundedAlertCircle,
            color: Colors.orange,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            l10n.may_be_large,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityChips extends StatelessWidget {
  const _CapabilityChips({required this.model, required this.theme});
  final OnDeviceModel model;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chips = <String>[
      if (model.format == OnDeviceModelFormat.gguf) 'GGUF',
      if (model.runtime == OnDeviceModelRuntime.llamaCpp) 'llama.cpp',
      if (model.supportsFunctionCalling) 'Tools',
      if (model.supportsThinking) 'Thinking',
      if (model.supportsVision) 'Vision',
      model.languagesLabel,
      if (model.backendNote != null &&
          model.backendNote!.toLowerCase() != 'llama.cpp')
        model.backendNote!,
      if (model.requiresHuggingFaceToken) l10n.model_requires_huggingface_token,
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips.map((label) {
        final isBackendNote = label == model.backendNote;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: (isBackendNote ? Colors.orange : theme.colorScheme.primary)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: (isBackendNote ? Colors.orange : theme.colorScheme.primary)
                  .withValues(alpha: 0.2),
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isBackendNote ? Colors.orange : theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ModelMetaRow extends StatelessWidget {
  const _ModelMetaRow({
    required this.model,
    required this.theme,
    required this.l10n,
  });
  final OnDeviceModel model;
  final ThemeData theme;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetaPill(label: model.fileSizeFormatted, theme: theme),
            if (!model.isImported)
              _MetaPill(label: model.license, theme: theme),
            _MetaPill(
              label: l10n.ram_min_required('${model.minRamMb ~/ 1024 + 1}'),
              theme: theme,
              muted: true,
            ),
          ],
        ),
        if (model.isImported) ...[
          const SizedBox(height: 8),
          Text(
            model.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
            ),
          ),
        ],
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.label,
    required this.theme,
    this.muted = false,
  });

  final String label;
  final ThemeData theme;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted
        ? theme.colorScheme.onSurface.withValues(alpha: 0.62)
        : theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ModelCardActions extends ConsumerWidget {
  const _ModelCardActions({
    required this.model,
    required this.isDownloaded,
    required this.isLoading,
    required this.isDownloading,
    required this.isPaused,
    this.downloadProgress,
    required this.theme,
    required this.l10n,
    required this.engineState,
    this.deviceMemory,
  });

  final OnDeviceModel model;
  final bool isDownloaded;
  final bool isLoading;
  final bool isDownloading;
  final bool isPaused;
  final DownloadProgressInfo? downloadProgress;
  final ThemeData theme;
  final AppLocalizations l10n;
  final OnDeviceEngineState engineState;
  final DeviceMemoryInfo? deviceMemory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isDownloaded) {
      return _DownloadedActions(
        model: model,
        isLoading: isLoading,
        engineState: engineState,
        l10n: l10n,
        theme: theme,
      );
    }

    if (isDownloading) {
      return _DownloadingActions(
        model: model,
        downloadProgress: downloadProgress,
        theme: theme,
        l10n: l10n,
      );
    }

    if (downloadProgress?.status == DownloadStatus.failed) {
      return _FailedDownloadActions(
        model: model,
        downloadProgress: downloadProgress,
        theme: theme,
        l10n: l10n,
      );
    }

    if (isPaused) {
      return _PausedDownloadActions(
        model: model,
        downloadProgress: downloadProgress,
        theme: theme,
        l10n: l10n,
      );
    }

    return _NotDownloadedActions(
      model: model,
      deviceMemory: deviceMemory,
      theme: theme,
      l10n: l10n,
    );
  }
}

class _DownloadedActions extends ConsumerWidget {
  const _DownloadedActions({
    required this.model,
    required this.isLoading,
    required this.engineState,
    required this.l10n,
    required this.theme,
  });

  final OnDeviceModel model;
  final bool isLoading;
  final OnDeviceEngineState engineState;
  final AppLocalizations l10n;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoaded = engineState.loadedModelId == model.id;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            HugeIcon(
              icon: isLoaded
                  ? HugeIcons.strokeRoundedCpu
                  : HugeIcons.strokeRoundedCheckmarkCircle01,
              color: isLoaded ? Colors.green : Colors.grey,
              size: 18,
            ),
            const SizedBox(width: 4),
            Text(
              isLoaded ? l10n.loaded_status : l10n.downloaded,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isLoaded ? Colors.green : Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (isLoaded)
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: () =>
                    ref.read(onDeviceEngineProvider.notifier).unloadModel(),
                child: Text(l10n.unload),
              )
            else if (!isLoading)
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: () => _loadModel(context, ref),
                child: Text(l10n.load),
              ),
            const SizedBox(width: 8),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: () => _deleteModel(context, ref),
              child: Text(l10n.delete),
            ),
          ],
        ),
        if (isLoading) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: theme.colorScheme.primary.withValues(
                alpha: 0.15,
              ),
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _loadModel(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    final engineNotifier = ref.read(onDeviceEngineProvider.notifier);
    await engineNotifier.loadModel(model.id, settings.preferredBackend);
  }

  Future<void> _deleteModel(BuildContext context, WidgetRef ref) async {
    final confirm = await ModelConfirmDialog.show(
      context: context,
      title: l10n.delete_model_title,
      message: l10n.delete_model_body(model.name),
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      isDestructive: true,
      icon: HugeIcons.strokeRoundedDelete02,
    );

    if (confirm == true) {
      final engineState = ref.read(onDeviceEngineProvider);
      if (engineState.loadedModelId == model.id) {
        await ref.read(onDeviceEngineProvider.notifier).unloadModel();
      }

      if (model.isImported) {
        await ref
            .read(importedGgufModelsProvider.notifier)
            .deleteModel(model.id);
      } else {
        final gemmaService = ref.read(onDeviceGemmaServiceProvider);
        await gemmaService.deleteModel(model.id);
      }
      ref.invalidate(downloadedModelsProvider);
    }
  }
}

class _DownloadingActions extends ConsumerWidget {
  const _DownloadingActions({
    required this.model,
    this.downloadProgress,
    required this.theme,
    required this.l10n,
  });

  final OnDeviceModel model;
  final DownloadProgressInfo? downloadProgress;
  final ThemeData theme;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: downloadProgress?.progress ?? 0.0,
                      minHeight: 6,
                      backgroundColor: theme.colorScheme.primary.withValues(
                        alpha: 0.1,
                      ),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.download_progress(
                          ((downloadProgress?.progress ?? 0) * 100)
                              .toStringAsFixed(1),
                          downloadProgress?.speedFormatted ?? '0 B/s',
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        l10n.eta_label(
                          downloadProgress?.etaFormatted ?? l10n.calculating,
                        ),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    downloadProgress?.progressFormatted ?? '',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: () => ref
                  .read(foregroundDownloadNotifierProvider.notifier)
                  .cancelDownload(model.id),
              child: Text(l10n.cancel),
            ),
          ],
        ),
      ],
    );
  }
}

class _FailedDownloadActions extends ConsumerWidget {
  const _FailedDownloadActions({
    required this.model,
    this.downloadProgress,
    required this.theme,
    required this.l10n,
  });

  final OnDeviceModel model;
  final DownloadProgressInfo? downloadProgress;
  final ThemeData theme;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: Text(
            downloadProgress?.error ?? l10n.download_failed,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
          ),
        ),
        const SizedBox(width: 8),
        ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: () => ref
              .read(foregroundDownloadNotifierProvider.notifier)
              .retryDownload(model.id),
          child: Text(l10n.retry),
        ),
      ],
    );
  }
}

class _PausedDownloadActions extends ConsumerWidget {
  const _PausedDownloadActions({
    required this.model,
    this.downloadProgress,
    required this.theme,
    required this.l10n,
  });

  final OnDeviceModel model;
  final DownloadProgressInfo? downloadProgress;
  final ThemeData theme;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Text(
          l10n.paused_progress(
            ((downloadProgress?.progress ?? 0) * 100).toStringAsFixed(0),
          ),
          style: theme.textTheme.bodySmall,
        ),
        const Spacer(),
        ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: () => _startDownload(context, ref),
          child: Text(l10n.resume),
        ),
      ],
    );
  }

  Future<void> _startDownload(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(foregroundDownloadNotifierProvider.notifier)
        .startDownload(model.id);

    if (result == 'missing_huggingface_token' && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.model_missing_huggingface_token),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: l10n.settings_title,
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ),
      );
    }
  }
}

class _NotDownloadedActions extends ConsumerWidget {
  const _NotDownloadedActions({
    required this.model,
    this.deviceMemory,
    required this.theme,
    required this.l10n,
  });

  final OnDeviceModel model;
  final DeviceMemoryInfo? deviceMemory;
  final ThemeData theme;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        const Spacer(),
        ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: () => _startDownload(context, ref),
          child: Text(l10n.download),
        ),
      ],
    );
  }

  Future<void> _startDownload(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    if (!Platform.isIOS && deviceMemory != null) {
      if (deviceMemory!.isOversized(model.minRamMb)) {
        final proceed = await _showRamWarning(
          context,
          l10n.ram_warning_body_download(
            '${model.minRamMb ~/ 1024 + 1}',
            deviceMemory!.totalMemoryFormatted,
          ),
        );
        if (!proceed) return;
      }
    }

    final result = await ref
        .read(foregroundDownloadNotifierProvider.notifier)
        .startDownload(model.id);

    if (result == 'missing_huggingface_token' && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.model_missing_huggingface_token),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: l10n.settings_title,
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ),
      );
    }
  }

  Future<bool> _showRamWarning(BuildContext context, String message) async {
    final availableRam = deviceMemory?.availableMemoryFormatted;
    final requiredRam = '${model.minRamMb ~/ 1024 + 1} GB';

    return RamWarningDialog.show(
      context: context,
      availableRam: availableRam,
      requiredRam: requiredRam,
      message: message,
    );
  }
}
