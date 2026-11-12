import 'dart:io';

import 'package:test/test.dart';

import '../bin/run.dart' as launcher;

void main() {
  late Directory output;
  final fixtures = Directory('test/fixtures/windows_native_log');
  setUp(() {
    output = Directory.systemTemp.createTempSync('run-native-report-');
    File(
      '${fixtures.path}/tiny.events.jsonl',
    ).copySync('${output.path}/events.jsonl');
  });
  tearDown(() => output.deleteSync(recursive: true));

  test('same tiny CUDA journal requires its native log to qualify', () {
    final without = launcher.writeRunReports(output);
    expect(without.assertionsPassed, isTrue);
    expect(without.qualified, isFalse);
    final withLog = launcher.writeRunReports(
      output,
      nativeLogPath: '${fixtures.path}/tiny.native.txt',
    );
    expect(withLog.qualified, isTrue);
    expect(withLog.cases.length, 15);
  });
  test('native proof does not waive an actual history case failure', () {
    File(
      '${fixtures.path}/chat.events.jsonl',
    ).copySync('${output.path}/events.jsonl');
    final report = launcher.writeRunReports(
      output,
      nativeLogPath: '${fixtures.path}/chat.native.txt',
    );
    expect(report.qualified, isFalse);
    expect(
      report.cases.singleWhere(
        (row) => row['case_id'] == 'C06.history',
      )['status'],
      'FAIL',
    );
  });
  test('missing capture is an error', () {
    expect(
      () => launcher.writeRunReports(
        output,
        nativeLogPath: '${output.path}/missing',
      ),
      throwsA(isA<FileSystemException>()),
    );
  });
  test('invalid UTF-8 capture is an error', () {
    final log = File('${output.path}/invalid')..writeAsBytesSync([0xff]);
    expect(
      () => launcher.writeRunReports(output, nativeLogPath: log.path),
      throwsA(isA<FileSystemException>()),
    );
  });
  test('empty or unrelated text does not manufacture GPU proof', () {
    final log = File('${output.path}/empty');
    for (final text in ['', 'GPU success']) {
      log.writeAsStringSync(text);
      expect(
        launcher.writeRunReports(output, nativeLogPath: log.path).qualified,
        isFalse,
      );
    }
  });
  test('CLI rejects missing capture before runtime or model work', () async {
    final missing = '${output.path}/missing-cli';
    final run = await Process.run(Platform.resolvedExecutable, [
      '--packages=.dart_tool/package_config.json',
      'bin/run.dart',
      '--native-log',
      missing,
      '--profile',
      'tiny-gguf-cuda',
    ]);
    expect(run.exitCode, 1);
    expect('${run.stderr}', contains(missing));
    expect('${run.stderr}', contains('Cannot open file'));
    expect('${run.stdout}', isNot(contains('LLAMADART_VALIDATION')));
  });
  test('CLI rejects invalid UTF-8 capture before model work', () async {
    final log = File('${output.path}/invalid-cli')..writeAsBytesSync([0xff]);
    final run = await Process.run(Platform.resolvedExecutable, [
      '--packages=.dart_tool/package_config.json',
      'bin/run.dart',
      '--native-log',
      log.path,
      '--profile',
      'tiny-gguf-cuda',
    ]);
    expect(run.exitCode, 1);
    expect('${run.stderr}', contains('Failed to decode'));
    expect('${run.stdout}', isNot(contains('LLAMADART_VALIDATION')));
  });
}
