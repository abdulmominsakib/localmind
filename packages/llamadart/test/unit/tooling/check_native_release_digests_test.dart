@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/testing/check_native_release_digests.dart';
import '../../../tool/testing/check_native_release_digests.dart'
    as check_native_release_digests;

String sums(
  Map<String, String> digests, {
  String tag = llamaCppTag,
  String prefix = 'llamadart-native',
}) => [
  for (final MapEntry(key: bundle, value: digest) in digests.entries)
    '$digest  $prefix-$bundle-$tag.tar.gz',
  '${'0' * 64}  $prefix-headers-$tag.tar.gz',
  '',
].join('\n');

String release(
  Map<String, String?> digests, {
  String tag = liteRtLmReleaseTag,
  String prefix = 'litert-lm-native-runtime',
}) => jsonEncode({
  'tag_name': tag,
  'assets': [
    for (final MapEntry(key: bundle, value: digest) in digests.entries)
      {
        'name': '$prefix-$bundle-$tag.tar.gz',
        'digest': digest == null ? null : 'sha256:$digest',
      },
    {'name': 'SHA256SUMS', 'digest': 'sha256:${'0' * 64}'},
  ],
});

final Map<String, String> llamaCppPins = {
  ...llamaCppBundleSha256,
  for (final spec in llamaCppBackendSidecarSpecs) spec.archive: spec.sha256,
};
final Map<String, String> liteRtLmPins = {
  for (final spec in liteRtLmBundleSpecs) spec.bundle: spec.sha256,
};

final Map<String, String> stableDiffusionPins = {
  for (final spec in stableDiffusionBundleSpecs) spec.bundle: spec.sha256,
};

String stableDiffusionSums(Map<String, String> digests) => sums(
  digests,
  tag: stableDiffusionReleaseTag,
  prefix: 'stable-diffusion-native-runtime',
);

void main() {
  final linux = 'a' * 64;
  final mac = 'b' * 64;
  final pinned = {'linux-x64': linux, 'macos-arm64': mac};

  group('nativeReleaseDigestProblems', () {
    test('accepts pins equal to the release SHA256SUMS', () {
      expect(
        nativeReleaseDigestProblems(
          tag: 'v1.2.3',
          pins: pinned,
          checksumText: sums(pinned, tag: 'v1.2.3'),
        ),
        isEmpty,
      );
    });

    test('reports a stale digest by bundle and archive', () {
      expect(
        nativeReleaseDigestProblems(
          tag: 'v1.2.3',
          pins: pinned,
          checksumText: sums({
            ...pinned,
            'macos-arm64': 'c' * 64,
          }, tag: 'v1.2.3'),
        ),
        [
          'macos-arm64 pins $mac, but SHA256SUMS lists ${'c' * 64} for '
              'llamadart-native-macos-arm64-v1.2.3.tar.gz',
        ],
      );
    });

    test('reports a pinned bundle the release does not list', () {
      expect(
        nativeReleaseDigestProblems(
          tag: 'v1.2.3',
          pins: pinned,
          checksumText: sums({'linux-x64': linux}, tag: 'v1.2.3'),
        ),
        ['SHA256SUMS lists no llamadart-native-macos-arm64-v1.2.3.tar.gz'],
      );
    });

    test('compares archives of the pinned tag only', () {
      expect(
        nativeReleaseDigestProblems(
          tag: 'v1.2.3',
          pins: pinned,
          checksumText: sums(pinned, tag: 'v1.2.2'),
        ),
        hasLength(2),
      );
    });

    test('compares archives with the given prefix only', () {
      final problems = nativeReleaseDigestProblems(
        tag: 'v1.2.3',
        pins: pinned,
        archivePrefix: 'stable-diffusion-native-runtime',
        checksumText: sums(pinned, tag: 'v1.2.3'),
      );
      expect(problems, [
        'SHA256SUMS lists no '
            'stable-diffusion-native-runtime-linux-x64-v1.2.3.tar.gz',
        'SHA256SUMS lists no '
            'stable-diffusion-native-runtime-macos-arm64-v1.2.3.tar.gz',
      ]);
    });

    test('rejects a malformed SHA256SUMS', () {
      expect(
        nativeReleaseDigestProblems(
          tag: 'v1.2.3',
          pins: pinned,
          checksumText: 'not a checksum line\n',
        ),
        [contains('malformed line 1')],
      );
    });
  });

  group('releaseAssetDigestProblems', () {
    List<String> problems(String releaseJson) => releaseAssetDigestProblems(
      tag: 'v1.2.3',
      pins: pinned,
      archivePrefix: 'litert-lm-native-runtime',
      releaseJson: releaseJson,
    );

    test('accepts pins equal to the release asset digests', () {
      expect(problems(release(pinned, tag: 'v1.2.3')), isEmpty);
    });

    test('reports a stale digest by bundle and archive', () {
      expect(
        problems(release({...pinned, 'linux-x64': 'c' * 64}, tag: 'v1.2.3')),
        [
          'linux-x64 pins $linux, but release assets lists ${'c' * 64} for '
              'litert-lm-native-runtime-linux-x64-v1.2.3.tar.gz',
        ],
      );
    });

    test('reports a pinned bundle the release does not publish', () {
      expect(problems(release({'linux-x64': linux}, tag: 'v1.2.3')), [
        'release assets lists no '
            'litert-lm-native-runtime-macos-arm64-v1.2.3.tar.gz',
      ]);
    });

    test('compares assets of the pinned tag only', () {
      expect(problems(release(pinned, tag: 'v1.2.2')), hasLength(2));
    });

    test('reports an asset without a SHA-256 digest', () {
      expect(problems(release({...pinned, 'linux-x64': null}, tag: 'v1.2.3')), [
        'release assets has no SHA-256 digest for '
            'litert-lm-native-runtime-linux-x64-v1.2.3.tar.gz',
      ]);
    });

    test('reports a non-SHA-256 or malformed digest', () {
      for (final Object digest in [
        'md5:${'a' * 32}',
        'sha256:${'A' * 64}',
        'sha256:${'a' * 63}',
        'xsha256:$linux',
        'sha256:${linux}a',
        7,
      ]) {
        final json = jsonEncode({
          'assets': [
            {
              'name': 'litert-lm-native-runtime-linux-x64-v1.2.3.tar.gz',
              'digest': digest,
            },
            {
              'name': 'litert-lm-native-runtime-macos-arm64-v1.2.3.tar.gz',
              'digest': 'sha256:$mac',
            },
          ],
        });
        expect(problems(json), [
          contains('has no SHA-256 digest for'),
        ], reason: '$digest');
      }
    });

    test('rejects a body that is not a GitHub release', () {
      for (final body in [
        'not json',
        '[]',
        '{}',
        '{"assets": 1}',
        '{"assets": [1]}',
        '{"assets": [{"name": 1}]}',
      ]) {
        expect(problems(body), [
          contains('release assets is not a GitHub release'),
        ], reason: body);
      }
    });
  });

  group('CLI', () {
    late Directory scratch;
    late StringBuffer out;
    late StringBuffer err;
    late Map<String, String> bodies;
    late List<Uri> fetched;
    late Map<String, String?> tokens;

    const llamaCppSumsUrl =
        'https://github.com/leehack/llamadart-native/releases/download/'
        '$llamaCppTag/SHA256SUMS';
    const stableDiffusionSumsUrl =
        'https://github.com/leehack/stable-diffusion-native/releases/download/'
        '$stableDiffusionReleaseTag/SHA256SUMS';
    const liteRtLmReleaseUrl =
        'https://api.github.com/repos/leehack/litert-lm-native/releases/tags/'
        '$liteRtLmReleaseTag';

    Future<String> fetch(Uri url, {String? token}) async {
      fetched.add(url);
      tokens['$url'] = token;
      final body = bodies['$url'];
      if (body == null) {
        throw HttpException('HTTP 404', uri: url);
      }
      return body;
    }

    Future<int> runCli([List<String> args = const []]) =>
        run(args, out: out, err: err, fetch: fetch, environment: const {});

    setUp(() {
      scratch = Directory.systemTemp.createTempSync('native-digests-');
      out = StringBuffer();
      err = StringBuffer();
      fetched = [];
      tokens = {};
      bodies = {
        llamaCppSumsUrl: sums(llamaCppPins),
        stableDiffusionSumsUrl: stableDiffusionSums(stableDiffusionPins),
        liteRtLmReleaseUrl: release(liteRtLmPins),
      };
    });

    tearDown(() => scratch.deleteSync(recursive: true));

    String write(String name, String body) =>
        (File(p.join(scratch.path, name))..writeAsStringSync(body)).path;

    test('passes for the committed pins of every runtime', () async {
      expect(await runCli(), 0, reason: '$err');
      expect(err.toString(), isEmpty);
      expect(
        out.toString(),
        allOf(
          contains('llamaCppBundleSha256 matches $llamaCppTag SHA256SUMS'),
          contains(
            'stableDiffusionBundleSpecs matches $stableDiffusionReleaseTag '
            'SHA256SUMS',
          ),
          contains(
            'liteRtLmBundleSpecs matches $liteRtLmReleaseTag release asset '
            'digests',
          ),
        ),
      );
      expect(fetched.map((url) => '$url'), [
        llamaCppSumsUrl,
        stableDiffusionSumsUrl,
        liteRtLmReleaseUrl,
      ]);
    });

    test('fails and names a drifted llama.cpp bundle', () async {
      final bundle = llamaCppPins.keys.first;
      bodies[llamaCppSumsUrl] = sums({...llamaCppPins, bundle: 'f' * 64});
      expect(await runCli(), 1);
      expect(err.toString(), contains('$bundle pins'));
      expect(err.toString(), contains('sync_native_release_pins.py'));
    });

    test('fails and names a drifted LiteRT-LM bundle', () async {
      final bundle = liteRtLmBundleSpecs.last.bundle;
      bodies[liteRtLmReleaseUrl] = release({...liteRtLmPins, bundle: 'f' * 64});
      expect(await runCli(), 1);
      expect(
        err.toString(),
        allOf(
          contains(
            'liteRtLmBundleSpecs does not match $liteRtLmReleaseTag '
            'release asset digests',
          ),
          contains('$bundle pins ${liteRtLmPins[bundle]}'),
          contains(
            'litert-lm-native-runtime-$bundle-$liteRtLmReleaseTag.tar.gz',
          ),
          contains('sync_native_release_pins.py'),
        ),
      );
      expect(out.toString(), contains('llamaCppBundleSha256 matches'));
    });

    test('fails and names a drifted stable_diffusion archive', () async {
      final bundle = stableDiffusionBundleSpecs.first.bundle;
      bodies[stableDiffusionSumsUrl] = stableDiffusionSums({
        ...stableDiffusionPins,
        bundle: 'f' * 64,
      });
      expect(await runCli(), 1);
      expect(
        err.toString(),
        allOf(
          contains(
            'stableDiffusionBundleSpecs does not match '
            '$stableDiffusionReleaseTag SHA256SUMS',
          ),
          contains('$bundle pins ${stableDiffusionPins[bundle]}'),
          contains(
            'stable-diffusion-native-runtime-$bundle-'
            '$stableDiffusionReleaseTag.tar.gz',
          ),
        ),
      );
    });

    test('fails when a release no longer publishes a pinned asset', () async {
      final bundle = liteRtLmBundleSpecs.first.bundle;
      bodies[liteRtLmReleaseUrl] = release({...liteRtLmPins}..remove(bundle));
      expect(await runCli(), 1);
      expect(
        err.toString(),
        contains(
          'lists no litert-lm-native-runtime-$bundle-'
          '$liteRtLmReleaseTag.tar.gz',
        ),
      );
    });

    test('fails when a release cannot be read, and still checks the '
        'others', () async {
      bodies.remove(liteRtLmReleaseUrl);
      bodies.remove(stableDiffusionSumsUrl);
      expect(await runCli(), 1);
      expect(
        err.toString(),
        allOf(
          contains(
            'Could not read leehack/litert-lm-native '
            '$liteRtLmReleaseTag release asset digests: '
            'HttpException: HTTP 404',
          ),
          contains(
            'Could not read leehack/stable-diffusion-native '
            '$stableDiffusionReleaseTag SHA256SUMS',
          ),
        ),
      );
      expect(out.toString(), contains('llamaCppBundleSha256 matches'));
      expect(err.toString(), isNot(contains('Regenerate')));
    });

    test('checks every pinned bundle of every runtime', () async {
      final sources = <String, String Function(String bundle)>{
        for (final bundle in llamaCppPins.keys)
          'llama.cpp $bundle': (bundle) => bodies[llamaCppSumsUrl] = sums({
            ...llamaCppPins,
            bundle: 'f' * 64,
          }),
        for (final bundle in stableDiffusionPins.keys)
          'stable_diffusion $bundle': (bundle) =>
              bodies[stableDiffusionSumsUrl] = stableDiffusionSums({
                ...stableDiffusionPins,
                bundle: 'f' * 64,
              }),
        for (final bundle in liteRtLmPins.keys)
          'LiteRT-LM $bundle': (bundle) => bodies[liteRtLmReleaseUrl] = release(
            {...liteRtLmPins, bundle: 'f' * 64},
          ),
      };
      expect(
        sources,
        hasLength(
          llamaCppPins.length +
              stableDiffusionBundleSpecs.length +
              liteRtLmBundleSpecs.length,
        ),
      );
      final original = Map.of(bodies);
      for (final MapEntry(key: name, value: flip) in sources.entries) {
        bodies = Map.of(original);
        err.clear();
        final bundle = name.split(' ').last;
        flip(bundle);
        expect(await runCli(), 1, reason: name);
        expect(err.toString(), contains('$bundle pins'), reason: name);
      }
    });

    test(
      'passes the first non-empty GitHub token to the API read only',
      () async {
        for (final (environment, expected) in [
          (<String, String>{}, null),
          ({'GH_TOKEN': 'gh'}, 'gh'),
          ({'GITHUB_TOKEN': 'github'}, 'github'),
          ({'GH_TOKEN': 'gh', 'GITHUB_TOKEN': 'github'}, 'gh'),
          ({'GH_TOKEN': '', 'GITHUB_TOKEN': 'github'}, 'github'),
          ({'GH_TOKEN': '', 'GITHUB_TOKEN': ''}, null),
        ]) {
          tokens.clear();
          final code = await run(
            const [],
            out: out,
            err: err,
            fetch: fetch,
            environment: environment,
          );
          expect(code, 0, reason: '$environment');
          expect(tokens, {
            llamaCppSumsUrl: null,
            stableDiffusionSumsUrl: null,
            liteRtLmReleaseUrl: expected,
          }, reason: '$environment');
        }
      },
    );

    test('reads local copies instead of fetching them', () async {
      final code = await runCli([
        '--llama-cpp-sums',
        write('llama', sums(llamaCppPins)),
        '--stable-diffusion-sums',
        write('sd', stableDiffusionSums(stableDiffusionPins)),
        '--litert-lm-release',
        write('litert', release(liteRtLmPins)),
      ]);
      expect(code, 0, reason: '$err');
      expect(fetched, isEmpty);
    });

    test('checks a local copy against the pins', () async {
      final bundle = liteRtLmBundleSpecs.first.bundle;
      final code = await runCli([
        '--litert-lm-release',
        write('litert', release({...liteRtLmPins, bundle: 'f' * 64})),
      ]);
      expect(code, 1);
      expect(err.toString(), contains('$bundle pins'));
      expect(fetched, hasLength(2));
    });

    test('fails when a local copy cannot be read', () async {
      final code = await runCli([
        '--llama-cpp-sums',
        p.join(scratch.path, 'missing'),
      ]);
      expect(code, 1);
      expect(
        err.toString(),
        contains('Could not read leehack/llamadart-native $llamaCppTag'),
      );
    });

    test('rejects unknown arguments with a usage error', () async {
      for (final args in [
        ['--bogus'],
        ['--bogus', 'x'],
        ['--sums-file', 'x'],
        ['--llama-cpp-sums'],
        ['--llama-cpp-sums', 'a', 'b'],
        ['--llama-cpp-sums', 'a', '--llama-cpp-sums', 'b'],
      ]) {
        err.clear();
        expect(await runCli(args), 64, reason: '$args');
        expect(err.toString(), contains('Usage:'), reason: '$args');
      }
      expect(fetched, isEmpty);
    });

    test('main sets the process exit code', () async {
      final bundle = llamaCppPins.keys.first;
      addTearDown(() => exitCode = 0);
      await check_native_release_digests.main([
        '--llama-cpp-sums',
        write('llama', sums({...llamaCppPins, bundle: 'f' * 64})),
        '--stable-diffusion-sums',
        write('sd', stableDiffusionSums(stableDiffusionPins)),
        '--litert-lm-release',
        write('litert', release(liteRtLmPins)),
      ]);
      expect(exitCode, 1);
    });
  });

  group('fetchers', () {
    late HttpServer server;
    late Uri url;
    var status = HttpStatus.ok;
    var body = '';
    HttpHeaders? headers;

    setUp(() async {
      status = HttpStatus.ok;
      body = '';
      headers = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      url = Uri.parse('http://${server.address.host}:${server.port}/file');
      server.listen((request) {
        headers = request.headers;
        request.response.statusCode = status;
        if (status == HttpStatus.found) {
          request.response.headers.set('location', '/elsewhere');
        }
        request.response
          ..write(body)
          ..close();
      });
    });

    tearDown(() => server.close(force: true));

    test('fetchSha256Sums returns a body of exactly the size limit', () async {
      body = 'a' * maxSha256SumsBytes;
      expect(await fetchSha256Sums(url), body);
    });

    test('fetchSha256Sums rejects a body over the size limit', () async {
      body = 'a' * (maxSha256SumsBytes + 1);
      await expectLater(
        fetchSha256Sums(url),
        throwsA(
          isA<HttpException>().having(
            (error) => error.message,
            'message',
            contains('body exceeds'),
          ),
        ),
      );
    });

    test('fetchSha256Sums rejects a non-200 response', () async {
      status = HttpStatus.notFound;
      await expectLater(
        fetchSha256Sums(url),
        throwsA(
          isA<HttpException>().having(
            (error) => error.message,
            'message',
            'HTTP 404',
          ),
        ),
      );
    });

    test('fetchGitHubRelease sends the token only as a header', () async {
      body = '{}';
      expect(await fetchGitHubRelease(url, token: 'secret-token'), '{}');
      expect(headers?.value('authorization'), 'Bearer secret-token');
      expect(headers?.value('accept'), 'application/vnd.github+json');
    });

    test('fetchGitHubRelease sends no authorization without a token', () async {
      body = '{}';
      for (final token in [null, '']) {
        headers = null;
        await fetchGitHubRelease(url, token: token);
        expect(headers?.value('authorization'), isNull, reason: '$token');
      }
    });

    test('fetchGitHubRelease does not follow redirects', () async {
      status = HttpStatus.found;
      await expectLater(
        fetchGitHubRelease(url, token: 'secret-token'),
        throwsA(
          isA<HttpException>()
              .having((error) => error.message, 'message', 'HTTP 302')
              .having(
                (error) => '$error',
                'toString',
                isNot(contains('secret-token')),
              ),
        ),
      );
    });

    test('fetchGitHubRelease reads a release body of up to 1 MiB', () async {
      for (final size in [64 * 1024 + 1, 512 * 1024, 1024 * 1024]) {
        body = 'a' * size;
        expect(await fetchGitHubRelease(url), hasLength(size));
      }
    });

    test('fetchGitHubRelease rejects a body over its size limit', () async {
      body = 'a' * (1024 * 1024 + 1);
      await expectLater(
        fetchGitHubRelease(url),
        throwsA(
          isA<HttpException>().having(
            (error) => error.message,
            'message',
            contains('body exceeds'),
          ),
        ),
      );
    });
  });
}
