import 'package:yaml/yaml.dart';

/// Fixed existing evidence for a core patch release with unchanged runtime pins.
const releaseMetadataRow = 'release-metadata-verification';
const releaseMetadataTest =
    'test/unit/tooling/verify_release_docs_companion_pins_test.dart';
const releaseMetadataVerifier =
    'tool/testing/verify_release_docs_versions.dart';
const releaseMetadataCommand =
    'dart run tool/testing/verify_release_docs_versions.dart --release-prep && '
    'dart test -p vm -j 1 $releaseMetadataTest';

/// Only current release documentation, not policy or versioned/MDX documents.
const releaseMetadataDocs = <String>{
  'CHANGELOG.md',
  'README.md',
  'website/docs/changelog/recent-releases.md',
  'website/docs/getting-started/installation.md',
  'packages/llamadart_llama_cpp_flutter/README.md',
  'packages/llamadart_litert_lm_flutter/README.md',
  'packages/llamadart_stable_diffusion_flutter/README.md',
};
const releaseMetadataLocks = <String, String>{
  'example/chat_app/pubspec.lock': '../..',
  'packages/llamadart_validation/pubspec.lock': '../..',
  'website/examples/observability/pubspec.lock': '../../..',
};
final Set<String> releaseMetadataPaths = Set<String>.unmodifiable({
  'pubspec.yaml',
  ...releaseMetadataLocks.keys,
  ...releaseMetadataDocs,
});

/// A literal Git blob and its mode; no candidate code is executed.
typedef ReadinessFile = ({String mode, String contents});
typedef ReadinessFilePair = ({ReadinessFile base, ReadinessFile head});

/// Validates a deliberately narrow core-only patch release transformation.
///
/// Companion version bumps, new files, pin updates and broader release work
/// remain on the ordinary changed-production-test route. All pairs must come
/// from the evaluator's exact Git base/head, never from the evidence JSON.
String? validateReleaseMetadata(Map<String, ReadinessFilePair> files) {
  if (!files.keys.toSet().containsAll(releaseMetadataPaths) ||
      files.keys.any((path) => !releaseMetadataPaths.contains(path))) {
    return 'Metadata release requires the complete fixed core pubspec, three generated '
        'consumer locks and current release-document inventory.';
  }
  for (final entry in files.entries) {
    if (entry.value.base.mode != '100644' ||
        entry.value.head.mode != '100644') {
      return 'Metadata release requires unchanged non-executable regular-file '
          'modes: ${entry.key}.';
    }
  }
  final pubspec = files['pubspec.yaml']!;
  final oldVersion = _packageVersion(pubspec.base.contents);
  final newVersion = _packageVersion(pubspec.head.contents);
  if (oldVersion == null || newVersion == null) {
    return 'Core pubspec must contain one canonical stable version scalar.';
  }
  final oldParts = oldVersion.split('.').map(int.parse).toList();
  final newParts = newVersion.split('.').map(int.parse).toList();
  if (oldParts[0] != newParts[0] ||
      oldParts[1] != newParts[1] ||
      oldParts[2] + 1 != newParts[2] ||
      pubspec.base.contents.replaceFirst(
            'version: $oldVersion\n',
            'version: $newVersion\n',
          ) !=
          pubspec.head.contents) {
    return 'Only the next core patch version scalar may change in pubspec; '
        'dependencies, SDK, hooks, overrides and other bytes must stay identical.';
  }

  for (final entry in releaseMetadataLocks.entries) {
    if (!_validLock(files[entry.key]!, oldVersion, newVersion, entry.value)) {
      return 'Generated consumer lock ${entry.key} may change only the matching '
          'local llamadart version; package inventory, paths, hashes and SDK '
          'must stay identical.';
    }
  }
  for (final path in releaseMetadataDocs) {
    final pair = files[path];
    if (pair == null) continue;
    var baseProse = pair.base.contents;
    var headProse = pair.head.contents;
    if (path.endsWith('README.md') || path.endsWith('installation.md')) {
      final dependencies = RegExp(
        r'^\s+llamadart:\s+\^([^\s#]+)',
        multiLine: true,
      ).allMatches(pair.head.contents).toList();
      if (dependencies.isEmpty ||
          dependencies.any((match) => match.group(1) != newVersion) ||
          _companionConstraints(pair.base.contents) !=
              _companionConstraints(pair.head.contents)) {
        return 'Current installation snippets must use the new core patch '
            'and preserve already-prepared companion constraints: $path.';
      }
    }
    if (path == 'CHANGELOG.md' ||
        path == 'website/docs/changelog/recent-releases.md') {
      final historical = RegExp(
        r'^## [0-9]+\.[0-9]+\.[0-9]+\s*$',
        multiLine: true,
      ).firstMatch(pair.base.contents);
      if (historical == null ||
          !pair.head.contents.endsWith(
            pair.base.contents.substring(historical.start),
          ) ||
          RegExp(
                '^## ${RegExp.escape(newVersion)}\$',
                multiLine: true,
              ).allMatches(pair.head.contents).length !=
              1 ||
          RegExp(
            r'^## Unreleased\s*$',
            multiLine: true,
          ).hasMatch(pair.head.contents)) {
        return 'Release changelogs must name the new patch and preserve all '
            'historical numbered sections: $path.';
      }
      // Historical bytes are already immutable. Do not reinterpret their old
      // Markdown with a new parser; inspect only the mutable release prefix.
      final historyLength = pair.base.contents.length - historical.start;
      baseProse = pair.base.contents.substring(0, historical.start);
      headProse = pair.head.contents.substring(
        0,
        pair.head.contents.length - historyLength,
      );
      final headings = RegExp(r'^## ([^\n]+)$', multiLine: true);
      final before = headings
          .allMatches(baseProse)
          .map((m) => m.group(1))
          .toList();
      final after = headings
          .allMatches(headProse)
          .map((m) => m.group(1))
          .toList();
      if (before.length != 1 ||
          before.single != 'Unreleased' ||
          after.length != 1 ||
          after.single != newVersion) {
        return 'Metadata release must replace only the Unreleased section '
            'heading with the next core patch: $path.';
      }
    }
    // This exception is for Markdown prose/code examples, not active MDX.
    // Deny active contexts altogether: fragment equality cannot establish JS
    // equivalence (template literal attributes or script bodies can change).
    if (_activeFragments(baseProse) != '' ||
        _activeFragments(headProse) != '' ||
        _frontMatter(pair.base.contents) != _frontMatter(pair.head.contents) ||
        _runtimeIdentities(pair.base.contents) !=
            _runtimeIdentities(pair.head.contents)) {
      return 'Metadata release docs require inactive Markdown, unchanged '
          'frontmatter and unchanged runtime identities: $path.';
    }
  }
  return null;
}

String? _packageVersion(String source) {
  try {
    final parsed = loadYaml(source);
    final matches = RegExp(
      r'^version: (0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$',
      multiLine: true,
    ).allMatches(source).toList();
    if (parsed is! YamlMap ||
        parsed['name'] != 'llamadart' ||
        matches.length != 1) {
      return null;
    }
    final version = matches.single.group(0)!.substring('version: '.length);
    return parsed['version'] == version ? version : null;
  } on YamlException {
    return null;
  }
}

bool _validLock(
  ReadinessFilePair pair,
  String oldVersion,
  String newVersion,
  String expectedPath,
) {
  try {
    for (final source in [pair.base.contents, pair.head.contents]) {
      final parsed = loadYaml(source);
      if (parsed is! YamlMap) return false;
      final packages = parsed['packages'];
      if (packages is! YamlMap) return false;
      final core = packages['llamadart'];
      if (core is! YamlMap || core['source'] != 'path') return false;
      final description = core['description'];
      if (description is! YamlMap ||
          description['path'] != expectedPath ||
          description['relative'] != true) {
        return false;
      }
    }
    final block = RegExp(
      r'^  llamadart:\n(?:    [^\n]*\n|      [^\n]*\n)*',
      multiLine: true,
    ).allMatches(pair.base.contents).toList();
    if (block.length != 1) return false;
    final oldLine = '    version: "$oldVersion"\n';
    final oldBlock = block.single.group(0)!;
    if (oldLine.allMatches(oldBlock).length != 1) return false;
    final newBlock = oldBlock.replaceFirst(
      oldLine,
      '    version: "$newVersion"\n',
    );
    return pair.base.contents.replaceRange(
          block.single.start,
          block.single.end,
          newBlock,
        ) ==
        pair.head.contents;
  } on YamlException {
    return false;
  }
}

String? _activeFragments(String source) {
  final prose = StringBuffer();
  String? fence;
  for (final line in source.split('\n')) {
    final marker = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$').firstMatch(line);
    if (fence != null) {
      if (marker != null &&
          marker.group(1)![0] == fence[0] &&
          marker.group(1)!.length >= fence.length &&
          marker.group(2)!.trim().isEmpty) {
        fence = null;
      }
      continue;
    }
    if (marker != null) {
      if ((marker.group(1)![0] == '`' && marker.group(2)!.contains('`')) ||
          marker.group(2)!.toLowerCase().contains('mdx-code-block')) {
        return null;
      }
      fence = marker.group(1)!;
      continue;
    }
    // Mask only matching inline backtick runs. Unmatched or escaped delimiters
    // never hide syntax. This keeps fenced/inline-to-active changes observable.
    var offset = 0;
    while (offset < line.length) {
      if (line[offset] != '`') {
        prose.write(line[offset++]);
        continue;
      }
      var slashes = 0;
      for (var index = offset - 1; index >= 0 && line[index] == r'\'; index--) {
        slashes++;
      }
      var end = offset;
      while (end < line.length && line[end] == '`') {
        end++;
      }
      final delimiter = line.substring(offset, end);
      int? closing;
      if (slashes.isEven) {
        var candidate = end;
        while ((candidate = line.indexOf('`', candidate)) >= 0) {
          var after = candidate;
          while (after < line.length && line[after] == '`') {
            after++;
          }
          if (after - candidate == delimiter.length) {
            closing = after;
            break;
          }
          candidate = after;
        }
      }
      if (closing == null) {
        prose.write(delimiter);
        offset = end;
      } else {
        prose.write(' ');
        offset = closing;
      }
    }
    prose.writeln();
  }
  if (fence != null) return null;
  return RegExp(
    r'<[^>]*>|\{[^}]*\}|^\s*(?:import|export)\b[^\n]*',
    multiLine: true,
  ).allMatches(prose.toString()).map((match) => match.group(0)).join('\n');
}

String _frontMatter(String source) =>
    RegExp(r'^---\n[\s\S]*?\n---\n').firstMatch(source)?.group(0) ?? '';

String _runtimeIdentities(String source) {
  final identities = RegExp(
    r'\bv[0-9]+\.[0-9]+\.[0-9]+(?:[-.][A-Za-z0-9]+)*\b|'
    r'\bb[0-9]+(?:[-.][A-Za-z0-9]+)*\b|\b[0-9a-f]{40,64}\b',
  ).allMatches(source).map((match) => match.group(0)!).toSet().toList()..sort();
  return identities.join('\n');
}

String _companionConstraints(String source) =>
    RegExp(
          r'^\s+(llamadart_(?:llama_cpp|litert_lm)_flutter):\s+\^([^\s#]+)',
          multiLine: true,
        )
        .allMatches(source)
        .map((match) => '${match.group(1)}:${match.group(2)}')
        .join('\n');
