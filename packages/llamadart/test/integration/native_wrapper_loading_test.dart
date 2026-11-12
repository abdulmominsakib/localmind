@TestOn('windows')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  for (final resolver in [
    '_resolveReasoningBudgetApi',
    '_resolveTtsApi',
    '_resolveLogLevelFallbackFunction',
    '_resolveSpeculativeApi',
  ]) {
    test('production $resolver loads Windows wrapper sibling DLLs', () async {
      // Reuse the pinned DLLs already bundled by the parent test invocation.
      // Bypass dartdev so the child cannot rerun hooks and try to replace
      // DLLs loaded by the parent process (Windows denies that deletion).
      // These optional resolvers open the wrapper explicitly; no @Native
      // entry point is called, so a second native-assets build is unnecessary.
      // Each fresh process must discover sibling DLLs without prior preloads.
      final process = await Process.start(Platform.resolvedExecutable, [
        '--disable-dart-dev',
        '--packages=${path.join('.dart_tool', 'package_config.json')}',
        path.join('test', 'fixtures', 'native_wrapper_loading_probe.dart'),
        resolver,
      ], workingDirectory: Directory.current.path);
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      int exitCode;
      try {
        exitCode = await process.exitCode.timeout(const Duration(minutes: 5));
      } on TimeoutException {
        process.kill();
        rethrow;
      }
      final output = await stdout;
      final errors = await stderr;
      expect(exitCode, 0, reason: '$output\n$errors');
      expect(output, contains('WRAPPER_RESOLVED $resolver'));
    }, timeout: const Timeout(Duration(minutes: 6)));
  }
}
