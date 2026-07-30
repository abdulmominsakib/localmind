import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/providers/chat_reasoning_providers.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/l10n/app_localizations.dart';

/// Compact, two-part chip used to toggle and configure the reasoning
/// ("thinking") mode for the actively selected model.
///
/// • Left side: tap toggles thinking on / off.
/// • Right side: opens a popup to choose the effort level (Low / Medium /
///   High). The picker collapses to a single tap-toggle button when
///   thinking is disabled, since effort is irrelevant in that state.
///
/// Rendered as a [ConsumerWidget] so both surfaces (the model picker
/// sheet and the chat input bar) stay perfectly in sync with the
/// underlying [chatReasoningConfigProvider].
class ThinkingModeChip extends ConsumerWidget {
  const ThinkingModeChip({
    super.key,
    required this.model,
    required this.isDark,
    this.compact = false,
    this.fullWidth = false,
  });

  /// When `null` or a model that doesn't support reasoning is passed the
  /// chip returns [SizedBox.shrink] so callers can drop it into any layout
  /// without conditionals.
  final ModelInfo? model;

  /// Theme context used for the on- / off-state colors.
  final bool isDark;

  /// When true, uses a slightly tighter horizontal padding so the chip
  /// fits comfortably inside the chat input bar's action row.
  final bool compact;

  /// When true, the chip will occupy the full available width instead of
  /// hugging its contents. Used by the model picker header so the chip
  /// sits flush under the title.
  final bool fullWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supportsReasoning = model?.supportsReasoning ?? false;
    if (!supportsReasoning) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final config = ref.watch(chatReasoningConfigProvider);
    final notifier = ref.read(chatReasoningConfigProvider.notifier);

    final accent = theme.colorScheme.primary;
    final enabledFg = accent;
    final disabledFg = isDark
        ? AppColors.darkMutedText
        : AppColors.lightMutedText;
    final fgColor = config.enabled ? enabledFg : disabledFg;
    final bgColor = config.enabled
        ? accent.withValues(alpha: 0.15)
        : theme.colorScheme.onSurface.withValues(alpha: 0.06);
    final borderColor = config.enabled
        ? accent.withValues(alpha: 0.4)
        : (isDark ? AppColors.darkBorder : AppColors.lightBorder);

    final hPad = compact ? 10.0 : 12.0;
    final vPad = compact ? 6.0 : 8.0;
    final borderRadius = BorderRadius.circular(999);

    final labelText = fullWidth
        ? l10n.thinking_mode_title
        : l10n.think_button_label;

    final toggleSide = InkWell(
      onTap: () {
        notifier.setEnabled(!config.enabled);
      },
      borderRadius: borderRadius,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(hPad, vPad, hPad, vPad),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedBrain,
              size: compact ? 14 : 16,
              color: fgColor,
            ),
            SizedBox(width: compact ? 4 : 6),
            Flexible(
              child: Text(
                labelText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w600,
                  color: fgColor,
                ),
              ),
            ),
            if (config.enabled) ...[
              SizedBox(width: compact ? 4 : 6),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 6 : 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _effortShortLabel(l10n, config.effort),
                  style: TextStyle(
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w700,
                    color: enabledFg,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    // Right-side effort picker. Hidden when thinking is off because the
    // choice has no effect — the entire chip is then a single tap toggle.
    Widget pickerSide = const SizedBox.shrink();
    if (config.enabled) {
      pickerSide = PopupMenuButton<ReasoningEffort>(
        tooltip: '',
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        onSelected: (effort) {
          notifier.setEnabled(true);
          notifier.setEffort(effort);
        },
        itemBuilder: (context) => ReasoningEffort.values
            .map(
              (effort) => PopupMenuItem(
                value: effort,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HugeIcon(
                      icon: effort == config.effort
                          ? HugeIcons.strokeRoundedTick01
                          : HugeIcons.strokeRoundedSquare01,
                      size: 16,
                      color: effort == config.effort
                          ? accent
                          : Colors.transparent,
                    ),
                    const SizedBox(width: 8),
                    Text(_effortShortLabel(l10n, effort)),
                  ],
                ),
              ),
            )
            .toList(),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(2, vPad, hPad, vPad),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedArrowDown01,
                size: compact ? 12 : 14,
                color: fgColor.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      );
    }

    final chip = Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor),
          borderRadius: borderRadius,
        ),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: fullWidth
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.start,
          children: [
            // Toggle side: flexes to absorb available width when [fullWidth]
            // is true, but stays hugging its content otherwise.
            if (fullWidth) Expanded(child: toggleSide) else toggleSide,
            pickerSide,
          ],
        ),
      ),
    );

    return fullWidth ? SizedBox(width: double.infinity, child: chip) : chip;
  }

  static String _effortShortLabel(
    AppLocalizations l10n,
    ReasoningEffort effort,
  ) {
    switch (effort) {
      case ReasoningEffort.low:
        return l10n.reasoning_effort_low;
      case ReasoningEffort.medium:
        return l10n.reasoning_effort_medium;
      case ReasoningEffort.high:
        return l10n.reasoning_effort_high;
    }
  }
}
