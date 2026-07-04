import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/core/device/device_memory_service.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/providers/device_info_providers.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/providers/model_selection_providers.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/models/providers/model_picker_providers.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/data/models/download_status.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/on_device/providers/foreground_download_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/features/models/components/metadata_chip.dart';

class OnDevicePickerSection extends ConsumerWidget {
  const OnDevicePickerSection({
    super.key,
    required this.selectedModelId,
    required this.isDark,
    this.scrollController,
  });

  final String? selectedModelId;
  final bool isDark;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final curatedModels = ref.watch(onDeviceModelsProvider);
    final downloadedAsync = ref.watch(downloadedModelsProvider);
    final engineState = ref.watch(onDeviceEngineProvider);
    final searchQuery = ref.watch(modelSearchQueryProvider);
    final deviceMemoryAsync = ref.watch(deviceMemoryProvider);

    return downloadedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              l10n.failed_load_models,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => ref.invalidate(downloadedModelsProvider),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.retry),
            ),
          ],
        ),
      ),
      data: (downloadedIds) {
        final filtered = searchQuery.isEmpty
            ? curatedModels
            : curatedModels
                  .where(
                    (m) => m.name.toLowerCase().contains(
                      searchQuery.toLowerCase(),
                    ),
                  )
                  .toList();

        if (filtered.isEmpty) {
          return Center(
            child: Text(
              searchQuery.isEmpty
                  ? l10n.no_models_available
                  : l10n.no_models_match(searchQuery),
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? AppColors.darkMutedText
                    : AppColors.lightMutedText,
              ),
            ),
          );
        }

        final importedModels =
            filtered.where((model) => model.isImported).toList()..sort(
              (a, b) => (b.importedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                  .compareTo(
                    a.importedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                  ),
            );
        final downloadableModels = filtered
            .where((model) => !model.isImported)
            .toList();

        Widget buildTile(OnDeviceModel model) {
          final isDownloaded = downloadedIds.contains(model.id);
          final isLoaded = engineState.loadedModelId == model.id;
          final isCurrentlyLoading =
              engineState.status == OnDeviceEngineStatus.loading &&
              engineState.loadedModelId == model.id;
          final isSelected = selectedModelId == model.id;

          return _OnDeviceModelTile(
            model: model,
            isDownloaded: isDownloaded,
            isLoaded: isLoaded,
            isCurrentlyLoading: isCurrentlyLoading,
            isSelected: isSelected,
            isDark: isDark,
            deviceMemory: deviceMemoryAsync.value,
          );
        }

        return ListView(
          controller: scrollController,
          children: [
            if (importedModels.isNotEmpty) ...[
              const SizedBox(height: 4),
              _PickerSectionLabel(
                title: l10n.gguf_imported_section_label,
                subtitle: l10n.gguf_already_available,
              ),
              ...importedModels.map(buildTile),
              const SizedBox(height: 8),
            ],
            if (downloadableModels.isNotEmpty) ...[
              _PickerSectionLabel(
                title: l10n.available_models,
                subtitle: l10n.gguf_curated_models_short,
              ),
              ...downloadableModels.map(buildTile),
            ],
          ],
        );
      },
    );
  }
}

class _PickerSectionLabel extends StatelessWidget {
  const _PickerSectionLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 11, color: muted)),
        ],
      ),
    );
  }
}

class _OnDeviceModelTile extends ConsumerWidget {
  const _OnDeviceModelTile({
    required this.model,
    required this.isDownloaded,
    required this.isLoaded,
    required this.isCurrentlyLoading,
    required this.isSelected,
    required this.isDark,
    this.deviceMemory,
  });

  final OnDeviceModel model;
  final bool isDownloaded;
  final bool isLoaded;
  final bool isCurrentlyLoading;
  final bool isSelected;
  final bool isDark;
  final DeviceMemoryInfo? deviceMemory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final downloadProgress = ref.watch(
      foregroundDownloadNotifierProvider,
    )[model.id];
    final isDownloading =
        downloadProgress != null &&
        (downloadProgress.status == DownloadStatus.running ||
            downloadProgress.status == DownloadStatus.pending);
    final isPaused = downloadProgress?.status == DownloadStatus.paused;

    return InkWell(
      onTap: () {
        if (isLoaded) {
          _selectModel(context, ref);
        } else if (isDownloaded && !isCurrentlyLoading && !isDownloading) {
          _loadModel(context, ref);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: accent.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          model.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isDownloaded
                                ? (isDark ? Colors.white : Colors.black)
                                : (isDark
                                      ? AppColors.darkMutedText
                                      : AppColors.lightMutedText),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (model.isRecommended)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.recommended,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: accent,
                            ),
                          ),
                        ),
                      if (model.isImported)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            model.importedSourceLabel ?? 'Imported',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (!Platform.isIOS &&
                      deviceMemory != null &&
                      deviceMemory!.isOversized(model.minRamMb))
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n.may_be_large,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isDownloading || isPaused)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: downloadProgress?.progress ?? 0.0,
                            backgroundColor: isDark
                                ? AppColors.darkBorder
                                : AppColors.lightBorder,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isPaused
                                ? l10n.paused_progress(
                                    ((downloadProgress?.progress ?? 0) * 100)
                                        .toStringAsFixed(0),
                                  )
                                : '${l10n.downloading_status} ${((downloadProgress?.progress ?? 0) * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark
                                  ? AppColors.darkMutedText
                                  : AppColors.lightMutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      MetadataChip(
                        label: model.fileSizeFormatted,
                        isDark: isDark,
                      ),
                      if (model.format == OnDeviceModelFormat.gguf)
                        MetadataChip(
                          label: l10n.gguf_format_label,
                          isDark: isDark,
                        ),
                      if (model.runtime == OnDeviceModelRuntime.llamaCpp)
                        MetadataChip(label: 'llama.cpp', isDark: isDark),
                      if (!model.isImported)
                        MetadataChip(label: model.license, isDark: isDark),
                      if (!model.isImported)
                        MetadataChip(
                          label: model.parameterLabel,
                          isDark: isDark,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isCurrentlyLoading) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ] else if (isLoaded) ...[
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppColors.darkAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              _IconButton(
                icon: Icon(
                  Icons.power_settings_new_outlined,
                  size: 18,
                  color: Colors.red[400],
                ),
                tooltip: l10n.unload,
                onPressed: () => _unloadModel(context, ref),
              ),
            ] else if (isDownloaded) ...[
              _IconButton(
                icon: Icon(Icons.play_arrow, size: 20, color: accent),
                tooltip: l10n.load,
                onPressed: () => _loadModel(context, ref),
              ),
              const SizedBox(width: 4),
              _IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: isDark
                      ? AppColors.darkMutedText
                      : AppColors.lightMutedText,
                ),
                tooltip: l10n.delete,
                onPressed: () => _deleteModel(context, ref),
              ),
            ] else if (isDownloading) ...[
              _IconButton(
                icon: Icon(
                  Icons.close,
                  size: 16,
                  color: isDark
                      ? AppColors.darkMutedText
                      : AppColors.lightMutedText,
                ),
                tooltip: l10n.cancel,
                onPressed: () => ref
                    .read(foregroundDownloadNotifierProvider.notifier)
                    .cancelDownload(model.id),
              ),
            ] else ...[
              _IconButton(
                icon: Icon(
                  Icons.cloud_download_outlined,
                  size: 18,
                  color: isDark
                      ? AppColors.darkMutedText
                      : AppColors.lightMutedText,
                ),
                tooltip: l10n.download,
                onPressed: () async {
                  final result = await ref
                      .read(foregroundDownloadNotifierProvider.notifier)
                      .startDownload(model.id);
                  if (result == 'missing_huggingface_token' &&
                      context.mounted) {
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
                },
              ),
              const SizedBox(width: 4),
              Text(
                l10n.not_downloaded,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppColors.darkMutedText
                      : AppColors.lightMutedText,
                ),
              ),
            ],
            if (isDownloaded && isSelected && isLoaded) ...[
              const SizedBox(width: 4),
              Icon(Icons.check_circle, color: accent, size: 22),
            ],
          ],
        ),
      ),
    );
  }

  void _loadModel(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    final engineNotifier = ref.read(onDeviceEngineProvider.notifier);

    if (!Platform.isIOS && deviceMemory != null) {
      if (!deviceMemory!.hasEnoughRam(model.minRamMb)) {
        final proceed = await _showRamWarning(context);
        if (!context.mounted) return;
        if (!proceed) return;
      }
    }

    final modelInfo = ModelInfo(
      id: model.id,
      name: model.name,
      description: model.description,
      parameterCount: double.tryParse(
        model.parameterLabel.replaceAll(RegExp(r'[^0-9\.]'), ''),
      ),
      fileSize: model.fileSizeBytes,
      quantization: model.format == OnDeviceModelFormat.gguf ? 'GGUF' : null,
      architecture: model.runtime == OnDeviceModelRuntime.llamaCpp
          ? 'llama.cpp'
          : null,
      serverType: ServerType.onDevice,
      serverId: 'on-device',
      modifiedAt: model.importedAt,
      onDeviceRuntime: model.runtime,
      onDeviceFormat: model.format,
      localPath: model.localPath,
      supportsVision: model.supportsVision,
      supportsReasoning: model.supportsThinking,
      supportsToolUse: model.supportsFunctionCalling,
    );

    await engineNotifier.loadModel(model.id, settings.preferredBackend);
    if (!context.mounted) return;

    final engineState = ref.read(onDeviceEngineProvider);
    if (engineState.loadedModelId == model.id) {
      ref.read(selectedModelProvider.notifier).setModel(modelInfo);
      Navigator.pop(context);
    }
  }

  Future<bool> _showRamWarning(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Text(l10n.ram_warning),
          ],
        ),
        content: Text(
          l10n.ram_warning_body_load(
            deviceMemory!.availableMemoryFormatted,
            '${model.minRamMb ~/ 1024 + 1}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: Text(l10n.proceed_anyway),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _selectModel(BuildContext context, WidgetRef ref) {
    final modelInfo = ModelInfo(
      id: model.id,
      name: model.name,
      description: model.description,
      parameterCount: double.tryParse(
        model.parameterLabel.replaceAll(RegExp(r'[^0-9\.]'), ''),
      ),
      fileSize: model.fileSizeBytes,
      quantization: model.format == OnDeviceModelFormat.gguf ? 'GGUF' : null,
      architecture: model.runtime == OnDeviceModelRuntime.llamaCpp
          ? 'llama.cpp'
          : null,
      serverType: ServerType.onDevice,
      serverId: 'on-device',
      modifiedAt: model.importedAt,
      onDeviceRuntime: model.runtime,
      onDeviceFormat: model.format,
      localPath: model.localPath,
      supportsVision: model.supportsVision,
      supportsReasoning: model.supportsThinking,
      supportsToolUse: model.supportsFunctionCalling,
    );

    ref.read(selectedModelProvider.notifier).setModel(modelInfo);
    Navigator.pop(context);
  }

  void _unloadModel(BuildContext context, WidgetRef ref) async {
    final engineNotifier = ref.read(onDeviceEngineProvider.notifier);
    await engineNotifier.unloadModel();
    if (!context.mounted) return;

    final selectedModel = ref.read(selectedModelProvider);
    if (selectedModel?.id == model.id) {
      ref.read(selectedModelProvider.notifier).clear();
    }
  }

  void _deleteModel(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.delete_model_title),
        content: Text(l10n.delete_model_body(model.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!context.mounted) return;

      final engineState = ref.read(onDeviceEngineProvider);
      final engineNotifier = ref.read(onDeviceEngineProvider.notifier);
      final selectedModelNotifier = ref.read(selectedModelProvider.notifier);

      if (engineState.loadedModelId == model.id) {
        await engineNotifier.unloadModel();
        if (!context.mounted) return;
        selectedModelNotifier.clear();
      }

      if (model.isImported) {
        await ref
            .read(importedGgufModelsProvider.notifier)
            .deleteModel(model.id);
      } else {
        // Use gemma service for non-imported models
        final gemmaService = ref.read(onDeviceGemmaServiceProvider);
        await gemmaService.deleteModel(model.id);
      }
      if (!context.mounted) return;
      ref.invalidate(downloadedModelsProvider);
    }
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(padding: const EdgeInsets.all(4), child: icon),
      ),
    );
  }
}
