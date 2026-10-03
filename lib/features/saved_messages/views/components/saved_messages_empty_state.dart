import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/l10n/app_localizations.dart';

class SavedMessagesEmptyState extends StatelessWidget {
  const SavedMessagesEmptyState({super.key, required this.isFiltered});

  /// A filter or folder hides everything, rather than nothing being saved.
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: isFiltered
                  ? HugeIcons.strokeRoundedSearch01
                  : HugeIcons.strokeRoundedBookmark01,
              size: 40,
              color: muted.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              isFiltered ? l10n.no_results_found : l10n.saved_messages_empty,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.45, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
