@TestOn('mac-os')
@Tags(['local-only'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

// Exercise the real Flutter/native-assets cache, not only hook output metadata.
// A fresh local clone keeps both tracked files and production caches untouched.
void main() {
  test('Flutter observes absent, added, and removed Apple overrides', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'apple-hook-cache-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final checkout = path.join(temporary.path, 'repo');
    await _expectSuccess('git', [
      'clone',
      '--shared',
      '--quiet',
      Directory.current.path,
      checkout,
    ], Directory.current.path);
    final app = path.join(checkout, 'example', 'chat_app');
    final artifacts = Directory(
      path.join(
        checkout,
        'packages',
        'llamadart_llama_cpp_flutter',
        'darwin',
        'llamadart_llama_cpp_flutter',
        'Artifacts',
      ),
    );
    expect(artifacts.existsSync(), isFalse);
    await _expectSuccess('flutter', ['pub', 'get'], app);
    const testArguments = [
      'test',
      '--no-pub',
      'test_vm/physical_ios_speech_e2e_support_test.dart',
    ];

    // Fresh success must not register a missing directory for Flutter scanning.
    await _expectSuccess('flutter', testArguments, app);
    // Warm success proves the successful hook output is reusable.
    await _expectSuccess('flutter', testArguments, app);
    await artifacts.create();
    final rejected = await _run('flutter', testArguments, app);
    expect(rejected.exitCode, isNot(0), reason: rejected.output);
    expect(
      rejected.output,
      contains('Local Artifacts overrides cannot establish'),
    );
    await artifacts.delete();
    // Do not clear any cache: removal must recover through the same runner.
    await _expectSuccess('flutter', testArguments, app);
  });
}

Future<void> _expectSuccess(
  String command,
  List<String> arguments,
  String cwd,
) async {
  final result = await _run(command, arguments, cwd);
  expect(result.exitCode, 0, reason: result.output);
}

Future<({int exitCode, String output})> _run(
  String command,
  List<String> arguments,
  String cwd,
) async {
  final process = await Process.start(
    command,
    arguments,
    workingDirectory: cwd,
  );
  final stdout = process.stdout.transform(utf8.decoder).join();
  final stderr = process.stderr.transform(utf8.decoder).join();
  final int exitCode;
  try {
    exitCode = await process.exitCode.timeout(const Duration(minutes: 4));
  } catch (_) {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    rethrow;
  }
  return (exitCode: exitCode, output: '${await stdout}\n${await stderr}');
}
