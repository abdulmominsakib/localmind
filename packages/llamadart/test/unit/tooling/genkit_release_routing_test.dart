@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'independent release shell routes and failures cannot publish another package',
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
            'test_genkit_release.py',
          ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, contains('OK'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: Platform.isWindows
        ? 'Replays POSIX release steps; workflow selection and staging stay portable.'
        : false,
  );
}
