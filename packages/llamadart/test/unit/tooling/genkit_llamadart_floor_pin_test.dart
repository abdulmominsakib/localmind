@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('genkit workflow llamadart pins equal the package floor', () {
    final floor =
        RegExp(r'^\s*llamadart:\s*\^(\d+\.\d+\.\d+)\s*$', multiLine: true)
            .firstMatch(
              File('packages/genkit_llamadart/pubspec.yaml').readAsStringSync(),
            )!
            .group(1);

    for (final path in [
      '.github/workflows/ci.yml',
      '.github/workflows/publish_genkit_pubdev.yml',
    ]) {
      final pins = RegExp(
        r'llamadart@(\d+\.\d+\.\d+)',
      ).allMatches(File(path).readAsStringSync()).map((m) => m.group(1));
      expect(pins, isNotEmpty, reason: path);
      expect(pins, everyElement(floor), reason: path);
    }
  });
}
