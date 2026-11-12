@TestOn('vm && linux')
library;

import 'package:test/test.dart';

import 'support/bounded_process.dart';

void main() {
  test(
    'Chrome supervisor requires real exit, complete output and owned cleanup',
    () async {
      final result = await runBoundedProcess('python3', [
        '-m',
        'unittest',
        'discover',
        '-s',
        'test/ci',
        '-p',
        'test_supervise_chrome_test.py',
      ], timeout: const Duration(seconds: 60));
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
