import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llamadart_validation/io.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class BlockedClient extends http.BaseClient {
  final response = Completer<http.StreamedResponse>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      response.future;
  @override
  void close() {
    closed = true;
    if (!response.isCompleted) {
      response.completeError(http.ClientException('cancelled'));
    }
  }
}

class SlowModelClient extends http.BaseClient {
  final body = StreamController<List<int>>();
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed) throw http.ClientException('Client is already closed');
    body.add([1, 2]);
    return http.StreamedResponse(body.stream, 200);
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    body.addError(http.ClientException('Connection closed by transport'));
    unawaited(body.close());
  }
}

void main() {
  late Directory cache;
  late ValidationProfile profile;
  final bytes = utf8.encode('model fixture bytes');
  setUp(() {
    cache = Directory.systemTemp.createTempSync('validation-model-test-');
    final json =
        jsonDecode(
              File('assets/profiles/tiny-gguf-cpu.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    json['model']['sha256'] = sha256.convert(bytes).toString();
    json['model']['bytes'] = bytes.length;
    profile = ValidationProfile.fromJson(json);
  });
  tearDown(() => cache.deleteSync(recursive: true));
  test('verified cache hit never downloads again', () async {
    var calls = 0;
    final first = await prepareModel(
      profile,
      cache,
      client: MockClient((_) async {
        calls++;
        return http.Response.bytes(bytes, 200);
      }),
      timeout: const Duration(minutes: 10),
    );
    expect(first.evidence['verified'], true);
    expect(first.evidence['download_timeout_ms'], 600000);
    final second = await prepareModel(
      profile,
      cache,
      client: MockClient((_) async => throw StateError('unexpected network')),
    );
    expect(second.evidence['cache_hit'], true);
    expect(calls, 1);
  });
  test(
    'oversized or wrong-hash download leaves no partial or cached model',
    () async {
      for (final content in [
        List<int>.filled(bytes.length, 0),
        [...bytes, 0],
      ]) {
        await expectLater(
          prepareModel(
            profile,
            cache,
            client: MockClient((_) async => http.Response.bytes(content, 200)),
          ),
          throwsFormatException,
        );
        expect(cache.listSync(recursive: true).whereType<File>(), isEmpty);
      }
    },
  );
  test(
    'preparation progress survives failure without claiming verification',
    () async {
      final events = <Map<String, dynamic>>[];
      await expectLater(
        prepareModel(
          profile,
          cache,
          client: MockClient(
            (_) async =>
                http.Response.bytes(List<int>.filled(bytes.length, 0), 200),
          ),
          onProgress: (event) async => events.add(event),
        ),
        throwsFormatException,
      );
      expect(events.map((e) => '${e['stage']}:${e['state']}'), [
        'download:started',
        'download:finished',
        'checksum:started',
        'checksum:rejected',
      ]);
      expect(events.last['bytes'], bytes.length);
      expect(
        events.every((e) => e['model_sha256'] == profile.modelHash),
        isTrue,
      );
      expect(jsonEncode(events), isNot(contains(cache.path)));
      expect(jsonEncode(events), isNot(contains(profile.model['url'])));
      expect(cache.listSync(recursive: true).whereType<File>(), isEmpty);
    },
  );

  test(
    'durable progress distinguishes download, hash and verified reuse',
    () async {
      final journal = FileValidationJournal(
        Directory(p.join(cache.path, 'run')),
      );
      await prepareModel(
        profile,
        cache,
        client: MockClient((_) async => http.Response.bytes(bytes, 200)),
        onProgress: journal.emitPreparation,
      );
      await journal.emit({'type': 'manifest', 'test_marker': true});
      journal.close();
      final suiteEvents = File(
        p.join(cache.path, 'run', 'events.jsonl'),
      ).readAsLinesSync();
      expect(suiteEvents, hasLength(1));
      expect(jsonDecode(suiteEvents.single)['type'], 'manifest');
      final events = const LineSplitter()
          .convert(
            File(
              p.join(cache.path, 'run', 'preparation.jsonl'),
            ).readAsStringSync(),
          )
          .map((line) => jsonDecode(line) as Map)
          .toList();
      expect(events.map((e) => '${e['stage']}:${e['state']}'), [
        'download:started',
        'download:finished',
        'checksum:started',
        'checksum:verified',
        'ready:verified',
      ]);
      expect(events.last['bytes'], bytes.length);
      final reuse = <Map<String, dynamic>>[];
      await prepareModel(
        profile,
        cache,
        client: MockClient((_) async => throw StateError('no network')),
        onProgress: (e) async => reuse.add(e),
      );
      expect(reuse.map((e) => e['stage']), ['checksum', 'checksum', 'ready']);
      // Progress alone cannot qualify an interrupted preparation as a suite pass.
      expect(
        ValidationReport.parse(events.map(jsonEncode).join('\n')).qualified,
        isFalse,
      );
    },
  );

  test('invalid supplied file is retained for the user', () async {
    final input = File(p.join(cache.path, 'user-model.gguf'))
      ..writeAsStringSync('wrong');
    await expectLater(
      prepareModel(profile, cache, suppliedPath: input.path),
      throwsFormatException,
    );
    expect(input.readAsStringSync(), 'wrong');
  });
  test(
    'deadline closes the active request and removes partial files',
    () async {
      final client = BlockedClient();
      await expectLater(
        prepareModel(
          profile,
          cache,
          client: client,
          timeout: const Duration(milliseconds: 5),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(client.closed, true);
      expect(cache.listSync(recursive: true).whereType<File>(), isEmpty);
    },
  );

  test('download deadline retains byte progress in its diagnostic', () async {
    final client = SlowModelClient();
    await expectLater(
      prepareModel(
        profile,
        cache,
        client: client,
        timeout: const Duration(milliseconds: 50),
      ),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'bounded progress diagnostic',
          contains('receiving 2 of ${bytes.length} bytes'),
        ),
      ),
    );
    expect(client.closed, isTrue);
    expect(cache.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('external cancellation is distinct from a download deadline', () async {
    final client = SlowModelClient();
    final cancel = Timer(const Duration(milliseconds: 20), client.close);
    addTearDown(cancel.cancel);
    await expectLater(
      prepareModel(
        profile,
        cache,
        client: client,
        retryDelays: const [Duration.zero],
      ),
      throwsA(isA<http.ClientException>()),
    );
    expect(cache.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  group('dropped connections', () {
    const noWait = [Duration.zero, Duration.zero];

    MockClient serving(
      List<http.BaseRequest> requests,
      List<int> Function(int attempt, int? rangeStart) body, {
      bool honorRange = true,
      int dropAfter = 5,
    }) => MockClient.streaming((request, _) async {
      requests.add(request);
      final attempt = requests.length;
      final range = request.headers['Range'];
      final start = range == null
          ? null
          : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      final resumed = honorRange && start != null;
      final chunk = body(attempt, resumed ? start : null);
      Stream<List<int>> stream() async* {
        if (attempt == 1) {
          yield chunk.sublist(0, dropAfter);
          throw http.ClientException('Connection closed while receiving data');
        }
        yield chunk;
      }

      return http.StreamedResponse(
        stream(),
        resumed ? 206 : 200,
        headers: resumed
            ? {
                'content-range':
                    'bytes $start-${bytes.length - 1}/${bytes.length}',
              }
            : const {},
      );
    });

    test('resume with a Range request after the connection drops', () async {
      final requests = <http.BaseRequest>[];
      final client = serving(
        requests,
        (attempt, start) => start == null ? bytes : bytes.sublist(start),
      );

      final prepared = await prepareModel(
        profile,
        cache,
        client: client,
        retryDelays: noWait,
      );

      expect(prepared.evidence['verified'], isTrue);
      expect(File(prepared.path).readAsBytesSync(), bytes);
      expect(requests, hasLength(2));
      expect(requests.first.headers.containsKey('Range'), isFalse);
      expect(requests.last.headers['Range'], 'bytes=5-');
    });

    test('restart from zero when the server ignores Range', () async {
      final requests = <http.BaseRequest>[];
      final client = serving(
        requests,
        (attempt, start) => bytes,
        honorRange: false,
      );

      final prepared = await prepareModel(
        profile,
        cache,
        client: client,
        retryDelays: noWait,
      );

      expect(File(prepared.path).readAsBytesSync(), bytes);
      expect(requests.last.headers['Range'], 'bytes=5-');
    });

    test('give up after the bounded number of retries', () async {
      var calls = 0;
      final client = MockClient.streaming((request, _) async {
        calls++;
        return http.StreamedResponse(
          Stream<List<int>>.error(
            http.ClientException('Connection closed while receiving data'),
          ),
          200,
        );
      });

      await expectLater(
        prepareModel(profile, cache, client: client, retryDelays: noWait),
        throwsA(isA<http.ClientException>()),
      );
      expect(calls, noWait.length + 1);
      expect(cache.listSync(recursive: true).whereType<File>(), isEmpty);
    });

    test('retry a server error but not a missing model', () async {
      for (final (status, expected) in [(503, 3), (404, 1)]) {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return http.Response('', status);
        });

        await expectLater(
          prepareModel(profile, cache, client: client, retryDelays: noWait),
          throwsA(isA<HttpException>()),
          reason: '$status',
        );
        expect(calls, expected, reason: '$status');
      }
    });
  });
}
