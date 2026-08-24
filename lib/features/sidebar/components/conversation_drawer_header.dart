import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/theme/colors.dart';

import '../../../l10n/app_localizations.dart';

class ConversationDrawerHeader extends ConsumerWidget {
  const ConversationDrawerHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
            child: Image.asset(
              'assets/images/logo.webp',
              width: 24,
              height: 24,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            l10n.app_name,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark
                  ? AppColors.darkPrimaryText
                  : AppColors.lightPrimaryText,
            ),
          ),
        ],
      ),
    );
  }
}
