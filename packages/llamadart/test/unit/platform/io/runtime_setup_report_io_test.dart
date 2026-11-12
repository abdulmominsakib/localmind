@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/platform/io/runtime_setup_report_io.dart';
import 'package:test/test.dart';

LlamaRuntimeSetupReport _host(String os, String abi) => buildDesktopSetupReport(
  os: os,
  osVersion: '1.2.3',
  abi: abi,
  dartVersion: '3.13.1 (stable) private-user',
  packageVersion: '0.16.2',
  environment: {},
);

void main() {
  test(
    'published, unavailable and unknown policies cover known desktop ABIs',
    () {
      for (final (os, abi, expected) in [
        ('macos', 'macos_arm64', ['published', 'published', 'published']),
        ('macos', 'macos_x64', ['published', 'unavailable', 'published']),
        ('linux', 'linux_arm64', ['published', 'published', 'published']),
        ('linux', 'linux_x64', ['published', 'published', 'published']),
        ('windows', 'windows_x64', ['published', 'published', 'published']),
        (
          'windows',
          'windows_arm64',
          ['published', 'unavailable', 'unavailable'],
        ),
        ('linux', 'linux_ia32', ['unavailable', 'unavailable', 'unavailable']),
        ('linux', 'linux_arm', ['unavailable', 'unavailable', 'unavailable']),
        (
          'windows',
          'windows_ia32',
          ['unavailable', 'unavailable', 'unavailable'],
        ),
        ('linux', 'linux_future', ['unknown', 'unknown', 'unknown']),
        ('future', 'linux_x64', ['unknown', 'unknown', 'unknown']),
        ('linux', 'windows_x64', ['unknown', 'unknown', 'unknown']),
      ]) {
        final report = _host(os, abi);
        expect(
          report.runtimes.map((runtime) => runtime.publication),
          expected,
          reason: '$os $abi',
        );
        expect(report.runtimes.map((runtime) => runtime.name), [
          'llama_cpp',
          'litert_lm',
          'stable_diffusion',
        ]);
        expect(report.runtimes.map((runtime) => runtime.expectedReleaseTag), [
          'v0.9.0',
          'v0.19.1-4',
          'v0.3.0-3',
        ]);
        expect(report.dartVersion, '3.13.1');
        expect(jsonEncode(report.toJson()), isNot(contains('private-user')));
      }
    },
  );

  test('IO rejects mobile and unknown hosts with typed guidance', () {
    for (final os in ['android', 'ios', 'future']) {
      expect(
        () => requireDesktopSetupHost(os),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    }
  });

  test(
    'collector resolves this package version from the package URI',
    () async {
      final library = await Isolate.resolvePackageUri(
        Uri.parse('package:llamadart/llamadart.dart'),
      );
      final expected = parseSetupPackageVersion(
        await File.fromUri(library!.resolve('../pubspec.yaml')).readAsString(),
      );
      expect(expected, isNot('unknown'));
      expect((await collectLlamaRuntimeSetupReport()).packageVersion, expected);
    },
  );

  test(
    'version origin never falls back to consuming app or current directory',
    () async {
      final directory = await Directory.systemTemp.createTemp('setup_origin_');
      addTearDown(() => directory.delete(recursive: true));
      final package = Directory.fromUri(directory.uri.resolve('package/'));
      await Directory.fromUri(
        package.uri.resolve('lib/'),
      ).create(recursive: true);
      await File.fromUri(
        directory.uri.resolve('pubspec.yaml'),
      ).writeAsString('name: consuming_app\nversion: 99.88.77\n');
      final pubspec = File.fromUri(package.uri.resolve('pubspec.yaml'));
      final library = package.uri.resolve('lib/llamadart.dart');
      expect(await readSetupPackageVersion(library), 'unknown');
      await pubspec.writeAsString('name: llamadart\nversion: 1.2.3\n');
      expect(await readSetupPackageVersion(library), '1.2.3');
      await pubspec.writeAsString('name: consuming_app\nversion: 99.88.77\n');
      expect(await readSetupPackageVersion(library), 'unknown');
      await pubspec.writeAsString(
        'name: llamadart\nversion: 1.2.3\n${'x' * 65536}',
      );
      expect(await readSetupPackageVersion(library), 'unknown');
      await pubspec.writeAsBytes([0xff, 0xff]);
      expect(await readSetupPackageVersion(library), 'unknown');
      expect(await readSetupPackageVersion(null), 'unknown');
      expect(
        await readSetupPackageVersion(Uri.parse('https://secret.example/')),
        'unknown',
      );

      final result = await Process.run(Platform.resolvedExecutable, [
        '--packages=${File('.dart_tool/package_config.json').absolute.path}',
        File('bin/doctor.dart').absolute.path,
        '--json',
      ], workingDirectory: directory.path);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final report =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final ownVersion = parseSetupPackageVersion(
        await File('pubspec.yaml').readAsString(),
      );
      expect(report['host']['llamadart_version'], ownVersion);
      expect(report['host']['llamadart_version'], isNot('99.88.77'));
    },
  );

  test('invalid and secret-bearing package metadata becomes unknown', () {
    for (final raw in [
      'name: llamadart\nversion: /Users/private-user/token\n',
      'name: llamadart\nversion: https://private.example/?token=SECRET\n',
      'name: llamadart\nversion: 1.2.3\u001b[31m\n',
      'name: llamadart\nversion: 1.2.3\nversion: 4.5.6\n',
      'name: llamadart\nname: other\nversion: 1.2.3\n',
      'name: other\nversion: 1.2.3\n',
    ]) {
      expect(parseSetupPackageVersion(raw), 'unknown');
    }
  });

  test(
    'real CLI VM produces one JSON document with invalid native overrides',
    () async {
      const secret = 'PRIVATE_DOCTOR_CANARY';
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['bin/doctor.dart', '--json'],
        environment: {
          'LLAMADART_NATIVE_LIB_DIR': '/nonexistent/$secret',
          'LLAMADART_BACKEND_MODULE_DIR': r'C:\nonexistent\' + secret,
          'LLAMADART_LITERT_LM_LIB_DIR': r'\\missing\share\' + secret,
        },
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stderr, isEmpty);
      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json['schema_version'], 1);
      expect(json['overrides'], {
        'LLAMADART_NATIVE_LIB_DIR': 'set',
        'LLAMADART_BACKEND_MODULE_DIR': 'set',
        'LLAMADART_LITERT_LM_LIB_DIR': 'set',
      });
      expect((json['observations'] as Map)['selected_backend'], 'unknown');
      expect('${result.stdout}${result.stderr}', isNot(contains(secret)));
      expect(json['host']['flutter_version'], 'unknown');
    },
  );

  for (final (name, args) in [
    ('unknown option', ['--token=https://private.example/?secret=SECRET']),
    ('duplicate JSON option', ['--json', '--json']),
    ('extra help argument', ['--help', 'SECRET']),
  ]) {
    test('real CLI rejects $name without echoing arguments', () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'bin/doctor.dart',
        ...args,
      ]);
      expect(result.exitCode, 64);
      expect(result.stdout, isEmpty);
      expect(result.stderr, 'doctor: invalid arguments. Use --help.\n');
    });
  }

  test('real CLI help explains build-hook preparation', () async {
    final help = await Process.run(Platform.resolvedExecutable, [
      'bin/doctor.dart',
      '--help',
    ]);
    expect(help.exitCode, 0);
    expect(help.stdout, contains('build hook can prepare/download assets'));
  });

  test(
    'real CLI human output states runtime verification is unchecked',
    () async {
      final human = await Process.run(Platform.resolvedExecutable, [
        'bin/doctor.dart',
      ]);
      expect(human.exitCode, 0);
      expect(human.stdout, contains('runtime not verified'));
    },
  );
}
