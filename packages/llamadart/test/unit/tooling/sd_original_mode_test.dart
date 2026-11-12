@TestOn('vm')
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'original-mode native/operator controls run without weights or a runtime',
    () async {
      final result = await Process.run('python3', const [
        '-m',
        'unittest',
        'discover',
        '-s',
        'packages/llamadart_validation/native/sd_original_mode',
        '-v',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stderr, matches(RegExp(r'Ran [1-9][0-9]* tests')));
      expect(result.stderr, isNot(contains('skipped=')));
    },
    skip: !Platform.isMacOS && !Platform.isLinux
        ? 'POSIX ownership and dladdr source controls'
        : false,
  );
}
