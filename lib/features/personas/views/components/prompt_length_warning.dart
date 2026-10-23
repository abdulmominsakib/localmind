import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/l10n/app_localizations.dart';

class PromptLengthWarning extends StatelessWidget {
  static const threshold = 4000;

  final int length;

  const PromptLengthWarning({super.key, required this.length});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const color = Color(0xFFE08A00);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HugeIcon(
            icon: HugeIcons.strokeRoundedAlert02,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.prompt_length_warning(length),
              style: const TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
