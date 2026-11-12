@TestOn('vm')
library;

import 'package:llamadart/src/hook/apple_companion_constraint.dart';
import 'package:test/test.dart';

const _nativePin = 'leehack/llamadart-native@v0.6.0-3';

String? _requirement(String? coreVersion, {String? firstPinningRelease}) =>
    appleCompanionRequirement(
      packageName: 'llamadart_llama_cpp_flutter',
      coreVersion: coreVersion,
      nativePin: _nativePin,
      firstPinningRelease: firstPinningRelease,
    );

void main() {
  group('appleCompanionConstraint', () {
    test('a core before lockstep names the first pinning 0.0.x release', () {
      for (final core in ['0.12.0', '0.12.2', '0.9.1']) {
        expect(
          appleCompanionConstraint(core, firstPinningRelease: '0.0.23'),
          '^0.0.23',
          reason: core,
        );
        expect(appleCompanionConstraint(core), isNull, reason: core);
      }
    });

    test('a lockstep core names its minor\'s first release when the pin '
        'predates the minor', () {
      for (final (core, expected) in [
        ('0.13.0', '^0.13.0'),
        ('0.13.4', '^0.13.0'),
        ('0.14.1', '^0.14.0'),
      ]) {
        for (final firstPinning in ['0.0.23', '0.13.1']) {
          if (firstPinning == '0.13.1' && core.startsWith('0.13.')) continue;
          expect(
            appleCompanionConstraint(core, firstPinningRelease: firstPinning),
            expected,
            reason: '$core with $firstPinning',
          );
        }
      }
    });

    test('a lockstep core names the first same-minor release pinning its '
        'tag', () {
      for (final (core, first) in [
        ('0.13.2', '0.13.1'),
        ('0.13.1', '0.13.1'),
        ('0.14.0', '0.14.0'),
      ]) {
        expect(
          appleCompanionConstraint(core, firstPinningRelease: first),
          '^$first',
          reason: '$core with $first',
        );
      }
    });

    test('a 1.x core names a range a caret would widen', () {
      expect(
        appleCompanionConstraint('1.2.3', firstPinningRelease: '1.2.1'),
        "'>=1.2.1 <1.3.0'",
      );
      expect(
        appleCompanionConstraint('1.2.3', firstPinningRelease: '1.1.4'),
        "'>=1.2.0 <1.3.0'",
      );
    });

    test('a prerelease of the first lockstep core precedes lockstep', () {
      expect(
        appleCompanionConstraint('0.13.0-dev.1', firstPinningRelease: '0.0.23'),
        '^0.0.23',
      );
      for (final (core, expected) in [
        ('0.13.0+build.1', '^0.13.0'),
        ('0.13.1-dev.1', '^0.13.0'),
        ('0.14.0-dev.1', '^0.14.0'),
      ]) {
        expect(
          appleCompanionConstraint(core, firstPinningRelease: '0.0.23'),
          expected,
          reason: core,
        );
      }
    });

    test('an unreadable core version names nothing', () {
      for (final core in [null, '', 'latest', '0.13']) {
        expect(
          appleCompanionConstraint(core, firstPinningRelease: '0.0.23'),
          isNull,
          reason: core,
        );
      }
    });
  });

  group('appleCompanionRequirement', () {
    test('core 0.12.x names the first release pinning the native tag', () {
      expect(
        _requirement('0.12.2', firstPinningRelease: '0.0.23'),
        'Depend on `llamadart_llama_cpp_flutter: ^0.0.23`, the first release '
        'pinning $_nativePin, in pubspec.yaml and rerun flutter pub get; a '
        'caret constraint on an earlier 0.0.x release never resolves it.',
      );
    });

    test('core 0.13.x names the companions of its minor', () {
      for (final (core, first, constraint) in [
        ('0.13.0', '0.0.23', '^0.13.0'),
        ('0.13.2', '0.0.23', '^0.13.0'),
        ('0.13.2', '0.13.1', '^0.13.1'),
      ]) {
        final requirement = _requirement(core, firstPinningRelease: first);
        expect(
          requirement,
          'Depend on `llamadart_llama_cpp_flutter: $constraint`, the core '
          '0.13.x companion releases pinning $_nativePin, in pubspec.yaml and '
          'rerun flutter pub get.',
          reason: '$core with $first',
        );
        expect(requirement, isNot(contains('0.0.')), reason: core);
      }
    });

    test('names nothing when no constraint is known', () {
      for (final core in ['0.12.2', '0.13.0', '0.13.2', '1.2.3']) {
        expect(appleCompanionConstraint(core), isNull, reason: core);
        expect(_requirement(core), isNull, reason: core);
      }
      expect(_requirement(null, firstPinningRelease: '0.0.23'), isNull);
    });
  });

  test('isAppleCompanionLockstepCore follows semver precedence', () {
    for (final core in ['0.13.0', '0.13.0+build.1', '0.13.1-dev.1', '1.0.0']) {
      expect(isAppleCompanionLockstepCore(core), isTrue, reason: core);
    }
    for (final core in ['0.12.9', '0.13.0-dev.1', '0.0.23', 'latest', '']) {
      expect(isAppleCompanionLockstepCore(core), isFalse, reason: core);
    }
  });
}
