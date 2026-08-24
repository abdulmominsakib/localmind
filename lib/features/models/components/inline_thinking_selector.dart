import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/providers/chat_reasoning_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';

/// Inline widget rendered under a model tile in the selection bottom sheet.
/// Shows the effort levels the model actually advertises (plus an "Off"
/// toggle unless reasoning is mandatory), keeping the choice in sync with
/// [chatReasoningConfigProvider].
class InlineThinkingSelector extends ConsumerWidget {
  const InlineThinkingSelector({
    super.key,
    required this.isDark,
    this.isSelected = false,
    this.onSelectModel,
    this.supportedEfforts,
    this.reasoningMandatory = false,
  });

  final bool isDark;
  final bool isSelected;

  /// Optional callback to select/load the parent model if it's not already selected.
  final VoidCallback? onSelectModel;

  /// Effort strings the model supports (OpenRouter `supported_efforts`).
  /// Null/empty falls back to low/medium/high for non-OpenRouter providers.
  final List<String>? supportedEfforts;

  /// When true the model can't run without reasoning, so "Off" is hidden.
  final bool reasoningMandatory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final config = ref.watch(chatReasoningConfigProvider);
    final notifier = ref.read(chatReasoningConfigProvider.notifier);

    final accent = theme.colorScheme.primary;
    final efforts = effortsForModel(supportedEfforts);

    final options = <_ThinkingOption>[
      if (!reasoningMandatory)
        _ThinkingOption(
          label: l10n.reasoning_effort_off,
          isEnabled: false,
          effort: ReasoningEffort.low,
        ),
      for (final effort in efforts)
        _ThinkingOption(
          label: effort.shortLabel(l10n),
          isEnabled: true,
          effort: effort,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedBrain,
            size: 14,
            color: isDark ? AppColors.darkMutedText : AppColors.lightMutedText,
          ),
          const SizedBox(width: 6),
          Text(
            l10n.thinking_mode_title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.darkMutedText
                  : AppColors.lightMutedText,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: options.map((opt) {
                  final isActive =
                      isSelected &&
                      (opt.isEnabled == config.enabled) &&
                      (!opt.isEnabled || opt.effort == config.effort);

                  final chipBg = isActive
                      ? accent.withValues(alpha: 0.2)
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.04));

                  final chipFg = isActive
                      ? accent
                      : (isDark
                            ? AppColors.darkMutedText
                            : AppColors.lightMutedText);

                  final borderColor = isActive
                      ? accent.withValues(alpha: 0.5)
                      : Colors.transparent;

                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          if (onSelectModel != null && !isSelected) {
                            onSelectModel!();
                          }
                          if (!opt.isEnabled) {
                            notifier.setEnabled(false);
                          } else {
                            notifier.setEnabled(true);
                            notifier.setEffort(opt.effort);
                          }
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: chipBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: borderColor, width: 1),
                          ),
                          child: Text(
                            opt.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: chipFg,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingOption {
  const _ThinkingOption({
    required this.label,
    required this.isEnabled,
    required this.effort,
  });

  final String label;
  final bool isEnabled;
  final ReasoningEffort effort;
}

extension on ReasoningEffort {
  String shortLabel(AppLocalizations l10n) {
    return switch (this) {
      ReasoningEffort.minimal => l10n.reasoning_effort_minimal,
      ReasoningEffort.low => l10n.reasoning_effort_low,
      ReasoningEffort.medium => l10n.reasoning_effort_medium,
      ReasoningEffort.high => l10n.reasoning_effort_high,
      ReasoningEffort.xhigh => l10n.reasoning_effort_xhigh,
      ReasoningEffort.max => l10n.reasoning_effort_max,
    };
  }
}
