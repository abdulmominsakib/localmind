#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:llamadart/src/hook/apple_companion_constraint.dart';
import 'package:llamadart/src/hook/native_bundle_config.dart';
import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import '../release/pub_content_limits.dart';
import 'check_released_changelog_sections.dart';

// Keep these maps in sync when adding companion packages or moving the current
// installation docs. Historical website/versioned_docs pages are intentionally
// excluded so archived release docs can keep their original package versions.
//
// During release-prep PRs, current install docs are expected to track the
// in-repository package versions being prepared. Publishing still happens only
// after merge; the release-prep PR merge is the approval boundary for the
// post-merge release automation.
const Map<String, String> _packagePubspecs = <String, String>{
  'llamadart': 'pubspec.yaml',
  'llamadart_llama_cpp_flutter':
      'packages/llamadart_llama_cpp_flutter/pubspec.yaml',
  'llamadart_litert_lm_flutter':
      'packages/llamadart_litert_lm_flutter/pubspec.yaml',
  'llamadart_stable_diffusion_flutter':
      'packages/llamadart_stable_diffusion_flutter/pubspec.yaml',
};

// Adds `genkit_llamadart` to the pub.dev size checks only. It keeps its own
// version and release routing (`website/docs/maintainers/genkit-package.md`),
// so it stays out of [_packagePubspecs] and every version check built on it.
const Map<String, String> _pubSizeCheckedPubspecs = <String, String>{
  ..._packagePubspecs,
  'genkit_llamadart': 'packages/genkit_llamadart/pubspec.yaml',
};

const Map<String, List<String>> _currentDocDependencies =
    <String, List<String>>{
      'README.md': <String>[
        'llamadart',
        'llamadart_llama_cpp_flutter',
        'llamadart_litert_lm_flutter',
        'llamadart_stable_diffusion_flutter',
      ],
      'website/docs/getting-started/installation.md': <String>[
        'llamadart',
        'llamadart_llama_cpp_flutter',
        'llamadart_litert_lm_flutter',
        'llamadart_stable_diffusion_flutter',
      ],
      'packages/llamadart_llama_cpp_flutter/README.md': <String>[
        'llamadart',
        'llamadart_llama_cpp_flutter',
      ],
      'packages/llamadart_litert_lm_flutter/README.md': <String>[
        'llamadart',
        'llamadart_litert_lm_flutter',
      ],
      'packages/llamadart_stable_diffusion_flutter/README.md': <String>[
        'llamadart',
        'llamadart_stable_diffusion_flutter',
      ],
    };

final Map<String, RegExp> _currentNativePins = <String, RegExp>{
  'lib/src/hook/native_release_pins.dart': RegExp(
    r"const llamaCppTag = '([^']+)';",
  ),
  'packages/llamadart_llama_cpp_flutter/darwin/'
      'llamadart_llama_cpp_flutter/Package.swift': RegExp(
    r'let llamaCppTag = "([^"]+)"',
  ),
  'packages/llamadart_llama_cpp_flutter/README.md': RegExp(
    r'The Apple SwiftPM manifest pins\s+`leehack/llamadart-native@([^`]+)`\.',
  ),
  'README.md': RegExp(
    r'\| Native llama\.cpp / GGUF \| `leehack/llamadart-native@([^`]+)` \|',
  ),
  'website/docs/getting-started/installation.md': RegExp(
    r'llamadart_native_tag:\s*([^\s#]+)',
  ),
  'website/docs/platforms/support-matrix.md': RegExp(
    r'The native-assets hook currently pins `llamadart-native` tag\s+`([^`]+)`',
  ),
};

/// Current docs whose prose calls a specific native tag the default runtime.
///
/// Release notes and `website/versioned_docs` pages are excluded because they
/// describe the pin that was current when they were written. The WebGPU pages
/// are excluded too: bridge assets deliberately trail the native pin, and
/// `tool/testing/check_webgpu_bridge_tag.dart` owns that divergence.
/// `README.md` and `website/docs/getting-started/installation.md` are excluded
/// as well, but their coverage differs by site. [_currentNativePins] checks
/// `README.md`'s pin table row and `installation.md`'s `llamadart_native_tag:`
/// override, so scanning those here would duplicate that contract.
/// `installation.md`'s prose `leehack/llamadart-native@<tag>` claim is not in
/// [_currentNativePins]; `tool/native/sync_native_release_pins.py` rewrites
/// every `leehack/llamadart-native@<tag>` occurrence in these docs and owns
/// keeping it current.
const List<String> defaultRuntimeClaimDocs = <String>[
  'website/docs/platforms/support-matrix.md',
  'website/docs/guides/performance-tuning.md',
];

final RegExp _defaultRuntimeClaim = RegExp(
  r'(?:default|package-pinned)\s+`([^`]+)`\s+runtime',
);

/// Matches the `owner/repo@` prefix docs may put in front of a native tag.
final RegExp _qualifiedTagPrefix = RegExp(r'^[\w.-]+/[\w.-]+@');

/// Returns one message per sentence in [contents] calling a tag other than
/// [expectedPin] the default native runtime.
///
/// [_currentNativePins] only covers sites that declare the pin; prose asserting
/// which runtime ships drifts silently when the pin moves, leaving the docs
/// recommending a runtime nobody ships. Pin-agnostic wording names no tag and
/// is always accepted. A claim may name the tag bare or as
/// `owner/repo@<tag>`; both compare by tag.
List<String> findStaleDefaultRuntimeClaims(
  String path,
  String contents,
  String expectedPin,
) {
  final problems = <String>[];
  for (final match in _defaultRuntimeClaim.allMatches(contents)) {
    final claimed = match.group(1)!.replaceFirst(_qualifiedTagPrefix, '');
    if (claimed == expectedPin) {
      continue;
    }
    final line = contents.substring(0, match.start).split('\n').length;
    problems.add(
      '$path:$line calls $claimed the default native runtime, but '
      'lib/src/hook/native_release_pins.dart pins $expectedPin.',
    );
  }
  return problems;
}

/// A companion package whose Apple SwiftPM pin must already be recorded in the
/// CHANGELOG section its `pubspec.yaml` version will publish.
///
/// `lib/src/hook/native_release_pins.dart` and `Package.swift` agreeing is not
/// enough: a companion
/// publishes the tag its own released section documents, and
/// `release_on_prep_merge.yml` silently skips a companion whose version is
/// already on pub.dev. Without this check a moved pin can sit in `Unreleased`
/// forever while the release ships the previous tag.
class CompanionSwiftPin {
  /// Package name, as in `pubspec.yaml`.
  final String package;

  /// Repository-relative package directory.
  final String root;

  /// Matches the tag in the package's `Package.swift`; group 1 is the tag.
  final RegExp swiftTag;

  /// Native repository the CHANGELOG names, as `owner/repo`.
  final String nativeRepo;

  /// Creates a companion pin site.
  const CompanionSwiftPin({
    required this.package,
    required this.root,
    required this.swiftTag,
    required this.nativeRepo,
  });

  /// Path of the package's SwiftPM manifest.
  String get swiftPackagePath => '$root/darwin/$package/Package.swift';

  /// Path of the package's CHANGELOG.
  String get changelogPath => '$root/CHANGELOG.md';

  /// Path of the package's pubspec.
  String get pubspecPath => '$root/pubspec.yaml';

  /// Matches the tag a CHANGELOG entry records; group 1 is the tag.
  RegExp get changelogTag => RegExp('`${RegExp.escape(nativeRepo)}@([^`]+)`');
}

/// Every companion package that pins a native runtime through SwiftPM.
final List<CompanionSwiftPin> companionSwiftPins = <CompanionSwiftPin>[
  CompanionSwiftPin(
    package: 'llamadart_llama_cpp_flutter',
    root: 'packages/llamadart_llama_cpp_flutter',
    swiftTag: RegExp(r'let llamaCppTag = "([^"]+)"'),
    nativeRepo: 'leehack/llamadart-native',
  ),
  CompanionSwiftPin(
    package: 'llamadart_litert_lm_flutter',
    root: 'packages/llamadart_litert_lm_flutter',
    swiftTag: RegExp(r'let liteRtLmTag = "([^"]+)"'),
    nativeRepo: 'leehack/litert-lm-native',
  ),
  CompanionSwiftPin(
    package: 'llamadart_stable_diffusion_flutter',
    root: 'packages/llamadart_stable_diffusion_flutter',
    swiftTag: RegExp(r'let stableDiffusionTag = "([^"]+)"'),
    nativeRepo: 'leehack/stable-diffusion-native',
  ),
];

/// A companion whose SwiftPM pin is recorded only under `## Unreleased`.
///
/// Native-sync PRs deliberately leave this state behind; a release-prep PR must
/// resolve it. See `website/docs/maintainers/release-workflow.md`.
class PendingCompanionBump {
  /// Package name.
  final String package;

  /// Version currently in `pubspec.yaml`.
  final String version;

  /// Tag `Package.swift` pins.
  final String swiftPin;

  /// Tag the `## $version` section records.
  final String releasedPin;

  /// Creates a pending bump record.
  const PendingCompanionBump({
    required this.package,
    required this.version,
    required this.swiftPin,
    required this.releasedPin,
  });

  @override
  String toString() =>
      '$package $version publishes $releasedPin, but Package.swift pins '
      '$swiftPin; bump the version and rename `## Unreleased` to the new '
      'version before releasing.';
}

/// Checks that every companion's SwiftPM pin is documented in the CHANGELOG
/// section its `pubspec.yaml` version will publish.
///
/// Appends hard failures to [errors] and returns the companions whose pin is
/// still sitting in `## Unreleased`. Callers decide whether a pending bump is
/// tolerable: it is during native sync, and never during release prep.
List<PendingCompanionBump> checkCompanionSwiftPins(
  Directory repoRoot,
  List<String> errors,
) {
  final pending = <PendingCompanionBump>[];
  for (final companion in companionSwiftPins) {
    final swiftPin = _matchInFile(
      repoRoot,
      companion.swiftPackagePath,
      companion.swiftTag,
      'SwiftPM native tag',
      errors,
    );
    final version = _matchInFile(
      repoRoot,
      companion.pubspecPath,
      RegExp(r'^version:\s*(\S+)\s*$', multiLine: true),
      'version field',
      errors,
    );
    if (swiftPin == null || version == null) {
      continue;
    }

    final sections = _changelogSections(
      repoRoot,
      companion.changelogPath,
      errors,
    );
    if (sections == null) {
      continue;
    }

    final released = sections[version];
    if (released == null) {
      errors.add(
        '${companion.changelogPath} has no `## $version` section for the '
        'version in ${companion.pubspecPath}.',
      );
      continue;
    }

    final releasedPin = companion.changelogTag.firstMatch(released)?.group(1);
    if (releasedPin == null) {
      errors.add(
        '${companion.changelogPath} section `## $version` does not record a '
        '`${companion.nativeRepo}@<tag>` pin.',
      );
      continue;
    }
    if (releasedPin == swiftPin) {
      continue;
    }

    final unreleasedPin = companion.changelogTag
        .firstMatch(sections['Unreleased'] ?? '')
        ?.group(1);
    if (unreleasedPin != swiftPin) {
      errors.add(
        '${companion.swiftPackagePath} pins $swiftPin, but '
        '${companion.changelogPath} section `## $version` records '
        '$releasedPin and no `## Unreleased` entry records $swiftPin.',
      );
      continue;
    }

    pending.add(
      PendingCompanionBump(
        package: companion.package,
        version: version,
        swiftPin: swiftPin,
        releasedPin: releasedPin,
      ),
    );
  }
  return pending;
}

/// The `llamadart` constraint a companion declares for a new core minor:
/// every release of [coreVersion]'s minor and nothing newer.
///
/// Pub then refuses to pair a companion with a core minor it was not built
/// for. Patch repins additionally require qualified older-companion support
/// and a narrowed new-companion floor, checked in both directions by
/// [checkPublishedCompanionPins] and [checkCompanionPublishedCorePins].
String companionCoreConstraintFor(Version coreVersion) =>
    '>=${coreVersion.major}.${coreVersion.minor}.0 '
    '<${coreVersion.major}.${coreVersion.minor + 1}.0';

final RegExp _companionCoreConstraint = RegExp(
  r'^>=([0-9]+\.[0-9]+\.[0-9]+) <([0-9]+\.[0-9]+\.[0-9]+)$',
);

/// Reads the hosted `llamadart` constraint from a companion pubspec's
/// [source], or returns why it has none.
({String? constraint, String? problem}) companionCoreConstraint(String source) {
  final Object? pubspec;
  try {
    pubspec = loadYaml(source);
  } on YamlException catch (error) {
    return (constraint: null, problem: 'is not valid YAML: ${error.message}');
  }
  final dependencies = pubspec is YamlMap ? pubspec['dependencies'] : null;
  final core = dependencies is YamlMap ? dependencies['llamadart'] : null;
  if (core == null) {
    return (constraint: null, problem: 'declares no `llamadart` dependency');
  }
  if (core is! String) {
    return (
      constraint: null,
      problem:
          'declares `llamadart` as a $core source instead of a hosted '
          'version constraint',
    );
  }
  return (constraint: core, problem: null);
}

/// Checks that every companion constrains `llamadart` to [coreVersion]'s
/// minor, written `>=M.m.P <M.(m+1).0` with `P` no later than [coreVersion].
///
/// `P` above `0` keeps an earlier companion honest about the first core patch
/// that accepts its native pin; a new minor starts at
/// [companionCoreConstraintFor].
List<String> checkCompanionCoreConstraints(
  Directory repoRoot,
  Version coreVersion,
) {
  final errors = <String>[];
  final expected = companionCoreConstraintFor(coreVersion);
  for (final companion in companionSwiftPins) {
    final source = _readFromRoot(repoRoot, companion.pubspecPath, errors);
    if (source == null) continue;
    final read = companionCoreConstraint(source);
    final constraint = read.constraint;
    if (constraint == null) {
      errors.add(
        '${companion.pubspecPath} ${read.problem}; declare '
        "`llamadart: '$expected'` so pub only pairs it with core "
        '${coreVersion.major}.${coreVersion.minor}.x.',
      );
      continue;
    }
    final match = _companionCoreConstraint.firstMatch(constraint);
    final min = match == null ? null : Version.parse(match.group(1)!);
    final max = match == null ? null : Version.parse(match.group(2)!);
    if (min == null ||
        max == null ||
        min.major != coreVersion.major ||
        min.minor != coreVersion.minor ||
        min > coreVersion ||
        max != Version(coreVersion.major, coreVersion.minor + 1, 0)) {
      errors.add(
        coreVersion.isPreRelease
            ? "${companion.pubspecPath} declares `llamadart: '$constraint'`, "
                  'but core is the prerelease $coreVersion. Release '
                  'automation publishes only stable core versions; set a '
                  'stable core version, then constrain each companion to its '
                  'minor.'
            : "${companion.pubspecPath} declares `llamadart: '$constraint'`, "
                  'but core is $coreVersion; a companion must allow exactly '
                  "this core minor, `'$expected'` for a new minor. Bump the "
                  'companion version with it, because pub.dev never changes a '
                  'published constraint.',
      );
    }
  }
  return errors;
}

/// Checks that every companion's `version` shares [coreVersion]'s
/// `MAJOR.MINOR` once [isAppleCompanionLockstepCore] holds for it.
///
/// Earlier companions are numbered `0.0.x` and stay valid beside an earlier
/// core. The hook decides with the same predicate, so the companion
/// constraint a build error names always admits the companion this check
/// aligns. Companion patch numbers move independently of the core's.
List<String> checkCompanionVersionAlignment(
  Directory repoRoot,
  Version coreVersion,
) {
  if (!isAppleCompanionLockstepCore('$coreVersion')) return const <String>[];
  final errors = <String>[];
  final series = '${coreVersion.major}.${coreVersion.minor}';
  for (final companion in companionSwiftPins) {
    final version = _matchInFile(
      repoRoot,
      companion.pubspecPath,
      RegExp(r'^version:\s*(\S+)\s*$', multiLine: true),
      'version field',
      errors,
    );
    if (version == null) continue;
    final Version parsed;
    try {
      parsed = Version.parse(version);
    } on FormatException catch (error) {
      errors.add(
        '${companion.pubspecPath} version $version is not semver: '
        '${error.message}',
      );
      continue;
    }
    if (parsed.major == coreVersion.major &&
        parsed.minor == coreVersion.minor) {
      continue;
    }
    errors.add(
      '${companion.pubspecPath} is version $version, but core is '
      '$coreVersion; companions share the core MAJOR.MINOR. Set it to '
      '$series.0 for a new core minor, or to the next $series patch for a '
      'companion change within it.',
    );
  }
  return errors;
}

/// Native tags the checkout's core accepts from each Apple companion,
/// keyed by package name.
Map<String, Set<String>> coreAcceptedCompanionPins() => <String, Set<String>>{
  'llamadart_llama_cpp_flutter': <String>{
    llamaCppTag,
    ...llamaCppCompatibleAppleCompanionTags.keys,
  },
  'llamadart_litert_lm_flutter': <String>{
    liteRtLmReleaseTag,
    ...earlierLiteRtLmRebuilds(liteRtLmReleaseTag),
  },
  'llamadart_stable_diffusion_flutter': <String>{
    stableDiffusionReleaseTag,
    ...stableDiffusionCompatibleAppleCompanionTags.keys,
  },
};

/// Earlier wrapper rebuilds of [tag]'s upstream LiteRT-LM release, which
/// `hook/build.dart` still links from a LiteRT-LM companion with an upgrade
/// warning (`_isEarlierLiteRtLmRebuild`); a bare `vMAJOR.MINOR.PATCH` counts
/// as rebuild 0.
Set<String> earlierLiteRtLmRebuilds(String tag) {
  final match = RegExp(r'^(v\d+\.\d+\.\d+)(?:-([1-9]\d*))?$').firstMatch(tag);
  if (match == null) return const <String>{};
  final base = match.group(1)!;
  final rebuild = int.parse(match.group(2) ?? '0');
  return <String>{
    for (var earlier = 0; earlier < rebuild; earlier++)
      earlier == 0 ? base : '$base-$earlier',
  };
}

/// Checks that each current companion excludes every published core whose
/// hook rejects its native pin. This is the reverse of
/// [checkPublishedCompanionPins]: a new companion must not resolve beside an
/// older core merely because both share the same minor.
List<String> checkCompanionPublishedCorePins(Directory repoRoot) {
  final errors = <String>[];
  final tags = _git(repoRoot, ['tag', '--list', 'v*'], errors);
  if (tags == null) return errors;
  if (tags.trim().isEmpty) {
    return [
      'No core release tags are checked out; fetch the full tag history '
          'before checking companion dependency floors.',
    ];
  }
  const contracts = <String, (String, String?)>{
    'llamadart_llama_cpp_flutter': (
      'llamaCppTag',
      'llamaCppCompatibleAppleCompanionTags',
    ),
    'llamadart_litert_lm_flutter': ('liteRtLmReleaseTag', null),
    'llamadart_stable_diffusion_flutter': (
      'stableDiffusionReleaseTag',
      'stableDiffusionCompatibleAppleCompanionTags',
    ),
  };
  final publishedPins = <String, String>{};
  final verifiedTags = <String>{};
  final shallow = _git(repoRoot, [
    'rev-parse',
    '--is-shallow-repository',
  ], errors);
  if (shallow?.trim() != 'false') {
    errors.add(
      'Fetch full core tag history before checking companion dependency floors.',
    );
    return errors;
  }
  for (final companion in companionSwiftPins) {
    final pubspec = _readFromRoot(repoRoot, companion.pubspecPath, errors);
    final manifest = _readFromRoot(
      repoRoot,
      companion.swiftPackagePath,
      errors,
    );
    if (pubspec == null || manifest == null) continue;
    final constraint = companionCoreConstraint(pubspec).constraint;
    final pin = companion.swiftTag.firstMatch(manifest)?.group(1);
    if (constraint == null || pin == null) {
      errors.add(
        '${companion.package} has no verifiable core constraint/native pin.',
      );
      continue;
    }
    if (!(coreAcceptedCompanionPins()[companion.package]?.contains(pin) ??
        false)) {
      errors.add(
        '${companion.package} current native pin is not accepted by the prepared core.',
      );
    }
    final VersionConstraint allowed;
    try {
      allowed = VersionConstraint.parse(constraint);
    } on FormatException {
      errors.add(
        '${companion.package} has an invalid core constraint: $constraint.',
      );
      continue;
    }
    for (final tag in const LineSplitter().convert(tags)) {
      final match = RegExp(r'^v(\d+\.\d+\.\d+)$').firstMatch(tag);
      if (match == null || !allowed.allows(Version.parse(match.group(1)!))) {
        continue;
      }
      if (!verifiedTags.contains(tag)) {
        final pubspec = _git(repoRoot, ['show', '$tag:pubspec.yaml'], errors);
        final identity = pubspec == null
            ? null
            : RegExp(
                r'^version:\s*(\S+)\s*$',
                multiLine: true,
              ).allMatches(pubspec).toList();
        if (identity == null ||
            identity.length != 1 ||
            identity.single.group(1) != match.group(1)) {
          errors.add('Published core $tag does not match its pubspec version.');
          continue;
        }
        verifiedTags.add(tag);
      }
      final source =
          publishedPins[tag] ??
          _git(repoRoot, [
            'show',
            '$tag:lib/src/hook/native_release_pins.dart',
          ], errors);
      if (source == null) continue;
      publishedPins[tag] = source;
      final (variable, compatibility) = contracts[companion.package]!;
      final accepted = _historicalCompanionPins(
        source,
        variable,
        compatibility,
        tag,
        errors,
      );
      if (accepted == null) continue;
      if (!accepted.contains(pin)) {
        errors.add(
          '${companion.package} pins ${companion.nativeRepo}@$pin, '
          "but its constraint '$constraint' admits published core $tag "
          'whose hook rejects that pin. Raise the companion core lower '
          'bound past that release and bump its package version.',
        );
      }
    }
  }
  return errors;
}

Set<String>? _historicalCompanionPins(
  String source,
  String variable,
  String? compatibility,
  String tag,
  List<String> errors,
) {
  // Parse historical code as data. Comments and string contents can contain
  // plausible declarations or keys, but must never grant compatibility.
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  if (parsed.errors.isNotEmpty) {
    errors.add(
      'Cannot read ${compatibility ?? variable} in published core $tag.',
    );
    return null;
  }
  final declarations = parsed.unit.declarations
      .whereType<TopLevelVariableDeclaration>()
      .expand((declaration) => declaration.variables.variables)
      .toList();
  final pins = declarations
      .where((node) => node.name.lexeme == variable)
      .toList();
  final pin = pins.length == 1 ? pins.single.initializer : null;
  if (pins.length != 1 ||
      !pins.single.isConst ||
      pin is! StringLiteral ||
      pin.stringValue == null) {
    errors.add('Cannot uniquely read $variable in published core $tag.');
    return null;
  }
  final accepted = <String>{pin.stringValue!};
  if (compatibility == null) return accepted;
  final maps = declarations
      .where((node) => node.name.lexeme == compatibility)
      .toList();
  if (maps.isEmpty) return accepted;
  final map = maps.length == 1 ? maps.single.initializer : null;
  if (maps.length != 1 || !maps.single.isConst || map is! SetOrMapLiteral) {
    errors.add('Cannot read $compatibility in published core $tag.');
    return null;
  }
  final keys = <String>{};
  for (final element in map.elements) {
    if (element is MapLiteralEntry) {
      final key = element.key;
      final value = element.value;
      if (key is StringLiteral &&
          key.stringValue != null &&
          value is StringLiteral &&
          value.stringValue != null &&
          keys.add(key.stringValue!)) {
        continue;
      }
    }
    errors.add('Cannot read $compatibility in published core $tag.');
    return null;
  }
  return accepted..addAll(keys);
}

/// Checks that every companion version release automation already published,
/// read from its `<package>-v<version>` tag in [repoRoot], either declares a
/// `llamadart` constraint that excludes [coreVersion] or pins a native tag in
/// [acceptedPins].
///
/// Published constraints are immutable, so a core patch that moved a
/// companion's pin would still resolve beside every earlier companion of the
/// same minor and fail its Apple build. Companions published without a
/// constraint predate it and stay the hook's job. Needs the full tag history,
/// and fails closed without it.
List<String> checkPublishedCompanionPins(
  Directory repoRoot,
  Version coreVersion, {
  Map<String, Set<String>>? acceptedPins,
}) {
  final accepted = acceptedPins ?? coreAcceptedCompanionPins();
  final errors = <String>[];
  final coreTags = _git(repoRoot, ['tag', '--list', 'v*'], errors);
  if (coreTags == null) return errors;
  if (coreTags.trim().isEmpty) {
    return [
      'No core `v*` release tags are checked out, so published companion '
          'pins cannot be verified; fetch the full tag history '
          '(`git fetch --tags`).',
    ];
  }
  for (final companion in companionSwiftPins) {
    final tags = _git(repoRoot, [
      'tag',
      '--list',
      '${companion.package}-v*',
    ], errors);
    if (tags == null) continue;
    for (final tag in const LineSplitter().convert(tags)) {
      if (tag.isEmpty) continue;
      final pubspec = _git(repoRoot, [
        'show',
        '$tag:${companion.pubspecPath}',
      ], errors);
      if (pubspec == null) continue;
      final constraint = companionCoreConstraint(pubspec).constraint;
      if (constraint == null) continue;
      final VersionConstraint allowed;
      try {
        allowed = VersionConstraint.parse(constraint);
      } on FormatException catch (error) {
        errors.add(
          '$tag declares an unparsable `llamadart` constraint: '
          '${error.message}',
        );
        continue;
      }
      if (!allowed.allows(coreVersion)) continue;
      final manifest = _git(repoRoot, [
        'show',
        '$tag:${companion.swiftPackagePath}',
      ], errors);
      if (manifest == null) continue;
      final pin = companion.swiftTag.firstMatch(manifest)?.group(1);
      final corePins = accepted[companion.package] ?? const <String>{};
      if (pin != null && corePins.contains(pin)) continue;
      errors.add(
        "$tag published ${companion.package} with `llamadart: '$constraint'`, "
        'which pub resolves beside core $coreVersion, but it pins '
        '${companion.nativeRepo}@${pin ?? '<none>'} and this core accepts '
        '${corePins.join(', ')}. Move a companion native pin only in a new '
        'core minor release, or keep the core hook accepting the earlier pin.',
      );
    }
  }
  return errors;
}

String? _git(Directory repoRoot, List<String> arguments, List<String> errors) {
  final ProcessResult result;
  try {
    result = Process.runSync('git', [
      '-C',
      repoRoot.path,
      ...arguments,
    ], stdoutEncoding: utf8);
  } on ProcessException catch (error) {
    errors.add('Could not run git ${arguments.join(' ')}: ${error.message}');
    return null;
  }
  if (result.exitCode != 0) {
    errors.add(
      'git ${arguments.join(' ')} failed: ${'${result.stderr}'.trim()}',
    );
    return null;
  }
  return result.stdout as String;
}

/// Returns section bodies keyed by heading text, or null when unreadable.
Map<String, String>? _changelogSections(
  Directory repoRoot,
  String path,
  List<String> errors,
) {
  final file = File('${repoRoot.path}/$path');
  if (!file.existsSync()) {
    errors.add('$path does not exist.');
    return null;
  }
  final sections = <String, String>{};
  var hasDuplicateHeading = false;
  String? heading;
  final body = StringBuffer();
  void flush() {
    final current = heading;
    if (current != null) {
      if (sections.containsKey(current)) {
        errors.add('$path contains duplicate `## $current` sections.');
        hasDuplicateHeading = true;
      } else {
        sections[current] = body.toString();
      }
    }
    body.clear();
  }

  late final List<String> lines;
  try {
    lines = file.readAsLinesSync();
  } on FileSystemException catch (error) {
    errors.add('$path could not be read: $error');
    return null;
  } on FormatException catch (error) {
    errors.add('$path could not be decoded as UTF-8 text: $error');
    return null;
  }

  for (final line in lines) {
    final match = RegExp(r'^##\s+(.*\S)\s*$').firstMatch(line);
    if (match != null) {
      flush();
      heading = match.group(1)!;
      continue;
    }
    body.writeln(line);
  }
  flush();
  return hasDuplicateHeading ? null : sections;
}

/// Returns group 1 of [pattern] in [path], recording an error when absent.
String? _matchInFile(
  Directory repoRoot,
  String path,
  RegExp pattern,
  String what,
  List<String> errors,
) {
  final file = File('${repoRoot.path}/$path');
  if (!file.existsSync()) {
    errors.add('$path does not exist.');
    return null;
  }
  late final String contents;
  try {
    contents = file.readAsStringSync();
  } on FileSystemException catch (error) {
    errors.add('$path could not be read: $error');
    return null;
  } on FormatException catch (error) {
    errors.add('$path could not be decoded as UTF-8 text: $error');
    return null;
  }
  final match = pattern.firstMatch(contents);
  if (match == null) {
    errors.add('$path does not contain its $what.');
    return null;
  }
  return match.group(1)!;
}

final RegExp _dependencyLine = RegExp(
  r'^\s+(llamadart(?:_[a-z0-9_]+)?):\s+\^([0-9]+\.[0-9]+\.[0-9]+(?:[-+][^\s#]+)?)',
);
final RegExp _fenceLine = RegExp(r'^\s*```\s*([^\s`]*)?\s*$');
final RegExp _versionLine = RegExp(r'^version:\s*(\S+)\s*$');

/// Selects the documented install pair without confusing a prepared companion
/// with the companion shipped for the core version. Release preparation always
/// requires the exact checkout versions instead.
Map<String, String> installDocVersions(
  Directory repoRoot,
  Map<String, String> checkoutVersions,
  List<String> errors, {
  required bool releasePrep,
}) {
  final result = Map<String, String>.of(checkoutVersions);
  if (releasePrep) return result;
  final coreVersion = checkoutVersions['llamadart'];
  final coreSections = _changelogSections(repoRoot, 'CHANGELOG.md', errors);
  final coreNotes = coreSections?[coreVersion];
  if (coreNotes == null) {
    errors.add('CHANGELOG.md has no section for install core $coreVersion.');
    return result;
  }
  final recordedCompanion = RegExp(
    r'Apple companion `([0-9]+\.[0-9]+\.[0-9]+)`',
  ).firstMatch(coreNotes)?.group(1);
  // Most patch releases do not prepare a different companion. An explicit
  // release pairing may override the checkout only after native-pin agreement.
  if (recordedCompanion == null) return result;
  final companion = companionSwiftPins.first;
  final nativeTag = companion.changelogTag.firstMatch(coreNotes)?.group(1);
  final companionSections = _changelogSections(
    repoRoot,
    companion.changelogPath,
    errors,
  );
  final companionNotes = companionSections?[recordedCompanion];
  final companionTag = companionNotes == null
      ? null
      : companion.changelogTag.firstMatch(companionNotes)?.group(1);
  if (nativeTag == null || companionTag != nativeTag) {
    errors.add(
      'Install core $coreVersion and companion $recordedCompanion '
      'must record the same native runtime pin in their changelogs.',
    );
    return result;
  }
  result[companion.package] = recordedCompanion;
  return result;
}

/// Changelogs whose first release heading must name the version being
/// published.
const _releasePrepChangelogs = <String>[
  'CHANGELOG.md',
  'website/docs/changelog/recent-releases.md',
];

final RegExp _unreleasedHeading = RegExp(r'^##\s+Unreleased\s*$');

/// Problems with `## Unreleased` among [changelog]'s level-two [headings].
///
/// `main` keeps exactly one `## Unreleased`, above every released section,
/// and release prep removes it. Union merges of the changelogs never conflict,
/// so a rebase across a release can leave a stray copy without any warning.
List<String> unreleasedHeadingProblems(
  String changelog,
  List<String> headings, {
  required bool releasePrep,
}) {
  final positions = [
    for (final (index, heading) in headings.indexed)
      if (_unreleasedHeading.hasMatch(heading)) index,
  ];
  if (positions.isEmpty) return const [];
  if (!releasePrep) {
    return positions.length == 1 && positions.single == 0
        ? const []
        : [
            '$changelog must have at most one `## Unreleased`, above every '
                'released section.',
          ];
  }
  return ['$changelog must not keep `## Unreleased` when publishing.'];
}

/// Docs changelog whose releases stop at the previous minor; `CHANGELOG.md`
/// keeps the rest.
const _docsChangelog = 'website/docs/changelog/recent-releases.md';

final RegExp _releaseHeading = RegExp(r'^##\s+(\d+)\.(\d+)\.\d+');

/// Requires every published patch in the retained minor series, deriving the
/// window from the full core changelog rather than guessing patch numbers.
List<String> docsChangelogRetentionProblems(
  String changelog,
  List<String> headings,
  Version core, {
  required List<String> coreHeadings,
}) {
  final retained = retainedReleaseHeadings(
    coreHeadings,
    major: core.major,
    minor: core.minor,
  );
  final releases = headings.where(_releaseHeading.hasMatch).toList();
  final missing = retained.where((heading) => !releases.contains(heading));
  final stale = releases.where((heading) => !retained.contains(heading));
  return [
    if (missing.isNotEmpty)
      '$changelog is missing retained release sections: ${missing.join(', ')}. '
          'Keep every patch from the current and previous published minor '
          '(see CHANGELOG.md).',
    if (stale.isNotEmpty)
      '$changelog keeps only the current and previous published minor; remove '
          '${stale.join(', ')} (older releases stay in CHANGELOG.md).',
  ];
}

void main(List<String> arguments) {
  final releasePrep = arguments.contains('--release-prep');
  final unknown = arguments.where((argument) => argument != '--release-prep');
  if (unknown.isNotEmpty) {
    stderr.writeln(
      'Unknown argument(s): ${unknown.join(', ')}. '
      'Usage: verify_release_docs_versions.dart [--release-prep]',
    );
    exitCode = 64;
    return;
  }

  final errors = <String>[];
  final versions = <String, String>{};
  var pending = const <PendingCompanionBump>[];
  String? nativePin;
  for (final entry in _packagePubspecs.entries) {
    final version = _readPubspecVersion(entry.value, errors);
    if (version != null) {
      versions[entry.key] = version;
    }
  }

  final contentLimits = checkPubContentLimits(Directory.current, {
    for (final MapEntry(key: name, value: pubspec)
        in _pubSizeCheckedPubspecs.entries)
      name: File(pubspec).parent.path,
  });
  errors.addAll(contentLimits.errors);
  for (final warning in contentLimits.warnings) {
    stdout.writeln('Warning: $warning');
  }

  final docVersions = installDocVersions(
    Directory.current,
    versions,
    errors,
    releasePrep: releasePrep,
  );
  if (errors.isEmpty) {
    for (final entry in _currentDocDependencies.entries) {
      _checkCurrentDoc(
        path: entry.key,
        expectedPackages: entry.value,
        versions: docVersions,
        errors: errors,
      );
    }
    nativePin = _checkCurrentNativePins(errors);
    if (nativePin != null) {
      for (final path in defaultRuntimeClaimDocs) {
        final lines = _readLines(path, errors);
        if (lines != null) {
          errors.addAll(
            findStaleDefaultRuntimeClaims(path, lines.join('\n'), nativePin),
          );
        }
      }
    }
    checkNativeTagGrammarDocContracts(Directory.current, errors);
    pending = checkCompanionSwiftPins(Directory.current, errors);
    if (releasePrep) {
      errors.addAll(pending.map((bump) => bump.toString()));
    }
    if (releasePrep) {
      final expected = '## ${versions['llamadart']}';
      for (final changelog in _releasePrepChangelogs) {
        final heading = _matchInFile(
          Directory.current,
          changelog,
          RegExp(r'^(## .*)$', multiLine: true),
          'first release heading',
          errors,
        );
        if (heading != expected) {
          errors.add('$changelog must start with $expected before publishing.');
        }
      }
    }
    for (final changelog in _releasePrepChangelogs) {
      final lines = _readLines(changelog, errors);
      if (lines != null) {
        final headings = lines.where(RegExp(r'^##\s').hasMatch).toList();
        errors.addAll(
          unreleasedHeadingProblems(
            changelog,
            headings,
            releasePrep: releasePrep,
          ),
        );
        if (changelog == _docsChangelog) {
          try {
            errors.addAll(
              docsChangelogRetentionProblems(
                changelog,
                headings,
                Version.parse(versions['llamadart']!),
                coreHeadings: _readLines('CHANGELOG.md', errors) ?? const [],
              ),
            );
          } on FormatException {
            // `_parseCoreVersion` below reports a version that is not semver.
          }
        }
      }
    }
    final coreVersion = _parseCoreVersion(versions['llamadart']!, errors);
    if (coreVersion != null) {
      errors.addAll(
        checkCompanionCoreConstraints(Directory.current, coreVersion),
      );
      errors.addAll(
        checkCompanionVersionAlignment(Directory.current, coreVersion),
      );
      if (releasePrep) {
        errors.addAll(
          checkPublishedCompanionPins(Directory.current, coreVersion),
        );
        errors.addAll(checkCompanionPublishedCorePins(Directory.current));
      }
    }
  }

  if (errors.isNotEmpty) {
    stderr.writeln('Release docs version verification failed:');
    for (final error in errors) {
      stderr.writeln('- $error');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Release docs versions verified: '
    '${docVersions.entries.map((entry) => '${entry.key} ${entry.value}').join(', ')}; '
    'checkout llamadart-native $nativePin.',
  );
  for (final bump in pending) {
    stdout.writeln('Pending companion bump: $bump');
  }
}

String? _checkCurrentNativePins(List<String> errors) {
  final pins = <String, String>{};
  for (final entry in _currentNativePins.entries) {
    final file = File(entry.key);
    if (!file.existsSync()) {
      errors.add('${entry.key} does not exist.');
      continue;
    }

    String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException catch (error) {
      errors.add('Could not read ${entry.key}: ${error.message}.');
      continue;
    }

    final match = entry.value.firstMatch(text);
    if (match == null) {
      errors.add('${entry.key} does not contain its current native pin.');
      continue;
    }
    final pin = match.group(1)!;
    if (!isValidNativeReleaseTag(pin)) {
      errors.add(
        '${entry.key} uses unsupported native tag $pin; expected stable '
        'vMAJOR.MINOR.PATCH, stable wrapper rebuild '
        'vMAJOR.MINOR.PATCH-N, canonical historical/nightly bNNNN without '
        'leading zeros, nightly wrapper '
        'rebuild bNNNN-N, or legacy wrapper artifact bNNNN-llamadart.N.',
      );
      continue;
    }
    pins[entry.key] = pin;
  }

  if (pins.isEmpty) {
    return null;
  }
  final expectedPin =
      pins['lib/src/hook/native_release_pins.dart'] ?? pins.values.first;
  for (final entry in pins.entries) {
    if (entry.value != expectedPin) {
      errors.add(
        '${entry.key} pins native tag ${entry.value}, but '
        'lib/src/hook/native_release_pins.dart pins $expectedPin.',
      );
    }
  }
  return expectedPin;
}

Version? _parseCoreVersion(String version, List<String> errors) {
  try {
    return Version.parse(version);
  } on FormatException catch (error) {
    errors.add('pubspec.yaml version $version is not semver: ${error.message}');
    return null;
  }
}

String? _readPubspecVersion(String path, List<String> errors) {
  final lines = _readLines(path, errors);
  if (lines == null) {
    return null;
  }

  for (final line in lines) {
    final match = _versionLine.firstMatch(line);
    if (match != null) {
      return match.group(1)!;
    }
  }

  errors.add('$path does not contain a top-level version field.');
  return null;
}

void _checkCurrentDoc({
  required String path,
  required List<String> expectedPackages,
  required Map<String, String> versions,
  required List<String> errors,
}) {
  final expectedPackageSet = expectedPackages.toSet();
  final seen = <String>{};
  final lines = _readLines(path, errors);
  if (lines == null) {
    return;
  }

  var inFence = false;
  var inYamlFence = false;
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    final fenceMatch = _fenceLine.firstMatch(line);
    if (fenceMatch != null) {
      if (inFence) {
        inFence = false;
        inYamlFence = false;
      } else {
        final language = fenceMatch.group(1)?.toLowerCase();
        inFence = true;
        inYamlFence = language == 'yaml' || language == 'yml';
      }
      continue;
    }

    if (!inYamlFence) {
      continue;
    }

    final match = _dependencyLine.firstMatch(line);
    if (match == null) {
      continue;
    }

    final package = match.group(1)!;
    if (!expectedPackageSet.contains(package)) {
      continue;
    }

    seen.add(package);
    final documentedVersion = match.group(2)!;
    final expectedVersion = versions[package]!;
    if (documentedVersion != expectedVersion) {
      errors.add(
        '$path:${index + 1} documents $package ^$documentedVersion, '
        'but the install-version contract requires $expectedVersion.',
      );
    }
  }

  for (final package in expectedPackages) {
    if (!seen.contains(package)) {
      errors.add(
        '$path is missing a current YAML dependency snippet for '
        '$package ^${versions[package]}.',
      );
    }
  }
}

List<String>? _readLines(String path, List<String> errors) {
  final file = File(path);
  if (!file.existsSync()) {
    errors.add('$path does not exist.');
    return null;
  }

  try {
    return file.readAsLinesSync();
  } on FileSystemException catch (error) {
    errors.add('Could not read $path: ${error.message}.');
    return null;
  }
}

String packagePubspecPath(String package) => _packagePubspecs[package]!;

/// Checks the workflow input and prose that restate the native release tag
/// grammar against `documentation_contract` in the shared grammar fixture, so
/// a grammar change cannot land without the docs that describe it.
void checkNativeTagGrammarDocContracts(
  Directory repoRoot,
  List<String> errors,
) {
  const fixturePath = 'tool/native/fixtures/native_release_tag_grammar.json';
  final fixture = _readFromRoot(repoRoot, fixturePath, errors);
  if (fixture == null) return;

  final Map<String, dynamic> workflow;
  final String workflowPath;
  final String workflowInput;
  final String workflowRequiredText;
  final Map<String, List<String>> docs;
  try {
    final contract =
        (jsonDecode(fixture) as Map<String, dynamic>)['documentation_contract']
            as Map<String, dynamic>;
    workflow = contract['workflow'] as Map<String, dynamic>;
    workflowPath = workflow['path'] as String;
    workflowInput = workflow['input'] as String;
    workflowRequiredText = workflow['required_text'] as String;
    docs = <String, List<String>>{
      for (final entry in (contract['docs'] as Map<String, dynamic>).entries)
        entry.key: (entry.value as List<dynamic>).cast<String>().toList(
          growable: false,
        ),
    };
  } on Object catch (error) {
    errors.add('$fixturePath has no usable documentation_contract: $error.');
    return;
  }

  final workflowText = _readFromRoot(repoRoot, workflowPath, errors);
  if (workflowText != null) {
    final normalizedWorkflow = workflowText.replaceAll('\r\n', '\n');
    // Only the 8-space body lines of the input may satisfy the contract, so a
    // matching description under a different input cannot stand in for it.
    final scopedDescription = RegExp(
      '^ {6}${RegExp.escape(workflowInput)}:\$\n'
      '(?: {8}.*\$\n)*?'
      ' {8}${RegExp.escape(workflowRequiredText)}\$\n',
      multiLine: true,
    );
    if (!scopedDescription.hasMatch(normalizedWorkflow)) {
      errors.add(
        '$workflowPath $workflowInput input description does not match the '
        'canonical native tag grammar contract.',
      );
    }
  }

  final whitespace = RegExp(r'\s+');
  for (final entry in docs.entries) {
    final text = _readFromRoot(repoRoot, entry.key, errors);
    if (text == null) continue;
    final normalized = text.replaceAll(whitespace, ' ');
    for (final requirement in entry.value) {
      if (!normalized.contains(requirement.replaceAll(whitespace, ' '))) {
        errors.add(
          '${entry.key} is missing native release tag contract requirement: '
          '"$requirement".',
        );
      }
    }
  }
}

String? _readFromRoot(
  Directory repoRoot,
  String relativePath,
  List<String> errors,
) {
  final file = File('${repoRoot.path}/$relativePath');
  if (!file.existsSync()) {
    errors.add('$relativePath does not exist.');
    return null;
  }

  try {
    return file.readAsStringSync();
  } on FileSystemException catch (error) {
    errors.add('Could not read $relativePath: ${error.message}.');
    return null;
  } on FormatException catch (error) {
    errors.add('$relativePath is not valid UTF-8 text: ${error.message}.');
    return null;
  }
}
