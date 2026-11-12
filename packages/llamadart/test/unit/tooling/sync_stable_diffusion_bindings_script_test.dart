@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'stable_diffusion header sync verifies the pinned archive before staging',
    () async {
      final result = await Process.run('python3', [
        'tool/native/test_sync_stable_diffusion_bindings.py',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect('${result.stdout}${result.stderr}', contains('OK'));
    },
  );
}
