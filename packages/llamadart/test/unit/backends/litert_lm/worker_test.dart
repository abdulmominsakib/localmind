@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:ffi';
import 'dart:isolate';

import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_embedding.dart';
import 'package:llamadart/src/backends/litert_lm/worker.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../support/suite_system_temp.dart';

void main() {
  useSuiteSystemTemp();

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

  for (final mode in [
    'pending',
    'safe-error',
    'quarantine',
    'cancel-failure',
    'dispose-cancel-failure',
    'cleanup-failure',
    'backend-quarantine',
  ]) {
    test('native fixture worker settlement: $mode', () async {
      final path =
          '${tempDir.path}/conversation.${Platform.isMacOS ? 'dylib' : 'so'}';
      final build = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        'test/fixtures/litert_lm/c_api_v1_conversation.c',
        '-o',
        path,
      ]);
      expect(build.exitCode, 0, reason: '${build.stderr}');
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          '--packages=.dart_tool/package_config.json',
          'test/fixtures/litert_lm_worker_settlement.dart',
          mode,
          path,
        ],
        environment: {'LITERT_SETTLEMENT_LIBRARY': path},
      ).timeout(const Duration(seconds: 20));
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('case $mode passed'));
    }, testOn: 'mac-os || linux');
  }

  for (final operation in ['contextFree', 'modelFree', 'dispose']) {
    test('$operation announces native teardown only after earlier native '
        'work settles', () async {
      final service = _TeardownLiteRtLmService();
      final worker = await _startWorkerInCurrentIsolate(service);
      final teardownPort = ReceivePort();
      final responses = <Object?>[];
      final done = Completer<void>();
      teardownPort.listen((response) {
        responses.add(response);
        if (response is LiteRtLmDoneResponse ||
            response is LiteRtLmErrorResponse) {
          done.complete();
        }
      });
      // Port order shows whether the notice preceded the native call.
      service.teardownObserver = teardownPort.sendPort;
      try {
        final active = _sendRequest(
          worker.sendPort,
          (port) => LiteRtLmTokenizeRequest(1, 'held', false, port),
        );
        await service.tokenizeStarted.future;
        worker.sendPort.send(switch (operation) {
          'contextFree' => LiteRtLmContextFreeRequest(1, teardownPort.sendPort),
          'modelFree' => LiteRtLmModelFreeRequest(1, teardownPort.sendPort),
          _ => LiteRtLmDisposeRequest(teardownPort.sendPort),
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(responses, isEmpty);
        expect(service.teardowns, isEmpty);

        service.releaseTokenize();
        await active;
        await done.future.timeout(const Duration(seconds: 2));
        expect(responses, [
          isA<LiteRtLmNativeTeardownStarted>(),
          'native $operation',
          isA<LiteRtLmDoneResponse>(),
        ]);
        expect(service.teardowns, [operation]);
      } finally {
        service.releaseTokenize();
        teardownPort.close();
        if (operation != 'dispose') await _disposeWorker(worker);
      }
    });
  }

  test('dispose never announces teardown for unsettled native work', () async {
    final service = _TeardownLiteRtLmService();
    final worker = await _startWorkerInCurrentIsolate(
      service,
      disposeTimeout: const Duration(milliseconds: 20),
    );
    final disposePort = ReceivePort();
    try {
      unawaited(
        _sendRequest(
          worker.sendPort,
          (port) => LiteRtLmTokenizeRequest(1, 'held', false, port),
        ),
      );
      await service.tokenizeStarted.future;
      worker.sendPort.send(LiteRtLmDisposeRequest(disposePort.sendPort));
      expect(
        await disposePort.first.timeout(const Duration(seconds: 2)),
        isA<LiteRtLmErrorResponse>().having(
          (response) => response.nativeSettlement,
          'nativeSettlement',
          LiteRtLmNativeSettlement.quarantined,
        ),
      );
      expect(service.teardowns, isEmpty);
    } finally {
      service.releaseTokenize();
      disposePort.close();
    }
  });

  test(
    'a queued embedding deadline preserves the active call and other requests',
    () async {
      final service = _QueuedEmbeddingService();
      final worker = await _startWorkerInCurrentIsolate(service);
      final expiredPort = ReceivePort();
      final survivorPort = ReceivePort();
      try {
        final active = _sendRequest(
          worker.sendPort,
          (port) => LiteRtLmTokenizeRequest(1, 'held', false, port),
        );
        await service.tokenizeStarted.future;
        worker.sendPort.send(
          LiteRtLmEmbedRequest(1, [], false, expiredPort.sendPort),
        );
        worker.sendPort.send(
          LiteRtLmEmbedRequest(1, [], false, survivorPort.sendPort),
        );
        expect(
          await _sendRequest(
            worker.sendPort,
            (port) =>
                LiteRtLmCancelEmbeddingRequest(expiredPort.sendPort, port),
          ),
          isA<LiteRtLmDoneResponse>(),
        );
        expect(
          service.cancelCount,
          0,
          reason: 'the active call belongs to another caller',
        );
        service.releaseTokenize();
        await active;
        expect(
          await expiredPort.first,
          isA<LiteRtLmErrorResponse>().having(
            (e) => e.message,
            'expired queue entry',
            contains('cancelled before dispatch'),
          ),
        );
        expect(await survivorPort.first, isA<LiteRtLmEmbedResponse>());
        expect(service.embedCount, 1);
        // A late deadline must not cancel a different request or retain an active target.
        expect(
          await _sendRequest(
            worker.sendPort,
            (port) =>
                LiteRtLmCancelEmbeddingRequest(survivorPort.sendPort, port),
          ),
          isA<LiteRtLmDoneResponse>(),
        );
        expect(service.cancelCount, 0);
      } finally {
        service.releaseTokenize();
        expiredPort.close();
        survivorPort.close();
        await _disposeWorker(worker);
      }
    },
  );

  test('schema admission and payload use the separate service route', () async {
    final service = _SchemaService();
    final worker = await _startWorkerInCurrentIsolate(service);
    try {
      expect(
        await _sendRequest(
          worker.sendPort,
          LiteRtLmJsonSchemaPrepareRequest.new,
        ),
        isA<LiteRtLmJsonSchemaAdmissionResponse>().having(
          (r) => r.thinking,
          'thinking',
          isFalse,
        ),
      );
      expect(service.admissions, 1);
      final responses = await _collectGenerationResponses(
        worker.sendPort,
        (port) => LiteRtLmGenerateChatRequest(
          7,
          const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'p'),
          ],
          const GenerationParams(),
          port,
          jsonSchema: '{"type":"object"}',
          enableThinking: false,
        ),
      );
      expect(service.schema, '{"type":"object"}');
      expect(service.context, 7);
      expect(
        responses.whereType<LiteRtLmTokenResponse>().expand((r) => r.bytes),
        [123, 125],
      );
      expect(responses.last, isA<LiteRtLmDoneResponse>());
      expect(service.ordinaryCalls, 0);
      // A recreated client clears the admission, so the service, not the
      // worker's stale view, decides whether thinking is allowed.
      final readmitted = await _collectGenerationResponses(
        worker.sendPort,
        (port) => LiteRtLmGenerateChatRequest(
          7,
          const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'p'),
          ],
          const GenerationParams(),
          port,
          jsonSchema: '{"type":"object"}',
          enableThinking: true,
        ),
      );
      expect(readmitted.last, isA<LiteRtLmDoneResponse>());
      expect(service.schemaCalls, 2);
      expect(service.schemaThinking, isTrue);
      service.schemaThinking = null;
      service.admitsThinking = true;
      expect(
        await _sendRequest(
          worker.sendPort,
          LiteRtLmJsonSchemaPrepareRequest.new,
        ),
        isA<LiteRtLmJsonSchemaAdmissionResponse>().having(
          (r) => r.thinking,
          'thinking',
          isTrue,
        ),
      );
      final thinking = await _collectGenerationResponses(
        worker.sendPort,
        (port) => LiteRtLmGenerateChatRequest(
          7,
          const [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'p'),
          ],
          const GenerationParams(),
          port,
          jsonSchema: '{"type":"object"}',
          enableThinking: true,
        ),
      );
      expect(thinking.last, isA<LiteRtLmDoneResponse>());
      expect(service.schemaCalls, 3);
      expect(service.schemaThinking, isTrue);
      service.rejectAdmission = true;
      expect(
        await _sendRequest(
          worker.sendPort,
          LiteRtLmJsonSchemaPrepareRequest.new,
        ),
        isA<LiteRtLmErrorResponse>().having(
          (e) => e.kind,
          'kind',
          'llamaUnsupported',
        ),
      );
    } finally {
      await _disposeWorker(worker);
    }
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

        final bundle = await _sendRequest(
          worker.sendPort,
          LiteRtLmBundleCapabilitiesRequest.new,
        );
        expect(
          bundle,
          isA<LiteRtLmBundleCapabilitiesResponse>().having(
            (response) => response.capabilities,
            'capabilities before a load',
            isNull,
          ),
        );

        final controls = await _sendRequest(
          worker.sendPort,
          LiteRtLmGenerationControlsRequest.new,
        );
        expect(
          controls,
          isA<LiteRtLmGenerationControlsResponse>().having(
            (response) => response.thinkingBudget,
            'thinking budget before a load',
            isFalse,
          ),
        );
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

    test('LiteRtLmDartLogLevelRequest leaves the logger alone without a log '
        'port', () async {
      final worker = await _startWorkerInCurrentIsolate(
        _DetokenizeLiteRtLmService(),
      );
      try {
        final response = await _sendRequest(
          worker.sendPort,
          (sendPort) =>
              LiteRtLmDartLogLevelRequest(LlamaLogLevel.debug, sendPort),
        );
        expect(response, isA<LiteRtLmDoneResponse>());
        expect(LlamaLogger.instance.level, LlamaLogLevel.none);
      } finally {
        await _disposeWorker(worker);
      }
    });

    test('routes the bundle capabilities of the loaded model', () async {
      final worker = await _startWorkerInCurrentIsolate(
        LiteRtLmService(
          readBundleCapabilities: (_) =>
              (vision: true, audio: false, speculativeDecoding: true),
        ),
      );
      try {
        await _sendRequest(
          worker.sendPort,
          (sendPort) => LiteRtLmModelLoadRequest(
            modelFile.path,
            const ModelParams(preferredBackend: GpuBackend.cpu),
            sendPort,
          ),
        );
        final bundle = await _sendRequest(
          worker.sendPort,
          LiteRtLmBundleCapabilitiesRequest.new,
        );
        expect(
          bundle,
          isA<LiteRtLmBundleCapabilitiesResponse>().having(
            (response) => response.capabilities,
            'capabilities',
            (vision: true, audio: false, speculativeDecoding: true),
          ),
        );
      } finally {
        await _disposeWorker(worker);
      }
    });

    test('routes successful detokenize service responses', () async {
      final service = _DetokenizeLiteRtLmService();
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
      } finally {
        await _disposeWorker(worker);
      }
    });

    test('routes runtime prompt tokenize requests to the service', () async {
      final worker = await _startWorkerInCurrentIsolate(
        _RuntimePromptLiteRtLmService(),
      );

      try {
        for (final (runtimePrompt, tokens) in [
          (false, [10]),
          (true, [20]),
        ]) {
          expect(
            await _sendRequest(
              worker.sendPort,
              (sendPort) => LiteRtLmTokenizeRequest(
                1,
                '<bos>hi',
                false,
                sendPort,
                runtimePrompt: runtimePrompt,
              ),
            ),
            isA<LiteRtLmTokenizeResponse>().having(
              (response) => response.tokens,
              'tokens',
              tokens,
            ),
          );
        }
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

    for (final embedding in [false, true]) {
      test('model load reports finish-reason support '
          '(embedding engine: $embedding)', () async {
        // The fake service stands in for a qualified embedding target on
        // every test host.
        debugLiteRtLmAbiOverride = Abi.macosArm64;
        addTearDown(() => debugLiteRtLmAbiOverride = null);
        final service = _FinishReasonLiteRtLmService();
        final worker = await _startWorkerInCurrentIsolate(service);

        try {
          final response = await _sendRequest(
            worker.sendPort,
            (sendPort) => LiteRtLmModelLoadRequest(
              modelFile.path,
              ModelParams(
                preferredBackend: GpuBackend.cpu,
                liteRtLmEmbeddingEngine: embedding,
              ),
              sendPort,
            ),
          );

          expect(
            response,
            isA<LiteRtLmHandleResponse>().having(
              (response) => response.reportsFinishReasons,
              'reportsFinishReasons',
              !embedding,
            ),
          );
        } finally {
          await _disposeWorker(worker);
        }
      });
    }

    for (final chat in [false, true]) {
      for (final limit in [null, ...BackendGenerationLimit.values]) {
        test(
          '${chat ? 'chat' : 'raw'} generation done carries limit $limit',
          () async {
            final service = _FinishReasonLiteRtLmService()..limit = limit;
            final worker = await _startWorkerInCurrentIsolate(service);

            try {
              final responses = await _collectGenerationResponses(
                worker.sendPort,
                (sendPort) => chat
                    ? LiteRtLmGenerateChatRequest(
                        1,
                        const [
                          LlamaChatMessage.fromText(
                            role: LlamaChatRole.user,
                            text: 'hi',
                          ),
                        ],
                        const GenerationParams(),
                        sendPort,
                      )
                    : LiteRtLmGenerateRequest(
                        1,
                        'hi',
                        const GenerationParams(),
                        sendPort,
                      ),
              );

              expect(
                responses.last,
                isA<LiteRtLmDoneResponse>().having(
                  (response) => response.generationLimit,
                  'generationLimit',
                  limit,
                ),
              );
            } finally {
              await _disposeWorker(worker);
            }
          },
        );
      }
    }

    test('forwards chat template kwargs to native chat generation', () async {
      final service = _ChatKwargsCapturingService();
      final worker = await _startWorkerInCurrentIsolate(service);

      try {
        final responses = await _collectGenerationResponses(
          worker.sendPort,
          (sendPort) => LiteRtLmGenerateChatRequest(
            1,
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
            ],
            const GenerationParams(),
            sendPort,
            chatTemplateKwargs: const {
              'source_lang_code': 'en',
              'target_lang_code': 'ko',
            },
          ),
        );

        expect(responses.last, isA<LiteRtLmDoneResponse>());
        expect(service.chatTemplateKwargs, {
          'source_lang_code': 'en',
          'target_lang_code': 'ko',
        });
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
        await disposePort
            .firstWhere(
              (response) => response is! LiteRtLmNativeTeardownStarted,
            )
            .timeout(const Duration(seconds: 2));
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
  final response = await responsePort.firstWhere(
    (response) => response is! LiteRtLmNativeTeardownStarted,
  );
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
  await responsePort.firstWhere(
    (response) => response is! LiteRtLmNativeTeardownStarted,
  );
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

class _TeardownLiteRtLmService extends _BlockingLiteRtLmService {
  final List<String> teardowns = [];
  SendPort? teardownObserver;

  void _record(String operation) {
    teardowns.add(operation);
    teardownObserver?.send('native $operation');
  }

  @override
  void freeContext(int contextHandle) => _record('contextFree');

  @override
  void freeModel(int modelHandle) => _record('modelFree');

  @override
  void dispose() => _record('dispose');
}

class _DetokenizeLiteRtLmService extends LiteRtLmService {
  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens,
    bool special,
  ) async {
    return 'decoded text';
  }
}

class _RuntimePromptLiteRtLmService extends LiteRtLmService {
  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text,
    bool addSpecial,
  ) async => const [10];

  @override
  Future<List<int>> tokenizeRuntimePrompt(
    int modelHandle,
    String prompt,
  ) async => const [20];
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

class _FinishReasonLiteRtLmService extends LiteRtLmService {
  BackendGenerationLimit? limit;
  BackendGenerationLimit? _last;

  @override
  bool reportsFinishReasons() => true;

  @override
  BackendGenerationLimit? get lastGenerationLimit => _last;

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    yield const [1];
    _last = limit;
  }

  @override
  Stream<List<int>> generateChat(
    int contextHandle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    List<Map<String, dynamic>>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    yield const [1];
    _last = limit;
  }
}

class _ChatKwargsCapturingService extends LiteRtLmService {
  Map<String, dynamic>? chatTemplateKwargs;

  @override
  Stream<List<int>> generateChat(
    int contextHandle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    List<Map<String, dynamic>>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    this.chatTemplateKwargs = chatTemplateKwargs;
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
  ({int total, int free}) getVramInfo() => (total: 2048, free: 512);
}

class _QueuedEmbeddingService extends _BlockingLiteRtLmService {
  int embedCount = 0;

  @override
  Future<List<List<double>>> embed(
    int contextHandle,
    List<List<LiteRtLmEmbeddingPart>> inputs, {
    required bool normalize,
  }) async {
    embedCount++;
    return [
      [3, 4],
    ];
  }
}

class _SchemaService extends LiteRtLmService {
  int admissions = 0;
  int schemaCalls = 0;
  int ordinaryCalls = 0;
  int? context;
  String? schema;
  bool? schemaThinking;
  bool rejectAdmission = false;
  bool admitsThinking = false;

  @override
  Future<void> prepareJsonSchemaChat() async {
    admissions++;
    if (rejectAdmission) {
      throw LlamaUnsupportedException('provider unavailable');
    }
  }

  @override
  bool get supportsJsonSchemaChatThinking => admitsThinking;

  @override
  Stream<List<int>> generateJsonSchemaChat(
    int contextHandle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    required String jsonSchema,
    bool enableThinking = false,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    schemaCalls++;
    context = contextHandle;
    schema = jsonSchema;
    schemaThinking = enableThinking;
    yield [123, 125];
  }

  @override
  Stream<List<int>> generateChat(
    int contextHandle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    List<Map<String, dynamic>>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    ordinaryCalls++;
  }
}
