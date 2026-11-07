@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';

import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:llamadart/src/backends/llama_cpp/worker_messages.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:test/test.dart';

void main() {
  test('createBackend returns a LlamaBackend', () {
    final backend = createBackend();
    expect(backend, isA<LlamaBackend>());
  });

  test('NativeLlamaBackend type is available', () {
    expect(NativeLlamaBackend, isNotNull);
  });

  group('NativeLlamaBackend request routing', () {
    late _FakeWorkerHarness harness;
    late _TrackingNativeLlamaBackend backend;

    setUp(() {
      harness = _FakeWorkerHarness();
      backend = _TrackingNativeLlamaBackend(initialSendPort: harness.sendPort);
    });

    tearDown(() async {
      await backend.dispose();
      harness.dispose();
    });

    test('setLogLevel forwards request through worker port', () async {
      await backend.setLogLevel(LlamaLogLevel.info);

      expect(
        harness.received.any((message) => message is LogLevelRequest),
        isTrue,
      );
    });

    test('model and context lifecycle routes handle responses', () async {
      final modelHandle = await backend.modelLoad(
        'ok.gguf',
        const ModelParams(),
      );
      expect(modelHandle, 11);

      final contextHandle = await backend.contextCreate(
        modelHandle,
        const ModelParams(),
      );
      expect(contextHandle, 22);

      await backend.modelFree(modelHandle);
      await backend.contextFree(contextHandle);
      expect(
        harness.received.whereType<ModelFreeRequest>().length,
        greaterThanOrEqualTo(1),
      );
      expect(
        harness.received.whereType<ContextFreeRequest>().length,
        greaterThanOrEqualTo(1),
      );
    });

    test('modelLoad and contextCreate surface worker errors', () async {
      expect(
        () => backend.modelLoad('error.gguf', const ModelParams()),
        throwsException,
      );
      expect(
        () => backend.contextCreate(-1, const ModelParams()),
        throwsException,
      );
    });

    test('free operations surface worker errors', () async {
      await expectLater(
        () => backend.contextFree(-1),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('context free failed'),
          ),
        ),
      );

      await expectLater(
        () => backend.modelFree(-1),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('model free failed'),
          ),
        ),
      );

      await expectLater(
        () => backend.multimodalContextFree(-1),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('mm free failed'),
          ),
        ),
      );
    });

    test('tokenize detokenize metadata and context-size requests', () async {
      expect(await backend.tokenize(1, 'hello'), <int>[1, 2, 3]);
      expect(await backend.detokenize(1, const <int>[1, 2]), 'decoded');
      expect(await backend.modelMetadata(1), <String, String>{'a': 'b'});
      expect(await backend.getContextSize(1), 2048);
    });

    test('embed and embedBatch requests are supported', () async {
      expect(await backend.embed(1, 'hello', normalize: true), <double>[
        0.1,
        0.2,
      ]);
      expect(
        await backend.embedBatch(1, const <String>['a', 'bb']),
        <List<double>>[
          <double>[1.0, 10.0],
          <double>[2.0, 10.0],
        ],
      );
      expect(
        await backend.embedBatch(1, const <String>[]),
        const <List<double>>[],
      );
      expect(() => backend.embed(1, 'boom'), throwsException);
      expect(
        () => backend.embedBatch(1, const <String>['boom']),
        throwsException,
      );
    });

    test('generate streams bytes and supports error forwarding', () async {
      final chunks = await backend
          .generate(1, 'ok', const GenerationParams())
          .toList();
      expect(chunks, <List<int>>[
        <int>[65],
        <int>[66],
      ]);

      await expectLater(
        backend.generate(1, 'boom', const GenerationParams()).drain<void>(),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            'Exception: generation failed',
          ),
        ),
      );

      await expectLater(
        backend
            .generate(1, 'unsupported', const GenerationParams())
            .drain<void>(),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('reasoning-budget wrapper'),
          ),
        ),
      );

      await expectLater(
        backend
            .generate(1, 'inference', const GenerationParams())
            .drain<void>(),
        throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.message,
            'message',
            contains('grammar sampler failed'),
          ),
        ),
      );
    });

    test(
      'canceling a generation subscription triggers backend cancelation',
      () async {
        final subscription = backend
            .generate(1, 'pending', const GenerationParams())
            .listen((_) {});

        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();

        expect(backend.cancelGenerationCalled, isTrue);
      },
    );

    test(
      'cancel defers token free until the terminal worker response',
      () async {
        final subscription = backend
            .generate(1, 'pending', const GenerationParams())
            .listen((_) {});
        await Future<void>.delayed(Duration.zero);

        final generateRequest = harness.received
            .whereType<GenerateRequest>()
            .last;

        // Cancelling closes the Dart side but must NOT free the shared cancel
        // token yet, because the worker may still be polling it.
        await subscription.cancel();
        expect(backend.cancelGenerationCalled, isTrue);

        // The worker observes the cancel flag and emits its terminal response,
        // which is when the token is finally freed. A double free here would
        // crash the VM.
        generateRequest.sendPort.send(DoneResponse());
        await Future<void>.delayed(Duration.zero);

        // The backend remains healthy: a subsequent generation still streams.
        final chunks = await backend
            .generate(1, 'ok', const GenerationParams())
            .toList();
        expect(chunks, <List<int>>[
          <int>[65],
          <int>[66],
        ]);
      },
    );

    test(
      'rejects overlapping generations until the active worker response ends',
      () async {
        final subscription = backend
            .generate(1, 'pending', const GenerationParams())
            .listen((_) {});
        await Future<void>.delayed(Duration.zero);

        await expectLater(
          backend.generate(1, 'ok', const GenerationParams()).drain<void>(),
          throwsA(isA<StateError>()),
        );

        final generateRequest = harness.received
            .whereType<GenerateRequest>()
            .last;
        await subscription.cancel();

        await expectLater(
          backend.generate(1, 'ok', const GenerationParams()).drain<void>(),
          throwsA(isA<StateError>()),
        );

        generateRequest.sendPort.send(DoneResponse());
        await Future<void>.delayed(Duration.zero);

        final chunks = await backend
            .generate(1, 'ok', const GenerationParams())
            .toList();
        expect(chunks, <List<int>>[
          <int>[65],
          <int>[66],
        ]);
      },
    );

    test('diagnostic and multimodal endpoints route correctly', () async {
      expect(await backend.getBackendName(), 'CPU');
      expect(await backend.getAvailableBackends(), 'CPU, METAL');
      expect(await backend.getResolvedGpuLayers(), 12);
      expect(await backend.isGpuSupported(), isTrue);
      expect(await backend.getVramInfo(), (total: 100, free: 40));

      final perf = await backend.getPerformanceContext(1);
      expect(perf, isNotNull);
      expect(perf!.speculativeDraftTokens, 0);
      expect(perf.speculativeAcceptedDraftTokens, 0);
      expect(perf.speculativeDraftAttempts, 10);
      expect(perf.speculativeVerifyTokens, 11);
      expect(perf.speculativeReplayTokens, 12);

      final mmHandle = await backend.multimodalContextCreate(1, 'mmproj.gguf');
      expect(mmHandle, 33);
      expect(await backend.supportsAudio(mmHandle!), isTrue);
      expect(await backend.supportsVision(mmHandle), isFalse);
      await backend.multimodalContextFree(mmHandle);
      expect(
        () => backend.multimodalContextCreate(-1, 'mmproj.gguf'),
        throwsException,
      );
    });

    test('chat template and lora methods map responses and errors', () async {
      expect(
        await backend.applyChatTemplate(1, const <Map<String, dynamic>>[]),
        'templated',
      );
      expect(
        () => backend.applyChatTemplate(
          1,
          const <Map<String, dynamic>>[],
          customTemplate: 'error',
        ),
        throwsException,
      );

      await backend.setLoraAdapter(1, '/tmp/a.lora', 0.5);
      await backend.removeLoraAdapter(1, '/tmp/a.lora');
      await backend.clearLoraAdapters(1);

      expect(
        harness.received.whereType<LoraRequest>().map((request) => request.op),
        containsAll(<String>['set', 'remove', 'clear']),
      );
    });

    test('modelLoadFromUrl remains unsupported on native backend', () {
      expect(
        () => backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        ),
        throwsA(isA<UnimplementedError>()),
      );
      expect(backend.supportsUrlLoading, isFalse);
      expect(backend.isReady, isTrue);
    });
  });

  test('modelFree and contextFree are no-op without worker port', () async {
    final backend = NativeLlamaBackend();

    await backend.modelFree(1);
    await backend.contextFree(1);
    expect(await backend.getContextSize(1), 0);

    await backend.dispose();
    expect(backend.isReady, isFalse);
  });
}

class _TrackingNativeLlamaBackend extends NativeLlamaBackend {
  _TrackingNativeLlamaBackend({super.initialSendPort});

  bool cancelGenerationCalled = false;

  @override
  void cancelGeneration() {
    cancelGenerationCalled = true;
    super.cancelGeneration();
  }
}

class _FakeWorkerHarness {
  final ReceivePort _port = ReceivePort();
  final List<Object> received = <Object>[];

  _FakeWorkerHarness() {
    _port.listen((message) {
      if (message is! Object) {
        return;
      }
      received.add(message);

      switch (message) {
        case LogLevelRequest():
          message.sendPort.send(DoneResponse());
        case ModelLoadRequest():
          if (message.modelPath.startsWith('error')) {
            message.sendPort.send(ErrorResponse('model load failed'));
          } else {
            message.sendPort.send(HandleResponse(11));
          }
        case ContextCreateRequest():
          if (message.modelHandle < 0) {
            message.sendPort.send(ErrorResponse('context create failed'));
          } else {
            message.sendPort.send(HandleResponse(22));
          }
        case ModelFreeRequest():
          if (message.modelHandle < 0) {
            message.sendPort.send(ErrorResponse('model free failed'));
          } else {
            message.sendPort.send(DoneResponse());
          }
        case ContextFreeRequest():
          if (message.contextHandle < 0) {
            message.sendPort.send(ErrorResponse('context free failed'));
          } else {
            message.sendPort.send(DoneResponse());
          }
        case TokenizeRequest():
          message.sendPort.send(TokenizeResponse(<int>[1, 2, 3]));
        case DetokenizeRequest():
          message.sendPort.send(DetokenizeResponse('decoded'));
        case MetadataRequest():
          message.sendPort.send(MetadataResponse(<String, String>{'a': 'b'}));
        case EmbedRequest():
          if (message.text == 'boom') {
            message.sendPort.send(ErrorResponse('embed failed'));
          } else {
            message.sendPort.send(EmbedResponse(<double>[0.1, 0.2]));
          }
        case EmbedBatchRequest():
          if (message.texts.contains('boom')) {
            message.sendPort.send(ErrorResponse('embed batch failed'));
          } else {
            message.sendPort.send(
              EmbedBatchResponse(
                message.texts
                    .map((text) => <double>[text.length.toDouble(), 10.0])
                    .toList(growable: false),
              ),
            );
          }
        case GenerateRequest():
          if (message.prompt == 'boom') {
            message.sendPort.send(
              ErrorResponse('Exception: generation failed'),
            );
          } else if (message.prompt == 'unsupported') {
            message.sendPort.send(
              ErrorResponse(
                'missing reasoning-budget wrapper',
                kind: WorkerErrorKind.unsupported,
              ),
            );
          } else if (message.prompt == 'inference') {
            message.sendPort.send(
              ErrorResponse(
                'grammar sampler failed',
                kind: WorkerErrorKind.inference,
              ),
            );
          } else if (message.prompt == 'pending') {
            // Hold open until the client cancels the stream.
          } else {
            message.sendPort.send(TokenResponse(<int>[65]));
            message.sendPort.send(TokenResponse(<int>[66]));
            message.sendPort.send(DoneResponse());
          }
        case BackendInfoRequest():
          message.sendPort.send(BackendInfoResponse('CPU'));
        case AvailableBackendsRequest():
          message.sendPort.send(BackendInfoResponse('CPU, METAL'));
        case ResolvedGpuLayersRequest():
          message.sendPort.send(ResolvedGpuLayersResponse(12));
        case GpuSupportRequest():
          message.sendPort.send(GpuSupportResponse(true));
        case SystemInfoRequest():
          message.sendPort.send(SystemInfoResponse(100, 40));
        case PerformanceContextRequest():
          message.sendPort.send(
            PerformanceContextResponse(
              loadMs: 1,
              promptEvalMs: 2,
              evalMs: 3,
              sampleMs: 4,
              decodeMs: 5,
              promptEvalTokens: 6,
              evalTokens: 7,
              sampleCount: 8,
              reusedGraphs: 9,
              speculativeDraftTokens: 0,
              speculativeAcceptedDraftTokens: 0,
              speculativeDraftAttempts: 10,
              speculativeVerifyTokens: 11,
              speculativeReplayTokens: 12,
              speculativeDraftMs: 0,
              speculativeVerifyMs: 13,
            ),
          );
        case MultimodalContextCreateRequest():
          if (message.modelHandle < 0) {
            message.sendPort.send(ErrorResponse('mm create failed'));
          } else {
            message.sendPort.send(HandleResponse(33));
          }
        case MultimodalContextFreeRequest():
          if (message.mmContextHandle < 0) {
            message.sendPort.send(ErrorResponse('mm free failed'));
          } else {
            message.sendPort.send(DoneResponse());
          }
        case SupportsAudioRequest():
          message.sendPort.send(true);
        case SupportsVisionRequest():
          message.sendPort.send(false);
        case GetContextSizeRequest():
          message.sendPort.send(GetContextSizeResponse(2048));
        case ChatTemplateRequest():
          if (message.customTemplate == 'error') {
            message.sendPort.send(ErrorResponse('chat template failed'));
          } else {
            message.sendPort.send(ChatTemplateResponse('templated'));
          }
        case LoraRequest():
          message.sendPort.send(DoneResponse());
        case DisposeRequest():
          message.sendPort.send(DoneResponse());
        case WorkerHandshake():
        // Not expected in these tests.
      }
    });
  }

  SendPort get sendPort => _port.sendPort;

  void dispose() {
    _port.close();
  }
}
