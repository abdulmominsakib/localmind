import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:localmind/l10n/app_localizations.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkStatus();
      }
    });
  }

  Future<void> _checkStatus() async {
    final settings = ref.read(settingsProvider);
    if (settings.hasAskedForNotifications) return;

    final service = ref.read(notificationPermissionServiceProvider);
    final granted = await service.isPermissionGranted();

    if (!mounted) return;

    if (!granted) {
      setState(() => _isVisible = true);
    } else {
      // Guard every ref access after an await — the State may have been
      // deactivated while the permission request was in flight.
      if (!mounted) return;
      await ref
          .read(settingsProvider.notifier)
          .updateSettings(settings.copyWith(hasAskedForNotifications: true));
    }
  }

  Future<void> _requestPermission() async {
    final service = ref.read(notificationPermissionServiceProvider);
    await service.requestPermission();
    if (!mounted) return;
    await _dismiss(true);
  }

  Future<void> _dismiss(bool asked) async {
    final settings = ref.read(settingsProvider);
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(settings.copyWith(hasAskedForNotifications: true));
    if (!mounted) return;
    setState(() => _isVisible = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                  l10n.enable_notifications,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  l10n.enable_notifications_desc,
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
            child: Text(l10n.not_now),
          ),
          const SizedBox(width: 8),
          ShadButton(
            size: ShadButtonSize.sm,
            onPressed: _requestPermission,
            child: Text(l10n.enable),
          ),
        ],
      ),
    );
  }
}
