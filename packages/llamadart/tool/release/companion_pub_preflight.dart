#!/usr/bin/env dart

/// Fails a release before any tag is pushed when a Flutter Apple companion
/// package does not exist on pub.dev yet, or when its checked-out version is
/// already published with different constraints or publishable contents.
///
/// `release_on_prep_merge.yml` publishes the core first, then pushes a
/// `<package>-v<version>` tag for every companion version missing from
/// pub.dev. Pub.dev automated publishing cannot create a package: the tag's
/// publish job would fail after the core already shipped, so the owner
/// publishes a package's first version by hand instead. The workflow also
/// skips a companion version that is already published, so a constraint
/// changed without a version bump would never reach pub.dev.
///
/// ```bash
/// dart run tool/release/companion_pub_preflight.dart
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import '../testing/verify_release_docs_versions.dart';
import 'companion_package_contents.dart';

/// A Flutter Apple SwiftPM companion package checked out under `packages/`.
typedef CompanionPackage = ({String name, String path});

/// Every Flutter Apple companion package under [repoRoot]: a `packages/<name>`
/// directory with a `darwin/<name>/Package.swift` manifest, sorted by name.
List<CompanionPackage> discoverAppleCompanionPackages(Directory repoRoot) {
  final packages = Directory('${repoRoot.path}/packages');
  if (!packages.existsSync()) return const [];
  return [
    for (final directory in packages.listSync().whereType<Directory>())
      if (File(
        '${directory.path}/darwin/${_baseName(directory.path)}/Package.swift',
      ).existsSync())
        (
          name: _baseName(directory.path),
          path: 'packages/${_baseName(directory.path)}',
        ),
  ]..sort((a, b) => a.name.compareTo(b.name));
}

/// The pub.dev endpoint that answers 200 once [package] exists.
Uri pubDevPackageUri(String package) =>
    Uri.https('pub.dev', '/api/packages/$package');

/// Problems that must stop the release before any tag is pushed: one per
/// companion missing from pub.dev, with the owner's first-publish steps, or
/// one per companion whose presence could not be confirmed. [statusOf]
/// returns the HTTP status of a GET, or throws when the request fails.
Future<List<String>> companionPubPreflightProblems(
  List<CompanionPackage> companions,
  Future<int> Function(Uri uri) statusOf,
) async {
  final problems = <String>[];
  for (final companion in companions) {
    final uri = pubDevPackageUri(companion.name);
    final int status;
    try {
      status = await statusOf(uri);
    } on Object catch (error) {
      problems.add(
        'Could not confirm ${companion.name} exists on pub.dev ($uri): '
        '$error. No release tags were pushed; retry once pub.dev answers.',
      );
      continue;
    }
    if (status == HttpStatus.ok) continue;
    if (status == HttpStatus.notFound) {
      problems.add(firstPublishInstructions(companion));
      continue;
    }
    problems.add(
      'Could not confirm ${companion.name} exists on pub.dev: $uri answered '
      'HTTP $status. No release tags were pushed; retry once pub.dev answers '
      '200.',
    );
  }
  return problems;
}

/// What the owner must do before automation can publish [companion].
String firstPublishInstructions(CompanionPackage companion) {
  final name = companion.name;
  return '''
$name does not exist on pub.dev yet, and pub.dev automated publishing cannot
create a package, so no release tags were pushed. Before rerunning this
release, the package owner must:
  1. Publish the first version by hand from a temporary copy of ${companion.path}:
       tmp_package="\$(mktemp -d)"
       rsync -a --delete --exclude='.dart_tool' --exclude='build' \\
         --exclude='pubspec.lock' --exclude='pubspec_overrides.yaml' \\
         ${companion.path}/ "\$tmp_package/"
       (cd "\$tmp_package" && flutter pub publish)
     Its `llamadart` constraint must resolve on pub.dev, so a companion can
     first publish only against a core minor that is already released.
  2. On https://pub.dev/packages/$name/admin, transfer the package to the
     leehack.com publisher.
  3. On the same page, enable automated publishing from GitHub Actions for
     repository leehack/llamadart with tag pattern $name-v{{version}}.''';
}

/// The pub.dev endpoint describing [version] of [package], including the
/// pubspec it was published with.
Uri pubDevVersionUri(String package, String version) =>
    Uri.https('pub.dev', '/api/packages/$package/versions/$version');

/// A response body and status from pub.dev.
typedef PubDevResponse = ({int status, String body});

/// Problems that must stop the release before any tag is pushed: one per
/// companion whose checked-out version is already on pub.dev with a
/// different `llamadart` constraint, or whose published pubspec could not be
/// confirmed. [get] fetches a URL, or throws when the request fails.
///
/// Release automation skips a companion version that is already published,
/// so the core would ship beside the published constraint, not the checked
/// out one.
Future<List<String>> companionPublishedConstraintProblems(
  Directory repoRoot,
  List<CompanionPackage> companions,
  Future<PubDevResponse> Function(Uri uri) get,
) async {
  final problems = <String>[];
  for (final companion in companions) {
    final pubspecPath = '${companion.path}/pubspec.yaml';
    final String source;
    try {
      source = File('${repoRoot.path}/$pubspecPath').readAsStringSync();
    } on FileSystemException catch (error) {
      problems.add('Could not read $pubspecPath: ${error.message}.');
      continue;
    }
    final version = _pubspecVersion(source);
    if (version == null) {
      problems.add('$pubspecPath does not declare a version.');
      continue;
    }
    final local = companionCoreConstraint(source).constraint;
    final uri = pubDevVersionUri(companion.name, version);
    final PubDevResponse response;
    try {
      response = await get(uri);
    } on Object catch (error) {
      problems.add(
        'Could not confirm whether ${companion.name} $version is on pub.dev '
        '($uri): $error. No release tags were pushed; retry once pub.dev '
        'answers.',
      );
      continue;
    }
    if (response.status == HttpStatus.notFound) continue;
    if (response.status != HttpStatus.ok) {
      problems.add(
        'Could not confirm whether ${companion.name} $version is on pub.dev: '
        '$uri answered HTTP ${response.status}. No release tags were pushed; '
        'retry once pub.dev answers.',
      );
      continue;
    }
    final Object? published;
    try {
      published = _publishedCoreConstraint(response.body);
    } on FormatException catch (error) {
      problems.add(
        '$uri did not describe the published ${companion.name} $version '
        'pubspec: ${error.message}. No release tags were pushed.',
      );
      continue;
    }
    if (_sameConstraint(local, published)) continue;
    problems.add(
      '${companion.name} $version is already on pub.dev with '
      '`llamadart: ${published ?? '<none>'}`, but $pubspecPath declares '
      '`llamadart: ${local ?? '<none>'}`. Release automation skips a '
      'published version, so bump ${companion.name} past $version in the '
      'release-prep PR. No release tags were pushed.',
    );
  }
  return problems;
}

/// Canonical immutable archive for one published companion version.
Uri pubDevArchiveUri(String package, String version) =>
    Uri.https('pub.dev', '/api/archives/$package-$version.tar.gz');

/// Rejects changed publishable contents at a version automation would skip.
/// The same-version archive is checksum-bound to pub.dev's version response.
Future<List<String>> companionPublishedContentProblems(
  Directory repoRoot,
  List<CompanionPackage> companions,
  Future<PubDevResponse> Function(Uri uri) get, {
  Future<List<int>> Function(Uri uri) getArchive = pubDevArchiveGet,
}) async {
  final problems = <String>[];
  for (final companion in companions) {
    String? version;
    try {
      final package = Directory('${repoRoot.path}/${companion.path}');
      version = _pubspecVersion(
        File('${package.path}/pubspec.yaml').readAsStringSync(),
      );
      if (version == null) throw const FormatException('Missing version.');
      final response = await get(pubDevVersionUri(companion.name, version));
      if (response.status == HttpStatus.notFound) continue;
      if (response.status != HttpStatus.ok) {
        throw const FormatException('Published version unavailable.');
      }
      final metadata = jsonDecode(response.body);
      final archiveUri = pubDevArchiveUri(companion.name, version);
      if (metadata is! Map ||
          metadata['version'] != version ||
          metadata['pubspec'] is! Map ||
          metadata['pubspec']['name'] != companion.name ||
          metadata['pubspec']['version'] != version ||
          metadata['archive_url'] != '$archiveUri' ||
          metadata['archive_sha256'] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(metadata['archive_sha256'])) {
        throw const FormatException('Invalid published archive identity.');
      }
      final archive = await getArchive(archiveUri);
      if (sha256.convert(archive).toString() != metadata['archive_sha256']) {
        throw const FormatException('Published archive checksum mismatch.');
      }
      final published = publishedCompanionContents(archive);
      final candidate = await candidateCompanionContents(package);
      if (candidate.length != published.length ||
          candidate.entries.any(
            (entry) => published[entry.key] != entry.value,
          )) {
        problems.add(
          '${companion.name} $version is already on pub.dev, but its '
          'publishable contents changed. Bump ${companion.name} past $version '
          'in the release-prep PR. No release tags were pushed.',
        );
      }
    } on Object {
      // Network/parser/process errors can contain credentials or local paths.
      problems.add(
        'Could not verify published contents of ${companion.name} '
        '${version ?? '(missing version)'}. No release tags were pushed.',
      );
    }
  }
  return problems;
}

/// Downloads only a canonical pub.dev archive, with bounded response size.
Future<List<int>> pubDevArchiveGet(Uri uri) async {
  if (uri.scheme != 'https' ||
      uri.host != 'pub.dev' ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !RegExp(
        r'^/api/archives/[a-z0-9_]+-[0-9A-Za-z.+-]+\.tar\.gz$',
      ).hasMatch(uri.path)) {
    throw const FormatException('Not a canonical pub.dev archive URL.');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 60));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Published archive unavailable.');
    }
    return await response
        .fold<List<int>>(<int>[], (bytes, chunk) {
          if (bytes.length + chunk.length > 100 * 1024 * 1024) {
            throw const FormatException('Published archive exceeds 100 MiB.');
          }
          return bytes..addAll(chunk);
        })
        .timeout(const Duration(seconds: 60));
  } finally {
    client.close(force: true);
  }
}

String? _pubspecVersion(String source) {
  try {
    final pubspec = loadYaml(source);
    final version = pubspec is YamlMap ? pubspec['version'] : null;
    return version is String ? version : null;
  } on YamlException {
    return null;
  }
}

/// The `llamadart` dependency in a pub.dev version response [body]: a
/// constraint string, another source description, or `null` for none.
Object? _publishedCoreConstraint(String body) {
  final decoded = jsonDecode(body);
  final pubspec = decoded is Map ? decoded['pubspec'] : null;
  if (pubspec is! Map) {
    throw const FormatException('the response has no pubspec');
  }
  final dependencies = pubspec['dependencies'];
  return dependencies is Map ? dependencies['llamadart'] : null;
}

bool _sameConstraint(String? local, Object? published) {
  if (local == null || published == null) return local == published;
  if (published is! String) return false;
  try {
    return VersionConstraint.parse(local) == VersionConstraint.parse(published);
  } on FormatException {
    return false;
  }
}

/// Fetches [uri], failing when the connection takes over 30 seconds, or the
/// response headers or [bodyTimeout] pass first.
Future<PubDevResponse> pubDevGet(
  Uri uri, {
  Duration bodyTimeout = const Duration(seconds: 60),
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 60));
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(bodyTimeout);
    return (status: response.statusCode, body: body);
  } finally {
    client.close(force: true);
  }
}

/// Calls [get] for [uri], and once more after [retryDelay] when it throws an
/// [Exception], such as a stalled body's [TimeoutException], or pub.dev
/// answers a 5xx status.
Future<PubDevResponse> getWithOneRetry(
  Uri uri,
  Future<PubDevResponse> Function(Uri uri) get, {
  Duration retryDelay = const Duration(seconds: 5),
}) async {
  try {
    final response = await get(uri);
    if (response.status < HttpStatus.internalServerError) return response;
  } on Exception {
    // Retried below; a second failure reaches the caller.
  }
  await Future<void>.delayed(retryDelay);
  return get(uri);
}

/// Runs all preflight checks on the companions under [repoRoot], fetching
/// pub.dev through [get], reports to [out] or [err], and returns the exit
/// code: `0` only when no problem stops the release.
Future<int> runCompanionPubPreflight(
  Directory repoRoot,
  Future<PubDevResponse> Function(Uri uri) get, {
  required StringSink out,
  required StringSink err,
  Future<List<int>> Function(Uri uri) getArchive = pubDevArchiveGet,
}) async {
  final companions = discoverAppleCompanionPackages(repoRoot);
  if (companions.isEmpty) {
    err.writeln('No Flutter Apple companion packages found under packages/.');
    return 1;
  }
  // A version response must not change between the constraint and payload
  // checks, particularly from an existing version to a transient 404.
  final responses = <Uri, Future<PubDevResponse>>{};
  Future<PubDevResponse> cachedGet(Uri uri) =>
      responses.putIfAbsent(uri, () => get(uri));
  final problems = [
    ...await companionPubPreflightProblems(
      companions,
      (uri) async => (await cachedGet(uri)).status,
    ),
    ...await companionPublishedConstraintProblems(
      repoRoot,
      companions,
      cachedGet,
    ),
    ...await companionPublishedContentProblems(
      repoRoot,
      companions,
      cachedGet,
      getArchive: getArchive,
    ),
  ];
  if (problems.isNotEmpty) {
    err.writeln('Companion pub.dev preflight failed:');
    problems.forEach(err.writeln);
    return 1;
  }
  out.writeln(
    'Companion packages exist on pub.dev, and no published companion '
    'version changes its constraint or publishable contents: '
    '${companions.map((companion) => companion.name).join(', ')}.',
  );
  return 0;
}

String _baseName(String path) =>
    path.split(RegExp(r'[/\\]')).where((part) => part.isNotEmpty).last;

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/release/companion_pub_preflight.dart');
    exitCode = 64;
    return;
  }
  exitCode = await runCompanionPubPreflight(
    Directory.current,
    (uri) => getWithOneRetry(uri, pubDevGet),
    out: stdout,
    err: stderr,
  );
}
