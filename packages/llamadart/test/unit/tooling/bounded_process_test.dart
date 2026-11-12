@TestOn('vm && !windows')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

import 'support/bounded_process.dart';

void main() {
  test('returns the exit code and output of a child', () async {
    final result = await runBoundedProcess('sh', const [
      '-c',
      'echo out; echo err >&2; exit 3',
    ], timeout: const Duration(seconds: 30));

    expect(result.exitCode, 3);
    expect(result.stdout, 'out\n');
    expect(result.stderr, 'err\n');
  });

  test('gives a child that reads stdin end-of-file', () async {
    final result = await runBoundedProcess(
      'cat',
      const [],
      timeout: const Duration(seconds: 30),
    );

    expect(result.exitCode, 0);
  });

  test('runs a child in the requested working directory', () async {
    final directory = Directory.systemTemp.createTempSync(
      'bounded-process-cwd-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/marker').writeAsStringSync('requested directory');
    final result = await runBoundedProcess(
      'cat',
      const ['marker'],
      workingDirectory: directory.path,
      timeout: const Duration(seconds: 30),
    );
    expect(result.exitCode, 0);
    expect(result.stdout, 'requested directory');
  });

  test('kills and reaps a TERM-ignoring child past its budget', () async {
    final stopwatch = Stopwatch()..start();
    final directory = Directory.systemTemp.createTempSync('bounded-process-');
    final childPid = File('${directory.path}/pid');
    addTearDown(() {
      if (childPid.existsSync()) {
        Process.killPid(
          int.parse(childPid.readAsStringSync().trim()),
          ProcessSignal.sigkill,
        );
      }
      directory.deleteSync(recursive: true);
    });

    await expectLater(
      runBoundedProcess('sh', [
        '-c',
        r'trap "" TERM; echo $$ > "$1"; echo partial-out; echo partial-err >&2; exec sleep 30',
        'bounded-process-test',
        childPid.path,
      ], timeout: const Duration(seconds: 1)),
      throwsA(
        isA<TestFailure>().having(
          (failure) => failure.message,
          'message',
          allOf(
            contains('did not exit within 1 s'),
            contains('stdout:\npartial-out\n'),
            contains('stderr:\npartial-err\n'),
          ),
        ),
      ),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 20)));
    expect(childPid.existsSync(), isTrue);
    final probe = await Process.run('kill', [
      '-0',
      childPid.readAsStringSync().trim(),
    ]);
    expect(
      probe.exitCode,
      isNot(0),
      reason: 'The timed-out direct child must be killed and reaped.',
    );
  });

  test(
    'reports the scheduler state of a timed-out child',
    testOn: 'linux',
    () async {
      await expectLater(
        runBoundedProcess('sleep', const [
          '30',
        ], timeout: const Duration(seconds: 1)),
        throwsA(
          isA<TestFailure>().having(
            (failure) => failure.message,
            'message',
            allOf(
              contains('did not exit within 1 s.\nChild '),
              contains(' at timeout: State:\tS (sleeping); wchan: '),
              matches(RegExp(r'; read_bytes: \d+\n')),
            ),
          ),
        ),
      );
    },
  );

  test(
    'interrupted tests reap children before deleting their directory',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'bounded-interrupt-',
      );
      final working = Directory('${directory.path}/working')..createSync();
      final pid = File('${directory.path}/pid');
      final receipt = File('${directory.path}/alive-at-delete');
      addTearDown(() async {
        if (pid.existsSync()) {
          Process.killPid(
            int.parse(pid.readAsStringSync()),
            ProcessSignal.sigkill,
          );
        }
        directory.deleteSync(recursive: true);
      });
      final config = File('.dart_tool/package_config.json').absolute.path;
      final testLibrary = await Isolate.resolvePackageUri(
        Uri.parse('package:test/test.dart'),
      );
      final runner = testLibrary!.resolve('../bin/test.dart').toFilePath();
      final helper = File(
        'test/unit/tooling/support/bounded_process.dart',
      ).absolute.uri;
      final fixture = File('${directory.path}/interrupted_test.dart');
      fixture.writeAsStringSync('''
import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';
import '$helper';

void main() {
  test('interrupted owner', () async {
    final working = Directory(${_dartString(working.path)});
    final pid = File(${_dartString(pid.path)});
    addTearDown(() async {
      final probe = await Process.run('kill', ['-0', pid.readAsStringSync().trim()]);
      File(${_dartString(receipt.path)}).writeAsStringSync('\${probe.exitCode}');
      working.deleteSync(recursive: true);
    });
    unawaited(runBoundedProcess('sh', [
      '-c', r'echo \$\$ > "\$1"; exec sleep 30', 'interrupted-child', pid.path,
    ], workingDirectory: working.path, timeout: const Duration(seconds: 20)));
    while (!pid.existsSync()) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('interrupt control');
  });
}
''');
      final result = await runBoundedProcess(Platform.resolvedExecutable, [
        '--packages=$config',
        runner,
        '-p',
        'vm',
        fixture.path,
      ], timeout: const Duration(seconds: 45));
      expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
      expect('${result.stdout}', contains('interrupt control'));
      expect(
        int.parse(receipt.readAsStringSync()),
        isNot(0),
        reason:
            'The child must be reaped before its working directory is deleted.',
      );
      expect(working.existsSync(), isFalse);
    },
  );
}

String _dartString(String value) => jsonEncode(value).replaceAll(r'$', r'\$');
