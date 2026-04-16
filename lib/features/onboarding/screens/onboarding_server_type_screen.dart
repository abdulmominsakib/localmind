import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/enums.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/routes/app_routes.dart';

class OnboardingServerTypeScreen extends ConsumerStatefulWidget {
  const OnboardingServerTypeScreen({super.key});

  @override
  ConsumerState<OnboardingServerTypeScreen> createState() =>
      _OnboardingServerTypeScreenState();
}

class _OnboardingServerTypeScreenState
    extends ConsumerState<OnboardingServerTypeScreen> {
  ServerType? _selectedType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Image.asset(
                'assets/images/logo.webp',
                width: 24,
                height: 24,
              ),
            ),
            const Text(
              'LOCALMIND',
              style: TextStyle(letterSpacing: 2, fontSize: 14),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          TextButton.icon(
            onPressed: () => _skipOnboarding(),
            label: const Text('Skip'),
            icon: HugeIcon(icon: HugeIcons.strokeRoundedNext),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Text(
                    'Connect Your\nServer',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Connect to LM Studio, Ollama, or\nOpenRouter to start your private AI\nexperience.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildServerCard(
                    type: ServerType.onDevice,
                    title: 'On-Device',
                    subtitle: 'NO SERVER NEEDED',
                    iconWidget: Icon(
                      Icons.phone_android_rounded,
                      color: _selectedType == ServerType.onDevice
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                    theme: theme,
                  ),
                  const SizedBox(height: 16),
                  _buildServerCard(
                    type: ServerType.lmStudio,
                    title: 'LM Studio',
                    subtitle: 'LOCAL API',
                    iconWidget: Icon(
                      Icons.terminal_rounded,
                      color: _selectedType == ServerType.lmStudio
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                    theme: theme,
                  ),
                  const SizedBox(height: 16),
                  _buildServerCard(
                    type: ServerType.ollama,
                    title: 'Ollama',
                    subtitle: 'CLI ENGINE',
                    iconWidget: Icon(
                      Icons.smart_toy_rounded,
                      color: _selectedType == ServerType.ollama
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                    theme: theme,
                  ),
                  const SizedBox(height: 16),
                  _buildServerCard(
                    type: ServerType.openRouter,
                    title: 'OpenRouter',
                    subtitle: 'UNIFIED CLOUD',
                    iconWidget: HugeIcon(
                      icon: HugeIcons.strokeRoundedCloudServer,
                      color: _selectedType == ServerType.openRouter
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                    theme: theme,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                // Status Indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _selectedType != null
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.4,
                              ),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _selectedType != null
                          ? 'READY TO CONTINUE'
                          : 'WAITING FOR SELECTION',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ShadButton(
                  width: double.infinity,
                  enabled: _selectedType != null,
                  onPressed: () {
                    if (_selectedType != null) {
                      if (_selectedType == ServerType.onDevice) {
                        _completeOnboarding();
                      } else {
                        context.push(
                          AppRoutes.onboardingSetup,
                          extra: _selectedType,
                        );
                      }
                    }
                  },
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                SizedBox(
                  height: MediaQuery.of(context).padding.bottom,
                ), // Reduced bottom padding slightly for small screens
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerCard({
    required ServerType type,
    required String title,
    required String subtitle,
    required Widget iconWidget,
    required ThemeData theme,
  }) {
    final isSelected = _selectedType == type;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedType = type;
        });
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: iconWidget,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 2,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _completeOnboarding() async {
    final settings = ref.read(settingsProvider);
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(settings.copyWith(hasCompletedOnboarding: true));
    if (mounted) {
      context.go(AppRoutes.home);
    }
  }

  void _skipOnboarding() {
    _completeOnboarding();
  }
}
