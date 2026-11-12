@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

import '../../../support/dart_script_snapshot.dart';

void main() {
  // `dart <source>` compiles the program before main runs, which took over
  // the probe's 2 s deadline on loaded macOS CI runners; kernels keep the
  // probe and outer deadlines measuring only the diagnostic itself.
  late final String probe;
  late final String child;
  late final String fakeChild;
  setUpAll(() async {
    probe = await compileDartScript(
      'test/fixtures/native_diagnostics_deadline_probe.dart',
    );
    child = await compileDartScript(
      'lib/src/platform/io/native_diagnostics_child.dart',
    );
    fakeChild = await compileDartScript(
      'test/fixtures/native_diagnostics_fake_child.dart',
    );
  });

  for (final (mode, expected, starts) in [
    ('regular', 'ARTIFACT_MISSING', 1),
    ('fifo-manifest', 'ASSET_DECLARATION_INVALID', 0),
    ('link-manifest', 'ASSET_DECLARATION_INVALID', 0),
    ('swap-manifest', 'ASSET_DECLARATION_INVALID', 1),
    ('fifo-result', 'CHILD_PROTOCOL_INVALID', 1),
    ('fifo-phase', 'CHILD_PROTOCOL_INVALID', 1),
    ('link-result', 'CHILD_PROTOCOL_INVALID', 1),
    ('link-phase', 'CHILD_PROTOCOL_INVALID', 1),
  ]) {
    test(
      'bounded report and CLI exit for $mode',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'diagnostic_deadline_',
        );
        final pidFile = File('${directory.path}/owned-child-pid');
        final config = (await Isolate.packageConfig)!;
        final process = await Process.start(Platform.resolvedExecutable, [
          '--disable-dart-dev',
          '--packages=${config.toFilePath()}',
          probe,
          mode,
          directory.path,
          pidFile.path,
          mode == 'regular' || mode.endsWith('manifest') ? child : fakeChild,
        ]);
        final output = <int>[];
        final errors = <int>[];
        final out = process.stdout.listen((chunk) {
          if (output.length < 8192) output.addAll(chunk);
        });
        final err = process.stderr.listen((chunk) {
          if (errors.length < 8192) errors.addAll(chunk);
        });
        var exited = false;
        try {
          int code;
          try {
            // This outer process deadline is deliberately independent of the
            // coordinator: a blocked parent File.open must fail, not hang CI.
            code = await process.exitCode.timeout(const Duration(seconds: 7));
            exited = true;
          } on TimeoutException {
            throw TestFailure(
              'Diagnostic probe did not exit within its outer guard',
            );
          }
          await out.cancel();
          await err.cancel();
          expect(code, 0);
          expect(errors, isEmpty);
          final receipt = jsonDecode(utf8.decode(output)) as Map;
          expect(receipt['code'], expected);
          expect(receipt['starts'], starts);
          expect(receipt['child_reaped'], isTrue);
          expect(receipt['private_output'], isTrue);
          expect(receipt['elapsed_ms'], lessThan(5000));
          if (!Platform.isWindows && pidFile.existsSync()) {
            final childPid = int.parse(pidFile.readAsStringSync());
            final alive = await Process.run('/bin/kill', ['-0', '$childPid']);
            expect(
              alive.exitCode,
              isNot(0),
              reason: 'Owned child must be gone before the probe exits',
            );
          }
          print('$mode: ${jsonEncode(receipt)}');
        } finally {
          if (!exited) {
            process.kill(ProcessSignal.sigkill);
            await process.exitCode.timeout(const Duration(seconds: 2));
            if (pidFile.existsSync()) {
              final childPid = int.tryParse(pidFile.readAsStringSync());
              if (childPid != null &&
                  childPid > 0 &&
                  childPid != pid &&
                  childPid != process.pid) {
                Process.killPid(childPid, ProcessSignal.sigkill);
              }
            }
          }
          await out.cancel();
          await err.cancel();
          await directory.delete(recursive: true);
        }
      },
      skip: mode != 'regular' && Platform.isWindows
          ? 'POSIX FIFO control; Windows native execution remains unqualified.'
          : false,
    );
  }
}
