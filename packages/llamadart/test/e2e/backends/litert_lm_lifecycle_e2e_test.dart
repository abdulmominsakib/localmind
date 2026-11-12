@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final model = Platform.environment['LITERT_LM_MODEL'];
  final backend = Platform.environment['LITERT_LM_BACKEND'] ?? 'cpu';
  final output = Directory(
    Platform.environment['LITERT_LM_LIFECYCLE_LOG_DIR'] ??
        '.dart_tool/litert_lm_lifecycle',
  );
  late String executable;
  setUpAll(() async {
    await output.create(recursive: true);
    executable =
        '${output.absolute.path}/lifecycle${Platform.isWindows ? '.exe' : ''}';
    final result = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      'test/fixtures/litert_lm_lifecycle.dart',
      '-o',
      executable,
    ]).timeout(const Duration(minutes: 2));
    await File(
      '${output.path}/compile.log',
    ).writeAsString('${result.stdout}\n${result.stderr}');
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
  for (final mode in ['recovery', 'timeout']) {
    test(
      'real LiteRT-LM $mode exits within a bounded process lifetime',
      () async {
        if (model == null || !File(model).existsSync()) {
          fail('Set LITERT_LM_MODEL to an existing .litertlm model.');
        }
        await output.create(recursive: true);
        final process = await Process.start(executable, [model, backend, mode]);
        final stdout = process.stdout.transform(utf8.decoder).join();
        final stderr = process.stderr.transform(utf8.decoder).join();
        int? code;
        var timedOut = false;
        try {
          code = await process.exitCode.timeout(
            Duration(seconds: mode == 'recovery' ? 240 : 120),
          );
        } on TimeoutException {
          timedOut = true;
          process.kill(ProcessSignal.sigkill);
          code = await process.exitCode;
        } finally {
          process.kill();
        }
        final text = await stdout;
        final nativeLog = await stderr;
        await File('${output.path}/$mode.stdout.log').writeAsString(text);
        await File('${output.path}/$mode.stderr.log').writeAsString(nativeLog);
        await File('${output.path}/$mode.process.json').writeAsString(
          jsonEncode({'exit_code': code, 'outer_timeout': timedOut}),
        );
        expect(
          timedOut,
          isFalse,
          reason: 'Owned child exceeded outer deadline. $text',
        );
        final events = text
            .split('\n')
            .where((line) => line.startsWith('{'))
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .toList();
        final stages = events.map((event) => event['stage']).toList();
        expect(stages, isNot(contains('failure')), reason: text);
        expect(stages.last, 'run_end');
        final cleanupFailed = stages.contains('cleanup_error');
        expect(code, cleanupFailed ? 1 : 0, reason: '$text\n$nativeLog');
        if (mode == 'recovery') {
          expect(stages.where((stage) => stage == 'generation'), hasLength(3));
          expect(
            stages,
            containsAll([
              'unloaded_rejected',
              'missing_model_rejected',
              'cleanup_pass',
            ]),
          );
        } else {
          expect(
            stages,
            containsAllInOrder([
              'operation_timeout',
              cleanupFailed ? 'cleanup_error' : 'cleanup_pass',
              cleanupFailed
                  ? 'pending_failed'
                  : anyOf('pending_completed', 'pending_failed'),
              'run_end',
            ]),
          );
        }
      },
    );
  }
}
