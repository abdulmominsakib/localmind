import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'metadata_chip.dart';

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
  final String? note;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;

    return InkWell(
      onTap: isLoading ? null : onTap,
      onLongPress: isLoading ? null : onLongPress,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isFavorite) ...[
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedStar,
                              size: 16,
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
                                color: isDark ? Colors.white : Colors.black,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (note != null && note!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          note!,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkMutedText
                                : AppColors.lightMutedText,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (model.parameterCountDisplay != null &&
                              model.parameterCountDisplay!.isNotEmpty)
                            MetadataChip(
                              label: model.parameterCountDisplay!,
                              isDark: isDark,
                            ),
                          if (model.quantization != null &&
                              model.quantization!.isNotEmpty)
                            MetadataChip(
                              label: model.quantization!,
                              isDark: isDark,
                            ),
                          if (model.formattedSize != null &&
                              model.formattedSize!.isNotEmpty)
                            MetadataChip(
                              label: model.formattedSize!,
                              isDark: isDark,
                            ),
                          if (model.contextLength != null)
                            MetadataChip(
                              label: l10n.context_chip(
                                model.contextLength.toString(),
                              ),
                              isDark: isDark,
                            ),
                        ],
                      ),
                      if (model.supportsReasoning)
                        InlineThinkingSelector(
                          isDark: isDark,
                          isSelected: isSelected,
                          onSelectModel: onTap,
                        ),
                    ],
                  ),
                ),
                if ((model.serverType == ServerType.lmStudio ||
                        model.serverType == ServerType.ollama) &&
                    isLoaded) ...[
                  IconButton(
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedPower,
                      size: 18,
                      color: Colors.red[400],
                    ),
                    onPressed: onUnload,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: l10n.unload_from_server,
                  ),
                  const SizedBox(width: 8),
                ],
                if (model.supportsVision ||
                    model.supportsReasoning ||
                    model.supportsToolUse) ...[
                  const SizedBox(width: 8),
                  _ModelCapabilityIcons(model: model, isDark: isDark),
                ],
                if (isSelected) ...[
                  const SizedBox(width: 4),
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                    color: accent,
                    size: 22,
                  ),
                ] else if (!isLoading)
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowRight01,
                    size: 20,
                    color: isDark
                        ? AppColors.darkMutedText
                        : AppColors.lightMutedText,
                  ),
              ],
            ),
            if (isLoading) ...[
              const SizedBox(height: 8),
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
