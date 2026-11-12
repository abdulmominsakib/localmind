import 'manifest.dart';

/// Platform adapter for a hash-verified, same-process native dispatch probe.
abstract interface class NpuExecutionMonitor {
  /// Installed, read-only Android native library directory.
  String get dispatchDirectory;

  /// Non-secret vendor, device and library identities recorded with every run.
  Map<String, dynamic> get identity;

  /// Schema, sync started/completed/failed, async submitted/failed, in-flight.
  List<int> snapshot();
}

/// Checks deltas, never confusing async acceptance or prior work with completion.
Map<String, dynamic> npuGenerationEvidence(List<int> before, List<int> after) {
  final shape =
      before.length == 7 &&
      after.length == 7 &&
      before[0] == 1 &&
      after[0] == 1 &&
      before.every((v) => v >= 0) &&
      after.every((v) => v >= 0);
  final monotonic =
      shape &&
      List.generate(5, (i) => after[i + 1] >= before[i + 1]).every((v) => v);
  final delta = monotonic
      ? [for (var i = 1; i < 6; i++) after[i] - before[i]]
      : <int>[];
  final verified =
      monotonic &&
      before[6] == 0 &&
      after[6] == 0 &&
      delta[0] > 0 &&
      delta[1] == delta[0] &&
      delta[2] == 0 &&
      delta[3] == 0 &&
      delta[4] == 0;
  return {
    'schema_version': 1,
    'before': before,
    'after': after,
    'verified': verified,
    'synchronous_completed': monotonic ? delta[1] : null,
    'placement': verified
        ? 'npu_participation_cpu_partitions_unknown'
        : 'unverified',
    'reason': verified
        ? 'Completed synchronous vendor calls during this generation; CPU partition coverage unknown'
        : 'Missing, reset, failed, in-flight or async-only execution proof',
  };
}

/// Rejects an incompatible installed-app device before native library loading.
void validateNpuDevice(ValidationProfile profile, Map<String, dynamic> device) {
  final target = profile.data['npu_target'] as Map;
  final aliases = target['device_soc_models'] as List;
  if (device['abi'] != target['abi'] ||
      device['android_api'] is! int ||
      (device['android_api'] as int) < (target['minimum_android_api'] as int) ||
      !aliases.any(
        (soc) => '$soc'.toLowerCase() == '${device['soc_model']}'.toLowerCase(),
      )) {
    throw StateError(
      'NPU device identity does not match ${target['soc']} / ${target['abi']}',
    );
  }
}
