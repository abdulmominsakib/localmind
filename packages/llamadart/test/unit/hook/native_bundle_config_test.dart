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
    test('defaults to the two default runtime families', () {
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

    test('parses both as the two default runtime families', () {
      for (final rawUserConfig in const <Object>[
        'both',
        ' Both ',
        ['both'],
      ]) {
        final selected = selectNativeRuntimesForBundle(
          bundle: 'linux-x64',
          rawUserConfig: rawUserConfig,
          warn: (_) {},
        );

        expect(selected, [
          nativeRuntimeLlamaCpp,
          nativeRuntimeLiteRtLm,
        ], reason: '$rawUserConfig');
      }
    });

    test('parses empty runtime list as the two default families', () {
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

    test('macOS x64 LiteRT-LM is explicit only for its exact bundle key', () {
      bool namedForMacOsX64(Object? rawUserConfig) =>
          nativeRuntimeNamedForExactBundle(
            bundle: 'macos-x86_64',
            rawUserConfig: rawUserConfig,
            runtime: nativeRuntimeLiteRtLm,
          );

      for (final key in ['macos-x86_64', 'macos-x64']) {
        expect(
          namedForMacOsX64({
            'platforms': {
              key: ['llama_cpp', 'litert_lm'],
            },
          }),
          isTrue,
          reason: key,
        );
      }
      for (final rawUserConfig in <Object?>[
        ['litert_lm'],
        {
          'runtimes': ['litert_lm'],
        },
        {
          'platforms': {
            'macos': ['litert_lm'],
          },
        },
        {
          'platforms': {
            'macos-arm64': ['litert_lm'],
          },
        },
        {
          'platforms': {
            'macos-x86_64': ['all'],
          },
        },
      ]) {
        expect(
          namedForMacOsX64(rawUserConfig),
          isFalse,
          reason: '$rawUserConfig',
        );
      }
    });
  });

  group('selectNativeRuntimesForBundle explicit none', () {
    List<String> select(Object? rawUserConfig, List<String> warnings) =>
        selectNativeRuntimesForBundle(
          bundle: 'linux-x64',
          rawUserConfig: rawUserConfig,
          warn: warnings.add,
        );

    test('explicit none tokens select nothing without warning', () {
      for (final rawUserConfig in const <Object?>[
        'none',
        'off',
        'false',
        false,
        ['none'],
        [false],
        ['llama_cpp', 'none'],
        ['llama_cpp', false],
        {'runtimes': 'none'},
        {'runtimes': false},
        {
          'runtimes': ['llama_cpp'],
          'platforms': {'linux-x64': 'none'},
        },
      ]) {
        final warnings = <String>[];

        expect(
          select(rawUserConfig, warnings),
          isEmpty,
          reason: rawUserConfig.toString(),
        );
        expect(warnings, isEmpty, reason: rawUserConfig.toString());
      }
    });

    test('a runtime named after none still selects', () {
      final warnings = <String>[];

      expect(select(const ['none', 'llama_cpp'], warnings), [
        nativeRuntimeLlamaCpp,
      ]);
      expect(warnings, isEmpty);
    });

    test('unset, empty, and unsupported root scalars stay all', () {
      for (final rawUserConfig in const <Object?>[null, '', <String>[]]) {
        final warnings = <String>[];

        expect(select(rawUserConfig, warnings), [
          nativeRuntimeLlamaCpp,
          nativeRuntimeLiteRtLm,
        ], reason: rawUserConfig.toString());
        expect(warnings, isEmpty, reason: rawUserConfig.toString());
      }

      final warnings = <String>[];
      expect(select(true, warnings), [
        nativeRuntimeLlamaCpp,
        nativeRuntimeLiteRtLm,
      ]);
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('true'));
    });

    test('all-unrecognised list warns and stays the two default families', () {
      final warnings = <String>[];

      expect(select(const ['tflite', 'onnx'], warnings), [
        nativeRuntimeLlamaCpp,
        nativeRuntimeLiteRtLm,
      ]);
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('tflite, onnx'));

      warnings.clear();
      expect(select(const ['none', 'tflite'], warnings), isEmpty);
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('tflite'));
    });

    test('none clears explicit runtime tracking', () {
      expect(
        nativeRuntimeExplicitlySelectedForBundle(
          bundle: 'linux-x64',
          rawUserConfig: const ['llama_cpp', 'none'],
          runtime: nativeRuntimeLlamaCpp,
        ),
        isFalse,
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

  group('stable_diffusion runtime selection', () {
    List<String> select(Object? rawUserConfig, List<String> warnings) =>
        selectNativeRuntimesForBundle(
          bundle: 'linux-x64',
          rawUserConfig: rawUserConfig,
          warn: warnings.add,
        );

    test('is never selected by default, an empty or unrecognised value, or '
        'both', () {
      for (final rawUserConfig in const <Object?>[
        null,
        '',
        <String>[],
        'both',
        ['both'],
        ['tflite'],
        true,
        {'runtimes': <String>[]},
        {'runtimes': 'both'},
        {
          'platforms': {
            'android': ['all'],
          },
        },
      ]) {
        final warnings = <String>[];
        expect(select(rawUserConfig, warnings), [
          nativeRuntimeLlamaCpp,
          nativeRuntimeLiteRtLm,
        ], reason: rawUserConfig.toString());
      }
      expect(defaultNativeRuntimes, [
        nativeRuntimeLlamaCpp,
        nativeRuntimeLiteRtLm,
      ]);
    });

    test('is selected by all, after the two default families', () {
      for (final rawUserConfig in const <Object?>[
        'all',
        ' ALL ',
        ['all'],
        ['both', 'all'],
        ['all', 'stable_diffusion'],
        ['llama_cpp', 'all'],
        {'runtimes': 'all'},
        {
          'runtimes': ['llama_cpp'],
          'platforms': {'linux': 'all'},
        },
      ]) {
        final warnings = <String>[];
        expect(select(rawUserConfig, warnings), [
          nativeRuntimeLlamaCpp,
          nativeRuntimeLiteRtLm,
          nativeRuntimeStableDiffusion,
        ], reason: rawUserConfig.toString());
        expect(warnings, isEmpty, reason: rawUserConfig.toString());
      }
      expect(select(const ['stable_diffusion', 'all'], []), [
        nativeRuntimeStableDiffusion,
        nativeRuntimeLlamaCpp,
        nativeRuntimeLiteRtLm,
      ]);
      expect(select(const ['all', 'none'], []), isEmpty);
    });

    test('is selected when named, including the stable-diffusion alias', () {
      for (final rawUserConfig in const <Object?>[
        ['stable_diffusion'],
        'stable-diffusion',
        ' Stable_Diffusion ',
        {'runtimes': 'stable_diffusion'},
      ]) {
        final warnings = <String>[];
        expect(select(rawUserConfig, warnings), [
          nativeRuntimeStableDiffusion,
        ], reason: rawUserConfig.toString());
        expect(warnings, isEmpty, reason: rawUserConfig.toString());
      }

      final warnings = <String>[];
      expect(select(const ['llama_cpp', 'stable_diffusion'], warnings), [
        nativeRuntimeLlamaCpp,
        nativeRuntimeStableDiffusion,
      ]);
      expect(select(const ['stable_diffusion', 'none'], warnings), isEmpty);
      expect(warnings, isEmpty);
    });

    test('all implies every runtime on every bundle and names none', () {
      for (final bundle in const [
        'android-arm64',
        'android-x64',
        'ios-arm64',
        'ios-arm64-sim',
        'ios-x86_64-sim',
        'linux-arm64',
        'linux-x64',
        'macos-arm64',
        'macos-x86_64',
        'windows-arm64',
        'windows-x64',
      ]) {
        for (final rawUserConfig in const <Object>[
          'all',
          ['all'],
          ['all', 'stable_diffusion'],
        ]) {
          final reason = '$bundle $rawUserConfig';
          final warnings = <String>[];
          expect(
            selectNativeRuntimesForBundle(
              bundle: bundle,
              rawUserConfig: rawUserConfig,
              warn: warnings.add,
            ),
            [
              nativeRuntimeLlamaCpp,
              nativeRuntimeLiteRtLm,
              nativeRuntimeStableDiffusion,
            ],
            reason: reason,
          );
          expect(warnings, isEmpty, reason: reason);
          // What lets `hook/build.dart` skip a runtime `all` implies with a
          // warning instead of failing the build.
          expect(
            nativeRuntimeExplicitlySelectedForBundle(
              bundle: bundle,
              rawUserConfig: rawUserConfig,
              runtime: nativeRuntimeLiteRtLm,
            ),
            isFalse,
            reason: reason,
          );
          expect(
            nativeRuntimeExplicitlySelectedForBundle(
              bundle: bundle,
              rawUserConfig: rawUserConfig,
              runtime: nativeRuntimeStableDiffusion,
            ),
            rawUserConfig is List && rawUserConfig.length == 2,
            reason: reason,
          );
          expect(
            nativeRuntimeNamedForExactBundle(
              bundle: bundle,
              rawUserConfig: rawUserConfig,
              runtime: nativeRuntimeStableDiffusion,
            ),
            isFalse,
            reason: reason,
          );
        }
      }
    });

    test('all and both never count as an explicitly selected runtime', () {
      for (final runtime in const ['all', 'both', 'none']) {
        expect(
          nativeRuntimeExplicitlySelectedForBundle(
            bundle: 'linux-x64',
            rawUserConfig: const ['all', 'both', 'llama_cpp'],
            runtime: runtime,
          ),
          isFalse,
          reason: runtime,
        );
      }
    });

    test('unknown-runtime warning lists stable_diffusion as supported', () {
      final warnings = <String>[];
      select(const ['onnx'], warnings);
      expect(
        warnings.single,
        contains('Supported runtimes: llama_cpp, litert_lm, stable_diffusion.'),
      );
    });

    test('bundle-scoped naming is detected only for the exact bundle', () {
      bool named(Object? rawUserConfig, {String bundle = 'android-x64'}) =>
          nativeRuntimeNamedForExactBundle(
            bundle: bundle,
            rawUserConfig: rawUserConfig,
            runtime: nativeRuntimeStableDiffusion,
          );

      expect(
        named({
          'platforms': {
            'android-x64': ['stable_diffusion'],
          },
        }),
        isTrue,
      );
      expect(
        named({
          'platforms': {
            'android_x86_64': {'runtimes': 'llama_cpp,stable-diffusion'},
          },
        }),
        isTrue,
      );
      expect(
        named({
          'android-x64': ['stable_diffusion'],
        }),
        isTrue,
      );
      for (final rawUserConfig in const <Object?>[
        null,
        ['stable_diffusion'],
        {'runtimes': 'stable_diffusion'},
        {
          'platforms': {
            'android': ['stable_diffusion'],
          },
        },
        {
          'platforms': {
            'android-arm64': ['stable_diffusion'],
          },
        },
        {
          'platforms': {
            'android-x64': ['stable_diffusion', 'none'],
          },
        },
        {
          'platforms': {
            'android-x64': ['all'],
          },
        },
      ]) {
        expect(named(rawUserConfig), isFalse, reason: rawUserConfig.toString());
      }
    });
  });

  group('stableDiffusionBundleForNativeBundle', () {
    NativeBundleSpec spec(OS os, Architecture arch, {bool sim = false}) =>
        resolveNativeBundleSpec(os: os, arch: arch, isIosSimulator: sim)!;

    test('maps Apple and Android bundles to their single archive', () {
      final expected = {
        spec(OS.android, Architecture.arm64): 'android-arm64',
        spec(OS.iOS, Architecture.arm64): 'ios-arm64',
        spec(OS.iOS, Architecture.arm64, sim: true): 'ios-arm64-sim',
        spec(OS.iOS, Architecture.x64, sim: true): 'ios-x64-sim',
        spec(OS.macOS, Architecture.arm64): 'macos-arm64',
        spec(OS.macOS, Architecture.x64): 'macos-x64',
      };
      for (final MapEntry(key: nativeSpec, value: bundle) in expected.entries) {
        for (final rawBackendConfig in const <Object?>[
          null,
          {
            'platforms': {'android': 'cpu,vulkan', 'macos': 'vulkan'},
          },
        ]) {
          expect(
            stableDiffusionBundleForNativeBundle(
              spec: nativeSpec,
              rawBackendConfig: rawBackendConfig,
            ),
            bundle,
            reason: '${nativeSpec.bundle} $rawBackendConfig',
          );
        }
      }
    });

    test('returns null where no archive is published', () {
      for (final nativeSpec in [
        spec(OS.android, Architecture.x64),
        spec(OS.windows, Architecture.arm64),
      ]) {
        expect(
          stableDiffusionBundleForNativeBundle(
            spec: nativeSpec,
            rawBackendConfig: null,
          ),
          isNull,
          reason: nativeSpec.bundle,
        );
      }
    });

    test('follows the llama.cpp Vulkan selection on Linux and Windows', () {
      for (final (os, arch, base) in [
        (OS.linux, Architecture.x64, 'linux-x64'),
        (OS.linux, Architecture.arm64, 'linux-arm64'),
        (OS.windows, Architecture.x64, 'windows-x64'),
      ]) {
        final nativeSpec = spec(os, arch);
        String? select(Object? rawBackendConfig) =>
            stableDiffusionBundleForNativeBundle(
              spec: nativeSpec,
              rawBackendConfig: rawBackendConfig,
            );

        expect(select(null), '$base-vulkan', reason: 'defaults include vulkan');
        expect(
          select({
            'platforms': {nativeSpec.bundle: <String>[]},
          }),
          '$base-vulkan',
        );
        expect(
          select({
            'platforms': {nativeSpec.bundle: 'cpu'},
          }),
          base,
        );
        expect(
          select({
            'platforms': {
              os.name: {
                'backends': ['cpu', 'vk'],
              },
            },
          }),
          '$base-vulkan',
        );
        expect(
          select({
            'platforms': {'android': 'cpu'},
          }),
          '$base-vulkan',
          reason: 'another platform entry leaves the defaults',
        );
      }
    });

    test('llamadart_stable_diffusion_backends overrides the llama.cpp choice '
        'on Linux and Windows', () {
      for (final (os, arch, base) in [
        (OS.linux, Architecture.x64, 'linux-x64'),
        (OS.linux, Architecture.arm64, 'linux-arm64'),
        (OS.windows, Architecture.x64, 'windows-x64'),
      ]) {
        final nativeSpec = spec(os, arch);
        final warnings = <String>[];
        String? select(Object? llamaCpp, Object? stableDiffusion) =>
            stableDiffusionBundleForNativeBundle(
              spec: nativeSpec,
              rawBackendConfig: llamaCpp,
              rawStableDiffusionBackendConfig: stableDiffusion,
              warn: warnings.add,
            );

        expect(select(null, ['cpu']), base, reason: 'CPU beside Vulkan text');
        expect(
          select({
            'platforms': {os.name: 'cpu'},
          }, 'vulkan'),
          '$base-vulkan',
          reason: 'Vulkan images beside CPU-only text',
        );
        expect(
          select(null, {
            'platforms': {
              nativeSpec.bundle: {
                'backends': ['cpu'],
              },
            },
          }),
          base,
        );
        expect(
          select(null, {
            'platforms': {'android': 'cpu'},
          }),
          '$base-vulkan',
          reason: 'an entry for another platform leaves the llama.cpp choice',
        );
        expect(warnings, isEmpty);

        expect(select(null, 'cuda'), '$base-vulkan');
        expect(
          warnings.single,
          allOf(
            contains('llamadart_stable_diffusion_backends'),
            contains(nativeSpec.bundle),
            contains('cuda'),
          ),
        );
      }
    });

    test('llamadart_stable_diffusion_backends picks Vulkan over CPU in a '
        'mixed list', () {
      for (final (os, arch, base) in [
        (OS.linux, Architecture.x64, 'linux-x64'),
        (OS.windows, Architecture.x64, 'windows-x64'),
      ]) {
        final nativeSpec = spec(os, arch);
        final warnings = <String>[];
        for (final mixed in <Object>[
          ['cpu', 'vulkan'],
          ['vulkan', 'cpu'],
          'cpu, vk',
          {
            'platforms': {
              os.name: ['cpu', 'vulkan'],
            },
          },
        ]) {
          expect(
            stableDiffusionBundleForNativeBundle(
              spec: nativeSpec,
              rawBackendConfig: {
                'platforms': {os.name: 'cpu'},
              },
              rawStableDiffusionBackendConfig: mixed,
              warn: warnings.add,
            ),
            '$base-vulkan',
            reason: '$mixed',
          );
        }
        expect(warnings, isEmpty);
      }
    });

    test('an empty llamadart_stable_diffusion_backends neither warns nor '
        'overrides the llama.cpp choice', () {
      for (final (os, arch, base) in [
        (OS.linux, Architecture.x64, 'linux-x64'),
        (OS.windows, Architecture.x64, 'windows-x64'),
      ]) {
        final nativeSpec = spec(os, arch);
        for (final empty in <Object>[
          <String>[],
          '',
          {
            'platforms': {os.name: <String>[]},
          },
          {
            'platforms': {
              os.name: {'backends': <String>[]},
            },
          },
        ]) {
          final warnings = <String>[];
          String? select(Object? llamaCpp) =>
              stableDiffusionBundleForNativeBundle(
                spec: nativeSpec,
                rawBackendConfig: llamaCpp,
                rawStableDiffusionBackendConfig: empty,
                warn: warnings.add,
              );

          expect(select(null), '$base-vulkan', reason: '$empty');
          expect(
            select({
              'platforms': {os.name: 'cpu'},
            }),
            base,
            reason: '$empty',
          );
          expect(warnings, isEmpty, reason: '$empty');
        }
      }
    });

    test('llamadart_stable_diffusion_backends does not change Apple or '
        'Android archives', () {
      for (final (nativeSpec, bundle) in [
        (spec(OS.android, Architecture.arm64), 'android-arm64'),
        (spec(OS.macOS, Architecture.arm64), 'macos-arm64'),
        (spec(OS.iOS, Architecture.arm64), 'ios-arm64'),
      ]) {
        expect(
          stableDiffusionBundleForNativeBundle(
            spec: nativeSpec,
            rawBackendConfig: null,
            rawStableDiffusionBackendConfig: 'vulkan',
          ),
          bundle,
        );
      }
    });
  });
}
