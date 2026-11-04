@TestOn('vm')
@Tags(['local-only', 'e2e'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('runs webgpu/cpu multimodal regression gate', () async {
    const scriptPath = 'tool/testing/run_webgpu_multimodal_regression_gate.sh';
    final script = File(scriptPath);
    expect(script.existsSync(), isTrue, reason: 'Missing $scriptPath');

    final result = await Process.run(script.path, const <String>[]);
    final output = '${result.stdout}\n${result.stderr}';
    expect(
      result.exitCode,
      equals(0),
      reason: 'multimodal regression gate failed:\n$output',
    );
  });
}
