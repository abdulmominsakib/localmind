// The gate runs only on Linux, where CI's "Select affected checks" job also
// runs this unittest. On GitHub's Windows runners, process start-up there has
// stalled past this suite's 30 s timeout while in-process tests kept running.
@TestOn('vm && !windows')
library;

import 'package:test/test.dart';

import 'support/bounded_process.dart';

void main() {
  test(
    'archive gate rejects private files and failed extracted consumers',
    () async {
      final result = await runBoundedProcess('python3', [
        '-m',
        'unittest',
        'discover',
        '-s',
        'test/ci',
        '-p',
        'test_core_archive.py',
      ], timeout: const Duration(seconds: 20));
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );
}
