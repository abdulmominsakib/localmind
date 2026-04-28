import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/enums.dart';
import '../../../core/providers/app_providers.dart';
import '../../sidebar/sidebar_widget.dart';
import '../data/kitten_tts_model.dart';
import '../data/kitten_tts_service.dart';
import '../providers/tts_model_providers.dart';

class TtsModelManagerScreen extends ConsumerWidget {
  const TtsModelManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final models = ref.watch(kittenTtsModelsProvider);
    final downloadedAsync = ref.watch(downloadedKittenTtsVariantsProvider);
    final downloadProgress = ref.watch(ttsDownloadProgressProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      drawer: const SidebarWidget(),
      appBar: AppBar(title: const Text('Kitten TTS Models')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Available Models',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Download a KittenTTS model to use neural text-to-speech. '
            'Models are stored locally on your device.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          ...models.map(
            (model) => _ModelVariantCard(
              model: model,
              isSelected: settings.kittenTtsModelVariant == model.variant,
              isDownloaded: downloadedAsync.when(
                data: (set) => set.contains(model.variant),
                loading: () => false,
                error: (_, _) => false,
              ),
              progress: downloadProgress[model.variant],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ModelVariantCard extends ConsumerStatefulWidget {
  const _ModelVariantCard({
    required this.model,
    required this.isSelected,
    required this.isDownloaded,
    this.progress,
  });

  final KittenTtsModel model;
  final bool isSelected;
  final bool isDownloaded;
  final Map<String, KittenTtsFileProgress>? progress;

  @override
  ConsumerState<_ModelVariantCard> createState() => _ModelVariantCardState();
}

class _ModelVariantCardState extends ConsumerState<_ModelVariantCard> {
  bool _showPreview = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDownloading =
        widget.progress != null &&
        widget.progress!.isNotEmpty &&
        !widget.progress!.values.every((f) => f.isComplete);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : widget.isDownloaded
                ? Colors.green.withValues(alpha: 0.3)
                : theme.colorScheme.outline.withValues(alpha: 0.3),
            width: widget.isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.model.displayName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (widget.model.isRecommended)
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
              widget.model.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  _formatBytes(widget.model.totalSizeBytes),
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(width: 12),
                Text(
                  '${widget.model.parameterLabel} params',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const Spacer(),
                if (widget.isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'Selected',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _buildActionRow(isDownloading),
            if (isDownloading) ...[
              const SizedBox(height: 12),
              _buildFileProgress(),
            ],
            if (widget.isDownloaded) ...[
              const SizedBox(height: 12),
              _buildPreviewToggle(),
              if (_showPreview) ...[
                const SizedBox(height: 8),
                _VoicePreviewSection(variant: widget.model.variant),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(bool isDownloading) {
    if (widget.isDownloaded) {
      return Row(
        children: [
          Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 18,
          ),
          const SizedBox(width: 4),
          Text(
            'Downloaded',
            style: TextStyle(
              fontSize: 13,
              color: Colors.green,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (!widget.isSelected)
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: () {
                ref
                    .read(settingsProvider.notifier)
                    .setKittenTtsModelVariant(widget.model.variant);
              },
              child: const Text('Select'),
            ),
          if (!widget.isSelected) const SizedBox(width: 8),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: () => _deleteModel(),
            child: const Text('Delete'),
          ),
        ],
      );
    }

    if (isDownloading) {
      final overallFraction = ref
          .read(ttsDownloadProgressProvider.notifier)
          .getOverallFraction(widget.model.variant);

      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: overallFraction,
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                ),
                const SizedBox(height: 6),
                Text(
                  '${(overallFraction * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: () {
              ref
                  .read(ttsDownloadProgressProvider.notifier)
                  .cancelDownload(widget.model.variant);
            },
            child: const Text('Cancel'),
          ),
        ],
      );
    }

    return Row(
      children: [
        const Spacer(),
        ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: () => _startDownload(),
          child: const Text('Download'),
        ),
      ],
    );
  }

  Widget _buildFileProgress() {
    if (widget.progress == null || widget.progress!.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.progress!.entries.map((entry) {
        final fileName = entry.key;
        final progress = entry.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  fileName,
                  style: theme.textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LinearProgressIndicator(
                  value: progress.fraction,
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.1),
                  minHeight: 4,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 50,
                child: Text(
                  progress.isComplete
                      ? 'Done'
                      : '${(progress.fraction * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPreviewToggle() {
    return InkWell(
      onTap: () => setState(() => _showPreview = !_showPreview),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              _showPreview ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              'Voice Preview',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startDownload() async {
    await ref
        .read(ttsDownloadProgressProvider.notifier)
        .startDownload(widget.model);
  }

  Future<void> _deleteModel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Model'),
        content: Text(
          'Are you sure you want to delete ${widget.model.displayName}?',
        ),
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
      await ref
          .read(ttsDownloadProgressProvider.notifier)
          .deleteVariant(widget.model.variant);

      final settings = ref.read(settingsProvider);
      if (settings.kittenTtsModelVariant == widget.model.variant) {
        ref
            .read(settingsProvider.notifier)
            .setKittenTtsModelVariant(KittenTtsModelVariant.nanoInt8);
      }
    }
  }

  String _formatBytes(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(0)} MB';
  }
}

/// Section that lists all voices with play buttons for the downloaded variant.
class _VoicePreviewSection extends ConsumerStatefulWidget {
  const _VoicePreviewSection({required this.variant});

  final KittenTtsModelVariant variant;

  @override
  ConsumerState<_VoicePreviewSection> createState() =>
      _VoicePreviewSectionState();
}

class _VoicePreviewSectionState extends ConsumerState<_VoicePreviewSection> {
  KittenTtsService? _previewService;
  AudioPlayer? _audioPlayer;
  KittenTtsVoice? _playingVoice;
  bool _isLoading = false;

  @override
  void dispose() {
    _audioPlayer?.dispose();
    _previewService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tap a voice to hear a preview',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: KittenTtsVoice.values.map((voice) {
              final isPlaying = _playingVoice == voice;
              return ActionChip(
                avatar: Icon(
                  isPlaying ? Icons.stop : Icons.play_arrow,
                  size: 18,
                  color: isPlaying
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                label: Text(voice.displayName),
                labelStyle: theme.textTheme.labelMedium?.copyWith(
                  color: isPlaying
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                  fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                ),
                backgroundColor: isPlaying
                    ? theme.colorScheme.primary.withValues(alpha: 0.1)
                    : theme.colorScheme.surface,
                side: BorderSide(
                  color: isPlaying
                      ? theme.colorScheme.primary.withValues(alpha: 0.3)
                      : theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
                onPressed: _isLoading && !isPlaying
                    ? null
                    : () => _togglePreview(voice),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePreview(KittenTtsVoice voice) async {
    if (_playingVoice == voice) {
      await _audioPlayer?.stop();
      setState(() => _playingVoice = null);
      return;
    }

    setState(() {
      _isLoading = true;
      _playingVoice = null;
    });

    try {
      if (_previewService == null ||
          _previewService!.currentVariant != widget.variant) {
        _previewService?.dispose();
        _previewService = KittenTtsService();
        await _previewService!.initialize(variant: widget.variant);
      }

      _audioPlayer ??= AudioPlayer();
      await _audioPlayer!.stop();

      final sampleText =
          "Hello, I am ${voice.displayName}. It's a pleasure to meet you.";
      final wavBytes = await _previewService!.generatePreviewWav(
        sampleText,
        voice: voice,
        speed: 1.0,
      );

      setState(() => _playingVoice = voice);

      await _audioPlayer!.play(BytesSource(wavBytes));
      _audioPlayer!.onPlayerComplete.first.then((_) {
        if (mounted) {
          setState(() => _playingVoice = null);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preview failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
