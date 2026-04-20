import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../on_device/providers/on_device_providers.dart';

class NotificationPermissionBanner extends ConsumerStatefulWidget {
  const NotificationPermissionBanner({super.key});

  @override
  ConsumerState<NotificationPermissionBanner> createState() =>
      _NotificationPermissionBannerState();
}

class _NotificationPermissionBannerState
    extends ConsumerState<NotificationPermissionBanner> {
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final settings = ref.read(settingsProvider);
    if (settings.hasAskedForNotifications) return;

    final service = ref.read(downloadNotificationServiceProvider);
    final granted = await service.isPermissionGranted();

    if (!granted) {
      setState(() => _isVisible = true);
    } else {
      // If already granted somehow, mark as asked
      await ref
          .read(settingsProvider.notifier)
          .updateSettings(settings.copyWith(hasAskedForNotifications: true));
    }
  }

  Future<void> _requestPermission() async {
    final service = ref.read(downloadNotificationServiceProvider);
    await service.requestPermission();
    await _dismiss(true);
  }

  Future<void> _dismiss(bool asked) async {
    final settings = ref.read(settingsProvider);
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(settings.copyWith(hasAskedForNotifications: true));
    setState(() => _isVisible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedNotification03,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enable Notifications',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Get notified when models finish downloading.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: () => _dismiss(true),
            child: const Text('Not Now'),
          ),
          const SizedBox(width: 8),
          ShadButton(
            size: ShadButtonSize.sm,
            onPressed: _requestPermission,
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }
}
