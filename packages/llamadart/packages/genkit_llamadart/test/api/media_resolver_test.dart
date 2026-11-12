import 'dart:async';

import 'package:genkit/plugin.dart' as genkit;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

const _secret = 'signed-token-never-expose';
final _uri = Uri.parse('https://media.example/image.png?token=$_secret');

class _Client extends http.BaseClient {
  _Client(this.sendResponse);
  final Future<http.StreamedResponse> Function(http.BaseRequest) sendResponse;
  final requests = <http.BaseRequest>[];
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return sendResponse(request);
  }

  @override
  void close() => closed = true;
}

http.StreamedResponse _response(
  List<List<int>> chunks, {
  int status = 200,
  Map<String, String> headers = const {'content-type': 'image/png'},
  int? length,
}) => http.StreamedResponse(
  Stream.fromIterable(chunks),
  status,
  headers: headers,
  contentLength: length,
);

Matcher _safe([genkit.StatusCode status = genkit.StatusCode.invalidArgument]) =>
    isA<genkit.GenkitException>()
        .having((e) => e.status, 'status', status)
        .having((e) => e.toString(), 'safe message', isNot(contains(_secret)))
        .having((e) => e.cause, 'no secret-bearing cause', isNull);

void main() {
  test(
    'streamed image and audio bytes reach caller without owning client',
    () async {
      final client = _Client(
        (_) async => _response([
          [1, 2],
          [3],
        ]),
      );
      final resolver = HttpLlamaDartMediaResolver(
        client: client,
        allowUri: (uri) => uri.host == 'media.example',
      );
      expect(await resolver.resolve(_uri, contentType: 'image/*'), [1, 2, 3]);
      expect(client.requests.single.followRedirects, isFalse);
      expect(client.closed, isFalse);
      final audioClient = _Client(
        (_) async => _response(
          [
            [4, 5],
          ],
          headers: {'content-type': 'Audio/WAV; charset=binary'},
        ),
      );
      expect(
        await HttpLlamaDartMediaResolver(
          client: audioClient,
          allowUri: (_) => true,
        ).resolve(_uri, contentType: 'audio/wav'),
        [4, 5],
      );
    },
  );

  test('initial and redirected destinations must pass policy', () async {
    final client = _Client(
      (_) async => _response(
        [],
        status: 302,
        headers: {'location': 'https://private.example/path?token=$_secret'},
      ),
    );
    final seen = <String>[];
    final resolver = HttpLlamaDartMediaResolver(
      client: client,
      allowUri: (uri) {
        seen.add(uri.host);
        return uri.host == 'media.example';
      },
    );
    await expectLater(
      resolver.resolve(_uri, contentType: 'image/png'),
      throwsA(_safe()),
    );
    expect(seen, ['media.example', 'private.example']);
    expect(client.requests, hasLength(1));
    client.requests.clear();
    await expectLater(
      resolver.resolve(
        Uri.parse('https://private.example/a'),
        contentType: 'image/png',
      ),
      throwsA(_safe()),
    );
    expect(client.requests, isEmpty);
  });

  test('relative redirects resolve once and discard redirect bodies', () async {
    var cancelled = false;
    final client = _Client((request) async {
      if (request.url.path == '/image.png') {
        return http.StreamedResponse(
          StreamController<List<int>>(
            onCancel: () {
              cancelled = true;
            },
          ).stream,
          302,
          headers: {'location': '/final.png'},
        );
      }
      return _response([
        [9],
      ]);
    });
    final resolver = HttpLlamaDartMediaResolver(
      client: client,
      allowUri: (_) => true,
    );
    expect(await resolver.resolve(_uri, contentType: 'image/png'), [9]);
    expect(client.requests.last.url.path, '/final.png');
    expect(cancelled, isTrue);
  });

  for (final scenario in [
    (
      name: 'HTTPS downgrade',
      location: 'http://media.example/insecure',
      message: 'Remote media cannot redirect from HTTPS to HTTP.',
      requests: 1,
    ),
    (
      name: 'URL credentials',
      location: 'https://user:$_secret@media.example/file',
      message: 'Remote media URL is not permitted by the application policy.',
      requests: 1,
    ),
    (
      name: 'non-HTTP scheme',
      location: 'file://media.example/secret',
      message: 'Remote media URL is not permitted by the application policy.',
      requests: 1,
    ),
    (
      name: 'redirect loop',
      location: 'https://media.example/image.png',
      message: 'Remote media exceeded its redirect limit.',
      requests: 2,
    ),
  ]) {
    test('rejects ${scenario.name} before another request', () async {
      final client = _Client(
        (_) async => _response(
          [],
          status: 302,
          headers: {'location': scenario.location},
        ),
      );
      final resolver = HttpLlamaDartMediaResolver(
        client: client,
        allowUri: (_) => true,
        maxRedirects: 1,
      );
      await expectLater(
        resolver.resolve(_uri, contentType: 'image/png'),
        throwsA(
          allOf(
            _safe(),
            isA<genkit.GenkitException>().having(
              (e) => e.message,
              'reason',
              scenario.message,
            ),
          ),
        ),
      );
      expect(client.requests, hasLength(scenario.requests));
    });
  }

  for (final response in [
    _response([
      [1],
    ], status: 403),
    _response(
      [
        [1],
      ],
      headers: {'content-type': 'audio/wav'},
    ),
    _response([
      [1],
    ], headers: {}),
    _response([
      [1],
    ], length: 100),
    _response([
      [1, 2],
      [3, 4],
    ]),
    _response([]),
  ]) {
    test('rejects failure, mismatched MIME, size or empty payload', () async {
      final client = _Client((_) async => response);
      await expectLater(
        HttpLlamaDartMediaResolver(
          client: client,
          allowUri: (_) => true,
          maxBytes: 3,
        ).resolve(_uri, contentType: 'image/png'),
        throwsA(_safe()),
      );
      expect(client.closed, isFalse);
    });
  }

  test(
    'aborts pending headers on total timeout without closing client',
    () async {
      final aborted = Completer<void>();
      final client = _Client((request) async {
        await (request as http.AbortableRequest).abortTrigger;
        aborted.complete();
        throw http.RequestAbortedException(request.url);
      });
      final resolver = HttpLlamaDartMediaResolver(
        client: client,
        allowUri: (_) => true,
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        resolver.resolve(_uri, contentType: 'image/png'),
        throwsA(_safe(genkit.StatusCode.deadlineExceeded)),
      );
      await aborted.future;
      expect(client.closed, isFalse);
    },
  );

  test(
    'cancellation aborts active stream and strips cancellation reason',
    () async {
      final started = Completer<void>();
      var streamCancelled = false;
      final controller = genkit.CancellationController();
      final client = _Client((request) async {
        final stream = StreamController<List<int>>(
          onCancel: () {
            streamCancelled = true;
          },
        );
        unawaited(
          (request as http.AbortableRequest).abortTrigger!.then((_) async {
            stream.addError(http.RequestAbortedException(request.url));
            await stream.close();
          }),
        );
        started.complete();
        return http.StreamedResponse(
          stream.stream,
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      final pending = HttpLlamaDartMediaResolver(
        client: client,
        allowUri: (_) => true,
      ).resolve(_uri, contentType: 'image/png', cancel: controller.token);
      final assertion = expectLater(
        pending,
        throwsA(_safe(genkit.StatusCode.cancelled)),
      );
      await started.future;
      controller.cancel(_secret);
      await assertion;
      await Future<void>.delayed(Duration.zero);
      expect(streamCancelled, isTrue);
      expect(client.closed, isFalse);
    },
  );

  test(
    'already cancelled makes no request and has no unhandled error',
    () async {
      final controller = genkit.CancellationController()..cancel(_secret);
      final client = _Client(
        (_) async => _response([
          [1],
        ]),
      );
      await expectLater(
        HttpLlamaDartMediaResolver(
          client: client,
          allowUri: (_) => true,
        ).resolve(_uri, contentType: 'image/png', cancel: controller.token),
        throwsA(_safe(genkit.StatusCode.cancelled)),
      );
      expect(client.requests, isEmpty);
    },
  );

  test(
    'client and policy exceptions cannot expose signed URLs or causes',
    () async {
      for (final policyError in [false, true]) {
        final client = _Client(
          (_) async => throw genkit.GenkitException(_secret, cause: _secret),
        );
        await expectLater(
          HttpLlamaDartMediaResolver(
            client: client,
            allowUri: (_) {
              if (policyError) throw genkit.GenkitException(_secret);
              return true;
            },
          ).resolve(_uri, contentType: 'image/png'),
          throwsA(_safe()),
        );
      }
    },
  );

  test('unsupported requested type makes no request', () async {
    final client = _Client(
      (_) async => _response([
        [1],
      ]),
    );
    await expectLater(
      HttpLlamaDartMediaResolver(
        client: client,
        allowUri: (_) => true,
      ).resolve(_uri, contentType: 'video/mp4'),
      throwsA(_safe()),
    );
    expect(client.requests, isEmpty);
  });
}
