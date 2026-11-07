@TestOn('vm')
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../../hook/build.dart' as build_hook;

void main() {
  final nativeTag = _readHookConst('_llamaCppTag');
  final litertVersion = _readHookConst('_litertLmVersion');
  final nativeBundleDir = Directory(
    '.dart_tool/llamadart/native_bundles/$nativeTag/linux-arm64/extracted',
  );
  final litertBundleDir = Directory(
    '.dart_tool/llamadart/litert_lm/$litertVersion/linux/arm64',
  );
  final macosArm64NativeBundleDir = Directory(
    '.dart_tool/llamadart/native_bundles/$nativeTag/macos-arm64/extracted',
  );
  final macosArm64LitertBundleDir = Directory(
    '.dart_tool/llamadart/litert_lm/$litertVersion/macos/arm64',
  );
  final macosX64NativeBundleDir = Directory(
    '.dart_tool/llamadart/native_bundles/$nativeTag/macos-x86_64/extracted',
  );
  final macosX64LitertBundleDir = Directory(
    '.dart_tool/llamadart/litert_lm/$litertVersion/macos/x64',
  );
  final iosDeviceNativeBundleDir = Directory(
    '.dart_tool/llamadart/native_bundles/$nativeTag/ios-arm64/extracted',
  );
  final iosArm64SimNativeBundleDir = Directory(
    '.dart_tool/llamadart/native_bundles/$nativeTag/ios-arm64-sim/extracted',
  );
  final iosX64SimNativeBundleDir = Directory(
    '.dart_tool/llamadart/native_bundles/$nativeTag/ios-x86_64-sim/extracted',
  );
  final iosDeviceLitertBundleDir = Directory(
    '.dart_tool/llamadart/litert_lm/$litertVersion/ios/arm64',
  );
  final iosArm64SimLitertBundleDir = Directory(
    '.dart_tool/llamadart/litert_lm/$litertVersion/ios/arm64-sim',
  );
  final backupPairs = [
    (nativeBundleDir, Directory('${nativeBundleDir.path}.__litert_test')),
    (litertBundleDir, Directory('${litertBundleDir.path}.__litert_test')),
    (
      macosArm64NativeBundleDir,
      Directory('${macosArm64NativeBundleDir.path}.__litert_test'),
    ),
    (
      macosArm64LitertBundleDir,
      Directory('${macosArm64LitertBundleDir.path}.__litert_test'),
    ),
    (
      macosX64NativeBundleDir,
      Directory('${macosX64NativeBundleDir.path}.__litert_test'),
    ),
    (
      macosX64LitertBundleDir,
      Directory('${macosX64LitertBundleDir.path}.__litert_test'),
    ),
    (
      iosDeviceNativeBundleDir,
      Directory('${iosDeviceNativeBundleDir.path}.__litert_test'),
    ),
    (
      iosArm64SimNativeBundleDir,
      Directory('${iosArm64SimNativeBundleDir.path}.__litert_test'),
    ),
    (
      iosX64SimNativeBundleDir,
      Directory('${iosX64SimNativeBundleDir.path}.__litert_test'),
    ),
    (
      iosDeviceLitertBundleDir,
      Directory('${iosDeviceLitertBundleDir.path}.__litert_test'),
    ),
    (
      iosArm64SimLitertBundleDir,
      Directory('${iosArm64SimLitertBundleDir.path}.__litert_test'),
    ),
  ];

  setUpAll(() async {
    for (final (directory, backup) in backupPairs) {
      await _backupDirectory(directory, backup);
    }
  });

  setUp(() async {
    await _writeBundleLibraries(nativeBundleDir, const [
      'libllamadart.so',
      'libllama.so',
      'libggml.so',
      'libggml-base.so',
      'libggml-cpu.so',
    ]);
    await _writeBundleLibraries(litertBundleDir, _linuxLiteRtLibraries);
    await _writeBundleLibraries(macosArm64NativeBundleDir, const [
      'libllamadart.dylib',
    ]);
    await _writeBundleLibraries(
      macosArm64LitertBundleDir,
      _macosArm64LiteRtLibraries,
    );
    await _writeBundleLibraries(macosX64NativeBundleDir, const [
      'libllamadart.dylib',
    ]);
    await _writeBundleLibraries(
      macosX64LitertBundleDir,
      _macosX64LiteRtLibraries,
    );
    for (final directory in [
      iosDeviceNativeBundleDir,
      iosArm64SimNativeBundleDir,
      iosX64SimNativeBundleDir,
    ]) {
      await _writeBundleLibraries(directory, const ['libllamadart.dylib']);
    }
    for (final directory in [
      iosDeviceLitertBundleDir,
      iosArm64SimLitertBundleDir,
    ]) {
      await _writeBundleLibraries(directory, [
        ..._iosLiteRtLibraries,
        'libLegacySplitRuntime.dylib',
      ]);
    }
  });

  tearDownAll(() async {
    for (final (directory, backup) in backupPairs.reversed) {
      await _restoreDirectory(directory, backup);
    }
  });

  test('LiteRT-LM bundle specs require platform runtime companions', () {
    final source = File('hook/build.dart').readAsStringSync();

    _expectSpecLibraries(source, 'android-arm64', _androidLiteRtLibraries);
    _expectSpecLibraries(source, 'android-x64', _androidLiteRtLibraries);
    _expectSpecLibraries(source, 'ios-arm64', _iosLiteRtLibraries);
    _expectSpecLibraries(source, 'ios-arm64-sim', _iosLiteRtLibraries);
    _expectSpecLibraries(source, 'macos-arm64', _macosArm64LiteRtLibraries);
    _expectSpecLibraries(source, 'macos-x64', _macosX64LiteRtLibraries);
    _expectSpecLibraries(source, 'linux-arm64', _linuxLiteRtLibraries);
    _expectSpecLibraries(source, 'linux-x64', _linuxLiteRtLibraries);
    _expectSpecLibraries(source, 'windows-x64', _windowsLiteRtLibraries);
  });

  test('LiteRT-LM bundle specs pin archive checksums', () {
    final source = File('hook/build.dart').readAsStringSync();

    for (final bundleKey in const [
      'android-arm64',
      'android-x64',
      'ios-arm64',
      'ios-arm64-sim',
      'macos-arm64',
      'macos-x64',
      'linux-arm64',
      'linux-x64',
      'windows-x64',
    ]) {
      _expectSpecChecksum(source, bundleKey);
    }
  });

  test(
    'build hook emits Linux arm64 LiteRT-LM runtime companions when requested',
    () async {
      await testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.linux,
        targetArchitecture: Architecture.arm64,
        userDefines: _allRuntimeUserDefines(),
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
          for (final library in _linuxLiteRtLibraries) {
            expect(emittedNames, contains(library));
          }
          for (final assetName in _linuxLiteRtAssetNames) {
            expect(codeAssetIds, contains('package:llamadart/$assetName'));
          }
        },
      );
    },
  );

  test(
    'build hook keeps macOS LiteRT-LM libraries in the cache when requested',
    () async {
      for (final (architecture, expectedLibraries) in [
        (Architecture.arm64, _macosArm64LiteRtLibraries),
        (Architecture.x64, _macosX64LiteRtLibraries),
      ]) {
        await testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.macOS,
          targetArchitecture: architecture,
          userDefines: _allRuntimeUserDefines(),
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
            expect(
              codeAssetIds.where((id) => id.contains('litert_lm')),
              isEmpty,
            );
            for (final library in expectedLibraries) {
              expect(emittedNames, isNot(contains(library)));
            }
          },
        );
      }
    },
  );

  test('build hook can emit LiteRT-LM runtime without llama.cpp', () async {
    await testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.linux,
      targetArchitecture: Architecture.arm64,
      userDefines: _liteRtLmOnlyUserDefines(),
      check: (input, output) {
        final codeAssets = output.assets.encodedAssets
            .where((asset) => asset.isCodeAsset)
            .map((asset) => asset.asCodeAsset)
            .toList(growable: false);

        final codeAssetIds = codeAssets.map((asset) => asset.id).toSet();
        final emittedNames = codeAssets
            .map((asset) => path.basename(asset.file!.toFilePath()))
            .toSet();

        expect(codeAssetIds, isNot(contains('package:llamadart/llamadart')));
        expect(emittedNames, isNot(contains('libllamadart.so')));
        for (final library in _linuxLiteRtLibraries) {
          expect(emittedNames, contains(library));
        }
        for (final assetName in _linuxLiteRtAssetNames) {
          expect(codeAssetIds, contains('package:llamadart/$assetName'));
        }
      },
    );
  });

  test(
    'build hook bundles Apple native assets without companion packages',
    () async {
      await testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        targetIOSSdk: IOSSdk.iPhoneOS,
        userDefines: _allRuntimeUserDefines(),
        check: (input, output) {
          final codeAssets = output.assets.encodedAssets
              .where((asset) => asset.isCodeAsset)
              .map((asset) => asset.asCodeAsset)
              .toList(growable: false);

          final codeAssetIds = codeAssets.map((asset) => asset.id).toSet();
          expect(codeAssetIds, contains('package:llamadart/llamadart'));
          for (final assetName in _iosLiteRtAssetNames) {
            expect(codeAssetIds, contains('package:llamadart/$assetName'));
          }
          expect(
            codeAssetIds.where((id) => id.contains('/litert_lm_')).toSet(),
            {
              for (final assetName in _iosLiteRtAssetNames)
                'package:llamadart/$assetName',
            },
          );
          expect(
            codeAssets.every(
              (asset) => asset.linkMode is DynamicLoadingBundled,
            ),
            isTrue,
          );

          final outputDir = input.outputDirectory.toFilePath();
          expect(
            Directory(path.join(outputDir, 'llamadart_bin')).existsSync(),
            isTrue,
          );
        },
      );
    },
  );

  test('build hook ignores native source overrides for Apple SPM', () async {
    final userDefines = await _flutterAppleUserDefines(
      dependencies: const ['llamadart_llama_cpp_flutter'],
      defines: {
        'llamadart_native_runtimes': ['litert_lm'],
        'llamadart_native_tag': '../ignored-by-spm',
        'llamadart_native_repository': '../ignored-by-spm',
        'llamadart_native_path': './missing-native-bundles',
        'llamadart_native_backends': {
          'platforms': {
            'ios-arm64': ['cuda'],
          },
        },
      },
    );

    await testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.iOS,
      targetArchitecture: Architecture.arm64,
      targetIOSSdk: IOSSdk.iPhoneOS,
      userDefines: userDefines,
      check: (input, output) {
        final codeAssets = output.assets.encodedAssets
            .where((asset) => asset.isCodeAsset)
            .map((asset) => asset.asCodeAsset)
            .toList(growable: false);

        expect(codeAssets, hasLength(1));
        final codeAsset = codeAssets.single;
        expect(codeAsset.id, 'package:llamadart/llamadart');
        expect(codeAsset.file, isNull);
        expect(codeAsset.linkMode, isA<LookupInProcess>());

        final outputDir = input.outputDirectory.toFilePath();
        expect(
          Directory(path.join(outputDir, 'llamadart_bin')).existsSync(),
          isFalse,
        );
      },
    );
  });

  test(
    'build hook emits no bundled Apple assets for Flutter iOS LiteRT-LM SPM mode',
    () async {
      await testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        targetIOSSdk: IOSSdk.iPhoneOS,
        userDefines: await _flutterLiteRtLmOnlyUserDefines(),
        check: (input, output) {
          final codeAssets = output.assets.encodedAssets
              .where((asset) => asset.isCodeAsset)
              .map((asset) => asset.asCodeAsset)
              .toList(growable: false);

          expect(codeAssets, isEmpty);
          final outputDir = input.outputDirectory.toFilePath();
          expect(
            Directory(path.join(outputDir, 'llamadart_bin')).existsSync(),
            isFalse,
          );
        },
      );
    },
  );

  test(
    'build hook keeps Flutter macOS LiteRT-LM on hook-managed assets',
    () async {
      await testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.macOS,
        targetArchitecture: Architecture.arm64,
        userDefines: await _flutterLiteRtLmOnlyUserDefines(),
        check: (input, output) {
          final codeAssets = output.assets.encodedAssets
              .where((asset) => asset.isCodeAsset)
              .map((asset) => asset.asCodeAsset)
              .toList(growable: false);

          expect(codeAssets, isEmpty);
          final outputDir = input.outputDirectory.toFilePath();
          expect(
            Directory(path.join(outputDir, 'llamadart_bin')).existsSync(),
            isTrue,
          );
        },
      );
    },
  );

  test(
    'build hook mixes macOS llama.cpp SPM with LiteRT-LM hook assets',
    () async {
      await testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.macOS,
        targetArchitecture: Architecture.arm64,
        userDefines: await _flutterAppleUserDefines(
          dependencies: const [
            'llamadart_llama_cpp_flutter',
            'llamadart_litert_lm_flutter',
          ],
        ),
        check: (input, output) {
          final codeAssets = output.assets.encodedAssets
              .where((asset) => asset.isCodeAsset)
              .map((asset) => asset.asCodeAsset)
              .toList(growable: false);

          expect(codeAssets, hasLength(1));
          final codeAsset = codeAssets.single;
          expect(codeAsset.id, 'package:llamadart/llamadart');
          expect(codeAsset.file, isNull);
          expect(codeAsset.linkMode, isA<LookupInProcess>());

          final outputDir = input.outputDirectory.toFilePath();
          expect(
            Directory(path.join(outputDir, 'llamadart_bin')).existsSync(),
            isTrue,
          );
        },
      );
    },
  );

  test(
    'build hook uses SPM process lookup for Flutter iOS llama.cpp companion',
    () async {
      await testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        targetIOSSdk: IOSSdk.iPhoneOS,
        userDefines: await _flutterAppleUserDefines(
          dependencies: const ['llamadart_llama_cpp_flutter'],
          defines: {
            'llamadart_native_runtimes': ['litert_lm'],
          },
        ),
        check: (_, output) {
          final codeAssets = output.assets.encodedAssets
              .where((asset) => asset.isCodeAsset)
              .map((asset) => asset.asCodeAsset)
              .toList(growable: false);

          expect(codeAssets, hasLength(1));
          final codeAsset = codeAssets.single;
          expect(codeAsset.id, 'package:llamadart/llamadart');
          expect(codeAsset.file, isNull);
          expect(codeAsset.linkMode, isA<LookupInProcess>());
        },
      );
    },
  );

  test(
    'build hook bundles iOS x64 simulator llama.cpp without companion packages',
    () async {
      await testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.x64,
        targetIOSSdk: IOSSdk.iPhoneSimulator,
        userDefines: _llamaCppOnlyUserDefines(),
        check: (_, output) {
          final codeAssets = output.assets.encodedAssets
              .where((asset) => asset.isCodeAsset)
              .map((asset) => asset.asCodeAsset)
              .toList(growable: false);

          expect(codeAssets.map((asset) => asset.id), [
            'package:llamadart/llamadart',
          ]);
          expect(codeAssets.single.linkMode, isA<DynamicLoadingBundled>());
        },
      );
    },
  );

  test('build hook drops unavailable LiteRT-LM from all selections', () async {
    for (final userDefines in [
      _allRuntimeUserDefines(),
      _emptyRuntimeUserDefines(),
    ]) {
      await testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.x64,
        targetIOSSdk: IOSSdk.iPhoneSimulator,
        userDefines: userDefines,
        check: (_, output) {
          final codeAssets = output.assets.encodedAssets
              .where((asset) => asset.isCodeAsset)
              .map((asset) => asset.asCodeAsset)
              .toList(growable: false);

          expect(codeAssets.map((asset) => asset.id), [
            'package:llamadart/llamadart',
          ]);
          expect(codeAssets.single.linkMode, isA<DynamicLoadingBundled>());
        },
      );
    }
  });

  test(
    'build hook ignores nested pubspec keys when detecting companions',
    () async {
      await testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        targetIOSSdk: IOSSdk.iPhoneOS,
        userDefines: await _flutterAppleUserDefines(
          dependencies: const [],
          dependenciesYaml: '''
  not_a_companion:
    llamadart_llama_cpp_flutter: true
''',
        ),
        check: (_, output) {
          final codeAssets = output.assets.encodedAssets
              .where((asset) => asset.isCodeAsset)
              .map((asset) => asset.asCodeAsset)
              .toList(growable: false);

          final codeAssetIds = codeAssets.map((asset) => asset.id).toSet();
          expect(codeAssetIds, contains('package:llamadart/llamadart'));
          for (final assetName in _iosLiteRtAssetNames) {
            expect(codeAssetIds, contains('package:llamadart/$assetName'));
          }
          expect(
            codeAssets.every(
              (asset) => asset.linkMode is DynamicLoadingBundled,
            ),
            isTrue,
          );
        },
      );
    },
  );

  test(
    'build hook lets runtime config win outside Flutter Apple apps',
    () async {
      await testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        targetIOSSdk: IOSSdk.iPhoneOS,
        userDefines: await _nonFlutterConsumerUserDefines(
          dependencies: const ['llamadart_litert_lm_flutter'],
          defines: {
            'llamadart_native_runtimes': ['llama_cpp'],
          },
        ),
        check: (_, output) {
          final codeAssets = output.assets.encodedAssets
              .where((asset) => asset.isCodeAsset)
              .map((asset) => asset.asCodeAsset)
              .toList(growable: false);

          expect(codeAssets.map((asset) => asset.id), [
            'package:llamadart/llamadart',
          ]);
          expect(codeAssets.single.linkMode, isA<DynamicLoadingBundled>());
        },
      );
    },
  );

  test(
    'build hook fails when explicitly requested LiteRT-LM is unavailable',
    () async {
      await expectLater(
        testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.iOS,
          targetArchitecture: Architecture.x64,
          targetIOSSdk: IOSSdk.iPhoneSimulator,
          userDefines: _liteRtLmOnlyUserDefines(),
          check: (_, _) {},
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('LiteRT-LM runtime is not available for ios-x86_64-sim'),
          ),
        ),
      );
    },
  );

  test(
    'build hook fails when Flutter companion selects unavailable LiteRT-LM',
    () async {
      await expectLater(
        testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.iOS,
          targetArchitecture: Architecture.x64,
          targetIOSSdk: IOSSdk.iPhoneSimulator,
          userDefines: await _flutterAppleUserDefines(
            dependencies: const ['llamadart_litert_lm_flutter'],
          ),
          check: (_, _) {},
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('LiteRT-LM runtime is not available for ios-x86_64-sim'),
          ),
        ),
      );
    },
  );
}

String _readHookConst(String name) {
  final source = File('hook/build.dart').readAsStringSync();
  final match = RegExp("const $name = '([^']+)';").firstMatch(source);
  if (match == null) {
    throw StateError('Could not locate $name in hook/build.dart');
  }
  return match.group(1)!;
}

PackageUserDefines _liteRtLmOnlyUserDefines() => PackageUserDefines(
  workspacePubspec: PackageUserDefinesSource(
    defines: {
      'llamadart_native_runtimes': ['litert_lm'],
    },
    basePath: Directory.current.uri,
  ),
);

PackageUserDefines _allRuntimeUserDefines() => PackageUserDefines(
  workspacePubspec: PackageUserDefinesSource(
    defines: {
      'llamadart_native_runtimes': ['all'],
    },
    basePath: Directory.current.uri,
  ),
);

PackageUserDefines _emptyRuntimeUserDefines() => PackageUserDefines(
  workspacePubspec: PackageUserDefinesSource(
    defines: {'llamadart_native_runtimes': <String>[]},
    basePath: Directory.current.uri,
  ),
);

Future<PackageUserDefines> _flutterLiteRtLmOnlyUserDefines() {
  return _flutterAppleUserDefines(
    dependencies: const ['llamadart_litert_lm_flutter'],
    defines: {
      'llamadart_native_runtimes': ['llama_cpp'],
    },
  );
}

Future<PackageUserDefines> _nonFlutterConsumerUserDefines({
  required List<String> dependencies,
  Map<String, Object?> defines = const {},
}) async {
  final dir = await Directory.systemTemp.createTemp('llamadart_dart_consumer_');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  final pubspec = File(path.join(dir.path, 'pubspec.yaml'));
  await pubspec.writeAsString('''
name: llamadart_dart_consumer
publish_to: none

environment:
  sdk: ^3.10.7

dependencies:
${dependencies.map((dependency) => '  $dependency: ^0.8.0').join('\n')}
''');

  return PackageUserDefines(
    workspacePubspec: PackageUserDefinesSource(
      defines: defines,
      basePath: pubspec.uri,
    ),
  );
}

Future<PackageUserDefines> _flutterAppleUserDefines({
  required List<String> dependencies,
  Map<String, Object?> defines = const {},
  String dependenciesYaml = '',
}) async {
  final dir = await Directory.systemTemp.createTemp(
    'llamadart_apple_consumer_',
  );
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  final pubspec = File(path.join(dir.path, 'pubspec.yaml'));
  await pubspec.writeAsString('''
name: llamadart_apple_consumer
publish_to: none

environment:
  sdk: ^3.10.7
  flutter: ^3.38.0

dependencies:
  flutter:
    sdk: flutter
${dependenciesYaml.trimRight()}
${dependencies.map((dependency) => '  $dependency: ^0.8.0').join('\n')}
''');

  return PackageUserDefines(
    workspacePubspec: PackageUserDefinesSource(
      defines: defines,
      basePath: pubspec.uri,
    ),
  );
}

PackageUserDefines _llamaCppOnlyUserDefines() => PackageUserDefines(
  workspacePubspec: PackageUserDefinesSource(
    defines: {
      'llamadart_native_runtimes': ['llama_cpp'],
    },
    basePath: Directory.current.uri,
  ),
);

void _expectSpecLibraries(
  String source,
  String bundleKey,
  List<String> expectedLibraries,
) {
  final escapedKey = RegExp.escape(bundleKey);
  final match = RegExp(
    "_LiteRtLmBundleSpec\\(\\s*'$escapedKey',[\\s\\S]*?"
    'requiredLibraries:\\s*\\{([\\s\\S]*?)\\},',
  ).firstMatch(source);
  if (match == null) {
    throw StateError('Could not locate LiteRT-LM libraries for $bundleKey');
  }
  final spec = match.group(1)!;
  for (final library in expectedLibraries) {
    expect(spec, contains("'$library'"), reason: bundleKey);
  }
}

void _expectSpecChecksum(String source, String bundleKey) {
  final escapedKey = RegExp.escape(bundleKey);
  final match = RegExp(
    "_LiteRtLmBundleSpec\\(\\s*'$escapedKey',[\\s\\S]*?"
    "sha256:\\s*'([0-9a-f]{64})',",
  ).firstMatch(source);
  expect(match, isNotNull, reason: bundleKey);
}

const List<String> _androidLiteRtLibraries = [
  'libGemmaModelConstraintProvider.so',
  'libLiteRtGpuAccelerator.so',
  'libLiteRtLm.so',
  'libLiteRtOpenClAccelerator.so',
  'libLiteRtTopKOpenClSampler.so',
  'libLiteRtTopKWebGpuSampler.so',
  'libLiteRtWebGpuAccelerator.so',
  'libwebgpu_dawn.so',
];

const List<String> _iosLiteRtLibraries = ['LiteRtLm', 'CLiteRTLM'];

const List<String> _iosLiteRtAssetNames = [
  'litert_lm_LiteRtLm',
  'litert_lm_CLiteRTLM',
];

const List<String> _macosArm64LiteRtLibraries = [
  'libLiteRtLm.dylib',
  'libCLiteRTLM_mac.dylib',
];

const List<String> _macosX64LiteRtLibraries = [
  'libLiteRtLm.dylib',
  'libCLiteRTLM_mac.dylib',
];

const List<String> _linuxLiteRtLibraries = [
  'libGemmaModelConstraintProvider.so',
  'libLiteRt.so',
  'libLiteRtLm.so',
  'libwebgpu_dawn.so',
  'libLiteRtTopKWebGpuSampler.so',
  'libLiteRtWebGpuAccelerator.so',
];

const List<String> _linuxLiteRtAssetNames = [
  'litert_lm_GemmaModelConstraintProvider',
  'litert_lm_LiteRt',
  'litert_lm_LiteRtLm',
  'litert_lm_webgpu_dawn',
  'litert_lm_LiteRtTopKWebGpuSampler',
  'litert_lm_LiteRtWebGpuAccelerator',
];

const List<String> _windowsLiteRtLibraries = [
  'LiteRtLm.dll',
  'libGemmaModelConstraintProvider.dll',
  'libLiteRt.dll',
  'libwebgpu_dawn.dll',
  'libLiteRtTopKWebGpuSampler.dll',
  'libLiteRtWebGpuAccelerator.dll',
];

Future<void> _backupDirectory(Directory directory, Directory backup) async {
  if (backup.existsSync()) {
    await backup.delete(recursive: true);
  }
  if (directory.existsSync()) {
    await directory.rename(backup.path);
  }
}

Future<void> _restoreDirectory(Directory directory, Directory backup) async {
  if (directory.existsSync()) {
    await directory.delete(recursive: true);
  }
  if (backup.existsSync()) {
    await backup.rename(directory.path);
  }
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
