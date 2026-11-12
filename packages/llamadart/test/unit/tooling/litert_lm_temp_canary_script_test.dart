@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _script = 'tool/ci/litert_lm_temp_canary.sh';
const _cap = 1 << 30;

void main() {
  late Directory root;
  late Directory runnerTemp;
  late File githubEnv;

  setUp(() {
    root = Directory.systemTemp.createTempSync('litert-temp-canary-');
    runnerTemp = Directory(p.join(root.path, 'runner-temp'))..createSync();
    githubEnv = File(p.join(root.path, 'github_env'))..createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  // The parent environment is dropped so a CI runner's own RUNNER_TEMP and
  // GITHUB_ENV can never point the script at real paths.
  Future<ProcessResult> run(
    String command, {
    bool withRunnerTemp = true,
    bool withGithubEnv = true,
  }) {
    return Process.run(
      'bash',
      [_script, command],
      includeParentEnvironment: false,
      environment: {
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        if (withRunnerTemp) 'RUNNER_TEMP': runnerTemp.path,
        if (withGithubEnv) 'GITHUB_ENV': githubEnv.path,
      },
    );
  }

  String scratch() => p.join(runnerTemp.path, 'llamadart-test-tmp');

  File canary() => File(
    p.join(
      scratch(),
      'llamadart_litert_lm',
      'ci-canary.litertlm_1_2_mldrift_program_cache.bin',
    ),
  );

  group('litert_lm_temp_canary.sh', () {
    test(
      'seed redirects temp variables and plants a canary over the cap',
      () async {
        final result = await run('seed');

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(githubEnv.readAsLinesSync(), [
          'TMPDIR=${scratch()}',
          'TEMP=${scratch()}',
          'TMP=${scratch()}',
        ]);
        expect(canary().lengthSync(), greaterThan(_cap));
      },
    );

    test('check passes while the canary is present', () async {
      expect((await run('seed')).exitCode, 0);

      final result = await run('check');

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stderr, isEmpty);
    });

    test(
      'check fails with an error annotation once the canary is deleted',
      () async {
        expect((await run('seed')).exitCode, 0);
        expect(canary().existsSync(), isTrue);
        canary().deleteSync();

        final result = await run('check');

        expect(result.exitCode, 1);
        expect(result.stderr, contains('::error::'));
        expect(result.stderr, contains(canary().path));
      },
    );

    test('check fails before seeding', () async {
      final result = await run('check');

      expect(result.exitCode, 1);
      expect(result.stderr, contains('::error::'));
    });

    test('fails without RUNNER_TEMP', () async {
      final result = await run('seed', withRunnerTemp: false);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('RUNNER_TEMP'));
      expect(githubEnv.readAsStringSync(), isEmpty);
    });

    test('fails without GITHUB_ENV', () async {
      final result = await run('seed', withGithubEnv: false);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('GITHUB_ENV'));
    });

    test('rejects an unknown command', () async {
      final result = await run('bogus');

      expect(result.exitCode, 64);
      expect(result.stderr, contains('usage:'));
    });
  }, skip: Platform.isWindows ? 'requires a POSIX Bash runtime' : false);
}
