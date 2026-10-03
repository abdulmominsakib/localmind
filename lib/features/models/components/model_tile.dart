import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/l10n/app_localizations.dart';

import 'inline_thinking_selector.dart';

class ModelTile extends StatelessWidget {
  const ModelTile({
    super.key,
    required this.model,
    required this.isSelected,
    required this.isLoaded,
    required this.isDark,
    required this.onTap,
    this.onLongPress,
    this.onUnload,
    this.isFavorite = false,
    this.isDefault = false,
    this.note,
    this.isLoading = false,
  });

  final ModelInfo model;
  final bool isSelected;
  final bool isLoaded;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Future<void> Function()? onUnload;
  final bool isFavorite;
  final bool isDefault;
  final String? note;
  final bool isLoading;

  /// Compact context size: 128000 → "128K", 131072 → "128K".
  static String compactContext(int tokens) {
    if (tokens >= 1000 && tokens % 1000 == 0) return '${tokens ~/ 1000}K';
    if (tokens >= 1024 && tokens % 1024 == 0) return '${tokens ~/ 1024}K';
    return '$tokens';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;
    final isPaidCloud =
        (model.serverType == ServerType.openRouter ||
            model.serverType == ServerType.requesty) &&
        model.pricingLabel != null;
    final showLoadedState =
        (model.serverType == ServerType.lmStudio ||
            model.serverType == ServerType.ollama) &&
        isLoaded;

    // One quiet line of facts instead of a row of boxed chips.
    final details = [
      if (model.parameterCountDisplay?.isNotEmpty ?? false)
        model.parameterCountDisplay!,
      if (model.quantization?.isNotEmpty ?? false) model.quantization!,
      if (model.formattedSize?.isNotEmpty ?? false) model.formattedSize!,
      if (model.contextLength != null)
        l10n.context_chip(compactContext(model.contextLength!)),
      if (isPaidCloud)
        model.isPricingFree
            ? l10n.openrouter_pricing_free
            : model.pricingLabel!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isSelected
            ? accent.withValues(alpha: isDark ? 0.08 : 0.04)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected
                ? accent.withValues(alpha: isDark ? 0.5 : 0.35)
                : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('model_tile_${model.id}'),
          onTap: isLoading ? null : onTap,
          onLongPress: isLoading ? null : onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (isFavorite) ...[
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedStar,
                        size: 15,
                        color: Colors.amber[600],
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        model.displayName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isDark
                              ? AppColors.darkPrimaryText
                              : AppColors.lightPrimaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isDefault) ...[
                      const SizedBox(width: 8),
                      ModelTileBadge(
                        label: l10n.model_default_badge,
                        isDark: isDark,
                      ),
                    ],
                    if (isSelected) ...[
                      const SizedBox(width: 8),
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedCheckmarkCircle02,
                        size: 20,
                        color: accent,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (details.isNotEmpty)
                      Flexible(
                        child: Text(
                          details,
                          style: TextStyle(fontSize: 12.5, color: muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (model.supportsVision ||
                        model.supportsReasoning ||
                        model.supportsToolUse) ...[
                      const SizedBox(width: 6),
                      _ModelCapabilityIcons(model: model, isDark: isDark),
                    ],
                  ],
                ),
                if (note != null && note!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    note!,
                    style: TextStyle(fontSize: 12, color: muted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (showLoadedState)
                  ModelLoadedRow(isDark: isDark, onUnload: onUnload),
                if (model.supportsReasoning)
                  InlineThinkingSelector(
                    isDark: isDark,
                    isSelected: isSelected,
                    onSelectModel: onTap,
                    supportedEfforts: model.supportedReasoningEfforts,
                    reasoningMandatory: model.reasoningMandatory,
                  ),
                if (isLoading) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: accent.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ModelTileBadge extends StatelessWidget {
  const ModelTileBadge({super.key, required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      ),
    );
  }
}

/// "● Loaded" with an Unload action, replacing the bare CPU and power
/// icons a loaded model used to show.
class ModelLoadedRow extends StatelessWidget {
  const ModelLoadedRow({super.key, required this.isDark, this.onUnload});

  final bool isDark;
  final Future<void> Function()? onUnload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final green = isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: green, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            l10n.model_loaded_status,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: green,
            ),
          ),
          const Spacer(),
          if (onUnload != null)
            Tooltip(
              message: l10n.unload_from_server,
              child: TextButton(
                key: const ValueKey('model_tile_unload'),
                onPressed: onUnload,
                style: TextButton.styleFrom(
                  foregroundColor: isDark
                      ? Colors.red[300]
                      : const Color(0xFFB91C1C),
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                child: Text(l10n.unload),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModelCapabilityIcons extends StatelessWidget {
  const _ModelCapabilityIcons({required this.model, required this.isDark});

  final ModelInfo model;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (model.supportsVision)
          _CapabilityIcon(
            icon: HugeIcons.strokeRoundedEye,
            tooltip: l10n.lm_studio_vision,
            color: color,
          ),
        if (model.supportsReasoning)
          _CapabilityIcon(
            icon: HugeIcons.strokeRoundedBrain,
            tooltip: l10n.lm_studio_reasoning,
            color: color,
          ),
        if (model.supportsToolUse)
          _CapabilityIcon(
            icon: HugeIcons.strokeRoundedTools,
            tooltip: l10n.lm_studio_tool_use,
            color: color,
          ),
      ],
    );
  }
}

class _CapabilityIcon extends StatelessWidget {
  const _CapabilityIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
  });

  final List<List<dynamic>> icon;
  final String tooltip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tooltip,
        child: HugeIcon(icon: icon, size: 14, color: color),
      ),
    );
  }
}
