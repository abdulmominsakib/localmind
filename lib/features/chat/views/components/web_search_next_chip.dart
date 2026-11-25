import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/providers/web_search_next_provider.dart';
import 'package:localmind/l10n/app_localizations.dart';

/// Shown inside the composer while "Search the web" is on for the next
/// message, with a cross to turn it off.
class WebSearchNextChip extends ConsumerWidget {
  const WebSearchNextChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(webSearchNextProvider)) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    return Padding(
      key: const ValueKey('web_search_next_chip'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Material(
        color: isDark ? AppColors.darkSurfaceInput : const Color(0xFFF2F2F3),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
          child: Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedGlobalSearch,
                size: 16,
                color: muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.web_search_next_chip,
                  style: TextStyle(fontSize: 12.5, color: fg),
                ),
              ),
              IconButton(
                key: const ValueKey('web_search_next_clear'),
                tooltip: l10n.web_search_next_off,
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    ref.read(webSearchNextProvider.notifier).set(false),
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
    );
  }
}
