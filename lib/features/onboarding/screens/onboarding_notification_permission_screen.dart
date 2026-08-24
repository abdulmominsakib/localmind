import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:cue/cue.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/routes/app_routes.dart';
import '../../../l10n/app_localizations.dart';
import '../../on_device/providers/on_device_providers.dart';

class OnboardingNotificationPermissionScreen extends ConsumerStatefulWidget {
  const OnboardingNotificationPermissionScreen({super.key});

  @override
  ConsumerState<OnboardingNotificationPermissionScreen> createState() =>
      _OnboardingNotificationPermissionScreenState();
}

class _OnboardingNotificationPermissionScreenState
    extends ConsumerState<OnboardingNotificationPermissionScreen> {
  bool _isProcessing = false;

  Future<void> _completeOnboarding() async {
    final settings = ref.read(settingsProvider);
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          settings.copyWith(
            hasCompletedOnboarding: true,
            hasAskedForNotifications: true,
          ),
        );

    if (mounted) {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _requestPermission() async {
    setState(() => _isProcessing = true);
    try {
      final notificationService = ref.read(
        notificationPermissionServiceProvider,
      );
      await notificationService.requestPermission();
      await _completeOnboarding();
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Cue.onMount(
          motion: .smooth(),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 32.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(),
                // Visual element
                Actor(
                  acts: [.fadeIn(), .scale(from: 0.8)],
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.2,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedNotification03,
                      size: 80,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                Actor(
                  delay: 60.ms,
                  acts: [.fadeIn(), .slideY(from: 0.08)],
                  child: Column(
                    children: [
                      Text(
                        l10n.stay_updated,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.stay_updated_desc,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                // Benefits list
                Actor(
                  delay: 120.ms,
                  acts: [.fadeIn(), .slideY(from: 0.08)],
                  child: Column(
                    children: [
                      _buildBenefitRow(
                        context,
                        HugeIcons.strokeRoundedDownload01,
                        l10n.notification_benefit_downloads,
                      ),
                      const SizedBox(height: 16),
                      _buildBenefitRow(
                        context,
                        HugeIcons.strokeRoundedAiChat01,
                        l10n.notification_benefit_completions,
                      ),
                      const SizedBox(height: 16),
                      _buildBenefitRow(
                        context,
                        HugeIcons.strokeRoundedClock01,
                        l10n.notification_benefit_background,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const SizedBox(height: 32),
                Actor(
                  delay: 180.ms,
                  acts: [.fadeIn(), .slideY(from: 0.08)],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ShadButton(
                        onPressed: _isProcessing ? null : _requestPermission,
                        child: _isProcessing
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                l10n.allow_notifications,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      ShadButton.ghost(
                        onPressed: _isProcessing ? null : _completeOnboarding,
                        child: Text(
                          l10n.not_now,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitRow(
    BuildContext context,
    List<List<dynamic>> icon,
    String text,
  ) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HugeIcon(
          icon: icon,
          size: 20,
          color: theme.colorScheme.primary.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}
