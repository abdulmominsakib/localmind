@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('release install snippets', () {
    test('current install docs use the core pubspec version', () {
      final coreVersion = _readCorePackageVersion();
      final staleConstraints = <String>[];

      for (final target in _installSnippetTargets) {
        final text = File(target.path).readAsStringSync();
        final matches = _coreDependencyPattern.allMatches(text).toList();

        expect(
          matches,
          hasLength(target.expectedCoreDependencySnippets),
          reason:
              '${target.path} should contain exactly '
              '${target.expectedCoreDependencySnippets} current core install '
              'snippet(s).',
        );

        for (final match in matches) {
          final snippetVersion = match.namedGroup('version')!;
          if (snippetVersion != coreVersion) {
            staleConstraints.add(
              '${target.path}: found llamadart: ^$snippetVersion, '
              'expected ^$coreVersion',
            );
          }
        }
      }

      expect(
        staleConstraints,
        isEmpty,
        reason:
            'Release prep must keep user-facing install snippets aligned with '
            'the core pubspec version:\n${staleConstraints.join('\n')}',
      );
    });
  });
}

final _coreVersionPattern = RegExp(
  r'^version:\s*(?<version>[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?)\s*$',
  multiLine: true,
);

final _coreDependencyPattern = RegExp(
  r'^\s*llamadart:\s*\^(?<version>[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?)\s*$',
  multiLine: true,
);

final _installSnippetTargets = <_InstallSnippetTarget>[
  _InstallSnippetTarget('README.md', expectedCoreDependencySnippets: 2),
  _InstallSnippetTarget(
    'website/docs/getting-started/installation.md',
    expectedCoreDependencySnippets: 2,
  ),
  _InstallSnippetTarget(
    'packages/llamadart_llama_cpp_flutter/README.md',
    expectedCoreDependencySnippets: 1,
  ),
  _InstallSnippetTarget(
    'packages/llamadart_litert_lm_flutter/README.md',
    expectedCoreDependencySnippets: 1,
  ),
];

String _readCorePackageVersion() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final match = _coreVersionPattern.firstMatch(pubspec);

  if (match == null) {
    throw StateError('Could not read core package version from pubspec.yaml');
  }

  return match.namedGroup('version')!;
}

class _InstallSnippetTarget {
  const _InstallSnippetTarget(
    this.path, {
    required this.expectedCoreDependencySnippets,
  });

  final String path;
  final int expectedCoreDependencySnippets;
}
