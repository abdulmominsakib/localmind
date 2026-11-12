@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:llamadart/src/hook/native_release_pins.dart';

import '../../../hook/build.dart' as build_hook;
import '../../support/hook_project_root.dart';
import '../../support/hooks_runner_layout.dart';
import '../../support/native_bundle_cache.dart';

const _stableDiffusionAssetId = 'package:llamadart/stable_diffusion';
const _primaryAssetId = 'package:llamadart/llamadart';
const _liteRtLmAssetIdPrefix = 'package:llamadart/litert_lm_';

void main() {
  final project = HookProjectRoot.create();
  final nativeBundlesRoot = project.resolve(
    '.dart_tool/llamadart/native_bundles_v2/$llamaCppTag',
  );
  final stableDiffusionRoot = project.resolve(
    '.dart_tool/llamadart/stable_diffusion/$stableDiffusionVersion',
  );

  Directory nativeBundle(String bundle) =>
      Directory('$nativeBundlesRoot/$bundle/extracted');
  Directory stableDiffusionBundle(String bundle) =>
      Directory('$stableDiffusionRoot/$bundle');

  final nativeBundles = {
    'linux-x64': const [
      'libllamadart.so',
      'libllama.so',
      'libggml.so',
      'libggml-base.so',
      'libggml-cpu.so',
      'libggml-vulkan.so',
    ],
    'android-x64': const [
      'libllamadart.so',
      'libllama.so',
      'libggml.so',
      'libggml-base.so',
      'libggml-cpu.so',
    ],
    'macos-arm64': const ['libllamadart.dylib'],
    'ios-x86_64-sim': const ['libllamadart.dylib'],
    'windows-arm64': const [
      'llamadart-windows-arm64.dll',
      'llama-windows-arm64.dll',
      'ggml-windows-arm64.dll',
      'ggml-base-windows-arm64.dll',
      'ggml-cpu-windows-arm64.dll',
    ],
  };
  final stableDiffusionBundles = {
    for (final spec in stableDiffusionBundleSpecs)
      if (const {
        'linux-x64',
        'linux-x64-vulkan',
        'macos-arm64',
        'ios-arm64',
        'ios-x64-sim',
      }.contains(spec.bundle))
        spec.bundle: spec.requiredLibraries.single,
  };
  final liteRtLmBundles = {
    'linux-x64': Directory(
      project.resolve(
        '.dart_tool/llamadart/litert_lm/$liteRtLmVersion/linux/x64',
      ),
    ),
    'android-x64': Directory(
      project.resolve(
        '.dart_tool/llamadart/litert_lm/$liteRtLmVersion/android/x64',
      ),
    ),
    'macos-arm64': Directory(
      project.resolve(
        '.dart_tool/llamadart/litert_lm/$liteRtLmVersion/macos/arm64',
      ),
    ),
  };
  setUp(() async {
    for (final MapEntry(key: bundle, value: libraries)
        in nativeBundles.entries) {
      await _writeLibraries(nativeBundle(bundle), {
        for (final library in libraries) library: 'fake-$library',
      });
      await markExtractedBundle(nativeBundle(bundle));
    }
    for (final MapEntry(key: bundle, value: library)
        in stableDiffusionBundles.entries) {
      await _writeLibraries(stableDiffusionBundle(bundle), {
        library: 'fake-sd-$bundle',
      });
    }
    for (final MapEntry(key: bundle, value: directory)
        in liteRtLmBundles.entries) {
      await _writeLibraries(directory, {
        for (final library
            in liteRtLmBundleSpecs
                .singleWhere((spec) => spec.bundle == bundle)
                .requiredLibraries)
          library: 'fake-$library',
      });
    }
  });

  tearDownAll(project.delete);

  test('unset, empty, unrecognised and both selections never bundle '
      'stable_diffusion', () async {
    final vulkanCache = stableDiffusionBundle('linux-x64-vulkan');
    await vulkanCache.delete(recursive: true);
    for (final defines in <Map<String, Object?>>[
      {},
      {'llamadart_native_runtimes': <String>[]},
      {
        'llamadart_native_runtimes': ['onnx'],
      },
      {'llamadart_native_runtimes': 'both'},
      {
        'llamadart_native_runtimes': {
          'platforms': {'android': 'all'},
        },
      },
    ]) {
      final log = await _captureHookLog(
        () => project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.linux,
          targetArchitecture: Architecture.x64,
          userDefines: _userDefines(defines),
          check: (_, output) {
            final ids = _codeAssetIds(output);
            expect(ids, contains(_primaryAssetId), reason: '$defines');
            expect(
              ids.any((id) => id.startsWith(_liteRtLmAssetIdPrefix)),
              isTrue,
              reason: '$defines',
            );
            expect(ids, isNot(contains(_stableDiffusionAssetId)));
          },
        ),
      );
      expect(
        log,
        contains(endsWith('Selected native runtimes: llama_cpp, litert_lm.')),
        reason: '$defines',
      );
      expect(
        vulkanCache.existsSync(),
        isFalse,
        reason: 'nothing may be downloaded without opting in: $defines',
      );
    }
  });

  test('all bundles every runtime a target publishes and skips the rest with '
      'a warning', () async {
    const liteRtLmSkipped = 'LiteRT-LM runtime is not available for';
    const stableDiffusionSkipped = 'stable_diffusion runtime is not available';
    const targets = [
      (
        os: OS.linux,
        architecture: Architecture.x64,
        simulator: false,
        bundle: 'linux-x64',
        liteRtLm: true,
        stableDiffusion: true,
      ),
      (
        os: OS.android,
        architecture: Architecture.x64,
        simulator: false,
        bundle: 'android-x64',
        liteRtLm: true,
        stableDiffusion: false,
      ),
      (
        os: OS.iOS,
        architecture: Architecture.x64,
        simulator: true,
        bundle: 'ios-x86_64-sim',
        liteRtLm: false,
        stableDiffusion: true,
      ),
      (
        os: OS.windows,
        architecture: Architecture.arm64,
        simulator: false,
        bundle: 'windows-arm64',
        liteRtLm: false,
        stableDiffusion: false,
      ),
    ];
    for (final (runtimes, selectsImages) in const <(Object?, bool)>[
      ('all', true),
      (['all'], true),
      (['all', 'stable_diffusion'], true),
      ({'runtimes': 'all'}, true),
      ('both', false),
      (null, false),
    ]) {
      for (final target in targets) {
        final reason = '${target.bundle} $runtimes';
        final stableDiffusion = selectsImages && target.stableDiffusion;
        final log = await _captureHookLog(
          () => project.testCodeBuildHook(
            mainMethod: build_hook.main,
            targetOS: target.os,
            targetArchitecture: target.architecture,
            targetAndroidNdkApi: target.os == OS.android ? 30 : null,
            targetIOSSdk: target.simulator ? IOSSdk.iPhoneSimulator : null,
            userDefines: _userDefines({'llamadart_native_runtimes': ?runtimes}),
            check: (_, output) {
              final ids = _codeAssetIds(output);
              expect(ids, contains(_primaryAssetId), reason: reason);
              expect(
                ids.any((id) => id.startsWith(_liteRtLmAssetIdPrefix)),
                target.liteRtLm,
                reason: reason,
              );
              expect(
                ids.contains(_stableDiffusionAssetId),
                stableDiffusion,
                reason: reason,
              );
            },
          ),
        );
        final warnings = log.where((line) => line.startsWith('WARNING: '));
        expect(
          warnings.any(
            (line) => line.contains('$liteRtLmSkipped ${target.bundle}'),
          ),
          !target.liteRtLm,
          reason: reason,
        );
        expect(
          warnings.any(
            (line) =>
                line.contains('$stableDiffusionSkipped for ${target.bundle}'),
          ),
          selectsImages && !target.stableDiffusion,
          reason: reason,
        );
        expect(
          log,
          contains(
            endsWith(
              'Selected native runtimes: ${['llama_cpp', if (target.liteRtLm) 'litert_lm', if (stableDiffusion) 'stable_diffusion'].join(', ')}.',
            ),
          ),
          reason: reason,
        );
      }
    }
  });

  test('all beside a Flutter Edge AI engine drops only LiteRT-LM', () async {
    final layout = await flutterEdgeAiWorkspace();
    addTearDown(layout.delete);
    final run = await runCodeBuildHook(
      project: project,
      hookMain: build_hook.main,
      targetOS: OS.linux,
      targetArchitecture: Architecture.x64,
      layout: layout,
      userDefines: layout.userDefines({'llamadart_native_runtimes': 'all'}),
    );
    expect(
      run.assets.keys,
      containsAll([_primaryAssetId, _stableDiffusionAssetId]),
    );
    expect(
      run.assets.keys.where((id) => id.startsWith(_liteRtLmAssetIdPrefix)),
      isEmpty,
    );
  });

  test('all under an exact bundle key still skips an unpublished '
      'stable_diffusion', () async {
    await project.testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.android,
      targetArchitecture: Architecture.x64,
      targetAndroidNdkApi: 30,
      userDefines: _userDefines({
        'llamadart_native_runtimes': {
          'platforms': {'android-x64': 'all'},
        },
      }),
      check: (_, output) {
        final ids = _codeAssetIds(output);
        expect(ids, contains(_primaryAssetId));
        expect(ids, isNot(contains(_stableDiffusionAssetId)));
      },
    );
  });

  for (final (os, sdk, bundle) in const [
    (OS.iOS, IOSSdk.iPhoneOS, 'ios-arm64'),
    (OS.macOS, null, 'macos-arm64'),
  ]) {
    for (final companion in const [false, true]) {
      for (final (runtimes, explicit) in const <(List<String>, bool)>[
        (['all'], false),
        (['all', 'stable_diffusion'], true),
      ]) {
        test('Flutter $bundle with $runtimes '
            '${companion ? 'and' : 'without'} the stable_diffusion '
            'companion', () async {
          final defines = await _flutterAppleApp(
            companions: [
              _llamaCppCompanionName,
              if (companion) _stableDiffusionCompanionName,
            ],
            defines: {'llamadart_native_runtimes': runtimes},
          );
          late final List<String> log;
          final stderrLines = await _captureStderr(() async {
            log = await _captureHookLog(
              () => project.testCodeBuildHook(
                mainMethod: build_hook.main,
                targetOS: os,
                targetArchitecture: Architecture.arm64,
                targetIOSSdk: sdk,
                userDefines: defines,
                check: (_, output) {
                  final ids = _codeAssetIds(output);
                  expect(ids, contains(_primaryAssetId));
                  expect(
                    ids.contains(_stableDiffusionAssetId),
                    companion || explicit,
                  );
                  if (companion || explicit) {
                    expect(
                      _stableDiffusionAsset(output).linkMode,
                      companion
                          ? isA<LookupInProcess>()
                          : isA<DynamicLoadingBundled>(),
                    );
                  }
                },
              ),
            );
          });
          final skipped = log.where(
            (line) =>
                line.startsWith('WARNING: ') &&
                line.contains('stable_diffusion is only implied by `all`'),
          );
          final relayed = stderrLines.where(
            (line) => line.contains('stable_diffusion is only implied'),
          );
          if (companion || explicit) {
            expect(skipped, isEmpty);
            expect(relayed, isEmpty);
          } else {
            expect(skipped.single, endsWith('$_impliedSkipWarning ($bundle)'));
            expect(relayed.single, 'warning: llamadart: $_impliedSkipWarning');
          }
          expect(
            stderrLines.any((line) => line.contains('MinimumOSVersion')),
            os == OS.iOS && explicit && !companion,
          );
        });
      }
    }
  }

  test('a Flutter Apple app without any companion skips a stable_diffusion '
      'that all only implies', () async {
    final defines = await _flutterAppleApp(
      companions: const [],
      defines: {'llamadart_native_runtimes': 'all'},
    );
    late final List<String> log;
    final stderrLines = await _captureStderr(() async {
      log = await _captureHookLog(
        () => project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.iOS,
          targetArchitecture: Architecture.x64,
          targetIOSSdk: IOSSdk.iPhoneSimulator,
          userDefines: defines,
          check: (_, output) {
            expect(_codeAssetIds(output), {_primaryAssetId});
          },
        ),
      );
    });
    expect(log, contains(endsWith('$_impliedSkipWarning (ios-x86_64-sim)')));
    expect(stderrLines, ['warning: llamadart: $_impliedSkipWarning']);
    expect(log, contains(endsWith('Selected native runtimes: llama_cpp.')));
  });

  test(
    'relays the implied LiteRT-LM drop beside Flutter Edge AI to stderr',
    () async {
      final layout = await flutterEdgeAiWorkspace();
      addTearDown(layout.delete);
      late final HookRun run;
      final stderrLines = await _captureStderr(() async {
        run = await runCodeBuildHook(
          project: project,
          hookMain: build_hook.main,
          targetOS: OS.linux,
          targetArchitecture: Architecture.x64,
          layout: layout,
          userDefines: layout.userDefines(),
        );
      });
      final dropped = run.warnings.singleWhere(
        (warning) => warning.startsWith('Leaving the LiteRT-LM runtime out'),
      );
      expect(stderrLines, ['warning: llamadart: $dropped']);
    },
  );

  test('Linux bundles the Vulkan archive with default backends', () async {
    await project.testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.linux,
      targetArchitecture: Architecture.x64,
      userDefines: _userDefines({
        'llamadart_native_runtimes': ['llama_cpp', 'stable_diffusion'],
      }),
      check: (_, output) {
        expect(_codeAssetIds(output), contains(_primaryAssetId));
        final asset = _stableDiffusionAsset(output);
        expect(asset.linkMode, isA<DynamicLoadingBundled>());
        final file = File.fromUri(asset.file!);
        expect(path.basename(file.path), 'libstable-diffusion.so');
        expect(file.readAsStringSync(), 'fake-sd-linux-x64-vulkan');
      },
    );
  });

  test('Linux bundles the CPU archive when Vulkan is not selected', () async {
    await project.testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.linux,
      targetArchitecture: Architecture.x64,
      userDefines: _userDefines({
        'llamadart_native_runtimes': 'llama_cpp,stable-diffusion',
        'llamadart_native_backends': {
          'platforms': {'linux': 'cpu'},
        },
      }),
      check: (_, output) {
        final assets = output.assets.encodedAssets
            .where((asset) => asset.isCodeAsset)
            .map((asset) => asset.asCodeAsset);
        expect(
          assets.map((asset) => path.basename(asset.file!.toFilePath())),
          isNot(contains('libggml-vulkan.so')),
        );
        expect(
          File.fromUri(_stableDiffusionAsset(output).file!).readAsStringSync(),
          'fake-sd-linux-x64',
        );
      },
    );
  });

  test('stable_diffusion picks its own build independently of llama.cpp '
      'backends', () async {
    await project.testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.linux,
      targetArchitecture: Architecture.x64,
      userDefines: _userDefines({
        'llamadart_native_runtimes': ['llama_cpp', 'stable_diffusion'],
        'llamadart_stable_diffusion_backends': {
          'platforms': {'linux': 'cpu'},
        },
      }),
      check: (_, output) {
        final assets = output.assets.encodedAssets
            .where((asset) => asset.isCodeAsset)
            .map((asset) => asset.asCodeAsset);
        expect(
          assets.map((asset) => path.basename(asset.file!.toFilePath())),
          contains('libggml-vulkan.so'),
          reason: 'llama.cpp keeps its default Vulkan backend',
        );
        expect(
          File.fromUri(_stableDiffusionAsset(output).file!).readAsStringSync(),
          'fake-sd-linux-x64',
        );
      },
    );
  });

  test('stable_diffusion can be bundled without llama.cpp', () async {
    await project.testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.macOS,
      targetArchitecture: Architecture.arm64,
      userDefines: _userDefines({
        'llamadart_native_runtimes': ['stable_diffusion'],
      }),
      check: (_, output) {
        expect(_codeAssetIds(output), {_stableDiffusionAssetId});
        final asset = _stableDiffusionAsset(output);
        expect(asset.linkMode, isA<DynamicLoadingBundled>());
        expect(
          File.fromUri(asset.file!).readAsStringSync(),
          'fake-sd-macos-arm64',
        );
      },
    );
  });

  test(
    'an unpublished target drops a broadly named stable_diffusion',
    () async {
      for (final defines in <Map<String, Object?>>[
        {
          'llamadart_native_runtimes': ['llama_cpp', 'stable_diffusion'],
        },
        {
          'llamadart_native_runtimes': {
            'platforms': {
              'android': ['llama_cpp', 'stable_diffusion'],
            },
          },
        },
      ]) {
        await project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.android,
          targetArchitecture: Architecture.x64,
          targetAndroidNdkApi: 30,
          userDefines: _userDefines(defines),
          check: (_, output) {
            final ids = _codeAssetIds(output);
            expect(ids, contains(_primaryAssetId), reason: '$defines');
            expect(ids, isNot(contains(_stableDiffusionAssetId)));
          },
        );
      }

      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.android,
        targetArchitecture: Architecture.x64,
        targetAndroidNdkApi: 30,
        userDefines: _userDefines({
          'llamadart_native_runtimes': ['stable_diffusion'],
        }),
        check: (_, output) {
          expect(_codeAssetIds(output), isEmpty);
        },
      );
    },
  );

  test('an unpublished target rejects a bundle-scoped request', () async {
    var emitted = false;
    await expectLater(
      project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.android,
        targetArchitecture: Architecture.x64,
        targetAndroidNdkApi: 30,
        userDefines: _userDefines({
          'llamadart_native_runtimes': {
            'platforms': {
              'android-x64': ['llama_cpp', 'stable_diffusion'],
            },
          },
        }),
        check: (_, _) => emitted = true,
      ),
      throwsA(
        predicate(
          (error) => error.toString().contains(
            'stable_diffusion runtime is not available for android-x64',
          ),
        ),
      ),
    );
    expect(emitted, isFalse);
  });

  test(
    'Flutter Apple builds without the stable_diffusion companion bundle it',
    () async {
      final consumer = await Directory.systemTemp.createTemp(
        'llamadart_sd_apple_consumer_',
      );
      addTearDown(() => consumer.delete(recursive: true));
      final pubspec = File(path.join(consumer.path, 'pubspec.yaml'))
        ..writeAsStringSync('''
name: llamadart_sd_apple_consumer
publish_to: none

environment:
  sdk: ^3.10.7

dependencies:
  flutter:
    sdk: flutter
  llamadart: ^0.9.0
  llamadart_litert_lm_flutter: ^0.0.17
''');

      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        targetIOSSdk: IOSSdk.iPhoneOS,
        userDefines: PackageUserDefines(
          workspacePubspec: PackageUserDefinesSource(
            defines: {
              'llamadart_native_runtimes': ['llama_cpp', 'stable_diffusion'],
            },
            basePath: pubspec.uri,
          ),
        ),
        check: (_, output) {
          expect(_codeAssetIds(output), {_stableDiffusionAssetId});
          final asset = _stableDiffusionAsset(output);
          expect(asset.linkMode, isA<DynamicLoadingBundled>());
          expect(
            File.fromUri(asset.file!).readAsStringSync(),
            'fake-sd-ios-arm64',
          );
        },
      );
    },
  );

  test('Flutter iOS hook bundling raises an Xcode warning that App Store '
      'upload needs the companion', () async {
    final defines = await _flutterAppleApp(
      companions: const [],
      defines: {
        'llamadart_native_runtimes': ['stable_diffusion'],
      },
    );
    final warnings = await _captureStderr(
      () => project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        targetIOSSdk: IOSSdk.iPhoneOS,
        userDefines: defines,
        check: (_, output) {
          expect(
            _stableDiffusionAsset(output).linkMode,
            isA<DynamicLoadingBundled>(),
          );
        },
      ),
    );
    expect(
      warnings,
      contains(
        allOf(
          startsWith('warning: '),
          contains('MinimumOSVersion 13.0'),
          contains(_stableDiffusionCompanionName),
        ),
      ),
    );
  });

  test(
    'the stable_diffusion companion selects and links it in process',
    () async {
      final defines = await _flutterAppleApp(
        companions: const [_stableDiffusionCompanionName],
      );
      final warnings = await _captureStderr(
        () => project.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.macOS,
          targetArchitecture: Architecture.arm64,
          userDefines: defines,
          check: (input, output) {
            expect(_codeAssetIds(output), {
              _primaryAssetId,
              _stableDiffusionAssetId,
            });
            final asset = _stableDiffusionAsset(output);
            expect(asset.linkMode, isA<LookupInProcess>());
            expect(asset.file, isNull);
            // llama.cpp has no companion here, so it stays on the hook.
            final llama = output.assets.encodedAssets
                .map((asset) => asset.asCodeAsset)
                .singleWhere((asset) => asset.id == _primaryAssetId);
            expect(llama.linkMode, isA<DynamicLoadingBundled>());
            expect(
              output.dependencies.any(
                (uri) => uri.path.endsWith('Package.swift'),
              ),
              isTrue,
            );
          },
        ),
      );
      expect(warnings, isEmpty);
    },
  );

  test(
    'both companions link llama.cpp and stable_diffusion in process',
    () async {
      final defines = await _flutterAppleApp(
        companions: const [
          _llamaCppCompanionName,
          _stableDiffusionCompanionName,
        ],
        defines: {
          'llamadart_native_runtimes': ['llama_cpp'],
        },
      );
      await project.testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.x64,
        targetIOSSdk: IOSSdk.iPhoneSimulator,
        userDefines: defines,
        check: (input, output) {
          final assets = output.assets.encodedAssets
              .map((asset) => asset.asCodeAsset)
              .toList();
          expect(assets.map((asset) => asset.id).toSet(), {
            _primaryAssetId,
            _stableDiffusionAssetId,
          });
          expect(
            assets.every((asset) => asset.linkMode is LookupInProcess),
            isTrue,
          );
          expect(
            Directory(
              path.join(input.outputDirectory.toFilePath(), 'llamadart_bin'),
            ).existsSync(),
            isFalse,
          );
        },
      );
    },
  );

  for (final scenario in [
    'old-pin',
    'unknown-rebuild',
    'wrong-checksum',
    'local-artifacts',
    'hardcoded-url',
    'missing-resolution',
  ]) {
    test(
      'the stable_diffusion companion rejects $scenario before lookup',
      () async {
        final defines = await _flutterAppleApp(
          companions: const [_stableDiffusionCompanionName],
          localArtifacts: scenario == 'local-artifacts',
          resolve: scenario != 'missing-resolution',
          editManifest: (manifest) => switch (scenario) {
            'old-pin' => manifest.replaceFirst(
              'let stableDiffusionTag = "$stableDiffusionReleaseTag"',
              'let stableDiffusionTag = "v0.1.1"',
            ),
            'unknown-rebuild' => manifest.replaceFirst(
              'let stableDiffusionTag = "$stableDiffusionReleaseTag"',
              'let stableDiffusionTag = "v0.2.0-5"',
            ),
            'wrong-checksum' => manifest.replaceFirst(
              stableDiffusionAppleCompanionChecksums[stableDiffusionReleaseTag]!,
              '0' * 64,
            ),
            'hardcoded-url' => manifest.replaceFirst(
              r'url: "https://github.com/\(repository)/releases/download/\(tag)/\(artifactName)"',
              'url: "https://example.com/stable_diffusion.zip"',
            ),
            _ => manifest,
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
                'Incompatible Apple stable_diffusion companion',
              ),
            ),
          ),
        );
        expect(emitted, isFalse);
      },
    );
  }

  // v0.3.0 grew sd_ctx_params_t: the bindings would overrun the
  // allocation of a v0.2.0-4 runtime. The v0.3.0 runtime aborts on FP8
  // weights on Metal, which the image preflight admits on the pinned runtime.
  for (final (tag, checksum) in [
    (
      'v0.2.0-4',
      '24b5fe8b0203ab7e35eb3e103fe18305aff82cfe57376a49d128135abe89d00b',
    ),
    (
      'v0.3.0',
      '3b83a0c21a00f6418890b679ea45b00c20d012da0a57fe989635b793e09f096a',
    ),
  ]) {
    test('rejects a locked companion pinning the published $tag '
        'XCFramework', () async {
      final defines = await _flutterAppleApp(
        companions: const [_stableDiffusionCompanionName],
        editManifest: (manifest) => manifest
            .replaceFirst(
              'let stableDiffusionTag = "$stableDiffusionReleaseTag"',
              'let stableDiffusionTag = "$tag"',
            )
            .replaceFirst(
              stableDiffusionAppleCompanionChecksums[stableDiffusionReleaseTag]!,
              checksum,
            ),
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
            (error) =>
                error.toString().contains(
                  'Incompatible Apple stable_diffusion companion',
                ) &&
                error.toString().contains(
                  'does not uniquely pin the required native runtime '
                  '$stableDiffusionReleaseTag',
                ),
          ),
        ),
      );
    });
  }

  // A core names the first pinning companion only within that companion's
  // minor, and release prep moves both to a new minor together.
  final companionMinor = stableDiffusionAppleCompanionVersion.substring(
    0,
    stableDiffusionAppleCompanionVersion.lastIndexOf('.'),
  );
  for (final core in ['$companionMinor.0', '$companionMinor.1']) {
    const requirement =
        'Depend on `llamadart_stable_diffusion_flutter: '
        '^$stableDiffusionAppleCompanionVersion`';
    test('core $core: the stable_diffusion companion rejection names the '
        'first compatible companion release', () async {
      final defines = await _flutterAppleApp(
        companions: const [_stableDiffusionCompanionName],
        editManifest: (manifest) => manifest.replaceFirst(
          'let stableDiffusionTag = "$stableDiffusionReleaseTag"',
          'let stableDiffusionTag = "v0.1.1"',
        ),
      );
      final coreRoot = HookProjectRoot.create(coreVersion: core);
      addTearDown(coreRoot.delete);
      await expectLater(
        coreRoot.testCodeBuildHook(
          mainMethod: build_hook.main,
          targetOS: OS.iOS,
          targetArchitecture: Architecture.arm64,
          targetIOSSdk: IOSSdk.iPhoneOS,
          userDefines: defines,
          check: (_, _) => fail('Must not emit in-process assets'),
        ),
        throwsA(predicate((error) => error.toString().contains(requirement))),
      );
    });
  }
}

const _impliedSkipWarning =
    'stable_diffusion is only implied by `all` in llamadart_native_runtimes, '
    'so this Flutter iOS/macOS build leaves the image runtime out: '
    'llamadart_stable_diffusion_flutter is not a dependency. Add that package '
    'to link the runtime through Swift Package Manager, or name '
    'stable_diffusion to bundle it through the hook.';

const _llamaCppCompanionName = 'llamadart_llama_cpp_flutter';
const _stableDiffusionCompanionName = 'llamadart_stable_diffusion_flutter';

/// A Flutter app depending on [companions], each resolved in its
/// `package_config.json` to a copy of the maintained package.
Future<PackageUserDefines> _flutterAppleApp({
  required List<String> companions,
  Map<String, Object?> defines = const {},
  String Function(String manifest)? editManifest,
  bool localArtifacts = false,
  bool resolve = true,
}) async {
  final app = await Directory.systemTemp.createTemp(
    'llamadart_sd_flutter_app_',
  );
  addTearDown(() => app.delete(recursive: true));
  final pubspec = File(path.join(app.path, 'pubspec.yaml'))
    ..writeAsStringSync('''
name: llamadart_sd_flutter_app
publish_to: none

environment:
  sdk: ^3.10.7

dependencies:
  flutter:
    sdk: flutter
  llamadart: ^0.9.0
${companions.map((name) => '  $name: any').join('\n')}
''');
  final entries = <Map<String, String>>[];
  for (final name in companions) {
    final root = Directory(path.join(app.path, 'resolved', name));
    final manifest = File(
      path.join(root.path, 'darwin', name, 'Package.swift'),
    );
    await manifest.parent.create(recursive: true);
    File(
      path.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: $name\nversion: 0.0.1\n');
    final source = File(
      'packages/$name/darwin/$name/Package.swift',
    ).readAsStringSync();
    manifest.writeAsStringSync(
      name == _stableDiffusionCompanionName && editManifest != null
          ? editManifest(source)
          : source,
    );
    if (localArtifacts) {
      await Directory(path.join(manifest.parent.path, 'Artifacts')).create();
    }
    entries.add({'name': name, 'rootUri': '../resolved/$name'});
  }
  if (resolve) {
    final config = File(
      path.join(app.path, '.dart_tool', 'package_config.json'),
    );
    await config.parent.create();
    config.writeAsStringSync(
      jsonEncode({'configVersion': 2, 'packages': entries}),
    );
  }
  return PackageUserDefines(
    workspacePubspec: PackageUserDefinesSource(
      defines: defines,
      basePath: pubspec.uri,
    ),
  );
}

/// The records the hook logs while [body] runs, as `LEVEL: time: message`.
Future<List<String>> _captureHookLog(Future<void> Function() body) async {
  final lines = <String>{};
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, line) => lines.add(line),
    ),
  );
  return lines.toList();
}

/// Lines the hook writes to stderr while [body] runs; Flutter relays them
/// into the Xcode build, where `warning:` lines become build warnings.
Future<List<String>> _captureStderr(Future<void> Function() body) async {
  final sink = _LineSink();
  await IOOverrides.runZoned(body, stderr: () => sink);
  return sink.lines;
}

final class _LineSink implements Stdout {
  final List<String> lines = [];

  @override
  void writeln([Object? object = '']) => lines.add('$object');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

PackageUserDefines _userDefines(Map<String, Object?> defines) =>
    PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: defines,
        basePath: Directory.current.uri,
      ),
    );

Set<String> _codeAssetIds(BuildOutput output) => output.assets.encodedAssets
    .where((asset) => asset.isCodeAsset)
    .map((asset) => asset.asCodeAsset.id)
    .toSet();

CodeAsset _stableDiffusionAsset(BuildOutput output) => output
    .assets
    .encodedAssets
    .where((asset) => asset.isCodeAsset)
    .map((asset) => asset.asCodeAsset)
    .singleWhere((asset) => asset.id == _stableDiffusionAssetId);

Future<void> _writeLibraries(
  Directory directory,
  Map<String, String> contents,
) async {
  if (directory.existsSync()) {
    await directory.delete(recursive: true);
  }
  await directory.create(recursive: true);
  for (final MapEntry(key: name, value: content) in contents.entries) {
    await File(path.join(directory.path, name)).writeAsString(content);
  }
}
