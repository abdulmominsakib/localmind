import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/providers/chat_reasoning_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';

/// Inline widget rendered under a model tile in the selection bottom sheet.
/// Shows direct level options (Off, Low, Medium, High) without needing a dropdown.
class InlineThinkingSelector extends ConsumerWidget {
  const InlineThinkingSelector({
    super.key,
    required this.isDark,
    this.isSelected = false,
    this.onSelectModel,
  });

  final bool isDark;
  final bool isSelected;

  /// Optional callback to select/load the parent model if it's not already selected.
  final VoidCallback? onSelectModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final config = ref.watch(chatReasoningConfigProvider);
    final notifier = ref.read(chatReasoningConfigProvider.notifier);

    final accent = theme.colorScheme.primary;

    // Options: Off, Low, Medium, High
    final options = <_ThinkingOption>[
      _ThinkingOption(
        label: 'Off',
        isEnabled: false,
        effort: ReasoningEffort.low,
      ),
      _ThinkingOption(
        label: l10n.reasoning_effort_low,
        isEnabled: true,
        effort: ReasoningEffort.low,
      ),
      _ThinkingOption(
        label: l10n.reasoning_effort_medium,
        isEnabled: true,
        effort: ReasoningEffort.medium,
      ),
      _ThinkingOption(
        label: l10n.reasoning_effort_high,
        isEnabled: true,
        effort: ReasoningEffort.high,
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
                  final isActive = isSelected &&
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
