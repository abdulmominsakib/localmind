@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/worker.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File modelFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'llamadart_litert_worker_test_',
    );
    modelFile = File('${tempDir.path}/model.litertlm');
    await modelFile.writeAsString('fake model');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('liteRtLmWorkerEntry function is available', () {
    expect(liteRtLmWorkerEntry, isA<Function>());
  });

  group('liteRtLmWorkerEntry isolate routing', () {
    test('handles control and info requests', () async {
      final worker = await _spawnWorker();

      try {
        final logResponse = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmLogLevelRequest(LlamaLogLevel.info, sendPort),
        );
        expect(logResponse, isA<LiteRtLmDoneResponse>());

        final backendInfo = await _sendRequest(
          worker.sendPort,
          LiteRtLmBackendInfoRequest.new,
        );
        expect(backendInfo, isA<LiteRtLmBackendInfoResponse>());

        final available = await _sendRequest(
          worker.sendPort,
          LiteRtLmAvailableBackendsRequest.new,
        );
        expect(available, isA<LiteRtLmBackendInfoResponse>());

        final resolved = await _sendRequest(
          worker.sendPort,
          LiteRtLmResolvedGpuLayersRequest.new,
        );
        expect(resolved, isA<LiteRtLmResolvedGpuLayersResponse>());

        final gpuSupport = await _sendRequest(
          worker.sendPort,
          LiteRtLmGpuSupportRequest.new,
        );
        expect(gpuSupport, isA<LiteRtLmGpuSupportResponse>());

        final systemInfo = await _sendRequest(
          worker.sendPort,
          LiteRtLmSystemInfoRequest.new,
        );
        expect(systemInfo, isA<LiteRtLmSystemInfoResponse>());
      } finally {
        await _disposeWorker(worker);
      }
    });

    test('loads model metadata without touching generation runtime', () async {
      final worker = await _spawnWorker();

      try {
        final modelLoad = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmModelLoadRequest(
            modelFile.path,
            const ModelParams(preferredBackend: GpuBackend.cpu),
            sendPort,
          ),
        );
        expect(modelLoad, isA<LiteRtLmHandleResponse>());
        final modelHandle = (modelLoad as LiteRtLmHandleResponse).handle;

        final contextCreate = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmContextCreateRequest(
            modelHandle,
            const ModelParams(contextSize: 2048),
            sendPort,
          ),
        );
        expect(contextCreate, isA<LiteRtLmHandleResponse>());
        final contextHandle = (contextCreate as LiteRtLmHandleResponse).handle;

        final contextSize = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmGetContextSizeRequest(contextHandle, sendPort),
        );
        expect(
          contextSize,
          isA<LiteRtLmGetContextSizeResponse>().having(
            (response) => response.size,
            'size',
            2048,
          ),
        );

        final metadata = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmMetadataRequest(modelHandle, sendPort),
        );
        expect(
          metadata,
          isA<LiteRtLmMetadataResponse>().having(
            (response) => response.metadata,
            'metadata',
            containsPair('general.file_type', 'litertlm'),
          ),
        );

        final template = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmChatTemplateRequest(
            modelHandle,
            const [
              {'role': 'user', 'content': 'hello'},
            ],
            null,
            true,
            sendPort,
          ),
        );
        expect(
          template,
          isA<LiteRtLmChatTemplateResponse>().having(
            (response) => response.result,
            'result',
            allOf(contains('hello'), contains('assistant')),
          ),
        );

        final multimodalTemplate = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmChatTemplateRequest(
            modelHandle,
            const [
              {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': 'describe this'},
                  {'type': 'image'},
                ],
              },
            ],
            null,
            true,
            sendPort,
          ),
        );
        expect(
          multimodalTemplate,
          isA<LiteRtLmErrorResponse>()
              .having((response) => response.kind, 'kind', 'unsupported')
              .having(
                (response) => response.message,
                'message',
                contains('multimodal chat-template content'),
              ),
        );

        final clearLora = await _sendRequest(
          worker.sendPort,
          (sendPort) =>
              LiteRtLmLoraRequest(contextHandle, 'clear', sendPort: sendPort),
        );
        expect(
          clearLora,
          isA<LiteRtLmErrorResponse>().having(
            (response) => response.kind,
            'kind',
            'unsupported',
          ),
        );

        final specialDetokenize = await _sendRequest(
          worker.sendPort,
          (sendPort) =>
              LiteRtLmDetokenizeRequest(modelHandle, const [1], true, sendPort),
        );
        expect(
          specialDetokenize,
          isA<LiteRtLmErrorResponse>().having(
            (response) => response.kind,
            'kind',
            'unsupported',
          ),
        );

        for (final request in <LiteRtLmWorkerRequest Function(SendPort)>[
          (sendPort) =>
              LiteRtLmMultimodalContextFreeRequest(contextHandle, sendPort),
          (sendPort) => LiteRtLmSupportsVisionRequest(contextHandle, sendPort),
          (sendPort) => LiteRtLmSupportsAudioRequest(contextHandle, sendPort),
        ]) {
          final response = await _sendRequest(worker.sendPort, request);
          expect(
            response,
            isA<LiteRtLmErrorResponse>().having(
              (response) => response.kind,
              'kind',
              'unsupported',
            ),
          );
        }

        final generate = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmGenerateRequest(
            contextHandle,
            'hello',
            const GenerationParams(grammar: 'root ::= "x"'),
            sendPort,
          ),
        );
        expect(
          generate,
          isA<LiteRtLmErrorResponse>().having(
            (response) => response.kind,
            'kind',
            'unsupported',
          ),
        );

        final freeModel = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmModelFreeRequest(modelHandle, sendPort),
        );
        expect(freeModel, isA<LiteRtLmDoneResponse>());
      } finally {
        await _disposeWorker(worker);
      }
    });

    test('returns typed error responses for invalid handles', () async {
      final worker = await _spawnWorker();

      try {
        final contextCreate = await _sendRequest(
          worker.sendPort,
          (sendPort) =>
              LiteRtLmContextCreateRequest(-1, const ModelParams(), sendPort),
        );
        expect(
          contextCreate,
          isA<LiteRtLmErrorResponse>().having(
            (response) => response.kind,
            'kind',
            'state',
          ),
        );

        final tokenize = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmTokenizeRequest(999, 'text', true, sendPort),
        );
        expect(tokenize, isA<LiteRtLmErrorResponse>());

        final detokenize = await _sendRequest(
          worker.sendPort,
          (sendPort) =>
              LiteRtLmDetokenizeRequest(999, const <int>[1], false, sendPort),
        );
        expect(detokenize, isA<LiteRtLmErrorResponse>());
      } finally {
        await _disposeWorker(worker);
      }
    });

    test('routes successful detokenize and LoRA service responses', () async {
      final service = _TokenAndLoraLiteRtLmService();
      final worker = await _startWorkerInCurrentIsolate(service);

      try {
        final detokenize = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmDetokenizeRequest(
            1,
            const <int>[10, 11],
            false,
            sendPort,
          ),
        );
        expect(
          detokenize,
          isA<LiteRtLmDetokenizeResponse>().having(
            (response) => response.text,
            'text',
            'decoded text',
          ),
        );

        final lora = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmLoraRequest(
            2,
            'set',
            path: 'adapter.bin',
            scale: 0.5,
            sendPort: sendPort,
          ),
        );
        expect(lora, isA<LiteRtLmDoneResponse>());
        expect(service.lastLoraContextHandle, 2);
        expect(service.lastLoraPath, 'adapter.bin');
        expect(service.lastLoraScale, 0.5);
        expect(service.lastLoraOp, 'set');
      } finally {
        await _disposeWorker(worker);
      }
    });

    test(
      'serializes regular requests while a service call is pending',
      () async {
        final service = _BlockingLiteRtLmService();
        final worker = await _startWorkerInCurrentIsolate(service);

        try {
          final tokenizeFuture = _sendRequest(
            worker.sendPort,
            (sendPort) => LiteRtLmTokenizeRequest(1, 'hello', true, sendPort),
          );
          await service.tokenizeStarted.future;

          final backendInfoFuture = _sendRequest(
            worker.sendPort,
            LiteRtLmBackendInfoRequest.new,
          );
          await expectLater(
            backendInfoFuture.timeout(const Duration(milliseconds: 25)),
            throwsA(isA<TimeoutException>()),
          );

          service.releaseTokenize();
          expect(await tokenizeFuture, isA<LiteRtLmTokenizeResponse>());
          expect(await backendInfoFuture, isA<LiteRtLmBackendInfoResponse>());
        } finally {
          await _disposeWorker(worker);
        }
      },
    );

    test('returns done when performance context is absent', () async {
      final service = _NoPerfLiteRtLmService();
      final worker = await _startWorkerInCurrentIsolate(service);

      try {
        final missingPerf = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmPerformanceContextRequest(1, sendPort),
        );
        expect(missingPerf, isA<LiteRtLmDoneResponse>());
      } finally {
        await _disposeWorker(worker);
      }
    });

    test('rejects overlapping generation requests immediately', () async {
      final service = _BlockingLiteRtLmService();
      final worker = await _startWorkerInCurrentIsolate(service);

      try {
        final firstGeneration = _collectGenerationResponses(
          worker.sendPort,
          (sendPort) => LiteRtLmGenerateRequest(
            1,
            'first',
            const GenerationParams(),
            sendPort,
          ),
        );
        await service.generateStarted.future;

        final secondGeneration = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmGenerateRequest(
            1,
            'second',
            const GenerationParams(),
            sendPort,
          ),
        );
        expect(
          secondGeneration,
          isA<LiteRtLmErrorResponse>()
              .having((response) => response.kind, 'kind', 'state')
              .having(
                (response) => response.message,
                'message',
                contains('already in progress'),
              ),
        );

        service.releaseGeneration();
        expect(await firstGeneration, contains(isA<LiteRtLmDoneResponse>()));
      } finally {
        await _disposeWorker(worker);
      }
    });

    test(
      'handles cancellation while generation owns the service queue',
      () async {
        final service = _BlockingLiteRtLmService();
        final worker = await _startWorkerInCurrentIsolate(service);

        try {
          final generationFuture = _collectGenerationResponses(
            worker.sendPort,
            (sendPort) => LiteRtLmGenerateRequest(
              1,
              'hello',
              const GenerationParams(),
              sendPort,
            ),
          );
          await service.generateStarted.future;

          final cancelResponse = await _sendRequest(
            worker.sendPort,
            LiteRtLmCancelGenerationRequest.new,
          ).timeout(const Duration(milliseconds: 100));
          expect(cancelResponse, isA<LiteRtLmDoneResponse>());
          expect(service.cancelCount, 1);

          service.releaseGeneration();
          expect(await generationFuture, contains(isA<LiteRtLmDoneResponse>()));
        } finally {
          await _disposeWorker(worker);
        }
      },
    );

    test('cancels accepted generation before it starts when queued', () async {
      final service = _BlockingLiteRtLmService();
      final worker = await _startWorkerInCurrentIsolate(service);

      try {
        final tokenizeFuture = _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmTokenizeRequest(1, 'hello', true, sendPort),
        );
        await service.tokenizeStarted.future;

        final generationFuture = _collectGenerationResponses(
          worker.sendPort,
          (sendPort) => LiteRtLmGenerateRequest(
            1,
            'queued',
            const GenerationParams(),
            sendPort,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final cancelResponse = await _sendRequest(
          worker.sendPort,
          LiteRtLmCancelGenerationRequest.new,
        ).timeout(const Duration(milliseconds: 100));
        expect(cancelResponse, isA<LiteRtLmDoneResponse>());

        service.releaseTokenize();
        expect(await tokenizeFuture, isA<LiteRtLmTokenizeResponse>());
        expect(await generationFuture, contains(isA<LiteRtLmDoneResponse>()));
        expect(service.generateCount, 0);
      } finally {
        await _disposeWorker(worker);
      }
    });

    test('batches and flushes generation token responses', () async {
      final service = _StreamingLiteRtLmService(const [
        [1],
        [2],
        [3],
      ]);
      final worker = await _startWorkerInCurrentIsolate(service);

      try {
        final responses = await _collectGenerationResponses(
          worker.sendPort,
          (sendPort) => LiteRtLmGenerateRequest(
            1,
            'hello',
            const GenerationParams(
              streamBatchTokenThreshold: 10,
              streamBatchByteThreshold: 10,
            ),
            sendPort,
          ),
        );

        expect(
          responses.whereType<LiteRtLmTokenResponse>().map(
            (response) => response.bytes,
          ),
          equals([
            [1],
            [2, 3],
          ]),
        );
        expect(responses.last, isA<LiteRtLmDoneResponse>());
      } finally {
        await _disposeWorker(worker);
      }
    });

    test('reports generation failures as typed worker errors', () async {
      final service = _ThrowingGenerationLiteRtLmService();
      final worker = await _startWorkerInCurrentIsolate(service);

      try {
        final responses = await _collectGenerationResponses(
          worker.sendPort,
          (sendPort) => LiteRtLmGenerateRequest(
            1,
            'hello',
            const GenerationParams(),
            sendPort,
          ),
        );

        expect(
          responses.single,
          isA<LiteRtLmErrorResponse>()
              .having((response) => response.kind, 'kind', 'state')
              .having(
                (response) => response.message,
                'message',
                contains('generation failed'),
              ),
        );
      } finally {
        await _disposeWorker(worker);
      }
    });

    test(
      'skips native dispose when an in-flight request has not settled',
      () async {
        final service = _DisposeTrackingBlockingService();
        final worker = await _startWorkerInCurrentIsolate(
          service,
          disposeTimeout: const Duration(milliseconds: 50),
        );

        final generationPort = ReceivePort();
        try {
          worker.sendPort.send(
            LiteRtLmGenerateRequest(
              1,
              'hello',
              const GenerationParams(),
              generationPort.sendPort,
            ),
          );
          await service.generateStarted.future;

          final disposePort = ReceivePort();
          worker.sendPort.send(LiteRtLmDisposeRequest(disposePort.sendPort));
          final ack = await disposePort.first.timeout(
            const Duration(seconds: 2),
          );
          disposePort.close();

          expect(ack, isA<LiteRtLmDoneResponse>());
          // The blocking generation never settled, so the worker must not
          // delete native handles out from under the in-flight native call.
          expect(service.disposeCalled, isFalse);
        } finally {
          generationPort.close();
        }
      },
    );

    test(
      'disposes native resources when the in-flight request settles',
      () async {
        final service = _DisposeTrackingStreamingService();
        final worker = await _startWorkerInCurrentIsolate(service);

        final responses = await _collectGenerationResponses(
          worker.sendPort,
          (sendPort) => LiteRtLmGenerateRequest(
            1,
            'hello',
            const GenerationParams(),
            sendPort,
          ),
        );
        expect(responses.last, isA<LiteRtLmDoneResponse>());

        final disposePort = ReceivePort();
        worker.sendPort.send(LiteRtLmDisposeRequest(disposePort.sendPort));
        await disposePort.first.timeout(const Duration(seconds: 2));
        disposePort.close();

        expect(service.disposeCalled, isTrue);
      },
    );

    test('routes performance and multimodal capability responses', () async {
      final service = _FeatureLiteRtLmService();
      final worker = await _startWorkerInCurrentIsolate(service);

      try {
        final perf = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmPerformanceContextRequest(9, sendPort),
        );
        expect(
          perf,
          isA<LiteRtLmPerformanceContextResponse>()
              .having((response) => response.loadMs, 'loadMs', 1.0)
              .having((response) => response.promptEvalMs, 'promptEvalMs', 2.0)
              .having((response) => response.evalMs, 'evalMs', 3.0)
              .having((response) => response.sampleMs, 'sampleMs', 4.0)
              .having(
                (response) => response.promptEvalTokens,
                'promptEvalTokens',
                5,
              )
              .having((response) => response.evalTokens, 'evalTokens', 6)
              .having((response) => response.sampleCount, 'sampleCount', 7)
              .having((response) => response.reusedGraphs, 'reusedGraphs', 8),
        );

        final multimodalCreate = await _sendRequest(
          worker.sendPort,
          (sendPort) =>
              LiteRtLmMultimodalContextCreateRequest(1, 'mmproj.bin', sendPort),
        );
        expect(
          multimodalCreate,
          isA<LiteRtLmHandleResponse>().having(
            (response) => response.handle,
            'handle',
            42,
          ),
        );

        final vision = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmSupportsVisionRequest(42, sendPort),
        );
        final audio = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmSupportsAudioRequest(42, sendPort),
        );
        expect(vision, isTrue);
        expect(audio, isFalse);

        final multimodalFree = await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmMultimodalContextFreeRequest(42, sendPort),
        );
        expect(multimodalFree, isA<LiteRtLmDoneResponse>());
        expect(service.freeMultimodalCount, 1);

        final systemInfo = await _sendRequest(
          worker.sendPort,
          LiteRtLmSystemInfoRequest.new,
        );
        expect(
          systemInfo,
          isA<LiteRtLmSystemInfoResponse>()
              .having((response) => response.totalVram, 'totalVram', 2048)
              .having((response) => response.freeVram, 'freeVram', 512),
        );
      } finally {
        await _disposeWorker(worker);
      }
    });
  });
}

Future<({Isolate isolate, SendPort sendPort})> _spawnWorker() async {
  final receivePort = ReceivePort();
  final isolate = await Isolate.spawn(
    liteRtLmWorkerEntry,
    receivePort.sendPort,
  );
  final sendPort = await receivePort.first as SendPort;
  sendPort.send(LiteRtLmWorkerHandshake(LlamaLogLevel.warn));
  return (isolate: isolate, sendPort: sendPort);
}

Future<({Isolate? isolate, SendPort sendPort})> _startWorkerInCurrentIsolate(
  LiteRtLmService service, {
  Duration disposeTimeout = const Duration(seconds: 5),
}) async {
  final receivePort = ReceivePort();
  runLiteRtLmWorkerForTesting(
    receivePort.sendPort,
    service,
    exitOnDispose: false,
    disposeTimeout: disposeTimeout,
  );
  final sendPort = await receivePort.first as SendPort;
  receivePort.close();
  sendPort.send(LiteRtLmWorkerHandshake(LlamaLogLevel.warn));
  return (isolate: null, sendPort: sendPort);
}

Future<dynamic> _sendRequest(
  SendPort workerSendPort,
  LiteRtLmWorkerRequest Function(SendPort sendPort) buildRequest,
) async {
  final responsePort = ReceivePort();
  workerSendPort.send(buildRequest(responsePort.sendPort));
  final response = await responsePort.first;
  responsePort.close();
  return response;
}

Future<List<Object?>> _collectGenerationResponses(
  SendPort workerSendPort,
  LiteRtLmWorkerRequest Function(SendPort sendPort) buildRequest,
) async {
  final responsePort = ReceivePort();
  final responses = <Object?>[];
  workerSendPort.send(buildRequest(responsePort.sendPort));
  await for (final response in responsePort) {
    responses.add(response);
    if (response is LiteRtLmDoneResponse || response is LiteRtLmErrorResponse) {
      responsePort.close();
    }
  }
  return responses;
}

Future<void> _disposeWorker(
  ({Isolate? isolate, SendPort sendPort}) worker,
) async {
  final responsePort = ReceivePort();
  worker.sendPort.send(LiteRtLmDisposeRequest(responsePort.sendPort));
  await responsePort.first;
  responsePort.close();
  worker.isolate?.kill(priority: Isolate.immediate);
}

class _BlockingLiteRtLmService extends LiteRtLmService {
  final Completer<void> tokenizeStarted = Completer<void>();
  final Completer<void> generateStarted = Completer<void>();
  final Completer<void> _releaseTokenize = Completer<void>();
  final Completer<void> _releaseGeneration = Completer<void>();
  int generateCount = 0;
  int cancelCount = 0;

  void releaseTokenize() {
    if (!_releaseTokenize.isCompleted) {
      _releaseTokenize.complete();
    }
  }

  void releaseGeneration() {
    if (!_releaseGeneration.isCompleted) {
      _releaseGeneration.complete();
    }
  }

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text,
    bool addSpecial,
  ) async {
    if (!tokenizeStarted.isCompleted) {
      tokenizeStarted.complete();
    }
    await _releaseTokenize.future;
    return const <int>[1, 2, 3];
  }

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    generateCount += 1;
    if (!generateStarted.isCompleted) {
      generateStarted.complete();
    }
    await _releaseGeneration.future;
  }

  @override
  void cancelGeneration() {
    cancelCount += 1;
  }
}

class _TokenAndLoraLiteRtLmService extends LiteRtLmService {
  int? lastLoraContextHandle;
  String? lastLoraPath;
  double? lastLoraScale;
  String? lastLoraOp;

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens,
    bool special,
  ) async {
    return 'decoded text';
  }

  @override
  void handleLora(int contextHandle, String? path, double? scale, String op) {
    lastLoraContextHandle = contextHandle;
    lastLoraPath = path;
    lastLoraScale = scale;
    lastLoraOp = op;
  }
}

class _NoPerfLiteRtLmService extends LiteRtLmService {
  @override
  BackendPerfContextData? getPerformanceContext(int contextHandle) {
    return null;
  }
}

class _StreamingLiteRtLmService extends LiteRtLmService {
  _StreamingLiteRtLmService(this.chunks);

  final List<List<int>> chunks;

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    for (final chunk in chunks) {
      yield chunk;
    }
  }
}

class _ThrowingGenerationLiteRtLmService extends LiteRtLmService {
  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    throw StateError('generation failed');
  }
}

class _DisposeTrackingBlockingService extends LiteRtLmService {
  final Completer<void> generateStarted = Completer<void>();
  final Completer<void> _releaseGeneration = Completer<void>();
  bool disposeCalled = false;

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    if (!generateStarted.isCompleted) {
      generateStarted.complete();
    }
    // Block forever; cancellation does not release this in the test, so the
    // worker's dispose wait must time out.
    await _releaseGeneration.future;
  }

  @override
  void cancelGeneration() {}

  @override
  void dispose() {
    disposeCalled = true;
  }
}

class _DisposeTrackingStreamingService extends LiteRtLmService {
  bool disposeCalled = false;

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    yield const [1];
  }

  @override
  void dispose() {
    disposeCalled = true;
  }
}

class _FeatureLiteRtLmService extends LiteRtLmService {
  int freeMultimodalCount = 0;

  @override
  BackendPerfContextData? getPerformanceContext(int contextHandle) {
    return const BackendPerfContextData(
      loadMs: 1.0,
      promptEvalMs: 2.0,
      evalMs: 3.0,
      sampleMs: 4.0,
      promptEvalTokens: 5,
      evalTokens: 6,
      sampleCount: 7,
      reusedGraphs: 8,
    );
  }

  @override
  int createMultimodalContext(int modelHandle, String mmProjPath) {
    return 42;
  }

  @override
  void freeMultimodalContext(int mmContextHandle) {
    freeMultimodalCount += 1;
  }

  @override
  bool supportsVision(int mmContextHandle) => true;

  @override
  bool supportsAudio(int mmContextHandle) => false;

  @override
  ({int total, int free}) getVramInfo() => (total: 2048, free: 512);
}
