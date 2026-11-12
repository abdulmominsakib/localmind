/// Checks the files pub.dev renders from a package archive against the size
/// pub.dev accepts.
///
/// pub.dev rejects an upload whose README, CHANGELOG, LICENSE or displayed
/// example file is larger than [pubContentLimitBytes], or whose `pubspec.yaml`
/// is larger than [pubPubspecLimitBytes], after the release tag is pushed.
/// `verify_release_docs_versions.dart` runs this check in PR CI and before
/// release automation pushes any tag.
library;

import 'dart:io';

/// The byte limit pub.dev applies to each rendered content file
/// (`maxContentLength` in pub-dev's `pub_package_reader`).
const int pubContentLimitBytes = 256 * 1024;

/// The byte limit pub.dev applies to `pubspec.yaml` (`maxPubspecLength` in
/// pub-dev's `pub_package_reader`).
const int pubPubspecLimitBytes = 128 * 1024;

/// Content files larger than this are reported as close to the limit.
const int pubContentWarningBytes = pubContentLimitBytes * 9 ~/ 10;

/// The content files of package [name] at [packagePath], relative to the
/// repository root, that pub.dev reads: `README.md`, `CHANGELOG.md`, `LICENSE`
/// and the first example file its Example tab would show.
///
/// Candidates are chosen by existence on disk. `.pubignore` is not consulted
/// (it is gitignore syntax, and no candidate is ignored today), so a
/// pub-ignored higher-priority example would make this check size that file
/// and skip the lower-priority one pub.dev actually shows.
List<String> pubContentFiles(
  Directory repoRoot,
  String packagePath,
  String name,
) {
  String path(String file) => packagePath == '.' ? file : '$packagePath/$file';
  bool exists(String file) =>
      File('${repoRoot.path}/${path(file)}').existsSync();
  // pub-dev's `exampleFileCandidates`, in its priority order.
  final example = <String>[
    'example/example.md',
    'example/lib/main.dart',
    'example/main.dart',
    'example/lib/$name.dart',
    'example/$name.dart',
    'example/lib/${name}_example.dart',
    'example/${name}_example.dart',
    'example/lib/example.dart',
    'example/example.dart',
    'example/README.md',
  ].where(exists).firstOrNull;
  return [
    for (final file in ['README.md', 'CHANGELOG.md', 'LICENSE', ?example])
      if (exists(file)) path(file),
  ];
}

/// Size problems in the content files of [packages], a map from package name
/// to its directory relative to [repoRoot]. Content files over
/// [pubContentLimitBytes] and a `pubspec.yaml` over [pubPubspecLimitBytes] are
/// errors; files over 90% of their limit are warnings.
({List<String> errors, List<String> warnings}) checkPubContentLimits(
  Directory repoRoot,
  Map<String, String> packages,
) {
  final errors = <String>[];
  final warnings = <String>[];
  for (final MapEntry(key: name, value: packagePath) in packages.entries) {
    final pubspec = packagePath == '.'
        ? 'pubspec.yaml'
        : '$packagePath/pubspec.yaml';
    final files = <String, int>{
      for (final path in pubContentFiles(repoRoot, packagePath, name))
        path: pubContentLimitBytes,
      if (File('${repoRoot.path}/$pubspec').existsSync())
        pubspec: pubPubspecLimitBytes,
    };
    for (final MapEntry(key: path, value: limit) in files.entries) {
      final size = File('${repoRoot.path}/$path').lengthSync();
      if (size > limit) {
        errors.add(
          '$path is $size bytes; pub.dev rejects $name when it exceeds '
          '$limit bytes. Shorten it before publishing${_shortenHint(path)}.',
        );
      } else if (size > limit * 9 ~/ 10) {
        warnings.add(
          '$path is $size bytes, within 10% of the $limit-byte '
          'limit pub.dev applies when publishing $name.',
        );
      }
    }
  }
  return (errors: errors, warnings: warnings);
}

String _shortenHint(String path) => path.endsWith('pubspec.yaml')
    ? ''
    : ' (the core CHANGELOG.md moves its oldest releases, verbatim, to '
          'doc/changelog_archive.md)';
