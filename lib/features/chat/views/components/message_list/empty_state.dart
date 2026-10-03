import 'package:cue/cue.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:flutter/material.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/l10n/app_localizations.dart';

class QuickPrompt {
  const QuickPrompt({required this.icon, required this.text});

  final List<List<dynamic>> icon;
  final String text;
}

/// The new-chat screen: a greeting, where messages go, and a few starter
/// prompts — sat just above the composer, within thumb reach. The model is
/// chosen from the app bar, personas from the menu, and past chats from the
/// drawer, so none of them are repeated here.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.onQuickPrompt,
    required this.quickPrompts,
    this.isCloudProvider = false,
    this.bottomInset = 0,
  });

  final void Function(String) onQuickPrompt;
  final List<QuickPrompt> quickPrompts;
  final bool isCloudProvider;

  /// Space the composer and system bars take below the content.
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, 16, 20, 140 + bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 156 - bottomInset).clamp(
              0,
              double.infinity,
            ),
          ),
          child: Cue.onMount(
            motion: .smooth(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Actor(
                  acts: [.fadeIn(), .slideY(from: 0.1)],
                  child: Text(
                    l10n.welcome_message_1,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      color: isDark
                          ? AppColors.darkPrimaryText
                          : AppColors.lightPrimaryText,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Actor(
                  delay: 60.ms,
                  acts: [.fadeIn(), .slideY(from: 0.1)],
                  child: Text(
                    isCloudProvider
                        ? l10n.welcome_message_cloud
                        : l10n.welcome_message_3,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                      color: muted,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Actor(
                  delay: 120.ms,
                  acts: [.fadeIn(), .slideY(from: 0.08)],
                  child: QuickPromptList(
                    prompts: quickPrompts,
                    onSelected: onQuickPrompt,
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

class QuickPromptList extends StatelessWidget {
  const QuickPromptList({
    super.key,
    required this.prompts,
    required this.onSelected,
  });

  final List<QuickPrompt> prompts;
  final void Function(String) onSelected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final iconColor = isDark
        ? AppColors.darkMutedText
        : AppColors.lightMutedText;
    final textColor = isDark
        ? AppColors.darkPrimaryText
        : AppColors.lightPrimaryText;

    return Material(
      color: isDark ? AppColors.darkSurfaceCard : AppColors.lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < prompts.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: border),
            InkWell(
              key: ValueKey('quick_prompt_$i'),
              onTap: () => onSelected(prompts[i].text),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      HugeIcon(
                        icon: prompts[i].icon,
                        size: 18,
                        color: iconColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          prompts[i].text,
                          style: TextStyle(fontSize: 15, color: textColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
