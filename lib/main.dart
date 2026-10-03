import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_logger/marionette_logger.dart';
import 'package:pdfrx/pdfrx.dart';

import 'bootstrap/bootstrap_host.dart';
import 'core/logger/app_logger.dart';
import 'core/services/crash_report_service.dart';
import 'core/widgets/crash_error_widget.dart';
import 'core/widgets/inline_build_error.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      final isFlutterTest =
          !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
      if (!kReleaseMode && !isFlutterTest) {
        final logCollector = LoggerLogCollector();
        Log.attachOutput(logCollector);
        MarionetteBinding.ensureInitialized(
          MarionetteConfiguration(logCollector: logCollector),
        );
      } else {
        WidgetsFlutterBinding.ensureInitialized();
      }
      await pdfrxFlutterInitialize();
      final crashReports = CrashReportService.instance;
      await crashReports.initialize();

      // Errors the framework reports from building, layout, painting or
      // gestures are contained to the widget that threw, so they're logged
      // and recorded without replacing the app with the crash screen. That
      // screen is kept for errors nothing else caught (below).
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        if (CrashReportService.isBenignFrameworkError(
          details.exception,
          details.stack,
        )) {
          return;
        }
        crashReports.capture(
          details.exception,
          details.stack ?? StackTrace.current,
          errorWidgetPayload: details.toString(),
          showCrashScreen: false,
        );
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        if (CrashReportService.isBenignFrameworkError(error, stack)) {
          return true;
        }
        crashReports.capture(error, stack);
        return true;
      };

      // A widget that failed to build leaves a gap instead of taking over
      // the screen; debug builds mark the spot so the bug isn't missed.
      ErrorWidget.builder = (details) {
        if (!CrashReportService.isBenignFrameworkError(
          details.exception,
          details.stack,
        )) {
          crashReports.capture(
            details.exception,
            details.stack ?? StackTrace.current,
            errorWidgetPayload: details.toString(),
            showCrashScreen: false,
          );
        }
        return kDebugMode
            ? InlineBuildError(message: details.exceptionAsString())
            : const SizedBox.shrink();
      };

      await JustAudioBackground.init(
        androidNotificationChannelId:
            'com.abdulmominsakib.localmind.channel.audio',
        androidNotificationChannelName: 'LocalMind Audio TTS Playback',
        androidNotificationOngoing: true,
      );
      runApp(const CrashFallbackApp());
    },
    (error, stack) {
      if (CrashReportService.isBenignFrameworkError(error, stack)) {
        return;
      }
      CrashReportService.instance.capture(error, stack);
    },
  );
}

/// Root widget that swaps the entire app body for `CrashErrorWidget`
/// when an async/unhandled crash is captured outside `ErrorWidget.builder`'s
/// reach. `ErrorWidget.builder` still handles in-frame errors.
class CrashFallbackApp extends StatelessWidget {
  const CrashFallbackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CrashReport?>(
      valueListenable: CrashReportService.instance.currentCrash,
      builder: (context, crash, _) {
        if (crash != null) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: CrashErrorWidget(crash: crash),
          );
        }
        return const BootstrapHost();
      },
    );
  }
}
