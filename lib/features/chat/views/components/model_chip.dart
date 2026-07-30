import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/l10n/app_localizations.dart';

/// Compact model picker chip that lives inside the chat input bar.
///
/// Shows the active model's display name (or a "Select model" placeholder
/// when none is set) and opens the model picker bottom sheet on tap.
/// Designed as a pure text pill — no leading icon — to keep the bottom
/// action row visually quiet.
class ModelChip extends StatelessWidget {
  const ModelChip({
    super.key,
    required this.model,
    required this.onTap,
    required this.enabled,
  });

  final ModelInfo? model;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final hasModel = model != null;
    final fg = hasModel
        ? (isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText)
        : (isDark ? AppColors.darkMutedText : AppColors.lightMutedText);
    final bg = hasModel
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : (isDark
              ? AppColors.darkSurfaceInput
              : AppColors.lightSurface.withValues(alpha: 0.0));
    final borderColor = hasModel
        ? theme.colorScheme.primary.withValues(alpha: 0.4)
        : (isDark ? AppColors.darkBorder : AppColors.lightBorder);

    final label = hasModel ? model!.displayName : l10n.select_model_prompt;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          // Constrain the pill itself instead of the entire action row. This
          // lets longer model names be readable while Flexible in the parent
          // row still protects the fixed-size action buttons on the right.
          constraints: const BoxConstraints(minWidth: 0, maxWidth: 280),
          padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 10, 6),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              HugeIcon(
                icon: HugeIcons.strokeRoundedArrowDown01,
                size: 12,
                color: fg.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
