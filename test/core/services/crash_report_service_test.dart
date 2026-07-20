import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/services/crash_report_service.dart';

CrashReport _makeReport({
  required Object error,
  required StackTrace stack,
  String? errorWidgetPayload,
}) {
  return CrashReport(
    error: error,
    errorType: error.runtimeType.toString(),
    stackTrace: stack,
    timestamp: DateTime(2026, 7, 20, 12, 0, 0),
    appVersion: '1.5.2',
    buildNumber: '57',
    platform: 'Android',
    osVersion: 'Android 14 (SDK 34)',
    deviceManufacturer: 'TestManufacturer',
    deviceModel: 'TestModel',
    locale: 'en_US',
    errorWidgetPayload: errorWidgetPayload,
  );
}

void main() {
  setUp(() {
    CrashReportService.instance.resetForTesting();
  });

  group('CrashReport', () {
    test('shortError returns first line when under limit', () {
      final report = _makeReport(
        error: Exception('Something went wrong'),
        stack: StackTrace.current,
      );
      expect(report.shortError, 'Something went wrong');
    });

    test('shortError truncates long first lines to 80 chars', () {
      final longMessage = 'A' * 200;
      final report = _makeReport(
        error: Exception(longMessage),
        stack: StackTrace.current,
      );
      expect(report.shortError.length, 80);
      expect(report.shortError, '${'A' * 77}...');
    });

    test('shortError sanitizes user-specific paths', () {
      final report = _makeReport(
        error: Exception(
          'File not found: /Users/janedoe/Documents/secret.txt',
        ),
        stack: StackTrace.current,
      );
      expect(report.shortError, isNot(contains('/Users/janedoe')));
      expect(report.shortError, contains('/Users/<user>'));
    });

    test('shortError does not split emoji grapheme clusters', () {
      final report = _makeReport(
        error: Exception('🚀' * 100),
        stack: StackTrace.current,
      );
      final value = report.shortError;
      expect(value.characters.length, lessThanOrEqualTo(80));
      // The trailing code unit must not be a lone high surrogate.
      final lastCodeUnit = value.codeUnits.last;
      expect(
        lastCodeUnit < 0xD800 || lastCodeUnit > 0xDBFF,
        isTrue,
        reason: 'shortError should not end with a high surrogate',
      );
    });

    test('markdownBody contains expected sections', () {
      final report = _makeReport(
        error: Exception('Oops'),
        stack: StackTrace.fromString('#0 somewhere (file.dart:1:2)'),
      );
      final body = report.markdownBody;
      expect(body, contains('## App Info'));
      expect(body, contains('## Device Info'));
      expect(body, contains('## Crash Details'));
      expect(body, contains('## Stack Trace'));
      expect(body, contains('## Steps to Reproduce'));
      expect(body, contains('## Expected Behavior'));
      expect(body, contains('## Actual Behavior'));
      expect(body, contains('## Additional Context'));
    });

    test('markdownBody escapes triple backticks', () {
      final report = _makeReport(
        error: Exception('```code```'),
        stack: StackTrace.fromString('#0 frame (file.dart:1:2)'),
      );
      final body = report.markdownBody;
      expect(body, isNot(contains('```code```')));
      expect(body, contains("'''code'''"));
    });

    test('markdownBody sanitizes user-specific paths', () {
      final report = _makeReport(
        error: Exception(
          'File not found: /Users/janedoe/Documents/secret.txt',
        ),
        stack: StackTrace.fromString(
          '#0 frame (/home/johndoe/app/main.dart:1:2)',
        ),
      );
      final body = report.markdownBody;
      expect(body, isNot(contains('/Users/janedoe')));
      expect(body, isNot(contains('/home/johndoe')));
      expect(body, contains('/Users/<user>'));
      expect(body, contains('/home/<user>'));
    });

    test('generated GitHub URL stays under a safe length', () {
      final longStack = '#0 frame (file.dart:1:2)\n' * 500;
      final report = _makeReport(
        error: Exception('Oops'),
        stack: StackTrace.fromString(longStack),
      );
      final service = CrashReportService.instance;
      final url = service.buildGitHubIssueUrl(report).toString();
      expect(url.length, lessThan(8192));
    });
  });

  group('CrashReportService', () {
    test('buildGitHubIssueUrl points to the configured repo and template', () {
      final report = _makeReport(
        error: Exception('Boom'),
        stack: StackTrace.current,
      );
      final uri = CrashReportService.instance.buildGitHubIssueUrl(report);
      expect(uri.host, 'github.com');
      expect(uri.path, '/abdulmominsakib/localmind/issues/new');
      expect(uri.queryParameters['template'], 'crash_report.md');
      expect(uri.queryParameters['labels'], 'crash,bug');
      expect(uri.queryParameters['title'], 'Crash: Boom');
      expect(uri.queryParameters['body'], isNotNull);
    });

    test('buildFeedbackIssueUrl points to the feedback form', () {
      final uri = CrashReportService.instance.buildFeedbackIssueUrl();
      expect(uri.path, '/abdulmominsakib/localmind/issues/new');
      expect(uri.queryParameters['template'], 'crash_report.md');
      expect(uri.queryParameters['labels'], 'feedback');
      expect(uri.queryParameters['title'], 'Feedback');
    });

    test('capture deduplicates identical errors within the window', () {
      final service = CrashReportService.instance;
      final error = Exception('Same error');
      final stack = StackTrace.current;

      service.capture(error, stack);
      expect(service.currentCrash.value, isNotNull);

      service.clearCrash();
      service.capture(error, stack);
      expect(service.currentCrash.value, isNull);
    });

    test('capture does not deduplicate different errors', () {
      final service = CrashReportService.instance;
      service.capture(Exception('First'), StackTrace.current);
      service.clearCrash();
      service.capture(Exception('Second'), StackTrace.current);
      expect(service.currentCrash.value, isNotNull);
    });

    test('clearCrash resets the current crash', () {
      final service = CrashReportService.instance;
      service.capture(Exception('Oops'), StackTrace.current);
      expect(service.currentCrash.value, isNotNull);
      service.clearCrash();
      expect(service.currentCrash.value, isNull);
    });
  });
}
