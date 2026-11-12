@TestOn('vm')
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../../hook/build.dart' as build_hook;
import '../../support/hook_project_root.dart';
import '../../support/hooks_runner_layout.dart';
import '../../support/native_bundle_cache.dart';

void main() {
  final nativeTag = _readHookNativeTag();
  final litertVersion = _readHookLiteRtLmVersion();
  final project = HookProjectRoot.create();
  final bundleDir = Directory(
    project.resolve(
      '.dart_tool/llamadart/native_bundles_v2/$nativeTag/android-arm64/extracted',
    ),
  );
  final litertBundleDir = Directory(
    project.resolve(
      '.dart_tool/llamadart/litert_lm/$litertVersion/android/arm64',
    ),
  );

  setUp(() async {
    if (bundleDir.existsSync()) {
      await bundleDir.delete(recursive: true);
    }
    await _writeBundleLibraries(bundleDir, _androidArm64Libraries);
    await markExtractedBundle(bundleDir);
    await _writeBundleLibraries(litertBundleDir, _androidLiteRtLibraries);
  });

  tearDownAll(project.delete);

  test('build hook defaults Android arm64 cpu profile to full', () async {
    final userDefines = PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: {
          'llamadart_native_backends': {
            'platforms': {
              'android-arm64': {
                'backends': ['vulkan'],
              },
            },
          },
        },
        basePath: Directory.current.uri,
      ),
    );

    await project.testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.android,
      targetArchitecture: Architecture.arm64,
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

        expect(emittedNames, contains('libllamadart.so'));
        expect(emittedNames, contains('libllama.so'));
        expect(emittedNames, contains('libllama-common.so'));
        expect(emittedNames, contains('libggml.so'));
        expect(emittedNames, contains('libggml-base.so'));
        expect(emittedNames, contains('libggml-vulkan.so'));

        for (final variant in _androidCpuVariantLibraries) {
          expect(emittedNames, contains(variant));
        }
        for (final library in _androidLiteRtLibraries) {
          expect(emittedNames, contains(library));
        }
        for (final assetName in _androidLiteRtAssetNames) {
          expect(codeAssetIds, contains('package:llamadart/$assetName'));
        }
      },
    );
  });

  test('build hook applies compact Android arm64 cpu profile', () async {
    final userDefines = PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: {
          'llamadart_native_backends': {
            'platforms': {
              'android-arm64': {
                'backends': ['vulkan'],
                'cpu_profile': 'compact',
              },
            },
          },
        },
        basePath: Directory.current.uri,
      ),
    );

    await project.testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.android,
      targetArchitecture: Architecture.arm64,
      userDefines: userDefines,
      check: (input, output) {
        final codeAssets = output.assets.encodedAssets
            .where((asset) => asset.isCodeAsset)
            .map((asset) => asset.asCodeAsset)
            .toList(growable: false);

        final emittedNames = codeAssets
            .map((asset) => path.basename(asset.file!.toFilePath()))
            .toSet();

        expect(emittedNames, contains('libggml-cpu-android_armv8.0_1.so'));
        for (final variant in _androidCpuVariantLibraries) {
          if (variant == 'libggml-cpu-android_armv8.0_1.so') {
            continue;
          }
          expect(emittedNames, isNot(contains(variant)));
        }
      },
    );
  });

  test('build hook uses cpu_variants override for Android arm64', () async {
    final userDefines = PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: {
          'llamadart_native_backends': {
            'platforms': {
              'android-arm64': {
                'backends': ['vulkan'],
                'cpu_profile': 'compact',
                'cpu_variants': ['android_armv8.6_1', 'armv9_2_2'],
              },
            },
          },
        },
        basePath: Directory.current.uri,
      ),
    );

    await project.testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.android,
      targetArchitecture: Architecture.arm64,
      userDefines: userDefines,
      check: (input, output) {
        final codeAssets = output.assets.encodedAssets
            .where((asset) => asset.isCodeAsset)
            .map((asset) => asset.asCodeAsset)
            .toList(growable: false);

        final emittedNames = codeAssets
            .map((asset) => path.basename(asset.file!.toFilePath()))
            .toSet();

        expect(emittedNames, contains('libggml-cpu-android_armv8.6_1.so'));
        expect(emittedNames, contains('libggml-cpu-android_armv9.2_2.so'));
        expect(
          emittedNames,
          isNot(contains('libggml-cpu-android_armv8.0_1.so')),
        );
        expect(
          emittedNames,
          isNot(contains('libggml-cpu-android_armv9.0_1.so')),
        );
      },
    );
  });

  test(
    'only LiteRT-LM assets follow the resolved graph',
    () => expectOnlyLiteRtLmFollowsResolvedGraph(
      hookMain: build_hook.main,
      targetOS: OS.android,
      targetArchitecture: Architecture.arm64,
      liteRtLmLibraries: _androidLiteRtLibraries,
      project: project,
    ),
  );
}

const List<String> _androidCpuVariantLibraries = [
  'libggml-cpu-android_armv8.0_1.so',
  'libggml-cpu-android_armv8.2_1.so',
  'libggml-cpu-android_armv8.2_2.so',
  'libggml-cpu-android_armv8.6_1.so',
  'libggml-cpu-android_armv9.0_1.so',
  'libggml-cpu-android_armv9.2_1.so',
  'libggml-cpu-android_armv9.2_2.so',
];

const List<String> _androidArm64Libraries = [
  'libllamadart.so',
  'libllama.so',
  'libllama-common.so',
  'libggml.so',
  'libggml-base.so',
  'libggml-vulkan.so',
  ..._androidCpuVariantLibraries,
];

const List<String> _androidLiteRtLibraries = [
  'libGemmaModelConstraintProvider.so',
  'libLiteRtGpuAccelerator.so',
  'libLiteRtLm.so',
  'libLiteRtOpenClAccelerator.so',
  'libLiteRtWebGpuAccelerator.so',
  'libwebgpu_dawn.so',
];

const List<String> _androidLiteRtAssetNames = [
  'litert_lm_GemmaModelConstraintProvider',
  'litert_lm_LiteRtGpuAccelerator',
  'litert_lm_LiteRtLm',
  'litert_lm_LiteRtOpenClAccelerator',
  'litert_lm_LiteRtWebGpuAccelerator',
  'litert_lm_webgpu_dawn',
];

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
