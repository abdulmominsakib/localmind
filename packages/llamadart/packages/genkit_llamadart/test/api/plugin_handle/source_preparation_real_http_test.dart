@Tags(<String>['real-model'])
library;

import 'dart:async';
import 'dart:io';

import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:test/test.dart';

import '../../integration/genkit/test_support/real_model_test_support.dart';

void main() {
  test(
    'prepareModelTask downloads a real GGUF over HTTP then hits cache',
    () async {
      final modelPath = await resolveIntegrationModelPath();
      if (modelPath == null) return;
      final server = await _FileServer.start(File(modelPath));
      final cacheDirectory = await Directory.systemTemp.createTemp(
        'genkit_llamadart_http_cache_',
      );
      addTearDown(() async {
        await server.close();
        await cacheDirectory.delete(recursive: true);
      });

      final firstTask = llamaDart.prepareModelTask(
        name: 'http-chat',
        source: ModelSource.url(server.uri),
        options: ModelLoadOptions(cacheDirectory: cacheDirectory.path),
        supportsEmbeddings: false,
      );
      final firstSnapshots = <LlamaModelPreparationSnapshot>[];
      final firstSubscription = firstTask.snapshots.listen(firstSnapshots.add);
      addTearDown(() async {
        await firstSubscription.cancel();
        await firstTask.dispose();
      });

      final firstPrepared = await firstTask.result;
      addTearDown(firstPrepared.dispose);

      expect(await File(firstPrepared.modelEntry.filePath).exists(), isTrue);
      expect(
        firstSnapshots.map((snapshot) => snapshot.stage),
        containsAllInOrder(<LlamaModelPreparationStage>[
          LlamaModelPreparationStage.checkingCache,
          LlamaModelPreparationStage.downloading,
          LlamaModelPreparationStage.ready,
        ]),
      );

      final secondTask = llamaDart.prepareModelTask(
        name: 'http-chat-cached',
        source: ModelSource.url(server.uri),
        options: ModelLoadOptions(cacheDirectory: cacheDirectory.path),
        supportsEmbeddings: false,
      );
      final secondSnapshots = <LlamaModelPreparationSnapshot>[];
      final secondSubscription = secondTask.snapshots.listen(
        secondSnapshots.add,
      );
      addTearDown(() async {
        await secondSubscription.cancel();
        await secondTask.dispose();
      });

      final secondPrepared = await secondTask.result;
      addTearDown(secondPrepared.dispose);

      expect(
        secondPrepared.modelEntry.filePath,
        firstPrepared.modelEntry.filePath,
      );
      expect(
        secondSnapshots.map((snapshot) => snapshot.stage),
        contains(LlamaModelPreparationStage.checkingCache),
      );
      expect(
        secondSnapshots.map((snapshot) => snapshot.stage),
        isNot(contains(LlamaModelPreparationStage.downloading)),
      );
    },
  );

  test('prepareModelTask cancels an in-flight HTTP download', () async {
    final modelPath = await resolveIntegrationModelPath();
    if (modelPath == null) return;
    final server = await _FileServer.start(
      File(modelPath),
      bytesPerChunk: 16 * 1024,
      delayPerChunk: const Duration(milliseconds: 2),
    );
    final cacheDirectory = await Directory.systemTemp.createTemp(
      'genkit_llamadart_http_cancel_',
    );
    addTearDown(() async {
      await server.close();
      await cacheDirectory.delete(recursive: true);
    });

    final task = llamaDart.prepareModelTask(
      name: 'cancel-http-chat',
      source: ModelSource.url(server.uri),
      options: ModelLoadOptions(cacheDirectory: cacheDirectory.path),
      supportsEmbeddings: false,
    );
    final snapshots = <LlamaModelPreparationSnapshot>[];
    late final StreamSubscription<LlamaModelPreparationSnapshot> subscription;
    subscription = task.snapshots.listen((snapshot) {
      snapshots.add(snapshot);
      if (snapshot.stage == LlamaModelPreparationStage.downloading &&
          snapshot.progress != null) {
        task.cancel();
      }
    });
    addTearDown(() async {
      await subscription.cancel();
      await task.dispose();
    });

    await expectLater(task.result, throwsA(isA<LlamaStateException>()));
    expect(snapshots.last.stage, LlamaModelPreparationStage.cancelled);
  });
}

class _FileServer {
  _FileServer._(this._server, this.uri);

  final HttpServer _server;
  final Uri uri;

  static Future<_FileServer> start(
    File file, {
    int bytesPerChunk = 256 * 1024,
    Duration delayPerChunk = Duration.zero,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final request in server) {
        await _serveFile(
          file: file,
          request: request,
          bytesPerChunk: bytesPerChunk,
          delayPerChunk: delayPerChunk,
        );
      }
    }());
    return _FileServer._(
      server,
      Uri.parse(
        'http://${server.address.host}:${server.port}/${file.uri.pathSegments.last}',
      ),
    );
  }

  Future<void> close() {
    return _server.close(force: true);
  }

  static Future<void> _serveFile({
    required File file,
    required HttpRequest request,
    required int bytesPerChunk,
    required Duration delayPerChunk,
  }) async {
    final response = request.response;
    response.headers.contentType = ContentType.binary;
    response.headers.set(
      'content-disposition',
      'attachment; filename="${file.uri.pathSegments.last}"',
    );
    response.contentLength = await file.length();

    final input = await file.open();
    try {
      while (true) {
        final bytes = await input.read(bytesPerChunk);
        if (bytes.isEmpty) {
          break;
        }
        response.add(bytes);
        await response.flush();
        if (delayPerChunk != Duration.zero) {
          await Future<void>.delayed(delayPerChunk);
        }
      }
    } on SocketException {
      // Expected when cancellation closes the client connection mid-stream.
    } on HttpException {
      // Expected when cancellation closes the client connection mid-stream.
    } finally {
      await input.close();
      await _closeResponse(response);
    }
  }

  static Future<void> _closeResponse(HttpResponse response) async {
    try {
      await response.close();
    } on SocketException {
      // The client may have disconnected before the server closes the response.
    } on HttpException {
      // The client may have disconnected before the server closes the response.
    }
  }
}
