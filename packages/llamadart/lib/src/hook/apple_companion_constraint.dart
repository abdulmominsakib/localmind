/// The Apple companion dependency `hook/build.dart` tells an app to declare.
library;

/// The first core `MAJOR.MINOR` whose Apple companions share it.
///
/// Companions paired with an earlier core are numbered `0.0.x`.
const appleCompanionLockstepStart = (major: 0, minor: 13);

final RegExp _versionPattern = RegExp(
  r'^(\d+)\.(\d+)\.(\d+)(-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
);

typedef _Version = ({int major, int minor, int patch, bool prerelease});

_Version? _parse(String? version) {
  final match = version == null ? null : _versionPattern.firstMatch(version);
  if (match == null) return null;
  return (
    major: int.parse(match[1]!),
    minor: int.parse(match[2]!),
    patch: int.parse(match[3]!),
    prerelease: match[4] != null,
  );
}

bool _isLockstep(_Version core) {
  const start = appleCompanionLockstepStart;
  if (core.major != start.major) return core.major > start.major;
  if (core.minor != start.minor) return core.minor > start.minor;
  // A prerelease of the first lockstep version precedes it.
  return core.patch > 0 || !core.prerelease;
}

/// Whether core [coreVersion] is at or after `appleCompanionLockstepStart.0`
/// in semver precedence, so its Apple companions share its `MAJOR.MINOR`.
///
/// A prerelease of that first version, such as `0.13.0-dev.1`, is not; a
/// [coreVersion] that is not a version is not either.
bool isAppleCompanionLockstepCore(String coreVersion) {
  final core = _parse(coreVersion);
  return core != null && _isLockstep(core);
}

/// The pubspec constraint that resolves an Apple companion core
/// [coreVersion] accepts, or `null` when there is none to name.
///
/// [firstPinningRelease] is the first companion release pinning the core's
/// native tag. A lockstep core ([isAppleCompanionLockstepCore]) names it when
/// it shares the core's `MAJOR.MINOR`, because the pin moved within that
/// minor, and otherwise the minor's first release: a caret on a 0.x release,
/// or `'>=FROM <MAJOR.(MINOR+1).0'` once a caret would admit later minors. An
/// earlier core names `^`[firstPinningRelease]. Without a known
/// [firstPinningRelease] nothing names a release that pins the tag, and a
/// missing [coreVersion], or one that is not a version, names nothing.
String? appleCompanionConstraint(
  String? coreVersion, {
  String? firstPinningRelease,
}) {
  final core = _parse(coreVersion);
  if (core == null || firstPinningRelease == null) return null;
  if (!_isLockstep(core)) return '^$firstPinningRelease';
  final first = _parse(firstPinningRelease);
  final from =
      first != null && first.major == core.major && first.minor == core.minor
      ? firstPinningRelease
      : '${core.major}.${core.minor}.0';
  return core.major == 0
      ? '^$from'
      : "'>=$from <${core.major}.${core.minor + 1}.0'";
}

/// The sentence an incompatible Apple companion build error uses to tell the
/// app which [packageName] release to depend on, or `null` when
/// [appleCompanionConstraint] names none.
///
/// [nativePin] is the `repository@tag` the core requires.
String? appleCompanionRequirement({
  required String packageName,
  required String? coreVersion,
  required String nativePin,
  String? firstPinningRelease,
}) {
  final constraint = appleCompanionConstraint(
    coreVersion,
    firstPinningRelease: firstPinningRelease,
  );
  if (constraint == null) return null;
  final core = _parse(coreVersion)!;
  if (_isLockstep(core)) {
    return 'Depend on `$packageName: $constraint`, the core '
        '${core.major}.${core.minor}.x companion releases pinning $nativePin, '
        'in pubspec.yaml and rerun flutter pub get.';
  }
  return 'Depend on `$packageName: $constraint`, the first release pinning '
      '$nativePin, in pubspec.yaml and rerun flutter pub get; a caret '
      'constraint on an earlier 0.0.x release never resolves it.';
}
