@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'preview labels skip unrelated events and production stays main-only',
    () async {
      final result =
          await Process.run(Platform.isWindows ? 'python' : 'python3', [
            '-B',
            '-m',
            'unittest',
            'discover',
            '-s',
            'test/ci',
            '-p',
            'test_web_deployment.py',
          ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, contains('OK'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'preview writes require live state and same-run artifact provenance',
    () async {
      final result =
          await Process.run(Platform.isWindows ? 'python' : 'python3', [
            '-B',
            '-m',
            'unittest',
            'discover',
            '-s',
            'test/ci',
            '-p',
            'test_preview_guard.py',
          ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, contains('OK'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
