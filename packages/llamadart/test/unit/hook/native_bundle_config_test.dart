@TestOn('vm')
library;

import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';

import 'package:llamadart/src/hook/native_bundle_config.dart';

void main() {
  group('resolveNativeBundleSpec', () {
    test('resolves android arm64 with cpu+vulkan defaults', () {
      final spec = resolveNativeBundleSpec(
        os: OS.android,
        arch: Architecture.arm64,
        isIosSimulator: false,
      );

      expect(spec, isNotNull);
      expect(spec!.bundle, 'android-arm64');
      expect(spec.configurableBackends, isTrue);
      expect(spec.defaultBackends, ['cpu', 'vulkan']);
    });

    test('resolves iOS x64 simulator as non-configurable', () {
      final spec = resolveNativeBundleSpec(
        os: OS.iOS,
        arch: Architecture.x64,
        isIosSimulator: true,
      );

      expect(spec, isNotNull);
      expect(spec!.bundle, 'ios-x86_64-sim');
      expect(spec.configurableBackends, isFalse);
      expect(spec.defaultBackends, isEmpty);
    });
  });

  group('describeNativeLibrary', () {
    test('classifies core llama library', () {
      final descriptor = describeNativeLibrary('/tmp/libllamadart.so');

      expect(descriptor.canonicalName, 'llamadart');
      expect(descriptor.isCore, isTrue);
      expect(descriptor.isPrimary, isTrue);
      expect(descriptor.backend, isNull);
    });

    test('classifies ggml backend module', () {
      final descriptor = describeNativeLibrary('/tmp/libggml-vulkan.so');

      expect(descriptor.canonicalName, 'ggml-vulkan');
      expect(descriptor.isCore, isFalse);
      expect(descriptor.backend, 'vulkan');
    });

    test('normalizes legacy suffix naming', () {
      final descriptor = describeNativeLibrary(
        '/tmp/ggml-cuda-windows-x64.dll',
      );

      expect(descriptor.canonicalName, 'ggml-cuda');
      expect(descriptor.backend, 'cuda');
    });

    test('maps OpenCL loader to opencl backend', () {
      final descriptor = describeNativeLibrary('/tmp/libOpenCL.so');

      expect(descriptor.canonicalName, 'opencl');
      expect(descriptor.backend, 'opencl');
    });

    test('does not classify cuda runtimes as backend modules', () {
      final descriptors = [
        describeNativeLibrary('/tmp/cudart64_12.dll'),
        describeNativeLibrary('/tmp/cublas64_12.dll'),
        describeNativeLibrary('/tmp/cublaslt64_12.dll'),
      ];

      expect(descriptors.map((descriptor) => descriptor.canonicalName), [
        'cudart64_12',
        'cublas64_12',
        'cublaslt64_12',
      ]);
      expect(
        descriptors.map((descriptor) => descriptor.backend),
        everyElement(isNull),
      );
    });

    test('normalizes Linux SONAME suffix for core libraries', () {
      final descriptor = describeNativeLibrary('/tmp/libllama.so.0');

      expect(descriptor.canonicalName, 'llama');
      expect(descriptor.isCore, isTrue);
      expect(descriptor.backend, isNull);
    });

    test('classifies llama common as a core runtime library', () {
      final descriptor = describeNativeLibrary('/tmp/libllama-common.so');

      expect(descriptor.canonicalName, 'llama-common');
      expect(descriptor.isCore, isTrue);
      expect(descriptor.backend, isNull);
    });

    test('normalizes Linux SONAME suffix for ggml base library', () {
      final descriptor = describeNativeLibrary('/tmp/libggml-base.so.1');

      expect(descriptor.canonicalName, 'ggml-base');
      expect(descriptor.isCore, isTrue);
      expect(descriptor.backend, isNull);
    });
  });

  group('parseRequestedBackends', () {
    test('parses hooks user-defines platform map', () {
      final requested = parseRequestedBackends(
        bundle: 'linux-x64',
        rawUserConfig: {
          'platforms': {
            'linux-x64': ['CUDA', ' vulkan '],
          },
        },
      );

      expect(requested, ['cuda', 'vulkan']);
    });

    test('supports direct platform map shape', () {
      final requested = parseRequestedBackends(
        bundle: 'windows-x64',
        rawUserConfig: {
          'windows-x64': ['vulkan'],
        },
      );

      expect(requested, ['vulkan']);
    });

    test('supports OS-level platform map shape', () {
      final requested = parseRequestedBackends(
        bundle: 'linux-x64',
        rawUserConfig: {
          'platforms': {
            'linux': ['vulkan'],
          },
        },
      );

      expect(requested, ['vulkan']);
    });

    test('uses exact target backend override before OS-level config', () {
      final requested = parseRequestedBackends(
        bundle: 'linux-x64',
        rawUserConfig: {
          'platforms': {
            'linux': ['vulkan'],
            'linux-x64': ['cuda'],
          },
        },
      );

      expect(requested, ['cuda']);
    });
  });

  group('selectNativeRuntimesForBundle', () {
    test('defaults to all runtime families', () {
      for (final bundle in [
        'android-arm64',
        'ios-arm64',
        'linux-x64',
        'macos-arm64',
        'windows-x64',
      ]) {
        final selected = selectNativeRuntimesForBundle(
          bundle: bundle,
          rawUserConfig: null,
          warn: (_) {},
        );

        expect(selected, [
          nativeRuntimeLlamaCpp,
          nativeRuntimeLiteRtLm,
        ], reason: bundle);
      }
    });

    test('parses global runtime list with aliases', () {
      final selected = selectNativeRuntimesForBundle(
        bundle: 'android-arm64',
        rawUserConfig: 'gguf, litert-lm',
        warn: (_) {},
      );

      expect(selected, [nativeRuntimeLlamaCpp, nativeRuntimeLiteRtLm]);
    });

    test('parses all as both runtime families on non-Android targets', () {
      final selected = selectNativeRuntimesForBundle(
        bundle: 'linux-x64',
        rawUserConfig: 'all',
        warn: (_) {},
      );

      expect(selected, [nativeRuntimeLlamaCpp, nativeRuntimeLiteRtLm]);
    });

    test('parses empty runtime list as all runtime families', () {
      for (final rawUserConfig in const [
        <String>[],
        '',
        {'runtimes': <String>[]},
        {
          'runtimes': ['llama_cpp'],
          'platforms': {'linux-x64': <String>[]},
        },
      ]) {
        final selected = selectNativeRuntimesForBundle(
          bundle: 'linux-x64',
          rawUserConfig: rawUserConfig,
          warn: (_) {},
        );

        expect(selected, [
          nativeRuntimeLlamaCpp,
          nativeRuntimeLiteRtLm,
        ], reason: rawUserConfig.toString());
      }
    });

    test('supports per-platform runtime override', () {
      final selected = selectNativeRuntimesForBundle(
        bundle: 'windows-x64',
        rawUserConfig: {
          'runtimes': ['llama_cpp', 'litert_lm'],
          'platforms': {
            'windows-x64': ['litert'],
          },
        },
        warn: (_) {},
      );

      expect(selected, [nativeRuntimeLiteRtLm]);
    });

    test('supports OS-level runtime override', () {
      final rawUserConfig = {
        'runtimes': ['llama_cpp', 'litert_lm'],
        'platforms': {
          'ios': ['llama_cpp'],
        },
      };

      final deviceSelected = selectNativeRuntimesForBundle(
        bundle: 'ios-arm64',
        rawUserConfig: rawUserConfig,
        warn: (_) {},
      );
      final simulatorSelected = selectNativeRuntimesForBundle(
        bundle: 'ios-arm64-sim',
        rawUserConfig: rawUserConfig,
        warn: (_) {},
      );
      final macosSelected = selectNativeRuntimesForBundle(
        bundle: 'macos-arm64',
        rawUserConfig: rawUserConfig,
        warn: (_) {},
      );

      expect(deviceSelected, [nativeRuntimeLlamaCpp]);
      expect(simulatorSelected, [nativeRuntimeLlamaCpp]);
      expect(macosSelected, [nativeRuntimeLlamaCpp, nativeRuntimeLiteRtLm]);
    });

    test('uses exact target runtime override before OS-level config', () {
      final rawUserConfig = {
        'runtimes': ['llama_cpp', 'litert_lm'],
        'platforms': {
          'ios': ['llama_cpp'],
          'ios-arm64': ['litert_lm'],
        },
      };

      final deviceSelected = selectNativeRuntimesForBundle(
        bundle: 'ios-arm64',
        rawUserConfig: rawUserConfig,
        warn: (_) {},
      );
      final simulatorSelected = selectNativeRuntimesForBundle(
        bundle: 'ios-arm64-sim',
        rawUserConfig: rawUserConfig,
        warn: (_) {},
      );

      expect(deviceSelected, [nativeRuntimeLiteRtLm]);
      expect(simulatorSelected, [nativeRuntimeLlamaCpp]);
    });

    test('supports direct OS runtime map shape', () {
      final rawUserConfig = {
        'ios': ['llama_cpp'],
        'macos': ['litert_lm'],
      };

      final iosSelected = selectNativeRuntimesForBundle(
        bundle: 'ios-arm64-sim',
        rawUserConfig: rawUserConfig,
        warn: (_) {},
      );
      final macosSelected = selectNativeRuntimesForBundle(
        bundle: 'macos-x86_64',
        rawUserConfig: rawUserConfig,
        warn: (_) {},
      );
      final linuxSelected = selectNativeRuntimesForBundle(
        bundle: 'linux-x64',
        rawUserConfig: rawUserConfig,
        warn: (_) {},
      );

      expect(iosSelected, [nativeRuntimeLlamaCpp]);
      expect(macosSelected, [nativeRuntimeLiteRtLm]);
      expect(linuxSelected, [nativeRuntimeLlamaCpp, nativeRuntimeLiteRtLm]);
    });

    test('supports map platform shape with runtimes key', () {
      final selected = selectNativeRuntimesForBundle(
        bundle: 'android-arm64',
        rawUserConfig: {
          'platforms': {
            'android-arm64': {
              'runtimes': ['llama.cpp'],
              'backends': ['vulkan'],
            },
          },
        },
        warn: (_) {},
      );

      expect(selected, [nativeRuntimeLlamaCpp]);
    });

    test('warns and ignores unknown runtime names', () {
      final warnings = <String>[];
      final selected = selectNativeRuntimesForBundle(
        bundle: 'linux-x64',
        rawUserConfig: ['litert_lm', 'onnx'],
        warn: warnings.add,
      );

      expect(selected, [nativeRuntimeLiteRtLm]);
      expect(warnings.single, contains('onnx'));
    });

    test('tracks explicit runtime requests separately from all/defaults', () {
      for (final rawUserConfig in const [
        null,
        '',
        <String>[],
        'all',
        ['both'],
        {'runtimes': <String>[]},
      ]) {
        expect(
          nativeRuntimeExplicitlySelectedForBundle(
            bundle: 'ios-x86_64-sim',
            rawUserConfig: rawUserConfig,
            runtime: nativeRuntimeLiteRtLm,
          ),
          isFalse,
          reason: rawUserConfig.toString(),
        );
      }

      expect(
        nativeRuntimeExplicitlySelectedForBundle(
          bundle: 'ios-x86_64-sim',
          rawUserConfig: ['litert_lm'],
          runtime: nativeRuntimeLiteRtLm,
        ),
        isTrue,
      );
      expect(
        nativeRuntimeExplicitlySelectedForBundle(
          bundle: 'ios-x86_64-sim',
          rawUserConfig: {
            'runtimes': ['litert_lm'],
            'platforms': {
              'ios-x86_64-sim': ['all'],
            },
          },
          runtime: nativeRuntimeLiteRtLm,
        ),
        isFalse,
      );
      expect(
        nativeRuntimeExplicitlySelectedForBundle(
          bundle: 'ios-x86_64-sim',
          rawUserConfig: {
            'runtimes': ['all'],
            'platforms': {
              'ios-x86_64-sim': ['litert_lm'],
            },
          },
          runtime: nativeRuntimeLiteRtLm,
        ),
        isTrue,
      );
    });
  });

  group('selectLibrariesForBundling', () {
    final spec = resolveNativeBundleSpec(
      os: OS.linux,
      arch: Architecture.x64,
      isIosSimulator: false,
    )!;

    final libraries = [
      describeNativeLibrary('/tmp/libllamadart.so'),
      describeNativeLibrary('/tmp/libllama.so'),
      describeNativeLibrary('/tmp/libllama-common.so'),
      describeNativeLibrary('/tmp/libggml.so'),
      describeNativeLibrary('/tmp/libggml-base.so'),
      describeNativeLibrary('/tmp/libggml-cpu.so'),
      describeNativeLibrary('/tmp/libggml-vulkan.so'),
      describeNativeLibrary('/tmp/libggml-opencl.so'),
    ];

    test('keeps defaults when no user config is provided', () {
      final selected = selectLibrariesForBundling(
        spec: spec,
        libraries: libraries,
        rawUserConfig: null,
        warn: (_) {},
      );

      final selectedNames = selected.map((item) => item.canonicalName).toSet();
      expect(selectedNames, contains('ggml-cpu'));
      expect(selectedNames, contains('ggml-vulkan'));
      expect(selectedNames, isNot(contains('ggml-opencl')));
      expect(selectedNames, contains('llama-common'));
    });

    test('uses requested backend when available', () {
      final selected = selectLibrariesForBundling(
        spec: spec,
        libraries: libraries,
        rawUserConfig: {
          'platforms': {
            'linux-x64': ['opencl'],
          },
        },
        warn: (_) {},
      );

      final selectedNames = selected.map((item) => item.canonicalName).toSet();
      expect(selectedNames, contains('ggml-cpu'));
      expect(selectedNames, contains('ggml-opencl'));
      expect(selectedNames, isNot(contains('ggml-vulkan')));
      expect(selectedNames, contains('llamadart'));
    });

    test('falls back to defaults when requested backend is unavailable', () {
      final warnings = <String>[];
      final selected = selectLibrariesForBundling(
        spec: spec,
        libraries: libraries,
        rawUserConfig: {
          'platforms': {
            'linux-x64': ['cuda'],
          },
        },
        warn: warnings.add,
      );

      final selectedNames = selected.map((item) => item.canonicalName).toSet();
      expect(selectedNames, contains('ggml-cpu'));
      expect(selectedNames, contains('ggml-vulkan'));
      expect(selectedNames, isNot(contains('ggml-opencl')));
      expect(warnings, isNotEmpty);
    });

    test(
      'filters backend runtime dependencies when backend is not selected',
      () {
        final windowsSpec = resolveNativeBundleSpec(
          os: OS.windows,
          arch: Architecture.x64,
          isIosSimulator: false,
        )!;
        final windowsLibraries = [
          describeNativeLibrary('/tmp/llamadart-windows-x64.dll'),
          describeNativeLibrary('/tmp/llama-windows-x64.dll'),
          describeNativeLibrary('/tmp/ggml-windows-x64.dll'),
          describeNativeLibrary('/tmp/ggml-base-windows-x64.dll'),
          describeNativeLibrary('/tmp/ggml-cpu-windows-x64.dll'),
          describeNativeLibrary('/tmp/ggml-vulkan-windows-x64.dll'),
          describeNativeLibrary('/tmp/ggml-cuda-windows-x64.dll'),
          describeNativeLibrary('/tmp/ggml-blas-windows-x64.dll'),
          describeNativeLibrary('/tmp/cudart64_12.dll'),
          describeNativeLibrary('/tmp/cublas64_12.dll'),
          describeNativeLibrary('/tmp/cublaslt64_12.dll'),
          describeNativeLibrary('/tmp/libopenblas.so.0'),
          describeNativeLibrary('/tmp/custom-runtime.dll'),
        ];

        final selected = selectLibrariesForBundling(
          spec: windowsSpec,
          libraries: windowsLibraries,
          rawUserConfig: {
            'platforms': {
              'windows-x64': ['vulkan', 'cpu'],
            },
          },
          warn: (_) {},
        );

        final selectedNames = selected
            .map((item) => item.canonicalName)
            .toSet();
        expect(selectedNames, contains('ggml-cpu'));
        expect(selectedNames, contains('ggml-vulkan'));
        expect(selectedNames, contains('custom-runtime'));
        expect(selectedNames, isNot(contains('ggml-cuda')));
        expect(selectedNames, isNot(contains('cudart64_12')));
        expect(selectedNames, isNot(contains('cublas64_12')));
        expect(selectedNames, isNot(contains('cublaslt64_12')));
        expect(selectedNames, isNot(contains('ggml-blas')));
        expect(selectedNames, isNot(contains('openblas')));
      },
    );

    test('keeps cuda runtime dependencies when cuda is selected', () {
      final windowsSpec = resolveNativeBundleSpec(
        os: OS.windows,
        arch: Architecture.x64,
        isIosSimulator: false,
      )!;
      final windowsLibraries = [
        describeNativeLibrary('/tmp/llamadart-windows-x64.dll'),
        describeNativeLibrary('/tmp/llama-windows-x64.dll'),
        describeNativeLibrary('/tmp/ggml-windows-x64.dll'),
        describeNativeLibrary('/tmp/ggml-base-windows-x64.dll'),
        describeNativeLibrary('/tmp/ggml-cpu-windows-x64.dll'),
        describeNativeLibrary('/tmp/ggml-vulkan-windows-x64.dll'),
        describeNativeLibrary('/tmp/ggml-cuda-windows-x64.dll'),
        describeNativeLibrary('/tmp/cudart64_12.dll'),
        describeNativeLibrary('/tmp/cublas64_12.dll'),
        describeNativeLibrary('/tmp/cublaslt64_12.dll'),
      ];

      final selected = selectLibrariesForBundling(
        spec: windowsSpec,
        libraries: windowsLibraries,
        rawUserConfig: {
          'platforms': {
            'windows-x64': ['cuda'],
          },
        },
        warn: (_) {},
      );

      final selectedNames = selected.map((item) => item.canonicalName).toSet();
      expect(selectedNames, contains('ggml-cpu'));
      expect(selectedNames, contains('ggml-cuda'));
      expect(selectedNames, contains('cudart64_12'));
      expect(selectedNames, contains('cublas64_12'));
      expect(selectedNames, contains('cublaslt64_12'));
      expect(selectedNames, isNot(contains('ggml-vulkan')));
    });

    test('keeps openblas runtime dependencies when blas is selected', () {
      final windowsSpec = resolveNativeBundleSpec(
        os: OS.windows,
        arch: Architecture.x64,
        isIosSimulator: false,
      )!;
      final windowsLibraries = [
        describeNativeLibrary('/tmp/llamadart-windows-x64.dll'),
        describeNativeLibrary('/tmp/llama-windows-x64.dll'),
        describeNativeLibrary('/tmp/ggml-windows-x64.dll'),
        describeNativeLibrary('/tmp/ggml-base-windows-x64.dll'),
        describeNativeLibrary('/tmp/ggml-cpu-windows-x64.dll'),
        describeNativeLibrary('/tmp/ggml-vulkan-windows-x64.dll'),
        describeNativeLibrary('/tmp/ggml-blas-windows-x64.dll'),
        describeNativeLibrary('/tmp/libopenblas.so.0'),
      ];

      final selected = selectLibrariesForBundling(
        spec: windowsSpec,
        libraries: windowsLibraries,
        rawUserConfig: {
          'platforms': {
            'windows-x64': ['blas'],
          },
        },
        warn: (_) {},
      );

      final selectedNames = selected.map((item) => item.canonicalName).toSet();
      expect(selectedNames, contains('ggml-cpu'));
      expect(selectedNames, contains('ggml-blas'));
      expect(selectedNames, contains('openblas'));
      expect(selectedNames, isNot(contains('ggml-vulkan')));
    });

    test('apple targets ignore backend config and include all libraries', () {
      final appleSpec = resolveNativeBundleSpec(
        os: OS.macOS,
        arch: Architecture.arm64,
        isIosSimulator: false,
      )!;

      final selected = selectLibrariesForBundling(
        spec: appleSpec,
        libraries: libraries,
        rawUserConfig: {
          'platforms': {
            'macos-arm64': ['cpu'],
          },
        },
        warn: (_) {},
      );

      expect(selected.length, libraries.length);
    });
  });

  group('android arm64 cpu policy selection', () {
    final spec = resolveNativeBundleSpec(
      os: OS.android,
      arch: Architecture.arm64,
      isIosSimulator: false,
    )!;

    final libraries = [
      describeNativeLibrary('/tmp/libllamadart.so'),
      describeNativeLibrary('/tmp/libllama.so'),
      describeNativeLibrary('/tmp/libllama-common.so'),
      describeNativeLibrary('/tmp/libggml.so'),
      describeNativeLibrary('/tmp/libggml-base.so'),
      describeNativeLibrary('/tmp/libggml-vulkan.so'),
      describeNativeLibrary('/tmp/libggml-cpu-android_armv8.0_1.so'),
      describeNativeLibrary('/tmp/libggml-cpu-android_armv8.2_1.so'),
      describeNativeLibrary('/tmp/libggml-cpu-android_armv8.2_2.so'),
      describeNativeLibrary('/tmp/libggml-cpu-android_armv8.6_1.so'),
      describeNativeLibrary('/tmp/libggml-cpu-android_armv9.0_1.so'),
      describeNativeLibrary('/tmp/libggml-cpu-android_armv9.2_1.so'),
      describeNativeLibrary('/tmp/libggml-cpu-android_armv9.2_2.so'),
    ];

    test('defaults to full cpu profile when unset', () {
      final selected = selectLibrariesForBundling(
        spec: spec,
        libraries: libraries,
        rawUserConfig: null,
        warn: (_) {},
      );

      final selectedNames = selected.map((item) => item.canonicalName).toSet();
      expect(selectedNames, contains('ggml-cpu-android_armv8.0_1'));
      expect(selectedNames, contains('ggml-cpu-android_armv8.2_1'));
      expect(selectedNames, contains('ggml-cpu-android_armv8.2_2'));
      expect(selectedNames, contains('ggml-cpu-android_armv8.6_1'));
      expect(selectedNames, contains('ggml-cpu-android_armv9.0_1'));
      expect(selectedNames, contains('ggml-cpu-android_armv9.2_1'));
      expect(selectedNames, contains('ggml-cpu-android_armv9.2_2'));
    });

    test('compact cpu profile keeps baseline variant only', () {
      final selected = selectLibrariesForBundling(
        spec: spec,
        libraries: libraries,
        rawUserConfig: {
          'platforms': {
            'android-arm64': {'cpu_profile': 'compact'},
          },
        },
        warn: (_) {},
      );

      final selectedNames = selected.map((item) => item.canonicalName).toSet();
      expect(selectedNames, contains('ggml-cpu-android_armv8.0_1'));
      expect(selectedNames, isNot(contains('ggml-cpu-android_armv8.2_1')));
      expect(selectedNames, isNot(contains('ggml-cpu-android_armv8.2_2')));
      expect(selectedNames, isNot(contains('ggml-cpu-android_armv8.6_1')));
      expect(selectedNames, isNot(contains('ggml-cpu-android_armv9.0_1')));
      expect(selectedNames, isNot(contains('ggml-cpu-android_armv9.2_1')));
      expect(selectedNames, isNot(contains('ggml-cpu-android_armv9.2_2')));
    });

    test('cpu_variants override cpu_profile', () {
      final selected = selectLibrariesForBundling(
        spec: spec,
        libraries: libraries,
        rawUserConfig: {
          'platforms': {
            'android-arm64': {
              'cpu_profile': 'compact',
              'cpu_variants': ['android_armv8.6_1', 'armv9_2_2'],
            },
          },
        },
        warn: (_) {},
      );

      final selectedNames = selected.map((item) => item.canonicalName).toSet();
      expect(selectedNames, contains('ggml-cpu-android_armv8.6_1'));
      expect(selectedNames, contains('ggml-cpu-android_armv9.2_2'));
      expect(selectedNames, isNot(contains('ggml-cpu-android_armv8.0_1')));
    });

    test('invalid cpu_profile falls back to full profile', () {
      final warnings = <String>[];
      final selected = selectLibrariesForBundling(
        spec: spec,
        libraries: libraries,
        rawUserConfig: {
          'platforms': {
            'android-arm64': {'cpu_profile': 'balanced'},
          },
        },
        warn: warnings.add,
      );

      final selectedNames = selected.map((item) => item.canonicalName).toSet();
      expect(selectedNames, contains('ggml-cpu-android_armv8.0_1'));
      expect(selectedNames, contains('ggml-cpu-android_armv9.2_2'));
      expect(
        warnings.any((warning) => warning.contains('Unknown cpu_profile')),
        isTrue,
      );
    });

    test('invalid cpu_variants fall back to cpu_profile/default selection', () {
      final warnings = <String>[];
      final selected = selectLibrariesForBundling(
        spec: spec,
        libraries: libraries,
        rawUserConfig: {
          'platforms': {
            'android-arm64': {
              'cpu_profile': 'compact',
              'cpu_variants': ['unknown_variant'],
            },
          },
        },
        warn: warnings.add,
      );

      final selectedNames = selected.map((item) => item.canonicalName).toSet();
      expect(selectedNames, contains('ggml-cpu-android_armv8.0_1'));
      expect(selectedNames, isNot(contains('ggml-cpu-android_armv9.2_2')));
      expect(
        warnings.any((warning) => warning.contains('No valid cpu_variants')),
        isTrue,
      );
    });
  });

  group('codeAssetNameForLibrary', () {
    test('maps Windows llama core to primary asset id', () {
      final spec = resolveNativeBundleSpec(
        os: OS.windows,
        arch: Architecture.x64,
        isIosSimulator: false,
      )!;
      final library = describeNativeLibrary('/tmp/llama-windows-x64.dll');

      expect(
        codeAssetNameForLibrary(spec: spec, library: library),
        'llamadart',
      );
    });

    test('maps Windows wrapper to non-primary asset id', () {
      final spec = resolveNativeBundleSpec(
        os: OS.windows,
        arch: Architecture.x64,
        isIosSimulator: false,
      )!;
      final library = describeNativeLibrary('/tmp/llamadart-windows-x64.dll');

      expect(
        codeAssetNameForLibrary(spec: spec, library: library),
        'llamadart_wrapper',
      );
    });

    test('keeps non-Windows primary mapping unchanged', () {
      final spec = resolveNativeBundleSpec(
        os: OS.linux,
        arch: Architecture.x64,
        isIosSimulator: false,
      )!;
      final library = describeNativeLibrary('/tmp/libllamadart.so');

      expect(
        codeAssetNameForLibrary(spec: spec, library: library),
        'llamadart',
      );
    });
  });
}
