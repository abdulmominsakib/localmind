@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../support/dart_script_snapshot.dart';

void main() {
  final packages = File('.dart_tool/package_config.json').absolute.path;
  late String verifier;
  late Directory root;

  setUpAll(
    () async => verifier = await compileDartScript(
      'tool/testing/verify_release_docs_versions.dart',
    ),
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('release-prep-heading-');
    // Companion patches move independently; the heading must follow the core.
    for (final entry in <String, String>{
      'pubspec.yaml': '0.14.0',
      'packages/llamadart_llama_cpp_flutter/pubspec.yaml': '0.14.1',
      'packages/llamadart_litert_lm_flutter/pubspec.yaml': '0.14.0',
      'packages/llamadart_stable_diffusion_flutter/pubspec.yaml': '0.14.0',
    }.entries) {
      File('${root.path}/${entry.key}')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('version: ${entry.value}\n');
    }
  });
  tearDown(() => root.deleteSync(recursive: true));

  ProcessResult verify(
    String changelog, {
    String? docsChangelog,
    bool releasePrep = true,
  }) {
    File('${root.path}/CHANGELOG.md').writeAsStringSync(changelog);
    File('${root.path}/website/docs/changelog/recent-releases.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(docsChangelog ?? changelog);
    return Process.runSync(Platform.resolvedExecutable, <String>[
      '--packages=$packages',
      verifier,
      if (releasePrep) '--release-prep',
    ], workingDirectory: root.path);
  }

  const diagnostic =
      'CHANGELOG.md must start with ## 0.14.0 before publishing.';
  const docsDiagnostic =
      'website/docs/changelog/recent-releases.md must start with ## 0.14.0 '
      'before publishing.';
  for (final entry in <String, String>{
    'Unreleased before the version': '## Unreleased\n\n## 0.14.0\n',
    'another version first': '## 0.13.2\n\n## 0.14.0\n',
    'no level-two heading': '# Changelog\n',
    'extra heading whitespace': '##  0.14.0\n',
    'trailing heading whitespace': '## 0.14.0 \n',
  }.entries) {
    test('release prep rejects ${entry.key}', () {
      final result = verify(entry.value);
      expect(result.exitCode, 1);
      expect(result.stderr, contains(diagnostic));
    });
  }

  for (final entry in <String, String>{
    'Unreleased before the version':
        '---\ntitle: Recent releases\n---\n\n'
        '## Unreleased\n\n## 0.14.0\n',
    'another version first': '## 0.13.2\n\n## 0.14.0\n',
  }.entries) {
    test('release prep rejects a docs changelog with ${entry.key}', () {
      final result = verify(
        '## 0.14.0\n\n## 0.13.2\n',
        docsChangelog: entry.value,
      );
      expect(result.exitCode, 1);
      expect(result.stderr, contains(docsDiagnostic));
      expect(result.stderr, isNot(contains(diagnostic)));
    });
  }

  test('the exact version heading passes the heading gate', () {
    final result = verify(
      '# Changelog\n\n## 0.14.0\n\n## 0.13.2\n',
      docsChangelog: '---\ntitle: Recent releases\n---\n\n## 0.14.0\n',
    );
    // This minimal repo deliberately lacks install docs; reaching their check
    // proves the heading gate accepted the prepared changelog.
    expect(result.stderr, isNot(contains(diagnostic)));
    expect(result.stderr, isNot(contains(docsDiagnostic)));
    expect(result.stderr, contains('README.md does not exist'));
  });

  test('normal verification still permits Unreleased before the version', () {
    final result = verify('## Unreleased\n\n## 0.14.0\n', releasePrep: false);
    expect(result.stderr, isNot(contains(diagnostic)));
    expect(result.stderr, isNot(contains(docsDiagnostic)));
    expect(result.stderr, isNot(contains('`## Unreleased`')));
    expect(result.stderr, contains('README.md does not exist'));
  });

  test('normal verification counts only level-two headings', () {
    final result = verify(
      '### Notes\n\n## Unreleased\n\n### Fixes\n\n## 0.14.0\n',
      releasePrep: false,
    );
    expect(result.stderr, isNot(contains('`## Unreleased`')));
    expect(result.stderr, contains('README.md does not exist'));
  });

  test('release prep rejects an Unreleased section below the version', () {
    final result = verify(
      '## 0.14.0\n\n## Unreleased\n\n- Stray.\n\n## 0.13.2\n',
      docsChangelog: '## 0.14.0\n\n## 0.13.2\n',
    );
    expect(result.exitCode, 1);
    expect(
      result.stderr,
      contains('CHANGELOG.md must not keep `## Unreleased` when publishing.'),
    );
    expect(result.stderr, isNot(contains(docsDiagnostic)));
  });

  for (final entry in <String, String>{
    'below a released section': '## 0.14.0\n\n## Unreleased\n\n- Stray.\n',
    'twice': '## Unreleased\n\n- A.\n\n## Unreleased\n\n## 0.14.0\n',
  }.entries) {
    test('normal verification rejects Unreleased ${entry.key}', () {
      final result = verify(
        '## Unreleased\n\n## 0.14.0\n',
        docsChangelog: '---\ntitle: Recent releases\n---\n\n${entry.value}',
        releasePrep: false,
      );
      expect(result.exitCode, 1);
      expect(
        result.stderr,
        contains(
          'website/docs/changelog/recent-releases.md must have at most one '
          '`## Unreleased`, above every released section.',
        ),
      );
      expect(result.stderr, isNot(contains('CHANGELOG.md must have')));
    });
  }

  group('docs changelog retention', () {
    const retention = 'website/docs/changelog/recent-releases.md keeps only ';

    for (final releasePrep in [true, false]) {
      test(
        'keeps the current and previous minor (releasePrep $releasePrep)',
        () {
          final result = verify(
            '## 0.14.0\n\n## 0.13.2\n\n## 0.13.0\n\n## 0.12.2\n',
            docsChangelog: '## 0.14.0\n\n## 0.13.2\n\n## 0.13.0\n',
            releasePrep: releasePrep,
          );
          expect(result.stderr, isNot(contains(retention)));
        },
      );

      test('rejects releases older than the previous minor '
          '(releasePrep $releasePrep)', () {
        final result = verify(
          '## 0.14.0\n\n## 0.13.2\n\n## 0.12.2\n',
          docsChangelog: '## 0.14.0\n\n## 0.13.2\n\n## 0.12.2\n\n## 0.5.0\n',
          releasePrep: releasePrep,
        );
        expect(result.exitCode, 1);
        expect(
          result.stderr,
          contains(
            '${retention}the current and previous published minor; remove ## 0.12.2, ## 0.5.0 '
            '(older releases stay in CHANGELOG.md).',
          ),
        );
        expect(result.stderr, isNot(contains('CHANGELOG.md keeps only')));
      });
    }

    for (final releasePrep in [true, false]) {
      for (final removed in [
        ['## 0.14.0'],
        ['## 0.13.0'],
        ['## 0.13.2', '## 0.13.0'],
      ]) {
        test('rejects missing $removed (releasePrep $releasePrep)', () {
          const headings = ['## 0.14.1', '## 0.14.0', '## 0.13.2', '## 0.13.0'];
          File(
            '${root.path}/pubspec.yaml',
          ).writeAsStringSync('version: 0.14.1\n');
          final result = verify(
            [...headings, '## 0.12.2'].join('\n\n'),
            docsChangelog: headings
                .where((heading) => !removed.contains(heading))
                .join('\n\n'),
            releasePrep: releasePrep,
          );
          expect(result.exitCode, 1);
          expect(
            result.stderr,
            contains(
              'is missing retained release sections: ${removed.join(', ')}.',
            ),
          );
        });
      }
    }

    test('ignores headings that are not releases', () {
      final result = verify(
        '## 0.14.0\n',
        docsChangelog: '## 0.14.0\n\n## 0.5.x line highlights\n',
      );
      expect(result.stderr, isNot(contains(retention)));
    });
  });
}
