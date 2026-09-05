import 'package:hugeicons/hugeicons.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/enums.dart';
import '../../../core/providers/app_providers.dart';
import '../../settings/data/models/app_settings.dart';
import '../data/kitten_tts_model.dart';
import '../data/piper_tts_model.dart';
import '../providers/tts_model_providers.dart';
import '../providers/tts_providers.dart' as tts;

class TtsModelManagerScreen extends ConsumerWidget {
  const TtsModelManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final topPadding = MediaQuery.of(context).padding.top;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: topPadding + 8,
            bottom: 16,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA),
            border: Border(
              bottom: BorderSide(
                color: isDark
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
              Text(
                l10n.tts_models_title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SystemEngineCard(
                isSelected: settings.ttsEngine == EngineId.system,
              ),
              const SizedBox(height: 16),
              _KittenEngineCard(
                isSelected: settings.ttsEngine == EngineId.kitten,
              ),
              const SizedBox(height: 16),
              _PiperEngineCard(
                isSelected: settings.ttsEngine == EngineId.piper,
              ),
              const SizedBox(height: 24),
              const _TtsTestSection(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}

// ── System Engine ──

class _SystemEngineCard extends ConsumerWidget {
  final bool isSelected;

  const _SystemEngineCard({required this.isSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final meta = EngineMeta.system;

    return _EngineCard(
      isSelected: isSelected,
      meta: meta,
      engine: EngineId.system,
      installed: true,
      statusText: l10n.always_available,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isSelected)
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: () => ref
                  .read(settingsProvider.notifier)
                  .setTtsEngine(EngineId.system),
              child: Text(l10n.select),
            ),
        ],
      ),
      child: _SystemVoicesList(),
    );
  }
}

class _SystemVoicesList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tts_system_desc,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          ShadAlert(
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedInformationCircle,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            description: Text(
              l10n.tts_other_services_background_note,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Kitten Engine ──

class _KittenEngineCard extends ConsumerWidget {
  final bool isSelected;

  const _KittenEngineCard({required this.isSelected});

  KittenTtsModel _selectedModel(AppSettings settings) {
    final variant = settings.kittenTtsModelVariant;
    return KittenTtsModel.allModels.firstWhere((m) => m.variant == variant);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);
    final meta = EngineMeta.kitten;
    final downloadedAsync = ref.watch(downloadedKittenTtsVariantsProvider);
    final downloadProgress = ref.watch(ttsDownloadProgressProvider);
    final model = _selectedModel(settings);
    final variantProgress = downloadProgress[model.variant];
    final isInstalled = downloadedAsync.when(
      data: (set) => set.contains(model.variant),
      loading: () => false,
      error: (_, _) => false,
    );
    final notifier = ref.read(ttsDownloadProgressProvider.notifier);
    final isDownloading = notifier.isDownloading(model.variant);

    return _EngineCard(
      isSelected: isSelected,
      meta: meta,
      engine: EngineId.kitten,
      installed: isInstalled,
      statusText: isInstalled
          ? l10n.installed
          : isDownloading
          ? l10n.downloading_status
          : l10n.not_installed,
      trailing: _buildAction(context, ref, isInstalled, isDownloading, model),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ShadBadge.secondary(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HugeIcon(
                    icon: HugeIcons.strokeRoundedMusicNote01,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.tts_supports_background,
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              l10n.tts_kitten_desc(_formatSize(model.totalSizeBytes)),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          if (isDownloading) ...[
            const SizedBox(height: 12),
            _buildVariantDownloadProgress(context, ref, model, variantProgress),
          ],
          if (isInstalled) ...[
            _VoiceChips(voices: kittenVoices, engine: EngineId.kitten),
          ],
        ],
      ),
    );
  }

  Widget _buildAction(
    BuildContext context,
    WidgetRef ref,
    bool isInstalled,
    bool isDownloading,
    KittenTtsModel model,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(ttsDownloadProgressProvider.notifier);
    if (isDownloading) {
      return ShadButton.outline(
        size: ShadButtonSize.sm,
        onPressed: () => notifier.cancelDownload(model.variant),
        child: Text(l10n.cancel),
      );
    }
    if (isInstalled) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isSelected)
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: () => ref
                  .read(settingsProvider.notifier)
                  .setTtsEngine(EngineId.kitten),
              child: Text(l10n.select),
            ),
          const SizedBox(width: 8),
          ShadIconButton.ghost(
            padding: EdgeInsets.zero,
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedDelete01,
              color: Colors.red,
              size: 20,
            ),
            onPressed: () => _confirmDelete(context, ref, model),
          ),
        ],
      );
    }
    return ShadButton.outline(
      size: ShadButtonSize.sm,
      onPressed: () => notifier.startDownload(model),
      child: Text(l10n.install),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    KittenTtsModel model,
  ) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.delete_model_title),
        content: Text(
          l10n.delete_model_body_with_size(
            model.displayName,
            _formatSize(model.totalSizeBytes),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(ttsDownloadProgressProvider.notifier)
                  .deleteVariant(model.variant);
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }

  Widget _buildVariantDownloadProgress(
    BuildContext context,
    WidgetRef ref,
    KittenTtsModel model,
    Map<String, KittenTtsFileProgress>? progress,
  ) {
    final fraction = ref
        .read(ttsDownloadProgressProvider.notifier)
        .getOverallFraction(model.variant);
    return Column(
      children: [
        LinearProgressIndicator(
          value: fraction,
          valueColor: AlwaysStoppedAnimation<Color>(
            Color(EngineMeta.kitten.accentColor),
          ),
          backgroundColor: Color(
            EngineMeta.kitten.accentColor,
          ).withValues(alpha: 0.15),
        ),
        const SizedBox(height: 4),
        if (progress != null)
          ...progress.entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.key,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  Text(
                    '${(e.value.fraction * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Piper Engine ──

class _PiperEngineCard extends ConsumerWidget {
  final bool isSelected;

  const _PiperEngineCard({required this.isSelected});

  PiperTtsModelVariant _selectedVariant(AppSettings settings) {
    final voiceId =
        voiceFromSettings(settings.ttsVoiceId, EngineId.piper)?.id ??
        piperVoices.first.id;
    return PiperTtsModelVariant.values.firstWhere(
      (variant) => variant.id == voiceId,
      orElse: () => PiperTtsModelVariant.enUsLessacMedium,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);
    final meta = EngineMeta.piper;
    final downloadedAsync = ref.watch(downloadedPiperTtsVariantsProvider);
    final downloadProgress = ref.watch(piperTtsDownloadProgressProvider);
    final notifier = ref.read(piperTtsDownloadProgressProvider.notifier);
    final selectedVariant = _selectedVariant(settings);
    final selectedVoice = piperVoices.firstWhere(
      (voice) => voice.id == selectedVariant.id,
      orElse: () => piperVoices.first,
    );
    final downloadedSet = downloadedAsync.when(
      data: (set) => set,
      loading: () => <PiperTtsModelVariant>{},
      error: (_, _) => <PiperTtsModelVariant>{},
    );
    final installedVoices = piperVoices
        .where(
          (voice) => downloadedSet.any((variant) => variant.id == voice.id),
        )
        .toList();
    final variantProgress = downloadProgress[selectedVariant];
    final isInstalled = downloadedSet.contains(selectedVariant);
    final isDownloading = notifier.isDownloading(selectedVariant);

    return _EngineCard(
      isSelected: isSelected,
      meta: meta,
      engine: EngineId.piper,
      installed: installedVoices.isNotEmpty,
      statusText: isInstalled
          ? l10n.installed
          : isDownloading
          ? l10n.downloading_status
          : l10n.not_installed,
      trailing: _buildAction(
        context,
        ref,
        selectedVariant,
        selectedVoice,
        isInstalled,
        isDownloading,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ShadBadge.secondary(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HugeIcon(
                    icon: HugeIcons.strokeRoundedMusicNote01,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.tts_supports_background,
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              l10n.tts_piper_desc(_formatSize(selectedVariant.totalSizeBytes)),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PiperTtsModelVariant.values
                .map(
                  (variant) => _PiperVariantChip(
                    variant: variant,
                    voice: piperVoices.firstWhere(
                      (voice) => voice.id == variant.id,
                      orElse: () => selectedVoice,
                    ),
                    selected: selectedVariant == variant,
                    installed: downloadedSet.contains(variant),
                    onTap: () => ref
                        .read(settingsProvider.notifier)
                        .setTtsVoiceId(variant.id),
                  ),
                )
                .toList(),
          ),
          if (isDownloading) ...[
            const SizedBox(height: 12),
            _buildVariantDownloadProgress(
              context,
              ref,
              selectedVariant,
              variantProgress,
            ),
          ],
          if (installedVoices.isNotEmpty) ...[
            _VoiceChips(voices: installedVoices, engine: EngineId.piper),
          ],
        ],
      ),
    );
  }

  Widget _buildAction(
    BuildContext context,
    WidgetRef ref,
    PiperTtsModelVariant variant,
    Voice voice,
    bool isInstalled,
    bool isDownloading,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(piperTtsDownloadProgressProvider.notifier);
    if (isDownloading) {
      return ShadButton.outline(
        size: ShadButtonSize.sm,
        onPressed: () => notifier.cancelDownload(variant),
        child: Text(l10n.cancel),
      );
    }
    if (isInstalled) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isSelected)
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: () {
                ref.read(settingsProvider.notifier).setTtsVoiceId(voice.id);
                ref
                    .read(settingsProvider.notifier)
                    .setTtsEngine(EngineId.piper);
              },
              child: Text(l10n.select),
            ),
          const SizedBox(width: 8),
          ShadIconButton.ghost(
            padding: EdgeInsets.zero,
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedDelete01,
              color: Colors.red,
              size: 20,
            ),
            onPressed: () => _confirmDelete(context, ref, variant),
          ),
        ],
      );
    }
    return ShadButton.outline(
      size: ShadButtonSize.sm,
      onPressed: () => notifier.startDownload(variant),
      child: Text(l10n.install),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    PiperTtsModelVariant variant,
  ) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.delete_voice_title),
        content: Text(
          l10n.delete_voice_body(
            variant.displayName,
            _formatSize(variant.totalSizeBytes),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(piperTtsDownloadProgressProvider.notifier)
                  .deleteVariant(variant);
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }

  Widget _buildVariantDownloadProgress(
    BuildContext context,
    WidgetRef ref,
    PiperTtsModelVariant variant,
    Map<String, PiperTtsFileProgress>? progress,
  ) {
    final fraction = ref
        .read(piperTtsDownloadProgressProvider.notifier)
        .getOverallFraction(variant);
    return Column(
      children: [
        LinearProgressIndicator(
          value: fraction,
          valueColor: AlwaysStoppedAnimation<Color>(
            Color(EngineMeta.piper.accentColor),
          ),
          backgroundColor: Color(
            EngineMeta.piper.accentColor,
          ).withValues(alpha: 0.15),
        ),
        const SizedBox(height: 4),
        if (progress != null)
          ...progress.entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.key,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  Text(
                    '${(e.value.fraction * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PiperVariantChip extends StatelessWidget {
  final PiperTtsModelVariant variant;
  final Voice voice;
  final bool selected;
  final bool installed;
  final VoidCallback onTap;

  const _PiperVariantChip({
    required this.variant,
    required this.voice,
    required this.selected,
    required this.installed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final accent = Color(EngineMeta.piper.accentColor);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.2,
                ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.45)
                : installed
                ? Colors.green.withValues(alpha: 0.35)
                : theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              voice.name,
              style: theme.textTheme.labelSmall?.copyWith(
                color: selected ? accent : theme.colorScheme.onSurface,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              variant.id.contains('ryan') ? l10n.voice_male : l10n.voice_female,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontWeight: FontWeight.w500,
              ),
            ),
            if (installed) ...[
              const SizedBox(width: 6),
              const HugeIcon(
                icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                size: 14,
                color: Colors.green,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Shared Widgets ──

class _EngineCard extends StatelessWidget {
  final bool isSelected;
  final EngineMeta meta;
  final EngineId engine;
  final bool installed;
  final String statusText;
  final Widget? trailing;
  final Widget? child;

  const _EngineCard({
    required this.isSelected,
    required this.meta,
    required this.engine,
    required this.installed,
    required this.statusText,
    this.trailing,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final accentColor = Color(meta.accentColor);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? accentColor.withValues(alpha: 0.6)
              : installed
              ? Colors.green.withValues(alpha: 0.3)
              : theme.colorScheme.outline.withValues(alpha: 0.3),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedVoice,
                  size: 18,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      meta.tagline,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    statusText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: installed
                          ? Colors.green
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.engine_spec(
                      meta.sizeMb.toString(),
                      meta.ramMb.toString(),
                      meta.voiceCount,
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (isSelected)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    l10n.active,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accentColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ?trailing,
            ],
          ),
          ?child,
        ],
      ),
    );
  }
}

class _VoiceChips extends ConsumerStatefulWidget {
  final List<Voice> voices;
  final EngineId engine;

  const _VoiceChips({required this.voices, required this.engine});

  @override
  ConsumerState<_VoiceChips> createState() => _VoiceChipsState();
}

class _VoiceChipsState extends ConsumerState<_VoiceChips> {
  Voice? _playingVoice;

  @override
  Widget build(BuildContext context) {
    ref.listen<tts.TtsState>(tts.ttsProvider, (previous, next) {
      if (!next.isSpeaking && (previous?.isSpeaking ?? false)) {
        if (mounted && _playingVoice != null) {
          setState(() => _playingVoice = null);
        }
      }
    });

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final selectedVoiceId = widget.engine == settings.ttsEngine
        ? settings.ttsVoiceId
        : null;
    final females = widget.voices.where((v) => v.gender == 'f').toList();
    final males = widget.voices.where((v) => v.gender == 'm').toList();
    final accent = Color(EngineMeta.forEngine(widget.engine).accentColor);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (males.isNotEmpty) ...[
            Text(
              l10n.voice_male,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: males
                    .map(
                      (v) => Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: _voiceChip(
                          context,
                          v,
                          theme,
                          accent,
                          selectedVoiceId,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (females.isNotEmpty) ...[
            Text(
              l10n.voice_female,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: females
                    .map(
                      (v) => Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: _voiceChip(
                          context,
                          v,
                          theme,
                          accent,
                          selectedVoiceId,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _voiceChip(
    BuildContext context,
    Voice voice,
    ThemeData theme,
    Color accent,
    String? selectedVoiceId,
  ) {
    final isPlaying = _playingVoice == voice;
    final isSelected = voice.id == selectedVoiceId;

    return Material(
      color: Colors.transparent,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.green.withValues(alpha: 0.1)
              : isPlaying
              ? accent.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Colors.green.withValues(alpha: 0.5)
                : isPlaying
                ? accent.withValues(alpha: 0.3)
                : theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => _selectVoice(voice),
              borderRadius: BorderRadiusDirectional.horizontal(
                start: const Radius.circular(20),
              ).resolve(Directionality.of(context)),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 12,
                  end: 8,
                  top: 8,
                  bottom: 8,
                ),
                child: Row(
                  children: [
                    if (isSelected) ...[
                      const HugeIcon(
                        icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                        size: 16,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      voice.name,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isSelected
                            ? Colors.green
                            : isPlaying
                            ? accent
                            : theme.colorScheme.onSurface,
                        fontWeight: isSelected || isPlaying
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 1,
              height: 20,
              color: isSelected
                  ? Colors.green.withValues(alpha: 0.3)
                  : isPlaying
                  ? accent.withValues(alpha: 0.2)
                  : theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
            InkWell(
              onTap: () => _previewVoice(voice),
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: HugeIcon(
                  icon: isPlaying
                      ? HugeIcons.strokeRoundedStop
                      : HugeIcons.strokeRoundedPlay,
                  size: 16,
                  color: isPlaying
                      ? accent
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectVoice(Voice voice) {
    ref.read(settingsProvider.notifier).setTtsVoiceId(voice.id);
  }

  Future<void> _previewVoice(Voice voice) async {
    final l10n = AppLocalizations.of(context)!;
    if (_playingVoice == voice) {
      await ref.read(tts.ttsProvider.notifier).stop();
      if (!mounted) return;
      setState(() => _playingVoice = null);
      return;
    }
    try {
      if (!mounted) return;
      setState(() => _playingVoice = voice);
      await ref.read(tts.ttsProvider.notifier).previewVoice(voice);
    } catch (e) {
      if (!mounted) return;
      setState(() => _playingVoice = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.preview_failed(e.toString()))),
      );
    }
  }
}

class _TtsTestSection extends ConsumerStatefulWidget {
  const _TtsTestSection();

  @override
  ConsumerState<_TtsTestSection> createState() => _TtsTestSectionState();
}

class _TtsTestSectionState extends ConsumerState<_TtsTestSection> {
  final _controller = TextEditingController(
    text:
        'The quick brown fox jumps over the lazy dog. '
        'This is a longer sample to test how the selected text-to-speech engine handles extended passages.',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _speak() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    try {
      await ref.read(tts.ttsProvider.notifier).speak(text);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.test_tts_section_title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          maxLines: 6,
          minLines: 4,
          decoration: InputDecoration(
            hintText: l10n.test_tts_hint,
            filled: true,
            fillColor: isDark
                ? const Color(0xFF1A1A1A)
                : const Color(0xFFF5F5F5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ShadButton(
                onPressed: _speak,
                leading: const HugeIcon(icon: HugeIcons.strokeRoundedVolumeUp),
                child: Text(l10n.test_speak_button),
              ),
            ),
            const SizedBox(width: 8),
            ShadButton.outline(
              onPressed: () => ref.read(tts.ttsProvider.notifier).stop(),
              leading: const HugeIcon(icon: HugeIcons.strokeRoundedStop),
              child: Text(l10n.stop),
            ),
          ],
        ),
      ],
    );
  }
}
