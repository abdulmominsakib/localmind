import 'dart:async';
import 'dart:io' show Platform;

import 'package:characters/characters.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Immutable payload describing a captured crash.
class CrashReport {
  CrashReport({
    required this.error,
    required this.errorType,
    required this.stackTrace,
    required this.timestamp,
    required this.appVersion,
    required this.buildNumber,
    required this.platform,
    required this.osVersion,
    required this.deviceManufacturer,
    required this.deviceModel,
    required this.locale,
    this.errorWidgetPayload,
  });

  final Object error;
  final String errorType;
  final StackTrace stackTrace;
  final DateTime timestamp;
  final String appVersion;
  final String buildNumber;
  final String platform;
  final String osVersion;
  final String deviceManufacturer;
  final String deviceModel;
  final String locale;
  final String? errorWidgetPayload;

  /// First non-empty line of the error, truncated. Used for the issue title.
  String get shortError {
    final raw = _sanitizePaths(error.toString().trim());
    if (raw.isEmpty) return errorType;
    final firstLine = raw.split('\n').first.trim();
    final chars = firstLine.characters;
    if (chars.length <= 80) return firstLine;
    return '${chars.take(77)}...';
  }

  /// Issue body markdown for GitHub. Built lazily when accessed so URL
  /// generation remains synchronous and side-effect-free.
  String get markdownBody {
    final stack = _truncate(
      _sanitizePaths(stackTrace.toString()),
      3000,
    );
    final cleanStack = _stripBackticks(stack);
    final ts = timestamp.toUtc().toIso8601String();

    final buffer = StringBuffer()
      ..writeln('## App Info')
      ..writeln('- **Version:** $appVersion')
      ..writeln('- **Build:** $buildNumber')
      ..writeln('- **Timestamp (UTC):** $ts')
      ..writeln('- **Locale:** $locale')
      ..writeln()
      ..writeln('## Device Info')
      ..writeln('- **Platform:** $platform ($osVersion)')
      ..writeln('- **Device:** $deviceManufacturer $deviceModel')
      ..writeln()
      ..writeln('## Crash Details')
      ..writeln()
      ..writeln('```text')
      ..writeln(_stripBackticks(_sanitizePaths(error.toString())))
      ..writeln('```');

    if (errorWidgetPayload != null && errorWidgetPayload!.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('**FlutterErrorDetails:**')
        ..writeln()
        ..writeln('```text')
        ..writeln(
          _stripBackticks(
            _truncate(_sanitizePaths(errorWidgetPayload!), 2000),
          ),
        )
        ..writeln('```');
    }

    buffer
      ..writeln()
      ..writeln('## Stack Trace')
      ..writeln()
      ..writeln('```text')
      ..writeln(cleanStack)
      ..writeln('```')
      ..writeln()
      ..writeln('## Steps to Reproduce')
      ..writeln('1. ')
      ..writeln('2. ')
      ..writeln()
      ..writeln('## Expected Behavior')
      ..writeln()
      ..writeln('<!-- What did you expect to happen? -->')
      ..writeln()
      ..writeln('## Actual Behavior')
      ..writeln()
      ..writeln('<!-- What happened instead? -->')
      ..writeln()
      ..writeln('## Additional Context')
      ..writeln()
      ..writeln(
        '<!-- Please remove any sensitive chat or model data before submitting. -->',
      );

    return buffer.toString();
  }

  String _truncate(String input, int max) {
    if (input.length <= max) return input;
    return '${input.substring(0, max)}\n\n…(truncated)…';
  }

  String _stripBackticks(String input) => input.replaceAll('```', "'''");

  /// Replaces user-specific path segments (home directories, Android package
  /// paths) with placeholders so that crash reports do not leak usernames or
  /// absolute paths while preserving the structure of the stack trace.
  String _sanitizePaths(String input) {
    return input
        .replaceAllMapped(
          RegExp(r'/Users/[^/\s]+'),
          (_) => '/Users/<user>',
        )
        .replaceAllMapped(
          RegExp(r'/home/[^/\s]+'),
          (_) => '/home/<user>',
        )
        .replaceAllMapped(
          RegExp(r'/data/user/[^/\s]+'),
          (_) => '/data/user/<user>',
        )
        .replaceAllMapped(
          RegExp(r'C:\\Users\\[^\\\s]+'),
          (_) => r'C:\Users\<user>',
        );
  }
}

/// Singleton that captures, dedupes, and exposes crashes for the UI layer.
///
/// Capture path is wired in `lib/main.dart`:
///   * `FlutterError.onError` — framework errors
///   * `PlatformDispatcher.instance.onError` — async zone errors
///   * `ErrorWidget.builder` — build-time errors
///   * `runZonedGuarded` callback — top-level uncaught
class CrashReportService {
  CrashReportService._();

  static final CrashReportService instance = CrashReportService._();

  static const String repoOwner = 'abdulmominsakib';
  static const String repoName = 'localmind';
  static const String issueTemplate = 'crash_report.md';

  final ValueNotifier<CrashReport?> _currentCrash = ValueNotifier<CrashReport?>(
    null,
  );
  final List<CrashReport> _recentCrashes = <CrashReport>[];

  PackageInfo? _packageInfo;
  String _appVersion = 'unknown';
  String _buildNumber = 'unknown';
  String _platformLabel = _platformFromDart();
  String _osVersion = 'unknown';
  String _deviceManufacturer = 'unknown';
  String _deviceModel = 'unknown';
  bool _initialized = false;

  /// Listenable for the UI. Wrap your root with a `ValueListenableBuilder`
  /// so an async crash can take over the entire app.
  ValueListenable<CrashReport?> get currentCrash => _currentCrash;

  /// Maximum time window (ms) within which two identical errors collapse
  /// into a single report — `FlutterError.onError` and `ErrorWidget.builder`
  /// frequently fire for the same exception.
  static const Duration _dedupeWindow = Duration(seconds: 2);

  /// Initialize device + app metadata. Safe to call multiple times.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _packageInfo = await PackageInfo.fromPlatform();
      _appVersion = _packageInfo?.version ?? 'unknown';
      _buildNumber = _packageInfo?.buildNumber ?? 'unknown';
    } catch (_) {}

    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        _platformLabel = 'Android';
        _osVersion =
            'Android ${android.version.release} (SDK ${android.version.sdkInt})';
        _deviceManufacturer = android.manufacturer;
        _deviceModel = android.model;
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        _platformLabel = 'iOS';
        _osVersion = '${ios.systemName} ${ios.systemVersion}';
        _deviceManufacturer = 'Apple';
        _deviceModel = ios.utsname.machine;
      }
    } catch (_) {}
  }

  /// Record a crash. Returns the captured `CrashReport` for the caller to use
  /// (e.g. `ErrorWidget.builder` rendering).
  ///
  /// Setting `_currentCrash.value` from inside `ErrorWidget.builder` is safe:
  /// `ValueNotifier` schedules a rebuild via `markNeedsBuild` rather than
  /// building synchronously, so it will not trigger a "dirty during build"
  /// assertion.
  CrashReport capture(
    Object error,
    StackTrace stack, {
    String? errorWidgetPayload,
  }) {
    final report = CrashReport(
      error: error,
      errorType: error.runtimeType.toString(),
      stackTrace: stack,
      timestamp: DateTime.now(),
      appVersion: _appVersion,
      buildNumber: _buildNumber,
      platform: _platformLabel,
      osVersion: _osVersion,
      deviceManufacturer: _deviceManufacturer,
      deviceModel: _deviceModel,
      locale: PlatformDispatcher.instance.locale.toString(),
      errorWidgetPayload: errorWidgetPayload,
    );

    // The duplicate check must run before the report is recorded, otherwise
    // the freshly added report matches itself and no crash would ever surface
    // in the UI.
    final isDuplicate = _isDuplicate(report);

    _recentCrashes.add(report);
    if (_recentCrashes.length > 20) {
      _recentCrashes.removeAt(0);
    }

    if (!isDuplicate) {
      _currentCrash.value = report;
    }
    return report;
  }

  /// Clear the current crash so the app can re-render normally.
  void clearCrash() {
    _currentCrash.value = null;
  }

  /// Construct a prefilled "new issue" URL pointing at the GitHub repo.
  /// `Uri.https` percent-encodes everything — never manually encode.
  Uri buildGitHubIssueUrl(CrashReport report) {
    final title = 'Crash: ${report.shortError}';
    final params = <String, String>{
      'title': title,
      'body': report.markdownBody,
      'labels': 'crash,bug',
      'template': issueTemplate,
    };
    return Uri.https('github.com', '/$repoOwner/$repoName/issues/new', params);
  }

  /// Plain feedback URL used by the "Report a problem" Settings tile —
  /// distinct from the crash flow; no diagnostics are included.
  Uri buildFeedbackIssueUrl() {
    return Uri.https(
      'github.com',
      '/$repoOwner/$repoName/issues/new',
      <String, String>{
        'title': 'Feedback',
        'labels': 'feedback',
        'template': issueTemplate,
      },
    );
  }

  /// Resets the singleton state. Intended for tests only.
  @visibleForTesting
  void resetForTesting() {
    _initialized = false;
    _packageInfo = null;
    _appVersion = 'unknown';
    _buildNumber = 'unknown';
    _platformLabel = _platformFromDart();
    _osVersion = 'unknown';
    _deviceManufacturer = 'unknown';
    _deviceModel = 'unknown';
    _recentCrashes.clear();
    _currentCrash.value = null;
  }

  bool _isDuplicate(CrashReport report) {
    final cutoff = DateTime.now().subtract(_dedupeWindow);
    for (final prior in _recentCrashes.reversed) {
      if (prior.timestamp.isBefore(cutoff)) return false;
      if (prior.errorType == report.errorType &&
          prior.error.toString() == report.error.toString()) {
        return true;
      }
    }
    return false;
  }

  static String _platformFromDart() {
    try {
      if (Platform.isAndroid) return 'Android';
      if (Platform.isIOS) return 'iOS';
      return Platform.operatingSystem;
    } catch (_) {
      return 'unknown';
    }
  }
}
