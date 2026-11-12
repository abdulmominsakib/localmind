import 'dart:convert';
import 'dart:io';

import 'package:coverage/coverage.dart';

const _usage = '''
Usage: dart run tool/testing/format_lcov.dart --lcov --in=<dir-or-file> \\
    --out=<file|stdout> [--report-on=<path>[,<path>...]]... [--check-ignore] \\
    [--package=<dir>]

Formats Dart VM coverage JSON as LCOV. Produces the same output as
`coverage:format_coverage --lcov` for the flags above, but creates one
Resolver and one ignored-lines cache for the whole run instead of one per
input file. Every other `format_coverage` flag and short alias is rejected;
`coverage_options.yaml` is ignored.''';

/// Parsed command line for the LCOV formatter.
class FormatLcovOptions {
  /// Creates options directly, bypassing command-line parsing.
  FormatLcovOptions({
    required this.input,
    required this.output,
    required this.reportOn,
    required this.checkIgnore,
    this.packagePath = '.',
  });

  /// Coverage JSON file, or directory searched recursively for `.json` files.
  final String input;

  /// Destination LCOV file, or `null` for stdout.
  final String? output;

  /// Paths coverage is reported on, or `null` to report on everything.
  final List<String>? reportOn;

  /// Whether `// coverage:ignore-*` comments are honoured.
  final bool checkIgnore;

  /// Root directory of the package whose `package:` URIs are resolved.
  final String packagePath;
}

/// Thrown for a malformed or unsupported command line.
class FormatLcovUsageException implements Exception {
  /// Creates an exception describing [message].
  FormatLcovUsageException(this.message);

  /// Human-readable reason the command line was rejected.
  final String message;

  @override
  String toString() => message;
}

/// Parses [args], accepting `--lcov`, `--in=`, `--out=`, `--report-on=`,
/// `--check-ignore` and `--package=`.
///
/// `--report-on=` may be repeated and splits its value on commas, matching the
/// `addMultiOption` `format_coverage` declares it with.
///
/// Throws [FormatLcovUsageException] for anything else, including every
/// `format_coverage` short alias, the `--pretty-print` modes and `--workers`.
FormatLcovOptions parseFormatLcovArgs(List<String> args) {
  var lcov = false;
  var checkIgnore = false;
  String? input;
  String? output;
  var packagePath = '.';
  final reportOn = <String>[];

  for (final arg in args) {
    if (arg == '--lcov') {
      lcov = true;
    } else if (arg == '--check-ignore') {
      checkIgnore = true;
    } else if (arg.startsWith('--in=')) {
      input = arg.substring('--in='.length);
    } else if (arg.startsWith('--out=')) {
      output = arg.substring('--out='.length);
    } else if (arg.startsWith('--report-on=')) {
      reportOn.addAll(arg.substring('--report-on='.length).split(','));
    } else if (arg.startsWith('--package=')) {
      packagePath = arg.substring('--package='.length);
    } else {
      throw FormatLcovUsageException('Unsupported argument: $arg');
    }
  }

  if (!lcov) {
    throw FormatLcovUsageException('--lcov is required.');
  }
  if (input == null || input.isEmpty) {
    throw FormatLcovUsageException('--in=<dir-or-file> is required.');
  }

  return FormatLcovOptions(
    input: input,
    output: output == 'stdout' ? null : output,
    reportOn: reportOn.isEmpty ? null : reportOn,
    checkIgnore: checkIgnore,
    packagePath: packagePath,
  );
}

/// Returns the coverage JSON files [input] denotes: every `.json` file under
/// [input], recursively, when it is a directory, otherwise [input] itself.
List<File> coverageJsonFiles(String input) {
  if (FileSystemEntity.isDirectorySync(input)) {
    return Directory(input)
        .listSync(recursive: true)
        .whereType<File>()
        .where((entity) => entity.path.endsWith('.json'))
        .toList();
  }
  return <File>[File(input)];
}

/// Merges every coverage JSON file [FormatLcovOptions.input] denotes into one
/// hit map and returns it in LCOV format.
///
/// One [Resolver] and one ignored-lines cache are shared across all input
/// files, so each source is read and scanned for ignore comments at most once.
///
/// Throws a [FormatException] for a `.json` input that is not a
/// `{"coverage": [...]}` report, as `format_coverage` does.
Future<String> formatLcovReport(FormatLcovOptions options) async {
  final resolver = await Resolver.create(packagePath: options.packagePath);
  final ignoredLinesInFilesCache = <String, List<List<int>>?>{};
  final globalHitmap = <String, HitMap>{};

  for (final file in coverageJsonFiles(options.input)) {
    switch (json.decode(file.readAsStringSync())) {
      case {'coverage': final List entries}:
        globalHitmap.merge(
          HitMap.parseJsonSync(
            entries.whereType<Map<String, dynamic>>().toList(),
            checkIgnoredLines: options.checkIgnore,
            ignoredLinesInFilesCache: ignoredLinesInFilesCache,
            resolver: resolver,
          ),
        );
      case final decoded:
        throw FormatException(
          'Unrecognized coverage JSON in "${file.path}". Expected a '
          '{"coverage": [...]} report, but got ${decoded.runtimeType}.',
        );
    }
  }

  return globalHitmap.formatLcov(resolver, reportOn: options.reportOn);
}

Future<void> main(List<String> args) async {
  final FormatLcovOptions options;
  try {
    options = parseFormatLcovArgs(args);
  } on FormatLcovUsageException catch (error) {
    stderr.writeln('$error\n\n$_usage');
    exitCode = 64;
    return;
  }

  if (!FileSystemEntity.isDirectorySync(options.input) &&
      !FileSystemEntity.isFileSync(options.input)) {
    stderr.writeln(
      'Input "${options.input}" is neither a directory nor a '
      'file.',
    );
    exitCode = 66;
    return;
  }

  final report = await formatLcovReport(options);
  final output = options.output;
  if (output == null) {
    stdout.write(report);
    return;
  }
  File(output)
    ..createSync(recursive: true)
    ..writeAsStringSync(report);
}
