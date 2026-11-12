@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/testing/validation/bundle.dart';
import '../../../tool/testing/validation/internal_diagnostic.dart';
import '../../../tool/testing/validation/process.dart';

void main() {
  late Directory root;
  late Map<String, dynamic> profile;
  late Map<String, dynamic> provenance;
  var inventory = 'source.dart\u0000';
  var inventoryExit = 0;
  Future<CommandResult> listing(
    String binary,
    List<String> args, {
    String? directory,
    Duration? timeout,
    Map<String, String>? environment,
  }) async => CommandResult(inventoryExit, inventory, '');
  Future<({List<String> defines, Map<String, dynamic> binding})> derive({
    String run = 'attempt-one',
    String path = 'public_api',
  }) => deriveInternalDiagnosticContract(
    root.path,
    run,
    profile,
    path,
    provenance,
    execute: listing,
  );
  setUp(() {
    root = Directory.systemTemp.createTempSync('diagnostic-contract-');
    File(p.join(root.path, 'source.dart')).writeAsStringSync('original');
    profile =
        jsonDecode(
              File(
                'packages/llamadart_validation/assets/profiles/tiny-gguf-cpu.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    provenance = {
      'source_commit': 'a' * 40,
      'source_dirty': false,
      'hook_sha256': 'b' * 64,
      'litert_tag': 'v0.18.0',
    };
    inventory = 'source.dart\u0000';
    inventoryExit = 0;
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('contract binds actual source bytes and executable profile', () async {
    final first = await derive();
    expect(first.binding['model_sha256'], profile['model']['sha256']);
    expect(first.binding['model_bytes'], profile['model']['bytes']);
    expect(first.binding['expected_case_ids'], isNotEmpty);
    expect(first.defines, contains('VALIDATION_INTERNAL_DIAGNOSTIC=true'));
    File(p.join(root.path, 'source.dart')).writeAsStringSync('changed');
    final second = await derive();
    expect(
      second.binding['source_snapshot_sha256'],
      isNot(first.binding['source_snapshot_sha256']),
    );
    profile['max_tokens'] = 16;
    expect(
      (await derive()).binding['profile_hash'],
      isNot(first.binding['profile_hash']),
    );
  });
  test(
    'invalid run, dirty source and native C path fail before inventory',
    () async {
      await expectLater(derive(run: '../escape'), throwsFormatException);
      provenance['source_dirty'] = true;
      await expectLater(derive(), throwsStateError);
      provenance['source_dirty'] = false;
      await expectLater(derive(path: 'native_c_api'), throwsStateError);
    },
  );
  test('malformed source/runtime identity is rejected', () async {
    for (final key in ['source_commit', 'hook_sha256', 'litert_tag']) {
      final value = provenance[key];
      provenance[key] = 'invalid/path';
      await expectLater(derive(), throwsStateError);
      provenance[key] = value;
    }
  });
  test(
    'missing, duplicate, unterminated and escaping inventories fail',
    () async {
      for (final bad in [
        '',
        'source.dart',
        'source.dart\u0000source.dart\u0000',
        '../source.dart\u0000',
        '/source.dart\u0000',
        'dir/../source.dart\u0000',
        'missing\u0000',
      ]) {
        inventory = bad;
        await expectLater(derive(), throwsStateError);
      }
      inventory = 'source.dart\u0000';
      inventoryExit = 1;
      await expectLater(derive(), throwsStateError);
    },
  );
  test('nested Git paths stay portable across host separators', () async {
    final nested = File(p.join(root.path, 'nested', 'source.dart'));
    nested.parent.createSync();
    nested.writeAsStringSync('nested source');
    inventory = 'nested/source.dart\u0000';
    expect(
      (await derive()).binding['source_snapshot_sha256'],
      matches(r'^[a-f0-9]{64}$'),
    );
    for (final escaped in [
      'C:/source.dart',
      'C:source.dart',
      '//server/share/file',
      r'nested\source.dart',
    ]) {
      inventory = '$escaped\u0000';
      await expectLater(derive(), throwsStateError);
    }
  });
  test('source links cannot replace tracked files', () async {
    File(p.join(root.path, 'source.dart')).deleteSync();
    File(p.join(root.path, 'target')).writeAsStringSync('target');
    Link(p.join(root.path, 'source.dart')).createSync('target');
    await expectLater(derive(), throwsStateError);
  });
  test('non-Android opt-in fails before any build command', () async {
    await expectLater(
      buildValidationBundle(
        root.path,
        'desktop',
        p.join(root.path, 'out'),
        internalDiagnosticRunId: 'attempt-one',
        execute: (binary, args, {directory, timeout, environment}) async =>
            throw StateError('Unexpected build command'),
      ),
      throwsFormatException,
    );
  });

  Future<Directory> build({bool diagnostic = true, bool mutate = false}) async {
    final tracked = [
      '.flutter-version',
      'hook/build.dart',
      'lib/src/hook/native_release_pins.dart',
      'scripts/fetch_webgpu_bridge_assets.sh',
      'packages/llamadart_validation/assets/profiles/tiny-gguf-cpu.json',
    ];
    for (final path in tracked) {
      final file = File(p.join(root.path, path));
      file.parent.createSync(recursive: true);
      File(path).copySync(file.path);
    }
    for (final dir in ['packages/llamadart_validation', 'example/chat_app']) {
      final lock = File(p.join(root.path, dir, 'pubspec.lock'));
      lock.parent.createSync(recursive: true);
      lock.writeAsStringSync('fixture');
    }
    var builds = 0;
    final contracts = <List<String>>[];
    final javaHome = p.join(root.path, 'jdk');
    File(
      p.join(javaHome, 'bin', Platform.isWindows ? 'java.exe' : 'java'),
    ).createSync(recursive: true);
    final output = await buildValidationBundle(
      root.path,
      'android',
      p.join(root.path, 'out'),
      internalDiagnosticRunId: diagnostic ? 'attempt-one' : null,
      environment: {'JAVA_HOME': javaHome},
      execute: (binary, args, {directory, timeout, environment}) async {
        if (binary == 'git') {
          return CommandResult(0, switch (args.first) {
            'rev-parse' => 'a' * 40,
            'ls-files' => '${tracked.join('\u0000')}\u0000',
            _ => '',
          }, '');
        }
        if (binary == 'flutter' && args.first == '--version') {
          return CommandResult(
            0,
            jsonEncode({
              'frameworkVersion': File(
                '.flutter-version',
              ).readAsStringSync().trim(),
              'dartSdkVersion': Platform.version.split(' ').first,
            }),
            '',
          );
        }
        if (binary == 'flutter' && args.first == 'build') {
          builds++;
          contracts.add(
            args.where((a) => a.startsWith('--dart-define=')).toList(),
          );
          final apk = File(
            p.join(
              root.path,
              'example/chat_app/build/app/outputs/flutter-apk/app-debug.apk',
            ),
          );
          apk.parent.createSync(recursive: true);
          apk.writeAsStringSync('apk $builds');
        }
        if (binary.contains('gradlew')) {
          final encoded = args
              .singleWhere((a) => a.startsWith('-Pdart-defines='))
              .substring('-Pdart-defines='.length)
              .split(',');
          final decoded = encoded
              .map((a) => utf8.decode(base64Decode(a)))
              .toList();
          expect(
            decoded,
            contracts.last
                .map((a) => a.substring('--dart-define='.length))
                .toList(),
          );
          final apk = File(
            p.join(
              root.path,
              'example/chat_app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk',
            ),
          );
          apk.parent.createSync(recursive: true);
          apk.writeAsStringSync('test apk');
          if (mutate) {
            File(
              p.join(root.path, 'hook/build.dart'),
            ).writeAsStringSync('changed while building');
          }
        }
        return const CommandResult(0, '', '');
      },
    );
    expect(builds, 2);
    expect(contracts.first, contracts.last);
    expect(
      contracts.first.any((a) => a.contains('VALIDATION_INTERNAL_DIAGNOSTIC')),
      diagnostic,
    );
    return output;
  }

  test(
    'Android app and test pair share exact diagnostic defines and sealed binding',
    () async {
      final output = await build();
      final environment =
          jsonDecode(
                File(
                  p.join(output.path, 'environment.json'),
                ).readAsStringSync(),
              )
              as Map;
      final binding = environment['internal_diagnostic'] as Map;
      expect(binding['run_id'], 'attempt-one');
      expect(binding['source_dirty'], false);
      expect(binding['source_snapshot_sha256'], matches(r'^[a-f0-9]{64}$'));
      final manifest =
          jsonDecode(
                File(
                  p.join(output.path, 'bundle-manifest.json'),
                ).readAsStringSync(),
              )
              as Map;
      expect(manifest['internal_diagnostic'], binding);
    },
  );
  test('ordinary Android builds keep internal diagnostics disabled', () async {
    final output = await build(diagnostic: false);
    final environment =
        jsonDecode(
              File(p.join(output.path, 'environment.json')).readAsStringSync(),
            )
            as Map;
    expect(environment.containsKey('internal_diagnostic'), false);
  });
  test('source-byte mutation during build removes incomplete output', () async {
    await expectLater(
      build(mutate: true),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'source bytes guard',
          'Diagnostic source bytes changed during the build',
        ),
      ),
    );
    expect(Directory(p.join(root.path, 'out')).existsSync(), false);
  });
}
