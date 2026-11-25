/// The parts of a `leehack/llamadart-native` release's `assets.json` that
/// `hook/build.dart` acts on: the hook contract version and the backend
/// modules published as sidecar archives beside a core bundle.
library;

import 'dart:convert';

final _archiveKeyPattern = RegExp(r'^[a-z0-9][a-z0-9._-]*$');

/// Hook contract versions this hook can build from.
///
/// Contract 2 moves some backend modules out of the core bundle into sidecar
/// archives ([backendsOnlyInSidecarsFromContract2]), which the hook downloads
/// only when that backend is selected.
const Set<int> supportedNativeHookContractVersions = {1, 2};

/// Backends that contract 2 publishes only as a sidecar, keyed by the bundle
/// they extend. Selecting one where its sidecar is missing fails the build
/// instead of falling back to the default backends.
const Map<String, Set<String>> backendsOnlyInSidecarsFromContract2 = {
  'windows-x64': {'cuda'},
};

/// Thrown when a native release needs a hook contract this hook does not
/// implement, when its `assets.json` cannot be read or is malformed, or when a
/// selected backend's sidecar is unavailable.
final class NativeHookContractException implements Exception {
  /// Creates an exception with an actionable [message].
  const NativeHookContractException(this.message);

  /// What failed and what to do next.
  final String message;

  @override
  String toString() => 'NativeHookContractException: $message';
}

/// A backend module a release publishes as its own archive,
/// `llamadart-native-<archive>-<tag>.tar.gz`, which extends [bundle].
final class NativeBackendSidecar {
  /// Creates a sidecar description.
  const NativeBackendSidecar({
    required this.bundle,
    required this.backend,
    required this.archive,
  });

  /// The core bundle the sidecar is extracted over, such as `windows-x64`.
  final String bundle;

  /// The backend the sidecar adds, such as `cuda`.
  final String backend;

  /// The archive key between `llamadart-native-` and `-<tag>.tar.gz`, such as
  /// `windows-x64-cuda12`.
  final String archive;
}

/// What the hook needs from one release's `assets.json`.
final class NativeReleaseManifest {
  /// Creates a manifest description.
  const NativeReleaseManifest({
    required this.hookContractVersion,
    required this.sidecars,
  });

  /// The release's `hook_contract_version`; always one of
  /// [supportedNativeHookContractVersions].
  final int hookContractVersion;

  /// Every backend sidecar the release publishes.
  final List<NativeBackendSidecar> sidecars;

  /// The sidecar that adds [backend] to [bundle], or `null` when there is none.
  NativeBackendSidecar? sidecarFor({
    required String bundle,
    required String backend,
  }) {
    for (final sidecar in sidecars) {
      if (sidecar.bundle == bundle && sidecar.backend == backend) {
        return sidecar;
      }
    }
    return null;
  }

  /// Whether this release publishes [backend] for [bundle] only as a sidecar,
  /// so a build selecting it must not fall back without one.
  bool publishesOnlyAsSidecar({
    required String bundle,
    required String backend,
  }) =>
      hookContractVersion >= 2 &&
      (backendsOnlyInSidecarsFromContract2[bundle]?.contains(backend) ?? false);
}

/// Parses release [tag]'s `assets.json` [text], read from [source].
///
/// A manifest without `hook_contract_version` predates the field and is
/// contract 1, but it still lists `artifacts`. Throws
/// [NativeHookContractException] when the JSON is malformed, the contract is not in [supportedNativeHookContractVersions], or
/// a `backend-*` artifact is malformed, duplicated, or not named
/// `llamadart-native-<archive>-<tag>.tar.gz`.
NativeReleaseManifest parseNativeReleaseManifest(
  String text, {
  required String tag,
  required String source,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    throw NativeHookContractException(
      '$source is not valid JSON (${error.message}).',
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw NativeHookContractException('$source is not a JSON object.');
  }

  if (!decoded.containsKey('hook_contract_version') &&
      !decoded.containsKey('artifacts')) {
    throw NativeHookContractException(
      '$source has neither hook_contract_version nor artifacts, so it is not '
      'a release manifest.',
    );
  }

  final rawVersion = decoded['hook_contract_version'] ?? 1;
  if (rawVersion is! int) {
    throw NativeHookContractException(
      '$source has a non-integer hook_contract_version: $rawVersion.',
    );
  }
  if (!supportedNativeHookContractVersions.contains(rawVersion)) {
    final supported = supportedNativeHookContractVersions.join(' or ');
    throw NativeHookContractException(
      '$source requires native hook contract $rawVersion, but this llamadart '
      'build hook supports only contract $supported. Upgrade llamadart to a '
      'version that supports contract $rawVersion, or set '
      'llamadart_native_tag to a release with hook contract $supported.',
    );
  }

  final artifacts = decoded['artifacts'] ?? const <Object?>[];
  if (artifacts is! List<Object?>) {
    throw NativeHookContractException('$source artifacts is not a list.');
  }
  final prefix = 'llamadart-native-';
  final suffix = '-$tag.tar.gz';
  final sidecars = <NativeBackendSidecar>[];
  for (final artifact in artifacts) {
    if (artifact is! Map<String, Object?>) {
      continue;
    }
    final module = artifact['module'];
    if (module is! String || !module.startsWith('backend-')) {
      continue;
    }
    final platform = artifact['platform'];
    final arch = artifact['arch'];
    final backend = artifact['backend'];
    final file = artifact['file'];
    if (platform is! String ||
        arch is! String ||
        backend is! String ||
        file is! String ||
        platform.isEmpty ||
        arch.isEmpty ||
        backend.isEmpty ||
        !file.startsWith(prefix) ||
        !file.endsWith(suffix) ||
        file.length <= prefix.length + suffix.length) {
      throw NativeHookContractException(
        '$source lists a malformed $module artifact: $artifact.',
      );
    }
    final bundle = '$platform-$arch';
    final archive = file.substring(prefix.length, file.length - suffix.length);
    // The archive key names a cache directory and a download URL, and must not
    // collide with the core bundle's own.
    if (!_archiveKeyPattern.hasMatch(archive) ||
        !archive.startsWith('$bundle-')) {
      throw NativeHookContractException(
        '$source lists $module archive $file, which is not named '
        '$prefix$bundle-<variant>$suffix.',
      );
    }
    final sidecar = NativeBackendSidecar(
      bundle: bundle,
      backend: backend,
      archive: archive,
    );
    if (sidecars.any(
      (other) =>
          other.bundle == sidecar.bundle && other.backend == sidecar.backend,
    )) {
      throw NativeHookContractException(
        '$source lists more than one $backend sidecar for ${sidecar.bundle}.',
      );
    }
    sidecars.add(sidecar);
  }

  return NativeReleaseManifest(
    hookContractVersion: rawVersion,
    sidecars: List.unmodifiable(sidecars),
  );
}
