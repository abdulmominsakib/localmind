import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/theme/colors.dart';

class QuickPrompt {
  const QuickPrompt({required this.icon, required this.text});

  final List<List<dynamic>> icon;
  final String text;
}

/// Starter prompts as one row of chips, scrolled sideways, sat just above
/// the composer.
class QuickPromptChips extends StatelessWidget {
  const QuickPromptChips({
    super.key,
    required this.prompts,
    required this.onSelected,
  });

  final List<QuickPrompt> prompts;
  final void Function(String) onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: .horizontal,
      padding: const .symmetric(horizontal: 12),
      child: Row(
        children: [
          for (var i = 0; i < prompts.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            QuickPromptChip(
              key: ValueKey('quick_prompt_$i'),
              prompt: prompts[i],
              onTap: () => onSelected(prompts[i].text),
            ),
          ],
        ],
      ),
    );
  }
}

class QuickPromptChip extends StatelessWidget {
  const QuickPromptChip({super.key, required this.prompt, required this.onTap});

  final QuickPrompt prompt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shape = RoundedRectangleBorder(
      borderRadius: .circular(999),
      side: BorderSide(
        color: isDark ? const Color(0xFF3A3A3A) : AppColors.lightBorder,
      ),
    );

    return Material(
      color: isDark ? const Color(0xFF2A2A2A) : AppColors.lightSurface,
      shape: shape,
      clipBehavior: .antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: Container(
          height: 44,
          padding: const .only(left: 14, right: 16),
          child: Row(
            mainAxisSize: .min,
            children: [
              HugeIcon(
                icon: prompt.icon,
                size: 17,
                color: isDark
                    ? AppColors.darkMutedText
                    : AppColors.lightMutedText,
              ),
              const SizedBox(width: 8),
              Text(
                prompt.text,
                style: TextStyle(
                  fontSize: 14.5,
                  color: isDark
                      ? AppColors.darkPrimaryText
                      : AppColors.lightPrimaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
