import 'package:hugeicons/hugeicons.dart';
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
        final nextMode = AppThemeType
            .values[(themeMode.index + 1) % AppThemeType.values.length];
        ref.read(themeModeProvider.notifier).setThemeMode(nextMode);
      },
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          return RotationTransition(
            turns: animation,
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: HugeIcon(
          icon: _getIconForMode(themeMode),
          key: ValueKey(themeMode),
          size: 20,
        ),
      ),
    );
  }

  List<List<dynamic>> _getIconForMode(AppThemeType mode) {
    switch (mode) {
      case AppThemeType.system:
        return HugeIcons.strokeRoundedComputer;
      case AppThemeType.light:
        return HugeIcons.strokeRoundedSun01;
      case AppThemeType.dark:
        return HugeIcons.strokeRoundedMoon02;
      case AppThemeType.claude:
        return HugeIcons.strokeRoundedTree01;
    }
  }
}
