@TestOn('vm')
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'default consumer qualification controls run without SDK or model inputs',
    () async {
      final result = await Process.run(
        Platform.isWindows ? 'python' : 'python3',
        const [
          '-B',
          '-m',
          'unittest',
          'discover',
          '-s',
          'test/fixtures/native_default_consumer_qualification',
          '-p',
          'test_*.py',
          '-v',
        ],
        environment: const {'PYTHONDONTWRITEBYTECODE': '1'},
      );
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stderr, matches(RegExp(r'Ran [1-9][0-9]* tests')));
    },
  );
}
