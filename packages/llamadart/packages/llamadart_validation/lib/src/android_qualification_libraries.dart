import 'package:code_assets/code_assets.dart';
// This private maintainer harness must replay the exact production hook policy.
// ignore: implementation_imports
import 'package:llamadart/src/hook/native_bundle_config.dart';

/// Uses the production hook's normal Android CPU/Vulkan packaged selection.
/// The complete owner archive remains a separate provenance inventory.
Map<String, Object?> androidQualificationLibrarySelection(
  Iterable<String> archiveNames, {
  String? cpuProfile,
}) {
  if (cpuProfile != null && !const ['full', 'compact'].contains(cpuProfile)) {
    throw const FormatException('Unknown consumer CPU profile');
  }
  final rawUserConfig = cpuProfile == null
      ? null
      : {
          'platforms': {
            'android-arm64': {'cpu_profile': cpuProfile},
          },
        };
  final names = archiveNames.toList()..sort();
  if (names.toSet().length != names.length ||
      names.any(
        (name) => !RegExp(r'^lib[A-Za-z0-9_.-]+\.so$').hasMatch(name),
      )) {
    throw const FormatException('Invalid owner archive library names');
  }
  final spec = resolveNativeBundleSpec(
    os: OS.android,
    arch: Architecture.arm64,
    isIosSimulator: false,
  )!;
  final selected = selectLibrariesForBundling(
    spec: spec,
    libraries: describeNativeLibraries(names),
    rawUserConfig: rawUserConfig,
    warn: (message) => throw StateError('Unadmitted hook selection: $message'),
  );
  if (!selected.any((entry) => entry.backend == 'cpu') ||
      !selected.any((entry) => entry.backend == 'vulkan')) {
    throw const FormatException(
      'Required CPU/Vulkan hook selection unavailable',
    );
  }
  final packaged = selected.map((entry) => entry.fileName).toList()..sort();
  return {
    'target': spec.bundle,
    'raw_user_config': rawUserConfig,
    'backends': spec.defaultBackends,
    'packaged': packaged,
    'omitted': names.where((name) => !packaged.contains(name)).toList(),
  };
}
