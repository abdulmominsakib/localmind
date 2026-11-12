@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/release/companion_pub_preflight.dart';
import '../../../tool/testing/release_metadata_readiness.dart';
import '../../../tool/testing/verify_release_docs_versions.dart';

/// Reads [path] with LF line endings, as Windows checkouts may use CRLF.
String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// Every hand-maintained companion list must name each Flutter Apple companion
/// checked out under `packages/`, so a removed or misspelled entry fails here.
void main() {
  final companions = discoverAppleCompanionPackages(Directory.current);

  test('the companion inventory is discovered', () {
    expect(
      companions.map((companion) => companion.name),
      contains('llamadart_stable_diffusion_flutter'),
    );
  });

  for (final companion in companions) {
    group(companion.name, () {
      test('release metadata docs include its README', () {
        final readme = '${companion.path}/README.md';
        expect(releaseMetadataDocs, contains(readme));
        expect(File(readme).existsSync(), isTrue);
      });

      test('the release docs verifier reads its pubspec', () {
        final pubspec = packagePubspecPath(companion.name);
        expect(pubspec, '${companion.path}/pubspec.yaml');
        expect(_read(pubspec), contains('name: ${companion.name}\n'));
      });

      test('the release docs verifier checks its SwiftPM pin', () {
        final pin = companionSwiftPins.singleWhere(
          (pin) => pin.package == companion.name,
        );
        expect(pin.root, companion.path);
        expect(pin.swiftTag.hasMatch(_read(pin.swiftPackagePath)), isTrue);
      });

      test('release automation can publish it', () {
        final release = _read('.github/workflows/release_on_prep_merge.yml');
        final publish = _read('.github/workflows/publish_companion_pubdev.yml');

        expect(release, contains('            ${companion.path}\n'));
        expect(
          publish,
          contains("      - '${companion.name}-v[0-9]+.[0-9]+.[0-9]+*'"),
        );
        expect(publish, contains('package_path="${companion.path}"'));
      });
    });
  }

  test(
    'the release docs verifier pins no companion that is not checked out',
    () {
      expect(
        companionSwiftPins.map((pin) => pin.package).toSet(),
        companions.map((companion) => companion.name).toSet(),
      );
    },
  );
}
