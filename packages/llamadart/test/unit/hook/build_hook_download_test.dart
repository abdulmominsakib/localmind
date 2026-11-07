@TestOn('vm')
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../../hook/build.dart' as build_hook;

void main() {
  late Directory tempDir;
  late Logger log;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('llamadart-download-test-');
    log = Logger('llamadart-download-test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('runtime bundle download retries transient HTTP failures', () async {
    final requests = <http.BaseRequest>[];
    final clients = Queue<http.Client>.from([
      _FakeClient((request) async {
        requests.add(request);
        return http.StreamedResponse(
          const Stream<List<int>>.empty(),
          HttpStatus.internalServerError,
        );
      }),
      _FakeClient((request) async {
        requests.add(request);
        return http.StreamedResponse(
          http.ByteStream.fromBytes('downloaded-bundle'.codeUnits),
          HttpStatus.ok,
        );
      }),
    ]);

    final destination = File(path.join(tempDir.path, 'bundle.tar.gz'));
    await build_hook.downloadRuntimeBundleForTesting(
      url: 'https://example.test/bundle.tar.gz',
      destination: destination,
      description: 'test bundle',
      log: log,
      maxAttempts: 2,
      retryBaseDelay: Duration.zero,
      createClient: clients.removeFirst,
    );

    expect(requests, hasLength(2));
    expect(await destination.readAsString(), 'downloaded-bundle');
    expect(File('${destination.path}.tmp').existsSync(), isFalse);
    expect(
      requests.map((request) => request.headers[HttpHeaders.acceptHeader]),
      everyElement('application/octet-stream'),
    );
    expect(
      requests.map((request) => request.headers[HttpHeaders.userAgentHeader]),
      everyElement('llamadart-build-hook'),
    );
  });

  test('runtime bundle request timeout preserves destination', () async {
    final destination = File(path.join(tempDir.path, 'bundle.tar.gz'));
    await destination.writeAsString('cached-bundle');

    await expectLater(
      build_hook.downloadRuntimeBundleForTesting(
        url: 'https://example.test/bundle.tar.gz',
        destination: destination,
        description: 'test bundle',
        log: log,
        maxAttempts: 1,
        requestTimeout: const Duration(milliseconds: 50),
        createClient: () =>
            _FakeClient((_) => Completer<http.StreamedResponse>().future),
      ),
      throwsA(isA<Exception>()),
    );

    expect(await destination.readAsString(), 'cached-bundle');
    expect(File('${destination.path}.tmp').existsSync(), isFalse);
  });

  test('runtime bundle download preserves destination on failure', () async {
    final destination = File(path.join(tempDir.path, 'bundle.tar.gz'));
    await destination.writeAsString('cached-bundle');

    await expectLater(
      build_hook.downloadRuntimeBundleForTesting(
        url: 'https://example.test/bundle.tar.gz',
        destination: destination,
        description: 'test bundle',
        log: log,
        maxAttempts: 1,
        createClient: () => _FakeClient((_) async {
          return http.StreamedResponse(
            const Stream<List<int>>.empty(),
            HttpStatus.badGateway,
          );
        }),
      ),
      throwsA(isA<Exception>()),
    );

    expect(await destination.readAsString(), 'cached-bundle');
    expect(File('${destination.path}.tmp').existsSync(), isFalse);
  });

  test('runtime bundle download uses fallback after HTTP retries', () async {
    var fallbackCalled = false;
    final destination = File(path.join(tempDir.path, 'bundle.tar.gz'));

    await build_hook.downloadRuntimeBundleForTesting(
      url: 'https://example.test/bundle.tar.gz',
      destination: destination,
      description: 'test bundle',
      log: log,
      maxAttempts: 1,
      useCurlFallback: true,
      createClient: () => _FakeClient((_) async {
        return http.StreamedResponse(
          const Stream<List<int>>.empty(),
          HttpStatus.gatewayTimeout,
        );
      }),
      curlFallback:
          ({
            required url,
            required destination,
            required description,
            required log,
          }) async {
            fallbackCalled = true;
            expect(url, 'https://example.test/bundle.tar.gz');
            expect(description, 'test bundle');
            await destination.writeAsString('fallback-bundle');
            return true;
          },
    );

    expect(fallbackCalled, isTrue);
    expect(await destination.readAsString(), 'fallback-bundle');
    expect(File('${destination.path}.tmp').existsSync(), isFalse);
  });

  test('runtime bundle body timeout cleans up partial download', () async {
    final controller = StreamController<List<int>>();
    addTearDown(controller.close);

    final destination = File(path.join(tempDir.path, 'bundle.tar.gz'));
    await destination.writeAsString('cached-bundle');

    await expectLater(
      build_hook.downloadRuntimeBundleForTesting(
        url: 'https://example.test/bundle.tar.gz',
        destination: destination,
        description: 'test bundle',
        log: log,
        maxAttempts: 1,
        transferTimeout: const Duration(milliseconds: 50),
        createClient: () => _FakeClient((_) async {
          scheduleMicrotask(() => controller.add('partial'.codeUnits));
          return http.StreamedResponse(controller.stream, HttpStatus.ok);
        }),
      ),
      throwsA(isA<Exception>()),
    );

    expect(await destination.readAsString(), 'cached-bundle');
    expect(File('${destination.path}.tmp').existsSync(), isFalse);
  });
}

final class _FakeClient extends http.BaseClient {
  _FakeClient(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _send(request);
  }
}
