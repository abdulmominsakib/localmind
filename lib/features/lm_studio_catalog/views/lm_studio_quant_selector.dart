import 'package:flutter/material.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/l10n/app_localizations.dart';

import '../data/catalog_models.dart';
import '../utils/download_matching.dart';
import '../utils/memory_compatibility.dart';

class LmStudioQuantSelector extends StatefulWidget {
  const LmStudioQuantSelector({
    super.key,
    required this.quants,
    required this.selected,
    required this.onSelected,
    required this.serverRamGb,
    required this.serverVramGb,
    required this.downloadedModels,
    required this.modelCapabilities,
  });

  final List<LmModelQuantOption> quants;
  final LmModelQuantOption? selected;
  final ValueChanged<LmModelQuantOption> onSelected;
  final int? serverRamGb;
  final int? serverVramGb;
  final List<ModelInfo> downloadedModels;
  final LmCatalogModel modelCapabilities;

  @override
  State<LmStudioQuantSelector> createState() => _LmStudioQuantSelectorState();
}

class _LmStudioQuantSelectorState extends State<LmStudioQuantSelector> {
  bool _expanded = false;

  bool _isDownloaded(LmModelQuantOption quant) {
    return isQuantDownloaded(
      model: widget.modelCapabilities,
      quant: quant,
      downloadedModels: widget.downloadedModels,
    );
  }

  MemoryCompatibility _compat(LmModelQuantOption quant) {
    return estimateMemoryCompatibility(
      modelSizeBytes: quant.sizeBytes,
      availableRamGb: widget.serverRamGb,
      availableVramGb: widget.serverVramGb,
    );
  }

  Widget _compatBadge(MemoryCompatibility compatibility, AppLocalizations l10n) {
    if (compatibility == MemoryCompatibility.unknown) {
      return const SizedBox.shrink();
    }

    late final String label;
    late final Color color;
    late final IconData icon;

    switch (compatibility) {
      case MemoryCompatibility.fullGpuOffload:
        label = l10n.lm_studio_full_gpu_offload;
        color = Colors.green;
        icon = Icons.rocket_launch_outlined;
      case MemoryCompatibility.partialGpuOffload:
        label = l10n.lm_studio_partial_gpu_offload;
        color = Colors.blue;
        icon = Icons.memory_outlined;
      case MemoryCompatibility.likelyTooLarge:
        label = l10n.lm_studio_likely_too_large;
        color = Colors.red;
        icon = Icons.cancel_outlined;
      case MemoryCompatibility.unknown:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selected = widget.selected ?? widget.quants.first;
    final recommended = LmModelQuantOption.recommended(widget.quants);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              child: Row(
                children: [
                  _GgufTag(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${selected.quantization} · ${formatBytes(selected.sizeBytes)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.hintColor,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Row(
                    children: [
                      Text(
                        l10n.lm_studio_choose_quant,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (recommended != null)
                        TextButton(
                          onPressed: () {
                            widget.onSelected(recommended);
                          },
                          child: Text(l10n.lm_studio_use_default_quant),
                        ),
                    ],
                  ),
                ),
                ...widget.quants.map((quant) {
                  final isSelected = quant.fileName == selected.fileName;
                  final downloaded = _isDownloaded(quant);
                  final compat = _compat(quant);
                  final isRecommended =
                      recommended != null && quant.fileName == recommended.fileName;
                  return Material(
                    color: isSelected
                        ? (isDark ? AppColors.darkAccent : AppColors.lightAccent)
                            .withValues(alpha: 0.12)
                        : Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        widget.onSelected(quant);
                        setState(() => _expanded = false);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              size: 18,
                              color: isSelected
                                  ? (isDark
                                      ? AppColors.darkAccent
                                      : AppColors.lightAccent)
                                  : theme.hintColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      _GgufTag(compact: true),
                                      Text(
                                        quant.quantization,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(fontWeight: FontWeight.w600),
                                      ),
                                      if (widget.modelCapabilities.metadata.vision)
                                        _CapIcon(Icons.visibility_outlined, Colors.amber),
                                      if (widget.modelCapabilities.metadata.reasoning)
                                        _CapIcon(Icons.psychology_outlined, Colors.green),
                                      if (widget.modelCapabilities.metadata.trainedForToolUse)
                                        _CapIcon(Icons.build_outlined, Colors.blue),
                                      if (isRecommended) _RecommendedTag(l10n: l10n),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    quant.fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 6),
                                  _compatBadge(compat, l10n),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  formatBytes(quant.sizeBytes),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (downloaded) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check, size: 14, color: Colors.green.shade400),
                                      const SizedBox(width: 2),
                                      Text(
                                        l10n.downloaded,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.green.shade400,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _GgufTag extends StatelessWidget {
  const _GgufTag({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 6,
        vertical: compact ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.35)),
      ),
      child: Text(
        'GGUF',
        style: TextStyle(
          color: Colors.blue.shade300,
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CapIcon extends StatelessWidget {
  const _CapIcon(this.icon, this.color);

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: 14, color: color);
  }
}

class _RecommendedTag extends StatelessWidget {
  const _RecommendedTag({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Text(
        l10n.lm_studio_recommended,
        style: TextStyle(
          color: Colors.amber.shade700,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Collect downloaded models from server catalog for download detection.
List<ModelInfo> downloadedModelsList(List<dynamic> models) {
  return models.whereType<ModelInfo>().toList();
}
