import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../core/theme/colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/models/on_device_model.dart';
import '../../providers/on_device_providers.dart';

/// Persisted generation control, available even when GGUF metadata does not
/// advertise thinking support. Changes apply to the next response.
class ImportedModelReasoningSetting extends ConsumerStatefulWidget {
  const ImportedModelReasoningSetting({super.key, required this.model});

  final OnDeviceModel model;

  @override
  ConsumerState<ImportedModelReasoningSetting> createState() =>
      _ImportedModelReasoningSettingState();
}

class _ImportedModelReasoningSettingState
    extends ConsumerState<ImportedModelReasoningSetting> {
  bool _saving = false;
  String? _error;

  Future<void> _save(String value) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(importedGgufModelsProvider.notifier)
          .updateReasoning(
            widget.model.id,
            value == 'default' ? null : value == 'on',
          );
    } catch (_) {
      if (mounted) {
        _error = AppLocalizations.of(context)!.model_reasoning_save_error;
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;

    final currentValue = switch (widget.model.reasoningEnabled) {
      true => 'on',
      false => 'off',
      null => 'default',
    };

    final options = [
      (value: 'default', label: l10n.model_reasoning_default),
      (value: 'on', label: l10n.model_reasoning_on),
      (value: 'off', label: l10n.reasoning_effort_off),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.3,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 270;
                final header = _ReasoningSettingHeader(
                  title: l10n.thinking_mode_title,
                  isDark: isDark,
                  saving: _saving,
                  accent: accent,
                );

                final chips = _ReasoningOptionChips(
                  options: options,
                  currentValue: currentValue,
                  saving: _saving,
                  isDark: isDark,
                  accent: accent,
                  onSelected: _save,
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [header, const SizedBox(height: 8), chips],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    header,
                    const SizedBox(width: 8),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: chips,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Text(
              l10n.model_reasoning_help,
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
                height: 1.25,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              _ReasoningErrorMessage(message: _error!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReasoningSettingHeader extends StatelessWidget {
  const _ReasoningSettingHeader({
    required this.title,
    required this.isDark,
    required this.saving,
    required this.accent,
  });

  final String title;
  final bool isDark;
  final bool saving;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HugeIcon(
          icon: HugeIcons.strokeRoundedBrain,
          size: 14,
          color: isDark ? AppColors.darkMutedText : AppColors.lightMutedText,
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.darkMutedText : AppColors.lightMutedText,
          ),
        ),
        if (saving) ...[
          const SizedBox(width: 6),
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReasoningOptionChips extends StatelessWidget {
  const _ReasoningOptionChips({
    required this.options,
    required this.currentValue,
    required this.saving,
    required this.isDark,
    required this.accent,
    required this.onSelected,
  });

  final List<({String value, String label})> options;
  final String currentValue;
  final bool saving;
  final bool isDark;
  final Color accent;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final isActive = opt.value == currentValue;

          final chipBg = isActive
              ? accent.withValues(alpha: 0.2)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.04));

          final chipFg = isActive
              ? accent
              : (isDark ? AppColors.darkMutedText : AppColors.lightMutedText);

          final borderColor = isActive
              ? accent.withValues(alpha: 0.5)
              : Colors.transparent;

          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: saving || isActive ? null : () => onSelected(opt.value),
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
                      fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                      color: chipFg,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ReasoningErrorMessage extends StatelessWidget {
  const _ReasoningErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        HugeIcon(
          icon: HugeIcons.strokeRoundedAlertCircle,
          size: 12,
          color: Colors.red[400],
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 10, color: Colors.red[400]),
          ),
        ),
      ],
    );
  }
}
