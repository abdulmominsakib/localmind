import 'package:cue/cue.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../core/theme/colors.dart';
import '../core/utils/locale_utils.dart';
import '../features/chat/utils/ascii_logo.dart';
import '../features/chat/views/components/message_list/ascii_logo_view.dart';
import '../l10n/app_localizations.dart';
import 'bootstrap_state.dart';
import 'components/bootstrap_error_view.dart';

/// The animated splash: the LocalMind ASCII logo scrambles in on the same
/// background the native launch screen shows (see `splash_background` on
/// Android and `SplashBackground` on iOS), so the handoff is invisible.
class BootstrapScreen extends StatelessWidget {
  final BootstrapState state;
  final VoidCallback? onRetry;
  final Locale? locale;

  /// Shows the startup stage under the logo. Off while the splash is
  /// playing its intro, so a fast start never flashes status text.
  final bool showStatus;

  const BootstrapScreen({
    super.key,
    required this.state,
    this.onRetry,
    this.locale,
    this.showStatus = true,
  });

  /// When the wordmark fades in: as the scrambled logo settles.
  static const wordmarkDelay = Duration(milliseconds: 1100);

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
          final isError = state.stage == BootstrapStage.error;
          return Directionality(
            textDirection: locale.languageCode.startsWith('ar')
                ? TextDirection.rtl
                : TextDirection.ltr,
            // The splash sits above MaterialApp: give the logo the theme it
            // reads its colors from, and keep the system bars readable.
            child: Theme(
              data: ThemeData(brightness: brightness),
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: isDark
                      ? Brightness.light
                      : Brightness.dark,
                  statusBarBrightness: brightness,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarIconBrightness: isDark
                      ? Brightness.light
                      : Brightness.dark,
                ),
                child: Material(
                  color: isDark
                      ? AppColors.darkBackground
                      : AppColors.lightBackground,
                  child: SafeArea(
                    child: Center(
                      child: Padding(
                        padding: const .symmetric(horizontal: 32),
                        child: Cue.onMount(
                          motion: .smooth(),
                          child: Column(
                            mainAxisSize: .min,
                            children: [
                              AsciiLogoView(
                                logo: AsciiLogo.localMind,
                                semanticLabel: l10n.app_name,
                              ),
                              const SizedBox(height: 8),
                              Actor(
                                delay: wordmarkDelay,
                                acts: [.fadeIn(), .slideY(from: 0.3)],
                                child: Text(
                                  l10n.app_name,
                                  style: TextStyle(
                                    fontFamily: 'Menlo',
                                    fontFamilyFallback: const [
                                      'Courier',
                                      'monospace',
                                    ],
                                    fontSize: 22,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 2,
                                    color: isDark
                                        ? AppColors.darkPrimaryText
                                        : AppColors.lightPrimaryText,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 32),
                              if (isError)
                                BootstrapErrorView(
                                  error: state.error,
                                  isDark: isDark,
                                  onRetry: onRetry,
                                )
                              else
                                // Fixed height: the logo stays put when the
                                // status appears.
                                SizedBox(
                                  height: 24,
                                  child: Cue.onToggle(
                                    toggled: showStatus,
                                    motion: .smooth(),
                                    acts: [.fadeIn()],
                                    child: Text(
                                      _stageMessage(l10n),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: isDark
                                            ? AppColors.darkMutedText
                                            : AppColors.lightMutedText,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
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
