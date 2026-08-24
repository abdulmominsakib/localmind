import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../core/theme/colors.dart';
import '../core/utils/locale_utils.dart';
import '../l10n/app_localizations.dart';
import 'bootstrap_state.dart';

class BootstrapScreen extends StatelessWidget {
  final BootstrapState state;
  final VoidCallback? onRetry;
  final Locale? locale;

  const BootstrapScreen({
    super.key,
    required this.state,
    this.onRetry,
    this.locale,
  });

  String _stageMessage(AppLocalizations l10n) {
    switch (state.stage) {
      case BootstrapStage.initializing:
        return l10n.initializing;
      case BootstrapStage.preparingApp:
        return l10n.preparing_app;
      case BootstrapStage.initializingServices:
        return l10n.initializing_services;
      case BootstrapStage.configuringServer:
        return l10n.configuring_server;
      case BootstrapStage.done:
        return l10n.ready;
      case BootstrapStage.error:
        return l10n.startup_failed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final isDark = brightness == Brightness.dark;
    final requestedLocale =
        this.locale ?? WidgetsBinding.instance.platformDispatcher.locale;
    final locale =
        findSupportedLocale(
          requestedLocale.toLanguageTag(),
          AppLocalizations.supportedLocales,
        ) ??
        const Locale('en');

    return Localizations(
      locale: locale,
      delegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      child: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context)!;
          return Directionality(
            textDirection: locale.languageCode.startsWith('ar')
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: Material(
              color: isDark
                  ? AppColors.darkBackground
                  : AppColors.lightBackground,
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/images/logo.webp',
                            width: 72,
                            height: 72,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          l10n.app_name,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? AppColors.darkPrimaryText
                                : AppColors.lightPrimaryText,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 48),
                        if (state.stage != BootstrapStage.error) ...[
                          LoadingAnimationWidget.fourRotatingDots(
                            size: 32,
                            color: isDark
                                ? AppColors.darkPrimaryText
                                : AppColors.lightPrimaryText,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _stageMessage(l10n),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? AppColors.darkMutedText
                                  : AppColors.lightMutedText,
                            ),
                          ),
                        ] else ...[
                          HugeIcon(
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
                            state.error?.toString() ?? l10n.unknown_error,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? AppColors.darkMutedText
                                  : AppColors.lightMutedText,
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
