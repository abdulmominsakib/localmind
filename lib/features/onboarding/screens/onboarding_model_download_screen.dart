import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/enums.dart';
import '../../../core/routes/app_routes.dart';
import '../../on_device/data/models/on_device_model.dart';
import '../../on_device/data/models/download_status.dart';
import '../../on_device/data/models/download_progress_info.dart';
import '../../on_device/providers/on_device_providers.dart';
import '../../on_device/providers/foreground_download_providers.dart';
import '../../servers/data/models/server.dart';
import '../../servers/providers/server_providers.dart';
import '../../../core/providers/device_info_providers.dart';
import '../../../core/device/device_memory_service.dart';

class OnboardingModelDownloadScreen extends ConsumerStatefulWidget {
  const OnboardingModelDownloadScreen({super.key});

  @override
  ConsumerState<OnboardingModelDownloadScreen> createState() =>
      _OnboardingModelDownloadScreenState();
}

class _OnboardingModelDownloadScreenState
    extends ConsumerState<OnboardingModelDownloadScreen> {
  bool _isCreatingServer = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final models = ref.watch(onDeviceModelsProvider);
    final downloadedModelsAsync = ref.watch(downloadedModelsProvider);
    final downloadStates = ref.watch(foregroundDownloadNotifierProvider);
    final isAndroid = Platform.isAndroid;
    final deviceMemoryAsync = ref.watch(deviceMemoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Download a Model')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          children: [
            Text(
              'Choose a model to download.\nIt will run locally on your device.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
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
                        'On-device inference is currently available on Android only.',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            _buildMemoryInfo(context, ref, deviceMemoryAsync),
            ...models.map((model) {
              final isDownloaded = downloadedModelsAsync.when(
                data: (set) => set.contains(model.id),
                loading: () => false,
                error: (_, _) => false,
              );
              final progressInfo = downloadStates[model.id];

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ModelCard(
                  model: model,
                  isDownloaded: isDownloaded,
                  progressInfo: progressInfo,
                  theme: theme,
                  deviceMemory: deviceMemoryAsync.value,
                ),
              );
            }),
            const SizedBox(height: 24),
            if (_isCreatingServer)
              const Center(child: CircularProgressIndicator())
            else
              ShadButton(
                width: double.infinity,
                onPressed: _canContinue() ? _createOnDeviceServer : null,
                child: const Text(
                  'Continue',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _canContinue() {
    final downloadedSet = ref.read(downloadedModelsProvider).whenData((s) => s);
    return downloadedSet.hasValue && downloadedSet.value!.isNotEmpty;
  }

  Future<void> _createOnDeviceServer() async {
    setState(() => _isCreatingServer = true);

    try {
      final server = Server(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: 'On-Device',
        type: ServerType.onDevice,
        host: '',
        port: 0,
        isDefault: true,
        createdAt: DateTime.now(),
        lastConnectedAt: DateTime.now(),
        status: ConnectionStatus.connected,
        iconName: 'strokeRoundedSmartPhone01',
      );

      await ref.read(serversProvider.notifier).addServer(server);
      await ref.read(serversProvider.notifier).setDefault(server.id);
      ref.read(activeServerProvider.notifier).setActiveServer(server);

      if (mounted) {
        context.push(AppRoutes.onboardingTheme);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingServer = false);
      }
    }
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
        return Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              _MemoryStat(
                label: 'Total RAM',
                value: info.totalMemoryFormatted,
                icon: Icons.memory,
              ),
              const SizedBox(width: 24),
              _MemoryStat(
                label: 'Available',
                value: info.availableMemoryFormatted,
                icon: Icons.event_available,
                color: info.availableMemoryMb < 1024 ? Colors.orange : null,
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _MemoryStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const _MemoryStat({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? theme.colorScheme.primary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ModelCard extends ConsumerWidget {
  final OnDeviceModel model;
  final bool isDownloaded;
  final DownloadProgressInfo? progressInfo;
  final ThemeData theme;
  final DeviceMemoryInfo? deviceMemory;

  const _ModelCard({
    required this.model,
    required this.isDownloaded,
    this.progressInfo,
    required this.theme,
    this.deviceMemory,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDownloading =
        progressInfo?.status == DownloadStatus.running ||
        progressInfo?.status == DownloadStatus.pending;
    final isPaused =
        progressInfo?.status == DownloadStatus.paused ||
        progressInfo?.status == DownloadStatus.canceled;

    return Container(
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
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 14),
                  const SizedBox(width: 4),
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
              Text(model.fileSizeFormatted, style: theme.textTheme.labelMedium),
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
          if (isDownloaded)
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 18),
                const SizedBox(width: 4),
                Text(
                  'Downloaded',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          else if (isDownloading)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LinearProgressIndicator(value: progressInfo?.progress ?? 0),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${((progressInfo?.progress ?? 0) * 100).toStringAsFixed(0)}% • ${progressInfo?.speedFormatted ?? "0 B/s"}',
                            style: theme.textTheme.labelSmall,
                          ),
                          Text(
                            'ETA: ${progressInfo?.etaFormatted ?? "..."}',
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
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
            )
          else if (isPaused)
            Row(
              children: [
                Text(
                  'Paused - ${((progressInfo?.progress ?? 0) * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: () => _startDownload(context, ref),
                  child: const Text('Resume'),
                ),
              ],
            )
          else
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: () => _startDownload(context, ref),
              child: const Text('Download'),
            ),
        ],
      ),
    );
  }

  Future<void> _startDownload(BuildContext context, WidgetRef ref) async {
    if (deviceMemory != null) {
      if (deviceMemory!.isOversized(model.minRamMb)) {
        final proceed = await _showRamWarning(context);
        if (!proceed) return;
      }
    }

    await ref
        .read(foregroundDownloadNotifierProvider.notifier)
        .startDownload(model.id);
  }

  Future<bool> _showRamWarning(BuildContext context) async {
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
        content: Text(
          'This model requires at least ${model.minRamMb ~/ 1024 + 1} GB RAM, but your device has ${deviceMemory!.totalMemoryFormatted}. It may not run correctly or could cause the app to crash.',
        ),
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
}
