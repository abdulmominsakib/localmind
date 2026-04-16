import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/enums.dart';
import '../../../core/routes/app_routes.dart';
import '../../on_device/data/models/on_device_model.dart';
import '../../on_device/data/on_device_model_download_service.dart';
import '../../on_device/providers/on_device_providers.dart';
import '../../servers/data/models/server.dart';
import '../../servers/providers/server_providers.dart';

class OnboardingModelDownloadScreen extends ConsumerStatefulWidget {
  const OnboardingModelDownloadScreen({super.key});

  @override
  ConsumerState<OnboardingModelDownloadScreen> createState() =>
      _OnboardingModelDownloadScreenState();
}

class _OnboardingModelDownloadScreenState
    extends ConsumerState<OnboardingModelDownloadScreen> {
  String? _downloadingModelId;
  double _downloadProgress = 0.0;
  bool _isCreatingServer = false;
  StreamSubscription<DownloadProgress>? _downloadSubscription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final models = ref.watch(onDeviceModelsProvider);
    final downloadedModelsAsync = ref.watch(downloadedModelsProvider);
    final isAndroid = Platform.isAndroid;

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
            ...models.map((model) {
              final isDownloaded = downloadedModelsAsync.when(
                data: (set) => set.contains(model.id),
                loading: () => false,
                error: (_, _) => false,
              );
              final isDownloading = _downloadingModelId == model.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ModelCard(
                  model: model,
                  isDownloaded: isDownloaded,
                  isDownloading: isDownloading,
                  downloadProgress: _downloadProgress,
                  onDownload: isDownloaded || isDownloading
                      ? null
                      : () => _downloadModel(model),
                  theme: theme,
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

  Future<void> _downloadModel(OnDeviceModel model) async {
    await _downloadSubscription?.cancel();
    setState(() {
      _downloadingModelId = model.id;
      _downloadProgress = 0.0;
    });

    final downloadService = ref.read(onDeviceDownloadServiceProvider);
    try {
      await for (final progress in downloadService.downloadModel(model)) {
        if (!mounted) return;
        setState(() {
          _downloadProgress = progress.fraction;
        });
      }
      ref.invalidate(downloadedModelsProvider);
      if (mounted) {
        setState(() {
          _downloadingModelId = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadingModelId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: ${e.toString()}')),
        );
      }
    }
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
}

class _ModelCard extends StatelessWidget {
  final OnDeviceModel model;
  final bool isDownloaded;
  final bool isDownloading;
  final double downloadProgress;
  final VoidCallback? onDownload;
  final ThemeData theme;

  const _ModelCard({
    required this.model,
    required this.isDownloaded,
    required this.isDownloading,
    required this.downloadProgress,
    this.onDownload,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: downloadProgress),
                const SizedBox(height: 4),
                Text(
                  '${(downloadProgress * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            )
          else
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: onDownload,
              child: const Text('Download'),
            ),
        ],
      ),
    );
  }
}
