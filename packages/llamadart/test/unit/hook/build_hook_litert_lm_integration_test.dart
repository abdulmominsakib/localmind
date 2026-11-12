@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:llamadart/src/hook/apple_companion_constraint.dart';
import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../../hook/build.dart' as build_hook;
import '../../support/hook_core_version.dart';
import '../../support/hook_project_root.dart';
import '../../support/native_bundle_cache.dart';

void main() {
  final nativeTag = _readPinnedConst('llamaCppTag');
  final litertVersion = _readPinnedConst('liteRtLmVersion');
  final project = HookProjectRoot.create();
  final nativeBundleDir = Directory(
    project.resolve(
      '.dart_tool/llamadart/native_bundles_v2/$nativeTag/linux-arm64/extracted',
    ),
  );
  final litertBundleDir = Directory(
    project.resolve(
      '.dart_tool/llamadart/litert_lm/$litertVersion/linux/arm64',
    ),
  );
  final macosArm64NativeBundleDir = Directory(
    project.resolve(
      '.dart_tool/llamadart/native_bundles_v2/$nativeTag/macos-arm64/extracted',
    ),
  );
  final macosArm64LitertBundleDir = Directory(
    project.resolve(
      '.dart_tool/llamadart/litert_lm/$litertVersion/macos/arm64',
    ),
  );
  final macosX64NativeBundleDir = Directory(
    project.resolve(
      '.dart_tool/llamadart/native_bundles_v2/$nativeTag/macos-x86_64/extracted',
    ),
  );
  final iosDeviceNativeBundleDir = Directory(
    project.resolve(
      '.dart_tool/llamadart/native_bundles_v2/$nativeTag/ios-arm64/extracted',
    ),
  );
  final iosArm64SimNativeBundleDir = Directory(
    project.resolve(
      '.dart_tool/llamadart/native_bundles_v2/$nativeTag/ios-arm64-sim/extracted',
    ),
  );
  final iosX64SimNativeBundleDir = Directory(
    project.resolve(
      '.dart_tool/llamadart/native_bundles_v2/$nativeTag/ios-x86_64-sim/extracted',
    ),
  );
  final iosDeviceLitertBundleDir = Directory(
    project.resolve('.dart_tool/llamadart/litert_lm/$litertVersion/ios/arm64'),
  );
  final iosArm64SimLitertBundleDir = Directory(
    project.resolve(
      '.dart_tool/llamadart/litert_lm/$litertVersion/ios/arm64-sim',
    ),
  );
  setUp(() async {
    await _writeBundleLibraries(nativeBundleDir, const [
      'libllamadart.so',
      'libllama.so',
      'libggml.so',
      'libggml-base.so',
      'libggml-cpu.so',
    ]);
    // The owner archive also carries the prebuilt libLiteRt.so that the
    // Linux host links in instead of loading.
    await _writeBundleLibraries(litertBundleDir, [
      ..._linuxLiteRtLibraries,
      'libLiteRt.so',
    ]);
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
        'GemmaModelConstraintProvider',
      ]);
    }
    for (final directory in [
      nativeBundleDir,
      macosArm64NativeBundleDir,
      macosX64NativeBundleDir,
      iosDeviceNativeBundleDir,
      iosArm64SimNativeBundleDir,
      iosX64SimNativeBundleDir,
    ]) {
      await markExtractedBundle(directory);
    }
  });

  tearDownAll(project.delete);

  test('LiteRT-LM bundle specs require platform runtime companions', () {
    final source = File(
      'lib/src/hook/native_release_pins.dart',
    ).readAsStringSync();

    _expectSpecLibraries(source, 'android-arm64', _androidLiteRtLibraries);
    _expectSpecLibraries(source, 'android-x64', _androidLiteRtLibraries);
    _expectSpecLibraries(source, 'ios-arm64', _iosLiteRtLibraries);
    _expectSpecLibraries(source, 'ios-arm64-sim', _iosLiteRtLibraries);
    _expectSpecLibraries(source, 'macos-arm64', _macosArm64LiteRtLibraries);
    final liteRtLmSpecs = source.substring(
      source.indexOf('const liteRtLmBundleSpecs'),
      source.indexOf('];', source.indexOf('const liteRtLmBundleSpecs')),
    );
    expect(liteRtLmSpecs, contains("'macos-arm64'"));
    expect(liteRtLmSpecs, isNot(contains("'macos-x64'")));
    _expectSpecLibraries(source, 'linux-arm64', _linuxLiteRtLibraries);
    _expectSpecLibraries(source, 'linux-x64', _linuxLiteRtLibraries);
    _expectSpecLibraries(source, 'windows-x64', _windowsLiteRtLibraries);
  });

  test('LiteRT-LM bundle specs pin archive checksums', () {
    final source = File(
      'lib/src/hook/native_release_pins.dart',
    ).readAsStringSync();

    for (final bundleKey in const [
      'android-arm64',
      'android-x64',
      'ios-arm64',
      'ios-arm64-sim',
      'macos-arm64',
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
      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.linux,
        targetArchitecture: Architecture.arm64,
        userDefines: _bothRuntimeUserDefines(),
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
          expect(emittedNames, isNot(contains('libLiteRt.so')));
          expect(
            codeAssetIds,
            isNot(contains('package:llamadart/litert_lm_LiteRt')),
          );
        },
      );
    },
  );

  test(
    'build hook keeps macOS LiteRT-LM libraries in the cache when requested',
    () async {
      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.macOS,
        targetArchitecture: Architecture.arm64,
        userDefines: _bothRuntimeUserDefines(),
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
          expect(codeAssetIds.where((id) => id.contains('litert_lm')), isEmpty);
          for (final library in _macosArm64LiteRtLibraries) {
            expect(emittedNames, isNot(contains(library)));
          }
        },
      );
    },
  );

  for (final (selection, userDefines) in [
    ('both', _bothRuntimeUserDefines),
    ('litert_lm only', _liteRtLmOnlyUserDefines),
  ]) {
    test('build hook skips LiteRT-LM on macOS x64 with a warning when '
        '$selection is selected', () async {
      final records = <String>[];
      final subscription = Logger.root.onRecord.listen(
        (record) => records.add(record.message),
      );
      addTearDown(subscription.cancel);
      final stderrLines = await _capturingStderr(
        () async => project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.macOS,
          targetArchitecture: Architecture.x64,
          userDefines: userDefines(),
          check: (input, output) {
            final codeAssetIds = output.assets.encodedAssets
                .where((asset) => asset.isCodeAsset)
                .map((asset) => asset.asCodeAsset.id)
                .toList(growable: false);
            expect(
              codeAssetIds,
              selection == 'both' ? ['package:llamadart/llamadart'] : isEmpty,
            );
          },
        ),
      );
      expect(stderrLines, contains(_macOsX64LiteRtLmSkippedWarning));
      _expectNoLiteRtLmBundleRequest(records);
    });
  }

  test('build hook can emit LiteRT-LM runtime without llama.cpp', () async {
    await project.testCodeBuildHook(
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
      final liteRtLmBinary = File(
        path.join(iosDeviceLitertBundleDir.path, 'LiteRtLm'),
      );
      if (!Platform.isWindows) {
        final result = await Process.run('chmod', ['a-w', liteRtLmBinary.path]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
      }
      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        targetIOSSdk: IOSSdk.iPhoneOS,
        userDefines: _bothRuntimeUserDefines(),
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
          if (!Platform.isWindows) {
            final emittedLiteRtLm = codeAssets.singleWhere(
              (asset) => path.basename(asset.file!.toFilePath()) == 'LiteRtLm',
            );
            final mode = FileStat.statSync(
              emittedLiteRtLm.file!.toFilePath(),
            ).mode;
            expect(mode & 0x80, isNonZero);
          }
          expect(
            Directory(path.join(outputDir, 'llamadart_bin')).existsSync(),
            isTrue,
          );
        },
      );
    },
  );

  for (final target in [OS.iOS, OS.macOS]) {
    test(
      'Apple $target rejects resolved old ABI despite native overrides',
      () async {
        final defines = await _flutterAppleUserDefines(
          dependencies: const ['llamadart_llama_cpp_flutter'],
          companionTag: 'v0.3.0',
          companionVersion: '0.0.17',
          defines: {
            'llamadart_native_tag': 'v0.4.0',
            'llamadart_native_path': './new-runtime',
            'llamadart_native_runtimes': ['litert_lm'],
          },
        );
        var emitted = false;
        await expectLater(
          project.testCodeBuildHook(
            mainMethod: build_hook.main,
            targetOS: target,
            targetArchitecture: Architecture.arm64,
            targetIOSSdk: target == OS.iOS ? IOSSdk.iPhoneOS : null,
            userDefines: defines,
            check: (_, _) => emitted = true,
          ),
          throwsA(
            predicate(
              (error) => error.toString().contains(
                'Incompatible Apple llama.cpp companion',
              ),
            ),
          ),
        );
        expect(emitted, isFalse);
      },
    );
  }

  // The checkout core's guidance comes from the helper; the fixed cores pin
  // the literal text, so a hook that stops reading its own version, or names
  // a 0.0.x companion from a lockstep core, fails.
  final checkoutCore = readCheckoutCoreVersion();
  final coreConstraints = <String?, String>{
    null: appleCompanionConstraint(
      checkoutCore,
      firstPinningRelease: llamaCppAppleCompanionVersion,
    )!,
    for (final core in ['0.12.2', '0.13.0-dev.1'])
      core: '^$llamaCppAppleCompanionVersion',
    '0.13.0': '^0.13.0',
    '0.13.3': '^0.13.0',
  };
  final coreRequirements = <String?, String>{
    null: appleCompanionRequirement(
      packageName: 'llamadart_llama_cpp_flutter',
      coreVersion: checkoutCore,
      nativePin: 'leehack/llamadart-native@$llamaCppTag',
      firstPinningRelease: llamaCppAppleCompanionVersion,
    )!,
    for (final core in ['0.12.2', '0.13.0-dev.1'])
      core:
          'Depend on `llamadart_llama_cpp_flutter: '
          '^$llamaCppAppleCompanionVersion`, the first release pinning '
          'leehack/llamadart-native@$llamaCppTag, in pubspec.yaml and rerun '
          'flutter pub get; a caret constraint on an earlier 0.0.x release '
          'never resolves it.',
    for (final core in ['0.13.0', '0.13.3'])
      core:
          'Depend on `llamadart_llama_cpp_flutter: ^0.13.0`, the core 0.13.x '
          'companion releases pinning leehack/llamadart-native@$llamaCppTag, '
          'in pubspec.yaml and rerun flutter pub get.',
  };
  HookProjectRoot coreRoot(String? core) {
    final root = HookProjectRoot.create(coreVersion: core);
    addTearDown(root.delete);
    return root;
  }

  String coreLabel(String? core) => core ?? 'checkout $checkoutCore';

  for (final target in [OS.iOS, OS.macOS]) {
    test(
      'Apple $target rejects the current tag with an arbitrary checksum',
      () async {
        final defines = await _flutterAppleUserDefines(
          dependencies: const ['llamadart_llama_cpp_flutter'],
          companionTag: llamaCppTag,
          companionChecksum: List.filled(64, 'a').join(),
        );
        var emitted = false;
        await expectLater(
          project.testCodeBuildHook(
            mainMethod: build_hook.main,
            targetOS: target,
            targetArchitecture: Architecture.arm64,
            targetIOSSdk: target == OS.iOS ? IOSSdk.iPhoneOS : null,
            userDefines: defines,
            check: (_, _) => emitted = true,
          ),
          throwsA(
            predicate(
              (error) => error.toString().contains(
                'XCFramework checksum does not match the qualified published '
                'artifact for $llamaCppTag.',
              ),
            ),
          ),
        );
        expect(emitted, isFalse);
      },
    );

    for (final MapEntry(key: tag, value: missing)
        in llamaCppCompatibleAppleCompanionTags.entries) {
      for (final MapEntry(key: core, value: constraint)
          in coreConstraints.entries) {
        test('Apple $target core ${coreLabel(core)} links a companion pinning '
            'compatible $tag and names `$constraint`', () async {
          final records = <String>[];
          final subscription = Logger.root.onRecord.listen(
            (record) => records.add(record.message),
          );
          addTearDown(subscription.cancel);
          final defines = await _flutterAppleUserDefines(
            dependencies: const ['llamadart_llama_cpp_flutter'],
            companionTag: tag,
            companionVersion: '0.0.22',
          );
          final hookRoot = coreRoot(core);
          final stderrLines = await _capturingStderr(
            () => hookRoot.testCodeBuildHook(
              mainMethod: build_hook.main,
              targetOS: target,
              targetArchitecture: Architecture.arm64,
              targetIOSSdk: target == OS.iOS ? IOSSdk.iPhoneOS : null,
              userDefines: defines,
              check: (_, output) {
                final asset = output.assets.encodedAssets.single.asCodeAsset;
                expect(asset.id, 'package:llamadart/llamadart');
                expect(asset.linkMode, isA<LookupInProcess>());
              },
            ),
          );
          final warning =
              'Resolved llamadart_llama_cpp_flutter 0.0.22 pins '
              'leehack/llamadart-native@$tag, an earlier llama.cpp runtime '
              'than $llamaCppTag that this core still supports, so this build '
              'links it. '
              'Its frameworks lack $missing. Depend on '
              '`llamadart_llama_cpp_flutter: $constraint` to link '
              '$llamaCppTag.';
          expect(stderrLines, contains('warning: llamadart: $warning'));
          expect(records, contains(warning));
        });
      }

      test('Apple $target rejects compatible $tag declaring another '
          'checksum', () async {
        final pinnedChecksum = RegExp(r'checksum: "([0-9a-f]{64})"')
            .firstMatch(
              File(
                'packages/llamadart_llama_cpp_flutter/'
                'darwin/llamadart_llama_cpp_flutter/Package.swift',
              ).readAsStringSync(),
            )!
            .group(1)!;
        expect(
          pinnedChecksum,
          isNot(llamaCppCompatibleAppleCompanionChecksums[tag]),
        );
        final defines = await _flutterAppleUserDefines(
          dependencies: const ['llamadart_llama_cpp_flutter'],
          companionTag: tag,
          companionChecksum: pinnedChecksum,
          companionVersion: '0.0.22',
        );
        var emitted = false;
        await expectLater(
          project.testCodeBuildHook(
            mainMethod: build_hook.main,
            targetOS: target,
            targetArchitecture: Architecture.arm64,
            targetIOSSdk: target == OS.iOS ? IOSSdk.iPhoneOS : null,
            userDefines: defines,
            check: (_, _) => emitted = true,
          ),
          throwsA(
            predicate(
              (error) => error.toString().contains(
                'Incompatible Apple llama.cpp companion: Companion '
                'XCFramework checksum does not match the qualified published '
                'artifact for $tag.',
              ),
            ),
          ),
        );
        expect(emitted, isFalse);
      });

      test('Apple $target still rejects local Artifacts beside compatible '
          '$tag', () async {
        final defines = await _flutterAppleUserDefines(
          dependencies: const ['llamadart_llama_cpp_flutter'],
          companionTag: tag,
          companionVersion: '0.0.22',
          localArtifacts: true,
        );
        final captured = _CapturedStderr();
        await expectLater(
          IOOverrides.runZoned(
            () => project.testCodeBuildHook(
              mainMethod: build_hook.main,
              targetOS: target,
              targetArchitecture: Architecture.arm64,
              targetIOSSdk: target == OS.iOS ? IOSSdk.iPhoneOS : null,
              userDefines: defines,
              check: (_, _) => fail('Must not emit in-process assets'),
            ),
            stderr: () => captured,
          ),
          throwsA(
            predicate(
              (error) => error.toString().contains(
                'Incompatible Apple llama.cpp companion: Local Artifacts',
              ),
            ),
          ),
        );
        expect(captured.lines, isNot(contains(contains('earlier build'))));
      });
    }

    test('Apple $target links the exact companion pin without a compatibility '
        'warning', () async {
      final records = <String>[];
      final subscription = Logger.root.onRecord.listen(
        (record) => records.add(record.message),
      );
      addTearDown(subscription.cancel);
      final defines = await _flutterAppleUserDefines(
        dependencies: const ['llamadart_llama_cpp_flutter'],
        companionVersion: llamaCppAppleCompanionVersion,
      );
      final stderrLines = await _capturingStderr(
        () => project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: target,
          targetArchitecture: Architecture.arm64,
          targetIOSSdk: target == OS.iOS ? IOSSdk.iPhoneOS : null,
          userDefines: defines,
          check: (_, output) => expect(
            output.assets.encodedAssets.single.asCodeAsset.linkMode,
            isA<LookupInProcess>(),
          ),
        ),
      );
      expect(stderrLines, isNot(contains(contains('earlier build'))));
      expect(records, isNot(contains(contains('earlier build'))));
    });

    for (final tag in ['v0.6.0-1', 'v0.6.0-4', 'v0.5.0-2']) {
      for (final MapEntry(key: core, value: requirement)
          in coreRequirements.entries) {
        test('Apple $target core ${coreLabel(core)} rejects unlisted companion '
            'pin $tag and names the companion release to depend on', () async {
          final defines = await _flutterAppleUserDefines(
            dependencies: const ['llamadart_llama_cpp_flutter'],
            companionTag: tag,
            companionVersion: '0.0.22',
          );
          final hookRoot = coreRoot(core);
          var emitted = false;
          await expectLater(
            hookRoot.testCodeBuildHook(
              mainMethod: build_hook.main,
              targetOS: target,
              targetArchitecture: Architecture.arm64,
              targetIOSSdk: target == OS.iOS ? IOSSdk.iPhoneOS : null,
              userDefines: defines,
              check: (_, _) => emitted = true,
            ),
            throwsA(
              predicate(
                (error) => error.toString().contains(
                  'Incompatible Apple llama.cpp companion: Resolved companion '
                  '0.0.22 does not uniquely pin the required native runtime '
                  '$llamaCppTag. $requirement Upgrade the core and companion '
                  'together',
                ),
              ),
            ),
          );
          expect(emitted, isFalse);
        });
      }
    }
  }

  for (final (scenario, compatibleTag) in [
    for (final tag in [null, ...llamaCppCompatibleAppleCompanionTags.keys])
      for (final scenario in [
        'missing',
        'duplicate',
        'local',
        'false-version',
        'malformed-config',
        'malformed-pubspec',
        'wrong-name',
        'missing-pin',
        'duplicate-pin',
        'wrong-target',
        'hardcoded-url',
        'comment-decoy',
        'missing-manifest',
      ])
        (scenario, tag),
  ]) {
    test(
      'Apple companion rejects $scenario metadata before lookup'
      '${compatibleTag == null ? '' : ' with compatible pin $compatibleTag'}',
      () async {
        final defines = await _flutterAppleUserDefines(
          dependencies: const ['llamadart_llama_cpp_flutter'],
          missingConfiguration: scenario == 'missing',
          duplicateCompanion: scenario == 'duplicate',
          localArtifacts: scenario == 'local',
          companionTag: scenario == 'false-version' ? 'v0.3.0' : compatibleTag,
          mutate: (root) {
            final config = File(
              path.join(root.path, '.dart_tool', 'package_config.json'),
            );
            final metadata = File(
              path.join(root.path, 'resolved companion', 'pubspec.yaml'),
            );
            final manifest = File(
              path.join(
                root.path,
                'resolved companion',
                'darwin',
                'llamadart_llama_cpp_flutter',
                'Package.swift',
              ),
            );
            switch (scenario) {
              case 'malformed-config':
                config.writeAsStringSync('{');
              case 'malformed-pubspec':
                metadata.writeAsStringSync('name: [');
              case 'wrong-name':
                metadata.writeAsStringSync('name: other\nversion: 0.0.18');
              case 'missing-pin':
                manifest.writeAsStringSync('// no pin');
              case 'duplicate-pin':
                manifest.writeAsStringSync(
                  '${manifest.readAsStringSync()}\nlet llamaCppTag = "v0.4.0"\n',
                );
              case 'wrong-target':
                manifest.writeAsStringSync(
                  manifest.readAsStringSync().replaceFirst(
                    'tag: llamaCppTag,',
                    'tag: "v0.3.0",',
                  ),
                );
              case 'missing-manifest':
                manifest.deleteSync();
              case 'hardcoded-url':
                manifest.writeAsStringSync(
                  manifest.readAsStringSync().replaceFirst(
                    r'url: "https://github.com/\(repository)/releases/download/\(tag)/\(artifactName)"',
                    'url: "https://github.com/leehack/llamadart-native/releases/download/v0.3.0/llamadart-native-apple-xcframework-v0.3.0.zip"',
                  ),
                );
              case 'comment-decoy':
                manifest.writeAsStringSync(
                  manifest.readAsStringSync().replaceFirst(
                    'tag: llamaCppTag,',
                    '// tag: llamaCppTag,\n            tag: "v0.3.0",',
                  ),
                );
            }
          },
        );
        var emitted = false;
        await expectLater(
          project.testCodeBuildHook(
            mainMethod: build_hook.main,
            targetOS: OS.iOS,
            targetArchitecture: Architecture.arm64,
            targetIOSSdk: IOSSdk.iPhoneOS,
            userDefines: defines,
            check: (_, _) => emitted = true,
          ),
          throwsA(
            predicate(
              (error) => error.toString().contains(
                'Incompatible Apple llama.cpp companion',
              ),
            ),
          ),
        );
        expect(emitted, isFalse);
      },
    );
  }

  test(
    'workspace-resolved matching companion tracks all metadata for caching',
    () async {
      final defines = await _flutterAppleUserDefines(
        dependencies: const ['llamadart_llama_cpp_flutter'],
        workspaceMember: true,
      );
      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.macOS,
        targetArchitecture: Architecture.arm64,
        userDefines: defines,
        check: (_, output) {
          expect(
            output.assets.encodedAssets.single.asCodeAsset.linkMode,
            isA<LookupInProcess>(),
          );
          final dependencies = output.dependencies
              .map((uri) => uri.toFilePath())
              .toList();
          expect(
            dependencies.where((entry) => entry.endsWith('pubspec.yaml')),
            hasLength(2),
          );
          expect(
            dependencies.any((entry) => entry.endsWith('package_config.json')),
            isTrue,
          );
          expect(
            dependencies.any((entry) => entry.endsWith('Package.swift')),
            isTrue,
          );
          expect(
            output.dependencies.any(
              (uri) =>
                  uri.path.endsWith('/darwin/llamadart_llama_cpp_flutter/'),
            ),
            isTrue,
          );
          expect(
            output.dependencies.any((uri) => uri.path.endsWith('/Artifacts/')),
            isFalse,
          );
          for (final uri in output.dependencies.where(
            (uri) => uri.path.endsWith('/'),
          )) {
            expect(Directory.fromUri(uri).existsSync(), isTrue);
          }
        },
      );
    },
  );

  test(
    'flow YAML and dependency overrides cannot hide old resolved ABI',
    () async {
      final defines = await _flutterAppleUserDefines(
        dependencies: const ['llamadart_llama_cpp_flutter'],
        companionTag: 'v0.3.0',
        mutate: (root) =>
            File(path.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: consumer
dependencies: {flutter: {sdk: flutter}, llamadart: ^0.8.22, llamadart_llama_cpp_flutter: ^0.0.18}
dependency_overrides: {llamadart_llama_cpp_flutter: {path: resolved companion}}
'''),
      );
      await expectLater(
        project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.iOS,
          targetArchitecture: Architecture.arm64,
          targetIOSSdk: IOSSdk.iPhoneOS,
          userDefines: defines,
          check: (_, _) => fail('Must not emit in-process assets'),
        ),
        throwsA(
          predicate(
            (error) => error.toString().contains(
              'Incompatible Apple llama.cpp companion',
            ),
          ),
        ),
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

    await project.testCodeBuildHook(
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
      await project.testCodeBuildHook(
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

  for (final architecture in [Architecture.arm64]) {
    test(
      'build hook hands Flutter macOS $architecture LiteRT-LM to the SwiftPM '
      'companion and keeps its cache for flutter_tester',
      () async {
        final records = <String>[];
        final subscription = Logger.root.onRecord.listen(
          (record) => records.add(record.message),
        );
        addTearDown(subscription.cancel);
        final stderrLines = await _capturingStderr(
          () async => project.testCodeBuildHook(
            mainMethod: build_hook.main,
            targetOS: OS.macOS,
            targetArchitecture: architecture,
            userDefines: await _flutterLiteRtLmOnlyUserDefines(),
            check: (input, output) {
              expect(output.assets.encodedAssets, isEmpty);
              final outputDir = input.outputDirectory.toFilePath();
              expect(
                Directory(path.join(outputDir, 'llamadart_bin')).existsSync(),
                isFalse,
              );
              expect(
                output.dependencies.map((uri) => uri.toFilePath()),
                contains(
                  endsWith(
                    path.join(
                      'resolved litert companion',
                      'darwin',
                      'llamadart_litert_lm_flutter',
                      'Package.swift',
                    ),
                  ),
                ),
              );
            },
          ),
        );
        final arch = architecture == Architecture.arm64 ? 'arm64' : 'x64';
        // The hook joins the platform and arch with '/', so normalise Windows
        // separators before matching the cache directory.
        expect(
          records.map((record) => record.replaceAll(r'\\', '/')),
          contains(
            allOf(
              startsWith('Using cached LiteRT-LM bundle: '),
              endsWith('macos/$arch'),
            ),
          ),
        );
        expect(stderrLines, isNot(contains(contains('warning: llamadart:'))));
      },
    );
  }

  for (final (scenario, defines) in [
    (
      'the published 0.0.14 manifest',
      () => _flutterLiteRtLmOnlyUserDefines(
        liteRtLmManifest: _publishedLiteRtLmCompanion0014Manifest(),
      ),
    ),
    (
      'an edited manifest',
      () => _flutterLiteRtLmOnlyUserDefines(
        liteRtLmManifest: _liteRtLmCompanionManifest().replaceFirst(
          '.target(name: "WebgpuDawn", condition: .when(platforms: [.macOS]))',
          '.target(name: "WebgpuDawn", condition: .when(platforms: [.iOS]))',
        ),
      ),
    ),
    (
      'an unresolved companion',
      () => _flutterLiteRtLmOnlyUserDefines(resolveLiteRtLmCompanion: false),
    ),
  ]) {
    for (final architecture in [Architecture.arm64]) {
      test('build hook keeps Flutter macOS $architecture LiteRT-LM on the '
          'hook cache with a build warning for $scenario', () async {
        final stderrLines = await _capturingStderr(
          () async => project.testCodeBuildHook(
            mainMethod: build_hook.main,
            targetOS: OS.macOS,
            targetArchitecture: architecture,
            userDefines: await defines(),
            check: (input, output) {
              expect(output.assets.encodedAssets, isEmpty);
              final outputDir = input.outputDirectory.toFilePath();
              expect(
                Directory(path.join(outputDir, 'llamadart_bin')).existsSync(),
                isTrue,
              );
            },
          ),
        );
        expect(
          stderrLines,
          contains(
            startsWith(
              'warning: llamadart: The resolved llamadart_litert_lm_flutter '
              'does not link the complete macOS LiteRT-LM runtime',
            ),
          ),
        );
        expect(stderrLines, isNot(contains(contains('embeds its complete'))));
      });
    }
  }

  final coreLiteRtLmTag = _readPinnedConst('liteRtLmReleaseTag');
  final coreLiteRtLmTagParts = RegExp(
    r'^v(\d+)\.(\d+)\.(\d+)(?:-(\d+))?$',
  ).firstMatch(coreLiteRtLmTag)!;
  final coreUpstream =
      'v${coreLiteRtLmTagParts[1]}.${coreLiteRtLmTagParts[2]}.'
      '${coreLiteRtLmTagParts[3]}';
  final coreRebuild = int.parse(coreLiteRtLmTagParts[4] ?? '0');
  final newerUpstream =
      'v${coreLiteRtLmTagParts[1]}.${int.parse(coreLiteRtLmTagParts[2]!) + 1}'
      '.0';
  String pinningLiteRtLm(String pin) =>
      _liteRtLmCompanionManifest().replaceFirst(
        'let liteRtLmTag = "$coreLiteRtLmTag"',
        'let liteRtLmTag = "$pin"',
      );

  const previousTemplateFixture =
      'test/fixtures/litert_lm/'
      'llamadart_litert_lm_flutter_0.19.1-3_Package.swift';
  String previousTemplateManifest(String pin) =>
      File(previousTemplateFixture).readAsStringSync().replaceFirst(
        RegExp(r'let liteRtLmTag = "[^"\n]+"'),
        'let liteRtLmTag = "$pin"',
      );
  Future<List<String>> previousTemplateWarnings(String pin) async {
    final stderrLines = await _capturingStderr(
      () async => project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.macOS,
        targetArchitecture: Architecture.arm64,
        userDefines: await _flutterLiteRtLmOnlyUserDefines(
          liteRtLmManifest: previousTemplateManifest(pin),
        ),
        check: (input, output) {
          expect(output.assets.encodedAssets, isEmpty);
          expect(
            Directory(
              path.join(input.outputDirectory.toFilePath(), 'llamadart_bin'),
            ).existsSync(),
            isTrue,
          );
        },
      ),
    );
    return stderrLines
        .where((line) => line.startsWith('warning: llamadart:'))
        .toList(growable: false);
  }

  final previousFixturePin = RegExp(
    r'let liteRtLmTag = "([^"\n]+)"',
  ).firstMatch(File(previousTemplateFixture).readAsStringSync())!.group(1)!;
  String hookTemplateHash(String name) => RegExp(
    '$name =\\s*\'([0-9a-f]{64})\'',
  ).firstMatch(File('hook/build.dart').readAsStringSync())!.group(1)!;
  final previousTemplateIsCurrent =
      hookTemplateHash('_previousLiteRtLmCompanionManifestTemplateSha256') ==
      hookTemplateHash('_liteRtLmCompanionManifestTemplateSha256');
  final previousFixtureOnCoreLine = previousFixturePin.startsWith(
    '$coreUpstream-',
  );

  test('previous companion template fixture matches the hook hash and, on the '
      'core release line, is an earlier rebuild', () {
    final template = previousTemplateManifest('PIN')
        .replaceAll('\r\n', '\n')
        .replaceAll(
          RegExp(r'checksum: "[0-9a-f]{64}"'),
          'checksum: "CHECKSUM"',
        );
    final hookSource = File('hook/build.dart').readAsStringSync();
    final expected = RegExp(
      r"_previousLiteRtLmCompanionManifestTemplateSha256 =\s*'([0-9a-f]{64})'",
    ).firstMatch(hookSource)!.group(1);
    expect(sha256.convert(utf8.encode(template)).toString(), expected);

    if (previousFixtureOnCoreLine) {
      expect(
        int.parse(previousFixturePin.substring(coreUpstream.length + 1)) <
            coreRebuild,
        isTrue,
        reason:
            'the fixture pins $previousFixturePin, not an earlier build of '
            '$coreLiteRtLmTag: rotate the fixture and the previous hash',
      );
    }
  });

  test(
    'build hook reports an earlier rebuild for the previous macOS-complete '
    'manifest template',
    () async {
      final pin = coreRebuild > 1
          ? '$coreUpstream-${coreRebuild - 1}'
          : coreUpstream;
      expect(await previousTemplateWarnings(pin), [
        'warning: llamadart: The resolved llamadart_litert_lm_flutter pins '
            'leehack/litert-lm-native@$pin, an earlier build of this '
            'core\'s LiteRT-LM release $coreLiteRtLmTag. It still embeds its '
            'complete macOS LiteRT-LM runtime, which the app loads from its '
            'bundle. Upgrade llamadart_litert_lm_flutter to the release '
            'pinning $coreLiteRtLmTag.',
      ]);
    },
    skip: coreRebuild == 0
        ? 'the core pins a bare release: no earlier build'
        : !previousFixtureOnCoreLine
        ? 'the previous companion pins $previousFixturePin on another release '
              'line than $coreLiteRtLmTag, so its template is never accepted'
        : null,
  );

  for (final (scenario, pin) in [
    ('the core tag', coreLiteRtLmTag),
    ('a newer release', newerUpstream),
  ]) {
    test(
      'build hook keeps the incomplete-manifest warning for the previous '
      'template pinning $scenario',
      () async {
        expect(
          await previousTemplateWarnings(pin),
          contains(
            contains(
              'does not link the complete macOS LiteRT-LM runtime (its '
              'Package.swift is not the macOS-complete manifest)',
            ),
          ),
        );
      },
      skip: previousTemplateIsCurrent
          ? 'the previous template is the current one, which any pin may use'
          : null,
    );
  }

  for (final pin in ['v0.18.0', coreLiteRtLmTag]) {
    test('build hook rejects the published 0.0.15 manifest topology '
        'even when it declares $pin', () async {
      final manifest = _publishedLiteRtLmCompanion0015Manifest().replaceFirst(
        'let liteRtLmTag = "v0.18.0"',
        'let liteRtLmTag = "$pin"',
      );
      final stderrLines = await _capturingStderr(
        () async => project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.macOS,
          targetArchitecture: Architecture.arm64,
          userDefines: await _flutterLiteRtLmOnlyUserDefines(
            liteRtLmManifest: manifest,
          ),
          check: (input, output) {
            expect(output.assets.encodedAssets, isEmpty);
            expect(
              Directory(
                path.join(input.outputDirectory.toFilePath(), 'llamadart_bin'),
              ).existsSync(),
              isTrue,
            );
          },
        ),
      );
      expect(
        stderrLines.where((line) => line.startsWith('warning: llamadart:')),
        [
          'warning: llamadart: The resolved llamadart_litert_lm_flutter '
              'does not link the complete macOS LiteRT-LM runtime '
              '(its Package.swift is not the macOS-complete manifest), '
              'so LiteRT-LM stays in the hook cache, which a sandboxed or '
              'relocated app cannot load. Upgrade llamadart_litert_lm_flutter '
              'together with llamadart.',
        ],
      );
    });
  }

  for (final (scenario, manifest, pin, upgradeCompanion) in [
    if (coreRebuild > 0)
      (
        'a macOS-complete manifest pinning the bare upstream release',
        () => pinningLiteRtLm(coreUpstream),
        coreUpstream,
        true,
      ),
    (
      'a macOS-complete manifest pinning an older LiteRT-LM release',
      () => pinningLiteRtLm('v0.17.0-8'),
      'v0.17.0-8',
      false,
    ),
    (
      'a macOS-complete manifest pinning a newer LiteRT-LM release',
      () => pinningLiteRtLm(newerUpstream),
      newerUpstream,
      false,
    ),
    (
      'a macOS-complete manifest pinning a newer build of the same release',
      () => pinningLiteRtLm('$coreUpstream-${coreRebuild + 1}'),
      '$coreUpstream-${coreRebuild + 1}',
      false,
    ),
    for (final malformed in [
      '$coreUpstream-0',
      '$coreUpstream-01',
      coreUpstream.substring(0, coreUpstream.lastIndexOf('.')),
      coreUpstream.substring(1),
      '$coreUpstream-llamadart.1',
      '$coreUpstream-99999999999999999999',
    ])
      (
        'a macOS-complete manifest pinning the malformed tag $malformed',
        () => pinningLiteRtLm(malformed),
        malformed,
        false,
      ),
  ]) {
    final advice = upgradeCompanion
        ? 'only asks to upgrade the companion'
        : 'asks to upgrade core and companion together';
    test('build hook keeps Flutter macOS LiteRT-LM on the hook cache and '
        '$advice for $scenario', () async {
      final stderrLines = await _capturingStderr(
        () async => project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.macOS,
          targetArchitecture: Architecture.arm64,
          userDefines: await _flutterLiteRtLmOnlyUserDefines(
            liteRtLmManifest: manifest(),
          ),
          check: (input, output) {
            expect(output.assets.encodedAssets, isEmpty);
            final outputDir = input.outputDirectory.toFilePath();
            expect(
              Directory(path.join(outputDir, 'llamadart_bin')).existsSync(),
              isTrue,
            );
          },
        ),
      );
      final warnings = stderrLines
          .where((line) => line.startsWith('warning: llamadart:'))
          .toList(growable: false);
      expect(warnings, [
        upgradeCompanion
            ? 'warning: llamadart: The resolved llamadart_litert_lm_flutter '
                  'pins leehack/litert-lm-native@$pin, an earlier build of '
                  'this core\'s LiteRT-LM release $coreLiteRtLmTag. It still '
                  'embeds its complete macOS LiteRT-LM runtime, which the app '
                  'loads from its bundle. Upgrade llamadart_litert_lm_flutter '
                  'to the release pinning $coreLiteRtLmTag.'
            : 'warning: llamadart: The resolved llamadart_litert_lm_flutter '
                  'pins leehack/litert-lm-native@$pin rather than this '
                  'core\'s $coreLiteRtLmTag, so LiteRT-LM stays in the hook '
                  'cache. Upgrade llamadart_litert_lm_flutter and llamadart '
                  'together to a matching released pair.',
      ]);
    });
  }

  test('build hook prints no companion warning for a Flutter macOS app '
      'without the LiteRT-LM companion', () async {
    final stderrLines = await _capturingStderr(
      () async => project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.macOS,
        targetArchitecture: Architecture.arm64,
        userDefines: await _flutterAppleUserDefines(
          dependencies: const [],
          defines: {
            'llamadart_native_runtimes': ['litert_lm'],
          },
        ),
        check: (input, output) {
          final outputDir = input.outputDirectory.toFilePath();
          expect(
            Directory(path.join(outputDir, 'llamadart_bin')).existsSync(),
            isTrue,
          );
        },
      ),
    );
    expect(stderrLines, isNot(contains(contains('warning: llamadart:'))));
  });

  for (final (scenario, dependencies, expectedAssetIds) in [
    ('the LiteRT-LM companion', const ['llamadart_litert_lm_flutter'], []),
    (
      'both companions',
      const ['llamadart_llama_cpp_flutter', 'llamadart_litert_lm_flutter'],
      ['package:llamadart/llamadart'],
    ),
  ]) {
    test('build hook drops companion-implied LiteRT-LM from the Flutter macOS '
        'x64 slice with a warning for $scenario', () async {
      final records = <String>[];
      final subscription = Logger.root.onRecord.listen(
        (record) => records.add(record.message),
      );
      addTearDown(subscription.cancel);
      final stderrLines = await _capturingStderr(
        () async => project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.macOS,
          targetArchitecture: Architecture.x64,
          userDefines: await _flutterAppleUserDefines(
            dependencies: dependencies,
            defines: {
              'llamadart_native_runtimes': {
                'runtimes': ['litert_lm'],
                'platforms': {
                  'macos': ['litert_lm'],
                },
              },
            },
          ),
          check: (input, output) {
            expect(
              output.assets.encodedAssets
                  .map((asset) => asset.asCodeAsset.id)
                  .toList(growable: false),
              expectedAssetIds,
            );
            final outputDir = input.outputDirectory.toFilePath();
            expect(
              Directory(path.join(outputDir, 'llamadart_bin')).existsSync(),
              isFalse,
            );
          },
        ),
      );
      expect(stderrLines, contains(_macOsX64LiteRtLmSkippedWarning));
      _expectNoLiteRtLmBundleRequest(records);
    });
  }

  for (final bundleKey in ['macos-x86_64', 'macos-x64']) {
    test('build hook fails a Flutter macOS x64 build whose $bundleKey entry '
        'names LiteRT-LM', () async {
      await expectLater(
        project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.macOS,
          targetArchitecture: Architecture.x64,
          userDefines: await _flutterAppleUserDefines(
            dependencies: const ['llamadart_litert_lm_flutter'],
            defines: {
              'llamadart_native_runtimes': {
                'platforms': {
                  bundleKey: ['litert_lm'],
                },
              },
            },
          ),
          check: (_, _) {},
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            allOf(
              contains(
                'LiteRT-LM is not available on macOS x86_64: '
                'litert-lm-native publishes arm64-only macOS runtimes '
                '(leehack/litert-lm-native#72).',
              ),
              contains(
                'Remove litert_lm from the macos-x86_64 entry of '
                'llamadart_native_runtimes',
              ),
            ),
          ),
        ),
      );
    });
  }

  test(
    'build hook keeps iOS LiteRT-LM on SwiftPM without probing the manifest',
    () async {
      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        targetIOSSdk: IOSSdk.iPhoneOS,
        userDefines: await _flutterLiteRtLmOnlyUserDefines(
          liteRtLmManifest: _publishedLiteRtLmCompanion0014Manifest(),
        ),
        check: (input, output) {
          expect(output.assets.encodedAssets, isEmpty);
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
    'build hook keeps non-Flutter macOS LiteRT-LM on the hook cache',
    () async {
      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.macOS,
        targetArchitecture: Architecture.arm64,
        userDefines: await _nonFlutterConsumerUserDefines(
          dependencies: const ['llamadart_litert_lm_flutter'],
          defines: {
            'llamadart_native_runtimes': ['litert_lm'],
          },
        ),
        check: (input, output) {
          expect(output.assets.encodedAssets, isEmpty);
          final outputDir = input.outputDirectory.toFilePath();
          expect(
            Directory(path.join(outputDir, 'llamadart_bin')).existsSync(),
            isTrue,
          );
        },
      );
    },
  );

  test('build hook hands both macOS runtimes to SwiftPM companions', () async {
    await project.testCodeBuildHook(
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
          isFalse,
        );
      },
    );
  });

  test('build hook mixes macOS llama.cpp SPM with LiteRT-LM hook assets for an '
      'older LiteRT-LM companion', () async {
    await project.testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.macOS,
      targetArchitecture: Architecture.arm64,
      userDefines: await _flutterAppleUserDefines(
        dependencies: const [
          'llamadart_llama_cpp_flutter',
          'llamadart_litert_lm_flutter',
        ],
        liteRtLmManifest: _publishedLiteRtLmCompanion0014Manifest(),
      ),
      check: (input, output) {
        final codeAssets = output.assets.encodedAssets
            .where((asset) => asset.isCodeAsset)
            .map((asset) => asset.asCodeAsset)
            .toList(growable: false);

        expect(codeAssets, hasLength(1));
        expect(codeAssets.single.linkMode, isA<LookupInProcess>());
        final outputDir = input.outputDirectory.toFilePath();
        expect(
          Directory(path.join(outputDir, 'llamadart_bin')).existsSync(),
          isTrue,
        );
      },
    );
  });

  test(
    'build hook uses SPM process lookup for Flutter iOS llama.cpp companion',
    () async {
      await project.testCodeBuildHook(
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
      await project.testCodeBuildHook(
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

  test('build hook drops unavailable LiteRT-LM from both and empty '
      'selections', () async {
    for (final userDefines in [
      _bothRuntimeUserDefines(),
      _emptyRuntimeUserDefines(),
    ]) {
      await project.testCodeBuildHook(
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
      await project.testCodeBuildHook(
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
      await project.testCodeBuildHook(
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
        project.testCodeBuildHook(
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
            allOf(
              contains('LiteRT-LM runtime is not available for ios-x86_64-sim'),
              contains('EXCLUDED_ARCHS[sdk=iphonesimulator*]=i386 x86_64'),
            ),
          ),
        ),
      );
    },
  );

  test(
    'build hook fails when Flutter companion selects unavailable LiteRT-LM',
    () async {
      await expectLater(
        project.testCodeBuildHook(
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
            allOf(
              contains('LiteRT-LM runtime is not available for ios-x86_64-sim'),
              contains('EXCLUDED_ARCHS[sdk=iphonesimulator*]=i386 x86_64'),
            ),
          ),
        ),
      );
    },
  );

  group('Flutter app reaching the llama.cpp companion through app_core', () {
    const companion = 'llamadart_llama_cpp_flutter';

    /// A standalone Flutter app whose `app_core` dependency, or dev
    /// dependency when [dev], declares the llama.cpp companion.
    Future<PackageUserDefines> appWithCore({
      String? companionTag,
      bool dev = false,
    }) => _flutterAppleUserDefines(
      dependencies: const [companion],
      companionTag: companionTag,
      companionVersion: llamaCppAppleCompanionVersion,
      mutate: (dir) {
        final pubspec = File(path.join(dir.path, 'pubspec.yaml'));
        pubspec.writeAsStringSync(
          pubspec
              .readAsStringSync()
              .replaceFirst(
                '  $companion: ^0.0.17\n',
                dev ? '' : '  app_core: any\n',
              )
              .replaceFirst(
                'dependencies:',
                dev
                    ? 'dev_dependencies:\n  app_core: any\n\ndependencies:'
                    : 'dependencies:',
              ),
        );
        File(
          path.join(dir.path, _dartToolDir, 'package_graph.json'),
        ).writeAsStringSync(
          jsonEncode({
            'roots': ['llamadart_apple_consumer'],
            'packages': [
              {
                'name': 'llamadart_apple_consumer',
                'dependencies': ['flutter', 'llamadart', if (!dev) 'app_core'],
                'devDependencies': [if (dev) 'app_core'],
              },
              {
                'name': 'app_core',
                'dependencies': ['flutter', 'llamadart', companion],
              },
              {
                'name': companion,
                'dependencies': ['flutter', 'llamadart'],
              },
              {'name': 'flutter', 'dependencies': <String>[]},
              {'name': 'llamadart', 'dependencies': <String>[]},
            ],
            'configVersion': 1,
          }),
        );
      },
    );

    for (final target in [OS.iOS, OS.macOS]) {
      test('Apple $target validates the companion', () async {
        await expectLater(
          project.testCodeBuildHook(
            mainMethod: build_hook.main,
            targetOS: target,
            targetArchitecture: Architecture.arm64,
            targetIOSSdk: target == OS.iOS ? IOSSdk.iPhoneOS : null,
            userDefines: await appWithCore(companionTag: 'v0.5.0'),
            check: (_, _) => fail('Must not emit in-process assets'),
          ),
          throwsA(
            predicate(
              (error) => error.toString().contains(
                'Incompatible Apple llama.cpp companion',
              ),
            ),
          ),
        );
      });
    }

    test('Apple links the companion', () async {
      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        targetIOSSdk: IOSSdk.iPhoneOS,
        userDefines: await appWithCore(),
        check: (_, output) {
          expect(
            output.assets.encodedAssets.single.asCodeAsset.linkMode,
            isA<LookupInProcess>(),
          );
          expect(
            output.dependencies.map((uri) => uri.toFilePath()),
            contains(endsWith(path.join(_dartToolDir, 'package_graph.json'))),
          );
        },
      );
    });

    test('Apple ignores a companion only a dev dependency reaches', () async {
      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        targetIOSSdk: IOSSdk.iPhoneOS,
        userDefines: await appWithCore(companionTag: 'v0.5.0', dev: true),
        check: (_, output) => expect(
          output.assets.encodedAssets.map(
            (asset) => asset.asCodeAsset.linkMode,
          ),
          everyElement(isA<DynamicLoadingBundled>()),
        ),
      );
    });

    for (final (scenario, edit) in [
      ('a missing', (File graph) => graph.deleteSync()),
      ('a malformed', (File graph) => graph.writeAsStringSync('{"roots": 1}')),
    ]) {
      test('Apple counts direct dependencies only with $scenario package '
          'graph', () async {
        final defines = await appWithCore(companionTag: 'v0.5.0');
        edit(
          File(
            path.join(
              File.fromUri(defines.workspacePubspec!.basePath).parent.path,
              _dartToolDir,
              'package_graph.json',
            ),
          ),
        );
        await project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.iOS,
          targetArchitecture: Architecture.arm64,
          targetIOSSdk: IOSSdk.iPhoneOS,
          userDefines: defines,
          check: (_, output) => expect(
            output.assets.encodedAssets.map(
              (asset) => asset.asCodeAsset.linkMode,
            ),
            everyElement(isA<DynamicLoadingBundled>()),
          ),
        );
      });
    }
  });

  group('pub workspace', () {
    const llamaCppCompanion = 'llamadart_llama_cpp_flutter';
    const app = ['flutter', 'llamadart', llamaCppCompanion];
    final inProcess = isA<LookupInProcess>();
    final bundled = isA<DynamicLoadingBundled>();
    final incompatibleLlamaCpp = throwsA(
      predicate(
        (error) =>
            error.toString().contains('Incompatible Apple llama.cpp companion'),
      ),
    );

    for (final target in [OS.iOS, OS.macOS]) {
      test('Apple $target rejects a mismatched llama.cpp companion only the '
          'app member declares', () async {
        var emitted = false;
        await expectLater(
          project.testCodeBuildHook(
            mainMethod: build_hook.main,
            targetOS: target,
            targetArchitecture: Architecture.arm64,
            targetIOSSdk: target == OS.iOS ? IOSSdk.iPhoneOS : null,
            userDefines: await _appleWorkspaceUserDefines(
              members: const {'app': app},
              llamaCppTag: 'v0.5.0',
            ),
            check: (_, _) => emitted = true,
          ),
          incompatibleLlamaCpp,
        );
        expect(emitted, isFalse);
      });

      test('Apple $target rejects the previous upstream companion declared '
          'by an app member before emitting assets', () async {
        var emitted = false;
        await expectLater(
          project.testCodeBuildHook(
            mainMethod: build_hook.main,
            targetOS: target,
            targetArchitecture: Architecture.arm64,
            targetIOSSdk: target == OS.iOS ? IOSSdk.iPhoneOS : null,
            userDefines: await _appleWorkspaceUserDefines(
              members: const {'app': app},
              llamaCppTag: 'v0.6.0-2',
            ),
            check: (_, _) => emitted = true,
          ),
          incompatibleLlamaCpp,
        );
        expect(emitted, isFalse);
      });
    }

    test('Apple rejects a mismatched stable_diffusion companion only the app '
        'member declares', () async {
      await expectLater(
        project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.iOS,
          targetArchitecture: Architecture.arm64,
          targetIOSSdk: IOSSdk.iPhoneOS,
          userDefines: await _appleWorkspaceUserDefines(
            members: const {
              'app': ['flutter', 'llamadart', _stableDiffusionCompanion],
            },
            stableDiffusionTag: 'v0.1.1',
          ),
          check: (_, _) => fail('Must not emit in-process assets'),
        ),
        throwsA(
          predicate(
            (error) => error.toString().contains(
              'Incompatible Apple stable_diffusion companion',
            ),
          ),
        ),
      );
    });

    test('macOS checks the LiteRT-LM companion manifest only the app member '
        'declares', () async {
      final stderrLines = await _capturingStderr(
        () async => project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.macOS,
          targetArchitecture: Architecture.arm64,
          userDefines: await _appleWorkspaceUserDefines(
            members: const {
              'app': ['flutter', 'llamadart', 'llamadart_litert_lm_flutter'],
            },
            defines: {
              'llamadart_native_runtimes': ['llama_cpp'],
            },
            liteRtLmManifest: _publishedLiteRtLmCompanion0014Manifest(),
          ),
          check: (_, output) => expect(output.assets.encodedAssets, isEmpty),
        ),
      );
      expect(
        stderrLines,
        contains(
          startsWith(
            'warning: llamadart: The resolved llamadart_litert_lm_flutter '
            'does not link the complete macOS LiteRT-LM runtime',
          ),
        ),
      );
    });

    test('Apple follows the app past a Flutter library member and a Flutter '
        'member without llamadart', () async {
      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        targetIOSSdk: IOSSdk.iPhoneOS,
        userDefines: await _appleWorkspaceUserDefines(
          members: const {
            'app': ['flutter', 'ai_kit', llamaCppCompanion],
            'ai_kit': ['flutter', 'llamadart'],
            'gallery': ['flutter'],
          },
        ),
        check: (_, output) {
          expect(
            output.assets.encodedAssets.single.asCodeAsset.linkMode,
            inProcess,
          );
          expect(
            output.dependencies.map((uri) => uri.toFilePath()),
            containsAll([
              endsWith(path.join('app', 'pubspec.yaml')),
              endsWith(path.join(_dartToolDir, 'package_graph.json')),
            ]),
          );
        },
      );
    });

    for (final (scenario, members) in [
      (
        'an e2e app that depends on the app',
        const {
          'app': app,
          'e2e': ['flutter', 'app'],
        },
      ),
      (
        'white-label apps that depend on a shared app core',
        const {
          'app_core': app,
          'brand_a': ['flutter', 'app_core'],
          'brand_b': ['flutter', 'app_core'],
        },
      ),
    ]) {
      for (final target in [OS.iOS, OS.macOS]) {
        test('Apple $target validates the companion of $scenario', () async {
          await expectLater(
            project.testCodeBuildHook(
              mainMethod: build_hook.main,
              targetOS: target,
              targetArchitecture: Architecture.arm64,
              targetIOSSdk: target == OS.iOS ? IOSSdk.iPhoneOS : null,
              userDefines: await _appleWorkspaceUserDefines(
                members: members,
                llamaCppTag: 'v0.5.0',
              ),
              check: (_, _) => fail('Must not emit in-process assets'),
            ),
            incompatibleLlamaCpp,
          );
        });
      }

      test('Apple links the companion of $scenario', () async {
        await project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.iOS,
          targetArchitecture: Architecture.arm64,
          targetIOSSdk: IOSSdk.iPhoneOS,
          userDefines: await _appleWorkspaceUserDefines(members: members),
          check: (_, output) => expect(
            output.assets.encodedAssets.single.asCodeAsset.linkMode,
            inProcess,
          ),
        );
      });
    }

    test('Apple applies the companions several Flutter apps share', () async {
      await expectLater(
        project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.iOS,
          targetArchitecture: Architecture.arm64,
          targetIOSSdk: IOSSdk.iPhoneOS,
          userDefines: await _appleWorkspaceUserDefines(
            members: const {'kiosk': app, 'phone': app},
            llamaCppTag: 'v0.5.0',
          ),
          check: (_, _) => fail('Must not emit in-process assets'),
        ),
        incompatibleLlamaCpp,
      );
    });

    for (final target in [OS.iOS, OS.macOS]) {
      test('Apple $target bundles assets for a workspace without Flutter '
          'apps', () async {
        final stderrLines = await _capturingStderr(
          () async => project.testCodeBuildHook(
            mainMethod: build_hook.main,
            targetOS: target,
            targetArchitecture: Architecture.arm64,
            targetIOSSdk: target == OS.iOS ? IOSSdk.iPhoneOS : null,
            userDefines: await _appleWorkspaceUserDefines(
              members: const {
                'tool': ['llamadart'],
              },
              defines: {
                'llamadart_native_runtimes': ['llama_cpp'],
              },
            ),
            check: (_, output) {
              expect(
                output.assets.encodedAssets.single.asCodeAsset.linkMode,
                bundled,
              );
              // A Flutter dependency added to the member, or a moved member
              // root, must rerun the hook.
              expect(
                output.dependencies.map((uri) => uri.toFilePath()),
                containsAll([
                  endsWith(path.join('tool', 'pubspec.yaml')),
                  endsWith(path.join(_dartToolDir, 'package_config.json')),
                ]),
              );
            },
          ),
        );
        expect(stderrLines, isNot(contains(contains('warning: llamadart:'))));
      });
    }

    for (final (scenario, members, devDependencies) in [
      (
        'a Dart package',
        const {
          'app': app,
          'cli': ['llamadart'],
        },
        const <String, List<String>>{},
      ),
      (
        'a Dart package that dev-depends on llamadart',
        const {'app': app, 'bench': <String>[]},
        const {
          'bench': ['llamadart'],
        },
      ),
      (
        'a root that dev-depends on llamadart',
        const {'app': app},
        const {
          _workspaceRootName: ['llamadart'],
        },
      ),
    ]) {
      test('iOS validates the Flutter app next to $scenario, which no iOS '
          'build bundles', () async {
        await expectLater(
          project.testCodeBuildHook(
            mainMethod: build_hook.main,
            targetOS: OS.iOS,
            targetArchitecture: Architecture.arm64,
            targetIOSSdk: IOSSdk.iPhoneOS,
            userDefines: await _appleWorkspaceUserDefines(
              members: members,
              devDependencies: devDependencies,
              llamaCppTag: 'v0.5.0',
            ),
            check: (_, _) => fail('Must not emit in-process assets'),
          ),
          incompatibleLlamaCpp,
        );
      });
    }

    test('macOS validates the Flutter app next to a Dart package whose '
        'dependency only dev-depends on llamadart', () async {
      await expectLater(
        project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.macOS,
          targetArchitecture: Architecture.arm64,
          userDefines: await _appleWorkspaceUserDefines(
            members: const {
              'app': app,
              'cli': ['helper'],
              'helper': <String>[],
            },
            devDependencies: const {
              'helper': ['llamadart'],
            },
            llamaCppTag: 'v0.5.0',
          ),
          check: (_, _) => fail('Must not emit in-process assets'),
        ),
        incompatibleLlamaCpp,
      );
    });

    const apple = [OS.iOS, OS.macOS];
    for (final (scenario, targets, members, devDependencies, setups) in [
      (
        'Flutter apps with different companions',
        apple,
        const {
          'app': app,
          'kiosk': ['flutter', 'llamadart'],
        },
        const <String, List<String>>{},
        'app (Flutter, $llamaCppCompanion); kiosk (Flutter, no Apple '
            'companion)',
      ),
      (
        'a Flutter app and a Dart package',
        [OS.macOS],
        const {
          'app': app,
          'cli': ['llamadart'],
        },
        const <String, List<String>>{},
        'app (Flutter, $llamaCppCompanion); cli (not Flutter)',
      ),
      (
        'a Flutter app and a Dart package that dev-depends on llamadart',
        [OS.macOS],
        const {'app': app, 'bench': <String>[]},
        const {
          'bench': ['llamadart'],
        },
        'app (Flutter, $llamaCppCompanion); bench (not Flutter)',
      ),
      (
        'a Flutter app and a Flutter package that dev-depends on llamadart',
        apple,
        const {
          'app': app,
          'harness': ['flutter'],
        },
        const {
          'harness': ['llamadart'],
        },
        'app (Flutter, $llamaCppCompanion); harness (Flutter, no Apple '
            'companion)',
      ),
      (
        'a Flutter app and an e2e Flutter app that dev-depends on llamadart',
        apple,
        const {
          'app': app,
          'e2e': ['flutter'],
        },
        const {
          'e2e': ['flutter_test', 'llamadart'],
        },
        'app (Flutter, $llamaCppCompanion); e2e (Flutter, no Apple '
            'companion)',
      ),
      (
        'a Flutter app and an e2e Flutter app that dev-depends on the app',
        apple,
        const {
          'app': app,
          'e2e': ['flutter'],
        },
        const {
          'e2e': ['app'],
        },
        'app (Flutter, $llamaCppCompanion); e2e (Flutter, no Apple '
            'companion)',
      ),
      (
        'a Flutter app and a root that dev-depends on llamadart',
        [OS.macOS],
        const {'app': app},
        const {
          _workspaceRootName: ['llamadart'],
        },
        'app (Flutter, $llamaCppCompanion); $_workspaceRootName (not '
            'Flutter)',
      ),
      (
        'Flutter apps that differ only in the stable_diffusion companion',
        apple,
        const {
          'app': app,
          'studio': [...app, _stableDiffusionCompanion],
        },
        const <String, List<String>>{},
        'app (Flutter, $llamaCppCompanion); studio (Flutter, '
            '$llamaCppCompanion, $_stableDiffusionCompanion)',
      ),
    ]) {
      for (final target in targets) {
        test('$target warns and bundles assets for $scenario', () async {
          final stderrLines = await _capturingStderr(
            () async => project.testCodeBuildHook(
              mainMethod: build_hook.main,
              targetOS: target,
              targetArchitecture: Architecture.arm64,
              targetIOSSdk: target == OS.iOS ? IOSSdk.iPhoneOS : null,
              userDefines: await _appleWorkspaceUserDefines(
                members: members,
                devDependencies: devDependencies,
                defines: {
                  'llamadart_native_runtimes': ['llama_cpp'],
                },
                llamaCppTag: 'v0.5.0',
              ),
              check: (_, output) => expect(
                output.assets.encodedAssets.single.asCodeAsset.linkMode,
                bundled,
              ),
            ),
          );
          expect(
            stderrLines,
            contains(
              allOf(
                startsWith(
                  'warning: llamadart: Cannot tell which member of the pub '
                  'workspace at ',
                ),
                contains('this Apple build is for: $setups. Every member'),
                contains(
                  'Declare the same Apple companions in every Flutter app that '
                  'depends on llamadart',
                ),
              ),
            ),
          );
        });
      }
    }

    test('a Flutter workspace root decides from its own pubspec', () async {
      await expectLater(
        project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.iOS,
          targetArchitecture: Architecture.arm64,
          targetIOSSdk: IOSSdk.iPhoneOS,
          userDefines: await _appleWorkspaceUserDefines(
            rootDependencies: app,
            members: const {
              'kiosk': ['flutter', 'llamadart'],
            },
            llamaCppTag: 'v0.5.0',
          ),
          check: (_, _) => fail('Must not emit in-process assets'),
        ),
        incompatibleLlamaCpp,
      );
    });

    final graph = path.join(_dartToolDir, 'package_graph.json');
    final config = path.join(_dartToolDir, 'package_config.json');
    for (final (scenario, file, problem, edit) in [
      (
        'missing package graph',
        graph,
        'could not be read',
        (File graph) => graph.deleteSync(),
      ),
      (
        'malformed package graph',
        graph,
        'is malformed',
        (File graph) => graph.writeAsStringSync('{"roots": 1}'),
      ),
      (
        'package graph entry without dependencies',
        graph,
        'is malformed',
        (File graph) => graph.writeAsStringSync(
          jsonEncode({
            'roots': [_workspaceRootName, 'app'],
            'packages': [
              {'name': 'app'},
            ],
          }),
        ),
      ),
      (
        'member root that is not a local directory',
        config,
        'has no local root for workspace member app',
        (File config) => config.writeAsStringSync(
          config.readAsStringSync().replaceFirst(
            '"rootUri":"../app"',
            '"rootUri":"https://example.com/app/"',
          ),
        ),
      ),
      (
        'member missing from the package config',
        config,
        'has no local root for workspace member app',
        (File config) => config.writeAsStringSync(
          config.readAsStringSync().replaceFirst(
            '{"name":"app","rootUri":"../app"},',
            '',
          ),
        ),
      ),
      (
        'member pubspec that cannot be read',
        path.join('app', 'pubspec.yaml'),
        'could not be read',
        (File pubspec) => pubspec.deleteSync(),
      ),
    ]) {
      test('Apple warns and bundles assets for a $scenario', () async {
        // kiosk fails companion validation, so the build only bundles assets
        // when the broken app member stops the search.
        final defines = await _appleWorkspaceUserDefines(
          members: const {'app': app, 'kiosk': app},
          defines: {
            'llamadart_native_runtimes': ['llama_cpp'],
          },
          llamaCppTag: 'v0.5.0',
        );
        edit(
          File(
            path.join(
              File.fromUri(defines.workspacePubspec!.basePath).parent.path,
              file,
            ),
          ),
        );
        final stderrLines = await _capturingStderr(
          () => project.testCodeBuildHook(
            mainMethod: build_hook.main,
            targetOS: OS.macOS,
            targetArchitecture: Architecture.arm64,
            userDefines: defines,
            check: (_, output) => expect(
              output.assets.encodedAssets.single.asCodeAsset.linkMode,
              bundled,
            ),
          ),
        );
        expect(
          stderrLines,
          contains(
            allOf(
              startsWith(
                'warning: llamadart: Cannot find the Flutter app in the pub '
                'workspace at ',
              ),
              contains(problem),
              endsWith('Run flutter pub get in the workspace and rebuild.'),
            ),
          ),
        );
      });
    }
  });
}

const _dartToolDir = '.dart_tool';
const _workspaceRootName = 'llamadart_apple_workspace';
const _stableDiffusionCompanion = 'llamadart_stable_diffusion_flutter';

/// A pub workspace whose root `pubspec.yaml` carries the user-defines, as pub
/// passes them to the hook, with each of [members] as `name: dependencies` at
/// `<root>/<name>` and [devDependencies] as the `dev_dependencies` of those
/// members or of [_workspaceRootName], the root, which has [rootDependencies];
/// a
/// `flutter` dependency is the Flutter SDK. Every companion
/// a member names resolves to a copy of the maintained one, with [llamaCppTag]
/// or [stableDiffusionTag] replacing its pin and [liteRtLmManifest] replacing
/// the LiteRT-LM manifest. Like pub, it writes `package_config.json` and
/// `package_graph.json` only under the root `.dart_tool/`.
Future<PackageUserDefines> _appleWorkspaceUserDefines({
  required Map<String, List<String>> members,
  List<String> rootDependencies = const [],
  Map<String, List<String>> devDependencies = const {},
  Map<String, Object?> defines = const {},
  String? llamaCppTag,
  String? stableDiffusionTag,
  String? liteRtLmManifest,
}) async {
  final root = await Directory.systemTemp.createTemp(
    'llamadart_apple_workspace_',
  );
  addTearDown(() => root.delete(recursive: true));
  const rootName = _workspaceRootName;
  String dependencyYaml(String dependency) => dependency == 'flutter'
      ? '  flutter:\n    sdk: flutter'
      : '  $dependency: any';
  final pubspec = File(path.join(root.path, 'pubspec.yaml'))
    ..writeAsStringSync('''
name: $rootName
publish_to: none

environment:
  sdk: ^3.10.7

workspace:
${members.keys.map((name) => '  - $name').join('\n')}

dependencies:
${rootDependencies.map(dependencyYaml).join('\n')}

dev_dependencies:
${devDependencies[rootName]?.map((dependency) => '  $dependency: any').join('\n') ?? ''}
''');
  final config = <Map<String, String>>[
    {'name': rootName, 'rootUri': '../'},
  ];
  final graph = <Map<String, Object?>>[
    {
      'name': rootName,
      'dependencies': rootDependencies,
      'devDependencies': devDependencies[rootName] ?? <String>[],
    },
    {'name': 'flutter', 'dependencies': <String>[]},
    {'name': 'llamadart', 'dependencies': <String>[]},
  ];
  for (final MapEntry(key: name, value: dependencies) in members.entries) {
    await Directory(path.join(root.path, name)).create();
    File(path.join(root.path, name, 'pubspec.yaml')).writeAsStringSync('''
name: $name
publish_to: none
resolution: workspace

environment:
  sdk: ^3.10.7

dependencies:
${dependencies.map(dependencyYaml).join('\n')}

dev_dependencies:
${devDependencies[name]?.map((dependency) => '  $dependency: any').join('\n') ?? ''}
''');
    config.add({'name': name, 'rootUri': '../$name'});
    graph.add({
      'name': name,
      'dependencies': dependencies,
      'devDependencies': devDependencies[name] ?? <String>[],
    });
  }
  final companions = {
    for (final dependencies in [rootDependencies, ...members.values])
      for (final dependency in dependencies)
        if (dependency.startsWith('llamadart_')) dependency,
  };
  for (final name in companions) {
    final companion = Directory(path.join(root.path, 'resolved', name));
    final manifest = File(
      path.join(companion.path, 'darwin', name, 'Package.swift'),
    );
    await manifest.parent.create(recursive: true);
    File(
      path.join(companion.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: $name\nversion: 0.13.0\n');
    var source = File(
      'packages/$name/darwin/$name/Package.swift',
    ).readAsStringSync();
    for (final (variable, tag) in [
      ('llamaCppTag', llamaCppTag),
      ('stableDiffusionTag', stableDiffusionTag),
    ]) {
      if (tag == null) continue;
      source = source.replaceFirst(
        RegExp('^let $variable = "[^"]+"', multiLine: true),
        'let $variable = "$tag"',
      );
    }
    if (name == 'llamadart_litert_lm_flutter' && liteRtLmManifest != null) {
      source = liteRtLmManifest;
    }
    manifest.writeAsStringSync(source);
    config.add({'name': name, 'rootUri': '../resolved/$name'});
    graph.add({
      'name': name,
      'dependencies': ['flutter', 'llamadart'],
    });
  }
  final dartTool = Directory(path.join(root.path, _dartToolDir));
  await dartTool.create();
  File(
    path.join(dartTool.path, 'package_config.json'),
  ).writeAsStringSync(jsonEncode({'configVersion': 2, 'packages': config}));
  File(path.join(dartTool.path, 'package_graph.json')).writeAsStringSync(
    jsonEncode({
      'roots': [rootName, ...members.keys],
      'packages': graph,
      'configVersion': 1,
    }),
  );
  return PackageUserDefines(
    workspacePubspec: PackageUserDefinesSource(
      defines: defines,
      basePath: pubspec.uri,
    ),
  );
}

const _macOsX64LiteRtLmSkippedWarning =
    'warning: llamadart: LiteRT-LM is not available on macOS x86_64: '
    'litert-lm-native publishes arm64-only macOS runtimes '
    '(leehack/litert-lm-native#72). The x86_64 slice of this build leaves '
    'LiteRT-LM out; selecting it there throws LlamaUnsupportedException.';

/// Fails when the hook looked up, downloaded or cached any LiteRT-LM bundle.
void _expectNoLiteRtLmBundleRequest(List<String> records) {
  expect(records, isNot(contains(contains('LiteRT-LM bundle'))));
  expect(records, isNot(contains(contains('litert-lm-native-runtime-'))));
}

/// Runs [body] with `stderr` captured, returning the lines it wrote.
Future<List<String>> _capturingStderr(Future<void> Function() body) async {
  final captured = _CapturedStderr();
  await IOOverrides.runZoned(body, stderr: () => captured);
  return captured.lines;
}

class _CapturedStderr implements Stdout {
  final lines = <String>[];

  @override
  void writeln([Object? object = '']) => lines.add('$object');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _readPinnedConst(String name) {
  final source = File(
    'lib/src/hook/native_release_pins.dart',
  ).readAsStringSync();
  final match = RegExp("const $name = '([^']+)';").firstMatch(source);
  if (match == null) {
    throw StateError(
      'Could not locate $name in lib/src/hook/native_release_pins.dart',
    );
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

PackageUserDefines _bothRuntimeUserDefines() => PackageUserDefines(
  workspacePubspec: PackageUserDefinesSource(
    defines: {
      'llamadart_native_runtimes': ['both'],
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

Future<PackageUserDefines> _flutterLiteRtLmOnlyUserDefines({
  bool resolveLiteRtLmCompanion = true,
  String? liteRtLmManifest,
}) {
  return _flutterAppleUserDefines(
    dependencies: const ['llamadart_litert_lm_flutter'],
    defines: {
      'llamadart_native_runtimes': ['llama_cpp'],
    },
    resolveLiteRtLmCompanion: resolveLiteRtLmCompanion,
    liteRtLmManifest: liteRtLmManifest,
  );
}

/// The maintained companion manifest, which links the complete macOS runtime.
String _liteRtLmCompanionManifest() => File(
  'packages/llamadart_litert_lm_flutter/'
  'darwin/llamadart_litert_lm_flutter/Package.swift',
).readAsStringSync();

/// The manifest published as companion 0.0.14, which links only LiteRtLm and
/// the CLiteRTLM shim on macOS.
String _publishedLiteRtLmCompanion0014Manifest() => File(
  'test/fixtures/litert_lm/llamadart_litert_lm_flutter_0.0.14_Package.swift',
).readAsStringSync();

/// The manifest published as companion 0.0.15: the macOS-complete manifest
/// pinning v0.18.0 rather than this core's rebuild of the same release.
String _publishedLiteRtLmCompanion0015Manifest() => File(
  'test/fixtures/litert_lm/llamadart_litert_lm_flutter_0.0.15_Package.swift',
).readAsStringSync();

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
  String? companionTag,
  String? companionChecksum,
  String companionVersion = '0.0.18',
  bool missingConfiguration = false,
  bool duplicateCompanion = false,
  bool localArtifacts = false,
  bool workspaceMember = false,
  bool resolveLiteRtLmCompanion = true,
  String? liteRtLmManifest,
  void Function(Directory)? mutate,
}) async {
  final dir = await Directory.systemTemp.createTemp(
    'llamadart_apple_consumer_',
  );
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  final consumer = workspaceMember
      ? Directory(path.join(dir.path, 'app'))
      : dir;
  await consumer.create(recursive: true);
  final pubspec = File(path.join(consumer.path, 'pubspec.yaml'));
  await pubspec.writeAsString('''
name: llamadart_apple_consumer
publish_to: none

environment:
  sdk: ^3.10.7
  flutter: ^3.38.0

dependencies:
  llamadart: ^0.8.22
  flutter:
    sdk: flutter
${dependenciesYaml.trimRight()}
${dependencies.map((dependency) => '  $dependency: ^0.0.17').join('\n')}
''');

  final packageEntries = <Map<String, String>>[];
  if (dependencies.contains('llamadart_llama_cpp_flutter') &&
      !missingConfiguration) {
    final companion = Directory(path.join(dir.path, 'resolved companion'));
    await companion.create();
    await File(path.join(companion.path, 'pubspec.yaml')).writeAsString(
      'name: llamadart_llama_cpp_flutter\nversion: $companionVersion\n',
    );
    final manifest = File(
      path.join(
        companion.path,
        'darwin',
        'llamadart_llama_cpp_flutter',
        'Package.swift',
      ),
    );
    await manifest.parent.create(recursive: true);
    var source =
        File(
          'packages/llamadart_llama_cpp_flutter/'
          'darwin/llamadart_llama_cpp_flutter/Package.swift',
        ).readAsStringSync().replaceFirst(
          'let llamaCppTag = "${_readPinnedConst('llamaCppTag')}"',
          'let llamaCppTag = "${companionTag ?? _readPinnedConst('llamaCppTag')}"',
        );
    final checksum =
        companionChecksum ??
        llamaCppCompatibleAppleCompanionChecksums[companionTag];
    if (checksum != null) {
      source = source.replaceFirst(
        RegExp(r'checksum: "[0-9a-f]{64}"'),
        'checksum: "$checksum"',
      );
    }
    await manifest.writeAsString(source);
    if (localArtifacts) {
      await Directory(path.join(manifest.parent.path, 'Artifacts')).create();
    }
    final entry = {
      'name': 'llamadart_llama_cpp_flutter',
      'rootUri': '../resolved%20companion',
    };
    packageEntries.addAll([entry, if (duplicateCompanion) entry]);
  }
  if (dependencies.contains('llamadart_litert_lm_flutter') &&
      resolveLiteRtLmCompanion &&
      !missingConfiguration) {
    final companion = Directory(
      path.join(dir.path, 'resolved litert companion'),
    );
    final manifest = File(
      path.join(
        companion.path,
        'darwin',
        'llamadart_litert_lm_flutter',
        'Package.swift',
      ),
    );
    await manifest.parent.create(recursive: true);
    await File(
      path.join(companion.path, 'pubspec.yaml'),
    ).writeAsString('name: llamadart_litert_lm_flutter\nversion: 0.0.14\n');
    await manifest.writeAsString(
      liteRtLmManifest ?? _liteRtLmCompanionManifest(),
    );
    packageEntries.add({
      'name': 'llamadart_litert_lm_flutter',
      'rootUri': '../resolved%20litert%20companion',
    });
  }
  if (packageEntries.isNotEmpty) {
    final config = File(
      path.join(dir.path, '.dart_tool', 'package_config.json'),
    );
    await config.parent.create();
    await config.writeAsString(
      jsonEncode({'configVersion': 2, 'packages': packageEntries}),
    );
  }
  mutate?.call(dir);

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
    "\\bLiteRtLmBundleSpec\\(\\s*'$escapedKey',[\\s\\S]*?"
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
    "\\bLiteRtLmBundleSpec\\(\\s*'$escapedKey',[\\s\\S]*?"
    "sha256:\\s*'([0-9a-f]{64})',",
  ).firstMatch(source);
  expect(match, isNotNull, reason: bundleKey);
}

const List<String> _androidLiteRtLibraries = [
  'libGemmaModelConstraintProvider.so',
  'libLiteRtGpuAccelerator.so',
  'libLiteRtLm.so',
  'libLiteRtOpenClAccelerator.so',
  'libLiteRtWebGpuAccelerator.so',
  'libwebgpu_dawn.so',
];

const List<String> _iosLiteRtLibraries = ['LiteRtLm', 'CLiteRTLM'];

const List<String> _iosLiteRtAssetNames = [
  'litert_lm_LiteRtLm',
  'litert_lm_CLiteRTLM',
];

const List<String> _macosArm64LiteRtLibraries = [
  'libCLiteRTLM_mac.dylib',
  'libGemmaModelConstraintProvider.dylib',
  'libLiteRtLm.dylib',
  'libwebgpu_dawn.dylib',
];

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
