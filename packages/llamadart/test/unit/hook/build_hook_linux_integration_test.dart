@TestOn('vm')
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../../hook/build.dart' as build_hook;
import '../../support/hook_project_root.dart';
import '../../support/hooks_runner_layout.dart';
import '../../support/native_bundle_cache.dart';
import '../../support/runtime_bundle_http_fixture.dart';

void main() {
  final nativeTag = _readHookNativeTag();
  final litertVersion = _readHookLiteRtLmVersion();
  final project = HookProjectRoot.create();
  final cacheRelativeDir =
      '.dart_tool/llamadart/native_bundles_v2/$nativeTag/linux-x64';
  final bundleDir = Directory(project.resolve('$cacheRelativeDir/extracted'));
  const historicalNativeTag = 'b10545';
  final historicalBundleDir = Directory(
    project.resolve(
      '.dart_tool/llamadart/native_bundles_v2/$historicalNativeTag/'
      'linux-x64/extracted',
    ),
  );
  final litertBundleDir = Directory(
    project.resolve('.dart_tool/llamadart/litert_lm/$litertVersion/linux/x64'),
  );

  setUp(() async {
    if (bundleDir.existsSync()) {
      await bundleDir.delete(recursive: true);
    }
    await _writeBundleLibraries(bundleDir, const [
      'libllamadart.so',
      'libmtmd.so',
      'libllama.so',
      'libllama-common.so',
      'libggml.so',
      'libggml-base.so',
      'libggml-cpu.so',
      'libggml-vulkan.so',
    ]);
    await markExtractedBundle(bundleDir);
    await _writeBundleLibraries(historicalBundleDir, const [
      'libllamadart.so',
      'libmtmd.so',
      'libllama.so',
      'libllama-common.so',
      'libggml.so',
      'libggml-base.so',
      'libggml-cpu.so',
      'libggml-vulkan.so',
    ]);
    await markExtractedBundle(historicalBundleDir);
    // The owner archive also carries the prebuilt libLiteRt.so that the
    // Linux host links in instead of loading.
    await _writeBundleLibraries(litertBundleDir, [
      ..._linuxLiteRtLibraries,
      'libLiteRt.so',
    ]);
  });

  tearDownAll(project.delete);

  test(
    'build hook emits linux SONAME aliases and all runtimes by default',
    () async {
      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.linux,
        targetArchitecture: Architecture.x64,
        check: (input, output) {
          final codeAssets = output.assets.encodedAssets
              .where((asset) => asset.isCodeAsset)
              .map((asset) => asset.asCodeAsset)
              .toList(growable: false);

          final codeAssetIds = codeAssets.map((asset) => asset.id).toSet();
          expect(codeAssetIds, contains('package:llamadart/llamadart'));

          final emittedNames = codeAssets
              .map((asset) => path.basename(asset.file!.toFilePath()))
              .toSet();

          expect(emittedNames, contains('libllamadart.so'));
          expect(emittedNames, contains('libmtmd.so'));
          expect(emittedNames, contains('libmtmd.so.0'));
          expect(emittedNames, isNot(contains('libmtmd.so.SOVERSION')));
          expect(emittedNames, contains('libllama.so'));
          expect(emittedNames, contains('libllama.so.0'));
          expect(emittedNames, contains('libllama-common.so'));
          expect(emittedNames, contains('libllama-common.so.0'));
          expect(emittedNames, contains('libggml.so'));
          expect(emittedNames, contains('libggml.so.0'));
          expect(emittedNames, contains('libggml-base.so'));
          expect(emittedNames, contains('libggml-base.so.0'));
          for (final library in _linuxLiteRtLibraries) {
            expect(emittedNames, contains(library));
          }
          for (final assetName in _linuxLiteRtAssetNames) {
            expect(codeAssetIds, contains('package:llamadart/$assetName'));
          }
          expect(emittedNames, isNot(contains('libLiteRt.so')));
        },
      );
    },
  );

  group('Flutter Edge AI coexistence', () {
    const workspacePubspec = 'name: workspace\nworkspace: [app, other]\n';
    final cases =
        <
          ({
            String name,
            List<String> roots,
            Map<String, List<String>> dependencies,
            Map<String, List<String>> devDependencies,
            String pubspec,
            Object? runtimes,
            bool bundlesLiteRtLm,
            List<String> warns,
          })
        >[
          for (final runtimes in [null, 'both'])
            (
              name: 'standalone app reaching $_edgeAiLlama, runtimes $runtimes',
              roots: ['app'],
              dependencies: {
                'app': [_edgeAiLlama],
                _edgeAiLlama: ['llamadart'],
                'llamadart': [],
              },
              devDependencies: {},
              pubspec: 'name: app\n',
              runtimes: runtimes,
              bundlesLiteRtLm: false,
              warns: [_edgeAiLlama, 'name litert_lm'],
            ),
          (
            name: 'standalone app with $_edgeAiLiteRtLm',
            roots: ['app'],
            dependencies: {
              'app': ['llamadart', _edgeAiLiteRtLm],
              _edgeAiLiteRtLm: [],
              'llamadart': [],
            },
            devDependencies: {},
            pubspec: 'name: app\n',
            runtimes: null,
            bundlesLiteRtLm: false,
            warns: [_edgeAiLiteRtLm, 'owns the same native libraries'],
          ),
          (
            name: 'standalone app naming litert_lm beside $_edgeAiLlama',
            roots: ['app'],
            dependencies: {
              'app': [_edgeAiLlama],
              _edgeAiLlama: ['llamadart'],
              'llamadart': [],
            },
            devDependencies: {},
            pubspec: 'name: app\n',
            runtimes: ['llama_cpp', 'litert_lm'],
            bundlesLiteRtLm: true,
            warns: [],
          ),
          (
            name: 'standalone app with $_edgeAiLlama as a dev dependency',
            roots: ['app'],
            dependencies: {
              'app': ['llamadart'],
              _edgeAiLlama: ['llamadart'],
              'llamadart': [],
            },
            devDependencies: {
              'app': [_edgeAiLlama],
            },
            pubspec: 'name: app\n',
            runtimes: null,
            bundlesLiteRtLm: false,
            warns: [_edgeAiLlama],
          ),
          (
            name: 'non-Apple app also resolving the Apple LiteRT-LM companion',
            roots: ['app'],
            dependencies: {
              'app': [
                'llamadart',
                _edgeAiLiteRtLm,
                'llamadart_litert_lm_flutter',
              ],
              _edgeAiLiteRtLm: [],
              'llamadart_litert_lm_flutter': ['llamadart'],
              'llamadart': [],
            },
            devDependencies: {},
            pubspec: 'name: app\n',
            runtimes: null,
            bundlesLiteRtLm: false,
            warns: [_edgeAiLiteRtLm],
          ),
          (
            name: 'workspace member with both engines, none in the root',
            roots: ['workspace', 'app', _edgeAiLlama, _edgeAiLiteRtLm],
            dependencies: {
              'workspace': [],
              'app': [_edgeAiLlama, _edgeAiLiteRtLm],
              _edgeAiLlama: ['llamadart'],
              _edgeAiLiteRtLm: [],
              'llamadart': [],
              'melos': [],
            },
            devDependencies: {
              'workspace': ['melos'],
            },
            pubspec:
                'name: workspace\n'
                'workspace: [app, $_edgeAiLlama, $_edgeAiLiteRtLm]\n'
                'dev_dependencies:\n'
                '  melos: any\n',
            runtimes: null,
            bundlesLiteRtLm: false,
            warns: [_edgeAiLlama, _edgeAiLiteRtLm],
          ),
          (
            name: 'workspace whose other member bundles $_edgeAiLlama',
            roots: ['workspace', 'app', 'other'],
            dependencies: {
              'workspace': [],
              'app': ['llamadart'],
              'other': [_edgeAiLlama],
              _edgeAiLlama: ['llamadart'],
              'llamadart': [],
            },
            devDependencies: {},
            pubspec: workspacePubspec,
            runtimes: null,
            bundlesLiteRtLm: false,
            warns: [_edgeAiLlama],
          ),
          (
            name:
                'workspace whose $_edgeAiLiteRtLm member never builds llamadart',
            roots: ['workspace', 'app', 'other'],
            dependencies: {
              'workspace': [],
              'app': ['llamadart'],
              'other': [_edgeAiLiteRtLm],
              _edgeAiLiteRtLm: [],
              'llamadart': [],
            },
            devDependencies: {},
            pubspec: workspacePubspec,
            runtimes: null,
            bundlesLiteRtLm: true,
            warns: [],
          ),
          (
            name: 'workspace member depending on a member with a dev engine',
            roots: ['workspace', 'app', 'other'],
            dependencies: {
              'workspace': [],
              'app': ['llamadart', 'other'],
              'other': [],
              _edgeAiLiteRtLm: [],
              'llamadart': [],
            },
            devDependencies: {
              'other': [_edgeAiLiteRtLm],
            },
            pubspec: workspacePubspec,
            runtimes: null,
            bundlesLiteRtLm: true,
            warns: [],
          ),
        ];

    for (final scenario in cases) {
      test(scenario.name, () async {
        final layout = await HooksRunnerLayout.create(
          roots: scenario.roots,
          dependencies: scenario.dependencies,
          devDependencies: scenario.devDependencies,
          pubspec: scenario.pubspec,
        );
        addTearDown(layout.delete);
        final run = await _runLinuxHook(
          project: project,
          layout: layout,
          defines: scenario.runtimes == null
              ? null
              : {'llamadart_native_runtimes': scenario.runtimes},
        );
        expect(run.assets.values, contains('libllamadart.so'));
        expect(
          run.assets.values.toSet().intersection(_linuxLiteRtLibraries.toSet()),
          scenario.bundlesLiteRtLm ? _linuxLiteRtLibraries.toSet() : isEmpty,
        );
        expect(
          run.assets.keys.where((id) => id.contains('litert_lm')),
          scenario.bundlesLiteRtLm ? isNotEmpty : isEmpty,
        );
        expect(run.dependencies, contains(layout.packageGraph.uri));
        final warning = run.warnings.where(
          (message) => message.contains('LiteRT-LM'),
        );
        if (scenario.warns.isEmpty) {
          expect(warning, isEmpty);
        } else {
          expect(warning.single, stringContainsInOrder(scenario.warns));
        }
      });
    }

    test('naming only litert_lm beside $_edgeAiLlama keeps it', () async {
      final layout = await HooksRunnerLayout.create(
        roots: ['app'],
        dependencies: {
          'app': [_edgeAiLlama],
          _edgeAiLlama: ['llamadart'],
          'llamadart': [],
        },
      );
      addTearDown(layout.delete);
      final run = await _runLinuxHook(
        project: project,
        layout: layout,
        defines: {
          'llamadart_native_runtimes': ['litert_lm'],
        },
      );
      expect(run.assets.values, unorderedEquals(_linuxLiteRtLibraries));
      expect(run.warnings, isEmpty);
    });

    test('naming only litert_lm beside $_edgeAiLiteRtLm fails', () async {
      final layout = await HooksRunnerLayout.create(
        roots: ['app'],
        dependencies: {
          'app': ['llamadart', _edgeAiLiteRtLm],
          _edgeAiLiteRtLm: [],
          'llamadart': [],
        },
      );
      addTearDown(layout.delete);
      await expectLater(
        _runLinuxHook(
          project: project,
          layout: layout,
          defines: {
            'llamadart_native_runtimes': ['litert_lm'],
          },
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Conflicting LiteRT-LM runtimes'),
          ),
        ),
      );
    });

    test(
      'only LiteRT-LM assets follow the resolved graph',
      () => expectOnlyLiteRtLmFollowsResolvedGraph(
        hookMain: build_hook.main,
        targetOS: OS.linux,
        targetArchitecture: Architecture.x64,
        liteRtLmLibraries: _linuxLiteRtLibraries,
        project: project,
      ),
    );

    test('an unreadable graph keeps the selection and warns', () async {
      final layout = await HooksRunnerLayout.create(
        roots: ['app'],
        dependencies: {
          'app': [_edgeAiLlama],
        },
      );
      addTearDown(layout.delete);
      await layout.packageGraph.writeAsString('{"roots": ["app"]}');
      final run = await _runLinuxHook(project: project, layout: layout);
      expect(run.assets.values, containsAll(_linuxLiteRtLibraries));
      expect(
        run.warnings.single,
        stringContainsInOrder([
          layout.packageGraph.path,
          'llamadart_native_runtimes: [llama_cpp]',
        ]),
      );
    });
  });

  test('build hook preserves historical linux mtmd SONAME alias', () async {
    await project.testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.linux,
      targetArchitecture: Architecture.x64,
      userDefines: PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: const {'llamadart_native_tag': historicalNativeTag},
          basePath: Directory.current.uri,
        ),
      ),
      check: (input, output) {
        final emittedNames = output.assets.encodedAssets
            .where((asset) => asset.isCodeAsset)
            .map((asset) => asset.asCodeAsset)
            .map((asset) => path.basename(asset.file!.toFilePath()))
            .toSet();

        expect(emittedNames, contains('libmtmd.so'));
        expect(emittedNames, contains('libmtmd.so.0'));
        expect(emittedNames, contains('libmtmd.so.SOVERSION'));
      },
    );
  });

  test('build hook emits archive symlink aliases with target bytes', () async {
    const overrideTag = 'v9.8.7';
    final overrideCacheDir = Directory(
      project.resolve(
        '.dart_tool/llamadart/native_bundles_v2/$overrideTag/linux-x64',
      ),
    );
    final overrideArchive = File(
      path.join(
        overrideCacheDir.path,
        'llamadart-native-linux-x64-$overrideTag.tar.gz',
      ),
    );
    if (overrideCacheDir.existsSync()) {
      await overrideCacheDir.delete(recursive: true);
    }
    addTearDown(() async {
      if (overrideCacheDir.existsSync()) {
        await overrideCacheDir.delete(recursive: true);
      }
    });
    await _writeSymlinkedBundleArchive(overrideArchive);
    final fixture = RuntimeBundleHttpFixture({
      'https://github.com/leehack/llamadart-native/releases/download/'
          '$overrideTag/SHA256SUMS': sha256SumsFor({
        path.basename(overrideArchive.path): overrideArchive.readAsBytesSync(),
      }).codeUnits,
    });

    await build_hook.withRuntimeBundleHttpClientForTesting(
      fixture.createClient,
      () => project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.linux,
        targetArchitecture: Architecture.x64,
        userDefines: PackageUserDefines(
          workspacePubspec: PackageUserDefinesSource(
            defines: const {'llamadart_native_tag': overrideTag},
            basePath: Directory.current.uri,
          ),
        ),
        check: (input, output) {
          final assetFilesByName = <String, File>{};
          for (final asset
              in output.assets.encodedAssets
                  .where((asset) => asset.isCodeAsset)
                  .map((asset) => asset.asCodeAsset)) {
            final assetFile = File(asset.file!.toFilePath());
            assetFilesByName[path.basename(assetFile.path)] = assetFile;
          }

          for (final fileName in const ['libmtmd.so', 'libmtmd.so.0']) {
            final assetFile = assetFilesByName[fileName];
            expect(assetFile, isNotNull, reason: fileName);
            expect(
              assetFile!.readAsStringSync(),
              _mtmdPayload,
              reason: fileName,
            );
          }

          expect(
            assetFilesByName['libllamadart.so']?.readAsStringSync(),
            'archive-libllamadart.so',
          );
        },
      ),
    );
    expect(fixture.requests, hasLength(1));
  });

  test('build hook fails when runtimes config selects none', () async {
    for (final rawUserConfig in const <Object>['none', false]) {
      await expectLater(
        project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.linux,
          targetArchitecture: Architecture.x64,
          userDefines: PackageUserDefines(
            workspacePubspec: PackageUserDefinesSource(
              defines: {'llamadart_native_runtimes': rawUserConfig},
              basePath: Directory.current.uri,
            ),
          ),
          check: (_, _) {},
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('No native runtimes selected for linux-x64'),
          ),
        ),
      );
    }
  });
}

String _readHookNativeTag() {
  final source = File(
    'lib/src/hook/native_release_pins.dart',
  ).readAsStringSync();
  final match = RegExp(r"const llamaCppTag = '([^']+)';").firstMatch(source);
  if (match == null) {
    throw StateError(
      'Could not locate llamaCppTag in lib/src/hook/native_release_pins.dart',
    );
  }
  return match.group(1)!;
}

String _readHookLiteRtLmVersion() {
  final source = File(
    'lib/src/hook/native_release_pins.dart',
  ).readAsStringSync();
  final match = RegExp(
    r"const liteRtLmVersion = '([^']+)';",
  ).firstMatch(source);
  if (match == null) {
    throw StateError(
      'Could not locate liteRtLmVersion in lib/src/hook/native_release_pins.dart',
    );
  }
  return match.group(1)!;
}

const List<String> _linuxLiteRtLibraries = [
  'libGemmaModelConstraintProvider.so',
  'libLiteRtLm.so',
  'libwebgpu_dawn.so',
  'libLiteRtWebGpuAccelerator.so',
];

const List<String> _linuxLiteRtAssetNames = [
  'litert_lm_GemmaModelConstraintProvider',
  'litert_lm_LiteRtLm',
  'litert_lm_webgpu_dawn',
  'litert_lm_LiteRtWebGpuAccelerator',
];

const String _edgeAiLlama = 'flutter_edge_ai_llama';
const String _edgeAiLiteRtLm = 'flutter_edge_ai_litertlm';

Future<HookRun> _runLinuxHook({
  required HookProjectRoot project,
  HooksRunnerLayout? layout,
  Map<String, Object?>? defines,
}) => runCodeBuildHook(
  hookMain: build_hook.main,
  targetOS: OS.linux,
  targetArchitecture: Architecture.x64,
  layout: layout,
  project: project,
  userDefines: layout?.userDefines(defines),
);

const String _mtmdPayload = 'archive-libmtmd.so.0.2.0';

Future<void> _writeSymlinkedBundleArchive(File archiveFile) async {
  final archive = Archive();

  void addRegularFile(String name, String content) {
    archive.addFile(ArchiveFile(name, content.length, content.codeUnits));
  }

  addRegularFile('libllamadart.so', 'archive-libllamadart.so');
  addRegularFile('libmtmd.so.0.2.0', _mtmdPayload);
  archive.addFile(ArchiveFile.symlink('libmtmd.so.0', 'libmtmd.so.0.2.0'));
  archive.addFile(ArchiveFile.symlink('libmtmd.so', 'libmtmd.so.0'));
  for (final name in const [
    'libllama.so',
    'libllama-common.so',
    'libggml.so',
    'libggml-base.so',
    'libggml-cpu.so',
    'libggml-vulkan.so',
  ]) {
    addRegularFile(name, 'archive-$name');
  }

  await archiveFile.parent.create(recursive: true);
  await archiveFile.writeAsBytes(
    GZipEncoder().encode(TarEncoder().encode(archive)),
  );
}

Future<void> _writeBundleLibraries(
  Directory bundleDir,
  List<String> fileNames,
) async {
  if (bundleDir.existsSync()) {
    await bundleDir.delete(recursive: true);
  }
  await bundleDir.create(recursive: true);
  for (final name in fileNames) {
    await File(path.join(bundleDir.path, name)).writeAsString('fake-$name');
  }
}
