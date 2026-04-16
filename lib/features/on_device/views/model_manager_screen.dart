import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/features/sidebar/sidebar_widget.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/enums.dart';
import '../../../core/providers/app_providers.dart';
import '../../on_device/data/models/on_device_model.dart';
import '../../on_device/data/models/download_progress_info.dart';
import '../../on_device/data/models/download_status.dart';
import '../../on_device/providers/on_device_providers.dart';
import '../../on_device/providers/foreground_download_providers.dart';

class OnDeviceModelManagerScreen extends ConsumerWidget {
  const OnDeviceModelManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final models = ref.watch(onDeviceModelsProvider);
    final downloadedAsync = ref.watch(downloadedModelsProvider);
    final engineState = ref.watch(onDeviceEngineProvider);
    final downloadProgress = ref.watch(foregroundDownloadNotifierProvider);
    final isAndroid = Platform.isAndroid;

    return Scaffold(
      drawer: const SidebarWidget(),
      appBar: AppBar(title: const Text('On-Device Models')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!isAndroid)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'On-device inference is available on Android only.',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          if (engineState.status == EngineStatus.loaded)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Model loaded: ${engineState.loadedModelId ?? "Unknown"} (${engineState.backend?.name ?? "CPU"})',
                      style: const TextStyle(color: Colors.green),
                    ),
                  ),
                ],
              ),
            )
          else if (engineState.status == EngineStatus.loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: LinearProgressIndicator(),
            )
          else if (engineState.status == EngineStatus.error)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: Text(
                engineState.error ?? 'Engine error',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          Text(
            'Available Models',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...models.map(
            (model) => _ModelCard(
              model: model,
              theme: theme,
              downloadedAsync: downloadedAsync,
              downloadProgress: downloadProgress[model.id],
              engineState: engineState,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ModelCard extends ConsumerWidget {
  const _ModelCard({
    required this.model,
    required this.theme,
    required this.downloadedAsync,
    required this.downloadProgress,
    required this.engineState,
  });

  final OnDeviceModel model;
  final ThemeData theme;
  final AsyncValue<Set<String>> downloadedAsync;
  final DownloadProgressInfo? downloadProgress;
  final OnDeviceEngineState engineState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDownloaded = downloadedAsync.when(
      data: (set) => set.contains(model.id),
      loading: () => false,
      error: (_, __) => false,
    );

    final isLoading =
        engineState.status == EngineStatus.loading &&
        engineState.loadedModelId == model.id;

    final isDownloading =
        downloadProgress != null &&
        (downloadProgress!.status == DownloadStatus.running ||
            downloadProgress!.status == DownloadStatus.pending);

    final isPaused = downloadProgress?.status == DownloadStatus.paused;

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
            Row(
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'RECOMMENDED',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              model.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  model.fileSizeFormatted,
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(width: 12),
                Text(model.license, style: theme.textTheme.labelMedium),
                const SizedBox(width: 12),
                Text(
                  '${model.minRamMb ~/ 1024 + 1} GB RAM min',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildActionRow(
              context,
              ref,
              isDownloaded,
              isLoading,
              isDownloading,
              isPaused,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(
    BuildContext context,
    WidgetRef ref,
    bool isDownloaded,
    bool isLoading,
    bool isDownloading,
    bool isPaused,
  ) {
    final isLoaded = engineState.loadedModelId == model.id;

    if (isDownloaded) {
      return Row(
        children: [
          Icon(
            isLoaded ? Icons.check_circle : Icons.check_circle_outline,
            color: isLoaded ? Colors.green : Colors.grey,
            size: 18,
          ),
          const SizedBox(width: 4),
          Text(
            isLoaded ? 'Loaded' : 'Downloaded',
            style: theme.textTheme.bodySmall?.copyWith(
              color: isLoaded ? Colors.green : Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (isLoading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (isLoaded)
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: () => _unloadModel(ref),
              child: const Text('Unload'),
            )
          else
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: () => _loadModel(ref),
              child: const Text('Load'),
            ),
          const SizedBox(width: 8),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: () => _deleteModel(context, ref),
            child: const Text('Delete'),
          ),
        ],
      );
    }

    if (isDownloading) {
      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: downloadProgress?.progress ?? 0.0,
                ),
                const SizedBox(height: 4),
                Text(
                  'Downloading - ${((downloadProgress?.progress ?? 0) * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: () => ref
                .read(foregroundDownloadNotifierProvider.notifier)
                .cancelDownload(model.id),
            child: const Text('Cancel'),
          ),
        ],
      );
    }

    if (downloadProgress?.status == DownloadStatus.failed) {
      return Row(
        children: [
          Expanded(
            child: Text(
              downloadProgress?.error ?? 'Download failed',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
            ),
          ),
          const SizedBox(width: 8),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: () => ref
                .read(foregroundDownloadNotifierProvider.notifier)
                .retryDownload(model.id),
            child: const Text('Retry'),
          ),
        ],
      );
    }

    return Row(
      children: [
        const Spacer(),
        ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: () => _startDownload(ref),
          child: const Text('Download'),
        ),
      ],
    );
  }

  Future<void> _startDownload(WidgetRef ref) async {
    await ref
        .read(foregroundDownloadNotifierProvider.notifier)
        .startDownload(model.id);
  }

  Future<void> _loadModel(WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    final engineNotifier = ref.read(onDeviceEngineProvider.notifier);
    await engineNotifier.loadModel(model.id, settings.preferredBackend);
  }

  Future<void> _unloadModel(WidgetRef ref) async {
    await ref.read(onDeviceEngineProvider.notifier).unloadModel();
  }

  Future<void> _deleteModel(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Model'),
        content: Text('Are you sure you want to delete ${model.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final engineState = ref.read(onDeviceEngineProvider);
      if (engineState.loadedModelId == model.id) {
        await ref.read(onDeviceEngineProvider.notifier).unloadModel();
      }

      final downloadService = ref.read(onDeviceDownloadServiceProvider);
      await downloadService.deleteModel(model.id);
      ref.invalidate(downloadedModelsProvider);
    }
  }
}
