#!/usr/bin/env dart

/// Fails a pull request that changes a released section of the core
/// changelogs.
///
/// Both changelogs union-merge (`.gitattributes`), so rebasing a branch across
/// a release can silently move its bullets, or stale copies of released ones,
/// into the new `## X.Y.Z` section. Everything from the first `## <version>`
/// heading down must therefore match the merge base with the PR's base branch
/// byte-for-byte. Release-prep PRs, detected as `release_on_prep_merge.yml`
/// detects them, are exempt because they create the new section.
///
/// The docs changelog keeps only the current and previous minor, so it may
/// also lose its oldest sections: its tail may be cut at a `## <version>`
/// heading, provided only releases older than the retained two minor series
/// are removed and every section that remains is unchanged. `CHANGELOG.md`
/// may instead move its oldest sections to the start of the releases in
/// `doc/changelog_archive.md`, keeping the published file under pub.dev's
/// content limit: read together, both files' released sections must stay
/// byte-for-byte unchanged.
///
/// CI runs it on `pull_request` events from a full-history checkout:
///
/// ```bash
/// dart run tool/testing/check_released_changelog_sections.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';

/// Changelogs whose released sections a non-release PR must not change.
const releasedChangelogs = <String>[
  'CHANGELOG.md',
  'website/docs/changelog/recent-releases.md',
];

/// Changelogs that may lose their oldest released sections.
const truncatableChangelogs = <String>{
  'website/docs/changelog/recent-releases.md',
};

/// Changelogs whose oldest released sections may move, verbatim, to the start
/// of the releases in an archive.
const changelogArchives = <String, String>{
  'CHANGELOG.md': 'doc/changelog_archive.md',
};

final RegExp _versionHeading = RegExp(r'^## [0-9]+\.[0-9]+\.[0-9]+\S*\s*$');
final RegExp _prepBranch = RegExp(
  r'^release/(prep-[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9._-]+)?'
  r'|[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9._-]+)?-prep)$',
);

/// Release headings in the current series and the latest earlier series that
/// actually shipped. This also retains the last minor of the previous major
/// when the current minor is zero; missing patch numbers are never invented.
List<String> retainedReleaseHeadings(
  Iterable<String> headings, {
  required int major,
  required int minor,
}) {
  final releases = <(String, int, int)>[];
  final version = RegExp(r'^## (\d+)\.(\d+)\.\d+\S*\s*$');
  (int, int)? previous;
  for (final heading in headings) {
    final match = version.firstMatch(heading);
    if (match == null) continue;
    final series = (int.parse(match[1]!), int.parse(match[2]!));
    releases.add((heading.trim(), series.$1, series.$2));
    if ((series.$1 < major || (series.$1 == major && series.$2 < minor)) &&
        (previous == null ||
            series.$1 > previous.$1 ||
            (series.$1 == previous.$1 && series.$2 > previous.$2))) {
      previous = series;
    }
  }
  return [
    for (final (heading, releaseMajor, releaseMinor) in releases)
      if ((releaseMajor == major && releaseMinor == minor) ||
          (releaseMajor, releaseMinor) == previous)
        heading,
  ];
}

/// Whether a PR is a core release prep, as `release_on_prep_merge.yml`
/// decides: the `release-prep` label or a versioned prep branch, from this
/// repository and not a Genkit release branch.
bool isCoreReleasePrep({
  required Iterable<String> labels,
  required String headRef,
  required String headRepository,
  required String repository,
}) {
  if (headRepository != repository ||
      headRef.startsWith('release/genkit_llamadart-')) {
    return false;
  }
  return labels.contains('release-prep') || _prepBranch.hasMatch(headRef);
}

/// Why [head] changes the released sections of [base], or null when it does
/// not. Released sections start at the first `## <version>` heading.
String? releasedSectionChange(String path, String base, String head) {
  final baseLines = const LineSplitter().convert(base);
  final baseStart = baseLines.indexWhere(_versionHeading.hasMatch);
  if (baseStart < 0) return null;
  final headLines = const LineSplitter().convert(head);
  final headStart = headLines.indexWhere(_versionHeading.hasMatch);
  if (headStart < 0) {
    return '$path no longer has the released section '
        '`${baseLines[baseStart]}`.';
  }
  final released = baseLines.sublist(baseStart);
  final candidate = headLines.sublist(headStart);
  final length = released.length < candidate.length
      ? released.length
      : candidate.length;
  var index = 0;
  while (index < length && released[index] == candidate[index]) {
    index++;
  }
  if (index == length &&
      released.length == candidate.length &&
      _endsWithNewline(base) == _endsWithNewline(head)) {
    return null;
  }
  if (truncatableChangelogs.contains(path) &&
      _isTailTruncation(released, candidate)) {
    return null;
  }
  String quote(List<String> lines) =>
      index < lines.length ? '`${lines[index]}`' : 'the end of the file';
  return '$path:${headStart + index + 1} changes a released section: the '
      'base has ${quote(released)}, this PR has ${quote(candidate)}. Keep '
      'new bullets under `## Unreleased`; a rebase across a release can move '
      'them (see website/docs/maintainers/release-workflow.md).';
}

/// Why [head] and [headArchive] change the released sections of [base] and
/// [baseArchive], or null when they do not. A null archive is absent.
///
/// Whole sections may move from the end of [path] to the start of
/// [archivePath]'s releases, which follow its first `## <version>` heading.
/// The changelog's releases followed by the archive's, ignoring blank lines
/// where they join, must match the base byte-for-byte.
String? archivedSectionChange(
  String path,
  String archivePath, {
  required String base,
  required String head,
  String? baseArchive,
  String? headArchive,
}) {
  if (baseArchive == headArchive) {
    return releasedSectionChange(path, base, head);
  }
  final headLines = const LineSplitter().convert(head);
  final headStart = headLines.indexWhere(_versionHeading.hasMatch);
  if (headStart < 0) return releasedSectionChange(path, base, head);
  final kept = _withoutTrailingBlankLines(headLines.sublist(headStart));
  final archiveLines = const LineSplitter().convert(headArchive ?? '');
  final archiveStart = archiveLines.indexWhere(_versionHeading.hasMatch);
  final released = _joinedReleases(base, baseArchive);
  final candidate = _joinedReleases(head, headArchive);
  final length = released.length < candidate.length
      ? released.length
      : candidate.length;
  var index = 0;
  while (index < length && released[index] == candidate[index]) {
    index++;
  }
  if (index == length && released.length == candidate.length) return null;
  final location = index < kept.length
      ? '$path:${headStart + index + 1}'
      : archiveStart < 0
      ? archivePath
      : '$archivePath:${archiveStart + index - kept.length}';
  String quote(List<String> lines) =>
      index < lines.length ? '`${lines[index]}`' : 'the end of the releases';
  return '$location changes a released section: the base has '
      '${quote(released)}, this PR has ${quote(candidate)}. Released sections '
      'may only move, unchanged, from the end of $path to the start of the '
      'releases in $archivePath; keep new bullets under `## Unreleased` (see '
      'website/docs/maintainers/release-workflow.md).';
}

/// The released lines of [changelog] followed by those of [archive], with
/// one blank line where they join.
List<String> _joinedReleases(String changelog, String? archive) {
  List<String> releases(String text) {
    final lines = const LineSplitter().convert(text);
    final start = lines.indexWhere(_versionHeading.hasMatch);
    return start < 0
        ? const []
        : _withoutTrailingBlankLines(lines.sublist(start));
  }

  final archived = releases(archive ?? '');
  return [
    ...releases(changelog),
    if (archived.isNotEmpty) ...['', ...archived],
  ];
}

/// Whether [candidate] is [released] with whole sections cut from the end:
/// what remains is an exact prefix and the first removed line is a version
/// heading. Trailing blank lines are ignored so an editor may trim the file.
bool _isTailTruncation(List<String> released, List<String> candidate) {
  final kept = _withoutTrailingBlankLines(candidate);
  if (kept.isEmpty ||
      kept.length >= _withoutTrailingBlankLines(released).length) {
    return false;
  }
  for (var index = 0; index < kept.length; index++) {
    if (released[index] != kept[index]) return false;
  }
  var next = kept.length;
  while (next < released.length && released[next].trim().isEmpty) {
    next++;
  }
  if (next >= released.length || !_versionHeading.hasMatch(released[next])) {
    return false;
  }
  final current = RegExp(r'^## (\d+)\.(\d+)\.').firstMatch(released.first)!;
  final retained = retainedReleaseHeadings(
    released,
    major: int.parse(current[1]!),
    minor: int.parse(current[2]!),
  ).toSet();
  return !released.skip(next).any(retained.contains);
}

List<String> _withoutTrailingBlankLines(List<String> lines) {
  var end = lines.length;
  while (end > 0 && lines[end - 1].trim().isEmpty) {
    end--;
  }
  return lines.sublist(0, end);
}

bool _endsWithNewline(String text) => text.endsWith('\n');

/// Problems for the PR described by the GitHub [event] payload, checked
/// against the Git checkout in [repoRoot]. Throws [StateError] when the base
/// cannot be determined, so the check fails closed.
List<String> checkReleasedChangelogSections(
  Directory repoRoot,
  Map<String, Object?> event, {
  required String repository,
  void Function(String message)? log,
}) {
  final pullRequest = event['pull_request'];
  if (pullRequest is! Map) {
    throw StateError('The event payload has no pull_request object.');
  }
  final base = pullRequest['base'];
  final head = pullRequest['head'];
  final baseRef = base is Map ? base['ref'] : null;
  final headRef = head is Map ? head['ref'] : null;
  final headRepo = head is Map ? head['repo'] : null;
  final headRepository = headRepo is Map ? headRepo['full_name'] : null;
  if (baseRef is! String || baseRef.isEmpty || headRef is! String) {
    throw StateError('The event payload has no pull_request base/head ref.');
  }
  final labels = [
    for (final label in pullRequest['labels'] as List? ?? const [])
      if (label is Map && label['name'] is String) label['name'] as String,
  ];
  if (isCoreReleasePrep(
    labels: labels,
    headRef: headRef,
    headRepository: headRepository is String ? headRepository : '',
    repository: repository,
  )) {
    log?.call('Release-prep PR: released changelog sections may change.');
    return const [];
  }

  final mergeBase = _git(repoRoot, ['merge-base', 'HEAD', 'origin/$baseRef']);
  if (mergeBase == null) {
    throw StateError(
      'Could not find the merge base of HEAD and origin/$baseRef. Check out '
      'with `fetch-depth: 0`, or run `git fetch origin $baseRef`, so the base '
      'branch and its history are available.',
    );
  }
  String? baseFile(String path) {
    if (_git(repoRoot, ['cat-file', '-e', '$mergeBase:$path']) == null) {
      return null;
    }
    final contents = _git(repoRoot, ['show', '$mergeBase:$path']);
    if (contents == null) {
      throw StateError('Could not read $path at merge base $mergeBase.');
    }
    return contents;
  }

  String? headFile(String path) {
    final file = File('${repoRoot.path}/$path');
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  final problems = <String>[];
  for (final path in releasedChangelogs) {
    final baseContents = baseFile(path);
    if (baseContents == null) {
      throw StateError('Could not read $path at merge base $mergeBase.');
    }
    final headContents = headFile(path);
    if (headContents == null) {
      problems.add('$path is missing; released sections cannot be removed.');
      continue;
    }
    final archivePath = changelogArchives[path];
    final change = archivePath == null
        ? releasedSectionChange(path, baseContents, headContents)
        : archivedSectionChange(
            path,
            archivePath,
            base: baseContents,
            head: headContents,
            baseArchive: baseFile(archivePath),
            headArchive: headFile(archivePath),
          );
    if (change != null) problems.add(change);
  }
  return problems;
}

String? _git(Directory repoRoot, List<String> arguments) {
  final result = Process.runSync(
    'git',
    arguments,
    workingDirectory: repoRoot.path,
    stdoutEncoding: utf8,
  );
  if (result.exitCode != 0) return null;
  final output = result.stdout as String;
  return arguments.first == 'show' ? output : output.trim();
}

void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    stderr.writeln(
      'Usage: dart run tool/testing/check_released_changelog_sections.dart',
    );
    exitCode = 64;
    return;
  }
  final environment = Platform.environment;
  if (environment['GITHUB_EVENT_NAME'] != 'pull_request') {
    stdout.writeln(
      'Not a pull_request event; released changelog sections not checked.',
    );
    return;
  }
  final eventPath = environment['GITHUB_EVENT_PATH'];
  final repository = environment['GITHUB_REPOSITORY'];
  try {
    if (eventPath == null || repository == null) {
      throw StateError(
        'GITHUB_EVENT_PATH and GITHUB_REPOSITORY must be set for a '
        'pull_request check.',
      );
    }
    final event = jsonDecode(File(eventPath).readAsStringSync());
    if (event is! Map<String, Object?>) {
      throw StateError('The event payload is not a JSON object.');
    }
    final problems = checkReleasedChangelogSections(
      Directory.current,
      event,
      repository: repository,
      log: stdout.writeln,
    );
    if (problems.isNotEmpty) {
      stderr.writeln('Released changelog sections changed:');
      for (final problem in problems) {
        stderr.writeln('- $problem');
      }
      exitCode = 1;
      return;
    }
    stdout.writeln('Released changelog sections match the base.');
  } on StateError catch (error) {
    stderr.writeln(
      'Cannot check released changelog sections: ${error.message}',
    );
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln('Cannot check released changelog sections: $error');
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('Cannot check released changelog sections: $error');
    exitCode = 1;
  }
}
