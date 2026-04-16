import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';

class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return ShadIconButton.ghost(
      onPressed: () {
        // Cycle through: System -> Light -> Dark -> Claude -> System
        final nextMode = AppThemeType.values[(themeMode.index + 1) % AppThemeType.values.length];
        ref.read(themeModeProvider.notifier).setThemeMode(nextMode);
      },
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          return RotationTransition(
            turns: animation,
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
        child: Icon(
          _getIconForMode(themeMode),
          key: ValueKey(themeMode),
          size: 20,
        ),
      ),
    );
  }

  IconData _getIconForMode(AppThemeType mode) {
    switch (mode) {
      case AppThemeType.system:
        return LucideIcons.monitor;
      case AppThemeType.light:
        return LucideIcons.sun;
      case AppThemeType.dark:
        return LucideIcons.moon;
      case AppThemeType.claude:
        return LucideIcons.palmtree;
    }
  }
}
