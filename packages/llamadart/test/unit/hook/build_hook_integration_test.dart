@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../../hook/build.dart' as build_hook;

void main() {
  final nativeTag = _readHookNativeTag();
  final litertVersion = _readHookLiteRtLmVersion();
  final cacheRelativeDir =
      '.dart_tool/llamadart/native_bundles/$nativeTag/windows-x64';
  final bundleRelativePath = '$cacheRelativeDir/extracted';
  final bundleDir = Directory(bundleRelativePath);
  final backupDir = Directory('$bundleRelativePath.__hook_test_backup');
  final litertBundleDir = Directory(
    '.dart_tool/llamadart/litert_lm/$litertVersion/windows/x64',
  );
  final litertBackupDir = Directory(
    '${litertBundleDir.path}.__hook_test_backup',
  );
  final archivePath =
      '$cacheRelativeDir/llamadart-native-windows-x64-$nativeTag.tar.gz';
  final archiveFile = File(archivePath);

  setUpAll(() async {
    if (backupDir.existsSync()) {
      await backupDir.delete(recursive: true);
    }

    if (bundleDir.existsSync()) {
      await bundleDir.rename(backupDir.path);
    }
    if (litertBackupDir.existsSync()) {
      await litertBackupDir.delete(recursive: true);
    }
    if (litertBundleDir.existsSync()) {
      await litertBundleDir.rename(litertBackupDir.path);
    }
  });

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
    await _writeBundleLibraries(litertBundleDir, _windowsLiteRtLibraries);

    if (archiveFile.existsSync()) {
      await archiveFile.delete();
    }
  });

  tearDownAll(() async {
    if (archiveFile.existsSync()) {
      await archiveFile.delete();
    }
    if (bundleDir.existsSync()) {
      await bundleDir.delete(recursive: true);
    }
    if (backupDir.existsSync()) {
      await backupDir.rename(bundleDir.path);
    }
    if (litertBundleDir.existsSync()) {
      await litertBundleDir.delete(recursive: true);
    }
    if (litertBackupDir.existsSync()) {
      await litertBackupDir.rename(litertBundleDir.path);
    }
  });

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

      await testCodeBuildHook(
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
          'llamadart_native_runtimes': ['all'],
          'llamadart_native_backends': {
            'platforms': {
              'windows-x64': ['vulkan'],
            },
          },
        },
        basePath: Directory.current.uri,
      ),
    );

    await testCodeBuildHook(
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

    await testCodeBuildHook(
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

    await testCodeBuildHook(
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

  test('build hook refreshes stale windows cache from local archive', () async {
    await _writeBundleLibraries(bundleDir, const [
      'llamadart-windows-x64.dll',
      'llama-windows-x64.dll',
      'ggml-windows-x64.dll',
      'ggml-base-windows-x64.dll',
      'ggml-cpu-windows-x64.dll',
      'ggml-cuda-windows-x64.dll',
    ]);

    await _writeBundleArchive(
      archiveFile: archiveFile,
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

    final userDefines = PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: {
          'llamadart_native_backends': {
            'platforms': {
              'windows-x64': ['cuda'],
            },
          },
        },
        basePath: Directory.current.uri,
      ),
    );

    await testCodeBuildHook(
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
    );
  });

  test('build hook uses pubspec native tag override', () async {
    const overrideTag = 'b0000-hook-test';
    final overrideCacheDir = Directory(
      '.dart_tool/llamadart/native_bundles/$overrideTag/windows-x64',
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

      await testCodeBuildHook(
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
          expect(emittedNames, isNot(contains('ggml-vulkan-windows-x64.dll')));
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
  });

  test('build hook uses custom GitHub repository cache namespace', () async {
    const overrideTag = 'b0000-repo-test';
    const customRepository = 'example/native-fork';
    final repoCacheRoot = Directory(
      '.dart_tool/llamadart/native_bundles/github/example/native-fork',
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

      await testCodeBuildHook(
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
    final localRoot = Directory(localRootPath);
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
          basePath: Directory.current.uri,
        ),
      );

      await testCodeBuildHook(
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
    const overrideTag = 'b0000-local-archive';
    const localRootPath = '.dart_tool/llamadart_hook_test_local_archive';
    final localRoot = Directory(localRootPath);
    final archiveFile = File(
      path.join(
        localRoot.path,
        'llamadart-native-windows-x64-$overrideTag.tar.gz',
      ),
    );
    final localCacheRoot = Directory(
      _localPathCacheRoot(
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
          basePath: Directory.current.uri,
        ),
      );

      await testCodeBuildHook(
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

  test('build hook rejects path-unsafe native tag override', () async {
    final userDefines = PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: const {'llamadart_native_tag': '../bad'},
        basePath: Directory.current.uri,
      ),
    );

    await expectLater(
      testCodeBuildHook(
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
          contains('path-safe release tag'),
        ),
      ),
    );
  });

  test('build hook rejects invalid native repository override', () async {
    final userDefines = PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: const {'llamadart_native_repository': '../bad'},
        basePath: Directory.current.uri,
      ),
    );

    await expectLater(
      testCodeBuildHook(
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
  final source = File('hook/build.dart').readAsStringSync();
  final match = RegExp(r"const _llamaCppTag = '([^']+)';").firstMatch(source);
  if (match == null) {
    throw StateError('Could not locate _llamaCppTag in hook/build.dart');
  }
  return match.group(1)!;
}

String _readHookLiteRtLmVersion() {
  final source = File('hook/build.dart').readAsStringSync();
  final match = RegExp(
    r"const _litertLmVersion = '([^']+)';",
  ).firstMatch(source);
  if (match == null) {
    throw StateError('Could not locate _litertLmVersion in hook/build.dart');
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
  'libGemmaModelConstraintProvider.dll',
  'libLiteRt.dll',
  'libwebgpu_dawn.dll',
  'libLiteRtTopKWebGpuSampler.dll',
  'libLiteRtWebGpuAccelerator.dll',
];

const List<String> _windowsLiteRtAssetNames = [
  'litert_lm_LiteRtLm',
  'litert_lm_GemmaModelConstraintProvider',
  'litert_lm_LiteRt',
  'litert_lm_webgpu_dawn',
  'litert_lm_LiteRtTopKWebGpuSampler',
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
  required String localRootPath,
  required String nativeTag,
  required String bundle,
}) {
  final localRootUri = Directory.current.uri.resolve(localRootPath);
  final digest = sha1.convert(utf8.encode(localRootUri.toString())).toString();
  return path.join(
    '.dart_tool',
    'llamadart',
    'native_bundles',
    'local',
    digest,
    nativeTag,
    bundle,
  );
}
