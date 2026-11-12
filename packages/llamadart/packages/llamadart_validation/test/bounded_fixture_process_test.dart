@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'support/bounded_fixture_process.dart';

const child = 'test/support/bounded_fixture_child.dart';

void main() {
  test('fixture exit code and both output streams are preserved', () async {
    final result = await runBoundedFixtureProcess(Platform.resolvedExecutable, [
      child,
      'exit',
    ], timeout: const Duration(seconds: 10));
    expect(result.exitCode, 7);
    expect(result.stdout, 'fixture-out\n');
    expect(result.stderr, 'fixture-err\n');
  });

  test('fixture stdin closes and spawn failure propagates', () async {
    final result = await runBoundedFixtureProcess(Platform.resolvedExecutable, [
      child,
      'stdin',
    ], timeout: const Duration(seconds: 10));
    expect(result.exitCode, 0);
    await expectLater(
      runBoundedFixtureProcess(
        '${Directory.systemTemp.path}/missing-fixture-executable',
        const [],
        timeout: const Duration(seconds: 1),
      ),
      throwsA(isA<ProcessException>()),
    );
  });

  test('deadline reaps a TERM-ignoring child and retains its output', () async {
    final temporary = Directory.systemTemp.createTempSync('fixture-deadline-');
    final pidFile = File('${temporary.path}/pid');
    addTearDown(() => temporary.deleteSync(recursive: true));
    await expectLater(
      runBoundedFixtureProcess(Platform.resolvedExecutable, [
        child,
        'hang',
        pidFile.path,
      ], timeout: const Duration(seconds: 1)),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'diagnostic',
          allOf(contains('fixture-out'), contains('fixture-err')),
        ),
      ),
    );
    expect(pidFile.existsSync(), isTrue);
    expect(Process.killPid(int.parse(pidFile.readAsStringSync())), isFalse);
  });

  test(
    'owner teardown reaps an outstanding child before scratch deletion',
    () async {
      final temporary = Directory.systemTemp.createTempSync(
        'fixture-teardown-',
      );
      final pidFile = File('${temporary.path}/pid');
      late Future<ProcessResult> pending;
      addTearDown(() async {
        try {
          final result = await pending.timeout(const Duration(seconds: 5));
          expect(result.exitCode, isNot(0));
          expect(Process.killPid(result.pid), isFalse);
        } finally {
          temporary.deleteSync(recursive: true);
        }
      });
      pending = runBoundedFixtureProcess(Platform.resolvedExecutable, [
        child,
        'hang',
        pidFile.path,
      ], timeout: const Duration(seconds: 30));
      final watch = Stopwatch()..start();
      while (!pidFile.existsSync()) {
        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // Leave the child outstanding: its later-registered teardown must run first.
    },
  );
}
