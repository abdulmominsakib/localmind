import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';
import 'package:hugeicons/hugeicons.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:cue/cue.dart';

import '../../../core/models/enums.dart';
import '../../../core/routes/app_routes.dart';
import '../../../l10n/app_localizations.dart';
import '../../on_device/data/models/on_device_model.dart';
import '../../on_device/data/models/download_status.dart';
import '../../on_device/data/models/download_progress_info.dart';
import '../../on_device/providers/on_device_providers.dart';
import '../../on_device/providers/foreground_download_providers.dart';
import '../../servers/data/models/server.dart';
import '../../servers/providers/server_providers.dart';
import '../../../core/providers/device_info_providers.dart';
import '../../../core/device/device_memory_service.dart';
import '../../models/components/ram_warning_dialog.dart';

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
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final models = ref.watch(onDeviceModelsProvider);
    final downloadedModelsAsync = ref.watch(downloadedModelsProvider);
    final downloadStates = ref.watch(foregroundDownloadNotifierProvider);
    final deviceMemoryAsync = ref.watch(deviceMemoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.download_model_title)),
      body: SafeArea(
        child: Cue.onMount(
          motion: .smooth(),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16.0,
                  ),
                  children: [
                    Actor(
                      acts: [.fadeIn(), .slideY(from: 0.08)],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.download_model_desc,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (!Platform.isAndroid && !Platform.isIOS)
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange),
                              ),
                              child: Row(
                                children: [
                                  const HugeIcon(
                                    icon: HugeIcons
                                        .strokeRoundedInformationCircle,
                                    color: Colors.orange,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      l10n.on_device_android_only,
                                      style: const TextStyle(
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          _buildMemoryInfo(context, ref, deviceMemoryAsync),
                        ],
                      ),
                    ),
                    Actor(
                      delay: 60.ms,
                      acts: [.fadeIn(), .slideY(from: 0.08)],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: models.map((model) {
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
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              Actor(
                delay: 120.ms,
                acts: [.fadeIn(), .slideY(from: 0.08)],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isCreatingServer)
                        const Center(child: CircularProgressIndicator())
                      else
                        ShadButton(
                          width: double.infinity,
                          onPressed: _canContinue()
                              ? _createOnDeviceServer
                              : null,
                          child: Text(
                            l10n.continue_action,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
      if (!mounted) return;
      await ref.read(serversProvider.notifier).setDefault(server.id);
      if (!mounted) return;
      ref.read(activeServerIdProvider.notifier).setActiveServer(server);

      if (mounted) {
        context.push(AppRoutes.onboardingTheme);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.error_with_message(e.toString()),
            ),
          ),
        );
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
    final l10n = AppLocalizations.of(context)!;
    return memoryAsync.when(
      data: (info) {
        if (info.totalMemoryMb == 0) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            children: [
              _MemoryStat(
                label: l10n.total_ram,
                value: info.totalMemoryFormatted,
                icon: HugeIcons.strokeRoundedCpu,
              ),
              const SizedBox(width: 24),
              _MemoryStat(
                label: l10n.available,
                value: info.availableMemoryFormatted,
                icon: HugeIcons.strokeRoundedCalendarCheckIn01,
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
  final List<List<dynamic>> icon;
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
        HugeIcon(
          icon: icon,
          size: 16,
          color: color ?? theme.colorScheme.primary,
        ),
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
    final l10n = AppLocalizations.of(context)!;
    final isDownloading =
        progressInfo?.status == DownloadStatus.running ||
        progressInfo?.status == DownloadStatus.pending;
    final isPaused =
        progressInfo?.status == DownloadStatus.paused ||
        progressInfo?.status == DownloadStatus.canceled;
    final builtInAvailability = model.isBuiltIn
        ? ref.watch(builtInAiAvailabilityProvider).value
        : null;
    final isBuiltInUnsupported =
        model.isBuiltIn &&
        (builtInAvailability ==
                BuiltInAiAvailability.unavailableDeviceUnsupported ||
            builtInAvailability == BuiltInAiAvailability.unavailableOther);

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
                    l10n.recommended,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (model.isBuiltIn)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    Platform.isIOS || Platform.isMacOS
                        ? ' Apple Intelligence'
                        : '⚡ Built-in AI',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.teal,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          if (!Platform.isIOS &&
              deviceMemory != null &&
              deviceMemory!.isOversized(model.minRamMb))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const HugeIcon(
                    icon: HugeIcons.strokeRoundedAlertCircle,
                    color: Colors.orange,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.may_be_large,
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
          _buildCapabilityChips(context),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(model.fileSizeFormatted, style: theme.textTheme.labelMedium),
              const SizedBox(width: 12),
              Text(model.license, style: theme.textTheme.labelMedium),
              const SizedBox(width: 12),
              Text(
                l10n.ram_min_required('${model.minRamMb ~/ 1024 + 1}'),
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
                const HugeIcon(
                  icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                  color: Colors.green,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.downloaded,
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progressInfo?.progress ?? 0.0,
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
                              ((progressInfo?.progress ?? 0) * 100)
                                  .toStringAsFixed(0),
                              progressInfo?.speedFormatted ?? '0 B/s',
                            ),
                            style: theme.textTheme.labelSmall,
                          ),
                          Text(
                            l10n.eta_label(
                              progressInfo?.etaFormatted ?? l10n.calculating,
                            ),
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
                      .cancelDownload(model.id),
                  child: Text(l10n.cancel),
                ),
              ],
            )
          else if (progressInfo?.status == DownloadStatus.failed)
            Row(
              children: [
                HugeIcon(
                  icon: isBuiltInUnsupported
                      ? HugeIcons.strokeRoundedUnavailable
                      : HugeIcons.strokeRoundedAlertCircle,
                  color: Colors.red[400]!,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isBuiltInUnsupported
                        ? l10n.builtin_ai_not_supported
                        : (progressInfo?.error ?? l10n.download_failed),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.red[400],
                    ),
                  ),
                ),
                if (!isBuiltInUnsupported) ...[
                  const SizedBox(width: 8),
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: () => ref
                        .read(foregroundDownloadNotifierProvider.notifier)
                        .retryDownload(model.id),
                    child: Text(l10n.retry),
                  ),
                ],
              ],
            )
          else if (isPaused)
            Row(
              children: [
                Text(
                  l10n.paused_progress(
                    '${((progressInfo?.progress ?? 0) * 100).toStringAsFixed(0)}%',
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
            )
          else if (isBuiltInUnsupported)
            Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedUnavailable,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.builtin_ai_not_supported,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            )
          else
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: () => _startDownload(context, ref),
              child: Text(
                model.isBuiltIn ? l10n.builtin_ai_enable : l10n.download,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCapabilityChips(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chips = <String>[
      if (model.isBuiltIn) '⚡ Built-in',
      if (model.supportsFunctionCalling) 'Tools',
      if (model.supportsThinking) 'Thinking',
      if (model.supportsVision) 'Vision',
      model.languagesLabel,
      if (model.backendNote != null) model.backendNote!,
      if (model.requiresHuggingFaceToken) l10n.model_requires_huggingface_token,
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips.map(_buildCapabilityChip).toList(),
    );
  }

  Widget _buildCapabilityChip(String label) {
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
  }

  Future<void> _startDownload(BuildContext context, WidgetRef ref) async {
    if (!Platform.isIOS && deviceMemory != null) {
      if (deviceMemory!.isOversized(model.minRamMb)) {
        final proceed = await _showRamWarning(context);
        if (!proceed) return;
      }
    }

    final result = await ref
        .read(foregroundDownloadNotifierProvider.notifier)
        .startDownload(model.id);

    if (result == 'missing_huggingface_token' && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.model_missing_huggingface_token,
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<bool> _showRamWarning(BuildContext context) async {
    final availableRam = deviceMemory?.totalMemoryFormatted;
    final requiredRam = '${model.minRamMb ~/ 1024 + 1} GB';

    return RamWarningDialog.show(
      context: context,
      availableRam: availableRam,
      requiredRam: requiredRam,
    );
  }
}
