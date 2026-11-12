#!/usr/bin/env dart

/// Puts an empty `## Unreleased` heading back at the top of the core
/// changelogs after a core release.
///
/// `docs_version_cut.yml` runs it on `main` after each core release tag, so
/// feature PRs only add bullets under an existing heading instead of each
/// adding the heading and conflicting with one another. Release prep moves the
/// bullets into `## X.Y.Z` and removes the heading again.
///
/// It inserts only before the first level-two heading and leaves every
/// released section byte-for-byte unchanged. It uses only `dart:io`, so the
/// workflow runs it as `dart tool/release/reopen_unreleased_changelog.dart`
/// without resolving packages or running the core build hook.
library;

import 'dart:io';

/// Core changelogs that carry the shared `## Unreleased` section.
const unreleasedChangelogs = <String>[
  'CHANGELOG.md',
  'website/docs/changelog/recent-releases.md',
];

const _unreleasedHeading = '## Unreleased';

/// [contents] with `## Unreleased` as its first level-two heading.
///
/// Returns [contents] unchanged when that heading is already first. Throws
/// [FormatException] when there is no level-two heading, or when
/// `## Unreleased` sits below a released section, rather than adding a second
/// one.
String reopenUnreleased(String contents) {
  final headings = RegExp(
    r'^## (.*)$',
    multiLine: true,
  ).allMatches(contents).toList();
  if (headings.isEmpty) {
    throw const FormatException('no `## ` release heading to insert above');
  }
  bool isUnreleased(RegExpMatch heading) =>
      heading.group(1)!.trim() == 'Unreleased';
  if (isUnreleased(headings.first)) return contents;
  if (headings.any(isUnreleased)) {
    throw const FormatException(
      '`## Unreleased` is not the first release heading',
    );
  }
  final start = headings.first.start;
  return '${contents.substring(0, start)}$_unreleasedHeading\n\n'
      '${contents.substring(start)}';
}

/// Rewrites each of [unreleasedChangelogs] under [repoRoot] and returns the
/// paths it changed. Validates every file before writing any.
List<String> reopenUnreleasedChangelogs(Directory repoRoot) {
  final updates = <String, String>{};
  for (final path in unreleasedChangelogs) {
    final file = File('${repoRoot.path}/$path');
    final String contents;
    final String reopened;
    try {
      contents = file.readAsStringSync();
      reopened = reopenUnreleased(contents);
    } on FormatException catch (error) {
      throw FormatException('$path: ${error.message}');
    }
    if (reopened != contents) updates[path] = reopened;
  }
  for (final entry in updates.entries) {
    File('${repoRoot.path}/${entry.key}').writeAsStringSync(entry.value);
  }
  return updates.keys.toList();
}

void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart tool/release/reopen_unreleased_changelog.dart');
    exitCode = 64;
    return;
  }
  try {
    final changed = reopenUnreleasedChangelogs(Directory.current);
    stdout.writeln(
      changed.isEmpty
          ? 'Changelogs already start with $_unreleasedHeading.'
          : 'Added $_unreleasedHeading to ${changed.join(', ')}.',
    );
  } on FileSystemException catch (error) {
    stderr.writeln('Could not reopen $_unreleasedHeading: $error');
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('Could not reopen $_unreleasedHeading: ${error.message}');
    exitCode = 1;
  }
}
