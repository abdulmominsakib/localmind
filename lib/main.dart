import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:pdfrx/pdfrx.dart';

import 'bootstrap/bootstrap_host.dart';
import 'core/services/crash_report_service.dart';
import 'core/widgets/crash_error_widget.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await pdfrxFlutterInitialize();
      final crashReports = CrashReportService.instance;
      await crashReports.initialize();

      // Framework errors are reported both here and via ErrorWidget.builder
      // (because FlutterError.presentError eventually builds an ErrorWidget).
      // CrashReportService deduplicates identical errors within a 2-second
      // window, so the user sees only one crash screen per incident.
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        crashReports.capture(
          details.exception,
          details.stack ?? StackTrace.current,
          errorWidgetPayload: details.toString(),
        );
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        crashReports.capture(error, stack);
        return true;
      };

      ErrorWidget.builder = (details) {
        final captured = crashReports.capture(
          details.exception,
          details.stack ?? StackTrace.current,
          errorWidgetPayload: details.toString(),
        );
        return CrashErrorWidget(crash: captured);
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
