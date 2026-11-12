// Fails when a runtime archive digest in lib/src/hook/native_release_pins.dart
// differs from what its pinned release publishes, so a manual pin edit cannot
// ship digests every consumer build would reject:
//
// - `llamaCppBundleSha256` and `llamaCppBackendSidecarSpecs` against the
//   `llamaCppTag` release's `SHA256SUMS`;
// - `stableDiffusionBundleSpecs` against the `stableDiffusionReleaseTag`
//   release's `SHA256SUMS`;
// - `liteRtLmBundleSpecs` against the GitHub asset digests of the
//   `liteRtLmReleaseTag` release, whose `SHA256SUMS` lists only the
//   extracted libraries, not the runtime archives.
//
// Network-dependent: CI runs it only when the pin file changes. Pass a local
// copy of any source to check against it instead (see the usage message).
// `GH_TOKEN` or `GITHUB_TOKEN`, when set, authenticates the GitHub API call.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/hook/native_archive_digest.dart';
import 'package:llamadart/src/hook/native_release_pins.dart';

/// GitHub repository that publishes the pinned llama.cpp runtime archives.
const String nativeReleaseRepository = 'leehack/llamadart-native';

/// GitHub repository that publishes the pinned LiteRT-LM runtime archives.
const String liteRtLmReleaseRepository = 'leehack/litert-lm-native';

/// GitHub repository that publishes the pinned stable_diffusion runtime
/// archives.
const String stableDiffusionReleaseRepository =
    'leehack/stable-diffusion-native';

/// Largest `SHA256SUMS` body the check reads.
const int maxSha256SumsBytes = 64 * 1024;

/// Largest GitHub release API body the check reads.
const int maxGitHubReleaseBytes = 1024 * 1024;

final _githubSha256Digest = RegExp(r'^sha256:[0-9a-f]{64}$');

/// Returns one problem per pinned bundle whose digest is missing from, or
/// differs from, [checksumText] for release [tag].
///
/// Bundle archives are named `<archivePrefix>-<bundle>-<tag>.tar.gz`.
List<String> nativeReleaseDigestProblems({
  required String tag,
  required Map<String, String> pins,
  required String checksumText,
  String source = 'SHA256SUMS',
  String archivePrefix = 'llamadart-native',
}) {
  final problems = <String>[];
  for (final MapEntry(key: bundle, value: pinned) in pins.entries) {
    final archive = '$archivePrefix-$bundle-$tag.tar.gz';
    final String? published;
    try {
      published = sha256SumsEntry(
        checksumText,
        fileName: archive,
        source: source,
      );
    } on NativeArchiveDigestException catch (error) {
      return <String>[error.message];
    }
    final problem = _digestProblem(bundle, pinned, archive, published, source);
    if (problem != null) {
      problems.add(problem);
    }
  }
  return problems;
}

/// Returns one problem per pinned bundle whose archive is missing from, lacks
/// a SHA-256 digest in, or has a different digest in [releaseJson], a GitHub
/// release API response for release [tag].
///
/// Bundle archives are named `<archivePrefix>-<bundle>-<tag>.tar.gz`.
List<String> releaseAssetDigestProblems({
  required String tag,
  required Map<String, String> pins,
  required String releaseJson,
  required String archivePrefix,
  String source = 'release assets',
}) {
  final Map<String, Object?> digests;
  try {
    digests = _releaseAssetDigests(releaseJson);
  } on FormatException catch (error) {
    return <String>['$source is not a GitHub release: ${error.message}'];
  }
  final problems = <String>[];
  for (final MapEntry(key: bundle, value: pinned) in pins.entries) {
    final archive = '$archivePrefix-$bundle-$tag.tar.gz';
    final digest = digests[archive];
    final String? problem;
    if (!digests.containsKey(archive)) {
      problem = _digestProblem(bundle, pinned, archive, null, source);
    } else if (digest is String && _githubSha256Digest.hasMatch(digest)) {
      problem = _digestProblem(
        bundle,
        pinned,
        archive,
        digest.substring('sha256:'.length),
        source,
      );
    } else {
      problem = '$source has no SHA-256 digest for $archive';
    }
    if (problem != null) {
      problems.add(problem);
    }
  }
  return problems;
}

Map<String, Object?> _releaseAssetDigests(String releaseJson) {
  final release = jsonDecode(releaseJson);
  final assets = release is Map<String, Object?> ? release['assets'] : null;
  if (assets is! List<Object?>) {
    throw const FormatException('no assets list');
  }
  final digests = <String, Object?>{};
  for (final asset in assets) {
    if (asset is! Map<String, Object?> || asset['name'] is! String) {
      throw const FormatException('an asset has no name');
    }
    digests[asset['name']! as String] = asset['digest'];
  }
  return digests;
}

String? _digestProblem(
  String bundle,
  String pinned,
  String archive,
  String? published,
  String source,
) {
  if (published == null) {
    return '$source lists no $archive';
  }
  if (published != pinned) {
    return '$bundle pins $pinned, but $source lists $published for $archive';
  }
  return null;
}

/// Downloads the `SHA256SUMS` body at [url], rejecting a non-200 status or a
/// body over [maxSha256SumsBytes].
Future<String> fetchSha256Sums(
  Uri url, {
  Duration timeout = const Duration(seconds: 30),
}) => _fetchText(url, maxBytes: maxSha256SumsBytes, timeout: timeout);

/// Downloads the GitHub release API body at [url], rejecting a non-200 status
/// (redirects included, so [token] never follows one) or a body over
/// [maxGitHubReleaseBytes].
///
/// [token], when given, is sent only as the `Authorization` header.
Future<String> fetchGitHubRelease(
  Uri url, {
  String? token,
  Duration timeout = const Duration(seconds: 30),
}) => _fetchText(
  url,
  maxBytes: maxGitHubReleaseBytes,
  timeout: timeout,
  followRedirects: false,
  headers: {
    HttpHeaders.acceptHeader: 'application/vnd.github+json',
    if (token != null && token.isNotEmpty)
      HttpHeaders.authorizationHeader: 'Bearer $token',
  },
);

Future<String> _fetchText(
  Uri url, {
  required int maxBytes,
  required Duration timeout,
  bool followRedirects = true,
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url).timeout(timeout);
    request.followRedirects = followRedirects;
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) {
        throw HttpException('body exceeds $maxBytes bytes', uri: url);
      }
    }
    return utf8.decode(bytes);
  } finally {
    client.close(force: true);
  }
}

enum _SourceKind { sha256Sums, githubRelease }

final class _DigestCheck {
  const _DigestCheck({
    required this.pinName,
    required this.flag,
    required this.repository,
    required this.tag,
    required this.pins,
    required this.archivePrefix,
    required this.kind,
  });

  final String pinName;
  final String flag;
  final String repository;
  final String tag;
  final Map<String, String> pins;
  final String archivePrefix;
  final _SourceKind kind;

  String get sourceName => switch (kind) {
    _SourceKind.sha256Sums => 'SHA256SUMS',
    _SourceKind.githubRelease => 'release asset digests',
  };

  Uri get url => switch (kind) {
    _SourceKind.sha256Sums => Uri.parse(
      'https://github.com/$repository/releases/download/$tag/SHA256SUMS',
    ),
    _SourceKind.githubRelease => Uri.parse(
      'https://api.github.com/repos/$repository/releases/tags/$tag',
    ),
  };

  List<String> problems(String text, String source) => switch (kind) {
    _SourceKind.sha256Sums => nativeReleaseDigestProblems(
      tag: tag,
      pins: pins,
      checksumText: text,
      source: source,
      archivePrefix: archivePrefix,
    ),
    _SourceKind.githubRelease => releaseAssetDigestProblems(
      tag: tag,
      pins: pins,
      releaseJson: text,
      archivePrefix: archivePrefix,
      source: source,
    ),
  };
}

final List<_DigestCheck> _checks = [
  _DigestCheck(
    pinName: 'llamaCppBundleSha256',
    flag: '--llama-cpp-sums',
    repository: nativeReleaseRepository,
    tag: llamaCppTag,
    pins: {
      ...llamaCppBundleSha256,
      for (final spec in llamaCppBackendSidecarSpecs) spec.archive: spec.sha256,
    },
    archivePrefix: 'llamadart-native',
    kind: _SourceKind.sha256Sums,
  ),
  _DigestCheck(
    pinName: 'stableDiffusionBundleSpecs',
    flag: '--stable-diffusion-sums',
    repository: stableDiffusionReleaseRepository,
    tag: stableDiffusionReleaseTag,
    pins: {
      for (final spec in stableDiffusionBundleSpecs) spec.bundle: spec.sha256,
    },
    archivePrefix: 'stable-diffusion-native-runtime',
    kind: _SourceKind.sha256Sums,
  ),
  _DigestCheck(
    pinName: 'liteRtLmBundleSpecs',
    flag: '--litert-lm-release',
    repository: liteRtLmReleaseRepository,
    tag: liteRtLmReleaseTag,
    pins: {for (final spec in liteRtLmBundleSpecs) spec.bundle: spec.sha256},
    archivePrefix: 'litert-lm-native-runtime',
    kind: _SourceKind.githubRelease,
  ),
];

Map<String, String>? _parseLocalSources(List<String> args) {
  final flags = {for (final check in _checks) check.flag};
  final paths = <String, String>{};
  for (var index = 0; index < args.length; index += 2) {
    final flag = args[index];
    if (!flags.contains(flag) ||
        index + 1 >= args.length ||
        paths.containsKey(flag)) {
      return null;
    }
    paths[flag] = args[index + 1];
  }
  return paths;
}

/// Runs the check and returns its exit code, writing to [out] and [err]
/// (stdout and stderr by default).
///
/// [fetch] replaces every network read; it receives the GitHub API token,
/// the first non-empty `GH_TOKEN` or `GITHUB_TOKEN` in [environment] (the
/// process environment by default), for the GitHub API read only.
///
/// Tests call this in-process: a child `dart run` re-bundles native assets
/// that the test VM holds open, which Windows refuses to overwrite.
Future<int> run(
  List<String> args, {
  StringSink? out,
  StringSink? err,
  Future<String> Function(Uri url, {String? token})? fetch,
  Map<String, String>? environment,
}) async {
  out ??= stdout;
  err ??= stderr;
  final localSources = _parseLocalSources(args);
  if (localSources == null) {
    err.writeln(
      'Usage: dart run tool/testing/check_native_release_digests.dart '
      '${_checks.map((check) => '[${check.flag} <path>]').join(' ')}',
    );
    return 64;
  }
  environment ??= Platform.environment;
  final token = [environment['GH_TOKEN'], environment['GITHUB_TOKEN']]
      .firstWhere(
        (value) => value != null && value.isNotEmpty,
        orElse: () => null,
      );
  var readFailed = false;
  var mismatched = false;
  for (final check in _checks) {
    final label = '${check.repository} ${check.tag} ${check.sourceName}';
    final localPath = localSources[check.flag];
    final String text;
    final String source;
    try {
      if (localPath != null) {
        source = localPath;
        text = File(localPath).readAsStringSync();
      } else {
        final url = check.url;
        source = url.toString();
        text = await switch (check.kind) {
          _SourceKind.sha256Sums => fetch?.call(url) ?? fetchSha256Sums(url),
          _SourceKind.githubRelease =>
            fetch?.call(url, token: token) ??
                fetchGitHubRelease(url, token: token),
        };
      }
    } on Exception catch (error) {
      err.writeln('Could not read $label: $error');
      readFailed = true;
      continue;
    }
    final problems = check.problems(text, source);
    if (problems.isEmpty) {
      out.writeln(
        '${check.pinName} matches ${check.tag} ${check.sourceName} '
        '(${check.pins.length} bundles).',
      );
      continue;
    }
    mismatched = true;
    err
      ..writeln(
        '${check.pinName} does not match ${check.tag} ${check.sourceName}:',
      )
      ..writeAll(problems.map((problem) => '  $problem\n'));
  }
  if (mismatched) {
    err.writeln(
      'Regenerate the pins with tool/native/sync_native_release_pins.py '
      'instead of editing them.',
    );
  }
  return readFailed || mismatched ? 1 : 0;
}

Future<void> main(List<String> args) async {
  exitCode = await run(args);
}
