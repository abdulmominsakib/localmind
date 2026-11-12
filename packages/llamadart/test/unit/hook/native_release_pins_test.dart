@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/hook/native_bundle_config.dart';
import 'package:llamadart/src/hook/native_release_manifest.dart';
import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:test/test.dart';

void main() {
  final sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

  test('llama.cpp pins the approved v0.9.0 release', () {
    expect(llamaCppTag, 'v0.9.0');
  });

  test('llama.cpp tag follows the native release tag grammar', () {
    expect(isValidNativeReleaseTag(llamaCppTag), isTrue, reason: llamaCppTag);
  });

  test('Apple llama.cpp requires the matching repaired runtime', () {
    // Older artifacts lack this release's ARM F16 accumulation fix, even when
    // their exported ABI is usable.
    expect(llamaCppCompatibleAppleCompanionTags, isEmpty);
    expect(llamaCppCompatibleAppleCompanionChecksums, {
      llamaCppTag:
          'b0005b1da364f9ea4345218b8d53d78d6de888f301c6defb44b08321e136ac2e',
    });
    final manifest = File(
      'packages/llamadart_llama_cpp_flutter/darwin/'
      'llamadart_llama_cpp_flutter/Package.swift',
    ).readAsStringSync();
    expect(manifest, contains('let llamaCppTag = "$llamaCppTag"'));
    expect(
      manifest,
      contains(
        'checksum: "b0005b1da364f9ea4345218b8d53d78d6de888f301c6defb44b08321e136ac2e"',
      ),
    );
  });

  test('Apple companion version is the first release pinning llamaCppTag', () {
    const companion = 'packages/llamadart_llama_cpp_flutter';
    final version = RegExp(
      r'^version: (\d+)\.(\d+)\.(\d+)$',
      multiLine: true,
    ).firstMatch(File('$companion/pubspec.yaml').readAsStringSync())!;
    final changelog = File('$companion/CHANGELOG.md').readAsStringSync();
    final sections = RegExp(
      r'^## (.+)$',
      multiLine: true,
    ).allMatches(changelog).toList();
    String? firstPinning;
    for (final (index, section) in sections.indexed) {
      final end = index + 1 < sections.length
          ? sections[index + 1].start
          : changelog.length;
      if (changelog
          .substring(section.end, end)
          .contains('leehack/llamadart-native@$llamaCppTag`')) {
        firstPinning = section.group(1);
      }
    }
    final expected = firstPinning == 'Unreleased'
        ? '${version.group(1)}.${version.group(2)}.'
              '${int.parse(version.group(3)!) + 1}'
        : firstPinning;
    expect(llamaCppAppleCompanionVersion, expected);
  });

  test('llama.cpp pins a sha256 for exactly the bundles the hook selects', () {
    final selectable = <String>{
      for (final os in OS.values)
        for (final arch in Architecture.values)
          for (final isIosSimulator in const [false, true])
            ?resolveNativeBundleSpec(
              os: os,
              arch: arch,
              isIosSimulator: isIosSimulator,
            )?.bundle,
    };
    expect(llamaCppBundleSha256.keys.toSet(), selectable);
    for (final MapEntry(key: bundle, value: digest)
        in llamaCppBundleSha256.entries) {
      expect(digest, matches(sha256Pattern), reason: bundle);
    }
  });

  test('llama.cpp pins a hook contract this hook supports', () {
    expect(
      supportedNativeHookContractVersions,
      contains(llamaCppHookContractVersion),
    );
  });

  test('llama.cpp backend sidecars extend a pinned bundle once each', () {
    final keys = <String>{};
    for (final spec in llamaCppBackendSidecarSpecs) {
      expect(llamaCppBundleSha256, contains(spec.bundle), reason: spec.archive);
      expect(spec.archive, startsWith('${spec.bundle}-'));
      expect(llamaCppBundleSha256, isNot(contains(spec.archive)));
      expect(spec.sha256, matches(sha256Pattern), reason: spec.archive);
      expect(keys.add('${spec.bundle}/${spec.backend}'), isTrue);
    }
    if (llamaCppHookContractVersion < 2) {
      expect(llamaCppBackendSidecarSpecs, isEmpty);
    }
  });

  test('LiteRT-LM cache version is the release tag without its v prefix', () {
    expect(liteRtLmReleaseTag, startsWith('v'));
    expect(liteRtLmVersion, liteRtLmReleaseTag.substring(1));
  });

  test('LiteRT-LM bundle specs are unique and pin a sha256 each', () {
    final bundles = liteRtLmBundleSpecs.map((spec) => spec.bundle).toList();
    expect(bundles.toSet(), hasLength(bundles.length));
    for (final spec in liteRtLmBundleSpecs) {
      expect(spec.bundle, matches(RegExp(r'^[a-z]+-[a-z0-9]+(-sim)?$')));
      expect(spec.sha256, matches(sha256Pattern), reason: spec.bundle);
      expect(spec.requiredLibraries, isNotEmpty, reason: spec.bundle);
    }
  });

  test('LiteRT-LM bundle specs cover every hook-selectable bundle', () {
    expect(
      liteRtLmBundleSpecs.map((spec) => spec.bundle),
      unorderedEquals(const [
        'android-arm64',
        'android-x64',
        'ios-arm64',
        'ios-arm64-sim',
        'macos-arm64',
        'linux-arm64',
        'linux-x64',
        'windows-x64',
      ]),
    );
  });

  test('iOS inventory excludes the provider and the Metal accelerator', () {
    for (final bundle in const ['ios-arm64', 'ios-arm64-sim']) {
      final spec = liteRtLmBundleSpecs.singleWhere(
        (spec) => spec.bundle == bundle,
      );
      expect(
        spec.requiredLibraries,
        unorderedEquals(const ['CLiteRTLM', 'LiteRtLm']),
        reason: bundle,
      );
    }
    final mac = liteRtLmBundleSpecs.singleWhere(
      (spec) => spec.bundle == 'macos-arm64',
    );
    expect(
      mac.requiredLibraries,
      contains('libGemmaModelConstraintProvider.dylib'),
    );
  });

  test('desktop bundle specs agree with the C API 1.0 required lists', () {
    const desktopBundles = {
      'macos-arm64': Abi.macosArm64,
      'linux-arm64': Abi.linuxArm64,
      'linux-x64': Abi.linuxX64,
      'windows-x64': Abi.windowsX64,
    };
    for (final entry in desktopBundles.entries) {
      final spec = liteRtLmBundleSpecs.singleWhere(
        (spec) => spec.bundle == entry.key,
      );
      expect(
        liteRtLmRequiredLibrariesForAbi(entry.value, cApiV1: true),
        unorderedEquals(spec.requiredLibraries),
        reason: entry.key,
      );
    }
  });

  test(
    'legacy overrides retain their prebuilt accelerator and sampler requirements',
    () {
      const samplers = {
        Abi.macosArm64: [
          'libLiteRt.dylib',
          'libLiteRtMetalAccelerator.dylib',
          'libLiteRtTopKMetalSampler.dylib',
          'libLiteRtTopKWebGpuSampler.dylib',
          'libLiteRtWebGpuAccelerator.dylib',
        ],
        Abi.linuxArm64: ['libLiteRtTopKWebGpuSampler.so'],
        Abi.linuxX64: ['libLiteRtTopKWebGpuSampler.so'],
        Abi.windowsX64: ['libLiteRtTopKWebGpuSampler.dll'],
      };
      // v0.18.x Linux and Windows hosts import the prebuilt libLiteRt that
      // C API 1 hosts from v0.19.1-1 link in.
      const liteRt = {
        Abi.linuxArm64: ['libLiteRt.so'],
        Abi.linuxX64: ['libLiteRt.so'],
        Abi.windowsX64: ['libLiteRt.dll'],
      };
      for (final entry in samplers.entries) {
        final modern = liteRtLmRequiredLibrariesForAbi(entry.key, cApiV1: true);
        expect(
          liteRtLmRequiredLibrariesForAbi(entry.key),
          unorderedEquals([...modern, ...entry.value, ...?liteRt[entry.key]]),
          reason: entry.key.toString(),
        );
        for (final sampler in entry.value) {
          expect(
            modern,
            isNot(contains(sampler)),
            reason: entry.key.toString(),
          );
        }
      }
    },
  );

  test('stable_diffusion pins the qualified v0.3.0-3 release artifacts', () {
    // Exact published owner manifest, independently checked against GitHub
    // asset digests before adoption. This also binds the Apple binary target.
    final manifest =
        jsonDecode(
              File(
                'test/fixtures/native/stable_diffusion_v0_3_0_3_manifest.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(stableDiffusionReleaseTag, manifest['tag']);
    final artifacts = (manifest['artifacts'] as List)
        .cast<Map<String, dynamic>>();
    final runtimes = {
      for (final artifact in artifacts)
        if (artifact['kind'] == 'runtime') artifact['target']: artifact,
    };
    expect(
      stableDiffusionBundleSpecs.map((spec) => spec.bundle).toSet(),
      runtimes.keys.toSet(),
    );
    for (final spec in stableDiffusionBundleSpecs) {
      expect(
        spec.sha256,
        runtimes[spec.bundle]!['sha256'],
        reason: spec.bundle,
      );
      expect(spec.requiredLibraries, {
        runtimes[spec.bundle]!['library'],
      }, reason: spec.bundle);
    }
    final apple = artifacts.singleWhere(
      (artifact) =>
          artifact['file'] ==
          'stable-diffusion-native-apple-xcframework-v0.3.0-3.zip',
    );
    final swift = File(
      'packages/llamadart_stable_diffusion_flutter/darwin/'
      'llamadart_stable_diffusion_flutter/Package.swift',
    ).readAsStringSync();
    expect(swift, contains('let stableDiffusionTag = "${manifest['tag']}"'));
    expect(swift, contains(apple['sha256'] as String));
  });

  // No older XCFramework is requalified: v0.3.0 aborts on FP8 weights on
  // Metal, and earlier pins have a smaller sd_ctx_params_t.
  test('the SD hook accepts only the pinned Apple companion artifact', () {
    final manifest =
        jsonDecode(
              File(
                'test/fixtures/native/stable_diffusion_v0_3_0_3_manifest.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final apple = (manifest['artifacts'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((artifact) => artifact['kind'] == 'xcframework');
    expect(stableDiffusionCompatibleAppleCompanionTags, isEmpty);
    expect(stableDiffusionAppleCompanionChecksums, {
      stableDiffusionReleaseTag: apple['sha256'],
    });
  });

  test('Apple SD companion version is the first release pinning '
      'stableDiffusionReleaseTag', () {
    const companion = 'packages/llamadart_stable_diffusion_flutter';
    final version = RegExp(
      r'^version: (\d+)\.(\d+)\.(\d+)$',
      multiLine: true,
    ).firstMatch(File('$companion/pubspec.yaml').readAsStringSync())!;
    final changelog = File('$companion/CHANGELOG.md').readAsStringSync();
    final sections = RegExp(
      r'^## (.+)$',
      multiLine: true,
    ).allMatches(changelog).toList();
    String? firstPinning;
    for (final (index, section) in sections.indexed) {
      final end = index + 1 < sections.length
          ? sections[index + 1].start
          : changelog.length;
      if (changelog
          .substring(section.end, end)
          .contains(
            'leehack/stable-diffusion-native@$stableDiffusionReleaseTag`',
          )) {
        firstPinning = section.group(1);
      }
    }
    final expected = firstPinning == 'Unreleased'
        ? '${version.group(1)}.${version.group(2)}.'
              '${int.parse(version.group(3)!) + 1}'
        : firstPinning;
    expect(stableDiffusionAppleCompanionVersion, expected);
  });

  test('stable_diffusion cache version is the release tag without its v', () {
    expect(
      stableDiffusionReleaseTag,
      matches(RegExp(r'^v\d+\.\d+\.\d+(?:-[1-9]\d*)?$')),
    );
    expect(stableDiffusionVersion, stableDiffusionReleaseTag.substring(1));
  });

  test('stable_diffusion bundle specs pin one library and a sha256 each', () {
    final bundles = stableDiffusionBundleSpecs
        .map((spec) => spec.bundle)
        .toList();
    expect(bundles.toSet(), hasLength(bundles.length));
    for (final spec in stableDiffusionBundleSpecs) {
      expect(spec.sha256, matches(sha256Pattern), reason: spec.bundle);
      expect(spec.requiredLibraries, hasLength(1), reason: spec.bundle);
      final library = spec.requiredLibraries.single;
      expect(library, switch (spec.bundle.split('-').first) {
        'windows' => 'stable-diffusion.dll',
        'android' || 'linux' => 'libstable-diffusion.so',
        _ => 'libstable-diffusion.dylib',
      }, reason: spec.bundle);
    }
  });

  test('stable_diffusion specs cover every bundle the hook can select', () {
    final specs = stableDiffusionBundleSpecs.map((spec) => spec.bundle).toSet();
    final selectable = <String>{};
    for (final os in OS.values) {
      for (final arch in Architecture.values) {
        for (final isIosSimulator in const [false, true]) {
          final nativeSpec = resolveNativeBundleSpec(
            os: os,
            arch: arch,
            isIosSimulator: isIosSimulator,
          );
          if (nativeSpec == null) continue;
          for (final rawBackendConfig in [
            null,
            {
              'platforms': {nativeSpec.bundle: 'cpu'},
            },
          ]) {
            final bundle = stableDiffusionBundleForNativeBundle(
              spec: nativeSpec,
              rawBackendConfig: rawBackendConfig,
            );
            if (bundle != null) selectable.add(bundle);
          }
        }
      }
    }
    expect(selectable, specs);
  });
}
