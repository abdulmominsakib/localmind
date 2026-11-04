@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_backend.dart';
import 'package:llamadart/src/backends/litert_lm/worker_messages.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/config/gpu_backend.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File modelFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('llamadart_litert_test_');
    modelFile = File('${tempDir.path}/model.litertlm');
    await modelFile.writeAsString('fake model');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('implements backend diagnostics contracts', () {
    final backend = LiteRtLmBackend();

    expect(backend, isA<LlamaBackend>());
    expect(backend, isA<BackendAvailability>());
    expect(backend, isA<BackendRuntimeDiagnostics>());
    expect(backend, isA<BackendPerformanceDiagnostics>());
    expect(backend, isA<BackendEmbeddingsSupport>());
    expect(backend, isA<BackendStatePersistenceSupport>());
    expect(backend, isA<BackendNativeChatGeneration>());
    expect(backend.supportsUrlLoading, isFalse);
    expect((backend as BackendEmbeddingsSupport).supportsEmbeddings, isFalse);
    expect(
      (backend as BackendStatePersistenceSupport).supportsStatePersistence,
      isFalse,
    );
    expect(
      (backend as BackendNativeChatGeneration).supportsNativeChatGeneration,
      isTrue,
    );
  });

  test('reports platform default diagnostics before model load', () async {
    final backend = LiteRtLmBackend();

    try {
      final expectedBackend = _expectedAutoLiteRtLmBackend();
      expect(await backend.getBackendName(), 'LiteRT-LM $expectedBackend');
      expect(
        await backend.getResolvedGpuLayers(),
        expectedBackend == 'cpu' ? 0 : ModelParams.maxGpuLayers,
      );
    } finally {
      await backend.dispose();
    }
  });

  test('coalesces concurrent worker startup diagnostics', () async {
    final backend = LiteRtLmBackend();

    try {
      final expectedBackend = _expectedAutoLiteRtLmBackend();
      final results = await Future.wait<Object?>([
        backend.getBackendName(),
        backend.getAvailableBackends(),
        backend.getResolvedGpuLayers(),
        backend.isGpuSupported(),
      ]);

      expect(results[0], 'LiteRT-LM $expectedBackend');
      expect(results[1], contains('cpu'));
      expect(
        results[2],
        expectedBackend == 'cpu' ? 0 : ModelParams.maxGpuLayers,
      );
      expect(results[3], Platform.isMacOS || Platform.isAndroid);
    } finally {
      await backend.dispose();
    }
  });

  test(
    'reports direct preferred backend diagnostics before model load',
    () async {
      final backend = LiteRtLmBackend(preferredBackend: ' CPU ');

      try {
        expect(await backend.getBackendName(), 'LiteRT-LM cpu');
        expect(await backend.getResolvedGpuLayers(), 0);
      } finally {
        await backend.dispose();
      }
    },
  );

  test('rejects unavailable direct preferred backend diagnostics', () async {
    final backend = LiteRtLmBackend(preferredBackend: 'npu');

    try {
      if (Platform.isAndroid) {
        expect(await backend.getBackendName(), 'LiteRT-LM npu');
        expect(await backend.getResolvedGpuLayers(), ModelParams.maxGpuLayers);
      } else {
        await expectLater(
          backend.getBackendName(),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message.toString(),
              'message',
              contains('not available'),
            ),
          ),
        );
      }
    } finally {
      await backend.dispose();
    }
  });

  test('rejects invalid direct preferred backend diagnostics', () async {
    final backend = LiteRtLmBackend(preferredBackend: 'directml');

    try {
      await expectLater(
        backend.getBackendName(),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message.toString(),
            'message',
            contains('must be cpu, gpu, or npu'),
          ),
        ),
      );
    } finally {
      await backend.dispose();
    }
  });

  test('loads local litertlm model and exposes metadata', () async {
    final backend = LiteRtLmBackend();

    try {
      final handle = await backend.modelLoad(
        modelFile.path,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );
      final contextHandle = await backend.contextCreate(
        handle,
        const ModelParams(),
      );

      expect(handle, 1);
      expect(contextHandle, 1);
      expect(backend.isReady, isTrue);
      expect(await backend.getContextSize(contextHandle), 4096);
      expect(await backend.getBackendName(), 'LiteRT-LM cpu');
      expect(await backend.getResolvedGpuLayers(), 0);
      expect(
        await backend.modelMetadata(handle),
        containsPair('general.file_type', 'litertlm'),
      );

      await backend.modelFree(handle);
      expect(backend.isReady, isFalse);
    } finally {
      await backend.dispose();
    }
  });

  test('invalidates stale handles after direct LiteRT-LM reload', () async {
    final backend = LiteRtLmBackend();
    final secondModelFile = File('${tempDir.path}/second.litertlm');
    await secondModelFile.writeAsString('fake model');

    try {
      final firstHandle = await backend.modelLoad(
        modelFile.path,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );
      final firstContextHandle = await backend.contextCreate(
        firstHandle,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );

      final secondHandle = await backend.modelLoad(
        secondModelFile.path,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );
      final secondContextHandle = await backend.contextCreate(
        secondHandle,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );

      expect(secondHandle, isNot(firstHandle));
      expect(secondContextHandle, isNot(firstContextHandle));
      await expectLater(backend.modelMetadata(firstHandle), throwsStateError);
      await expectLater(
        backend.getContextSize(firstContextHandle),
        throwsStateError,
      );
      await expectLater(
        backend.contextFree(firstContextHandle),
        throwsStateError,
      );
      await expectLater(backend.modelFree(firstHandle), throwsStateError);
      expect(
        await backend.modelMetadata(secondHandle),
        containsPair('general.name', 'second.litertlm'),
      );
    } finally {
      await backend.dispose();
    }
  });

  test('rejects unsupported load and llama.cpp-specific operations', () async {
    final backend = LiteRtLmBackend();
    final wrongFormat = File('${tempDir.path}/model.gguf');
    await wrongFormat.writeAsString('fake model');

    try {
      await expectLater(
        backend.modelLoad(wrongFormat.path, const ModelParams()),
        throwsArgumentError,
      );
      expect(
        () => backend.modelLoadFromUrl(
          'https://example.test/model.litertlm',
          const ModelParams(),
        ),
        throwsUnsupportedError,
      );

      final handle = await backend.modelLoad(
        modelFile.path,
        const ModelParams(),
      );
      final contextHandle = await backend.contextCreate(
        handle,
        const ModelParams(),
      );

      expect(
        () => backend.setLoraAdapter(contextHandle, 'adapter.bin', 1.0),
        throwsUnsupportedError,
      );
      expect(
        () => backend.removeLoraAdapter(contextHandle, 'adapter.bin'),
        throwsUnsupportedError,
      );
      expect(
        () => backend.clearLoraAdapters(contextHandle),
        throwsUnsupportedError,
      );
      await expectLater(
        backend.multimodalContextCreate(handle, 'mmproj.bin'),
        throwsUnsupportedError,
      );
      await expectLater(
        backend.multimodalContextFree(contextHandle),
        throwsUnsupportedError,
      );
      await expectLater(
        backend.supportsVision(contextHandle),
        throwsUnsupportedError,
      );
      await expectLater(
        backend.supportsAudio(contextHandle),
        throwsUnsupportedError,
      );
      await expectLater(
        backend.generate(
          contextHandle,
          'hello',
          const GenerationParams(grammar: 'root ::= "x"'),
        ),
        emitsError(isA<UnsupportedError>()),
      );
    } finally {
      await backend.dispose();
    }
  });

  test(
    'invalid handles fail before touching native LiteRT-LM runtime',
    () async {
      final backend = LiteRtLmBackend();

      try {
        expect(
          () => backend.contextCreate(99, const ModelParams()),
          throwsStateError,
        );
        expect(() => backend.modelMetadata(99), throwsStateError);
        expect(() => backend.getContextSize(99), throwsStateError);
      } finally {
        await backend.dispose();
      }
    },
  );

  test('free operations are no-ops before worker startup', () async {
    final backend = LiteRtLmBackend();

    await backend.contextFree(123);
    await backend.modelFree(123);

    expect(backend.isReady, isFalse);
  });

  test('rejects calls after dispose without restarting worker', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      await backend.dispose();
      await expectLater(
        backend.getBackendName(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('disposed'),
          ),
        ),
      );
      expect(worker.requests.whereType<LiteRtLmBackendInfoRequest>(), isEmpty);
    } finally {
      worker.close();
    }
  });

  test('routes tokenization APIs through the LiteRT-LM worker', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[2, 10, 11],
      detokenizeResponse: 'hello',
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      expect(await backend.tokenize(42, 'hello', addSpecial: false), [
        2,
        10,
        11,
      ]);
      expect(
        await backend.detokenize(42, const [10, 11], special: true),
        'hello',
      );

      final tokenizeRequest = worker.requests
          .whereType<LiteRtLmTokenizeRequest>()
          .single;
      expect(tokenizeRequest.modelHandle, 42);
      expect(tokenizeRequest.text, 'hello');
      expect(tokenizeRequest.addSpecial, isFalse);

      final detokenizeRequest = worker.requests
          .whereType<LiteRtLmDetokenizeRequest>()
          .single;
      expect(detokenizeRequest.modelHandle, 42);
      expect(detokenizeRequest.tokens, [10, 11]);
      expect(detokenizeRequest.special, isTrue);
    } finally {
      await backend.dispose();
      worker.close();
    }
  });

  test('streams generated token bytes from the LiteRT-LM worker', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      generationChunks: const [
        [104, 101],
        [108, 108, 111],
      ],
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      expect(
        await backend.generate(7, 'prompt', const GenerationParams()).toList(),
        [
          [104, 101],
          [108, 108, 111],
        ],
      );

      final request = worker.requests
          .whereType<LiteRtLmGenerateRequest>()
          .single;
      expect(request.contextHandle, 7);
      expect(request.prompt, 'prompt');
      expect(request.parts, isNull);
    } finally {
      await backend.dispose();
      worker.close();
    }
  });

  test('streams native chat token bytes from the LiteRT-LM worker', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      generationChunks: const [
        [110, 97],
        [116, 105, 118, 101],
      ],
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      expect(
        await backend
            .generateChat(
              7,
              const [
                LlamaChatMessage.fromText(
                  role: LlamaChatRole.user,
                  text: 'hello',
                ),
              ],
              const GenerationParams(maxTokens: 5),
              tools: [
                ToolDefinition(
                  name: 'get_weather',
                  description: 'Get weather',
                  parameters: const [],
                  handler: (_) async => 'sunny',
                ),
              ],
              toolChoice: ToolChoice.auto,
              chatTemplateKwargs: const {'locale': 'en_CA'},
            )
            .toList(),
        [
          [110, 97],
          [116, 105, 118, 101],
        ],
      );

      final request = worker.requests
          .whereType<LiteRtLmGenerateChatRequest>()
          .single;
      expect(request.contextHandle, 7);
      expect(request.messages.single.content, 'hello');
      expect(request.params.maxTokens, 5);
      expect(request.tools?.single['function']['name'], 'get_weather');
      expect(request.toolChoice, ToolChoice.auto);
      expect(request.chatTemplateKwargs, {'locale': 'en_CA'});
    } finally {
      await backend.dispose();
      worker.close();
    }
  });

  test('maps unknown worker generation errors to generic exceptions', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      generationErrorResponse: LiteRtLmErrorResponse(
        'native failed',
        kind: 'native',
      ),
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      await expectLater(
        backend.generate(7, 'prompt', const GenerationParams()).drain<void>(),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('native failed'),
          ),
        ),
      );
    } finally {
      await backend.dispose();
      worker.close();
    }
  });

  test('rejects concurrent generation before touching worker', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      holdGeneration: true,
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      final firstDone = Completer<void>();
      final firstSubscription = backend
          .generate(1, 'first', const GenerationParams())
          .listen(
            (_) {},
            onError: firstDone.completeError,
            onDone: firstDone.complete,
          );
      await worker.generateReceived.future;

      await expectLater(
        backend.generate(1, 'second', const GenerationParams()).drain<void>(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('already in progress'),
          ),
        ),
      );
      expect(
        worker.requests.whereType<LiteRtLmGenerateRequest>(),
        hasLength(1),
      );

      worker.releaseGeneration();
      await firstDone.future.timeout(const Duration(seconds: 1));
      await firstSubscription.cancel();
    } finally {
      await backend.dispose();
      worker.close();
    }
  });

  test(
    'does not send generation after immediate stream cancellation',
    () async {
      final worker = _FakeLiteRtLmWorker(
        tokenizeResponse: const <int>[],
        detokenizeResponse: '',
      );
      final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

      try {
        final subscription = backend
            .generate(1, 'cancelled', const GenerationParams())
            .listen((_) {});

        await subscription.cancel();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(worker.requests.whereType<LiteRtLmGenerateRequest>(), isEmpty);
        expect(
          worker.requests.whereType<LiteRtLmCancelGenerationRequest>(),
          hasLength(1),
        );
      } finally {
        await backend.dispose();
        worker.close();
      }
    },
  );

  test('cancels active generation before context free', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      holdGeneration: true,
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      final firstDone = Completer<void>();
      final firstSubscription = backend
          .generate(1, 'first', const GenerationParams())
          .listen(
            (_) {},
            onError: firstDone.completeError,
            onDone: firstDone.complete,
          );
      await worker.generateReceived.future;

      await backend.contextFree(1);
      await firstDone.future.timeout(const Duration(seconds: 1));

      final cancelIndex = worker.requests.indexWhere(
        (request) => request is LiteRtLmCancelGenerationRequest,
      );
      final contextFreeIndex = worker.requests.indexWhere(
        (request) => request is LiteRtLmContextFreeRequest,
      );
      expect(cancelIndex, isNonNegative);
      expect(contextFreeIndex, isNonNegative);
      expect(cancelIndex, lessThan(contextFreeIndex));
      expect(
        worker.requests.whereType<LiteRtLmGenerateRequest>(),
        hasLength(1),
      );

      await firstSubscription.cancel();
    } finally {
      await backend.dispose();
      worker.close();
    }
  });

  test('cancels active generation before model free', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      holdGeneration: true,
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      final firstDone = Completer<void>();
      final firstSubscription = backend
          .generate(1, 'first', const GenerationParams())
          .listen(
            (_) {},
            onError: firstDone.completeError,
            onDone: firstDone.complete,
          );
      await worker.generateReceived.future;

      await backend.modelFree(1);
      await firstDone.future.timeout(const Duration(seconds: 1));

      final cancelIndex = worker.requests.indexWhere(
        (request) => request is LiteRtLmCancelGenerationRequest,
      );
      final modelFreeIndex = worker.requests.indexWhere(
        (request) => request is LiteRtLmModelFreeRequest,
      );
      expect(cancelIndex, isNonNegative);
      expect(modelFreeIndex, isNonNegative);
      expect(cancelIndex, lessThan(modelFreeIndex));
      expect(backend.isReady, isFalse);
      expect(
        worker.requests.whereType<LiteRtLmGenerateRequest>(),
        hasLength(1),
      );

      await firstSubscription.cancel();
    } finally {
      await backend.dispose();
      worker.close();
    }
  });

  test('cancels active generation before direct model reload', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      holdGeneration: true,
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      final firstDone = Completer<void>();
      final firstSubscription = backend
          .generate(1, 'first', const GenerationParams())
          .listen(
            (_) {},
            onError: firstDone.completeError,
            onDone: firstDone.complete,
          );
      await worker.generateReceived.future;

      expect(
        await backend.modelLoad(
          modelFile.path,
          const ModelParams(preferredBackend: GpuBackend.cpu),
        ),
        1,
      );
      await firstDone.future.timeout(const Duration(seconds: 1));

      final cancelIndex = worker.requests.indexWhere(
        (request) => request is LiteRtLmCancelGenerationRequest,
      );
      final loadIndex = worker.requests.indexWhere(
        (request) => request is LiteRtLmModelLoadRequest,
      );
      expect(cancelIndex, isNonNegative);
      expect(loadIndex, isNonNegative);
      expect(cancelIndex, lessThan(loadIndex));
      expect(backend.isReady, isTrue);
      expect(
        worker.requests.whereType<LiteRtLmGenerateRequest>(),
        hasLength(1),
      );

      await firstSubscription.cancel();
    } finally {
      await backend.dispose();
      worker.close();
    }
  });

  test(
    'routes chat template application through the LiteRT-LM worker',
    () async {
      final worker = _FakeLiteRtLmWorker(
        tokenizeResponse: const <int>[],
        detokenizeResponse: '',
        chatTemplateResponse: 'templated',
      );
      final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

      try {
        expect(
          await backend.applyChatTemplate(
            42,
            const [
              {'role': 'user', 'content': 'hello'},
            ],
            customTemplate: 'custom',
            addAssistant: false,
          ),
          'templated',
        );

        final request = worker.requests
            .whereType<LiteRtLmChatTemplateRequest>()
            .single;
        expect(request.modelHandle, 42);
        expect(request.messages.single, containsPair('content', 'hello'));
        expect(request.customTemplate, 'custom');
        expect(request.addAssistant, isFalse);
      } finally {
        await backend.dispose();
        worker.close();
      }
    },
  );

  test('routes diagnostics through the LiteRT-LM worker', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      backendInfoResponse: 'LiteRT-LM gpu',
      availableBackendsResponse: 'cpu, gpu',
      resolvedGpuLayersResponse: 999,
      gpuSupportResponse: true,
      performanceContextResponse: LiteRtLmPerformanceContextResponse(
        loadMs: 1.5,
        promptEvalMs: 2.5,
        evalMs: 3.5,
        sampleMs: 4.5,
        promptEvalTokens: 11,
        evalTokens: 22,
        sampleCount: 33,
        reusedGraphs: 44,
      ),
      vramInfoResponse: (total: 4096, free: 1024),
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      expect(await backend.getBackendName(), 'LiteRT-LM gpu');
      expect(await backend.getAvailableBackends(), 'cpu, gpu');
      expect(await backend.getResolvedGpuLayers(), 999);
      expect(await backend.isGpuSupported(), isTrue);
      expect(await backend.getVramInfo(), (total: 4096, free: 1024));

      final perf = await backend.getPerformanceContext(7);
      expect(perf, isNotNull);
      expect(perf!.loadMs, 1.5);
      expect(perf.promptEvalMs, 2.5);
      expect(perf.evalMs, 3.5);
      expect(perf.sampleMs, 4.5);
      expect(perf.promptEvalTokens, 11);
      expect(perf.evalTokens, 22);
      expect(perf.sampleCount, 33);
      expect(perf.reusedGraphs, 44);

      await backend.setLogLevel(LlamaLogLevel.debug);
      final logLevelRequest = worker.requests
          .whereType<LiteRtLmLogLevelRequest>()
          .single;
      expect(logLevelRequest.logLevel, LlamaLogLevel.debug);
    } finally {
      await backend.dispose();
      worker.close();
    }
  });

  test('rejects unexpected worker response types', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      backendInfoRawResponse: LiteRtLmDoneResponse(),
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      await expectLater(
        backend.getBackendName(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(
              'Unexpected LiteRT-LM response during backend info lookup',
            ),
          ),
        ),
      );
    } finally {
      await backend.dispose();
      worker.close();
    }
  });

  test('returns null when LiteRT-LM performance data is absent', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      expect(await backend.getPerformanceContext(7), isNull);
    } finally {
      await backend.dispose();
      worker.close();
    }
  });

  test('routes multimodal capability methods through the worker', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      multimodalHandleResponse: 77,
      supportsVisionResponse: true,
      supportsAudioResponse: false,
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      expect(await backend.multimodalContextCreate(42, 'mmproj.bin'), 77);
      await backend.multimodalContextFree(77);
      expect(await backend.supportsVision(77), isTrue);
      expect(await backend.supportsAudio(77), isFalse);

      final createRequest = worker.requests
          .whereType<LiteRtLmMultimodalContextCreateRequest>()
          .single;
      expect(createRequest.modelHandle, 42);
      expect(createRequest.mmProjPath, 'mmproj.bin');
      expect(
        worker.requests.whereType<LiteRtLmMultimodalContextFreeRequest>(),
        hasLength(1),
      );
      expect(
        worker.requests.whereType<LiteRtLmSupportsVisionRequest>(),
        hasLength(1),
      );
      expect(
        worker.requests.whereType<LiteRtLmSupportsAudioRequest>(),
        hasLength(1),
      );
    } finally {
      await backend.dispose();
      worker.close();
    }
  });
}

String _expectedAutoLiteRtLmBackend() {
  if (Platform.isAndroid || Platform.isMacOS) {
    return 'gpu';
  }
  return 'cpu';
}

class _FakeLiteRtLmWorker {
  _FakeLiteRtLmWorker({
    required this.tokenizeResponse,
    required this.detokenizeResponse,
    this.chatTemplateResponse = '',
    this.holdGeneration = false,
    this.generationChunks = const <List<int>>[],
    this.generationErrorResponse,
    this.backendInfoResponse = 'LiteRT-LM cpu',
    this.backendInfoRawResponse,
    this.availableBackendsResponse = 'cpu',
    this.resolvedGpuLayersResponse = 0,
    this.gpuSupportResponse = false,
    this.performanceContextResponse,
    this.vramInfoResponse = (total: 0, free: 0),
    this.multimodalHandleResponse,
    this.supportsVisionResponse,
    this.supportsAudioResponse,
  }) {
    _receivePort.listen(_handleMessage);
  }

  final List<int> tokenizeResponse;
  final String detokenizeResponse;
  final String chatTemplateResponse;
  final bool holdGeneration;
  final List<List<int>> generationChunks;
  final LiteRtLmErrorResponse? generationErrorResponse;
  final String backendInfoResponse;
  final Object? backendInfoRawResponse;
  final String availableBackendsResponse;
  final int resolvedGpuLayersResponse;
  final bool gpuSupportResponse;
  final LiteRtLmPerformanceContextResponse? performanceContextResponse;
  final ({int total, int free}) vramInfoResponse;
  final int? multimodalHandleResponse;
  final bool? supportsVisionResponse;
  final bool? supportsAudioResponse;
  final ReceivePort _receivePort = ReceivePort();
  final List<Object?> requests = <Object?>[];
  final Completer<LiteRtLmGenerateRequest> generateReceived =
      Completer<LiteRtLmGenerateRequest>();
  final Completer<void> _releaseGeneration = Completer<void>();

  SendPort get sendPort => _receivePort.sendPort;

  void close() {
    _receivePort.close();
  }

  void releaseGeneration() {
    if (!_releaseGeneration.isCompleted) {
      _releaseGeneration.complete();
    }
  }

  void _handleMessage(Object? message) {
    requests.add(message);
    switch (message) {
      case LiteRtLmGenerateRequest():
        if (!generateReceived.isCompleted) {
          generateReceived.complete(message);
        }
        if (generationErrorResponse != null) {
          message.sendPort.send(generationErrorResponse);
          break;
        }
        for (final chunk in generationChunks) {
          message.sendPort.send(LiteRtLmTokenResponse(chunk));
        }
        if (holdGeneration) {
          unawaited(
            _releaseGeneration.future.then(
              (_) => message.sendPort.send(LiteRtLmDoneResponse()),
            ),
          );
        } else {
          message.sendPort.send(LiteRtLmDoneResponse());
        }
      case LiteRtLmGenerateChatRequest():
        if (generationErrorResponse != null) {
          message.sendPort.send(generationErrorResponse);
          break;
        }
        for (final chunk in generationChunks) {
          message.sendPort.send(LiteRtLmTokenResponse(chunk));
        }
        if (holdGeneration) {
          unawaited(
            _releaseGeneration.future.then(
              (_) => message.sendPort.send(LiteRtLmDoneResponse()),
            ),
          );
        } else {
          message.sendPort.send(LiteRtLmDoneResponse());
        }
      case LiteRtLmModelLoadRequest():
        message.sendPort.send(LiteRtLmHandleResponse(1));
      case LiteRtLmTokenizeRequest():
        message.sendPort.send(LiteRtLmTokenizeResponse(tokenizeResponse));
      case LiteRtLmDetokenizeRequest():
        message.sendPort.send(LiteRtLmDetokenizeResponse(detokenizeResponse));
      case LiteRtLmContextFreeRequest():
        message.sendPort.send(LiteRtLmDoneResponse());
      case LiteRtLmModelFreeRequest():
        message.sendPort.send(LiteRtLmDoneResponse());
      case LiteRtLmChatTemplateRequest():
        message.sendPort.send(
          LiteRtLmChatTemplateResponse(chatTemplateResponse),
        );
      case LiteRtLmBackendInfoRequest():
        message.sendPort.send(
          backendInfoRawResponse ??
              LiteRtLmBackendInfoResponse(backendInfoResponse),
        );
      case LiteRtLmAvailableBackendsRequest():
        message.sendPort.send(
          LiteRtLmBackendInfoResponse(availableBackendsResponse),
        );
      case LiteRtLmResolvedGpuLayersRequest():
        message.sendPort.send(
          LiteRtLmResolvedGpuLayersResponse(resolvedGpuLayersResponse),
        );
      case LiteRtLmGpuSupportRequest():
        message.sendPort.send(LiteRtLmGpuSupportResponse(gpuSupportResponse));
      case LiteRtLmPerformanceContextRequest():
        message.sendPort.send(
          performanceContextResponse ?? LiteRtLmDoneResponse(),
        );
      case LiteRtLmSystemInfoRequest():
        message.sendPort.send(
          LiteRtLmSystemInfoResponse(
            vramInfoResponse.total,
            vramInfoResponse.free,
          ),
        );
      case LiteRtLmLogLevelRequest():
        message.sendPort.send(LiteRtLmDoneResponse());
      case LiteRtLmMultimodalContextCreateRequest():
        final handle = multimodalHandleResponse;
        if (handle == null) {
          message.sendPort.send(
            LiteRtLmErrorResponse(
              'LiteRT-LM multimodal context unavailable.',
              kind: 'unsupported',
            ),
          );
        } else {
          message.sendPort.send(LiteRtLmHandleResponse(handle));
        }
      case LiteRtLmMultimodalContextFreeRequest():
        message.sendPort.send(LiteRtLmDoneResponse());
      case LiteRtLmSupportsVisionRequest():
        message.sendPort.send(supportsVisionResponse ?? false);
      case LiteRtLmSupportsAudioRequest():
        message.sendPort.send(supportsAudioResponse ?? false);
      case LiteRtLmCancelGenerationRequest():
        message.sendPort.send(LiteRtLmDoneResponse());
      case LiteRtLmDisposeRequest():
        message.sendPort.send(LiteRtLmDoneResponse());
      default:
        if (message is LiteRtLmWorkerRequest) {
          message.sendPort.send(
            LiteRtLmErrorResponse(
              'Unexpected fake worker request: ${message.runtimeType}',
              kind: 'state',
            ),
          );
        }
    }
  }
}
