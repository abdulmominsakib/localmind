@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  for (final (nativeTag, upstreamRef) in [
    ('v0.6.0-3', 'v0.6.0'),
    ('v0.6.0', 'v0.6.0'),
    ('b9000-llamadart.2', 'b9000'),
  ]) {
    test(
      'builds the validator at $upstreamRef for native pin $nativeTag',
      () async {
        final root = Directory.systemTemp.createTempSync('runtime-gbnf-');
        addTearDown(() => root.deleteSync(recursive: true));
        final log = File(p.join(root.path, 'calls.log'));
        final testing = Directory(p.join(root.path, 'tool', 'testing'))
          ..createSync(recursive: true);
        File('tool/testing/build_llama_cpp_runtime_gbnf_validator.sh').copySync(
          p.join(testing.path, 'build_llama_cpp_runtime_gbnf_validator.sh'),
        );
        Directory(
          p.join(root.path, 'lib', 'src', 'hook'),
        ).createSync(recursive: true);
        File(
          p.join(root.path, 'lib', 'src', 'hook', 'native_release_pins.dart'),
        ).writeAsStringSync("const llamaCppTag = '$nativeTag';\n");
        _writeExecutable(
          p.join(testing.path, 'prepare_llama_cpp_source.sh'),
          '#!/usr/bin/env bash\n'
          'echo "prepare \$LLAMA_CPP_REF" >> "${log.path}"\n'
          'if [[ -n "\${GITHUB_OUTPUT:-}" ]]; then\n'
          '  echo "llama_cpp_ref=\$LLAMA_CPP_REF" >> "\$GITHUB_OUTPUT"\n'
          'fi\n',
        );
        final stepOutput = File(p.join(root.path, 'github_output'))
          ..writeAsStringSync('llama_cpp_ref=b10549\n');
        final bin = Directory(p.join(root.path, 'bin'))..createSync();
        _writeExecutable(
          p.join(bin.path, 'cmake'),
          '#!/usr/bin/env bash\necho "cmake \$*" >> "${log.path}"\n',
        );

        final result = await Process.run(
          'bash',
          [p.join(testing.path, 'build_llama_cpp_runtime_gbnf_validator.sh')],
          environment: {
            'PATH': '${bin.path}:${Platform.environment['PATH']}',
            'LLAMA_CPP_REF': '',
            'LLAMA_CPP_RUNTIME_BUILD_DIR': p.join(root.path, 'build'),
            'GITHUB_OUTPUT': stepOutput.path,
          },
        );

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(
          (result.stdout as String).trim(),
          p.join(root.path, 'build', 'bin', 'test-gbnf-validator'),
        );
        final calls = log.readAsLinesSync();
        expect(calls.first, 'prepare $upstreamRef');
        expect(calls.last, contains('--target test-gbnf-validator'));
        expect(stepOutput.readAsStringSync(), 'llama_cpp_ref=b10549\n');
      },
      skip: Platform.isWindows ? 'requires a POSIX Bash runtime' : false,
    );
  }

  test('fails when the native pin is missing', () async {
    final root = Directory.systemTemp.createTempSync('runtime-gbnf-');
    addTearDown(() => root.deleteSync(recursive: true));
    final testing = Directory(p.join(root.path, 'tool', 'testing'))
      ..createSync(recursive: true);
    File('tool/testing/build_llama_cpp_runtime_gbnf_validator.sh').copySync(
      p.join(testing.path, 'build_llama_cpp_runtime_gbnf_validator.sh'),
    );
    Directory(
      p.join(root.path, 'lib', 'src', 'hook'),
    ).createSync(recursive: true);
    File(
      p.join(root.path, 'lib', 'src', 'hook', 'native_release_pins.dart'),
    ).writeAsStringSync('');

    final result = await Process.run('bash', [
      p.join(testing.path, 'build_llama_cpp_runtime_gbnf_validator.sh'),
    ]);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('llamaCppTag not found'));
  }, skip: Platform.isWindows ? 'requires a POSIX Bash runtime' : false);
}

void _writeExecutable(String path, String contents) {
  File(path).writeAsStringSync(contents);
  final chmod = Process.runSync('chmod', ['+x', path]);
  expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
}
