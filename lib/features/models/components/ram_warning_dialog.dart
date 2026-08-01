import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/l10n/app_localizations.dart';

/// A modern, high-end RAM Warning Dialog component.
class RamWarningDialog extends StatelessWidget {
  const RamWarningDialog({
    super.key,
    this.availableRam,
    this.requiredRam,
    this.message,
    this.proceedLabel,
    this.cancelLabel,
    required this.onProceed,
    required this.onCancel,
  });

  final String? availableRam;
  final String? requiredRam;
  final String? message;
  final String? proceedLabel;
  final String? cancelLabel;
  final VoidCallback onProceed;
  final VoidCallback onCancel;

  static Future<bool> show({
    required BuildContext context,
    String? availableRam,
    String? requiredRam,
    String? message,
    String? proceedLabel,
    String? cancelLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => RamWarningDialog(
        availableRam: availableRam,
        requiredRam: requiredRam,
        message: message,
        proceedLabel: proceedLabel,
        cancelLabel: cancelLabel,
        onProceed: () => Navigator.of(ctx).pop(true),
        onCancel: () => Navigator.of(ctx).pop(false),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    const warningColor = AppColors.warning;

    // Infer RAM specs from message if available parameters were omitted
    String? availRam = availableRam;
    String? reqRam = requiredRam;

    if ((availRam == null || reqRam == null) && message != null) {
      final matches =
          RegExp(r'(\d+(?:\.\d+)?\s*(?:GB|MB))', caseSensitive: false)
              .allMatches(message!)
              .map((m) => m.group(0))
              .whereType<String>()
              .toList();
      if (matches.length >= 2) {
        availRam ??= matches[0];
        reqRam ??= matches[1];
      } else if (matches.length == 1) {
        reqRam ??= matches[0];
      }
    }

    final bodyText =
        message ??
        (availRam != null && reqRam != null
            ? l10n.ram_warning_body_load(availRam, reqRam)
            : l10n.ram_warning);

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
            // Glowing Warning Icon Badge
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: warningColor.withValues(alpha: isDark ? 0.16 : 0.10),
                shape: BoxShape.circle,
                border: Border.all(
                  color: warningColor.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: warningColor.withValues(alpha: 0.15),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedAlertCircle,
                  color: warningColor,
                  size: 30,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Dialog Title
            Text(
              l10n.ram_warning,
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
            const SizedBox(height: 16),

            // Visual RAM Stats Box (if available)
            if (availRam != null && reqRam != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkBackground
                      : warningColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: warningColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            "AVAILABLE RAM",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: isDark
                                  ? AppColors.darkMutedText
                                  : AppColors.lightMutedText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            availRam,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      height: 32,
                      width: 1,
                      color: isDark
                          ? AppColors.darkBorder
                          : warningColor.withValues(alpha: 0.25),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            "RECOMMENDED",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: isDark
                                  ? AppColors.darkMutedText
                                  : AppColors.lightMutedText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            reqRam,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: warningColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Body Warning Description
            Text(
              bodyText,
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

            // Actions Buttons
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
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
                      child: Text(
                        cancelLabel ?? l10n.cancel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: onProceed,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: FittedBox(
                        child: Text(
                          proceedLabel ?? l10n.proceed_anyway,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
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

/// A modern, styled confirmation dialog for model operations (e.g. Delete Model).
class ModelConfirmDialog extends StatelessWidget {
  const ModelConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    this.isDestructive = true,
    this.icon,
    required this.onConfirm,
    required this.onCancel,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDestructive;
  final dynamic icon;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
    bool isDestructive = true,
    dynamic icon,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ModelConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        isDestructive: isDestructive,
        icon: icon,
        onConfirm: () => Navigator.of(ctx).pop(true),
        onCancel: () => Navigator.of(ctx).pop(false),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final accentColor = isDestructive
        ? AppColors.error
        : theme.colorScheme.primary;
    final dialogIcon =
        icon ??
        (isDestructive
            ? HugeIcons.strokeRoundedDelete02
            : HugeIcons.strokeRoundedAlertCircle);

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
            // Icon Badge Header
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: isDark ? 0.16 : 0.10),
                shape: BoxShape.circle,
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: HugeIcon(icon: dialogIcon, color: accentColor, size: 28),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              title,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppColors.darkPrimaryText
                    : AppColors.lightPrimaryText,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Message
            Text(
              message,
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

            // Buttons
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
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
                      child: Text(
                        cancelLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: onConfirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: isDestructive
                            ? Colors.white
                            : Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        confirmLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
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
