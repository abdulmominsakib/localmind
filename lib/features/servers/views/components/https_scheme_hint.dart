import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/models/server.dart';

class HttpsSchemeHint extends StatelessWidget {
  final TextEditingController controller;

  const HttpsSchemeHint({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        if (!isHttpsAddressInput(value.text)) {
          return const SizedBox.shrink();
        }

        return AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colorScheme.tertiary.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedLock,
                  size: 18,
                  color: colorScheme.tertiary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.https_requires_ssl,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onTertiaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.most_local_setups_use_http,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onTertiaryContainer.withValues(
                            alpha: 0.82,
                          ),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
