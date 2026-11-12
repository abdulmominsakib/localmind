import '../../core/exceptions.dart';

/// A ggml backend device reported by the stable_diffusion runtime.
final class StableDiffusionDevice {
  /// Device name, as accepted by stable-diffusion.cpp backend assignment.
  final String name;

  /// Human-readable device description.
  final String description;

  /// Creates a device entry.
  const StableDiffusionDevice({required this.name, required this.description});
}

/// Outcome of probing the opt-in stable_diffusion native runtime.
final class StableDiffusionRuntimeStatus {
  /// stable-diffusion.cpp version string, when available.
  final String? version;

  /// stable-diffusion.cpp commit, when available.
  final String? commit;

  /// Backend devices the runtime can use, when available.
  final List<StableDiffusionDevice> devices;

  /// Why the runtime cannot be used, or `null` when it can.
  final LlamaUnsupportedException? unavailableReason;

  /// Whether the runtime loads FP8 weights as F16 on Metal, as
  /// `StableDiffusionCalls.loadsFp8AsF16OnMetal` decides. Without it, FP8
  /// weights abort the process when a Metal context is created.
  final bool loadsFp8AsF16OnMetal;

  /// Whether a native context can enforce the intrinsic tiny-decoder v1
  /// policy through every automatic model refresh.
  final bool supportsIntrinsicTinyDecoderV1;

  /// A runtime that loaded and answered the probe.
  const StableDiffusionRuntimeStatus.available({
    required String this.version,
    required String this.commit,
    required this.devices,
    this.loadsFp8AsF16OnMetal = false,
    this.supportsIntrinsicTinyDecoderV1 = false,
  }) : unavailableReason = null;

  /// A runtime that cannot be used, for [reason].
  const StableDiffusionRuntimeStatus.unavailable(
    LlamaUnsupportedException reason,
  ) : unavailableReason = reason,
      version = null,
      commit = null,
      devices = const [],
      loadsFp8AsF16OnMetal = false,
      supportsIntrinsicTinyDecoderV1 = false;

  /// Whether the runtime loaded and answered the probe.
  bool get isAvailable => unavailableReason == null;

  /// Throws [unavailableReason] when the runtime cannot be used.
  void throwIfUnavailable() {
    final reason = unavailableReason;
    if (reason != null) {
      throw reason;
    }
  }
}

/// Parses `sd_list_devices` output: one `name<TAB>description` per line.
/// Blank lines are skipped; a line without a tab is a name with no
/// description.
List<StableDiffusionDevice> parseStableDiffusionDeviceList(String text) {
  final devices = <StableDiffusionDevice>[];
  for (final line in text.split('\n')) {
    final trimmed = line.trimRight();
    if (trimmed.trim().isEmpty) {
      continue;
    }
    final separator = trimmed.indexOf('\t');
    devices.add(
      separator < 0
          ? StableDiffusionDevice(name: trimmed.trim(), description: '')
          : StableDiffusionDevice(
              name: trimmed.substring(0, separator).trim(),
              description: trimmed.substring(separator + 1).trim(),
            ),
    );
  }
  return devices;
}

/// CPU features the Android arm64 runtime is compiled for
/// (`armv8.2-a+dotprod+fp16`): dot-product plus scalar and vector fp16.
const List<String> stableDiffusionRequiredArmFeatures = [
  'asimddp',
  'fphp',
  'asimdhp',
];

/// Whether every `Features` line of an Arm Linux `/proc/cpuinfo` lists all of
/// [stableDiffusionRequiredArmFeatures]. `false` when there is no `Features`
/// line, so an unreadable or foreign format never passes. Every core must
/// report them because the process may be scheduled on any of them.
bool cpuInfoReportsRequiredArmFeatures(String cpuInfo) =>
    _everyLineReports(cpuInfo, 'features', stableDiffusionRequiredArmFeatures);

/// CPU features the Linux and Windows x64 runtimes are compiled for: ggml's
/// portable x86 build enables AVX2, FMA, F16C and BMI2, so a CPU without them
/// crashes with an illegal instruction.
const List<String> stableDiffusionRequiredX86Features = [
  'avx2',
  'fma',
  'f16c',
  'bmi2',
];

/// Whether every `flags` line of an x86 Linux `/proc/cpuinfo` lists all of
/// [stableDiffusionRequiredX86Features]. `false` when there is no `flags`
/// line, so an unreadable or foreign format never passes.
bool cpuInfoReportsRequiredX86Features(String cpuInfo) =>
    _everyLineReports(cpuInfo, 'flags', stableDiffusionRequiredX86Features);

bool _everyLineReports(String cpuInfo, String key, List<String> required) {
  var sawKey = false;
  for (final line in cpuInfo.split('\n')) {
    final separator = line.indexOf(':');
    if (separator < 0 ||
        line.substring(0, separator).trim().toLowerCase() != key) {
      continue;
    }
    sawKey = true;
    final features = line.substring(separator + 1).trim().split(RegExp(r'\s+'));
    if (!required.every(features.contains)) {
      return false;
    }
  }
  return sawKey;
}
