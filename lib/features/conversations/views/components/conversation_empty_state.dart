import 'package:cue/cue.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:localmind/l10n/app_localizations.dart';

class ConversationEmptyState extends StatelessWidget {
  const ConversationEmptyState({super.key, required this.isSearching});

  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Cue.onMount(
      motion: .smooth(),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Actor(
                acts: [.fadeIn(), .scale(from: 0.85)],
                child: HugeIcon(
                  icon: isSearching
                      ? HugeIcons.strokeRoundedSearch01
                      : HugeIcons.strokeRoundedChatting01,
                  size: 48,
                  color: isDark
                      ? const Color(0xFF3A3A3A)
                      : const Color(0xFFE5E5E5),
                ),
              ),
              const SizedBox(height: 16),
              Actor(
                delay: 80.ms,
                acts: [.fadeIn(), .slideY(from: 0.08)],
                child: Text(
                  isSearching
                      ? l10n.no_results_found
                      : l10n.no_conversations_yet,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Actor(
                delay: 140.ms,
                acts: [.fadeIn(), .slideY(from: 0.06)],
                child: Text(
                  isSearching
                      ? l10n.try_different_search
                      : l10n.start_new_conversation,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? const Color(0xFF888888)
                        : const Color(0xFF666666),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
