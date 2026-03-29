import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_theme.dart';

class OnboardingThemeScreen extends ConsumerStatefulWidget {
  const OnboardingThemeScreen({super.key});

  @override
  ConsumerState<OnboardingThemeScreen> createState() =>
      _OnboardingThemeScreenState();
}

class _OnboardingThemeScreenState extends ConsumerState<OnboardingThemeScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentTheme = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Theme'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            context.pop();
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Personalize the app appearance. You can always change this later in settings.',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 32),

              Expanded(
                child: ListView(
                  children: [
                    _buildThemeCard(
                      type: AppThemeType.system,
                      title: 'System',
                      subtitle: 'Matches your device settings',
                      iconWidget: HugeIcon(
                        icon: HugeIcons.strokeRoundedSettings01,
                        color: currentTheme == AppThemeType.system
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                      currentTheme: currentTheme,
                      context: context,
                    ),
                    const SizedBox(height: 16),
                    _buildThemeCard(
                      type: AppThemeType.light,
                      title: 'Light',
                      subtitle: 'Clean and bright',
                      iconWidget: HugeIcon(
                        icon: HugeIcons.strokeRoundedSun01,
                        color: currentTheme == AppThemeType.light
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                      currentTheme: currentTheme,
                      context: context,
                    ),
                    const SizedBox(height: 16),
                    _buildThemeCard(
                      type: AppThemeType.dark,
                      title: 'Dark',
                      subtitle: 'Easy on the eyes',
                      iconWidget: HugeIcon(
                        icon: HugeIcons.strokeRoundedMoon02,
                        color: currentTheme == AppThemeType.dark
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                      currentTheme: currentTheme,
                      context: context,
                    ),
                    const SizedBox(height: 16),
                    _buildThemeCard(
                      type: AppThemeType.claude,
                      title: 'Claude',
                      subtitle: 'A warm, peach-tinted theme',
                      iconWidget: HugeIcon(
                        icon: HugeIcons.strokeRoundedPaintBrush02,
                        color: currentTheme == AppThemeType.claude
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                      currentTheme: currentTheme,
                      context: context,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              ShadButton(
                width: double.infinity,
                onPressed: () async {
                  // Mark onboarding as complete
                  final settings = ref.read(settingsProvider);
                  await ref
                      .read(settingsProvider.notifier)
                      .updateSettings(
                        settings.copyWith(hasCompletedOnboarding: true),
                      );

                  if (context.mounted) {
                    context.go(AppRoutes.home);
                  }
                },
                child: const Text(
                  'Finish Setup',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemeCard({
    required AppThemeType type,
    required String title,
    required String subtitle,
    required Widget iconWidget,
    required AppThemeType currentTheme,
    required BuildContext context,
  }) {
    final theme = Theme.of(context);
    final isSelected = currentTheme == type;

    return GestureDetector(
      onTap: () {
        ref.read(themeModeProvider.notifier).setThemeMode(type);
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: iconWidget,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
