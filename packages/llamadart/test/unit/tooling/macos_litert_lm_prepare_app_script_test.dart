@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('macos_litert_lm_prepare_app.sh', () {
    test('chat app relies on the companion instead of a LiteRT-LM phase', () {
      final project = File(
        path.join(
          'example',
          'chat_app',
          'macos',
          'Runner.xcodeproj',
          'project.pbxproj',
        ),
      ).readAsStringSync();

      expect(project, contains('macos_assemble.sh embed'));
      expect(project, isNot(contains('LiteRT-LM')));
      expect(project, isNot(contains('macos_litert_lm_prepare_app.sh')));
    });

    for (final docs in _installationDocs) {
      test('$docs build phase runs the resolved package script', () async {
        final script = _documentedBuildPhase(docs);
        final root = await Directory.systemTemp.createTemp(
          'litert_prepare_docs_',
        );
        addTearDown(() => root.delete(recursive: true));

        final workspace = Directory(path.join(root.path, 'my workspace'));
        final package = Directory(
          path.join(workspace.path, 'packages', 'llama dart'),
        );
        final prepare = File(
          path.join(package.path, 'tool', 'macos_litert_lm_prepare_app.sh'),
        );
        await prepare.parent.create(recursive: true);
        await prepare.writeAsString('echo "PREPARE \$1"\n');
        final config = File(
          path.join(workspace.path, '.dart_tool', 'package_config.json'),
        );
        await config.parent.create(recursive: true);
        final project = Directory(
          path.join(workspace.path, 'apps', 'my app', 'macos'),
        );
        await project.create(recursive: true);

        Future<ProcessResult> run() => Process.run(
          'bash',
          ['-c', script],
          environment: {
            'PROJECT_DIR': project.path,
            'TARGET_BUILD_DIR': path.join(root.path, 'Build'),
            'WRAPPER_NAME': 'My App.app',
          },
        );
        final appPath = path.join(root.path, 'Build', 'My App.app');

        for (final rootUri in [
          '../packages/llama%20dart/',
          Uri.directory(package.path).toString(),
        ]) {
          await config.writeAsString(
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {'name': 'meta', 'rootUri': 'file:///unused/'},
                {'name': 'llamadart', 'rootUri': rootUri},
              ],
            }),
          );
          final result = await run();
          expect(result.exitCode, 0, reason: '$rootUri: ${result.stderr}');
          expect(result.stdout, contains('PREPARE $appPath'));
        }

        await config.writeAsString(
          jsonEncode({'configVersion': 2, 'packages': <Object>[]}),
        );
        final unresolved = await run();
        expect(unresolved.exitCode, 1);
        expect(unresolved.stderr, contains('llamadart is not resolved'));

        await config.delete();
        final missing = await run();
        expect(missing.exitCode, 1);
        expect(missing.stderr, contains('run flutter pub get'));
      }, skip: Platform.isMacOS ? false : 'requires macOS plutil');
    }

    test('rejects incomplete explicit arm64 runtime directories', () async {
      final root = await Directory.systemTemp.createTemp(
        'litert_prepare_partial_',
      );
      addTearDown(() => root.delete(recursive: true));

      final libDir = Directory(path.join(root.path, 'litert'))..createSync();
      await File(path.join(libDir.path, 'libLiteRtLm.dylib')).create();

      final appDir = Directory(path.join(root.path, 'Test.app'));
      final result = await _runPrepareApp(appDir, libDir, arch: 'arm64');

      expect(result.exitCode, 2);
      expect(result.stderr, contains('library directory is incomplete'));
      expect(result.stderr, contains('libCLiteRTLM_mac.dylib'));
      expect(
        Directory(
          path.join(appDir.path, 'Contents', 'Frameworks'),
        ).existsSync(),
        isFalse,
      );
    }, skip: Platform.isWindows ? 'requires bash and POSIX symlinks' : false);

    for (final missing in _arm64Libraries) {
      test('rejects an arm64 runtime missing $missing', () async {
        final root = await Directory.systemTemp.createTemp(
          'litert_prepare_missing_',
        );
        addTearDown(() => root.delete(recursive: true));

        final libDir = await _arm64LibraryDir(root);
        await File(path.join(libDir.path, missing)).delete();
        final appDir = Directory(path.join(root.path, 'Test.app'));
        final result = await _runPrepareApp(appDir, libDir, arch: 'arm64');

        expect(result.exitCode, 2, reason: result.stderr.toString());
        expect(result.stderr, contains('library directory is incomplete'));
        expect(result.stderr, contains('  - $missing'));
        expect(_stagedRuntime(appDir).existsSync(), isFalse);
      }, skip: Platform.isWindows ? 'requires bash and POSIX symlinks' : false);
    }

    test('installs the full arm64 companion library set', () async {
      final root = await Directory.systemTemp.createTemp(
        'litert_prepare_full_',
      );
      addTearDown(() => root.delete(recursive: true));

      final libDir = Directory(path.join(root.path, 'litert'))..createSync();
      for (final library in [
        ..._arm64Libraries,
        ..._obsoleteSamplerLibraries,
      ]) {
        await File(path.join(libDir.path, library)).create();
      }

      final appDir = Directory(path.join(root.path, 'Test.app'));
      final result = await _runPrepareApp(appDir, libDir, arch: 'arm64');

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('Prepared LiteRT-LM macOS'));

      final frameworksDir = path.join(appDir.path, 'Contents', 'Frameworks');
      final runtimeDir = path.join(frameworksDir, 'LiteRtLmRuntime');
      for (final library in _arm64Libraries) {
        final libraryPath = path.join(runtimeDir, library);
        expect(File(libraryPath).existsSync(), isTrue, reason: library);
      }
      for (final library in _obsoleteSamplerLibraries) {
        expect(
          File(path.join(runtimeDir, library)).existsSync(),
          isFalse,
          reason: library,
        );
      }
      for (final framework in _oldFrameworks) {
        expect(
          Directory(
            path.join(frameworksDir, '$framework.framework'),
          ).existsSync(),
          isFalse,
          reason: framework,
        );
      }
    }, skip: Platform.isWindows ? 'requires bash and POSIX symlinks' : false);

    test(
      'does not treat unrelated Flutter frameworks as LiteRT-LM runtime',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'litert_prepare_flutter_framework_',
        );
        addTearDown(() => root.delete(recursive: true));

        final libDir = Directory(path.join(root.path, 'litert'))..createSync();
        for (final library in _arm64Libraries) {
          await File(path.join(libDir.path, library)).create();
        }

        final appDir = Directory(path.join(root.path, 'Test.app'));
        Directory(
          path.join(
            appDir.path,
            'Contents',
            'Frameworks',
            'llamadart.framework',
          ),
        ).createSync(recursive: true);

        final result = await _runPrepareApp(appDir, libDir, arch: 'arm64');

        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(result.stdout, contains('Prepared LiteRT-LM macOS'));
        expect(
          File(
            path.join(
              appDir.path,
              'Contents',
              'Frameworks',
              'LiteRtLmRuntime',
              'libCLiteRTLM_mac.dylib',
            ),
          ).existsSync(),
          isTrue,
        );
      },
      skip: Platform.isWindows ? 'requires bash and POSIX symlinks' : false,
    );

    test(
      'skips on the second run although signing rewrote the bytes',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'litert_prepare_signed_',
        );
        addTearDown(() => root.delete(recursive: true));

        final libDir = await _arm64LibraryDir(root);
        final appDir = Directory(path.join(root.path, 'Test.app'));

        final first = await _runPrepareApp(
          appDir,
          libDir,
          arch: 'arm64',
          fakeSigning: true,
        );
        expect(first.stdout, contains('Prepared LiteRT-LM macOS'));
        final signed = File(
          path.join(_stagedRuntime(appDir).path, _arm64Libraries.first),
        );
        expect(signed.readAsBytesSync(), isNotEmpty);

        final second = await _runPrepareApp(
          appDir,
          libDir,
          arch: 'arm64',
          fakeSigning: true,
        );

        expect(second.exitCode, 0, reason: second.stderr.toString());
        expect(second.stdout, contains('Complete LiteRT-LM runtime detected'));
        expect(second.stdout, isNot(contains('Prepared LiteRT-LM macOS')));
      },
      skip: Platform.isWindows ? 'requires bash and POSIX symlinks' : false,
    );

    test('replaces the runtime when the prepared one changes', () async {
      final root = await Directory.systemTemp.createTemp(
        'litert_prepare_skew_',
      );
      addTearDown(() => root.delete(recursive: true));

      final libDir = await _arm64LibraryDir(root);
      final appDir = Directory(path.join(root.path, 'Test.app'));
      await _runPrepareApp(appDir, libDir, arch: 'arm64');

      for (final library in _arm64Libraries) {
        await File(path.join(libDir.path, library)).writeAsString('new');
      }
      final result = await _runPrepareApp(appDir, libDir, arch: 'arm64');

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('replacing it'));
      expect(result.stdout, contains('Prepared LiteRT-LM macOS'));
      for (final library in _arm64Libraries) {
        expect(
          File(
            path.join(_stagedRuntime(appDir).path, library),
          ).readAsStringSync(),
          'new',
          reason: library,
        );
      }
      final third = await _runPrepareApp(appDir, libDir, arch: 'arm64');
      expect(third.stdout, contains('Complete LiteRT-LM runtime detected'));
    }, skip: Platform.isWindows ? 'requires bash and POSIX symlinks' : false);

    test('replaces a runtime without a stamp once', () async {
      final root = await Directory.systemTemp.createTemp(
        'litert_prepare_nostamp_',
      );
      addTearDown(() => root.delete(recursive: true));

      final libDir = await _arm64LibraryDir(root);
      final appDir = Directory(path.join(root.path, 'Test.app'));
      final runtimeDir = _stagedRuntime(appDir)..createSync(recursive: true);
      for (final library in _arm64Libraries) {
        await File(path.join(runtimeDir.path, library)).writeAsString('old');
      }

      final first = await _runPrepareApp(appDir, libDir, arch: 'arm64');
      expect(first.stdout, contains('Prepared LiteRT-LM macOS'));
      expect(
        File(
          path.join(runtimeDir.path, _arm64Libraries.first),
        ).readAsStringSync(),
        isEmpty,
      );

      final second = await _runPrepareApp(appDir, libDir, arch: 'arm64');
      expect(second.stdout, contains('Complete LiteRT-LM runtime detected'));
    }, skip: Platform.isWindows ? 'requires bash and POSIX symlinks' : false);

    test('keeps a bundled runtime when no prepared one resolves', () async {
      final root = await Directory.systemTemp.createTemp(
        'litert_prepare_unresolved_',
      );
      addTearDown(() => root.delete(recursive: true));

      final tool = Directory(path.join(root.path, 'pkg', 'tool'))
        ..createSync(recursive: true);
      final script =
          File(path.join(tool.path, 'macos_litert_lm_prepare_app.sh'))
            ..writeAsStringSync(
              File('tool/macos_litert_lm_prepare_app.sh').readAsStringSync(),
            );
      final appDir = Directory(path.join(root.path, 'Test.app'));
      final runtimeDir = _stagedRuntime(appDir)..createSync(recursive: true);
      for (final library in _arm64Libraries) {
        await File(path.join(runtimeDir.path, library)).writeAsString('old');
      }

      final result = await Process.run(
        'bash',
        [script.path, appDir.path],
        environment: {'LLAMADART_LITERT_LM_ARCH': 'arm64'},
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('Complete LiteRT-LM runtime detected'));
      expect(
        File(
          path.join(runtimeDir.path, _arm64Libraries.first),
        ).readAsStringSync(),
        'old',
      );
    }, skip: Platform.isWindows ? 'requires bash and POSIX symlinks' : false);

    test(
      'does not treat partial arm64 native SPM runtime as complete',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'litert_prepare_partial_spm_',
        );
        addTearDown(() => root.delete(recursive: true));

        final libDir = Directory(path.join(root.path, 'litert'))..createSync();
        for (final library in _arm64Libraries) {
          await File(path.join(libDir.path, library)).create();
        }

        final appDir = Directory(path.join(root.path, 'Test.app'));
        final frameworksDir = Directory(
          path.join(appDir.path, 'Contents', 'Frameworks'),
        )..createSync(recursive: true);
        final liteRtLmDir = Directory(
          path.join(frameworksDir.path, 'LiteRtLm.framework', 'Versions', 'A'),
        )..createSync(recursive: true);
        await File(path.join(liteRtLmDir.path, 'LiteRtLm')).create();
        await File(
          path.join(frameworksDir.path, 'libCLiteRTLM_mac.dylib'),
        ).create();

        final result = await _runPrepareApp(appDir, libDir, arch: 'arm64');

        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(result.stdout, contains('Prepared LiteRT-LM macOS'));
        expect(
          File(
            path.join(
              frameworksDir.path,
              'LiteRtLmRuntime',
              'libCLiteRTLM_mac.dylib',
            ),
          ).existsSync(),
          isTrue,
        );
      },
      skip: Platform.isWindows ? 'requires bash and POSIX symlinks' : false,
    );

    test(
      'skips the copy when the arm64 SwiftPM companion layout is embedded',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'litert_prepare_complete_spm_',
        );
        addTearDown(() => root.delete(recursive: true));

        final appDir = Directory(path.join(root.path, 'Test.app'));
        final frameworksDir = path.join(appDir.path, 'Contents', 'Frameworks');
        for (final file in _arm64SwiftPmFiles) {
          final embedded = File(path.join(frameworksDir, file));
          await embedded.parent.create(recursive: true);
          await embedded.create();
        }

        final result = await Process.run(
          'bash',
          ['tool/macos_litert_lm_prepare_app.sh', appDir.path],
          environment: {'LLAMADART_LITERT_LM_ARCH': 'arm64'},
        );

        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(result.stdout, contains('Complete LiteRT-LM runtime detected'));
        expect(
          Directory(path.join(frameworksDir, 'LiteRtLmRuntime')).existsSync(),
          isFalse,
        );
      },
      skip: Platform.isWindows ? 'requires bash and POSIX symlinks' : false,
    );

    for (final arch in ['x64', 'x86_64', 'amd64']) {
      test('warns and skips LiteRT-LM for a macOS $arch build', () async {
        final root = await Directory.systemTemp.createTemp(
          'litert_prepare_x64_',
        );
        addTearDown(() => root.delete(recursive: true));

        final libDir = await _arm64LibraryDir(root);
        final appDir = Directory(path.join(root.path, 'Test.app'));
        final result = await _runPrepareApp(appDir, libDir, arch: arch);

        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(result.stderr, contains(_x64Warning));
        expect(_stagedRuntime(appDir).existsSync(), isFalse);
      }, skip: Platform.isWindows ? 'requires bash' : false);
    }

    for (final (host, archs, staged) in [
      ('x86_64', 'arm64 x86_64', true),
      ('x86_64', 'x86_64 arm64', true),
      ('x86_64', 'arm64', true),
      ('x86_64', 'x86_64', false),
      ('x86_64', null, false),
      ('arm64', 'arm64', true),
      ('arm64', 'arm64 x86_64', true),
      ('arm64', 'x86_64', false),
    ]) {
      final build = archs == null ? 'no ARCHS' : 'ARCHS=$archs';
      final outcome = staged ? 'stages arm64' : 'warns and skips';
      test('$build on an $host build Mac $outcome', () async {
        final root = await Directory.systemTemp.createTemp(
          'litert_prepare_archs_',
        );
        addTearDown(() => root.delete(recursive: true));

        final libDir = await _arm64LibraryDir(root);
        final appDir = Directory(path.join(root.path, 'Test.app'));
        final result = await _runPrepareApp(
          appDir,
          libDir,
          archs: archs,
          hostArch: host,
        );

        expect(result.exitCode, 0, reason: result.stderr.toString());
        if (staged) {
          expect(result.stdout, contains('Prepared LiteRT-LM macOS'));
          expect(result.stderr, isNot(contains(_x64Warning)));
          for (final library in _arm64Libraries) {
            expect(
              File(
                path.join(_stagedRuntime(appDir).path, library),
              ).existsSync(),
              isTrue,
              reason: library,
            );
          }
        } else {
          expect(result.stderr, contains(_x64Warning));
          expect(_stagedRuntime(appDir).existsSync(), isFalse);
        }
      }, skip: Platform.isWindows ? 'requires bash' : false);
    }
  });
}

const _installationDocs = [
  'website/docs/platforms/apple-setup.md',
  'website/versioned_docs/version-0.12.0/getting-started/installation.md',
];

/// The `bash` block of the Flutter macOS LiteRT-LM build phase section.
String _documentedBuildPhase(String docsPath) {
  final docs = File(docsPath).readAsStringSync();
  final section = docs.indexOf('## Flutter macOS LiteRT-LM build phase');
  expect(section, greaterThanOrEqualTo(0), reason: docsPath);
  final start = docs.indexOf('```bash\n', section) + '```bash\n'.length;
  return docs.substring(start, docs.indexOf('```', start));
}

const _x64Warning =
    'warning: LiteRT-LM is not available on macOS x86_64: litert-lm-native '
    'publishes arm64-only macOS runtimes (leehack/litert-lm-native#72).';

Directory _stagedRuntime(Directory appDir) => Directory(
  path.join(appDir.path, 'Contents', 'Frameworks', 'LiteRtLmRuntime'),
);

Future<Directory> _arm64LibraryDir(Directory root) async {
  final libDir = Directory(path.join(root.path, 'litert'))..createSync();
  for (final library in _arm64Libraries) {
    await File(path.join(libDir.path, library)).create();
  }
  return libDir;
}

/// Runs the script with [arch] as `LLAMADART_LITERT_LM_ARCH`, or, when
/// [arch] is null, with Xcode's [archs] on a build Mac whose `uname -m` is
/// [hostArch].
Future<ProcessResult> _runPrepareApp(
  Directory appDir,
  Directory libDir, {
  String? arch,
  String? archs,
  String? hostArch,
  bool fakeSigning = false,
}) async {
  final environment = {'LLAMADART_LITERT_LM_LIB_DIR': libDir.path};
  final removed = <String>{'LLAMADART_LITERT_LM_ARCH', 'ARCHS'};
  if (arch != null) {
    environment['LLAMADART_LITERT_LM_ARCH'] = arch;
    removed.remove('LLAMADART_LITERT_LM_ARCH');
  }
  if (archs != null) {
    environment['ARCHS'] = archs;
    removed.remove('ARCHS');
  }
  final bin = Directory(path.join(libDir.parent.path, 'bin'))..createSync();
  if (fakeSigning) {
    File(
      path.join(bin.path, 'file'),
    ).writeAsStringSync('#!/bin/sh\necho Mach-O\n');
    File(path.join(bin.path, 'codesign')).writeAsStringSync(
      '#!/bin/sh\nfor last; do :; done\necho signed >>"\$last"\n',
    );
    await Process.run('chmod', [
      '+x',
      path.join(bin.path, 'file'),
      path.join(bin.path, 'codesign'),
    ]);
  }
  if (hostArch != null) {
    final uname = File(path.join(bin.path, 'uname'))
      ..writeAsStringSync('#!/bin/sh\necho $hostArch\n');
    await Process.run('chmod', ['+x', uname.path]);
  }
  if (hostArch != null || fakeSigning) {
    environment['PATH'] = '${bin.path}:${Platform.environment['PATH']}';
  }
  return Process.run(
    'bash',
    ['tool/macos_litert_lm_prepare_app.sh', appDir.path],
    environment: {
      for (final entry in Platform.environment.entries)
        if (!removed.contains(entry.key)) entry.key: entry.value,
      ...environment,
    },
    includeParentEnvironment: false,
  );
}

const List<String> _arm64Libraries = [
  'libCLiteRTLM_mac.dylib',
  'libGemmaModelConstraintProvider.dylib',
  'libLiteRtLm.dylib',
  'libwebgpu_dawn.dylib',
];

const List<String> _obsoleteSamplerLibraries = [
  'libLiteRtTopKMetalSampler.dylib',
  'libLiteRtTopKWebGpuSampler.dylib',
];

/// What Xcode embeds from the companion's v0.19.0 xcframeworks.
const List<String> _arm64SwiftPmFiles = [
  'LiteRtLm.framework/Versions/A/LiteRtLm',
  'libCLiteRTLM_mac.dylib',
  'LiteRtLm.framework/Versions/A/Dependencies/libGemmaModelConstraintProvider.dylib',
  'libwebgpu_dawn.dylib',
];

const List<String> _oldFrameworks = [
  'GemmaModelConstraintProvider',
  'LiteRt',
  'LiteRtLm',
  'LiteRtMetalAccelerator',
  'LiteRtTopKMetalSampler',
  'LiteRtTopKWebGpuSampler',
  'LiteRtWebGpuAccelerator',
];
