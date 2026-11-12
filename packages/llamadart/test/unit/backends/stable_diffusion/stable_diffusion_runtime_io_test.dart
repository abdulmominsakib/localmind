@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';

import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_calls.dart';
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_runtime_io.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/hook/native_bundle_config.dart';
import 'package:llamadart/src/platform/io/ios_simulator.dart';

const _dotProductCpuInfo =
    'Features\t: fp asimd atomics fphp asimdhp asimddp\n';
const _haswellCpuInfo = 'flags\t\t: fpu sse4_2 avx f16c fma avx2 bmi2\n';

void main() {
  test('stableDiffusionHostIsMacosX64 follows the process ABI', () {
    expect(stableDiffusionHostIsMacosX64(), Abi.current() == Abi.macosX64);
  });

  group('probeStableDiffusionRuntime', () {
    test('reports version, commit and devices from a loaded runtime', () {
      final status = probeStableDiffusionRuntime(
        abi: Abi.macosArm64,
        api: _FakeApi(devices: 'CPU\tApple M4\nMTL0\tApple M4\n'),
      );

      expect(status.isAvailable, isTrue);
      expect(status.version, 'v-test');
      expect(status.commit, 'c0ffee');
      expect(status.devices.map((device) => device.name), ['CPU', 'MTL0']);
      expect(status.loadsFp8AsF16OnMetal, isFalse);
    });

    test('names the iOS simulator target, not the device, when the '
        'runtime is not bundled', () {
      String reasonOn({Abi abi = Abi.iosArm64, required bool simulator}) {
        final status = probeStableDiffusionRuntime(
          abi: abi,
          isIosSimulator: () => simulator,
          api: _FakeApi(
            error: ArgumentError(
              "Couldn't resolve native function 'sd_version' in "
              "'package:llamadart/stable_diffusion' : No asset with id "
              "'package:llamadart/stable_diffusion' found.",
            ),
          ),
        );
        return status.unavailableReason!.message;
      }

      expect(
        reasonOn(simulator: true),
        contains('not bundled for ios-arm64-sim.'),
      );
      expect(
        reasonOn(simulator: false),
        contains('not bundled for ios-arm64.'),
      );
      expect(
        reasonOn(abi: Abi.iosX64, simulator: true),
        contains('not bundled for ios-x64-sim.'),
      );
    });

    test('iOS labels are the build hook stable_diffusion bundle keys', () {
      for (final (abi, arch, simulator) in [
        (Abi.iosArm64, Architecture.arm64, false),
        (Abi.iosArm64, Architecture.arm64, true),
        (Abi.iosX64, Architecture.x64, true),
      ]) {
        final bundle = stableDiffusionBundleForNativeBundle(
          spec: resolveNativeBundleSpec(
            os: OS.iOS,
            arch: arch,
            isIosSimulator: simulator,
          )!,
          rawBackendConfig: null,
        );
        final status = probeStableDiffusionRuntime(
          abi: abi,
          isIosSimulator: () => simulator,
          api: _FakeApi(
            error: ArgumentError(
              "No asset with id 'package:llamadart/stable_diffusion' found.",
            ),
          ),
        );
        expect(
          status.unavailableReason!.message,
          contains('not bundled for $bundle.'),
          reason: '$abi simulator: $simulator',
        );
      }
    });

    test('the default simulator check labels arm64 iOS as the device on a '
        'host that is not a simulator', () {
      final status = probeStableDiffusionRuntime(
        abi: Abi.iosArm64,
        api: _FakeApi(
          error: ArgumentError(
            "Couldn't resolve native function 'sd_version' in "
            "'package:llamadart/stable_diffusion' : No asset with id "
            "'package:llamadart/stable_diffusion' found.",
          ),
        ),
      );

      expect(isIosSimulatorProcess(), isFalse);
      expect(
        status.unavailableReason!.message,
        contains('not bundled for ios-arm64.'),
      );
    });

    test('reports the native intrinsic tiny-decoder invariant capability', () {
      for (final supported in [false, true]) {
        final status = probeStableDiffusionRuntime(
          abi: Abi.macosArm64,
          api: _FakeApi(intrinsicTinyV1: supported),
        );
        expect(status.supportsIntrinsicTinyDecoderV1, supported);
      }
      final absent = BundledStableDiffusionApi(resolveCalls: () => null);
      expect(absent.supportsIntrinsicTinyDecoderV1(), isFalse);
    });

    test('reports whether the runtime loads FP8 weights as F16 on Metal', () {
      for (final fp8Metal in [true, false]) {
        final status = probeStableDiffusionRuntime(
          abi: Abi.macosArm64,
          api: _FakeApi(fp8Metal: fp8Metal),
        );

        expect(status.loadsFp8AsF16OnMetal, fp8Metal);
      }
    });

    test('the bundled API reports FP8-as-F16 on Metal only for a runtime '
        'that resolves the upstream 1017 functions', () {
      StableDiffusionCalls? resolve({
        String releaseTag = StableDiffusionCalls.fp8MetalNativeRelease,
        Set<String> missing = const {},
      }) => StableDiffusionCalls.tryResolve(
        symbol: (name) => missing.contains(name)
            ? throw ArgumentError("Couldn't resolve native function '$name'")
            : Pointer.fromAddress(0x1000),
        releaseTag: releaseTag,
      );
      bool loads(StableDiffusionCalls? Function() resolveCalls) =>
          BundledStableDiffusionApi(
            resolveCalls: resolveCalls,
          ).loadsFp8AsF16OnMetal();

      expect(loads(resolve), isTrue);
      expect(loads(() => null), isFalse);
      expect(
        loads(
          () => resolve(missing: StableDiffusionCalls.fp8MetalSymbols.toSet()),
        ),
        isFalse,
      );
      expect(loads(() => resolve(releaseTag: 'v0.3.0')), isFalse);
    });

    test('records the log at the given level before the device list, which '
        'initializes the GPU backend and logs', () {
      for (final level in [LlamaLogLevel.none, LlamaLogLevel.info]) {
        final api = _FakeApi();

        probeStableDiffusionRuntime(
          abi: Abi.macosArm64,
          api: api,
          logLevel: level,
        );

        expect(api.order, ['recordLog ${level.name}', 'listDevices']);
      }
      final api = _FakeApi();
      probeStableDiffusionRuntime(abi: Abi.macosArm64, api: api);
      expect(api.order.first, 'recordLog none');
    });

    test('a runtime without the sd_dart_ functions is unavailable, and the '
        'reason names them and the release that has them', () {
      final status = probeStableDiffusionRuntime(
        abi: Abi.macosArm64,
        api: _FakeApi(wrapperCalls: false),
      );

      expect(status.isAvailable, isFalse);
      expect(
        status.unavailableReason?.message,
        allOf(
          contains('does not export the sd_dart_ functions'),
          contains('sd_dart_progress_read'),
          contains('sd_dart_exit_free'),
          contains('stable-diffusion-native v0.2.0-1 or later'),
        ),
      );
    });

    test('rejects an unpublished ABI before touching the library', () {
      for (final abi in [Abi.androidX64, Abi.windowsArm64, Abi.linuxArm]) {
        final api = _FakeApi();
        final status = probeStableDiffusionRuntime(abi: abi, api: api);

        expect(api.calls, 0, reason: '$abi');
        expect(
          status.unavailableReason?.message,
          allOf(
            contains('stable_diffusion runtime is not published for'),
            contains(abi.toString().replaceAll('_', '-')),
          ),
        );
      }
    });

    test('an unpublished ABI is told the targets the hook has bundles for', () {
      const hostTargets = [
        (OS.android, Architecture.arm64, false),
        (OS.android, Architecture.x64, false),
        (OS.iOS, Architecture.arm64, false),
        (OS.iOS, Architecture.arm64, true),
        (OS.iOS, Architecture.x64, true),
        (OS.linux, Architecture.arm64, false),
        (OS.linux, Architecture.x64, false),
        (OS.macOS, Architecture.arm64, false),
        (OS.macOS, Architecture.x64, false),
        (OS.windows, Architecture.arm64, false),
        (OS.windows, Architecture.x64, false),
      ];
      final hookBundles = {
        for (final (os, arch, simulator) in hostTargets)
          stableDiffusionBundleForNativeBundle(
            spec: resolveNativeBundleSpec(
              os: os,
              arch: arch,
              isIosSimulator: simulator,
            )!,
            rawBackendConfig: null,
            rawStableDiffusionBackendConfig: 'cpu',
          ),
      }..remove(null);

      final message = probeStableDiffusionRuntime(
        abi: Abi.androidX64,
        api: _FakeApi(),
      ).unavailableReason!.message;
      final named = message
          .substring(message.indexOf('available on ') + 13, message.length - 1)
          .split(RegExp(r', | and '))
          .toSet();

      expect(named, hookBundles);
    });

    test('Android arm64 without asimddp never loads the library', () {
      for (final cpuInfo in [
        'Features\t: fp asimd atomics\n',
        '${_dotProductCpuInfo}Features\t: fp asimd\n',
        null,
      ]) {
        final api = _FakeApi();
        final status = probeStableDiffusionRuntime(
          abi: Abi.androidArm64,
          readCpuInfo: () => cpuInfo,
          api: api,
        );

        expect(api.calls, 0, reason: cpuInfo);
        expect(
          status.unavailableReason?.message,
          allOf(
            contains('android-arm64'),
            contains('Armv8.2 dot-product and fp16 (asimddp, fphp, asimdhp)'),
          ),
          reason: cpuInfo,
        );
      }
    });

    test('Android arm64 with the required features on every core loads the '
        'library', () {
      final api = _FakeApi();
      final status = probeStableDiffusionRuntime(
        abi: Abi.androidArm64,
        readCpuInfo: () => _dotProductCpuInfo * 8,
        api: api,
      );

      expect(status.isAvailable, isTrue);
      expect(api.calls, greaterThan(0));
    });

    test('Arm desktop and Apple probes check no CPU features', () {
      for (final abi in [Abi.linuxArm64, Abi.macosArm64, Abi.macosX64]) {
        final status = probeStableDiffusionRuntime(
          abi: abi,
          readCpuInfo: () => fail('cpuinfo is not read on $abi'),
          windowsHasAvx2: () => fail('Windows is not queried on $abi'),
          api: _FakeApi(),
        );

        expect(status.isAvailable, isTrue, reason: '$abi');
      }
    });

    test('Linux x64 without AVX2, FMA, F16C or BMI2 never loads the '
        'library', () {
      for (final cpuInfo in [
        'flags\t\t: fpu sse4_2 avx popcnt\n',
        '$_haswellCpuInfo${'flags\t\t: fpu sse4_2 avx avx2\n'}',
        null,
      ]) {
        final api = _FakeApi();
        final status = probeStableDiffusionRuntime(
          abi: Abi.linuxX64,
          readCpuInfo: () => cpuInfo,
          api: api,
        );

        expect(api.calls, 0, reason: cpuInfo);
        expect(
          status.unavailableReason?.message,
          allOf(
            contains('linux-x64'),
            contains('AVX2, FMA, F16C, BMI2'),
            cpuInfo == null
                ? contains('could not be read')
                : contains('does not report them'),
          ),
          reason: cpuInfo,
        );
      }
    });

    test('Linux x64 with the required features on every core loads the '
        'library', () {
      final api = _FakeApi();
      final status = probeStableDiffusionRuntime(
        abi: Abi.linuxX64,
        readCpuInfo: () => _haswellCpuInfo * 8,
        api: api,
      );

      expect(status.isAvailable, isTrue);
      expect(api.calls, greaterThan(0));
    });

    test('Windows x64 requires AVX2 before loading the library', () {
      final api = _FakeApi();
      final rejected = probeStableDiffusionRuntime(
        abi: Abi.windowsX64,
        readCpuInfo: () => fail('cpuinfo is not read on Windows'),
        windowsHasAvx2: () => false,
        api: api,
      );

      expect(api.calls, 0);
      expect(
        rejected.unavailableReason?.message,
        allOf(contains('windows-x64'), contains('does not report AVX2')),
      );

      final accepted = probeStableDiffusionRuntime(
        abi: Abi.windowsX64,
        windowsHasAvx2: () => true,
        api: api,
      );
      expect(accepted.isAvailable, isTrue);
    });

    test('the x86_64 iOS simulator loads without a CPU feature check', () {
      final api = _FakeApi();
      final status = probeStableDiffusionRuntime(abi: Abi.iosX64, api: api);

      expect(status.isAvailable, isTrue);
      expect(api.calls, greaterThan(0));
    });

    test('a missing native asset reports how to opt in', () {
      final status = probeStableDiffusionRuntime(
        abi: Abi.linuxX64,
        readCpuInfo: () => _haswellCpuInfo,
        api: _FakeApi(
          error: ArgumentError(
            "Couldn't resolve native function 'sd_version' in "
            "'package:llamadart/stable_diffusion' : No asset with id "
            "'package:llamadart/stable_diffusion' found. Available native "
            'assets: package:llamadart/llamadart. Attempted to fallback to '
            'process lookup. dlsym(RTLD_DEFAULT, sd_version): symbol not '
            'found.',
          ),
        ),
      );

      expect(
        status.unavailableReason,
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          'stable_diffusion runtime is not bundled for linux-x64; set '
              'hooks.user_defines.llamadart.llamadart_native_runtimes to '
              'all, or add stable_diffusion to its list, and rebuild. A list '
              'replaces the default llama_cpp and litert_lm.',
        ),
      );
    });
  });

  group('stableDiffusionLoadFailure', () {
    String messageFor(String detail) => stableDiffusionLoadFailure(
      platform: 'linux-x64',
      error: ArgumentError(detail),
    ).message;

    test('names the Vulkan loader when the Vulkan variant cannot load', () {
      final message = messageFor(
        "Couldn't resolve native function 'sd_version' in "
        "'package:llamadart/stable_diffusion' : Failed to load dynamic "
        "library '/app/lib/libstable-diffusion.so': libvulkan.so.1: cannot "
        'open shared object file: No such file or directory',
      );

      expect(message, contains('Vulkan variant'));
      expect(message, contains('libvulkan.so.1'));
      expect(message, contains('llamadart_stable_diffusion_backends to [cpu]'));
      expect(message, isNot(contains('/app/lib')));
    });

    test('a missing asset beside llama.cpp Vulkan assets is not a loader '
        'failure', () {
      // Default Linux and Windows builds bundle llama.cpp's ggml-vulkan, and
      // the VM lists every bundled asset in the missing-asset message.
      final message = messageFor(
        "Couldn't resolve native function 'sd_version' in "
        "'package:llamadart/stable_diffusion' : No asset with id "
        "'package:llamadart/stable_diffusion' found. Available native "
        'assets: package:llamadart/llamadart, package:llamadart/ggml-base, '
        'package:llamadart/ggml-cpu, package:llamadart/ggml-vulkan. Attempted '
        'to fallback to process lookup.',
      );

      expect(message, contains('not bundled for linux-x64'));
      expect(message, isNot(contains('Vulkan variant')));
    });

    test('a path containing "vulkan" is not a loader failure', () {
      final message = messageFor(
        "Couldn't resolve native function 'sd_version' in "
        "'package:llamadart/stable_diffusion' : Failed to load dynamic "
        "library '/opt/vulkan-demo/lib/libstable-diffusion.so': "
        'libstdc++.so.6: cannot open shared object file',
      );

      expect(message, isNot(contains('Vulkan variant')));
      expect(message, contains('could not be loaded on linux-x64'));
    });

    test('reports a symbol missing from a mismatched runtime', () {
      final message = messageFor(
        "Couldn't resolve native function 'sd_list_devices' in "
        "'package:llamadart/stable_diffusion' : Failed to lookup symbol "
        "'sd_list_devices': undefined symbol: sd_list_devices",
      );

      expect(message, contains('does not export the stable-diffusion.h API'));
    });

    test('names the Flutter Apple companion only on iOS and macOS', () {
      const missingAsset =
          "Couldn't resolve native function 'sd_version' in "
          "'package:llamadart/stable_diffusion' : No asset with id "
          "'package:llamadart/stable_diffusion' found.";
      for (final platform in ['ios-arm64', 'macos-x64']) {
        final message = stableDiffusionLoadFailure(
          platform: platform,
          error: ArgumentError(missingAsset),
        ).message;
        expect(
          message,
          'stable_diffusion runtime is not bundled for $platform. In a '
          'Flutter iOS/macOS app, add the '
          'llamadart_stable_diffusion_flutter package and rebuild: without '
          'it the build hook leaves out a stable_diffusion that all only '
          'implies. Naming stable_diffusion in '
          'hooks.user_defines.llamadart.llamadart_native_runtimes bundles it '
          'through the hook instead, in a framework App Store Connect '
          'rejects on iOS. In any other build, set '
          'hooks.user_defines.llamadart.llamadart_native_runtimes to all, or '
          'add stable_diffusion to its list, and rebuild. A list replaces '
          'the default llama_cpp and litert_lm.',
          reason: platform,
        );
      }
      expect(
        messageFor(missingAsset),
        isNot(contains('llamadart_stable_diffusion_flutter')),
      );
    });

    test('an unlinked Apple framework points at Swift Package Manager', () {
      String messageOn({required bool flutterTestHost}) =>
          stableDiffusionLoadFailure(
            platform: 'ios-arm64',
            error: ArgumentError(
              "Couldn't resolve native function 'sd_version' in "
              "'package:llamadart/stable_diffusion' : Failed to lookup symbol "
              "'sd_version': dlsym(RTLD_DEFAULT, sd_version): symbol not found",
            ),
            isFlutterTestHost: () => flutterTestHost,
          ).message;

      expect(
        messageOn(flutterTestHost: false),
        allOf(
          contains('not linked into the process on ios-arm64'),
          contains('flutter config --enable-swift-package-manager'),
          contains('llamadart_stable_diffusion_flutter'),
          contains('Host `flutter test` runs never link the companion'),
        ),
      );
      expect(
        messageOn(flutterTestHost: true),
        allOf(
          contains('not linked into the flutter test host on ios-arm64'),
          contains('llamadart_stable_diffusion_flutter'),
          contains('integration test'),
          isNot(contains('enable-swift-package-manager')),
        ),
      );
    });

    test('detects a flutter test host from FLUTTER_TEST', () {
      expect(isFlutterTestEnvironment({'FLUTTER_TEST': 'true'}), isTrue);
      expect(isFlutterTestEnvironment({'FLUTTER_TEST': 'false'}), isFalse);
      expect(isFlutterTestEnvironment({'FLUTTER_TESTS': 'true'}), isFalse);
      expect(isFlutterTestEnvironment(const {}), isFalse);
      expect(
        isFlutterTestEnvironment(),
        Platform.environment['FLUTTER_TEST'] == 'true',
      );
    });

    test('reads FLUTTER_TEST from the process by default', () {
      final dir = Directory.systemTemp.createTempSync('sd_flutter_test_host_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final script = File('${dir.path}/load_failure.dart')
        ..writeAsStringSync('''
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_runtime_io.dart';

void main() {
  print(stableDiffusionLoadFailure(
    platform: 'ios-arm64',
    error: ArgumentError("Failed to lookup symbol 'sd_version'"),
  ).message);
}
''');
      final packages = File('.dart_tool/package_config.json').absolute.path;

      String messageWith(String flutterTest) {
        final result = Process.runSync(
          Platform.resolvedExecutable,
          ['--packages=$packages', script.path],
          environment: {'FLUTTER_TEST': flutterTest},
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return '${result.stdout}';
      }

      expect(
        messageWith('true'),
        contains('not linked into the flutter test host on ios-arm64'),
      );
      expect(
        messageWith('false'),
        contains('not linked into the process on ios-arm64'),
      );
    });

    group('Windows error 126', () {
      final error126 = ArgumentError(
        "Couldn't resolve native function 'sd_version' in "
        "'package:llamadart/stable_diffusion' : Failed to load dynamic "
        "library 'stable-diffusion.dll': The specified module could not be "
        'found.\r\n (error code: 126).\n',
      );

      String messageWithMissing(Set<String> missing) {
        final checked = <String>[];
        final message = stableDiffusionLoadFailure(
          platform: 'windows-x64',
          error: error126,
          missingWindowsLibraries: (names) {
            checked.addAll(names);
            return [
              for (final name in names)
                if (missing.contains(name)) name,
            ];
          },
        ).message;
        expect(checked, isNotEmpty);
        return message;
      }

      test('names a missing Visual C++ runtime before the Vulkan loader', () {
        final message = messageWithMissing({'msvcp140.dll', 'vulkan-1.dll'});

        expect(message, contains('could not be loaded on windows-x64'));
        expect(
          message,
          contains('latest Microsoft Visual C++ v14 Redistributable (x64)'),
        );
        expect(message, contains('msvcp140.dll could not be loaded'));
        expect(message, isNot(contains('vulkan-1.dll')));
        expect(message, isNot(contains('..')));
      });

      test('names the Vulkan loader when the runtime is present', () {
        final message = messageWithMissing({'vulkan-1.dll'});

        expect(message, contains('vulkan-1.dll could not be loaded'));
        expect(
          message,
          contains('llamadart_stable_diffusion_backends to [cpu]'),
        );
        expect(message, isNot(contains('Visual C++')));
        expect(message, isNot(contains('..')));
      });

      test(
        'the default check probes every Visual C++ DLL the runtime imports',
        () {
          // Off Windows none of these load, so the real check must report all
          // of them: this pins the list against stable-diffusion.dll's PE
          // imports (MSVCP140, MSVCP140_CODECVT_IDS, VCRUNTIME140,
          // VCRUNTIME140_1).
          final message = stableDiffusionLoadFailure(
            platform: 'windows-x64',
            error: error126,
          ).message;

          expect(
            message,
            contains(
              'msvcp140.dll, msvcp140_codecvt_ids.dll, vcruntime140.dll, '
              'vcruntime140_1.dll could not be loaded',
            ),
          );
          expect(message, contains('could not be found. It requires'));
        },
        skip: Platform.isWindows
            ? 'the Visual C++ runtime loads on Windows hosts'
            : false,
      );

      test('recognizes error 126 without an English system message', () {
        final message = stableDiffusionLoadFailure(
          platform: 'windows-x64',
          error: ArgumentError(
            "Couldn't resolve native function 'sd_version' in "
            "'package:llamadart/stable_diffusion' : Failed to load dynamic "
            "library 'stable-diffusion.dll': error code 126",
          ),
          missingWindowsLibraries: (names) =>
              names.contains('msvcp140.dll') ? ['msvcp140.dll'] : const [],
        ).message;

        expect(message, contains("'stable-diffusion.dll': error code 126."));
        expect(message, contains('msvcp140.dll could not be loaded'));
      });

      test('does not treat error 1260 as error 126', () {
        final checked = <String>[];
        final message = stableDiffusionLoadFailure(
          platform: 'windows-x64',
          error: ArgumentError(
            "Failed to load dynamic library 'stable-diffusion.dll': This "
            'program is blocked by group policy.\r\n (error code: 1260).\n',
          ),
          missingWindowsLibraries: (names) {
            checked.addAll(names);
            return names;
          },
        ).message;

        expect(checked, isEmpty);
        expect(message, isNot(contains('Visual C++')));
      });

      test('says neither dependency is missing when both load', () {
        final message = messageWithMissing(const {});

        expect(message, contains('does not name the missing dependency'));
        expect(message, isNot(contains('install')));
      });
    });

    test('keeps the first line of any other loader failure', () {
      final message = messageFor('dlopen failed: bad ELF magic\nsecond line');

      expect(
        message,
        'stable_diffusion runtime could not be loaded on linux-x64: '
        'dlopen failed: bad ELF magic',
      );
    });
  });
}

final class _FakeApi implements StableDiffusionNativeApi {
  _FakeApi({
    this.devices = 'CPU\tHost CPU\n',
    this.error,
    this.wrapperCalls = true,
    this.fp8Metal = false,
    this.intrinsicTinyV1 = false,
  });

  final String devices;
  final ArgumentError? error;
  final bool wrapperCalls;
  final bool fp8Metal;
  final bool intrinsicTinyV1;
  int calls = 0;
  final List<String> order = [];

  T _call<T>(T value) {
    calls++;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return value;
  }

  @override
  String version() => _call('v-test');

  @override
  String commit() => _call('c0ffee');

  @override
  void recordLog(LlamaLogLevel level) {
    order.add('recordLog ${level.name}');
    _call(null);
  }

  @override
  String listDevices() {
    order.add('listDevices');
    return _call(devices);
  }

  @override
  bool exportsWrapperCalls() => _call(wrapperCalls);

  @override
  bool loadsFp8AsF16OnMetal() => _call(fp8Metal);

  @override
  bool supportsIntrinsicTinyDecoderV1() => _call(intrinsicTinyV1);
}
