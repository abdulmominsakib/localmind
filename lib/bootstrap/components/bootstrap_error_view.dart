import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/theme/colors.dart';
import '../../l10n/app_localizations.dart';

/// What the splash shows under the logo when startup failed.
class BootstrapErrorView extends StatelessWidget {
  const BootstrapErrorView({
    super.key,
    required this.error,
    required this.isDark,
    this.onRetry,
  });

  final Object? error;
  final bool isDark;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: .min,
      children: [
        const HugeIcon(
          icon: HugeIcons.strokeRoundedInformationCircle,
          size: 40,
          color: AppColors.error,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.something_went_wrong,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark
                ? AppColors.darkPrimaryText
                : AppColors.lightPrimaryText,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          error?.toString() ?? l10n.unknown_error,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppColors.darkMutedText : AppColors.lightMutedText,
          ),
        ),
        const SizedBox(height: 24),
        if (onRetry != null)
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedRefresh,
              size: 18,
            ),
            label: Text(l10n.retry),
          ),
      ],
    );
  }
}
