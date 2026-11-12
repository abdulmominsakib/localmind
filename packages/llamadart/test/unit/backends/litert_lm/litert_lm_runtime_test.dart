@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/model_source.dart';
import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('companion loading retries an unordered dependency chain', () {
    final loaded = <String>{};
    final attempts = <String>[];
    final handle = DynamicLibrary.process();
    final libraries = liteRtLmOpenCompanionLibraries(
      ['sampler', 'accelerator', 'dawn'],
      openLibrary: (name) {
        attempts.add(name);
        final dependency = switch (name) {
          'sampler' => 'accelerator',
          'accelerator' => 'dawn',
          _ => null,
        };
        if (dependency != null && !loaded.contains(dependency)) {
          throw ArgumentError('Missing dependency $dependency');
        }
        loaded.add(name);
        return handle;
      },
    );
    expect(libraries, [handle, handle, handle]);
    expect(attempts, [
      'sampler',
      'accelerator',
      'dawn',
      'sampler',
      'accelerator',
      'sampler',
    ]);
  });

  test(
    'companion loading stops without progress and preserves loader errors',
    () {
      final failure = ArgumentError('Missing external dependency');
      final attempts = <String>[];
      expect(
        () => liteRtLmOpenCompanionLibraries(
          ['broken', 'independent'],
          openLibrary: (name) {
            attempts.add(name);
            if (name == 'broken') throw failure;
            return DynamicLibrary.process();
          },
        ),
        throwsA(same(failure)),
      );
      expect(attempts, ['broken', 'independent', 'broken']);
    },
  );

  test('companion loading does not retry unrelated errors', () {
    final failure = StateError('Unexpected loader failure');
    final attempts = <String>[];
    expect(
      () => liteRtLmOpenCompanionLibraries(
        ['broken', 'independent'],
        openLibrary: (name) {
          attempts.add(name);
          throw failure;
        },
      ),
      throwsA(same(failure)),
    );
    expect(attempts, ['broken']);
  });

  test('missing explicit runtime does not advertise the ASR bridge', () {
    final client = LiteRtLmRuntimeClient(
      libraryPath: '/missing/libLiteRtLm.so',
    );
    addTearDown(client.dispose);

    expect(client.supportsAsrBridge, isFalse);
  });

  test('ASR config is validated before loading the native runtime', () {
    final client = LiteRtLmRuntimeClient(
      libraryPath: '/missing/libLiteRtLm.so',
    );
    addTearDown(client.dispose);

    LiteRtLmAsrRuntimeConfig config({
      String modelPath = 'model.tflite',
      String tokenizerPath = 'tokenizer.json',
      int numberOfThreads = 4,
      Duration maxBufferedAudio = const Duration(seconds: 30),
      double overlapRatio = 0.4,
      LiteRtLmAsrModelPreset modelPreset = LiteRtLmAsrModelPreset.moonshineTiny,
    }) => LiteRtLmAsrRuntimeConfig(
      modelPath: modelPath,
      tokenizerPath: tokenizerPath,
      modelPreset: modelPreset,
      numberOfThreads: numberOfThreads,
      maxBufferedAudio: maxBufferedAudio,
      overlapRatio: overlapRatio,
    );

    for (final invalid in <(LiteRtLmAsrRuntimeConfig, String)>[
      (config(modelPath: ' '), 'modelPath'),
      (config(tokenizerPath: ' '), 'tokenizerPath'),
      (config(numberOfThreads: 0), 'numberOfThreads'),
      (config(numberOfThreads: 0x80000000), 'numberOfThreads'),
      (config(maxBufferedAudio: Duration.zero), 'maxBufferedAudio'),
      (
        config(maxBufferedAudio: const Duration(milliseconds: 0x80000000)),
        'maxBufferedAudio',
      ),
      (
        config(
          modelPreset: LiteRtLmAsrModelPreset.whisperTiny,
          maxBufferedAudio: const Duration(seconds: 29),
        ),
        'maxBufferedAudio',
      ),
      (config(overlapRatio: double.nan), 'overlapRatio'),
      (config(overlapRatio: double.infinity), 'overlapRatio'),
      (config(overlapRatio: -0.1), 'overlapRatio'),
      (config(overlapRatio: 1), 'overlapRatio'),
    ]) {
      expect(
        () => client.createAsrSession(invalid.$1),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            invalid.$2,
          ),
        ),
      );
    }
  });

  test('ASR sessions open local files only', () {
    final client = LiteRtLmRuntimeClient(
      libraryPath: '/missing/libLiteRtLm.so',
    );
    addTearDown(client.dispose);

    expect(
      () => client.createAsrSession(
        LiteRtLmAsrRuntimeConfig.source(
          model: ModelSource.path('/models/model.tflite'),
          tokenizer: ModelSource.parse(
            'https://example.com/tokenizer.json?token=secret',
          ),
          modelPreset: LiteRtLmAsrModelPreset.moonshineTiny,
        ),
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('tokenizer'),
            contains('SpeechToTextEngine.load'),
            isNot(contains('secret')),
          ),
        ),
      ),
    );
  });

  test('LiteRtLmRuntimeMetrics serializes runtime counters', () {
    const metrics = LiteRtLmRuntimeMetrics(
      inputTokens: 12,
      outputTokens: 34,
      timeToFirstTokenSeconds: 0.5,
      initSeconds: 1.25,
      prefillTokensPerSecond: 20.0,
      decodeTokensPerSecond: 30.0,
      wallMilliseconds: 4567,
    );

    expect(metrics.toJson(), {
      'inputTokens': 12,
      'outputTokens': 34,
      'timeToFirstTokenSeconds': 0.5,
      'initSeconds': 1.25,
      'prefillTokensPerSecond': 20.0,
      'decodeTokensPerSecond': 30.0,
      'wallMilliseconds': 4567,
    });
  });

  test('LiteRtLmRuntimeResult keeps generated text with metrics', () {
    const metrics = LiteRtLmRuntimeMetrics(
      inputTokens: 1,
      outputTokens: 2,
      timeToFirstTokenSeconds: null,
      initSeconds: null,
      prefillTokensPerSecond: null,
      decodeTokensPerSecond: null,
      wallMilliseconds: 3,
    );

    const result = LiteRtLmRuntimeResult(text: 'hello', metrics: metrics);

    expect(result.text, 'hello');
    expect(result.metrics, same(metrics));
  });

  test('macOS arm64 is a supported LiteRT-LM ABI', () {
    expect(liteRtLmUnsupportedAbiException(Abi.macosArm64), isNull);
    expect(liteRtLmPrimaryLibraryForAbi(Abi.macosArm64), 'libLiteRtLm.dylib');
    expect(liteRtLmMacOsRequiredLibrariesForAbi(Abi.macosArm64), isNotEmpty);
    for (final abi in const [
      Abi.linuxArm64,
      Abi.linuxX64,
      Abi.windowsX64,
      Abi.androidArm64,
      Abi.iosArm64,
    ]) {
      expect(liteRtLmUnsupportedAbiException(abi), isNull, reason: '$abi');
    }
  });

  test('macOS x64 reports a typed LiteRT-LM unsupported error', () {
    expect(
      liteRtLmUnsupportedAbiException(Abi.macosX64),
      isA<LlamaUnsupportedException>().having(
        (error) => error.message,
        'message',
        allOf(
          contains('LiteRT-LM is not available on macOS x86_64'),
          contains('arm64-only macOS runtimes'),
          contains('leehack/litert-lm-native#72'),
          contains('not under Rosetta'),
          contains('llama.cpp backend'),
        ),
      ),
    );
  });

  group('macOS x86_64 load gate', () {
    void runOn(Abi abi) {
      debugLiteRtLmAbiOverride = abi;
      addTearDown(() => debugLiteRtLmAbiOverride = null);
    }

    test('throws the typed error before looking for a runtime', () {
      runOn(Abi.macosX64);
      final client = LiteRtLmRuntimeClient();
      addTearDown(client.dispose);

      expect(
        () => client.bundleCapabilities('/missing/model.litertlm'),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('LiteRT-LM is not available on macOS x86_64'),
          ),
        ),
      );
    });

    test('names each ABI without a published runtime', () {
      for (final (abi, message) in [
        (Abi.windowsArm64, 'LiteRT-LM is not available on Windows arm64'),
        (Abi.iosX64, 'LiteRT-LM is not available on the x86_64 iOS simulator'),
      ]) {
        runOn(abi);
        final client = LiteRtLmRuntimeClient();
        addTearDown(client.dispose);

        expect(
          () => client.bundleCapabilities('/missing/model.litertlm'),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              contains(message),
            ),
          ),
        );
      }
      for (final abi in [Abi.linuxArm64, Abi.windowsX64, Abi.iosArm64]) {
        expect(liteRtLmUnsupportedAbiException(abi), isNull, reason: '$abi');
      }
    });

    test('lets an explicit libraryPath through', () {
      runOn(Abi.macosX64);
      final client = LiteRtLmRuntimeClient(
        libraryPath: '/missing/libLiteRtLm.dylib',
      );
      addTearDown(client.dispose);

      expect(
        () => client.bundleCapabilities('/missing/model.litertlm'),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('/missing/libLiteRtLm.dylib'),
          ),
        ),
      );
    });

    test('does not stop macOS arm64', () {
      runOn(Abi.macosArm64);
      final client = LiteRtLmRuntimeClient();
      addTearDown(client.dispose);

      Object? error;
      try {
        client.bundleCapabilities('/missing/model.litertlm');
      } on Object catch (caught) {
        error = caught;
      }
      expect(error, isNot(isA<LlamaUnsupportedException>()));
    });
  });

  test('macOS LiteRT-LM cache lookup follows the current runtime ABI', () {
    expect(
      liteRtLmMacOsCacheDirectoryCandidatesForAbi(Abi.macosArm64),
      const <String>['macos_arm64', 'macos/arm64'],
    );
    expect(liteRtLmMacOsCacheDirectoryCandidatesForAbi(Abi.macosX64), isEmpty);
    expect(liteRtLmCacheDirectoryCandidatesForAbi(Abi.macosX64), isEmpty);
    expect(liteRtLmMacOsCacheDirectoryCandidatesForAbi(Abi.linuxX64), isEmpty);
  });

  test('macOS LiteRT-LM paths precede process-linked runtime fallback', () {
    expect(
      liteRtLmMacOsLibraryCandidates(
        '/runtime/libLiteRtLm.dylib',
        explicitOverride: true,
      ),
      const <String>['/runtime/libLiteRtLm.dylib'],
    );
    expect(
      liteRtLmMacOsLibraryCandidates(
        '/runtime/libLiteRtLm.dylib',
        explicitOverride: false,
      ),
      const <String>['/runtime/libLiteRtLm.dylib', '<process>'],
    );
  });

  test('rejects legacy StreamProxy with the v0.15 stream-chunk API', () {
    expect(
      liteRtLmStreamProxyCompatibilityError(
        hasStreamProxy: true,
        hasStreamChunkApi: true,
        callbackAbiVersion: null,
      ),
      contains('not stream-chunk compatible'),
    );
    final legacyAbiError = liteRtLmStreamProxyCompatibilityError(
      hasStreamProxy: true,
      hasStreamChunkApi: true,
      callbackAbiVersion: 1,
    );
    expect(legacyAbiError, contains('not stream-chunk compatible'));
    expect(legacyAbiError, contains('Expected callback ABI 2'));
    expect(legacyAbiError, contains('litert-lm-native $liteRtLmReleaseTag;'));
    expect(legacyAbiError, contains('detected 1'));
  });

  test('accepts legacy runtimes and stream-chunk-compatible proxies', () {
    expect(
      liteRtLmStreamProxyCompatibilityError(
        hasStreamProxy: true,
        hasStreamChunkApi: false,
        callbackAbiVersion: 1,
      ),
      isNull,
    );
    expect(
      liteRtLmStreamProxyCompatibilityError(
        hasStreamProxy: true,
        hasStreamChunkApi: true,
        callbackAbiVersion: 2,
      ),
      isNull,
    );
    expect(
      liteRtLmStreamProxyCompatibilityError(
        hasStreamProxy: false,
        hasStreamChunkApi: true,
        callbackAbiVersion: null,
      ),
      contains('missing or not stream-chunk compatible'),
    );
  });

  test('LiteRT-LM cache lookup follows desktop runtime ABIs', () {
    expect(
      liteRtLmCacheDirectoryCandidatesForAbi(Abi.macosArm64),
      const <String>['macos_arm64', 'macos/arm64'],
    );
    expect(liteRtLmCacheDirectoryCandidatesForAbi(Abi.linuxX64), const <String>[
      'linux/x64',
      'linux_x64',
    ]);
    expect(
      liteRtLmCacheDirectoryCandidatesForAbi(Abi.linuxArm64),
      const <String>['linux/arm64', 'linux_arm64'],
    );
    expect(
      liteRtLmCacheDirectoryCandidatesForAbi(Abi.windowsX64),
      const <String>['windows/x64', 'windows_x64'],
    );
    expect(liteRtLmCacheDirectoryCandidatesForAbi(Abi.androidArm64), isEmpty);
  });

  test('LiteRT-LM package config lookup finds the llamadart package root', () {
    final root = Directory.systemTemp.createTempSync('litert_lm_pkg_config_');
    addTearDown(() => root.deleteSync(recursive: true));

    final appRoot = Directory('${root.path}/app')..createSync();
    final packageRoot = Directory('${root.path}/llamadart')..createSync();
    final dotDartTool = Directory('${appRoot.path}/.dart_tool')
      ..createSync(recursive: true);
    final packageConfig = File('${dotDartTool.path}/package_config.json')
      ..writeAsStringSync('''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "llamadart",
      "rootUri": "${packageRoot.uri}",
      "packageUri": "lib/",
      "languageVersion": "3.10"
    }
  ]
}
''');

    expect(liteRtLmPackageRootsFromPackageConfig(packageConfig), [
      path.normalize(packageRoot.absolute.path),
    ]);
  });

  test('LiteRT-LM package config lookup parses supplied contents', () {
    final packageConfig = File(
      path.join('consumer', '.dart_tool', 'package_config.json'),
    );
    expect(packageConfig.existsSync(), isFalse);

    expect(
      liteRtLmPackageRootsFromPackageConfig(
        packageConfig,
        contents: jsonEncode({
          'configVersion': 2,
          'packages': [
            {'name': 'llamadart', 'rootUri': '../../llamadart'},
          ],
        }),
      ),
      [path.normalize(File('llamadart').absolute.path)],
    );
    expect(
      liteRtLmPackageRootsFromPackageConfig(packageConfig, contents: '{'),
      isEmpty,
    );
  });

  test('LiteRT-LM iOS fallback identifiers include process and frameworks', () {
    // The process candidate supports the Flutter SPM bridge. The remaining
    // entries preserve the native-asset/framework fallbacks used by bundled
    // builds.
    expect(liteRtLmIosLibraryCandidatesForAbi(Abi.iosArm64), const <String>[
      '<process>',
      'package:llamadart/litert_lm_LiteRtLm',
      'LiteRtLm',
      'CLiteRTLM',
    ]);
    expect(liteRtLmIosLibraryCandidatesForAbi(Abi.iosX64), const <String>[
      '<process>',
      'package:llamadart/litert_lm_LiteRtLm',
      'LiteRtLm',
      'CLiteRTLM',
    ]);
    expect(liteRtLmIosLibraryCandidatesForAbi(Abi.macosArm64), isEmpty);
  });

  test('LiteRT-LM iOS lookup prefers the wrapper framework path', () {
    // The wrapper exports StreamProxy and reexports the upstream API, so it
    // must precede process and CLiteRTLM handles that can expose only part of
    // the required v0.15 callback ABI.
    expect(
      liteRtLmIosLibraryCandidates(
        Abi.iosArm64,
        frameworksDirPath: '/App.app/Frameworks',
      ),
      const <String>[
        '/App.app/Frameworks/LiteRtLm.framework/LiteRtLm',
        '<process>',
        '/App.app/Frameworks/CLiteRTLM.framework/CLiteRTLM',
        'package:llamadart/litert_lm_LiteRtLm',
        'LiteRtLm',
        'CLiteRTLM',
      ],
    );
    // Without a Frameworks dir, only process and fallback identifiers remain.
    expect(liteRtLmIosLibraryCandidates(Abi.iosArm64), const <String>[
      '<process>',
      'package:llamadart/litert_lm_LiteRtLm',
      'LiteRtLm',
      'CLiteRTLM',
    ]);
    // Non-iOS ABIs have no iOS candidates regardless of a frameworks dir.
    expect(
      liteRtLmIosLibraryCandidates(
        Abi.macosArm64,
        frameworksDirPath: '/App.app/Frameworks',
      ),
      isEmpty,
    );
    expect(
      liteRtLmIosFrameworkBinaryPath('/App.app/Frameworks', 'LiteRtLm'),
      '/App.app/Frameworks/LiteRtLm.framework/LiteRtLm',
    );
  });

  test('macOS LiteRT-LM cache validation follows runtime ABI files', () {
    expect(liteRtLmMacOsRequiredLibrariesForAbi(Abi.macosArm64), const <String>[
      'libCLiteRTLM_mac.dylib',
      'libGemmaModelConstraintProvider.dylib',
      'libLiteRt.dylib',
      'libLiteRtLm.dylib',
      'libLiteRtMetalAccelerator.dylib',
      'libLiteRtTopKMetalSampler.dylib',
      'libLiteRtTopKWebGpuSampler.dylib',
      'libLiteRtWebGpuAccelerator.dylib',
      'libwebgpu_dawn.dylib',
    ]);
    expect(liteRtLmMacOsRequiredLibrariesForAbi(Abi.macosX64), isEmpty);
    expect(liteRtLmRequiredLibrariesForAbi(Abi.macosX64), isEmpty);
    expect(liteRtLmPrimaryLibraryForAbi(Abi.macosX64), isNull);
    expect(liteRtLmMacOsRequiredLibrariesForAbi(Abi.linuxX64), isEmpty);
  });

  test('LiteRT-LM cache validation follows desktop runtime ABI files', () {
    expect(liteRtLmRequiredLibrariesForAbi(Abi.linuxX64), const <String>[
      'libGemmaModelConstraintProvider.so',
      'libLiteRt.so',
      'libLiteRtLm.so',
      'libLiteRtTopKWebGpuSampler.so',
      'libLiteRtWebGpuAccelerator.so',
      'libwebgpu_dawn.so',
    ]);
    expect(liteRtLmRequiredLibrariesForAbi(Abi.windowsX64), const <String>[
      'LiteRtLm.dll',
      'dxcompiler.dll',
      'dxil.dll',
      'libGemmaModelConstraintProvider.dll',
      'libLiteRt.dll',
      'libLiteRtTopKWebGpuSampler.dll',
      'libLiteRtWebGpuAccelerator.dll',
      'libwebgpu_dawn.dll',
      'msvcp140.dll',
      'vcruntime140.dll',
      'vcruntime140_1.dll',
      'vcruntime140_threads.dll',
      'webgpu_dawn.dll',
    ]);
    expect(liteRtLmRequiredLibrariesForAbi(Abi.androidArm64), isEmpty);
  });

  test('Windows DXC pair is required but never preloaded', () {
    expect(
      liteRtLmNonPreloadedLibrariesForAbi(Abi.windowsX64),
      unorderedEquals(const ['dxcompiler.dll', 'dxil.dll']),
    );
    for (final abi in Abi.values) {
      expect(
        liteRtLmRequiredLibrariesForAbi(abi),
        containsAll(liteRtLmNonPreloadedLibrariesForAbi(abi)),
        reason: '$abi',
      );
      if (abi != Abi.windowsX64) {
        expect(
          liteRtLmNonPreloadedLibrariesForAbi(abi),
          isEmpty,
          reason: '$abi',
        );
      }
    }
    expect(liteRtLmCompanionLibrariesForAbi(Abi.windowsX64), const <String>[
      'vcruntime140.dll',
      'vcruntime140_1.dll',
      'vcruntime140_threads.dll',
      'msvcp140.dll',
      'webgpu_dawn.dll',
      'libGemmaModelConstraintProvider.dll',
      'libLiteRt.dll',
      'libLiteRtTopKWebGpuSampler.dll',
      'libLiteRtWebGpuAccelerator.dll',
      'libwebgpu_dawn.dll',
    ]);
  });

  test('Windows companions open every imported DLL before its importers', () {
    // Import tables of the v0.18.1-4 Windows runtime, companions only.
    // Windows binds an import to an already loaded module before searching
    // System32, the working directory and PATH.
    const imports = <String, List<String>>{
      'libLiteRtTopKWebGpuSampler.dll': ['webgpu_dawn.dll'],
      'libLiteRtWebGpuAccelerator.dll': ['webgpu_dawn.dll'],
      'msvcp140.dll': ['vcruntime140.dll', 'vcruntime140_1.dll'],
      'vcruntime140_1.dll': ['vcruntime140.dll'],
      'vcruntime140_threads.dll': ['vcruntime140.dll'],
    };
    final order = liteRtLmCompanionLibrariesForAbi(Abi.windowsX64);
    for (final MapEntry(key: importer, value: dependencies)
        in imports.entries) {
      for (final dependency in dependencies) {
        expect(
          order.indexOf(dependency),
          allOf(isNonNegative, lessThan(order.indexOf(importer))),
          reason: '$dependency must open before $importer',
        );
      }
    }
  });

  test('companion libraries are the required list minus the primary', () {
    for (final abi in const [
      Abi.macosArm64,
      Abi.linuxArm64,
      Abi.linuxX64,
      Abi.windowsX64,
    ]) {
      final primary = liteRtLmPrimaryLibraryForAbi(abi)!;
      final required = liteRtLmRequiredLibrariesForAbi(abi);
      expect(required, contains(primary), reason: '$abi');
      expect(
        liteRtLmCompanionLibrariesForAbi(abi),
        unorderedEquals(
          required
              .where((library) => library != primary)
              .where(
                (library) =>
                    !liteRtLmNonPreloadedLibrariesForAbi(abi).contains(library),
              )
              .toList(),
        ),
        reason: '$abi',
      );
    }
    expect(liteRtLmPrimaryLibraryForAbi(Abi.androidArm64), isNull);
    expect(liteRtLmCompanionLibrariesForAbi(Abi.androidArm64), isEmpty);
  });

  test('macOS LiteRT-LM app framework validation follows runtime ABI', () {
    expect(
      liteRtLmMacOsRequiredFrameworksForAbi(Abi.macosArm64),
      _macOsFrameworkFiles,
    );
    expect(liteRtLmMacOsRequiredFrameworksForAbi(Abi.macosX64), isEmpty);
    expect(liteRtLmMacOsRequiredFrameworksForAbi(Abi.linuxX64), isEmpty);
  });

  test('macOS LiteRT-LM native SPM validation matches the embedded layout', () {
    // Xcode embeds library xcframeworks as flat dylibs and keeps the Gemma
    // provider inside LiteRtLm.framework, as companion v0.18.0 builds do.
    expect(liteRtLmMacOsRequiredNativeSpmFilesForAbi(Abi.macosArm64), const <
      String
    >[
      'LiteRtLm.framework/Versions/A/LiteRtLm',
      'libCLiteRTLM_mac.dylib',
      'LiteRtLm.framework/Versions/A/Dependencies/libGemmaModelConstraintProvider.dylib',
      'libLiteRt.dylib',
      'libLiteRtTopKWebGpuSampler.dylib',
      'libLiteRtWebGpuAccelerator.dylib',
      'libwebgpu_dawn.dylib',
    ]);
    expect(liteRtLmMacOsRequiredNativeSpmFilesForAbi(Abi.macosX64), isEmpty);
    expect(liteRtLmMacOsRequiredNativeSpmFilesForAbi(Abi.linuxX64), isEmpty);
  });

  test('macOS LiteRT-LM cache validation rejects partial caches', () {
    final root = Directory.systemTemp.createTempSync('litert_lm_cache_test_');
    addTearDown(() => root.deleteSync(recursive: true));

    final arm64Dir = Directory('${root.path}/arm64')..createSync();
    File('${arm64Dir.path}/libLiteRtLm.dylib').createSync();

    expect(
      liteRtLmIsMacOsCacheDirectoryForAbi(arm64Dir, Abi.macosArm64),
      isFalse,
    );

    for (final library in liteRtLmMacOsRequiredLibrariesForAbi(
      Abi.macosArm64,
    )) {
      File('${arm64Dir.path}/$library').createSync();
    }

    expect(
      liteRtLmIsMacOsCacheDirectoryForAbi(arm64Dir, Abi.macosArm64),
      isTrue,
    );

    // Every published arm64 companion is required even for CPU loading:
    // accepting an incomplete cache can hide a broken GPU deployment.
    for (final library in liteRtLmMacOsRequiredLibrariesForAbi(
      Abi.macosArm64,
    )) {
      final file = File('${arm64Dir.path}/$library');
      file.deleteSync();
      expect(
        liteRtLmIsCacheDirectoryForAbi(arm64Dir, Abi.macosArm64),
        isFalse,
        reason: 'Missing $library must invalidate the cache',
      );
      file.createSync();
    }
    expect(liteRtLmIsCacheDirectoryForAbi(arm64Dir, Abi.macosArm64), isTrue);

    // A complete arm64 cache is never an x64 cache: no x64 runtime exists.
    expect(
      liteRtLmIsMacOsCacheDirectoryForAbi(arm64Dir, Abi.macosX64),
      isFalse,
    );
    expect(liteRtLmIsCacheDirectoryForAbi(arm64Dir, Abi.macosX64), isFalse);
    expect(
      liteRtLmIsMacOsCacheDirectoryForAbi(arm64Dir, Abi.linuxX64),
      isFalse,
    );
  });

  test('LiteRT-LM cache validation rejects partial desktop caches', () {
    final root = Directory.systemTemp.createTempSync('litert_lm_cache_test_');
    addTearDown(() => root.deleteSync(recursive: true));

    final linuxDir = Directory('${root.path}/linux')..createSync();
    File('${linuxDir.path}/libLiteRtLm.so').createSync();

    expect(liteRtLmIsCacheDirectoryForAbi(linuxDir, Abi.linuxX64), isFalse);

    for (final library in liteRtLmRequiredLibrariesForAbi(Abi.linuxX64)) {
      File('${linuxDir.path}/$library').createSync();
    }

    expect(liteRtLmIsCacheDirectoryForAbi(linuxDir, Abi.linuxX64), isTrue);

    final windowsDir = Directory('${root.path}/windows')..createSync();
    File('${windowsDir.path}/LiteRtLm.dll').createSync();

    expect(liteRtLmIsCacheDirectoryForAbi(windowsDir, Abi.windowsX64), isFalse);

    for (final library in liteRtLmRequiredLibrariesForAbi(Abi.windowsX64)) {
      File('${windowsDir.path}/$library').createSync();
    }

    expect(liteRtLmIsCacheDirectoryForAbi(windowsDir, Abi.windowsX64), isTrue);
    expect(liteRtLmIsCacheDirectoryForAbi(windowsDir, Abi.linuxX64), isFalse);
  });

  group('LiteRT-LM app bundle directory', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('litert_lm_bundle_test_');
    });
    tearDown(() => root.deleteSync(recursive: true));

    Directory populate(List<String> segments, Abi abi) {
      final dir = Directory(path.joinAll([root.path, ...segments]))
        ..createSync(recursive: true);
      for (final library in liteRtLmRequiredLibrariesForAbi(abi)) {
        File(path.join(dir.path, library)).createSync();
      }
      return dir;
    }

    test('probes beside, lib/ and, from bin/, ../lib/ of the executable', () {
      final executable = path.join(root.path, 'bundle', 'bin', 'app');
      for (final abi in const [Abi.linuxX64, Abi.linuxArm64, Abi.windowsX64]) {
        expect(
          liteRtLmBundleLibraryDirectoryCandidatesForAbi(executable, abi),
          [
            path.join(root.path, 'bundle', 'bin'),
            path.join(root.path, 'bundle', 'bin', 'lib'),
            path.join(root.path, 'bundle', 'lib'),
          ],
        );
      }
    });

    test('never looks outside the folder of an executable not in bin/', () {
      populate(['lib'], Abi.linuxX64);
      populate(['lib'], Abi.windowsX64);
      final linuxApp = path.join(root.path, 'bundle', 'app');
      final windowsApp = path.join(root.path, 'Release', 'app.exe');
      expect(
        liteRtLmBundleLibraryDirectoryCandidatesForAbi(linuxApp, Abi.linuxX64),
        [path.join(root.path, 'bundle'), path.join(root.path, 'bundle', 'lib')],
      );
      expect(
        liteRtLmFindBundleLibraryDirectoryForAbi(linuxApp, Abi.linuxX64),
        isNull,
      );
      expect(
        liteRtLmFindBundleLibraryDirectoryForAbi(windowsApp, Abi.windowsX64),
        isNull,
      );
    });

    test('finds the dart build cli, Flutter Linux and Flutter Windows '
        'layouts', () {
      final cliLib = populate(['cli', 'bundle', 'lib'], Abi.linuxX64);
      expect(
        liteRtLmFindBundleLibraryDirectoryForAbi(
          path.join(root.path, 'cli', 'bundle', 'bin', 'app'),
          Abi.linuxX64,
        )?.path,
        cliLib.path,
      );

      final flutterLinuxLib = populate([
        'flutter_linux',
        'bundle',
        'lib',
      ], Abi.linuxX64);
      expect(
        liteRtLmFindBundleLibraryDirectoryForAbi(
          path.join(root.path, 'flutter_linux', 'bundle', 'app'),
          Abi.linuxX64,
        )?.path,
        flutterLinuxLib.path,
      );

      final flutterWindowsDir = populate(['Release'], Abi.windowsX64);
      expect(
        liteRtLmFindBundleLibraryDirectoryForAbi(
          path.join(flutterWindowsDir.path, 'app.exe'),
          Abi.windowsX64,
        )?.path,
        flutterWindowsDir.path,
      );
    });

    test('rejects a bundle missing any required library', () {
      final lib = populate(['bundle', 'lib'], Abi.windowsX64);
      final executable = path.join(root.path, 'bundle', 'bin', 'app.exe');
      for (final library in liteRtLmRequiredLibrariesForAbi(Abi.windowsX64)) {
        final file = File(path.join(lib.path, library))..deleteSync();
        expect(
          liteRtLmFindBundleLibraryDirectoryForAbi(executable, Abi.windowsX64),
          isNull,
          reason: 'Missing $library must not select the bundle',
        );
        file.createSync();
      }
      expect(
        liteRtLmFindBundleLibraryDirectoryForAbi(executable, Abi.windowsX64),
        isNotNull,
      );
      expect(
        liteRtLmFindBundleLibraryDirectoryForAbi(executable, Abi.linuxX64),
        isNull,
      );
    });

    test('is not probed on platforms without hook-bundled desktop '
        'libraries', () {
      final executable = path.join(root.path, 'bundle', 'bin', 'app');
      for (final abi in const [
        Abi.macosArm64,
        Abi.macosX64,
        Abi.iosArm64,
        Abi.androidArm64,
        Abi.windowsArm64,
      ]) {
        expect(
          liteRtLmBundleLibraryDirectoryCandidatesForAbi(executable, abi),
          isEmpty,
          reason: '$abi',
        );
      }
    });
  });

  group('LiteRT-LM runtime directory resolution', () {
    const abi = Abi.linuxX64;
    late Directory root;
    late String executable;
    late Directory override;
    late Directory bundle;
    late Directory project;
    late Directory cache;

    Directory complete(List<String> segments) {
      final dir = Directory(path.joinAll([root.path, ...segments]))
        ..createSync(recursive: true);
      for (final library in liteRtLmRequiredLibrariesForAbi(abi)) {
        File(path.join(dir.path, library)).createSync();
      }
      return dir;
    }

    setUp(() {
      root = Directory.systemTemp.createTempSync('litert_lm_resolve_test_');
      executable = path.join(root.path, 'app', 'bin', 'app');
      override = complete(['override']);
      bundle = complete(['app', 'lib']);
      project = Directory(path.join(root.path, 'project'));
      cache = complete([
        'project',
        '.dart_tool',
        'llamadart',
        'litert_lm',
        liteRtLmVersion,
        'linux',
        'x64',
      ]);
    });
    tearDown(() => root.deleteSync(recursive: true));

    // The hook-cache walk joins with `/`; normalize so Windows compares
    // separators consistently.
    String? resolve({String? libDirOverride, bool searchRootsAllowed = true}) {
      final dir = liteRtLmResolveRuntimeDirectoryForAbi(
        abi,
        libDirOverride: libDirOverride,
        executablePath: executable,
        searchRoots: () {
          if (!searchRootsAllowed) {
            fail('the hook cache must not be searched');
          }
          return [Directory(path.join(project.path, 'src'))];
        },
      );
      return dir == null ? null : path.normalize(dir.path);
    }

    test(
      'a complete LLAMADART_LITERT_LM_LIB_DIR wins over bundle and cache',
      () {
        expect(
          resolve(libDirOverride: override.path, searchRootsAllowed: false),
          override.absolute.path,
        );
      },
    );

    test('the app bundle wins over the hook cache', () {
      expect(resolve(searchRootsAllowed: false), bundle.path);
      final incompleteOverride = Directory(path.join(root.path, 'partial'))
        ..createSync();
      expect(
        () => resolve(
          libDirOverride: incompleteOverride.path,
          searchRootsAllowed: false,
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('the hook cache above a search root is the last resort', () {
      bundle.deleteSync(recursive: true);
      expect(resolve(), cache.path);
      cache.deleteSync(recursive: true);
      expect(resolve(), isNull);
    });
  });

  test('engine create failure diagnostics include fallback guidance', () {
    expect(
      liteRtLmEngineCreateFailureMessage(
        backend: 'npu',
        modelPath: '/models/gemma-4-E2B-it.litertlm',
      ),
      allOf(
        contains('backend "npu"'),
        contains('gemma-4-E2B-it.litertlm'),
        contains('Android NPU delegate'),
        contains('backend "gpu"'),
        contains('backend "cpu"'),
      ),
    );
    expect(
      liteRtLmEngineCreateFailureMessage(
        backend: 'gpu',
        modelPath: '/models/gemma-4-E2B-it.litertlm',
      ),
      allOf(contains('GPU delegate'), contains('backend "cpu"')),
    );
    expect(
      liteRtLmEngineCreateFailureMessage(
        backend: 'cpu',
        modelPath: '/models/gemma-4-E2B-it.litertlm',
      ),
      allOf(
        contains('backend "cpu"'),
        contains('Verify the LiteRT-LM bundle'),
        isNot(contains('delegate')),
      ),
    );
    expect(
      liteRtLmEngineCreateFailureMessage(
        backend: 'gpu',
        modelPath: '/models/gemma-4-E2B-it.litertlm',
        nativeError: 'LiteRT-LM reported INTERNAL (13): no OpenCL device.',
      ),
      'LiteRT-LM engine creation failed for backend "gpu" and model '
      '"gemma-4-E2B-it.litertlm". LiteRT-LM reported INTERNAL (13): no '
      'OpenCL device. The GPU delegate may not support this device, OS, '
      'model, or bundle; try backend "cpu".',
    );
  });

  test('a null engine from engine create throws LiteRtLmEngineCreateError', () {
    expect(
      () => liteRtLmCheckEngineCreated(
        0,
        backend: 'gpu',
        modelPath: '/models/gemma-4-E2B-it.litertlm',
      ),
      throwsA(
        isA<LiteRtLmEngineCreateError>().having(
          (error) => error.message,
          'message',
          allOf(contains('backend "gpu"'), contains('gemma-4-E2B-it.litertlm')),
        ),
      ),
    );
    liteRtLmCheckEngineCreated(
      0x1000,
      backend: 'gpu',
      modelPath: '/models/gemma-4-E2B-it.litertlm',
    );
  });

  test(
    'LiteRtLmRuntimeClient validates counts before native initialization',
    () {
      final client = LiteRtLmRuntimeClient();

      expect(
        client.initialize(modelPath: 'model.litertlm', maxTokens: 0),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'maxTokens',
          ),
        ),
      );
      expect(
        client.initialize(modelPath: 'model.litertlm', outputTokens: 0),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'outputTokens',
          ),
        ),
      );
      expect(
        client.initialize(modelPath: 'model.litertlm', prefillTokens: -1),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'prefillTokens',
          ),
        ),
      );
      expect(
        client.initialize(modelPath: 'model.litertlm', maxNumImages: 0),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'maxNumImages',
          ),
        ),
      );
      expect(
        client.initialize(modelPath: 'model.litertlm', prefillChunkSize: 0),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'prefillChunkSize',
          ),
        ),
      );
      expect(
        client.initialize(modelPath: 'model.litertlm', dispatchLibDir: '  '),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'dispatchLibDir',
          ),
        ),
      );
      expect(
        client.initialize(modelPath: 'model.litertlm', numberOfThreads: 0),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'numberOfThreads',
          ),
        ),
      );
    },
  );

  test(
    'LiteRtLmRuntimeClient validates backend before native initialization',
    () {
      final client = LiteRtLmRuntimeClient();

      expect(
        client.initialize(modelPath: 'model.litertlm', backend: ' dsp '),
        throwsA(
          isA<ArgumentError>().having((error) => error.name, 'name', 'backend'),
        ),
      );
      expect(
        client.initialize(modelPath: 'model.litertlm', visionBackend: ' dsp '),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'visionBackend',
          ),
        ),
      );
      expect(
        client.initialize(modelPath: 'model.litertlm', audioBackend: ' dsp '),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'audioBackend',
          ),
        ),
      );
    },
  );

  test('LiteRtLmRuntimeClient validates send optional args', () {
    final client = LiteRtLmRuntimeClient();

    expect(
      () => client.generateMessageJson(
        '{"role":"user","content":[{"type":"text","text":"hi"}]}',
        visualTokenBudget: 0,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.name,
          'name',
          'visualTokenBudget',
        ),
      ),
    );
    expect(
      () => client.generateMessageJson(
        '{"role":"user","content":[{"type":"text","text":"hi"}]}',
        maxOutputTokens: 0,
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.name,
          'name',
          'maxOutputTokens',
        ),
      ),
    );
  });

  test('LiteRtLmRuntimeClient validates benchmark loop counts', () {
    final client = LiteRtLmRuntimeClient();

    expect(
      client.run(prompt: 'hello', warmupRuns: -1),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.name,
          'name',
          'warmupRuns',
        ),
      ),
    );
    expect(
      client.run(prompt: 'hello', measuredRuns: 0),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.name,
          'name',
          'measuredRuns',
        ),
      ),
    );
  });
}

const List<String> _macOsFrameworkFiles = <String>[
  'CLiteRTLM_mac.framework/Versions/A/CLiteRTLM_mac',
  'GemmaModelConstraintProvider.framework/Versions/A/'
      'GemmaModelConstraintProvider',
  'LiteRt.framework/Versions/A/LiteRt',
  'LiteRtLm.framework/Versions/A/LiteRtLm',
  'LiteRtMetalAccelerator.framework/Versions/A/LiteRtMetalAccelerator',
  'LiteRtTopKMetalSampler.framework/Versions/A/LiteRtTopKMetalSampler',
  'LiteRtTopKWebGpuSampler.framework/Versions/A/LiteRtTopKWebGpuSampler',
  'LiteRtWebGpuAccelerator.framework/Versions/A/LiteRtWebGpuAccelerator',
  'webgpu_dawn.framework/Versions/A/webgpu_dawn',
];
