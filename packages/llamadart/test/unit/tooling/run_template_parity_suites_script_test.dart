@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'prepares llama.cpp templates and requires them before detection parity',
    () async {
      final root = Directory.systemTemp.createTempSync('template-parity-');
      addTearDown(() => root.deleteSync(recursive: true));
      final log = File(p.join(root.path, 'calls.log'));
      final testing = Directory(p.join(root.path, 'tool', 'testing'))
        ..createSync(recursive: true);
      File(
        'tool/testing/run_template_parity_suites.sh',
      ).copySync(p.join(testing.path, 'run_template_parity_suites.sh'));
      _writeExecutable(
        p.join(testing.path, 'prepare_llama_cpp_source.sh'),
        '#!/usr/bin/env bash\n'
        'echo prepare >> "${log.path}"\n'
        'mkdir -p "${root.path}/.dart_tool/llama_cpp/models/templates"\n',
      );
      _writeExecutable(
        p.join(testing.path, 'build_llama_cpp_runtime_gbnf_validator.sh'),
        '#!/usr/bin/env bash\n'
        'echo runtime-validator >> "${log.path}"\n'
        'echo /runtime/bin/test-gbnf-validator\n',
      );
      final bin = Directory(p.join(root.path, 'bin'))..createSync();
      _writeExecutable(
        p.join(bin.path, 'dart'),
        '#!/usr/bin/env bash\n'
        'fixtures=missing\n'
        '[[ -d .dart_tool/llama_cpp/models/templates ]] && fixtures=present\n'
        'echo "dart require=\${REQUIRE_LLAMA_CPP_TEMPLATES:-unset} '
        'fixtures=\$fixtures \$*" >> "${log.path}"\n'
        'if [[ -n "\${LLAMA_CPP_GBNF_VALIDATOR:-}" ]]; then '
        'echo "validator=\$LLAMA_CPP_GBNF_VALIDATOR" >> "${log.path}"; fi\n',
      );

      final result = await Process.run(
        'bash',
        [p.join(testing.path, 'run_template_parity_suites.sh')],
        environment: {
          'PATH': '${bin.path}:${Platform.environment['PATH']}',
          'REQUIRE_LLAMA_CPP_TEMPLATES': '',
          'LLAMA_CPP_GBNF_VALIDATOR': '',
        },
      );

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      final calls = log.readAsLinesSync();
      expect(calls.first, 'prepare');
      expect(
        calls[1],
        'dart require=1 fixtures=present test -p vm -j 1 '
        'test/integration/core/template/'
        'llama_cpp_template_detection_integration_test.dart',
      );
      expect(calls.sublist(calls.length - 3), [
        'runtime-validator',
        'dart require=1 fixtures=present test -p vm -j 1 '
            'test/e2e/template/'
            'specialized_tool_grammar_validation_e2e_test.dart --run-skipped',
        'validator=/runtime/bin/test-gbnf-validator',
      ]);
    },
    skip: Platform.isWindows ? 'requires a POSIX Bash runtime' : false,
  );
}

void _writeExecutable(String path, String contents) {
  File(path).writeAsStringSync(contents);
  final chmod = Process.runSync('chmod', ['+x', path]);
  expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
}
