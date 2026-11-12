@TestOn('vm && (mac-os || linux)')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory app;
  late File manifest;

  setUp(() {
    app = Directory.systemTemp.createTempSync('swiftpm-bootstrap-');
    manifest = File(
      p.join(
        app.path,
        'macos/Flutter/ephemeral/Packages',
        'FlutterGeneratedPluginSwiftPackage/Package.swift',
      ),
    )..createSync(recursive: true);
  });
  tearDown(() => app.deleteSync(recursive: true));

  Future<ProcessResult> bootstrap() {
    final docs = File(
      'website/docs/platforms/apple-setup.md',
    ).readAsStringSync();
    final script = RegExp(
      "python3 - <<'PY'\n(.*?)\nPY",
      dotAll: true,
    ).firstMatch(docs);
    expect(
      script,
      isNotNull,
      reason: 'The consumer bootstrap must be runnable.',
    );
    return Process.run('python3', [
      '-c',
      script!.group(1)!,
    ], workingDirectory: app.path);
  }

  test('documented bootstrap raises only the generated macOS floor', () async {
    const before = '''// swift-tools-version: 5.9
platforms: [.macOS("12.0")]
// Preserve dependency URLs, checksums and target declarations.
''';
    manifest.writeAsStringSync(before);
    final result = await bootstrap();
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(
      manifest.readAsStringSync(),
      before.replaceFirst('.macOS("12.0")', '.macOS("14.0")'),
    );
  });

  for (final contents in [
    'platforms: [.macOS("15.0")]',
    'platforms: [.macOS("12.0"), .macOS("12.0")]',
  ]) {
    test('unexpected generated manifest is rejected: $contents', () async {
      manifest.writeAsStringSync(contents);
      final result = await bootstrap();
      expect(result.exitCode, isNot(0));
      expect(
        result.stderr,
        contains('Expected one generated macOS 12.0 floor'),
      );
      expect(manifest.readAsStringSync(), contents);
    });
  }

  test('missing generation fails without creating a manifest', () async {
    manifest.deleteSync();
    final result = await bootstrap();
    expect(result.exitCode, isNot(0));
    expect(manifest.existsSync(), isFalse);
  });

  for (final valid in [true, false]) {
    test('full recipe propagates failures and uses --no-pub: $valid', () async {
      manifest.writeAsStringSync(
        'platforms: [.macOS("${valid ? '12.0' : '15.0'}")]',
      );
      final bin = Directory(p.join(app.path, 'bin'))..createSync();
      final flutter = File(p.join(bin.path, 'flutter'))
        ..writeAsStringSync('''#!/bin/sh
echo "\$*" >> flutter-calls
''');
      expect((await Process.run('chmod', ['+x', flutter.path])).exitCode, 0);
      final docs = File(
        'website/docs/platforms/apple-setup.md',
      ).readAsStringSync();
      final recipe = RegExp(
        r'```bash\n(\(\n.*?flutter pub get\npython3.*?)\n```',
        dotAll: true,
      ).firstMatch(docs)!.group(1)!;
      final result = await Process.run(
        'bash',
        ['-c', recipe],
        workingDirectory: app.path,
        environment: {'PATH': '${bin.path}:${Platform.environment['PATH']}'},
      );
      expect(result.exitCode, valid ? 0 : isNot(0));
      expect(File(p.join(app.path, 'flutter-calls')).readAsLinesSync(), [
        'pub get',
        if (valid) 'build macos --debug --no-pub',
      ]);
    });
  }
}
