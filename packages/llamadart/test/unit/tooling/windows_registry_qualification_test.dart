@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

import '../../fixtures/windows_ggml_registry_qualification/payload/passive_modules.dart';
import 'support/bounded_process.dart';

bool _canRun(String executable) {
  try {
    return Process.runSync(executable, [
          '-NoLogo',
          '-Command',
          'exit 0',
        ]).exitCode ==
        0;
  } on ProcessException {
    return false;
  }
}

void main() {
  final shell = Platform.environment['LLAMADART_TEST_PWSH'] ?? 'pwsh';
  final pwshSkip = _canRun(shell)
      ? null
      : '$shell not found; install PowerShell or set LLAMADART_TEST_PWSH.';

  test(
    'maintained integration reporter proves execution without skips',
    () async {
      final scratch = await Directory.systemTemp.createTemp(
        'registry-reporter-',
      );
      addTearDown(() => scratch.delete(recursive: true));
      final root = scratch.resolveSymbolicLinksSync();
      final core = Directory('$root/core')..createSync();
      final tests = Directory('${core.path}/test/integration')
        ..createSync(recursive: true);
      Directory('${core.path}/.dart_tool').createSync();
      File(
        '.dart_tool/package_config.json',
      ).copySync('${core.path}/.dart_tool/package_config.json');
      File(
        '${core.path}/pubspec.yaml',
      ).writeAsStringSync('name: reporter_control\n');
      final testLibrary = await Isolate.resolvePackageUri(
        Uri.parse('package:test/test.dart'),
      );
      final runner = testLibrary!.resolve('../bin/test.dart').toFilePath();
      final config = File('.dart_tool/package_config.json').absolute.path;
      final kernel = '$root/test_runner.dill';
      // Reuse the real runner without recompiling its dependencies seven times.
      final compiled = await runBoundedProcess(Platform.resolvedExecutable, [
        'compile',
        'kernel',
        '--packages=$config',
        runner,
        '-o',
        kernel,
      ], timeout: const Duration(seconds: 60));
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );
      for (final variant in [
        'pass',
        'skip',
        'failure',
        'empty',
        'wrong-name',
        'multiple',
        'setup-failure',
      ]) {
        final body = variant == 'empty'
            ? ''
            : '''
${variant == 'setup-failure' ? "setUpAll(() => fail('setup control'));" : ''}
test('${variant == 'wrong-name' ? 'different test' : 'an external module directory does not open another ggml registry'}',
  () { ${variant == 'failure' ? "fail('test control');" : 'expect(1, 1);'} }, skip: ${variant == 'skip'});
${variant == 'multiple' ? "test('extra test', () {});" : ''}
''';
        File('${tests.path}/windows_ggml_registry_test.dart').writeAsStringSync(
          "import 'package:test/test.dart';\nvoid main() {$body}\n",
        );
        final watch = Stopwatch()..start();
        print('Registry reporter $variant started (45 s child budget)');
        final result = await runBoundedProcess(
          Platform.resolvedExecutable,
          [
            '--packages=$config',
            kernel,
            '-p',
            'vm',
            '-j',
            '1',
            '--file-reporter',
            'json:$root/$variant.events.json',
            'test/integration/windows_ggml_registry_test.dart',
          ],
          workingDirectory: core.path,
          environment: {'GITHUB_ACTIONS': 'true'},
          timeout: const Duration(seconds: 45),
        );
        print(
          'Registry reporter $variant elapsed ${watch.elapsedMilliseconds} ms',
        );
        expect(
          result.exitCode,
          variant == 'empty'
              ? 79
              : ['failure', 'setup-failure'].contains(variant)
              ? 1
              : 0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        if (variant == 'pass') {
          expect('${result.stdout}', contains('1 test passed.'));
          expect('${result.stdout}', isNot(contains('All tests passed!')));
        }
      }
      final result = await runBoundedProcess(shell, [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-File',
        'test/unit/tooling/support/windows_registry/check_registry_report.ps1',
        '-BundleRoot',
        Directory(
          'test/fixtures/windows_ggml_registry_qualification',
        ).absolute.path,
        '-ReportsRoot',
        root,
        '-OutputPath',
        '$root/receipt.json',
      ], timeout: const Duration(seconds: 30));
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    // The 405 s child budgets leave time for forced termination and reaping.
    timeout: const Timeout(Duration(minutes: 8)),
    skip: pwshSkip,
  );

  test('observer flushes complete before the next piped snapshot', () async {
    for (final mode in ['unawaited-flush', 'success', 'exception']) {
      final process = await Process.start(Platform.resolvedExecutable, [
        'test/fixtures/windows_ggml_registry_qualification/observer_stdout_probe.dart',
        mode,
      ]);
      addTearDown(() => process.kill());
      final ready = Completer<void>();
      final errors = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) {
            if (line == 'OBSERVER_STDOUT_READY' && !ready.isCompleted) {
              ready.complete();
            }
            return line;
          })
          .join('\n');
      unawaited(
        errors.then((_) {
          if (!ready.isCompleted) ready.complete();
        }),
      );
      // Keep the pipe full while the first snapshot starts its flush.
      await ready.future;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final output = process.stdout.transform(utf8.decoder).join();
      final code = await process.exitCode;
      final text = await output;
      final errorText = await errors;
      if (mode == 'unawaited-flush') {
        expect(code, isNot(0));
        expect(errorText, contains('StreamSink is bound to a stream'));
        continue;
      }
      expect(code, mode == 'exception' ? 7 : 0, reason: errorText);
      expect(errorText, contains('NATIVE_STDERR emitter-only cadence'));
      expect(errorText, isNot(contains('StreamSink is bound to a stream')));
      final lines = const LineSplitter().convert(text);
      expect(lines.first, startsWith('MODEL_OUTCOME $mode'));
      final identity = lines.indexWhere(
        (line) => line.startsWith('REGISTRY_IDENTITY '),
      );
      expect(identity, 65);
      expect(lines, hasLength(130));
      for (var index = 0; index < lines.length; index++) {
        if (index == 0 || index == identity) continue;
        expect(lines[index], startsWith('PASSIVE_MODULE '));
        final row = jsonDecode(lines[index].substring(15)) as Map;
        final second = index > identity;
        expect(
          row['checkpoint'],
          second ? 'after-registry-observation' : 'after-stock-model-$mode',
        );
        expect(row['registryGettersCalled'], second);
        expect(row['index'], second ? index - identity - 1 : index - 1);
        expect(row['emitterOnlyPadding'], 'x' * 16384);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 1)));

  test(
    'primary observer accepts real Windows separators and exact DLL leaf',
    () {
      for (final value in [
        r'C:\runtime\llama.dll',
        r'C:\RUNTIME\LLAMA.DLL',
        r'\\host\share\llama.dll',
      ]) {
        expect(isPrimaryLlamaModule(value), isTrue, reason: value);
      }
      for (final value in [
        r'C:\runtime\notllama.dll',
        r'C:\runtime\llama.dll.bak',
        r'C:\llama.dll\other.dll',
        'llama.dll',
      ]) {
        expect(isPrimaryLlamaModule(value), isFalse, reason: value);
      }
    },
  );

  test(
    'download verifier refuses omitted and false-success evidence',
    () async {
      final result =
          await Process.run(Platform.isWindows ? 'python' : 'python3', [
            'test/unit/tooling/support/windows_registry/check_evidence.py',
            Directory(
              'test/fixtures/windows_ggml_registry_qualification',
            ).absolute.path,
          ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );

  for (final name in [
    'protocol',
    'path',
    'registry_mutation',
    'aot_distribution',
    'matrix_workflow',
  ]) {
    test(
      'real qualification $name controls',
      () async {
        final scratch = await Directory.systemTemp.createTemp(
          'registry-controls-',
        );
        addTearDown(() => scratch.delete(recursive: true));
        final result = await Process.run(shell, [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-File',
          'test/unit/tooling/support/windows_registry/check_$name.ps1',
          '-BundleRoot',
          Directory(
            'test/fixtures/windows_ggml_registry_qualification',
          ).absolute.path,
          '-OutputPath',
          '${scratch.resolveSymbolicLinksSync()}/receipt.json',
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(
          File(
            '${scratch.resolveSymbolicLinksSync()}/receipt.json',
          ).existsSync(),
          isTrue,
        );
        if (name == 'protocol') {
          final verifier = [
            'test/fixtures/windows_ggml_registry_qualification/verify_evidence.py',
            '${scratch.resolveSymbolicLinksSync()}/protocol/evidence.zip',
            '--head',
            List.filled(40, 'a').join(),
            '--run-id',
            '12',
            '--run-attempt',
            '1',
          ];
          final integrity = await Process.run(
            Platform.isWindows ? 'python' : 'python3',
            [...verifier, '--inventory-only'],
          );
          expect(
            integrity.exitCode,
            0,
            reason: '${integrity.stdout}\n${integrity.stderr}',
          );
          expect(
            '${integrity.stdout}',
            contains('"qualificationVerified": false'),
          );
          final qualification = await Process.run(
            Platform.isWindows ? 'python' : 'python3',
            verifier,
          );
          expect(
            qualification.exitCode,
            isNot(0),
            reason: 'Complete failed-run evidence cannot become a pass.',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: pwshSkip,
    );
  }
}
