@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('preserves generated-file exclusions and the transport fixture', () async {
    final repository = await Directory.systemTemp.createTemp(
      'gitignore_contract_',
    );
    addTearDown(() => repository.delete(recursive: true));
    await File('.gitignore').copy('${repository.path}/.gitignore');
    final init = await Process.run('git', [
      'init',
      '--quiet',
    ], workingDirectory: repository.path);
    expect(init.exitCode, 0, reason: '${init.stdout}\n${init.stderr}');
    // Keeps a contributor's global excludes and .git/info/exclude from
    // masking a missing rule.
    final emptyExcludes = File('${repository.path}/.git/empty_excludes')
      ..writeAsStringSync('');
    File('${repository.path}/.git/info/exclude').writeAsStringSync('');

    for (final (candidate, expectedExit) in <(String, int)>[
      for (final package in [
        'llamadart_litert_lm_flutter',
        'llamadart_llama_cpp_flutter',
        'llamadart_stable_diffusion_flutter',
      ])
        ('packages/$package/darwin/$package/.build/manifest.db', 0),
      (
        'test/fixtures/windows_ggml_registry_qualification/transport-selftest.bin',
        1,
      ),
      ('models/weights.bin', 0),
      ('test/fixtures/windows_ggml_registry_qualification/local-model.bin', 0),
      ('test/fixtures/other/transport-selftest.bin', 0),
    ]) {
      final result = await Process.run('git', [
        '-c',
        'core.excludesFile=${emptyExcludes.path}',
        'check-ignore',
        '--no-index',
        '--quiet',
        candidate,
      ], workingDirectory: repository.path);
      expect(result.exitCode, expectedExit, reason: candidate);
    }
  });
}
