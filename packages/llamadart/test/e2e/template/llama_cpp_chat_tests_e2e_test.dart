@TestOn('vm')
@Tags(['local-only', 'e2e'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('runs upstream llama.cpp chat test selection', () async {
    const scriptPath = 'tool/testing/run_llama_cpp_chat_tests.sh';
    final script = File(scriptPath);
    expect(script.existsSync(), isTrue, reason: 'Missing $scriptPath');

    final result = await Process.run(script.path, const <String>[]);
    final output = '${result.stdout}\n${result.stderr}';
    expect(
      result.exitCode,
      equals(0),
      reason: 'llama.cpp chat tests failed:\n$output',
    );
  });

  test('runs upstream llama.cpp full chat test suite', () async {
    const scriptPath = 'tool/testing/run_llama_cpp_chat_tests.sh';
    final script = File(scriptPath);
    expect(script.existsSync(), isTrue, reason: 'Missing $scriptPath');

    final result = await Process.run(
      script.path,
      const <String>[],
      environment: const <String, String>{
        'LLAMA_CPP_CHAT_TEST_INCLUDE_FULL': '1',
      },
    );
    final output = '${result.stdout}\n${result.stderr}';
    expect(
      result.exitCode,
      equals(0),
      reason: 'llama.cpp full chat tests failed:\n$output',
    );
  });
}
