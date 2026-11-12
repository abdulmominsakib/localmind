@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/hook/windows_file_version.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../../hook/build.dart' as build_hook;
import '../../support/hook_project_root.dart';
import '../../support/hooks_runner_layout.dart';
import '../../support/native_bundle_cache.dart';
import '../../support/runtime_bundle_http_fixture.dart';
import '../../support/windows_version_resource.dart';

void main() {
  final nativeTag = _readHookNativeTag();
  final litertVersion = _readHookLiteRtLmVersion();
  final project = HookProjectRoot.create();
  final cacheRelativeDir =
      '.dart_tool/llamadart/native_bundles_v2/$nativeTag/windows-x64';
  final bundleDir = Directory(project.resolve('$cacheRelativeDir/extracted'));
  final litertBundleDir = Directory(
    project.resolve(
      '.dart_tool/llamadart/litert_lm/$litertVersion/windows/x64',
    ),
  );

  setUp(() async {
    if (bundleDir.existsSync()) {
      await bundleDir.delete(recursive: true);
    }
    await _writeBundleLibraries(bundleDir, const [
      'llamadart-windows-x64.dll',
      'llama-windows-x64.dll',
      'ggml-windows-x64.dll',
      'ggml-base-windows-x64.dll',
      'ggml-cpu-windows-x64.dll',
      'ggml-vulkan-windows-x64.dll',
      'ggml-cuda-windows-x64.dll',
      'cudart64_12.dll',
      'cublas64_12.dll',
      'cublaslt64_12.dll',
    ]);
    await markExtractedBundle(bundleDir);
    // The owner archive also carries the prebuilt libLiteRt.dll that the
    // Windows host links in instead of loading.
    await _writeBundleLibraries(litertBundleDir, [
      ..._windowsLiteRtLibraries,
      'libLiteRt.dll',
    ]);
  });

  tearDownAll(project.delete);

  test(
    'hook assets and Windows fallback share v2 and leave legacy untouched',
    () async {
      final legacy = Directory(
        project.resolve(
          '.dart_tool/llamadart/native_bundles/v9.9.9/windows-x64/extracted',
        ),
      );
      await _writeBundleLibraries(legacy, const [
        'llamadart-windows-x64.dll',
        'llama-windows-x64.dll',
        'ggml-windows-x64.dll',
        'ggml-cpu-windows-x64.dll',
      ]);
      final sentinel = File(path.join(legacy.path, 'llama-windows-x64.dll'))
        ..writeAsStringSync('legacy runtime');
      final original = sentinel.readAsBytesSync();

      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.windows,
        targetArchitecture: Architecture.x64,
        userDefines: PackageUserDefines(
          workspacePubspec: PackageUserDefinesSource(
            defines: {
              'llamadart_native_runtimes': ['llama_cpp'],
            },
            basePath: Directory.current.uri,
          ),
        ),
        check: (_, output) {
          final assets = output.assets.encodedAssets
              .where((asset) => asset.isCodeAsset)
              .map((asset) => asset.asCodeAsset);
          expect(assets, isNotEmpty);
          for (final asset in assets) {
            final emitted = File.fromUri(asset.file!);
            expect(
              emitted.readAsBytesSync(),
              File(
                path.join(bundleDir.path, path.basename(emitted.path)),
              ).readAsBytesSync(),
            );
          }
          final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
            resolvedExecutablePath: path.join(
              project.directory.path,
              'sdk',
              'dart.exe',
            ),
            currentDirectoryPath: project.directory.path,
            environment: const {},
          );
          expect(path.normalize(resolved!), path.normalize(bundleDir.path));
        },
      );
      expect(sentinel.readAsBytesSync(), original);
    },
  );

  test(
    'build hook selects configured backend modules and all runtimes by default',
    () async {
      final userDefines = PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: {
            'llamadart_native_backends': {
              'platforms': {
                'windows-x64': ['vulkan'],
              },
            },
          },
          basePath: Directory.current.uri,
        ),
      );

      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.windows,
        targetArchitecture: Architecture.x64,
        userDefines: userDefines,
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

          expect(emittedNames, contains('ggml-vulkan-windows-x64.dll'));
          expect(emittedNames, contains('ggml-cpu-windows-x64.dll'));
          expect(emittedNames, contains('llamadart-windows-x64.dll'));
          expect(emittedNames, contains('llama-windows-x64.dll'));
          expect(emittedNames, contains('ggml-windows-x64.dll'));
          expect(emittedNames, contains('ggml-base-windows-x64.dll'));
          for (final library in _windowsLiteRtLibraries) {
            expect(emittedNames, contains(library));
          }
          for (final assetName in _windowsLiteRtAssetNames) {
            expect(codeAssetIds, contains('package:llamadart/$assetName'));
          }
          expect(emittedNames, isNot(contains('libLiteRt.dll')));
          expect(emittedNames, isNot(contains('ggml-cuda-windows-x64.dll')));
          expect(emittedNames, isNot(contains('cudart64_12.dll')));
          expect(emittedNames, isNot(contains('cublas64_12.dll')));
          expect(emittedNames, isNot(contains('cublaslt64_12.dll')));
        },
      );
    },
  );

  test('build hook can emit both runtime families when requested', () async {
    final userDefines = PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: {
          'llamadart_native_runtimes': ['both'],
          'llamadart_native_backends': {
            'platforms': {
              'windows-x64': ['vulkan'],
            },
          },
        },
        basePath: Directory.current.uri,
      ),
    );

    await project.testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.windows,
      targetArchitecture: Architecture.x64,
      userDefines: userDefines,
      check: (input, output) {
        final codeAssets = output.assets.encodedAssets
            .where((asset) => asset.isCodeAsset)
            .map((asset) => asset.asCodeAsset)
            .toList(growable: false);

        final codeAssetIds = codeAssets.map((asset) => asset.id).toSet();
        final emittedNames = codeAssets
            .map((asset) => path.basename(asset.file!.toFilePath()))
            .toSet();

        expect(codeAssetIds, contains('package:llamadart/llamadart'));
        expect(emittedNames, contains('ggml-vulkan-windows-x64.dll'));
        for (final library in _windowsLiteRtLibraries) {
          expect(emittedNames, contains(library));
        }
        for (final assetName in _windowsLiteRtAssetNames) {
          expect(codeAssetIds, contains('package:llamadart/$assetName'));
        }
      },
    );
  });

  test('build hook can emit llama.cpp runtime without LiteRT-LM', () async {
    final userDefines = PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: {
          'llamadart_native_runtimes': ['llama_cpp'],
          'llamadart_native_backends': {
            'platforms': {
              'windows-x64': ['vulkan'],
            },
          },
        },
        basePath: Directory.current.uri,
      ),
    );

    await project.testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.windows,
      targetArchitecture: Architecture.x64,
      userDefines: userDefines,
      check: (input, output) {
        final codeAssets = output.assets.encodedAssets
            .where((asset) => asset.isCodeAsset)
            .map((asset) => asset.asCodeAsset)
            .toList(growable: false);

        final codeAssetIds = codeAssets.map((asset) => asset.id).toSet();
        final emittedNames = codeAssets
            .map((asset) => path.basename(asset.file!.toFilePath()))
            .toSet();

        expect(codeAssetIds, contains('package:llamadart/llamadart'));
        expect(emittedNames, contains('ggml-vulkan-windows-x64.dll'));
        for (final library in _windowsLiteRtLibraries) {
          expect(emittedNames, isNot(contains(library)));
        }
        for (final assetName in _windowsLiteRtAssetNames) {
          expect(codeAssetIds, isNot(contains('package:llamadart/$assetName')));
        }
      },
    );
  });

  test('build hook supports OS-level runtime selection', () async {
    final userDefines = PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: {
          'llamadart_native_runtimes': {
            'runtimes': ['llama_cpp', 'litert_lm'],
            'platforms': {
              'windows': ['llama_cpp'],
            },
          },
          'llamadart_native_backends': {
            'platforms': {
              'windows-x64': ['vulkan'],
            },
          },
        },
        basePath: Directory.current.uri,
      ),
    );

    await project.testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.windows,
      targetArchitecture: Architecture.x64,
      userDefines: userDefines,
      check: (input, output) {
        final codeAssets = output.assets.encodedAssets
            .where((asset) => asset.isCodeAsset)
            .map((asset) => asset.asCodeAsset)
            .toList(growable: false);

        final codeAssetIds = codeAssets.map((asset) => asset.id).toSet();
        final emittedNames = codeAssets
            .map((asset) => path.basename(asset.file!.toFilePath()))
            .toSet();

        expect(codeAssetIds, contains('package:llamadart/llamadart'));
        expect(emittedNames, contains('ggml-vulkan-windows-x64.dll'));
        for (final library in _windowsLiteRtLibraries) {
          expect(emittedNames, isNot(contains(library)));
        }
        for (final assetName in _windowsLiteRtAssetNames) {
          expect(codeAssetIds, isNot(contains('package:llamadart/$assetName')));
        }
      },
    );
  });

  test(
    'build hook refreshes stale windows cache from a verified cached archive',
    () async {
      const overrideTag = 'v9.8.7';
      final overrideCacheDir = Directory(
        project.resolve(
          '.dart_tool/llamadart/native_bundles_v2/$overrideTag/windows-x64',
        ),
      );
      final overrideArchive = File(
        path.join(
          overrideCacheDir.path,
          'llamadart-native-windows-x64-$overrideTag.tar.gz',
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
      await _writeBundleLibraries(
        Directory(path.join(overrideCacheDir.path, 'extracted')),
        const [
          'llamadart-windows-x64.dll',
          'llama-windows-x64.dll',
          'ggml-windows-x64.dll',
          'ggml-base-windows-x64.dll',
          'ggml-cpu-windows-x64.dll',
          'ggml-cuda-windows-x64.dll',
        ],
      );
      await _writeBundleArchive(
        archiveFile: overrideArchive,
        files: const [
          'llamadart-windows-x64.dll',
          'llama-windows-x64.dll',
          'ggml-windows-x64.dll',
          'ggml-base-windows-x64.dll',
          'ggml-cpu-windows-x64.dll',
          'ggml-cuda-windows-x64.dll',
          'cudart64_12.dll',
          'cublas64_12.dll',
          'cublaslt64_12.dll',
        ],
      );
      final fixture = RuntimeBundleHttpFixture({
        'https://github.com/leehack/llamadart-native/releases/download/'
            '$overrideTag/SHA256SUMS': sha256SumsFor({
          path.basename(overrideArchive.path): overrideArchive
              .readAsBytesSync(),
        }).codeUnits,
      });

      final userDefines = PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: {
            'llamadart_native_tag': overrideTag,
            'llamadart_native_backends': {
              'platforms': {
                'windows-x64': ['cuda'],
              },
            },
          },
          basePath: Directory.current.uri,
        ),
      );

      await build_hook.withRuntimeBundleHttpClientForTesting(
        fixture.createClient,
        () => project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.windows,
          targetArchitecture: Architecture.x64,
          userDefines: userDefines,
          check: (input, output) {
            final codeAssets = output.assets.encodedAssets
                .where((asset) => asset.isCodeAsset)
                .map((asset) => asset.asCodeAsset)
                .toList(growable: false);

            final emittedNames = codeAssets
                .map((asset) => path.basename(asset.file!.toFilePath()))
                .toSet();

            expect(emittedNames, contains('ggml-cuda-windows-x64.dll'));
            expect(emittedNames, contains('cudart64_12.dll'));
            expect(emittedNames, contains('cublas64_12.dll'));
            expect(emittedNames, contains('cublaslt64_12.dll'));
          },
        ),
      );
      expect(fixture.requests, hasLength(1));
    },
  );

  test('build hook uses accepted wrapper native tag overrides', () async {
    for (final overrideTag in const [
      'v9.8.8-1',
      'b0-1',
      'b0-llamadart.1',
      'b10514-1',
      'b10514-llamadart.1',
    ]) {
      final overrideCacheDir = Directory(
        project.resolve(
          '.dart_tool/llamadart/native_bundles_v2/$overrideTag/windows-x64',
        ),
      );
      final overrideBundleDir = Directory(
        path.join(overrideCacheDir.path, 'extracted'),
      );
      final overrideBackupDir = Directory(
        '${overrideCacheDir.path}.__hook_test_backup',
      );

      if (overrideBackupDir.existsSync()) {
        await overrideBackupDir.delete(recursive: true);
      }
      if (overrideCacheDir.existsSync()) {
        await overrideCacheDir.rename(overrideBackupDir.path);
      }

      try {
        await _writeBundleLibraries(overrideBundleDir, const [
          'llamadart-windows-x64.dll',
          'llama-windows-x64.dll',
          'ggml-windows-x64.dll',
          'ggml-base-windows-x64.dll',
          'ggml-cpu-windows-x64.dll',
          'ggml-opencl-windows-x64.dll',
        ]);
        await markExtractedBundle(overrideBundleDir);

        final userDefines = PackageUserDefines(
          workspacePubspec: PackageUserDefinesSource(
            defines: {
              'llamadart_native_tag': overrideTag,
              'llamadart_native_backends': {
                'platforms': {
                  'windows-x64': ['opencl'],
                },
              },
            },
            basePath: Directory.current.uri,
          ),
        );

        await project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.windows,
          targetArchitecture: Architecture.x64,
          userDefines: userDefines,
          check: (input, output) {
            final codeAssets = output.assets.encodedAssets
                .where((asset) => asset.isCodeAsset)
                .map((asset) => asset.asCodeAsset)
                .toList(growable: false);

            final emittedNames = codeAssets
                .map((asset) => path.basename(asset.file!.toFilePath()))
                .toSet();

            expect(emittedNames, contains('ggml-opencl-windows-x64.dll'));
            expect(
              emittedNames,
              isNot(contains('ggml-vulkan-windows-x64.dll')),
            );
          },
        );
      } finally {
        if (overrideCacheDir.existsSync()) {
          await overrideCacheDir.delete(recursive: true);
        }
        if (overrideBackupDir.existsSync()) {
          await overrideBackupDir.rename(overrideCacheDir.path);
        }
      }
    }
  });

  test('build hook uses custom GitHub repository cache namespace', () async {
    const overrideTag = 'b0';
    const customRepository = 'example/native-fork';
    final repoCacheRoot = Directory(
      project.resolve(
        '.dart_tool/llamadart/native_bundles_v2/github/example/native-fork',
      ),
    );
    final overrideBundleDir = Directory(
      path.join(repoCacheRoot.path, overrideTag, 'windows-x64', 'extracted'),
    );
    final overrideBackupDir = Directory(
      '${repoCacheRoot.path}.__hook_test_backup',
    );

    if (overrideBackupDir.existsSync()) {
      await overrideBackupDir.delete(recursive: true);
    }
    if (repoCacheRoot.existsSync()) {
      await repoCacheRoot.rename(overrideBackupDir.path);
    }

    try {
      await _writeBundleLibraries(overrideBundleDir, const [
        'llamadart-windows-x64.dll',
        'llama-windows-x64.dll',
        'ggml-windows-x64.dll',
        'ggml-base-windows-x64.dll',
        'ggml-cpu-windows-x64.dll',
        'ggml-opencl-windows-x64.dll',
      ]);
      await markExtractedBundle(overrideBundleDir);

      final userDefines = PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: {
            'llamadart_native_tag': overrideTag,
            'llamadart_native_repository':
                'https://github.com/$customRepository',
            'llamadart_native_backends': {
              'platforms': {
                'windows-x64': ['opencl'],
              },
            },
          },
          basePath: Directory.current.uri,
        ),
      );

      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.windows,
        targetArchitecture: Architecture.x64,
        userDefines: userDefines,
        check: (input, output) {
          final emittedNames = _emittedFileNames(output);

          expect(emittedNames, contains('ggml-opencl-windows-x64.dll'));
          expect(emittedNames, isNot(contains('ggml-vulkan-windows-x64.dll')));
        },
      );
    } finally {
      if (repoCacheRoot.existsSync()) {
        await repoCacheRoot.delete(recursive: true);
      }
      if (overrideBackupDir.existsSync()) {
        await overrideBackupDir.rename(repoCacheRoot.path);
      }
    }
  });

  test('build hook uses local native path directory', () async {
    const localRootPath = '.dart_tool/llamadart_hook_test_local_dir';
    final localRoot = Directory(project.resolve(localRootPath));
    final localBundleDir = Directory(path.join(localRoot.path, 'windows-x64'));

    if (localRoot.existsSync()) {
      await localRoot.delete(recursive: true);
    }

    try {
      await _writeBundleLibraries(localBundleDir, const [
        'llamadart-windows-x64.dll',
        'llama-windows-x64.dll',
        'ggml-windows-x64.dll',
        'ggml-base-windows-x64.dll',
        'ggml-cpu-windows-x64.dll',
        'ggml-opencl-windows-x64.dll',
      ]);

      final userDefines = PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: {
            'llamadart_native_path': localRootPath,
            'llamadart_native_backends': {
              'platforms': {
                'windows-x64': ['opencl'],
              },
            },
          },
          basePath: project.directory.uri,
        ),
      );

      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.windows,
        targetArchitecture: Architecture.x64,
        userDefines: userDefines,
        check: (input, output) {
          final emittedNames = _emittedFileNames(output);

          expect(emittedNames, contains('ggml-opencl-windows-x64.dll'));
          expect(emittedNames, isNot(contains('ggml-vulkan-windows-x64.dll')));
        },
      );
    } finally {
      if (localRoot.existsSync()) {
        await localRoot.delete(recursive: true);
      }
    }
  });

  test('build hook uses local native path archive', () async {
    const overrideTag = 'b0-llamadart.1';
    const localRootPath = '.dart_tool/llamadart_hook_test_local_archive';
    final localRoot = Directory(project.resolve(localRootPath));
    final archiveFile = File(
      path.join(
        localRoot.path,
        'llamadart-native-windows-x64-$overrideTag.tar.gz',
      ),
    );
    final localCacheRoot = Directory(
      _localPathCacheRoot(
        project: project,
        localRootPath: localRootPath,
        nativeTag: overrideTag,
        bundle: 'windows-x64',
      ),
    );

    if (localRoot.existsSync()) {
      await localRoot.delete(recursive: true);
    }
    if (localCacheRoot.existsSync()) {
      await localCacheRoot.delete(recursive: true);
    }

    try {
      await _writeBundleArchive(
        archiveFile: archiveFile,
        files: const [
          'llamadart-windows-x64.dll',
          'llama-windows-x64.dll',
          'ggml-windows-x64.dll',
          'ggml-base-windows-x64.dll',
          'ggml-cpu-windows-x64.dll',
          'ggml-opencl-windows-x64.dll',
        ],
      );

      final userDefines = PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: {
            'llamadart_native_tag': overrideTag,
            'llamadart_native_path': localRootPath,
            'llamadart_native_backends': {
              'platforms': {
                'windows-x64': ['opencl'],
              },
            },
          },
          basePath: project.directory.uri,
        ),
      );

      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.windows,
        targetArchitecture: Architecture.x64,
        userDefines: userDefines,
        check: (input, output) {
          final emittedNames = _emittedFileNames(output);

          expect(emittedNames, contains('ggml-opencl-windows-x64.dll'));
          expect(emittedNames, isNot(contains('ggml-vulkan-windows-x64.dll')));
        },
      );
    } finally {
      if (localRoot.existsSync()) {
        await localRoot.delete(recursive: true);
      }
      if (localCacheRoot.existsSync()) {
        await localCacheRoot.delete(recursive: true);
      }
    }
  });

  test('build hook rejects the shared negative tag corpus', () async {
    final fixture =
        jsonDecode(
              await File(
                'tool/native/fixtures/native_release_tag_grammar.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final invalidTags = <String>[
      for (final rawCase in fixture['negative_cases'] as List<dynamic>)
        (rawCase as Map<String, dynamic>)['tag'] as String,
      for (final rawCase in fixture['reserved_inputs'] as List<dynamic>)
        if (!(rawCase['dart_build_hook'] as bool)) rawCase['value'] as String,
    ];

    for (final invalidTag in invalidTags) {
      final userDefines = PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: {'llamadart_native_tag': invalidTag},
          basePath: Directory.current.uri,
        ),
      );

      await expectLater(
        project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.windows,
          targetArchitecture: Architecture.x64,
          userDefines: userDefines,
          check: (input, output) {},
        ),
        throwsA(isA<FormatException>()),
        reason: invalidTag,
      );
    }
  });

  test('build hook rejects invalid native repository override', () async {
    final userDefines = PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: const {'llamadart_native_repository': '../bad'},
        basePath: Directory.current.uri,
      ),
    );

    await expectLater(
      project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.windows,
        targetArchitecture: Architecture.x64,
        userDefines: userDefines,
        check: (input, output) {},
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('GitHub repository slug'),
        ),
      ),
    );
  });

  group('both runtime families ship the Visual C++ runtime', () {
    final bothRuntimes = PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: {
          'llamadart_native_runtimes': ['both'],
        },
        basePath: Directory.current.uri,
      ),
    );

    Future<void> writeDll(
      Directory bundle,
      String name,
      WindowsFileVersion version,
    ) => File(
      path.join(bundle.path, name),
    ).writeAsBytes(windowsDllWithVersion(version, label: bundle.path));

    test('the app bundles each runtime DLL once, the newer copy', () async {
      await writeDll(bundleDir, 'msvcp140.dll', (14, 51, 36247, 0));
      await writeDll(bundleDir, 'vcruntime140.dll', (14, 51, 36247, 0));
      await writeDll(bundleDir, 'vcruntime140_1.dll', (14, 51, 36247, 0));
      await markExtractedBundle(bundleDir);
      await writeDll(litertBundleDir, 'msvcp140.dll', (14, 52, 36300, 0));
      await writeDll(litertBundleDir, 'vcruntime140.dll', (14, 50, 35710, 0));
      await File(
        path.join(litertBundleDir.path, 'vcruntime140_1.dll'),
      ).writeAsBytes(
        await File(
          path.join(bundleDir.path, 'vcruntime140_1.dll'),
        ).readAsBytes(),
      );
      await writeDll(litertBundleDir, 'vcruntime140_threads.dll', (
        14,
        52,
        36300,
        0,
      ));

      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.windows,
        targetArchitecture: Architecture.x64,
        userDefines: bothRuntimes,
        check: (input, output) {
          final files = {
            for (final asset in output.assets.encodedAssets.where(
              (asset) => asset.isCodeAsset,
            ))
              asset.asCodeAsset.id: asset.asCodeAsset.file!.toFilePath(),
          };
          final names = files.values.map(path.basename).toList();
          expect(names.toSet(), hasLength(names.length));
          WindowsFileVersion? versionOf(String name) => windowsFileVersion(
            File(
              files.values.singleWhere((file) => path.basename(file) == name),
            ).readAsBytesSync(),
          );
          expect(versionOf('msvcp140.dll'), (14, 52, 36300, 0));
          expect(versionOf('vcruntime140.dll'), (14, 51, 36247, 0));
          expect(versionOf('vcruntime140_1.dll'), (14, 51, 36247, 0));
          expect(versionOf('vcruntime140_threads.dll'), (14, 52, 36300, 0));
          expect(
            files.keys,
            contains('package:llamadart/litert_lm_vcruntime140_threads'),
          );
          expect(
            files.keys,
            isNot(contains('package:llamadart/litert_lm_msvcp140')),
          );
          for (final library in _windowsLiteRtLibraries) {
            expect(names, contains(library));
          }
        },
      );
    });

    test('equal file versions keep the llama.cpp copy', () async {
      await writeDll(bundleDir, 'msvcp140.dll', (14, 51, 36247, 0));
      await markExtractedBundle(bundleDir);
      await writeDll(litertBundleDir, 'msvcp140.dll', (14, 51, 36247, 0));
      final llamaCppBytes = await File(
        path.join(bundleDir.path, 'msvcp140.dll'),
      ).readAsBytes();
      expect(
        await File(
          path.join(litertBundleDir.path, 'msvcp140.dll'),
        ).readAsBytes(),
        isNot(llamaCppBytes),
      );

      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.windows,
        targetArchitecture: Architecture.x64,
        userDefines: bothRuntimes,
        check: (input, output) {
          final bundled = output.assets.encodedAssets
              .where((asset) => asset.isCodeAsset)
              .map((asset) => asset.asCodeAsset.file!.toFilePath())
              .where((file) => path.basename(file) == 'msvcp140.dll')
              .toList();
          expect(bundled, hasLength(1));
          expect(File(bundled.single).readAsBytesSync(), llamaCppBytes);
        },
      );
    });

    test('a different unversioned library both ship fails the build', () async {
      await File(
        path.join(bundleDir.path, 'msvcp140.dll'),
      ).writeAsString('llama.cpp copy');
      await markExtractedBundle(bundleDir);
      await File(
        path.join(litertBundleDir.path, 'msvcp140.dll'),
      ).writeAsString('LiteRT-LM copy');

      await expectLater(
        project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.windows,
          targetArchitecture: Architecture.x64,
          userDefines: bothRuntimes,
          check: (input, output) {},
        ),
        throwsA(
          isA<Exception>().having(
            (error) => '$error',
            'message',
            contains('both ship a different `msvcp140.dll`'),
          ),
        ),
      );
    });
  });

  test(
    'only LiteRT-LM assets follow the resolved graph',
    () => expectOnlyLiteRtLmFollowsResolvedGraph(
      hookMain: build_hook.main,
      targetOS: OS.windows,
      targetArchitecture: Architecture.x64,
      liteRtLmLibraries: _windowsLiteRtLibraries,
      project: project,
    ),
  );
}

Set<String> _emittedFileNames(BuildOutput output) {
  final codeAssets = output.assets.encodedAssets
      .where((asset) => asset.isCodeAsset)
      .map((asset) => asset.asCodeAsset)
      .toList(growable: false);

  return codeAssets
      .map((asset) => path.basename(asset.file!.toFilePath()))
      .toSet();
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

const List<String> _windowsLiteRtLibraries = [
  'LiteRtLm.dll',
  'dxcompiler.dll',
  'dxil.dll',
  'libGemmaModelConstraintProvider.dll',
  'libwebgpu_dawn.dll',
  'webgpu_dawn.dll',
  'libLiteRtWebGpuAccelerator.dll',
  'msvcp140.dll',
  'vcruntime140.dll',
  'vcruntime140_1.dll',
  'vcruntime140_threads.dll',
];

const List<String> _windowsLiteRtAssetNames = [
  'litert_lm_LiteRtLm',
  'litert_lm_GemmaModelConstraintProvider',
  'litert_lm_webgpu_dawn',
  'litert_lm_LiteRtWebGpuAccelerator',
];

Future<void> _writeBundleArchive({
  required File archiveFile,
  required List<String> files,
}) async {
  final archive = Archive();
  for (final fileName in files) {
    final content = 'archive-$fileName';
    archive.addFile(ArchiveFile(fileName, content.length, content.codeUnits));
  }

  final tarBytes = TarEncoder().encode(archive);
  final gzBytes = GZipEncoder().encode(tarBytes);

  await archiveFile.parent.create(recursive: true);
  await archiveFile.writeAsBytes(gzBytes);
}

String _localPathCacheRoot({
  required HookProjectRoot project,
  required String localRootPath,
  required String nativeTag,
  required String bundle,
}) {
  final localRootUri = project.directory.uri.resolve(localRootPath);
  final digest = sha1.convert(utf8.encode(localRootUri.toString())).toString();
  return project.resolve(
    path.join(
      '.dart_tool',
      'llamadart',
      'native_bundles_v2',
      'local',
      digest,
      nativeTag,
      bundle,
    ),
  );
}
