import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../core/exceptions.dart';
import '../../core/models/config/log_level.dart';
import '../../platform/io/ios_simulator.dart';
import '../windows_runtime_libraries.dart';
import 'stable_diffusion_bindings.dart' as sd;
import 'stable_diffusion_calls.dart';
import 'stable_diffusion_log.dart';
import 'stable_diffusion_runtime_status.dart';

/// The native calls the probe makes; tests substitute a fake.
abstract interface class StableDiffusionNativeApi {
  /// `sd_version()`.
  String version();

  /// `sd_commit()`.
  String commit();

  /// Starts the runtime's log recorder at [level], where the runtime has
  /// one: from then on its messages, ggml's among them, are recorded and not
  /// printed to stderr.
  void recordLog(LlamaLogLevel level);

  /// `sd_list_devices()` output.
  String listDevices();

  /// Whether the runtime exports every function of [StableDiffusionCalls].
  bool exportsWrapperCalls();

  /// [StableDiffusionCalls.loadsFp8AsF16OnMetal] of the runtime.
  bool loadsFp8AsF16OnMetal();

  /// Whether the runtime enforces the intrinsic tiny-decoder v1 contract.
  bool supportsIntrinsicTinyDecoderV1();
}

/// The host operating system, as `Platform.operatingSystem` reports it.
String stableDiffusionHostOperatingSystem() => Platform.operatingSystem;

/// Whether this is a macOS x86_64 process, Rosetta included.
bool stableDiffusionHostIsMacosX64() => Abi.current() == Abi.macosX64;

/// ABIs stable-diffusion-native publishes a runtime for. `Abi.iosArm64` covers
/// both the device and the arm64 simulator archive; `Abi.iosX64` is the x86_64
/// simulator.
const Set<Abi> stableDiffusionPublishedAbis = {
  Abi.androidArm64,
  Abi.iosArm64,
  Abi.iosX64,
  Abi.linuxArm64,
  Abi.linuxX64,
  Abi.macosArm64,
  Abi.macosX64,
  Abi.windowsX64,
};

/// Probes the stable_diffusion runtime the build hook bundled.
///
/// The library is resolved through its native-asset id
/// (`package:llamadart/stable_diffusion`) on the first native call, so
/// nothing is loaded before the platform checks pass: an unpublished ABI is
/// rejected up front, and the CPU must support what the runtime was compiled
/// for, or it would crash with an illegal instruction:
///
/// - Android arm64: `/proc/cpuinfo` must report
///   [stableDiffusionRequiredArmFeatures] (Armv8.2 dot-product and fp16).
/// - Linux x64: `/proc/cpuinfo` must report
///   [stableDiffusionRequiredX86Features].
/// - Windows x64: `IsProcessorFeaturePresent` must report AVX2. Windows has no
///   feature constant for FMA, F16C or BMI2; every x86 CPU with AVX2 also has
///   them.
///
/// macOS x64 and the x86_64 iOS simulator need no check: the runtime is
/// cross-compiled without AVX, and macOS 13.3 runs only on Intel CPUs that
/// have AVX2 anyway.
///
/// Then `sd_version`, `sd_commit` and `sd_list_devices` must answer, and the
/// runtime must export the `sd_dart_` functions of [StableDiffusionCalls],
/// which a release older than [StableDiffusionCalls.minimumNativeRelease]
/// does not.
///
/// `sd_list_devices` initializes the GPU backend, which logs through ggml.
/// The runtime's log recorder is registered before it, at [logLevel], so
/// those messages are recorded for the next image worker to forward instead
/// of going to stderr, and the registration, which is not synchronized,
/// never runs beside a device initialization.
///
/// [abi], [isIosSimulator], [readCpuInfo], [windowsHasAvx2],
/// [missingWindowsLibraries] and [api] default to the host and the bundled
/// library; tests replace them. [isIosSimulator] only labels messages:
/// `Abi.iosArm64` is both the device and the arm64 simulator. Messages name
/// the targets as the build hook names their bundles: `ios-arm64`,
/// `ios-arm64-sim` and `ios-x64-sim`.
StableDiffusionRuntimeStatus probeStableDiffusionRuntime({
  Abi? abi,
  bool Function() isIosSimulator = isIosSimulatorProcess,
  String? Function() readCpuInfo = _readProcCpuInfo,
  bool Function() windowsHasAvx2 = _windowsHasAvx2,
  List<String> Function(List<String> names) missingWindowsLibraries =
      findMissingWindowsLibraries,
  StableDiffusionNativeApi api = const BundledStableDiffusionApi(),
  LlamaLogLevel logLevel = LlamaLogLevel.none,
}) {
  final targetAbi = abi ?? Abi.current();
  final platform = switch (targetAbi) {
    Abi.iosArm64 when isIosSimulator() => 'ios-arm64-sim',
    Abi.iosX64 => 'ios-x64-sim',
    _ => _abiLabel(targetAbi),
  };
  if (!stableDiffusionPublishedAbis.contains(targetAbi)) {
    return StableDiffusionRuntimeStatus.unavailable(
      LlamaUnsupportedException(
        'stable_diffusion runtime is not published for $platform; it is '
        'available on android-arm64, ios-arm64, ios-arm64-sim, ios-x64-sim, '
        'macos-arm64, macos-x64, linux-arm64, linux-x64 and windows-x64.',
      ),
    );
  }

  if (targetAbi == Abi.androidArm64) {
    final cpuInfo = readCpuInfo();
    if (cpuInfo == null) {
      return StableDiffusionRuntimeStatus.unavailable(
        LlamaUnsupportedException(
          'stable_diffusion runtime on $platform requires Armv8.2 '
          'dot-product and fp16 ($_armFeatureList), and /proc/cpuinfo could '
          'not be read to confirm it.',
        ),
      );
    }
    if (!cpuInfoReportsRequiredArmFeatures(cpuInfo)) {
      return StableDiffusionRuntimeStatus.unavailable(
        LlamaUnsupportedException(
          'stable_diffusion runtime on $platform requires Armv8.2 '
          'dot-product and fp16 ($_armFeatureList), which this CPU does not '
          'report on every core in /proc/cpuinfo.',
        ),
      );
    }
  }

  if (targetAbi == Abi.linuxX64) {
    final cpuInfo = readCpuInfo();
    if (cpuInfo == null || !cpuInfoReportsRequiredX86Features(cpuInfo)) {
      final evidence = cpuInfo == null
          ? '/proc/cpuinfo could not be read to confirm it'
          : 'this CPU does not report them in /proc/cpuinfo';
      return StableDiffusionRuntimeStatus.unavailable(
        LlamaUnsupportedException(
          'stable_diffusion runtime on $platform requires an x86-64 CPU with '
          '$_x86FeatureList, and $evidence.',
        ),
      );
    }
  }

  if (targetAbi == Abi.windowsX64 && !windowsHasAvx2()) {
    return StableDiffusionRuntimeStatus.unavailable(
      LlamaUnsupportedException(
        'stable_diffusion runtime on $platform requires an x86-64 CPU with '
        '$_x86FeatureList; this CPU does not report AVX2.',
      ),
    );
  }

  try {
    final version = api.version();
    final commit = api.commit();
    api.recordLog(logLevel);
    final devices = parseStableDiffusionDeviceList(api.listDevices());
    if (!api.exportsWrapperCalls()) {
      return StableDiffusionRuntimeStatus.unavailable(
        stableDiffusionWrapperUnsupported(),
      );
    }
    return StableDiffusionRuntimeStatus.available(
      version: version,
      commit: commit,
      devices: devices,
      loadsFp8AsF16OnMetal: api.loadsFp8AsF16OnMetal(),
      supportsIntrinsicTinyDecoderV1: api.supportsIntrinsicTinyDecoderV1(),
    );
  } on ArgumentError catch (error) {
    return StableDiffusionRuntimeStatus.unavailable(
      stableDiffusionLoadFailure(
        platform: platform,
        error: error,
        missingWindowsLibraries: missingWindowsLibraries,
      ),
    );
  }
}

/// Maps a failed native-asset resolution to the requirement the app missed.
///
/// The VM reports a missing asset, a library that fails to load and a missing
/// symbol through the same [ArgumentError]; only its message tells them
/// apart. A missing asset is checked first because that message lists every
/// bundled asset, which on Linux and Windows includes llama.cpp's
/// `ggml-vulkan`. A Linux dynamic-loader failure names the loader library it
/// could not find. Windows reports only error 126 without naming the
/// dependency, so [missingWindowsLibraries] checks which of the runtime's
/// imports fail to load: the Visual C++ runtime, which stock Windows Server
/// lacks, and the Vulkan loader. On iOS and macOS the advice also names the
/// `llamadart_stable_diffusion_flutter` companion, which links the runtime
/// into the process through Swift Package Manager instead of the hook.
/// [isFlutterTestHost] (default: [isFlutterTestEnvironment]) marks a host
/// `flutter test` run, which never links that companion.
LlamaUnsupportedException stableDiffusionLoadFailure({
  required String platform,
  required ArgumentError error,
  List<String> Function(List<String> names) missingWindowsLibraries =
      findMissingWindowsLibraries,
  bool Function() isFlutterTestHost = isFlutterTestEnvironment,
}) {
  final detail = '${error.message ?? error}';
  final isApple = platform.startsWith('ios-') || platform.startsWith('macos-');
  if (detail.contains('No asset with id')) {
    const key = 'hooks.user_defines.llamadart.llamadart_native_runtimes';
    const hookAdvice =
        'set $key to all, or add stable_diffusion to its list, and rebuild. '
        'A list replaces the default llama_cpp and litert_lm.';
    if (isApple) {
      return LlamaUnsupportedException(
        'stable_diffusion runtime is not bundled for $platform. In a Flutter '
        'iOS/macOS app, add the $_appleCompanion package and rebuild: '
        'without it the build hook leaves out a stable_diffusion that all '
        'only implies. Naming stable_diffusion in $key bundles it through '
        'the hook instead, in a framework App Store Connect rejects on iOS. '
        'In any other build, $hookAdvice',
      );
    }
    return LlamaUnsupportedException(
      'stable_diffusion runtime is not bundled for $platform; $hookAdvice',
    );
  }
  if (_vulkanLoaderNames.any(detail.toLowerCase().contains)) {
    return LlamaUnsupportedException(
      'stable_diffusion runtime on $platform is the Vulkan variant, which '
      'requires the Vulkan loader (libvulkan.so.1 on Linux, vulkan-1.dll on '
      'Windows); install it, or set '
      'hooks.user_defines.llamadart.llamadart_stable_diffusion_backends to '
      '[cpu] for this platform and rebuild.',
    );
  }
  if (detail.contains('Failed to lookup symbol')) {
    if (isApple && isFlutterTestHost()) {
      return LlamaUnsupportedException(
        'stable_diffusion runtime symbols are not linked into the flutter test '
        'host on $platform: host `flutter test` runs do not link Swift Package '
        'Manager companions such as $_appleCompanion. Run image generation in '
        'an integration test on a device, simulator or the macOS app '
        '(`flutter test integration_test -d <device>`).',
      );
    }
    if (isApple) {
      return LlamaUnsupportedException(
        'stable_diffusion runtime symbols are not linked into the process on '
        '$platform. A Flutter iOS/macOS app that depends on $_appleCompanion '
        'links them through Swift Package Manager: enable it with '
        '`flutter config --enable-swift-package-manager`, or remove '
        '$_appleCompanion to bundle the runtime through the build hook. Host '
        '`flutter test` runs never link the companion. Otherwise the runtime '
        'does not match the pinned stable-diffusion-native release.',
      );
    }
    return LlamaUnsupportedException(
      'stable_diffusion runtime on $platform does not export the '
      'stable-diffusion.h API these bindings were generated from; bundle the '
      'pinned stable-diffusion-native release.',
    );
  }
  final firstLine = detail.split('\n').first.trimRight();
  if (isWindowsModuleNotFoundError(detail)) {
    final cause = firstLine.replaceFirst(RegExp(r'\.+$'), '');
    final missingRuntime = missingWindowsLibraries(
      _windowsVisualCppRuntimeLibraries,
    );
    if (missingRuntime.isNotEmpty) {
      final advice = visualCppRuntimeAdvice(
        architecture: 'x64',
        missing: missingRuntime,
        library: 'stable-diffusion.dll',
      );
      return LlamaUnsupportedException(
        'stable_diffusion runtime could not be loaded on $platform: $cause. '
        '$advice',
      );
    }
    if (missingWindowsLibraries(const ['vulkan-1.dll']).isNotEmpty) {
      return LlamaUnsupportedException(
        'stable_diffusion runtime could not be loaded on $platform: $cause. '
        'vulkan-1.dll could not be loaded; if the app bundles the Vulkan '
        'build, install a GPU driver that provides the Vulkan loader, or set '
        'hooks.user_defines.llamadart.llamadart_stable_diffusion_backends to '
        '[cpu] and rebuild.',
      );
    }
    return LlamaUnsupportedException(
      'stable_diffusion runtime could not be loaded on $platform: $cause. '
      'Windows does not name the missing dependency, and the Visual C++ '
      'runtime and Vulkan loader both load.',
    );
  }
  return LlamaUnsupportedException(
    'stable_diffusion runtime could not be loaded on $platform: $firstLine',
  );
}

final String _armFeatureList = stableDiffusionRequiredArmFeatures.join(', ');

final String _x86FeatureList = stableDiffusionRequiredX86Features
    .map((feature) => feature.toUpperCase())
    .join(', ');

/// `PF_AVX2_INSTRUCTIONS_AVAILABLE` for `IsProcessorFeaturePresent`.
const int _pfAvx2InstructionsAvailable = 40;

const List<String> _vulkanLoaderNames = ['libvulkan.so', 'vulkan-1.dll'];

const String _appleCompanion = 'llamadart_stable_diffusion_flutter';

/// The Visual C++ runtime DLLs `stable-diffusion.dll` imports.
const List<String> _windowsVisualCppRuntimeLibraries = [
  'msvcp140.dll',
  'msvcp140_codecvt_ids.dll',
  'vcruntime140.dll',
  'vcruntime140_1.dll',
];

/// Whether [environment] (default: this process's) is a host `flutter test`
/// run, which sets `FLUTTER_TEST` to `true`.
bool isFlutterTestEnvironment([Map<String, String>? environment]) =>
    (environment ?? Platform.environment)['FLUTTER_TEST'] == 'true';

String _abiLabel(Abi abi) => abi.toString().replaceAll('_', '-');

String? _readProcCpuInfo() {
  try {
    return File('/proc/cpuinfo').readAsStringSync();
  } on FileSystemException {
    return null;
  }
}

bool _windowsHasAvx2() {
  final isProcessorFeaturePresent = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<Int32 Function(Uint32), int Function(int)>(
        'IsProcessorFeaturePresent',
      );
  return isProcessorFeaturePresent(_pfAvx2InstructionsAvailable) != 0;
}

/// The runtime the build hook bundled.
///
/// [resolveCalls] replaces how the `sd_dart_` calls are resolved; tests use it
/// to stand in for an older or incomplete runtime.
final class BundledStableDiffusionApi implements StableDiffusionNativeApi {
  /// Creates the API of the bundled runtime.
  const BundledStableDiffusionApi({
    this.resolveCalls = StableDiffusionCalls.tryResolve,
  });

  /// Resolves the `sd_dart_` calls, or returns `null` when the runtime lacks
  /// them.
  final StableDiffusionCalls? Function() resolveCalls;

  @override
  String version() => _string(sd.sd_version());

  @override
  String commit() => _string(sd.sd_commit());

  @override
  void recordLog(LlamaLogLevel level) {
    final log = StableDiffusionCalls.tryResolve()?.log;
    if (log != null) {
      recordStableDiffusionLog(log, level);
    }
  }

  @override
  String listDevices() {
    final size = sd.sd_list_devices(nullptr, 0);
    if (size <= 0) {
      return '';
    }
    final buffer = calloc<Char>(size + 1);
    try {
      sd.sd_list_devices(buffer, size + 1);
      return buffer.cast<Utf8>().toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  bool exportsWrapperCalls() => resolveCalls() != null;

  @override
  bool loadsFp8AsF16OnMetal() => resolveCalls()?.loadsFp8AsF16OnMetal ?? false;

  @override
  bool supportsIntrinsicTinyDecoderV1() =>
      resolveCalls()?.newContextIntrinsicTinyV1 != null;

  static String _string(Pointer<Char> value) =>
      value == nullptr ? '' : value.cast<Utf8>().toDartString();
}
