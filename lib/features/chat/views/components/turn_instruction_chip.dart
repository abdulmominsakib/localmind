import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/providers/turn_instruction_provider.dart';
import 'package:localmind/l10n/app_localizations.dart';

/// Lets the user write, change or remove the one-reply instruction.
Future<void> showTurnInstructionDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        TurnInstructionDialog(initial: ref.read(turnInstructionProvider)),
  );
}

class TurnInstructionDialog extends ConsumerStatefulWidget {
  const TurnInstructionDialog({super.key, this.initial});

  final String? initial;

  @override
  ConsumerState<TurnInstructionDialog> createState() =>
      _TurnInstructionDialogState();
}

class _TurnInstructionDialogState extends ConsumerState<TurnInstructionDialog> {
  late final _controller = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    ref.read(turnInstructionProvider.notifier).set(_controller.text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    return AlertDialog(
      title: Text(l10n.turn_instruction_title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.turn_instruction_desc,
            style: TextStyle(fontSize: 13, color: muted),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('turn_instruction_input'),
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: l10n.turn_instruction_hint),
          ),
        ],
      ),
      actions: [
        if ((widget.initial ?? '').isNotEmpty)
          TextButton(
            key: const ValueKey('turn_instruction_remove'),
            onPressed: () {
              ref.read(turnInstructionProvider.notifier).clear();
              Navigator.of(context).pop();
            },
            child: Text(l10n.turn_instruction_remove),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const ValueKey('turn_instruction_save'),
          onPressed: _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

/// Shown inside the composer while a one-reply instruction is set: tap to
/// edit it, or the cross to drop it.
class TurnInstructionChip extends ConsumerWidget {
  const TurnInstructionChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instruction = ref.watch(turnInstructionProvider);
    if (instruction == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Material(
        color: isDark ? AppColors.darkSurfaceInput : const Color(0xFFF2F2F3),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('turn_instruction_chip'),
          onTap: () => showTurnInstructionDialog(context, ref),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            child: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedNoteEdit,
                  size: 16,
                  color: muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${l10n.turn_instruction_chip_label} ',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: muted,
                          ),
                        ),
                        TextSpan(text: instruction),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: fg),
                  ),
                ),
                IconButton(
                  key: const ValueKey('turn_instruction_clear'),
                  tooltip: l10n.turn_instruction_remove,
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: () =>
                      ref.read(turnInstructionProvider.notifier).clear(),
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedCancel01,
                    size: 16,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
