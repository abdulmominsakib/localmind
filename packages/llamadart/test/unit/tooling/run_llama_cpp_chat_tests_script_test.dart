@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('run_llama_cpp_chat_tests.sh', () {
    late String script;

    setUpAll(() {
      script = File(
        'tool/testing/run_llama_cpp_chat_tests.sh',
      ).readAsStringSync();
    });

    test('supports renamed upstream chat parser target', () {
      expect(script, contains('test-chat-auto-parser'));
      expect(script, contains('test-chat-parser'));
      expect(script, contains('resolve_target'));
      expect(script, contains(r'(:|$|[[:space:]])'));
    });

    test(
      'runs built llama.cpp test binaries with their build library path',
      () {
        expect(script, contains('DYLD_LIBRARY_PATH'));
        expect(script, contains('LD_LIBRARY_PATH'));
        expect(script, contains('bin/test-chat'));
      },
    );

    test(
      'builds full upstream chat suite without patching prepared source',
      () {
        expect(script, contains('build_tools=ON'));
        expect(script, contains('build_server=ON'));
        expect(script, contains(r'-I${src_dir}/tools/mtmd'));
        expect(script, contains('CMAKE_CXX_FLAGS'));
        expect(
          script,
          contains('instead of patching the prepared upstream source'),
        );
      },
    );

    test('bounds build parallelism and defaults to two jobs', () {
      expect(
        script,
        contains(r'build_jobs="${LLAMA_CPP_CHAT_TEST_BUILD_JOBS:-2}"'),
      );
      expect(script, contains(r'--parallel "${build_jobs}"'));
      expect(
        script,
        isNot(contains(RegExp(r'--parallel\s*$', multiLine: true))),
      );
    });

    test('rejects a non-positive job count', () async {
      final result = await Process.run(
        'bash',
        const ['tool/testing/run_llama_cpp_chat_tests.sh'],
        environment: const {'LLAMA_CPP_CHAT_TEST_BUILD_JOBS': '0'},
        includeParentEnvironment: true,
      );
      expect(result.exitCode, 64);
      expect(
        '${result.stdout}\n${result.stderr}',
        contains('LLAMA_CPP_CHAT_TEST_BUILD_JOBS must be a positive integer.'),
      );
    }, skip: Platform.isWindows ? 'requires a POSIX Bash runtime' : false);
  });
}
