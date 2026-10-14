import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/theme/colors.dart';
import '../../../l10n/app_localizations.dart';

enum OnboardingWarningAction { chooseModel, skipForNow, wait, continueAnyway }

class OnboardingModelWarningDialog extends StatelessWidget {
  final String title;
  final String description;
  final List<List<dynamic>> icon;
  final Color iconColor;
  final String primaryButtonLabel;
  final String secondaryButtonLabel;
  final OnboardingWarningAction primaryAction;
  final OnboardingWarningAction secondaryAction;

  const OnboardingModelWarningDialog({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.primaryButtonLabel,
    required this.secondaryButtonLabel,
    required this.primaryAction,
    required this.secondaryAction,
  });

  static Future<OnboardingWarningAction?> showNoModelDownloaded(
    BuildContext context,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<OnboardingWarningAction>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => OnboardingModelWarningDialog(
        title: l10n.no_model_downloaded_title,
        description: l10n.no_model_downloaded_desc,
        icon: HugeIcons.strokeRoundedAlertCircle,
        iconColor: AppColors.warning,
        secondaryButtonLabel: l10n.skip,
        secondaryAction: OnboardingWarningAction.skipForNow,
        primaryButtonLabel: l10n.choose_a_model,
        primaryAction: OnboardingWarningAction.chooseModel,
      ),
    );
  }

  static Future<OnboardingWarningAction?> showDownloadInProgress(
    BuildContext context,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return showDialog<OnboardingWarningAction>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => OnboardingModelWarningDialog(
        title: l10n.download_in_progress_title,
        description: l10n.download_in_progress_desc,
        icon: HugeIcons.strokeRoundedDownload04,
        iconColor: theme.colorScheme.primary,
        secondaryButtonLabel: l10n.wait_for_download,
        secondaryAction: OnboardingWarningAction.wait,
        primaryButtonLabel: l10n.continue_anyway,
        primaryAction: OnboardingWarningAction.continueAnyway,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isDark
              ? AppColors.darkBorder.withValues(alpha: 0.6)
              : AppColors.lightBorder,
          width: 1,
        ),
      ),
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon Badge
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: isDark ? 0.16 : 0.10),
                shape: BoxShape.circle,
                border: Border.all(
                  color: iconColor.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: iconColor.withValues(alpha: 0.15),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: HugeIcon(icon: icon, color: iconColor, size: 30),
              ),
            ),
            const SizedBox(height: 16),

            // Dialog Title
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppColors.darkPrimaryText
                    : AppColors.lightPrimaryText,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Description
            Text(
              description,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: isDark
                    ? AppColors.darkMutedText
                    : AppColors.lightMutedText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(secondaryAction),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        side: BorderSide(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        foregroundColor: isDark
                            ? AppColors.darkPrimaryText
                            : AppColors.lightPrimaryText,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          secondaryButtonLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(primaryAction),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          primaryButtonLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
