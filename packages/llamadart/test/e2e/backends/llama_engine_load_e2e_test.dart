@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Real-runtime coverage of `LlamaEngine.load` and `setModel`: a GGUF with
/// its projector on the default device and on the CPU, replacing a model
/// across runtimes, and cancel and dispose during a download from a loopback
/// HTTP server.
///
/// Set `LLAMADART_LOAD_MODEL_PATH` to a chat GGUF and
/// `LLAMADART_LOAD_MMPROJ_PATH` to its vision projector. The LiteRT-LM tests
/// also need `LLAMADART_LOAD_LITERTLM_PATH`, a `.litertlm` chat bundle.
void main() {
  final modelPath = Platform.environment['LLAMADART_LOAD_MODEL_PATH'] ?? '';
  final mmprojPath = Platform.environment['LLAMADART_LOAD_MMPROJ_PATH'] ?? '';
  final liteRtLmPath =
      Platform.environment['LLAMADART_LOAD_LITERTLM_PATH'] ?? '';
  final skip = modelPath.isEmpty || mmprojPath.isEmpty
      ? 'Set LLAMADART_LOAD_MODEL_PATH and LLAMADART_LOAD_MMPROJ_PATH to run '
            'the LlamaEngine.load E2E.'
      : null;
  final skipLiteRtLm =
      skip ??
      (liteRtLmPath.isEmpty
          ? 'Set LLAMADART_LOAD_LITERTLM_PATH to run the LiteRT-LM cases.'
          : null);

  LlamaModel gguf() => LlamaModel(
    ModelSource.path(modelPath),
    projector: ModelSource.path(mmprojPath),
  );

  // Generated text, or the reasoning of a model that thinks first.
  Future<String> answer(LlamaEngine engine) async {
    final reply = await engine.complete(const [
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Say hello.'),
    ], params: const GenerationParams(maxTokens: 8));
    return '${reply.thinking}${reply.text}';
  }

  Future<void> report(String label, LlamaEngine engine, Stopwatch load) async {
    // ignore: avoid_print
    print(
      'LOAD_E2E ${jsonEncode({'case': label, 'runtime': engine.runtime?.name, 'backend': await engine.getBackendName(), 'gpuLayers': await engine.getResolvedGpuLayers(), 'vision': await engine.supportsVision, 'loadMs': load.elapsedMilliseconds})}',
    );
  }

  for (final device in [ComputeDevice.auto, ComputeDevice.cpu]) {
    test(
      'load reads a GGUF and its projector in one call (${device.name})',
      skip: skip,
      () async {
        final load = Stopwatch()..start();
        final engine = await LlamaEngine.load(
          gguf(),
          params: ModelParams(contextSize: 2048, device: device),
        );
        load.stop();
        addTearDown(engine.dispose);
        await report('load ${device.name}', engine, load);

        expect(engine.isReady, isTrue);
        expect(engine.runtime, LlamaRuntime.llamaCpp);
        expect(engine.hasMultimodalProjector, isTrue);
        expect(await engine.supportsVision, isTrue);
        if (device == ComputeDevice.cpu) {
          expect(await engine.getResolvedGpuLayers(), 0);
        }
        expect(await answer(engine), isNotEmpty);
      },
    );
  }

  for (final device in [ComputeDevice.auto, ComputeDevice.cpu]) {
    for (final operation in ['unload', 'dispose', 'replace']) {
      test(
        '$operation cancels a real GGUF tool-loop answer (${device.name})',
        skip: skip,
        () async {
          final observer = _FirstReplyObserver();
          final params = ModelParams(contextSize: 2048, device: device);
          final engine = await LlamaEngine.load(
            gguf(),
            params: params,
            observers: [observer],
          );
          addTearDown(engine.dispose);
          final session = ChatSession(engine, maxContextTokens: 0);
          final running = session.sendWithTools(
            'Count from 1 to 1000, writing each number on a new line.',
            tools: const [],
            enableThinking: false,
            params: const GenerationParams(
              maxTokens: 1024,
              streamBatchTokenThreshold: 1,
              streamBatchByteThreshold: 1,
            ),
          );
          await observer.firstReply.future.timeout(const Duration(seconds: 30));
          switch (operation) {
            case 'unload':
              await engine.unloadModel();
            case 'dispose':
              await engine.dispose();
            case 'replace':
              await engine.setModel(gguf(), params: params);
          }
          final result = await running;
          expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
          expect(result.text, isNotEmpty);
          expect(result.rolledBack, isFalse);
          expect(session.history.last.role, LlamaChatRole.assistant);
          expect(session.history.last.content, result.text);

          if (operation == 'unload') {
            await engine.setModel(gguf(), params: params);
          }
          if (operation != 'dispose') {
            session.reset();
            final next = await session.sendWithTools(
              'Say hello.',
              tools: const [],
              enableThinking: false,
              params: const GenerationParams(maxTokens: 16),
            );
            // A short sampling budget may truncate a valid fresh reply.
            expect(
              next.stopReason,
              isIn([
                LlamaToolLoopStopReason.completed,
                LlamaToolLoopStopReason.truncated,
              ]),
            );
            expect(next.text, isNotEmpty);
          }
        },
      );
    }
  }

  test(
    'a projector that does not fit the model leaves nothing loaded',
    skip: skip,
    () async {
      final notAProjector = LlamaModel(
        ModelSource.path(modelPath),
        projector: ModelSource.path(modelPath),
      );
      await expectLater(
        LlamaEngine.load(notAProjector),
        throwsA(isA<LlamaException>()),
      );

      final engine = await LlamaEngine.load(
        gguf(),
        params: const ModelParams(contextSize: 2048),
      );
      addTearDown(engine.dispose);
      await expectLater(
        engine.setModel(notAProjector),
        throwsA(isA<LlamaException>()),
      );
      expect(engine.isReady, isFalse);
      expect(engine.hasMultimodalProjector, isFalse);

      await engine.setModel(
        gguf(),
        params: const ModelParams(contextSize: 2048),
      );
      expect(await engine.supportsVision, isTrue);
      expect(await answer(engine), isNotEmpty);
    },
  );

  test('load reads a local file whose name holds %2F', skip: skip, () async {
    final directory = await Directory.systemTemp.createTemp('llamadart_e2e_');
    addTearDown(() => directory.delete(recursive: true));
    final link = await Link(
      p.join(directory.path, 'chat%2Fmodel.gguf'),
    ).create(modelPath);

    final engine = await LlamaEngine.load(
      LlamaModel(ModelSource.path(link.path)),
      params: const ModelParams(contextSize: 2048),
    );
    addTearDown(engine.dispose);

    expect(await answer(engine), isNotEmpty);
  });

  test(
    'setModel replaces a GGUF with a LiteRT-LM bundle and back',
    skip: skipLiteRtLm,
    () async {
      final load = Stopwatch()..start();
      final engine = await LlamaEngine.load(
        gguf(),
        params: const ModelParams(contextSize: 2048),
      );
      addTearDown(engine.dispose);

      load.reset();
      await engine.setModel(
        LlamaModel(ModelSource.path(liteRtLmPath)),
        params: const ModelParams(contextSize: 2048),
      );
      await report('setModel litertlm', engine, load);
      expect(engine.runtime, LlamaRuntime.liteRtLm);
      expect(engine.hasMultimodalProjector, isFalse);
      expect(await answer(engine), isNotEmpty);

      await expectLater(
        engine.setModel(
          LlamaModel(
            ModelSource.path(liteRtLmPath),
            projector: ModelSource.path(mmprojPath),
          ),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(engine.runtime, LlamaRuntime.liteRtLm);
      expect(await answer(engine), isNotEmpty);

      load.reset();
      await engine.setModel(
        gguf(),
        params: const ModelParams(contextSize: 2048),
      );
      await report('setModel gguf', engine, load);
      expect(engine.runtime, LlamaRuntime.llamaCpp);
      expect(await engine.supportsVision, isTrue);
      expect(await answer(engine), isNotEmpty);
    },
  );

  group('with the model served over loopback HTTP', () {
    late Directory cache;
    late HttpServer server;
    late Completer<void> started;
    late Completer<void> release;

    setUp(() async {
      cache = await Directory.systemTemp.createTemp('llamadart_e2e_cache_');
      started = Completer<void>();
      release = Completer<void>();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final file = File(modelPath);
        final response = request.response
          ..bufferOutput = false
          ..headers.contentLength = file.lengthSync();
        try {
          var sent = 0;
          await for (final chunk in file.openRead()) {
            response.add(chunk);
            sent += chunk.length;
            if (sent >= 1 << 20 && !started.isCompleted) {
              await response.flush();
              started.complete();
              await release.future;
            }
          }
          await response.close();
        } on Object {
          // The client stopped reading.
        }
      });
    });

    tearDown(() async {
      if (!release.isCompleted) release.complete();
      await server.close(force: true);
      await cache.delete(recursive: true);
    });

    LlamaModel remote() => LlamaModel(
      ModelSource.url(
        Uri.parse('http://127.0.0.1:${server.port}/downloaded.gguf'),
      ),
      projector: ModelSource.path(mmprojPath),
    );

    bool cached() => cache
        .listSync(recursive: true)
        .any((entry) => p.basename(entry.path) == 'downloaded.gguf');

    test(
      'the loaded model answers while the next one downloads, then is '
      'replaced',
      skip: skip,
      () async {
        final engine = await LlamaEngine.load(
          LlamaModel(ModelSource.path(modelPath)),
          params: const ModelParams(contextSize: 2048),
        );
        addTearDown(engine.dispose);
        final progress = <ModelDownloadProgress>[];

        final replacing = engine.setModel(
          remote(),
          params: const ModelParams(contextSize: 2048),
          download: ModelLoadOptions(cacheDirectory: cache.path),
          onProgress: progress.add,
        );
        await started.future;
        expect(engine.isReady, isTrue);
        expect(engine.hasMultimodalProjector, isFalse);
        expect(await answer(engine), isNotEmpty);
        release.complete();
        await replacing;

        expect(cached(), isTrue);
        expect(progress.last.receivedBytes, progress.last.totalBytes);
        expect(await engine.supportsVision, isTrue);
        expect(await answer(engine), isNotEmpty);
      },
    );

    test(
      'a cancelled download leaves the loaded model answering',
      skip: skip,
      () async {
        final engine = await LlamaEngine.load(
          LlamaModel(ModelSource.path(modelPath)),
          params: const ModelParams(contextSize: 2048),
        );
        addTearDown(engine.dispose);
        final token = ModelDownloadCancelToken();

        final replacing = engine.setModel(
          remote(),
          download: ModelLoadOptions(
            cacheDirectory: cache.path,
            cancelToken: token,
          ),
        );
        final outcome = expectLater(
          replacing,
          throwsA(isA<LlamaStateException>()),
        );
        await started.future;
        token.cancel();
        release.complete();
        await outcome;

        expect(cached(), isFalse);
        expect(engine.isReady, isTrue);
        expect(await answer(engine), isNotEmpty);
      },
    );

    test(
      'dispose during the download ends the load at once and loads nothing',
      skip: skip,
      () async {
        final engine = LlamaEngine(LlamaBackend());
        final loading = engine.setModel(
          remote(),
          download: ModelLoadOptions(cacheDirectory: cache.path),
        );
        final outcome = expectLater(
          loading,
          throwsA(
            isA<LlamaStateException>().having(
              (error) => error.message,
              'message',
              contains('disposed while loading'),
            ),
          ),
        );
        await started.future;

        final dispose = Stopwatch()..start();
        await engine.dispose();
        dispose.stop();
        await outcome;
        // ignore: avoid_print
        print(
          'LOAD_E2E ${jsonEncode({'case': 'dispose during download', 'disposeMs': dispose.elapsedMilliseconds})}',
        );

        expect(dispose.elapsed, lessThan(const Duration(seconds: 5)));
        expect(engine.isReady, isFalse);
        release.complete();
        await Future<void>.delayed(const Duration(seconds: 1));
        expect(cached(), isFalse);
        expect(engine.isReady, isFalse);
      },
    );
  });
}

final class _FirstReplyObserver extends LlamaEngineObserver {
  final firstReply = Completer<void>();

  @override
  LlamaOperationObserver? onStart(LlamaOperation operation) =>
      operation is LlamaChatOperation ? _ReplyObserver(firstReply) : null;
}

final class _ReplyObserver extends LlamaOperationObserver {
  _ReplyObserver(this.firstReply);

  final Completer<void> firstReply;

  @override
  void onChunk(LlamaCompletionChunk chunk) {
    if (!firstReply.isCompleted &&
        chunk.choices.any(
          (choice) => choice.delta.content?.isNotEmpty ?? false,
        )) {
      firstReply.complete();
    }
  }

  @override
  void onEnd(LlamaOperationResult result) {}
}
