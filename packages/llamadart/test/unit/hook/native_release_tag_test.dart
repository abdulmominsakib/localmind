@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/hook/native_bundle_config.dart';
import 'package:test/test.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'tool/native/fixtures/native_release_tag_grammar.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final patterns = fixture['patterns'] as Map<String, dynamic>;
  final positiveCases = (fixture['positive_cases'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final negativeCases = (fixture['negative_cases'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final reservedInputs = (fixture['reserved_inputs'] as List<dynamic>)
      .cast<Map<String, dynamic>>();

  test('compiled pattern matches the fixture specification', () {
    expect(nativeReleaseTagPattern.pattern, patterns['combined_pattern']);
  });

  group('positive native release tag corpus', () {
    for (final testCase in positiveCases) {
      final tag = testCase['tag'] as String;
      test('accepts "$tag" and resolves its upstream tag', () {
        expect(isValidNativeReleaseTag(tag), isTrue);
        expect(normalizeNativeLlamaCppTag(tag), testCase['upstream_tag']);
      });
    }
  });

  group('negative native release tag corpus', () {
    for (final testCase in negativeCases) {
      final tag = testCase['tag'] as String;
      test('rejects "$tag" (${testCase['reason']})', () {
        expect(isValidNativeReleaseTag(tag), isFalse);
        expect(normalizeNativeLlamaCppTag(tag), isNull);
      });
    }
  });

  group('reserved native tag inputs', () {
    for (final testCase in reservedInputs) {
      final value = testCase['value'] as String;
      test('"$value" is not a release tag the build hook accepts', () {
        expect(testCase['dart_build_hook'], isFalse);
        expect(isValidNativeReleaseTag(value), isFalse);
      });
    }
  });
}
