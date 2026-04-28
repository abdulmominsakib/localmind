import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../sidebar/sidebar_widget.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/enums.dart';
import '../../../core/providers/app_providers.dart';
import '../../on_device/data/models/on_device_model.dart';
import '../../on_device/data/models/download_progress_info.dart';
import '../../on_device/data/models/download_status.dart';
import '../../on_device/providers/on_device_providers.dart';
import '../../on_device/providers/foreground_download_providers.dart';
import '../../../core/providers/device_info_providers.dart';
import '../../../core/device/device_memory_service.dart';

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
    final deviceMemoryAsync = ref.watch(deviceMemoryProvider);

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
          _buildMemoryInfo(context, ref, deviceMemoryAsync),
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
              deviceMemory: deviceMemoryAsync.value,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildMemoryInfo(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<DeviceMemoryInfo> memoryAsync,
  ) {
    return memoryAsync.when(
      data: (info) {
        if (info.totalMemoryMb == 0) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final usedMb = info.totalMemoryMb - info.availableMemoryMb;
        final usagePercent = usedMb / info.totalMemoryMb;
        
        // Memory health logic
        Color statusColor = Colors.green;
        String statusText = 'Healthy';
        if (info.availableMemoryMb < 1024) {
          statusColor = Colors.red;
          statusText = 'Critical';
        } else if (info.availableMemoryMb < 2048) {
          statusColor = Colors.orange;
          statusText = 'Low';
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.surfaceContainerHighest,
                theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.memory_rounded,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Device Memory',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    ShadButton.ghost(
                      size: ShadButtonSize.sm,
                      onPressed: () => ref.invalidate(deviceMemoryProvider),
                      child: const Icon(Icons.refresh_rounded, size: 18),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'RAM Usage',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: statusColor.withValues(alpha: 0.2)),
                          ),
                          child: Text(
                            statusText,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        children: [
                          Container(
                            height: 10,
                            width: double.infinity,
                            color: theme.colorScheme.surfaceContainerLowest,
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            height: 10,
                            width: MediaQuery.of(context).size.width * usagePercent,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  statusColor,
                                  statusColor.withValues(alpha: 0.7),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: statusColor.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(usagePercent * 100).toStringAsFixed(0)}% used',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${_formatMb(usedMb)} / ${info.totalMemoryFormatted}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _MemoryStat(
                        label: 'Available RAM',
                        value: info.availableMemoryFormatted,
                        icon: Icons.speed_rounded,
                        color: statusColor,
                        isPrimary: true,
                      ),
                    ),
                    Container(
                      height: 30,
                      width: 1,
                      color: theme.colorScheme.outline.withValues(alpha: 0.1),
                    ),
                    Expanded(
                      child: _MemoryStat(
                        label: 'Total Capacity',
                        value: info.totalMemoryFormatted,
                        icon: Icons.storage_rounded,
                        alignment: CrossAxisAlignment.end,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  String _formatMb(int mb) {
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '$mb MB';
  }
}

class _MemoryStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final CrossAxisAlignment alignment;
  final bool isPrimary;

  const _MemoryStat({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.alignment = CrossAxisAlignment.start,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = color ?? theme.colorScheme.onSurface.withValues(alpha: 0.4);

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (alignment == CrossAxisAlignment.start) ...[
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 10,
              ),
            ),
            if (alignment == CrossAxisAlignment.end) ...[
              const SizedBox(width: 6),
              Icon(icon, size: 14, color: iconColor),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: (isPrimary ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: isPrimary ? -0.5 : null,
          ),
        ),
      ],
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
    this.deviceMemory,
  });

  final OnDeviceModel model;
  final ThemeData theme;
  final AsyncValue<Set<String>> downloadedAsync;
  final DownloadProgressInfo? downloadProgress;
  final OnDeviceEngineState engineState;
  final DeviceMemoryInfo? deviceMemory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDownloaded = downloadedAsync.when(
      data: (set) => set.contains(model.id),
      loading: () => false,
      error: (_, _) => false,
    );

    final isLoading =
        engineState.status == EngineStatus.loading &&
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
            if (deviceMemory != null && deviceMemory!.isOversized(model.minRamMb))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'May be too large for this device',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
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
              onPressed: () => _loadModel(context, ref),
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: downloadProgress?.progress ?? 0.0,
                      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${((downloadProgress?.progress ?? 0) * 100).toStringAsFixed(1)}% • ${downloadProgress?.speedFormatted ?? '0 B/s'}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'ETA: ${downloadProgress?.etaFormatted ?? 'Calculating...'}',
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
                    .pauseDownload(model.id),
                child: const Text('Pause'),
              ),
            ],
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

    if (isPaused) {
      return Row(
        children: [
          Text(
            'Paused - ${((downloadProgress?.progress ?? 0) * 100).toStringAsFixed(0)}%',
            style: theme.textTheme.bodySmall,
          ),
          const Spacer(),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: () => _startDownload(context, ref),
            child: const Text('Resume'),
          ),
        ],
      );
    }

    return Row(
      children: [
        const Spacer(),
        ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: () => _startDownload(context, ref),
          child: const Text('Download'),
        ),
      ],
    );
  }

  Future<void> _startDownload(BuildContext context, WidgetRef ref) async {
    if (deviceMemory != null) {
      if (deviceMemory!.isOversized(model.minRamMb)) {
        final proceed = await _showRamWarning(
          context,
          'This model requires at least ${model.minRamMb ~/ 1024 + 1} GB RAM, but your device has ${deviceMemory!.totalMemoryFormatted}. It may not run correctly or could cause the app to crash.',
        );
        if (!proceed) return;
      }
    }

    await ref
        .read(foregroundDownloadNotifierProvider.notifier)
        .startDownload(model.id);
  }

  Future<void> _loadModel(BuildContext context, WidgetRef ref) async {
    if (deviceMemory != null) {
      if (!deviceMemory!.hasEnoughRam(model.minRamMb)) {
        final proceed = await _showRamWarning(
          context,
          'Your device has ${deviceMemory!.availableMemoryFormatted} available RAM, but this model recommends at least ${model.minRamMb ~/ 1024 + 1} GB. Loading it might fail or cause instability.',
        );
        if (!proceed) return;
      }
    }

    final settings = ref.read(settingsProvider);
    final engineNotifier = ref.read(onDeviceEngineProvider.notifier);
    await engineNotifier.loadModel(model.id, settings.preferredBackend);
  }

  Future<bool> _showRamWarning(BuildContext context, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('RAM Warning'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Proceed Anyway'),
          ),
        ],
      ),
    );
    return result ?? false;
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
