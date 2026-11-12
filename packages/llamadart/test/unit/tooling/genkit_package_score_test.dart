@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test(
    'candidate package scoring binds source and rejects stale metadata',
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
            'test_genkit_package_score.py',
          ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, contains('OK'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('candidate scoring is CI only and publication keeps public Pana', () {
    final ci = File('.github/workflows/ci.yml').readAsStringSync();
    expect(ci, contains('python3 tool/ci/check_genkit_package_score.py'));
    final checkout = loadYaml(ci)['jobs']['genkit']['steps'].first;
    expect(checkout['with'], {'fetch-depth': 0, 'persist-credentials': false});
    final publisher = File(
      '.github/workflows/publish_genkit_pubdev.yml',
    ).readAsStringSync();
    expect(
      publisher,
      contains('dart pub global run pana . --exit-code-threshold 0'),
    );
    expect(publisher, isNot(contains('check_genkit_package_score.py')));
  });
}
