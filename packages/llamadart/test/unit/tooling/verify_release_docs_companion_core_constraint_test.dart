@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/hook/apple_companion_constraint.dart';
import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../../../tool/testing/verify_release_docs_versions.dart';

const _llamaCpp = 'llamadart_llama_cpp_flutter';
const _liteRtLm = 'llamadart_litert_lm_flutter';
const _stableDiffusion = 'llamadart_stable_diffusion_flutter';

const _swiftVariables = <String, String>{
  _llamaCpp: 'llamaCppTag',
  _liteRtLm: 'liteRtLmTag',
  _stableDiffusion: 'stableDiffusionTag',
};

const _acceptedPins = <String, Set<String>>{
  _llamaCpp: {'v1.0.0', 'v1.0.0-earlier'},
  _liteRtLm: {'v2.0.0'},
  _stableDiffusion: {'v3.0.0'},
};

String _pubspec(String version, {String? core}) {
  final buffer = StringBuffer()
    ..writeln('name: companion')
    ..writeln('version: $version')
    ..writeln('dependencies:')
    ..writeln('  flutter:')
    ..writeln('    sdk: flutter');
  if (core != null) buffer.writeln('  llamadart: $core');
  return buffer.toString();
}

/// Writes every companion's pubspec, constraining core to [core], and SwiftPM
/// pin under [root]; [pubspecs] and [pins] replace them per package.
void _writeCompanions(
  Directory root, {
  String core = "'>=0.13.0 <0.14.0'",
  Map<String, String> pubspecs = const {},
  Map<String, String> pins = const {},
}) {
  for (final companion in companionSwiftPins) {
    final package = companion.package;
    final pin = pins[package] ?? _acceptedPins[package]!.first;
    File('${root.path}/${companion.pubspecPath}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(pubspecs[package] ?? _pubspec('0.0.1', core: core));
    File('${root.path}/${companion.swiftPackagePath}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('let ${_swiftVariables[package]} = "$pin"\n');
  }
}

Directory _tempRoot() {
  final root = Directory.systemTemp.createTempSync('companion_core_');
  addTearDown(() => root.deleteSync(recursive: true));
  return root;
}

void _git(Directory root, List<String> arguments) {
  final result = Process.runSync('git', [
    '-C',
    root.path,
    '-c',
    'user.name=Test',
    '-c',
    'user.email=test@example.com',
    '-c',
    'commit.gpgsign=false',
    '-c',
    'tag.gpgsign=false',
    ...arguments,
  ]);
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
}

/// Commits the companions [_writeCompanions] lays out and tags the commit.
void _commitAndTag(Directory root, List<String> tags) {
  _git(root, ['add', '-A']);
  _git(root, ['commit', '--quiet', '--allow-empty', '-m', tags.join(' ')]);
  for (final tag in tags) {
    _git(root, ['tag', tag]);
  }
}

Directory _gitRepo() {
  final root = _tempRoot();
  _git(root, ['init', '--quiet']);
  return root;
}

List<String> _cliContractProblems(String source) {
  final problems = <String>[];
  final always = RegExp(
    r'errors\.addAll\(\s*checkCompanionCoreConstraints\(\s*'
    r'Directory\.current,\s*coreVersion,?\s*\),?\s*\);',
  ).allMatches(source).toList();
  final alignment = RegExp(
    r'errors\.addAll\(\s*checkCompanionVersionAlignment\(\s*'
    r'Directory\.current,\s*coreVersion,?\s*\),?\s*\);',
  ).allMatches(source).toList();
  final strict = RegExp(
    r'if \(releasePrep\) \{\s*errors\.addAll\(\s*'
    r'checkPublishedCompanionPins\(\s*Directory\.current,\s*coreVersion,?\s*'
    r'\),?\s*\);\s*errors\.addAll\(\s*'
    r'checkCompanionPublishedCorePins\(Directory\.current\),?\s*\);\s*\}',
  ).allMatches(source).toList();
  if (always.length != 1) {
    problems.add('expected one unconditional core-constraint check');
  }
  if (alignment.length != 1) {
    problems.add('expected one unconditional version-alignment check');
  }
  if (strict.length != 1) {
    problems.add('expected one release-prep published-pin check');
  }
  final errorGuard = source.indexOf('if (errors.isNotEmpty) {');
  if (always.length == 1 &&
      alignment.length == 1 &&
      strict.length == 1 &&
      !(always.single.start < alignment.single.start &&
          alignment.single.start < strict.single.start &&
          strict.single.start < errorGuard)) {
    problems.add('every check must run before success can be reported');
  }
  if (alignment.length == 1) {
    final before = source.substring(0, alignment.single.start);
    if (before.lastIndexOf('if (releasePrep) {') >
        before.lastIndexOf('final coreVersion = _parseCoreVersion(')) {
      problems.add('the version-alignment check must not need --release-prep');
    }
  }
  return problems;
}

void main() {
  group('companionCoreConstraintFor', () {
    test('spans exactly the core minor', () {
      expect(
        companionCoreConstraintFor(Version.parse('0.13.2')),
        '>=0.13.0 <0.14.0',
      );
      expect(
        companionCoreConstraintFor(Version.parse('1.4.0')),
        '>=1.4.0 <1.5.0',
      );
    });
  });

  group('checkCompanionCoreConstraints', () {
    test('the checkout constrains every companion to its core minor', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1)!;

      expect(
        checkCompanionCoreConstraints(
          Directory.current,
          Version.parse(version),
        ),
        isEmpty,
      );
    });

    test('accepts the core minor from its first or an earlier patch', () {
      for (final core in ["'>=0.13.0 <0.14.0'", "'>=0.13.2 <0.14.0'"]) {
        final root = _tempRoot();
        _writeCompanions(root, core: core);

        expect(
          checkCompanionCoreConstraints(root, Version.parse('0.13.2')),
          isEmpty,
          reason: core,
        );
      }
    });

    test('rejects a companion without a hosted core constraint', () {
      final root = _tempRoot();
      _writeCompanions(
        root,
        pubspecs: {
          _llamaCpp: _pubspec('0.0.1'),
          _liteRtLm: '${_pubspec('0.0.1')}  llamadart:\n    path: ../..\n',
        },
      );

      final errors = checkCompanionCoreConstraints(
        root,
        Version.parse('0.13.0'),
      );

      expect(errors, [
        allOf(
          contains('packages/$_llamaCpp/pubspec.yaml declares no `llamadart`'),
          contains("declare `llamadart: '>=0.13.0 <0.14.0'`"),
        ),
        allOf(
          contains('packages/$_liteRtLm/pubspec.yaml declares `llamadart` as'),
          contains("declare `llamadart: '>=0.13.0 <0.14.0'`"),
        ),
      ]);
    });

    test('rejects a window that is not exactly the core minor', () {
      for (final core in [
        "'>=0.12.0 <0.13.0'",
        "'>=0.12.5 <0.14.0'",
        "'>=0.13.0 <0.15.0'",
        "'>=0.13.0 <1.0.0'",
        "'>=0.13.3 <0.14.0'",
        "'>=0.13.0 <=0.14.0'",
        "'^0.13.0'",
        "'any'",
      ]) {
        final root = _tempRoot();
        _writeCompanions(root, core: core);

        final errors = checkCompanionCoreConstraints(
          root,
          Version.parse('0.13.2'),
        );

        expect(errors, hasLength(companionSwiftPins.length), reason: core);
        expect(
          errors.first,
          allOf(
            contains('but core is 0.13.2'),
            contains("`'>=0.13.0 <0.14.0'` for a new minor"),
            contains('Bump the companion version'),
          ),
          reason: core,
        );
      }
    });

    test('names a prerelease core instead of a window that excludes it', () {
      final root = _tempRoot();
      _writeCompanions(root);

      final errors = checkCompanionCoreConstraints(
        root,
        Version.parse('0.13.0-dev.1'),
      );

      expect(errors, hasLength(companionSwiftPins.length));
      expect(
        errors.first,
        allOf(
          contains('but core is the prerelease 0.13.0-dev.1'),
          contains('publishes only stable core versions'),
          isNot(contains("`'>=0.13.0 <0.14.0'` for a new minor")),
        ),
      );
    });
  });

  group('checkPublishedCompanionPins', () {
    test('fails closed without core release tags', () {
      final root = _gitRepo();
      _writeCompanions(root);
      _commitAndTag(root, ['$_llamaCpp-v0.0.1']);

      expect(
        checkPublishedCompanionPins(
          root,
          Version.parse('0.13.1'),
          acceptedPins: _acceptedPins,
        ),
        [contains('No core `v*` release tags are checked out')],
      );
    });

    test('fails closed outside a git checkout', () {
      expect(
        checkPublishedCompanionPins(
          _tempRoot(),
          Version.parse('0.13.1'),
          acceptedPins: _acceptedPins,
        ),
        [contains('git tag --list v* failed')],
      );
    });

    test('passes published companions this core accepts', () {
      final root = _gitRepo();
      _writeCompanions(root, pubspecs: {_llamaCpp: _pubspec('0.0.1')});
      _commitAndTag(root, ['v0.12.0', '$_llamaCpp-v0.0.1']);
      _writeCompanions(root, pins: {_llamaCpp: 'v1.0.0-earlier'});
      _commitAndTag(root, [
        'v0.13.0',
        '$_llamaCpp-v0.0.2',
        '$_liteRtLm-v0.0.1',
        '$_stableDiffusion-v0.0.1',
      ]);

      expect(
        checkPublishedCompanionPins(
          root,
          Version.parse('0.13.1'),
          acceptedPins: _acceptedPins,
        ),
        isEmpty,
      );
    });

    test('rejects a pin moved inside the published core minor', () {
      final root = _gitRepo();
      _writeCompanions(root, pins: {_liteRtLm: 'v1.9.0'});
      _commitAndTag(root, ['v0.13.0', '$_liteRtLm-v0.0.4']);

      expect(
        checkPublishedCompanionPins(
          root,
          Version.parse('0.13.1'),
          acceptedPins: _acceptedPins,
        ),
        [
          allOf(
            startsWith(
              '$_liteRtLm-v0.0.4 published $_liteRtLm with '
              "`llamadart: '>=0.13.0 <0.14.0'`",
            ),
            contains('beside core 0.13.1'),
            contains('leehack/litert-lm-native@v1.9.0'),
            contains('this core accepts v2.0.0'),
            contains('only in a new core minor release'),
          ),
        ],
      );
    });

    test('rejects a published constraint pub cannot parse', () {
      final root = _gitRepo();
      _writeCompanions(root, core: "'>=0.13.0 <<0.14.0'");
      _commitAndTag(root, ['v0.13.0', '$_llamaCpp-v0.0.3']);

      expect(
        checkPublishedCompanionPins(
          root,
          Version.parse('0.13.1'),
          acceptedPins: _acceptedPins,
        ),
        [
          startsWith(
            '$_llamaCpp-v0.0.3 declares an unparsable `llamadart` '
            'constraint: ',
          ),
        ],
      );
    });

    test('ignores companions whose constraint excludes this core', () {
      final root = _gitRepo();
      _writeCompanions(root, pins: {_stableDiffusion: 'v0.0.9'});
      _commitAndTag(root, ['v0.13.0', '$_stableDiffusion-v0.0.1']);

      expect(
        checkPublishedCompanionPins(
          root,
          Version.parse('0.14.0'),
          acceptedPins: _acceptedPins,
        ),
        isEmpty,
      );
    });

    test('accepts earlier LiteRT-LM rebuilds of the pinned release, as the '
        'hook does', () {
      expect(earlierLiteRtLmRebuilds('v0.18.0-3'), {
        'v0.18.0',
        'v0.18.0-1',
        'v0.18.0-2',
      });
      expect(earlierLiteRtLmRebuilds('v0.18.0'), isEmpty);
      expect(earlierLiteRtLmRebuilds('g0123456789ab-2'), isEmpty);
      expect(
        coreAcceptedCompanionPins()[_liteRtLm],
        containsAll(earlierLiteRtLmRebuilds(liteRtLmReleaseTag)),
      );
      expect(
        coreAcceptedCompanionPins()[_liteRtLm],
        isNot(contains('v0.17.0')),
      );
    });

    test('defaults to the pins the checkout core accepts', () {
      expect(coreAcceptedCompanionPins().keys.toSet(), {
        for (final companion in companionSwiftPins) companion.package,
      });
      expect(
        coreAcceptedCompanionPins()[_llamaCpp],
        containsAll(llamaCppCompatibleAppleCompanionTags.keys),
      );
      for (final companion in companionSwiftPins) {
        final pin = companion.swiftTag
            .firstMatch(File(companion.swiftPackagePath).readAsStringSync())!
            .group(1);
        expect(
          coreAcceptedCompanionPins()[companion.package],
          contains(pin),
          reason: companion.package,
        );
      }
    });
  });

  group('checkCompanionPublishedCorePins', () {
    Directory pair({
      String floor = '0.15.0',
      String oldPin = 'v0.2.0-3',
      String? source,
      String oldIdentity = '0.15.1',
    }) {
      final root = _gitRepo();
      const current = <String, String>{
        _llamaCpp: llamaCppTag,
        _liteRtLm: liteRtLmReleaseTag,
        _stableDiffusion: stableDiffusionReleaseTag,
      };
      _writeCompanions(root, core: "'>=0.15.0 <0.16.0'", pins: current);
      File(
        '${root.path}/pubspec.yaml',
      ).writeAsStringSync('version: $oldIdentity\n');
      File('${root.path}/lib/src/hook/native_release_pins.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          source ??
              """
const llamaCppTag = '$llamaCppTag';
const liteRtLmReleaseTag = '$liteRtLmReleaseTag';
const stableDiffusionReleaseTag = '$oldPin';
""",
        );
      _commitAndTag(root, ['v0.15.1']);
      _writeCompanions(
        root,
        core: "'>=0.15.0 <0.16.0'",
        pins: current,
        pubspecs: {
          _stableDiffusion: _pubspec('0.15.2', core: "'>=$floor <0.16.0'"),
        },
      );
      return root;
    }

    test('new SD companion excludes the older rejecting core', () {
      expect(checkCompanionPublishedCorePins(pair()), [
        allOf(
          contains('llamadart_stable_diffusion_flutter'),
          contains('published core v0.15.1'),
          contains('Raise the companion core lower bound'),
        ),
      ]);
      expect(checkCompanionPublishedCorePins(pair(floor: '0.15.2')), isEmpty);
    });

    test('an unchanged native pin can retain the wider constraint', () {
      expect(
        checkCompanionPublishedCorePins(
          pair(oldPin: stableDiffusionReleaseTag),
        ),
        isEmpty,
      );
    });

    test('published core tag identity is checked before trusting its pins', () {
      expect(
        checkCompanionPublishedCorePins(pair(oldIdentity: '0.15.0')),
        everyElement(contains('does not match its pubspec version')),
      );
    });

    test('unreadable and duplicate historical pin declarations fail closed', () {
      for (final declarations in [
        '',
        "const stableDiffusionReleaseTag = '$stableDiffusionReleaseTag';\n" * 2,
      ]) {
        final source =
            "const llamaCppTag = '$llamaCppTag';\n"
            "const liteRtLmReleaseTag = '$liteRtLmReleaseTag';\n$declarations";
        expect(checkCompanionPublishedCorePins(pair(source: source)), [
          contains('Cannot uniquely read stableDiffusionReleaseTag'),
        ]);
      }
    });

    test('historical compatibility is interpreted as data, not executed', () {
      final source =
          """
const llamaCppTag = '$llamaCppTag';
const liteRtLmReleaseTag = '$liteRtLmReleaseTag';
const stableDiffusionReleaseTag = 'v0.2.0-3';
const stableDiffusionCompatibleAppleCompanionTags = <String, String>{
  '$stableDiffusionReleaseTag': 'verified ' 'explicit compatibility',
};
""";
      expect(checkCompanionPublishedCorePins(pair(source: source)), isEmpty);
      expect(
        checkCompanionPublishedCorePins(
          pair(source: source.replaceFirst('<String, String>{', 'unknown(')),
        ),
        contains(
          contains('Cannot read stableDiffusionCompatibleAppleCompanionTags'),
        ),
      );
    });

    test('commented and string-contained keys never qualify a historical pin', () {
      for (final body in [
        "/* '$stableDiffusionReleaseTag': 'comment only', */",
        "/* outer /* nested */ '$stableDiffusionReleaseTag': 'comment only', */",
        "// '$stableDiffusionReleaseTag': 'comment only',",
        "'v0.2.0-2': \"\"\"example\n  '$stableDiffusionReleaseTag': 'string only',\n\"\"\",",
      ]) {
        final source =
            """
const llamaCppTag = '$llamaCppTag';
const liteRtLmReleaseTag = '$liteRtLmReleaseTag';
const stableDiffusionReleaseTag = 'v0.2.0-3';
const stableDiffusionCompatibleAppleCompanionTags = <String, String>{
  $body
};
""";
        expect(checkCompanionPublishedCorePins(pair(source: source)), [
          contains('whose hook rejects that pin'),
        ], reason: body);
      }
    });

    test('string-contained declarations cannot impersonate live constants', () {
      final source =
          """
const llamaCppTag = '$llamaCppTag';
const liteRtLmReleaseTag = '$liteRtLmReleaseTag';
const stableDiffusionReleaseTag = 'v0.2.0-3';
const example = \"\"\"
const stableDiffusionCompatibleAppleCompanionTags = <String, String>{
  '$stableDiffusionReleaseTag': 'string only',
};
\"\"\";
""";
      expect(checkCompanionPublishedCorePins(pair(source: source)), [
        contains('whose hook rejects that pin'),
      ]);
      expect(
        checkCompanionPublishedCorePins(
          pair(
            source: source.replaceFirst(
              "const stableDiffusionReleaseTag = 'v0.2.0-3';",
              "/* const stableDiffusionReleaseTag = '$stableDiffusionReleaseTag'; */",
            ),
          ),
        ),
        [contains('Cannot uniquely read stableDiffusionReleaseTag')],
      );
    });

    test('nonliteral and duplicate compatibility entries fail closed', () {
      for (final body in [
        "...{'$stableDiffusionReleaseTag': 'spread'},",
        "if (true) '$stableDiffusionReleaseTag': 'conditional',",
        "'$stableDiffusionReleaseTag': describe(),",
        r"'v0.2.0-4': '${runtimeValue}',",
        "'$stableDiffusionReleaseTag': 'first', '$stableDiffusionReleaseTag': 'duplicate',",
      ]) {
        final source =
            """
const llamaCppTag = '$llamaCppTag';
const liteRtLmReleaseTag = '$liteRtLmReleaseTag';
const stableDiffusionReleaseTag = 'v0.2.0-3';
const stableDiffusionCompatibleAppleCompanionTags = <String, String>{
  $body
};
""";
        expect(checkCompanionPublishedCorePins(pair(source: source)), [
          contains('Cannot read stableDiffusionCompatibleAppleCompanionTags'),
        ], reason: body);
      }
    });

    test('the production release-prep reverse check cannot be bypassed', () {
      final source = File(
        'tool/testing/verify_release_docs_versions.dart',
      ).readAsStringSync();
      expect(_cliContractProblems(source), isEmpty);
      final bypassed = source.replaceFirst(
        'errors.addAll(checkCompanionPublishedCorePins(Directory.current));',
        '',
      );
      expect(
        _cliContractProblems(bypassed),
        contains('expected one release-prep published-pin check'),
      );
    });
  });

  group('checkCompanionVersionAlignment', () {
    Directory companionsAt(Map<String, String> versions) {
      final root = _tempRoot();
      _writeCompanions(
        root,
        pubspecs: {
          for (final entry in versions.entries)
            entry.key: _pubspec(entry.value, core: "'>=0.13.0 <0.14.0'"),
        },
      );
      return root;
    }

    test('the checkout passes', () {
      final version = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;

      expect(
        checkCompanionVersionAlignment(
          Directory.current,
          Version.parse(version),
        ),
        isEmpty,
      );
    });

    test('starts with core 0.13.0', () {
      final root = companionsAt({});

      expect(
        checkCompanionVersionAlignment(root, Version.parse('0.12.9')),
        isEmpty,
      );
      expect(
        checkCompanionVersionAlignment(root, Version.parse('0.13.0')),
        hasLength(companionSwiftPins.length),
      );
    });

    test('starts where the hook names a lockstep companion constraint', () {
      final root = companionsAt({});

      for (final core in [
        '0.12.9',
        '0.13.0-dev.1',
        '0.13.0',
        '0.13.0+build.1',
        '0.13.1-dev.1',
        '1.0.0',
      ]) {
        expect(
          checkCompanionVersionAlignment(root, Version.parse(core)).isEmpty,
          !isAppleCompanionLockstepCore(core),
          reason: core,
        );
      }
      expect(
        checkCompanionVersionAlignment(root, Version.parse('0.13.0-dev.1')),
        isEmpty,
      );
    });

    test('accepts any companion patch within the core minor', () {
      final root = companionsAt({
        _llamaCpp: '0.13.0',
        _liteRtLm: '0.13.7',
        _stableDiffusion: '0.13.2',
      });

      expect(
        checkCompanionVersionAlignment(root, Version.parse('0.13.4')),
        isEmpty,
      );
    });

    test('rejects a companion outside the core MAJOR.MINOR', () {
      for (final version in ['0.12.4', '0.0.23', '0.14.0', '1.13.0']) {
        final root = companionsAt({
          _llamaCpp: '0.13.0',
          _liteRtLm: version,
          _stableDiffusion: '0.13.0',
        });

        expect(checkCompanionVersionAlignment(root, Version.parse('0.13.0')), [
          allOf(
            startsWith(
              'packages/$_liteRtLm/pubspec.yaml is version $version, but '
              'core is 0.13.0',
            ),
            contains('share the core MAJOR.MINOR'),
            contains('Set it to 0.13.0 for a new core minor'),
          ),
        ], reason: version);
      }
    });

    test('compares the major as well as the minor', () {
      final root = companionsAt({
        _llamaCpp: '1.0.0',
        _liteRtLm: '1.0.3',
        _stableDiffusion: '2.0.0',
      });

      expect(checkCompanionVersionAlignment(root, Version.parse('1.0.1')), [
        startsWith(
          'packages/$_stableDiffusion/pubspec.yaml is version 2.0.0, but '
          'core is 1.0.1',
        ),
      ]);
    });

    test('rejects a companion version it cannot read', () {
      final root = companionsAt({
        _llamaCpp: '0.13.0',
        _liteRtLm: 'next',
        _stableDiffusion: '0.13.0',
      });
      File(
        '${root.path}/packages/$_llamaCpp/pubspec.yaml',
      ).writeAsStringSync('name: $_llamaCpp\n');

      expect(checkCompanionVersionAlignment(root, Version.parse('0.13.0')), [
        'packages/$_llamaCpp/pubspec.yaml does not contain its version field.',
        startsWith('packages/$_liteRtLm/pubspec.yaml version next is not '),
      ]);
    });
  });

  test('release docs CLI runs every check before reporting success', () {
    final source = File(
      'tool/testing/verify_release_docs_versions.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(_cliContractProblems(source), isEmpty);
    for (final mutated in [
      source.replaceFirst(
        'checkCompanionCoreConstraints(Directory.current, coreVersion)',
        'checkCompanionCoreConstraints(Directory.systemTemp, coreVersion)',
      ),
      source.replaceFirst(
        'checkPublishedCompanionPins(Directory.current, coreVersion)',
        'checkPublishedCompanionPins(Directory.systemTemp, coreVersion)',
      ),
      source.replaceFirst(
        RegExp(r'if \(releasePrep\) \{\s*errors\.addAll\(\s*checkPublished'),
        'if (false) {\n        errors.addAll(\n          checkPublished',
      ),
      source.replaceFirst(
        'checkCompanionVersionAlignment(Directory.current, coreVersion)',
        'checkCompanionVersionAlignment(Directory.systemTemp, coreVersion)',
      ),
      source.replaceFirst(
        RegExp(
          r'errors\.addAll\(\s*checkCompanionVersionAlignment\('
          r'Directory\.current, coreVersion\),?\s*\);',
        ),
        '',
      ),
      source.replaceFirstMapped(
        RegExp(
          r'errors\.addAll\(\s*checkCompanionVersionAlignment\('
          r'Directory\.current, coreVersion\),?\s*\);',
        ),
        (match) => 'if (releasePrep) {\n${match[0]}\n}',
      ),
    ]) {
      expect(_cliContractProblems(mutated), isNotEmpty);
    }
  });
}
