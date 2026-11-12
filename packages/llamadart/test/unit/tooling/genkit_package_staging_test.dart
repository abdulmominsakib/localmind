@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'publisher staging preserves adapter source and refuses existing output',
    () async {
      final scratch = await Directory.systemTemp.createTemp('genkit_staging_');
      addTearDown(() => scratch.delete(recursive: true));
      final destination = Directory('${scratch.path}/package');
      Future<ProcessResult> stage() => Process.run(
        Platform.isWindows ? 'python' : 'python3',
        ['tool/release/stage_genkit_package.py', destination.path],
      );
      final result = await stage();
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      for (final path in [
        'pubspec.yaml',
        'README.md',
        'CHANGELOG.md',
        'LICENSE',
        'lib/genkit_llamadart.dart',
        'example/genkit_llamadart_example.dart',
        'doc/usage.md',
        'skills/genkit-llamadart-getting-started/SKILL.md',
      ]) {
        expect(
          File('${destination.path}/$path').readAsBytesSync(),
          File('packages/genkit_llamadart/$path').readAsBytesSync(),
          reason: path,
        );
      }
      for (final path in [
        'pubspec_overrides.yaml',
        'pubspec.lock',
        '.dart_tool',
        '.github',
      ]) {
        expect(
          FileSystemEntity.typeSync('${destination.path}/$path'),
          FileSystemEntityType.notFound,
          reason: path,
        );
      }
      final marker = File('${destination.path}/marker')
        ..writeAsStringSync('keep');
      final repeated = await stage();
      expect(repeated.exitCode, isNot(0));
      expect(repeated.stderr, contains('Destination already exists'));
      expect(marker.readAsStringSync(), 'keep');
    },
  );

  test(
    'staging rejects leaked overrides and symlink sources in fixture tests',
    () async {
      final result =
          await Process.run(Platform.isWindows ? 'python' : 'python3', [
            '-B',
            '-m',
            'unittest',
            'discover',
            '-s',
            'test/ci',
            '-p',
            'test_stage_genkit_package.py',
          ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, matches(RegExp(r'Ran [1-9][0-9]* tests')));
    },
  );
}
