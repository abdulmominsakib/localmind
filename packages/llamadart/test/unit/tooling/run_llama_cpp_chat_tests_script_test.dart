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
  });
}
