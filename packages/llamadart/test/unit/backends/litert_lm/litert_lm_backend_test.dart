@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';

import 'package:llamadart/llamadart.dart' as api;
import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/native/native_backend.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_backend.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/worker.dart';
import 'package:llamadart/src/core/engine/engine.dart';
import 'package:llamadart/src/core/engine/engine_observer.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/llama_logging.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/config/gpu_backend.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:test/test.dart';

import '../../../support/dart_script_snapshot.dart';

void main() {
  test(
    'native schema admission is delegated, request scoped and reset on reload',
    () async {
      final worker = _FakeLiteRtLmWorker(
        tokenizeResponse: const [],
        detokenizeResponse: '',
        generationChunks: [utf8.encode('{}')],
      );
      final direct = LiteRtLmBackend(initialSendPort: worker.sendPort);
      final backend = NativeAutoBackend(liteRtLmFactory: () => direct);
      try {
        await backend.modelLoad(
          'Qwen3.litertlm',
          const ModelParams(device: api.ComputeDevice.cpu),
        );
        expect(backend.supportsJsonSchemaChatGeneration, isFalse);
        worker.schemaAdmissionError = LiteRtLmErrorResponse(
          'missing provider',
          kind: 'llamaUnsupported',
        );
        await expectLater(
          backend.prepareJsonSchemaChat(),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(backend.supportsJsonSchemaChatGeneration, isFalse);
        expect(
          () => backend.generateChatWithJsonSchema(
            1,
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'p'),
            ],
            const GenerationParams(),
            jsonSchema: {'type': 'object'},
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        worker.schemaAdmissionError = null;
        await backend.prepareJsonSchemaChat();
        expect(backend.supportsJsonSchemaChatGeneration, isTrue);
        expect(
          await backend
              .generateChatWithJsonSchema(
                1,
                const [
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: 'p',
                  ),
                ],
                const GenerationParams(),
                jsonSchema: {'type': 'object'},
              )
              .toList(),
          [utf8.encode('{}')],
        );
        final request = worker.requests
            .whereType<LiteRtLmGenerateChatRequest>()
            .single;
        expect(request.jsonSchema, '{"type":"object"}');
        expect(request.enableThinking, isFalse);
        expect(request.params.grammar, isNull);
        expect(worker.requests.whereType<LiteRtLmGenerateRequest>(), isEmpty);
        expect(backend.supportsJsonSchemaChatThinking, isFalse);
        expect(
          () => backend.generateChatWithJsonSchemaAndThinking(
            1,
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'p'),
            ],
            const GenerationParams(),
            jsonSchema: {'type': 'object'},
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (e) => e.message,
              'message',
              contains('Gemma 4'),
            ),
          ),
        );
        await backend.contextCreate(
          1,
          const ModelParams(device: api.ComputeDevice.cpu),
        );
        worker.schemaAdmitsThinking = true;
        await backend.prepareJsonSchemaChat();
        expect(backend.supportsJsonSchemaChatThinking, isTrue);
        await backend
            .generateChatWithJsonSchemaAndThinking(
              1,
              const [
                LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'p'),
              ],
              const GenerationParams(),
              jsonSchema: {'type': 'object'},
            )
            .drain<void>();
        expect(
          worker.requests.whereType<LiteRtLmGenerateChatRequest>().last,
          isA<LiteRtLmGenerateChatRequest>()
              .having((r) => r.enableThinking, 'enableThinking', isTrue)
              .having((r) => r.jsonSchema, 'jsonSchema', '{"type":"object"}'),
        );
        worker.schemaAdmitsThinking = false;
        await backend.contextCreate(
          1,
          const ModelParams(device: api.ComputeDevice.cpu),
        );
        expect(backend.supportsJsonSchemaChatGeneration, isFalse);
        await backend.prepareJsonSchemaChat();
        expect(backend.supportsJsonSchemaChatGeneration, isTrue);
        await backend.contextFree(1);
        expect(backend.supportsJsonSchemaChatGeneration, isFalse);
        for (final freeContext in [false, true]) {
          final started = worker.schemaAdmissionStarted = Completer<void>();
          final gate = worker.schemaAdmissionGate = Completer<void>();
          final admission = backend.prepareJsonSchemaChat();
          await started.future;
          if (freeContext) {
            await backend.contextFree(1);
          } else {
            await backend.contextCreate(
              1,
              const ModelParams(device: api.ComputeDevice.cpu),
            );
          }
          final rejected = expectLater(
            admission,
            throwsA(isA<LlamaStateException>()),
          );
          gate.complete();
          await rejected;
          expect(backend.supportsJsonSchemaChatGeneration, isFalse);
        }
        await backend.modelLoad(
          'Qwen3-next.litertlm',
          const ModelParams(device: api.ComputeDevice.cpu),
        );
        expect(backend.supportsJsonSchemaChatGeneration, isFalse);
        expect(
          (backend as BackendGrammarConstraintsSupport)
              .supportsGrammarConstraints,
          isFalse,
        );
      } finally {
        await backend.dispose();
        worker.close();
      }
    },
  );

  test(
    'embedding cancellation during worker startup prevents dispatch',
    () async {
      final startup = ReceivePort();
      final endpoint = ReceivePort();
      var dispatched = 0;
      endpoint.listen((message) {
        if (message is LiteRtLmEmbedRequest) {
          dispatched++;
          message.sendPort.send(
            LiteRtLmEmbedResponse([
              [1.0],
            ]),
          );
        } else if (message is LiteRtLmWorkerRequest) {
          message.sendPort.send(LiteRtLmDoneResponse());
        }
      });
      final startupControl = startup.sendPort;
      final backend = LiteRtLmBackend(
        workerEntryPoint: _embeddingStartupWorker(startupControl),
      );
      final mirror = reflect(backend);
      final owner = mirror.type.owner as LibraryMirror;
      // Exercise startup/recovery with a previously selected embedding engine.
      mirror.setField(MirrorSystem.getSymbol('_embeddingEngine', owner), true);
      addTearDown(() async {
        await backend.dispose();
        endpoint.close();
        startup.close();
      });
      final future = backend.embed(1, 'text');
      final handshake = await startup.first as SendPort;
      backend.cancelGeneration();
      final cancelled = expectLater(
        future,
        throwsA(
          isA<LlamaInferenceException>().having(
            (e) => e.message,
            'cancellation',
            contains('cancel'),
          ),
        ),
      );
      handshake.send(endpoint.sendPort);
      await cancelled;
      expect(dispatched, 0);
      expect(await backend.embed(1, 'text'), [1.0]);
      expect(dispatched, 1);
    },
  );

  test(
    'embedding load reaches the worker with its explicit engine selector',
    () async {
      final worker = _FakeLiteRtLmWorker(
        tokenizeResponse: const [],
        detokenizeResponse: '',
        generationChunks: const [],
      );
      final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);
      try {
        await backend.modelLoad(
          'fake.litertlm',
          const ModelParams(liteRtLmEmbeddingEngine: true),
        );
        expect(
          worker.requests
              .whereType<LiteRtLmModelLoadRequest>()
              .single
              .modelParams
              .liteRtLmEmbeddingEngine,
          isTrue,
        );
        expect(backend.supportsEmbeddings, isTrue);
      } finally {
        await backend.dispose();
        worker.close();
      }
    },
  );

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

  for (final routed in [false, true]) {
    test(
      'engine rejects LoRA adapters and projectors (routed: $routed)',
      () async {
        final worker = _FakeLiteRtLmWorker(
          tokenizeResponse: const <int>[],
          detokenizeResponse: '',
        );
        final liteRt = LiteRtLmBackend(initialSendPort: worker.sendPort);
        final LlamaBackend backend = routed
            ? NativeAutoBackend(liteRtLmFactory: () => liteRt)
            : liteRt;
        final engine = LlamaEngine(backend);
        try {
          await engine.loadModel(modelFile.path);
          Matcher unsupported(String operation) => throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              routed
                  ? '$operation are not supported by the active native runtime.'
                  : allOf(contains(operation), contains('does not implement')),
            ),
          );

          await expectLater(engine.clearLoras(), unsupported('LoRA adapters'));
          await expectLater(
            // ignore: deprecated_member_use_from_same_package
            engine.removeLora('adapter.bin'),
            unsupported('LoRA adapters'),
          );
          await engine.removeLoraSource(api.ModelSource.path('adapter.bin'));
          final noProjector = throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              contains('A LiteRT-LM model takes no multimodal projector'),
            ),
          );
          await expectLater(
            // ignore: deprecated_member_use_from_same_package
            engine.loadMultimodalProjector('mmproj.bin'),
            noProjector,
          );
          await expectLater(
            engine.loadMultimodalProjectorSource(
              api.ModelSource.path('mmproj.bin'),
            ),
            noProjector,
          );
          final capabilities = await engine.capabilities;
          expect(capabilities.supportsVision, isFalse);
          expect(capabilities.supportsAudio, isFalse);
        } finally {
          await engine.dispose();
          worker.close();
        }
      },
    );
  }

  for (final routed in [false, true]) {
    test('rejects automatic tool loops before native generation '
        '(routed: $routed)', () async {
      final worker = _FakeLiteRtLmWorker(
        tokenizeResponse: const <int>[],
        detokenizeResponse: '',
        generationChunks: [utf8.encode('Hello')],
      );
      final liteRt = LiteRtLmBackend(initialSendPort: worker.sendPort);
      final LlamaBackend backend = routed
          ? NativeAutoBackend(liteRtLmFactory: () => liteRt)
          : liteRt;
      final engine = LlamaEngine(backend);
      final session = api.ChatSession(engine, maxContextTokens: 0);
      final previous = api.LlamaChatMessage.fromText(
        role: api.LlamaChatRole.user,
        text: 'Existing turn',
      );
      session.addMessage(previous);
      var callbacks = 0;
      var toolRuns = 0;
      final tools = [
        api.ToolDefinition(
          name: 'weather',
          description: 'Weather',
          parameters: const [],
          handler: (_) async {
            toolRuns++;
            return 'sunny';
          },
        ),
      ];
      try {
        await engine.loadModel(modelFile.path);
        expect(engine.runtime, api.LlamaRuntime.liteRtLm);
        expect(
          (backend as BackendGenerationLimitSupport)
              .generationLimitUnsupportedReason,
          contains('v0.18.0'),
        );
        for (final resume in [false, true]) {
          await expectLater(
            session.completeWithTools(
              resume ? const [] : const [api.LlamaTextContent('New turn')],
              tools: tools,
              params: const api.GenerationParams(maxTokens: 1),
              onMessageAdded: (_) => callbacks++,
            ),
            throwsA(
              isA<api.LlamaUnsupportedException>().having(
                (error) => error.message,
                'diagnostic',
                contains('token-limit reporting'),
              ),
            ),
          );
          expect(session.history, [same(previous)]);
        }
        await expectLater(
          session.sendWithTools('No tools', tools: const []),
          throwsA(isA<api.LlamaUnsupportedException>()),
        );
        expect(callbacks, 0);
        expect(toolRuns, 0);
        expect(session.history, [same(previous)]);
        expect(worker.requests.whereType<LiteRtLmGenerateRequest>(), isEmpty);
        expect(
          worker.requests.whereType<LiteRtLmGenerateChatRequest>(),
          isEmpty,
        );

        // The safety gate does not prevent manually managed completion.
        final chunks = await engine.create(const [
          api.LlamaChatMessage.fromText(
            role: api.LlamaChatRole.user,
            text: 'hi',
          ),
        ], params: const api.GenerationParams(maxTokens: 1)).toList();
        expect(chunks.map((chunk) => chunk.text).join(), 'Hello');
        expect(chunks.last.choices.single.finishReason, 'stop');
        expect(
          worker.requests.whereType<LiteRtLmGenerateChatRequest>(),
          hasLength(1),
        );
      } finally {
        await engine.dispose();
        worker.close();
      }
    });
  }

  group('finish reasons', () {
    api.ToolDefinition weatherTool(void Function() onRun) => api.ToolDefinition(
      name: 'weather',
      description: 'Weather',
      parameters: const [],
      handler: (_) async {
        onRun();
        return 'sunny';
      },
    );

    for (final routed in [false, true]) {
      Future<
        ({LlamaEngine engine, LlamaBackend backend, _FakeLiteRtLmWorker worker})
      >
      load({required bool reports, BackendGenerationLimit? limit}) async {
        final worker = _FakeLiteRtLmWorker(
          tokenizeResponse: const <int>[],
          detokenizeResponse: '',
          generationChunks: [utf8.encode('Hello')],
          reportsFinishReasons: reports,
          generationLimit: limit,
        );
        final liteRt = LiteRtLmBackend(initialSendPort: worker.sendPort);
        final LlamaBackend backend = routed
            ? NativeAutoBackend(liteRtLmFactory: () => liteRt)
            : liteRt;
        final engine = LlamaEngine(backend);
        addTearDown(() async {
          await engine.dispose();
          worker.close();
        });
        await engine.loadModel(modelFile.path);
        return (engine: engine, backend: backend, worker: worker);
      }

      const messages = [
        api.LlamaChatMessage.fromText(role: api.LlamaChatRole.user, text: 'hi'),
      ];
      const params = api.GenerationParams(maxTokens: 1);

      test(
        'a reported token limit finishes with length (routed: $routed)',
        () async {
          for (final limit in [
            BackendGenerationLimit.maxTokens,
            BackendGenerationLimit.contextSize,
          ]) {
            final loaded = await load(reports: true, limit: limit);
            expect(
              (loaded.backend as BackendGenerationLimitSupport)
                  .generationLimitUnsupportedReason,
              isNull,
            );

            final chunks = await loaded.engine
                .create(messages, params: params)
                .toList();
            expect(chunks.last.choices.single.finishReason, 'length');
            expect(completionGenerationLimit(chunks.last), limit);

            final raw = loaded.engine.generate('hi', params: params);
            expect(await raw.join(), 'Hello');
            expect(rawGenerationLimit(raw), limit);
          }
        },
      );

      test('no reported limit finishes with stop (routed: $routed)', () async {
        final loaded = await load(reports: true);

        final chunks = await loaded.engine
            .create(messages, params: params)
            .toList();
        expect(chunks.last.choices.single.finishReason, 'stop');
        expect(completionGenerationLimit(chunks.last), isNull);
      });

      test('automatic tool loops run on a reporting runtime and stop '
          'truncated at a limit (routed: $routed)', () async {
        var toolRuns = 0;
        final tools = [weatherTool(() => toolRuns++)];

        final completed = await load(reports: true);
        final completedSession = api.ChatSession(
          completed.engine,
          maxContextTokens: 0,
        );
        final done = await completedSession.completeWithTools(
          const [api.LlamaTextContent('New turn')],
          tools: tools,
          params: params,
        );
        expect(done.stopReason, api.LlamaToolLoopStopReason.completed);
        expect(done.completion.finishReason, api.LlamaFinishReason.stop);
        expect(completedSession.history, hasLength(2));

        final limited = await load(
          reports: true,
          limit: BackendGenerationLimit.maxTokens,
        );
        final limitedSession = api.ChatSession(
          limited.engine,
          maxContextTokens: 0,
        );
        final truncated = await limitedSession.completeWithTools(
          const [api.LlamaTextContent('New turn')],
          tools: tools,
          params: params,
        );
        expect(truncated.stopReason, api.LlamaToolLoopStopReason.truncated);
        expect(truncated.completion.finishReason, api.LlamaFinishReason.length);
        expect(truncated.rolledBack, isTrue);
        expect(limitedSession.history, isEmpty);
        expect(toolRuns, 0);
      });

      test('a runtime without finish reasons keeps loops unsupported '
          '(routed: $routed)', () async {
        final loaded = await load(reports: false);
        expect(
          (loaded.backend as BackendGenerationLimitSupport)
              .generationLimitUnsupportedReason,
          allOf(
            contains('v0.18.0-3'),
            contains('stream_proxy_finish_reason_abi_version'),
          ),
        );
        await expectLater(
          api.ChatSession(loaded.engine).completeWithTools(
            const [api.LlamaTextContent('New turn')],
            tools: [weatherTool(() {})],
            params: params,
          ),
          throwsA(isA<api.LlamaUnsupportedException>()),
        );
      });
    }

    test('a free forgets that the runtime reports finish reasons', () async {
      final worker = _FakeLiteRtLmWorker(
        tokenizeResponse: const <int>[],
        detokenizeResponse: '',
        reportsFinishReasons: true,
      );
      final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);
      try {
        final model = await backend.modelLoad(
          modelFile.path,
          const ModelParams(),
        );
        expect(backend.generationLimitUnsupportedReason, isNull);
        await backend.modelFree(model);
        expect(backend.generationLimitUnsupportedReason, isNotNull);
      } finally {
        await backend.dispose();
        worker.close();
      }
    });

    test('a failed reload forgets that the runtime reports finish '
        'reasons', () async {
      final worker = _FakeLiteRtLmWorker(
        tokenizeResponse: const <int>[],
        detokenizeResponse: '',
        reportsFinishReasons: true,
      );
      final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);
      try {
        await backend.modelLoad(modelFile.path, const ModelParams());
        expect(backend.generationLimitUnsupportedReason, isNull);
        worker.modelLoadErrorResponse = LiteRtLmErrorResponse(
          'load failed',
          kind: 'state',
        );
        await expectLater(
          backend.modelLoad(modelFile.path, const ModelParams()),
          throwsA(anything),
        );
        expect(backend.generationLimitUnsupportedReason, isNotNull);
      } finally {
        await backend.dispose();
        worker.close();
      }
    });

    test('an embedding engine names itself as why loops cannot run', () async {
      final worker = _FakeLiteRtLmWorker(
        tokenizeResponse: const <int>[],
        detokenizeResponse: '',
      );
      final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);
      try {
        await backend.modelLoad(
          modelFile.path,
          const ModelParams(liteRtLmEmbeddingEngine: true),
        );
        expect(
          backend.generationLimitUnsupportedReason,
          allOf(contains('embedding engine'), isNot(contains('v0.18.0-3'))),
        );
      } finally {
        await backend.dispose();
        worker.close();
      }
    });

    test(
      'a generation cancelled through the backend records no limit',
      () async {
        final worker = _FakeLiteRtLmWorker(
          tokenizeResponse: const <int>[],
          detokenizeResponse: '',
          generationChunks: [utf8.encode('Hello')],
          holdGeneration: true,
          reportsFinishReasons: true,
          generationLimit: BackendGenerationLimit.maxTokens,
        );
        final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);
        try {
          await backend.modelLoad(modelFile.path, const ModelParams());
          final stream = backend.generate(1, 'hi', const GenerationParams());
          final first = Completer<void>();
          final done = stream.map((chunk) {
            if (!first.isCompleted) first.complete();
            return chunk;
          }).drain<void>();
          await first.future;
          backend.cancelGeneration();
          worker.releaseGeneration();
          await done;
          expect(
            generationLimitReporterOf(backend)!.generationLimitOf(stream),
            isNull,
          );
        } finally {
          await backend.dispose();
          worker.close();
        }
      },
    );

    test('a cancelled generation records no limit', () async {
      for (final cancel in [false, true]) {
        final worker = _FakeLiteRtLmWorker(
          tokenizeResponse: const <int>[],
          detokenizeResponse: '',
          generationChunks: [utf8.encode('Hello')],
          holdGeneration: true,
          reportsFinishReasons: true,
          generationLimit: BackendGenerationLimit.maxTokens,
        );
        final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);
        try {
          await backend.modelLoad(modelFile.path, const ModelParams());
          final stream = backend.generate(1, 'hi', const GenerationParams());
          final first = Completer<void>();
          final subscription = stream.listen((_) {
            if (!first.isCompleted) first.complete();
          });
          final done = subscription.asFuture<void>();
          await first.future;
          if (cancel) {
            await subscription.cancel();
          }
          worker.releaseGeneration();
          if (!cancel) {
            await done;
          }
          await pumpEventQueue();
          expect(
            generationLimitReporterOf(backend)!.generationLimitOf(stream),
            cancel ? isNull : BackendGenerationLimit.maxTokens,
            reason: 'cancel: $cancel',
          );
        } finally {
          await backend.dispose();
          worker.close();
        }
      }
    });
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
    expect(backend, isA<BackendDeferredEngineCreation>());
    expect(backend.supportsUrlLoading, isFalse);
    expect(
      (backend as BackendDeferredEngineCreation).defersEngineCreation,
      isTrue,
    );
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

  test('reports the LiteRT-LM runtime', () {
    expect(LiteRtLmBackend().runtime, LlamaRuntime.liteRtLm);
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
      expect(
        results[3],
        Platform.isAndroid ||
            liteRtLmGateAbi() == Abi.macosArm64 ||
            liteRtLmGateAbi() == Abi.linuxX64 ||
            liteRtLmGateAbi() == Abi.windowsX64,
      );
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

  test('reports a direct GPU preference by macOS ABI', () async {
    addTearDown(() => debugLiteRtLmAbiOverride = null);
    final backend = LiteRtLmBackend(preferredBackend: 'gpu');

    try {
      debugLiteRtLmAbiOverride = Abi.macosArm64;
      expect(await backend.getBackendName(), 'LiteRT-LM gpu');
      expect(await backend.getResolvedGpuLayers(), ModelParams.maxGpuLayers);

      debugLiteRtLmAbiOverride = Abi.macosX64;
      await expectLater(
        backend.getBackendName(),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('LiteRT-LM GPU is not available on macOS x86_64'),
          ),
        ),
      );
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

  test(
    'direct modelLoad rejects llama.cpp-only fields it would ignore',
    () async {
      final backend = LiteRtLmBackend();

      try {
        for (final (params, field) in [
          (const ModelParams(loadMtp: true), 'loadMtp'),
          (
            const ModelParams(speculativeRollbackTokenMax: 4),
            'speculativeRollbackTokenMax',
          ),
          (const ModelParams(preferMemory64: true), 'preferMemory64'),
          (const ModelParams(modelBytesHint: 1), 'modelBytesHint'),
        ]) {
          await expectLater(
            backend.modelLoad(modelFile.path, params),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'message',
                contains('llama.cpp-specific ModelParams: $field.'),
              ),
            ),
          );
        }
      } finally {
        await backend.dispose();
      }
    },
  );

  test(
    'embedding without an embedding engine names the option to set',
    () async {
      final backend = LiteRtLmBackend();
      try {
        await expectLater(
          backend.embed(1, 'text'),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              contains('LiteRtLmModelParams(embeddingEngine: true)'),
            ),
          ),
        );
      } finally {
        await backend.dispose();
      }
    },
  );

  test('embedding mode names options the way LiteRtLmModelParams spells '
      'them', () async {
    final backend = LiteRtLmBackend();
    try {
      await expectLater(
        backend.modelLoad(
          modelFile.path,
          const LiteRtLmModelParams(embeddingEngine: true, prefillChunkSize: 8),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'LiteRT-LM embedding mode does not apply: prefillChunkSize. Use '
                'contextSize (encoder signature), numberOfThreads, cacheDir '
                'and CPU device selection.',
          ),
        ),
      );
    } finally {
      await backend.dispose();
    }
  });

  test('direct modelLoad rejects LlamaCppModelParams', () async {
    final backend = LiteRtLmBackend();
    try {
      await expectLater(
        backend.modelLoad(modelFile.path, const LlamaCppModelParams()),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('Use LiteRtLmModelParams.'),
          ),
        ),
      );
      await expectLater(
        backend.modelLoad(
          modelFile.path,
          const LiteRtLmModelParams(contextSize: 0),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('contextSize=0'),
          ),
        ),
      );
    } finally {
      await backend.dispose();
    }
  });

  test('direct modelLoad keeps invalid ModelParams typed', () async {
    final backend = LiteRtLmBackend();

    try {
      await expectLater(
        backend.modelLoad(
          modelFile.path,
          const ModelParams(speculativeRollbackTokenMax: -1),
        ),
        throwsA(
          isA<LlamaArgumentException>().having(
            (error) => error.message,
            'message',
            contains('speculativeRollbackTokenMax'),
          ),
        ),
      );
    } finally {
      await backend.dispose();
    }
  });

  test('public engine rejects unsupported model params and recovers', () async {
    final engine = LlamaEngine(LiteRtLmBackend());

    try {
      await expectLater(
        engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(batchSize: 128, useMlock: true),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(contains('batchSize'), contains('useMlock')),
          ),
        ),
      );
      expect(engine.isReady, isFalse);

      await engine.loadModel(
        modelFile.path,
        modelParams: const ModelParams(preferredBackend: GpuBackend.cpu),
      );
      expect(engine.isReady, isTrue);
    } finally {
      await engine.dispose();
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

  for (final operation in ['dispose', 'contextFree', 'modelFree']) {
    test(
      '$operation settles abandoned requests and reports unsafe cleanup',
      () async {
        final port = ReceivePort();
        final received = Completer<LiteRtLmTokenizeRequest>();
        port.listen((message) {
          if (message is LiteRtLmTokenizeRequest) {
            received.complete(message);
          } else if (message is LiteRtLmCancelGenerationRequest ||
              message is LiteRtLmDisposeRequest) {
            (message as LiteRtLmWorkerRequest).sendPort.send(
              LiteRtLmDoneResponse(),
            );
          }
          // Free requests deliberately never settle, as with a blocked runtime.
        });
        final backend = LiteRtLmBackend(
          initialSendPort: port.sendPort,
          freeTimeout: const Duration(milliseconds: 50),
        );
        final pending = backend.tokenize(1, 'hello');
        final failed = expectLater(
          pending,
          throwsA(isA<LlamaStateException>()),
        );
        final request = await received.future;
        try {
          await expectLater(switch (operation) {
            'contextFree' => backend.contextFree(1),
            'modelFree' => backend.modelFree(1),
            _ => backend.dispose(),
          }, throwsA(isA<LlamaStateException>()));
          await failed.timeout(const Duration(seconds: 1));
          expect(backend.isReady, isFalse);
          await expectLater(
            backend.tokenize(1, 'retry'),
            throwsA(isA<LlamaStateException>()),
          );
          await expectLater(
            backend.dispose(),
            throwsA(isA<LlamaStateException>()),
          );
          await expectLater(
            backend.contextFree(1),
            throwsA(isA<LlamaStateException>()),
          );
          await expectLater(
            backend.modelFree(1),
            throwsA(isA<LlamaStateException>()),
          );
          // A late reply cannot revive the terminated request or backend.
          request.sendPort.send(LiteRtLmTokenizeResponse([42]));
          if (operation != 'dispose') {
            await expectLater(
              backend.dispose(),
              throwsA(isA<LlamaStateException>()),
            );
          }
        } finally {
          port.close();
        }
      },
    );
  }

  for (final operation in ['dispose', 'contextFree', 'modelFree']) {
    test(
      '$operation waits past freeTimeout for started native teardown',
      () async {
        final port = ReceivePort();
        final teardown = Completer<LiteRtLmWorkerRequest>();
        port.listen((message) {
          if (message is! LiteRtLmWorkerRequest) return;
          final isTeardown =
              message is LiteRtLmContextFreeRequest ||
              message is LiteRtLmModelFreeRequest ||
              message is LiteRtLmDisposeRequest;
          if (isTeardown && !teardown.isCompleted) {
            message.sendPort.send(const LiteRtLmNativeTeardownStarted());
            teardown.complete(message);
          } else {
            message.sendPort.send(LiteRtLmDoneResponse());
          }
        });
        final backend = LiteRtLmBackend(
          initialSendPort: port.sendPort,
          freeTimeout: const Duration(milliseconds: 50),
        );
        try {
          var settled = false;
          final pending = switch (operation) {
            'contextFree' => backend.contextFree(1),
            'modelFree' => backend.modelFree(1),
            _ => backend.dispose(),
          }.whenComplete(() => settled = true);
          final request = await teardown.future.timeout(
            const Duration(seconds: 2),
          );
          await Future<void>.delayed(const Duration(milliseconds: 150));
          expect(settled, isFalse, reason: 'teardown has not finished');

          request.sendPort.send(LiteRtLmDoneResponse());
          await pending.timeout(const Duration(seconds: 2));
          if (operation != 'dispose') {
            await backend.dispose();
          }
        } finally {
          port.close();
        }
      },
    );
  }

  for (final operation in ['dispose', 'contextFree', 'modelFree']) {
    test(
      '$operation reports a worker that exits during native teardown',
      () async {
        final backend = LiteRtLmBackend(
          workerEntryPoint: _exitDuringTeardownWorker,
        );
        await backend.modelLoad('fake.litertlm', const ModelParams());
        await expectLater(
          switch (operation) {
            'contextFree' => backend.contextFree(1),
            'modelFree' => backend.modelFree(1),
            _ => backend.dispose(),
          }.timeout(const Duration(seconds: 2)),
          throwsA(isA<LlamaStateException>()),
        );
        if (operation != 'dispose') {
          await expectLater(
            backend.dispose(),
            throwsA(isA<LlamaStateException>()),
          );
        }
      },
    );
  }

  test('dispose reports unsettled cleanup when the worker never starts '
      'native teardown', () async {
    // The worker never dequeues anything, as when earlier native work hangs.
    final port = ReceivePort();
    final backend = LiteRtLmBackend(
      initialSendPort: port.sendPort,
      freeTimeout: const Duration(milliseconds: 50),
      cancelAcknowledgementTimeout: const Duration(milliseconds: 50),
    );
    try {
      await expectLater(
        backend.dispose().timeout(const Duration(seconds: 2)),
        throwsA(isA<LlamaStateException>()),
      );
    } finally {
      port.close();
    }
  });

  test('concurrent disposal waits for the same cleanup result', () async {
    final port = ReceivePort();
    final received = Completer<LiteRtLmDisposeRequest>();
    var disposeCount = 0;
    port.listen((message) {
      if (message is LiteRtLmDisposeRequest) {
        disposeCount++;
        received.complete(message);
      } else if (message is LiteRtLmCancelGenerationRequest) {
        message.sendPort.send(LiteRtLmDoneResponse());
      }
    });
    final backend = LiteRtLmBackend(initialSendPort: port.sendPort);
    final first = backend.dispose();
    final second = backend.dispose();
    expect(identical(first, second), isTrue);
    final checks = [
      expectLater(first, throwsA(isA<LlamaStateException>())),
      expectLater(second, throwsA(isA<LlamaStateException>())),
    ];
    final request = await received.future;
    request.sendPort.send(LiteRtLmErrorResponse('unsettled', kind: 'state'));
    await Future.wait(checks);
    expect(disposeCount, 1);
    port.close();
  });

  test(
    'dispose reports rejected native cleanup even without pending requests',
    () async {
      final port = ReceivePort();
      port.listen((message) {
        if (message is LiteRtLmDisposeRequest) {
          message.sendPort.send(
            LiteRtLmErrorResponse(
              'native operation has not settled',
              kind: 'state',
            ),
          );
        } else if (message is LiteRtLmCancelGenerationRequest) {
          message.sendPort.send(LiteRtLmDoneResponse());
        }
      });
      final backend = LiteRtLmBackend(initialSendPort: port.sendPort);
      try {
        await expectLater(
          backend.dispose(),
          throwsA(isA<LlamaStateException>()),
        );
      } finally {
        port.close();
      }
    },
  );

  for (final entry in [_exitingWorker, _crashingWorker]) {
    test(
      'unexpected worker termination fails concurrent requests and generation',
      () async {
        final backend = LiteRtLmBackend(workerEntryPoint: entry);
        final requests = [
          expectLater(
            backend.tokenize(1, 'hello'),
            throwsA(isA<LlamaStateException>()),
          ),
          expectLater(
            backend.detokenize(1, [1]),
            throwsA(isA<LlamaStateException>()),
          ),
          expectLater(
            backend.generate(1, 'hello', const GenerationParams()).toList(),
            throwsA(isA<LlamaStateException>()),
          ),
        ];
        await Future.wait(requests).timeout(const Duration(seconds: 2));
        expect(backend.isReady, isFalse);
        await expectLater(
          backend.dispose(),
          throwsA(isA<LlamaStateException>()),
        );
      },
    );
  }

  for (final freeContext in [true, false]) {
    test(
      'free fails when worker exits during generation cancellation: $freeContext',
      () async {
        final backend = LiteRtLmBackend(
          workerEntryPoint: _exitOnCancelWorker,
          cancelAcknowledgementTimeout: const Duration(milliseconds: 50),
        );
        final started = Completer<void>();
        final stream = freeContext
            ? backend.generate(1, 'hello', const GenerationParams())
            : backend.generateChat(1, const [
                LlamaChatMessage.fromText(
                  role: LlamaChatRole.user,
                  text: 'hello',
                ),
              ], const GenerationParams());
        final generation = stream.map((tokens) {
          if (!started.isCompleted) started.complete();
          return tokens;
        }).toList();
        final failed = expectLater(
          generation,
          throwsA(isA<LlamaStateException>()),
        );
        await started.future.timeout(const Duration(seconds: 2));
        await expectLater(
          freeContext ? backend.contextFree(1) : backend.modelFree(1),
          throwsA(isA<LlamaStateException>()),
        );
        await failed;
        await expectLater(
          backend.dispose(),
          throwsA(isA<LlamaStateException>()),
        );
      },
    );
  }

  group('worker log forwarding', () {
    final records = <LlamaLogRecord>[];

    setUp(records.clear);

    tearDown(LlamaLogging.configure);

    test('a worker warning reaches the LlamaLogging handler', () async {
      await LlamaLogging.configure(
        level: LlamaLogLevel.warn,
        handler: records.add,
      );
      final backend = LiteRtLmBackend(workerEntryPoint: _loggingWorkerEntry);
      try {
        final name = await backend.getBackendName().timeout(
          const Duration(seconds: 5),
        );
        expect(name, 'logging');
        await _waitForRecords(records, 1);
        expect(records.single.level, LlamaLogLevel.warn);
        expect(records.single.message, 'worker warning');
        expect(records.single.error, 'Bad state: worker detail');
      } finally {
        await backend.dispose().timeout(const Duration(seconds: 2));
      }
    });

    test('nothing is forwarded at level none', () async {
      await LlamaLogging.configure(
        level: LlamaLogLevel.none,
        handler: records.add,
      );
      final backend = LiteRtLmBackend(workerEntryPoint: _loggingWorkerEntry);
      try {
        await backend.getBackendName().timeout(const Duration(seconds: 5));
        LlamaLogger.instance.setLevel(LlamaLogLevel.debug);
        await backend.getBackendName().timeout(const Duration(seconds: 5));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(records, isEmpty);
      } finally {
        await backend.dispose().timeout(const Duration(seconds: 2));
      }
    });

    test(
      'LlamaLogging.configure changes what a running worker forwards',
      () async {
        await LlamaLogging.configure(
          level: LlamaLogLevel.none,
          handler: records.add,
        );
        final backend = LiteRtLmBackend(workerEntryPoint: _loggingWorkerEntry);
        final engine = LlamaEngine(backend);
        try {
          await backend.getBackendName().timeout(const Duration(seconds: 5));
          await LlamaLogging.configure(
            level: LlamaLogLevel.warn,
            handler: records.add,
          ).timeout(const Duration(seconds: 5));
          await backend.getBackendName().timeout(const Duration(seconds: 5));
          await _waitForRecords(records, 1);
          expect(records.single.message, 'worker warning');
        } finally {
          await engine.dispose().timeout(const Duration(seconds: 2));
        }
      },
    );
  });

  test('worker exit before handshake settles startup', () async {
    final backend = LiteRtLmBackend(workerEntryPoint: _exitBeforeHandshake);
    await expectLater(
      backend.tokenize(1, 'hello').timeout(const Duration(seconds: 2)),
      throwsA(isA<LlamaStateException>()),
    );
    await expectLater(backend.dispose(), throwsA(isA<LlamaStateException>()));
  });

  test(
    'completed response stays successful when disposal follows immediately',
    () async {
      final port = ReceivePort();
      port.listen((message) {
        if (message is LiteRtLmTokenizeRequest) {
          message.sendPort.send(LiteRtLmTokenizeResponse([42]));
        } else if (message is LiteRtLmWorkerRequest) {
          message.sendPort.send(LiteRtLmDoneResponse());
        }
      });
      final backend = LiteRtLmBackend(initialSendPort: port.sendPort);
      try {
        expect(await backend.tokenize(1, 'hello'), [42]);
        await backend.dispose();
      } finally {
        port.close();
      }
    },
  );

  test(
    'abandoned request cleanup allows a CLI process to exit naturally',
    () async {
      // Running the source would compile the package before main, which took
      // over this exit deadline on loaded macOS CI runners.
      final child = await compileDartScript(
        'test/fixtures/litert_lm_pending_request_exit.dart',
      );
      final packageConfig = await Isolate.packageConfig;
      final process = await Process.start(Platform.resolvedExecutable, [
        '--packages=${packageConfig!.toFilePath()}',
        child,
      ]);
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      try {
        final code = await process.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
        expect(
          code,
          0,
          reason: 'phases:\n${await stdout}stderr:\n${await stderr}',
        );
      } finally {
        process.kill();
      }
    },
  );

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
      expect(tokenizeRequest.runtimePrompt, isFalse);

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

  test('routes runtime prompt tokenization through the LiteRT-LM worker '
      'without exposing it in the backend type', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[2, 10],
      detokenizeResponse: '',
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      expect(backend, isNot(isA<BackendRuntimePromptTokenization>()));
      expect(
        await runtimePromptTokenizerOf(
          backend,
        )!.tokenizeRuntimePrompt(42, '<bos>hi'),
        [2, 10],
      );

      final request = worker.requests
          .whereType<LiteRtLmTokenizeRequest>()
          .single;
      expect(request.modelHandle, 42);
      expect(request.text, '<bos>hi');
      expect(request.runtimePrompt, isTrue);
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

  test('sends deprecated language codes in chatTemplateKwargs', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      generationChunks: const [],
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      await backend
          .generateChat(
            7,
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
            ],
            const GenerationParams(maxTokens: 5),
            chatTemplateKwargs: const {'locale': 'en_CA'},
            // ignore: deprecated_member_use_from_same_package
            sourceLangCode: 'en',
            // ignore: deprecated_member_use_from_same_package
            targetLangCode: 'ko',
          )
          .drain<void>();

      final request = worker.requests
          .whereType<LiteRtLmGenerateChatRequest>()
          .single;
      expect(request.chatTemplateKwargs, {
        'locale': 'en_CA',
        'source_lang_code': 'en',
        'target_lang_code': 'ko',
      });
    } finally {
      await backend.dispose();
      worker.close();
    }
  });

  test('keeps typed unsupported worker errors across the isolate', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      generationErrorResponse: LiteRtLmErrorResponse(
        'remote image URLs are unsupported',
        kind: 'llamaUnsupported',
      ),
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      await expectLater(
        backend.generate(7, 'prompt', const GenerationParams()).drain<void>(),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'remote image URLs are unsupported',
          ),
        ),
      );
    } finally {
      await backend.dispose();
      worker.close();
    }
  });

  for (final (kind, matcher) in [
    ('llamaArgument', isA<LlamaArgumentException>()),
    ('llamaModel', isA<LlamaModelException>()),
    ('llamaContext', isA<LlamaContextException>()),
    ('llamaInference', isA<LlamaInferenceException>()),
    ('llamaState', isA<LlamaStateException>()),
  ]) {
    test('rebuilds a $kind worker error as its LlamaException', () async {
      final worker = _FakeLiteRtLmWorker(
        tokenizeResponse: const <int>[],
        detokenizeResponse: '',
        generationErrorResponse: LiteRtLmErrorResponse(
          '$kind failed',
          kind: kind,
        ),
      );
      final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

      try {
        await expectLater(
          backend.generate(7, 'prompt', const GenerationParams()).drain<void>(),
          throwsA(
            matcher.having((error) => error.message, 'message', '$kind failed'),
          ),
        );
      } finally {
        await backend.dispose();
        worker.close();
      }
    });
  }

  test('keeps the argument name of a worker llamaArgument error', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      generationErrorResponse: LiteRtLmErrorResponse(
        'needs prompt text',
        kind: 'llamaArgument',
        argumentName: 'prompt',
      ),
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      await expectLater(
        backend.generate(7, 'prompt', const GenerationParams()).drain<void>(),
        throwsA(
          isA<LlamaArgumentException>().having(
            (error) => error.name,
            'name',
            'prompt',
          ),
        ),
      );
    } finally {
      await backend.dispose();
      worker.close();
    }
  });

  test('keeps an unnamed worker llamaArgument error unnamed', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      generationErrorResponse: LiteRtLmErrorResponse(
        'bad combination',
        kind: 'llamaArgument',
      ),
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      await expectLater(
        backend.generate(7, 'prompt', const GenerationParams()).drain<void>(),
        throwsA(
          isA<LlamaArgumentException>().having(
            (error) => error.name,
            'name',
            isNull,
          ),
        ),
      );
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

  test('a completed generation sends the worker no cancel, then or on a '
      'later modelFree', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      generationChunks: [utf8.encode('Hi')],
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      final output = await backend
          .generate(1, 'first', const GenerationParams())
          .expand((bytes) => bytes)
          .toList();
      expect(utf8.decode(output), 'Hi');
      await _settle();
      expect(
        worker.requests.whereType<LiteRtLmCancelGenerationRequest>(),
        isEmpty,
      );

      await backend.modelFree(1);
      expect(
        worker.requests.whereType<LiteRtLmCancelGenerationRequest>(),
        isEmpty,
      );
    } finally {
      await backend.dispose();
      worker.close();
    }
  });

  test('a subscription cancel after cancelGeneration sends no second worker '
      'cancel', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      holdGeneration: true,
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

    try {
      final subscription = backend
          .generate(1, 'first', const GenerationParams())
          .listen((_) {});
      await worker.generateReceived.future;

      backend.cancelGeneration();
      await subscription.cancel();
      await _settle();
      expect(
        worker.requests.whereType<LiteRtLmCancelGenerationRequest>(),
        hasLength(1),
      );
    } finally {
      worker.releaseGeneration();
      await backend.dispose();
      worker.close();
    }
  });

  test(
    'modelFree after a subscription cancel sends no second worker cancel',
    () async {
      final worker = _FakeLiteRtLmWorker(
        tokenizeResponse: const <int>[],
        detokenizeResponse: '',
        holdGeneration: true,
      );
      final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

      try {
        final subscription = backend
            .generate(1, 'first', const GenerationParams())
            .listen((_) {});
        await worker.generateReceived.future;

        await subscription.cancel();
        await _settle();
        final freed = backend.modelFree(1);
        await _settle();
        expect(
          worker.requests.whereType<LiteRtLmCancelGenerationRequest>(),
          hasLength(1),
        );
        worker.releaseGeneration();
        await freed;
      } finally {
        worker.releaseGeneration();
        await backend.dispose();
        worker.close();
      }
    },
  );

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

  test('an engine subscription cancel before the first token cancels the '
      'worker generation', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      holdGeneration: true,
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);
    final engine = LlamaEngine(backend);

    try {
      await engine.loadModel(modelFile.path);
      final subscription = engine.generate('pending').listen((_) {});
      await worker.generateReceived.future;

      await subscription.cancel();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        worker.requests.whereType<LiteRtLmCancelGenerationRequest>(),
        hasLength(1),
      );
    } finally {
      worker.releaseGeneration();
      await backend.dispose();
      worker.close();
    }
  });

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

  for (final bundle in <({bool vision, bool audio, bool speculativeDecoding})?>[
    (vision: true, audio: false, speculativeDecoding: true),
    (vision: false, audio: true, speculativeDecoding: false),
    null,
  ]) {
    test('reports media and speculative decoding for bundle $bundle', () async {
      final worker = _FakeLiteRtLmWorker(
        tokenizeResponse: const <int>[],
        detokenizeResponse: '',
        bundleCapabilitiesResponse: bundle,
      );
      final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

      try {
        expect(await backend.directMediaInput(), (
          vision: bundle?.vision ?? false,
          audio: bundle?.audio ?? false,
        ));
        final capabilities = await backend.generationCapabilities();
        expect(capabilities.penalty, isFalse);
        expect(capabilities.presencePenalty, isFalse);
        expect(capabilities.minP, isFalse);
        expect(capabilities.thinkingBudget, isFalse);
        expect(capabilities.streamBatching, isTrue);
        expect(
          capabilities.speculativeDecodingStrategies,
          bundle?.speculativeDecoding == false
              ? isEmpty
              : <SpeculativeDecodingStrategy>{
                  SpeculativeDecodingStrategy.backendDefault,
                  SpeculativeDecodingStrategy.mtp,
                },
        );
        expect(
          worker.requests.whereType<LiteRtLmBundleCapabilitiesRequest>(),
          hasLength(2),
        );
      } finally {
        await backend.dispose();
        worker.close();
      }
    });
  }

  for (final controls in [
    (penalties: true, thinkingBudget: true),
    (penalties: true, thinkingBudget: false),
    (penalties: false, thinkingBudget: false),
  ]) {
    test('reports the generation controls the worker applies: '
        '$controls', () async {
      final worker = _FakeLiteRtLmWorker(
        tokenizeResponse: const <int>[],
        detokenizeResponse: '',
        generationControlsResponse: controls,
      );
      final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);

      try {
        final capabilities = await backend.generationCapabilities();
        expect(capabilities.penalty, controls.penalties);
        expect(capabilities.presencePenalty, controls.penalties);
        expect(capabilities.thinkingBudget, controls.thinkingBudget);
        expect(capabilities.minP, isFalse);
      } finally {
        await backend.dispose();
        worker.close();
      }
    });
  }

  for (final nativeChat in [false, true]) {
    test(
      'worker queued cancellation clears previous metrics (chat: $nativeChat)',
      () async {
        final service = _CounterRunService();
        final backend = LiteRtLmBackend(
          initialSendPort: await _startWorkerInCurrentIsolate(service),
        );
        addTearDown(() async {
          service.tokenizeGate?.complete();
          service.finishAll();
          await backend.dispose();
        });
        final first = _CollectedGeneration(
          backend.generate(1, 'first', const GenerationParams()),
        );
        (await service.started(0)).finish();
        await first.done;
        expect((await backend.getPerformanceContext(1))?.evalTokens, 7);
        service.tokenizeGate = Completer<void>();
        final tokenized = backend.tokenize(1, 'busy');
        await service.tokenizeStarted.future;
        final next = _CollectedGeneration(
          nativeChat
              ? backend.generateChat(1, [
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: 'next',
                  ),
                ], const GenerationParams())
              : backend.generate(1, 'next', const GenerationParams()),
        );
        await _settle();
        backend.cancelGeneration();
        await _settle();
        service.tokenizeGate!.complete();
        service.tokenizeGate = null;
        await tokenized;
        await next.done;
        expect(service.runs, hasLength(1));
        expect(await backend.getPerformanceContext(1), isNull);
      },
    );
  }

  test('failed LiteRT send invalidates previous counters', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const [],
      detokenizeResponse: '',
      generationChunks: const [],
      performanceContextResponse: LiteRtLmPerformanceContextResponse(
        loadMs: 1,
        promptEvalMs: 1,
        evalMs: 1,
        sampleMs: 0,
        promptEvalTokens: 1,
        evalTokens: 7,
        sampleCount: 7,
        reusedGraphs: 0,
      ),
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);
    addTearDown(() async {
      await backend.dispose();
      worker.close();
    });
    expect((await backend.getPerformanceContext(1))?.evalTokens, 7);
    final unsendable = ReceivePort();
    addTearDown(unsendable.close);
    await expectLater(
      backend.generateChat(
        1,
        [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'next')],
        const GenerationParams(),
        chatTemplateKwargs: {'port': unsendable},
      ),
      emitsError(isA<ArgumentError>()),
    );
    expect(await backend.getPerformanceContext(1), isNull);
    expect(worker.requests.whereType<LiteRtLmGenerateChatRequest>(), isEmpty);
    await backend
        .generate(1, 'recovery', const GenerationParams())
        .drain<void>();
    expect((await backend.getPerformanceContext(1))?.evalTokens, 7);
  });

  test('worker teardown clears stale marks before handle reuse', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const [],
      detokenizeResponse: '',
      generationChunks: const [],
      performanceContextResponse: LiteRtLmPerformanceContextResponse(
        loadMs: 1,
        promptEvalMs: 1,
        evalMs: 1,
        sampleMs: 0,
        promptEvalTokens: 1,
        evalTokens: 7,
        sampleCount: 7,
        reusedGraphs: 0,
      ),
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);
    addTearDown(() async {
      await backend.dispose();
      worker.close();
    });
    final unsendable = ReceivePort();
    addTearDown(unsendable.close);
    await expectLater(
      backend.generateChat(
        1,
        [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'next')],
        const GenerationParams(),
        chatTemplateKwargs: {'port': unsendable},
      ),
      emitsError(isA<ArgumentError>()),
    );
    expect(await backend.getPerformanceContext(1), isNull);
    final mirror = reflect(backend);
    final owner = mirror.type.owner as LibraryMirror;
    mirror.invoke(MirrorSystem.getSymbol('_stopWorker', owner), []);
    mirror.setField(
      MirrorSystem.getSymbol('_sendPort', owner),
      worker.sendPort,
    );
    expect((await backend.getPerformanceContext(1))?.evalTokens, 7);
  });

  test(
    'rejected LiteRT overlap preserves the running request counters',
    () async {
      final service = _CounterRunService();
      final backend = LiteRtLmBackend(
        initialSendPort: await _startWorkerInCurrentIsolate(service),
      );
      addTearDown(() async {
        final disposed = backend.dispose();
        service.finishAll();
        await disposed;
      });
      final active = _CollectedGeneration(
        backend.generate(1, 'active', const GenerationParams()),
      );
      final run = await service.started(0);
      await active.firstChunk;
      await expectLater(
        backend.generate(1, 'overlap', const GenerationParams()),
        emitsInOrder([emitsError(isA<LlamaStateException>()), emitsDone]),
      );
      run.finish();
      await active.done;
      expect((await backend.getPerformanceContext(1))?.evalTokens, 7);
    },
  );

  test(
    'LiteRT cancellation invalidates a perf RPC already waiting on the worker',
    () async {
      final service = _CounterRunService();
      final backend = LiteRtLmBackend(
        initialSendPort: await _startWorkerInCurrentIsolate(service),
      );
      addTearDown(() async {
        final disposed = backend.dispose();
        service.finishAll();
        await disposed;
      });
      final active = _CollectedGeneration(
        backend.generate(1, 'active', const GenerationParams()),
      );
      final run = await service.started(0);
      await active.firstChunk;
      final lookup = backend.getPerformanceContext(1);
      await _settle();
      backend.cancelGeneration();
      final abandoned = _CollectedGeneration(
        backend.generate(1, 'abandoned', const GenerationParams()),
      );
      await _settle();
      backend.cancelGeneration();
      await abandoned.done;
      run.finish();
      await active.done;
      expect(await lookup, isNull);
    },
  );

  test('stale LiteRT lookup cannot revive after a later dispatch', () async {
    final service = _CounterRunService();
    final workerPort = await _startWorkerInCurrentIsolate(service);
    final proxy = ReceivePort();
    final held = <LiteRtLmPerformanceContextRequest>[];
    proxy.listen((message) {
      if (message is LiteRtLmPerformanceContextRequest) {
        held.add(message);
      } else {
        workerPort.send(message);
      }
    });
    final backend = LiteRtLmBackend(initialSendPort: proxy.sendPort);
    addTearDown(() async {
      final disposed = backend.dispose();
      service.finishAll();
      await disposed;
      proxy.close();
    });
    final active = _CollectedGeneration(
      backend.generate(1, 'active', const GenerationParams()),
    );
    final run = await service.started(0);
    await active.firstChunk;
    backend.cancelGeneration();
    final abandoned = _CollectedGeneration(
      backend.generate(1, 'abandoned', const GenerationParams()),
    );
    await _settle();
    backend.cancelGeneration();
    await abandoned.done;
    run.finish();
    await active.done;
    final lookup = backend.getPerformanceContext(1);
    await _settle();
    final next = _CollectedGeneration(
      backend.generate(1, 'next', const GenerationParams()),
    );
    final nextRun = await service.started(1);
    nextRun.finish();
    await next.done;
    for (final request in held) {
      workerPort.send(request);
    }
    expect(await lookup, isNull);
    expect(held, isEmpty, reason: 'stale metrics need no worker RPC');
  });

  for (final nativeChat in [false, true]) {
    for (final subscriptionCancel in [false, true]) {
      test('unsent LiteRT cancellation invalidates only its context counters '
          '(chat: $nativeChat, subscription: $subscriptionCancel)', () async {
        final service = _CounterRunService();
        final backend = LiteRtLmBackend(
          initialSendPort: await _startWorkerInCurrentIsolate(service),
        );
        addTearDown(() async {
          final disposed = backend.dispose();
          service.finishAll();
          await disposed;
        });
        const params = GenerationParams();
        Stream<List<int>> start(String prompt) => nativeChat
            ? backend.generateChat(1, [
                LlamaChatMessage.fromText(
                  role: LlamaChatRole.user,
                  text: prompt,
                ),
              ], params)
            : backend.generate(1, prompt, params);
        final first = _CollectedGeneration(start('first'));
        final run = await service.started(0);
        await first.firstChunk;
        backend.cancelGeneration();
        final queued = _CollectedGeneration(start('queued'));
        await _settle();
        if (subscriptionCancel) {
          await queued.subscription.cancel();
        } else {
          backend.cancelGeneration();
          await queued.done;
        }
        run.finish();
        await first.done;
        expect((await backend.getPerformanceContext(2))?.evalTokens, 7);
        expect(await backend.getPerformanceContext(1), isNull);
        final next = _CollectedGeneration(start('next'));
        final nextRun = await service.started(1);
        await next.firstChunk;
        nextRun.finish();
        await next.done;
        expect((await backend.getPerformanceContext(1))?.evalTokens, 7);
        // Teardown must also forget a stale mark on a recycled handle.
        backend.cancelGeneration();
        final active = _CollectedGeneration(start('active'));
        final activeRun = await service.started(2);
        await active.firstChunk;
        backend.cancelGeneration();
        final abandoned = _CollectedGeneration(start('abandoned'));
        await _settle();
        backend.cancelGeneration();
        await abandoned.done;
        activeRun.finish();
        await active.done;
        await backend.contextFree(1);
        expect((await backend.getPerformanceContext(1))?.evalTokens, 7);
      });
    }
  }

  group('a generation started after a cancel', () {
    const params = GenerationParams(streamBatchTokenThreshold: 1);
    late _CancellableRunService service;
    late LiteRtLmBackend backend;

    setUp(() async {
      service = _CancellableRunService();
      backend = LiteRtLmBackend(
        initialSendPort: await _startWorkerInCurrentIsolate(service),
      );
    });

    tearDown(() async {
      // Dispose first: it ends any queued generation before the held runs
      // finish, so a test that failed with one queued cannot start it here.
      final disposed = backend.dispose();
      service.finishAll();
      await disposed;
    });

    // A stale queue entry would make the finished second generation start
    // again from every finish, a microtask loop that starves the isolate, so
    // this checks the queue while the second generation is still running.
    test('an admitted queued generation leaves the queue', () async {
      final first = _CollectedGeneration(backend.generate(1, 'first', params));
      final firstRun = await service.started(0);
      await first.firstChunk;

      backend.cancelGeneration();
      final second = _CollectedGeneration(
        backend.generate(1, 'second', params),
      );
      await _settle();
      firstRun.finish();
      final secondRun = await service.started(1);
      await second.firstChunk;

      await second.subscription.cancel();
      final third = _CollectedGeneration(backend.generate(1, 'third', params));
      await _settle();
      expect(third.error, isNull);

      secondRun.finish();
      final thirdRun = await service.started(2);
      thirdRun.finish();
      await third.done;
      expect(third.error, isNull);
      expect(third.text, 'third;');
      expect(service.runs.map((run) => run.prompt), [
        'first',
        'second',
        'third',
      ]);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('waits for a run stopped by cancelGeneration, then starts', () async {
      final first = _CollectedGeneration(backend.generate(1, 'first', params));
      final firstRun = await service.started(0);
      await first.firstChunk;

      backend.cancelGeneration();
      final second = _CollectedGeneration(
        backend.generate(1, 'second', params),
      );
      await _settle();
      expect(service.runs, hasLength(1));
      expect(second.error, isNull);

      firstRun.finish();
      await first.done;
      expect(first.error, isNull);
      expect(first.text, 'first;');

      final secondRun = await service.started(1);
      expect(secondRun.prompt, 'second');
      await second.firstChunk;
      secondRun.finish();
      await second.done;
      expect(second.error, isNull);
      expect(second.text, 'second;');
    });

    test(
      'waits for a run stopped by a subscription cancel, then starts',
      () async {
        final first = _CollectedGeneration(
          backend.generate(1, 'first', params),
        );
        final firstRun = await service.started(0);
        await first.firstChunk;

        await first.subscription.cancel();
        final second = _CollectedGeneration(
          backend.generate(1, 'second', params),
        );
        await _settle();
        expect(service.runs, hasLength(1));
        expect(service.cancelCount, greaterThanOrEqualTo(1));
        expect(second.error, isNull);

        firstRun.finish();
        final secondRun = await service.started(1);
        secondRun.finish();
        await second.done;
        expect(second.error, isNull);
        expect(second.text, 'second;');
      },
    );

    test('waits for a native chat run stopped by cancelGeneration', () async {
      final first = _CollectedGeneration(
        backend.generateChat(1, [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'chat'),
        ], params),
      );
      final firstRun = await service.started(0);
      await first.firstChunk;

      backend.cancelGeneration();
      final second = _CollectedGeneration(
        backend.generate(1, 'second', params),
      );
      await _settle();
      expect(service.runs, hasLength(1));

      firstRun.finish();
      await first.done;
      expect(first.error, isNull);
      final secondRun = await service.started(1);
      secondRun.finish();
      await second.done;
      expect(second.error, isNull);
      expect(second.text, 'second;');
    });

    test('a cancel before the request reaches the worker ends the stream '
        'without running it', () async {
      final first = _CollectedGeneration(backend.generate(1, 'first', params));
      backend.cancelGeneration();
      await first.done;
      expect(first.error, isNull);
      expect(first.text, isEmpty);
      expect(service.runs, isEmpty);

      final second = _CollectedGeneration(
        backend.generate(1, 'second', params),
      );
      final secondRun = await service.started(0);
      expect(secondRun.prompt, 'second');
      secondRun.finish();
      await second.done;
      expect(second.error, isNull);
      expect(second.text, 'second;');
    });

    test(
      'a cancel after completion does not affect the next generation',
      () async {
        final first = _CollectedGeneration(
          backend.generate(1, 'first', params),
        );
        (await service.started(0)).finish();
        await first.done;
        expect(first.text, 'first;');

        backend.cancelGeneration();
        await _settle();
        final second = _CollectedGeneration(
          backend.generate(1, 'second', params),
        );
        final secondRun = await service.started(1);
        await second.firstChunk;
        secondRun.finish();
        await second.done;
        expect(second.error, isNull);
        expect(second.text, 'second;');
      },
    );

    test('repeated cancels queue the next generation once', () async {
      final first = _CollectedGeneration(backend.generate(1, 'first', params));
      final firstRun = await service.started(0);
      await first.firstChunk;

      backend
        ..cancelGeneration()
        ..cancelGeneration();
      await first.subscription.cancel();
      backend.cancelGeneration();
      final second = _CollectedGeneration(
        backend.generate(1, 'second', params),
      );
      await _settle();
      expect(service.runs, hasLength(1));

      firstRun.finish();
      final secondRun = await service.started(1);
      await second.firstChunk;
      secondRun.finish();
      await second.done;
      expect(second.error, isNull);
      expect(second.text, 'second;');
      expect(service.runs, hasLength(2));
    });

    test('a subscription cancel of the cancelled run does not end the '
        'generation queued behind it', () async {
      final first = _CollectedGeneration(backend.generate(1, 'first', params));
      final firstRun = await service.started(0);
      await first.firstChunk;

      backend.cancelGeneration();
      final second = _CollectedGeneration(
        backend.generate(1, 'second', params),
      );
      await first.subscription.cancel();
      await _settle();
      expect(second.isDone, isFalse);

      firstRun.finish();
      final secondRun = await service.started(1);
      secondRun.finish();
      await second.done;
      expect(second.error, isNull);
      expect(second.text, 'second;');
    });

    test(
      'cancelGeneration ends a queued generation without running it',
      () async {
        final first = _CollectedGeneration(
          backend.generate(1, 'first', params),
        );
        final firstRun = await service.started(0);
        await first.firstChunk;

        backend.cancelGeneration();
        final second = _CollectedGeneration(
          backend.generate(1, 'second', params),
        );
        await _settle();
        backend.cancelGeneration();
        await second.done;
        expect(second.error, isNull);
        expect(second.text, isEmpty);

        firstRun.finish();
        await first.done;
        final third = _CollectedGeneration(
          backend.generate(1, 'third', params),
        );
        final thirdRun = await service.started(1);
        expect(thirdRun.prompt, 'third');
        thirdRun.finish();
        await third.done;
        expect(third.error, isNull);
        expect(third.text, 'third;');
        expect(service.runs.map((run) => run.prompt), ['first', 'third']);
      },
    );

    test(
      'a subscription cancel of a queued generation leaves the queue',
      () async {
        final first = _CollectedGeneration(
          backend.generate(1, 'first', params),
        );
        final firstRun = await service.started(0);
        await first.firstChunk;

        backend.cancelGeneration();
        final second = _CollectedGeneration(
          backend.generate(1, 'second', params),
        );
        await _settle();
        await second.subscription.cancel();
        final third = _CollectedGeneration(
          backend.generate(1, 'third', params),
        );
        await _settle();
        expect(third.error, isNull);

        firstRun.finish();
        final thirdRun = await service.started(1);
        thirdRun.finish();
        await third.done;
        expect(third.error, isNull);
        expect(third.text, 'third;');
        expect(service.runs.map((run) => run.prompt), ['first', 'third']);
      },
    );

    test('dispose ends a queued generation without running it', () async {
      final first = _CollectedGeneration(backend.generate(1, 'first', params));
      final firstRun = await service.started(0);
      await first.firstChunk;

      backend.cancelGeneration();
      final second = _CollectedGeneration(
        backend.generate(1, 'second', params),
      );
      await _settle();

      final disposed = backend.dispose();
      firstRun.finish();
      await disposed;
      await second.done;
      expect(second.error, isNull);
      expect(second.text, isEmpty);
      expect(service.runs, hasLength(1));
    });

    for (final teardown in ['modelFree', 'contextFree', 'modelLoad']) {
      test('$teardown ends a queued generation without running it', () async {
        final first = _CollectedGeneration(
          backend.generate(1, 'first', params),
        );
        final firstRun = await service.started(0);
        await first.firstChunk;

        backend.cancelGeneration();
        final second = _CollectedGeneration(
          backend.generate(1, 'second', params),
        );
        await _settle();
        final settled = switch (teardown) {
          'modelFree' => backend.modelFree(1),
          'contextFree' => backend.contextFree(1),
          _ => backend.modelLoad(modelFile.path, const ModelParams()),
        }.then<void>((_) {}, onError: (Object _) {});
        await second.done;
        expect(second.error, isNull);
        expect(second.text, isEmpty);

        firstRun.finish();
        await settled;
        await _settle();
        expect(service.runs.map((run) => run.prompt), ['first']);
      });
    }

    for (final teardown in ['modelFree', 'contextFree', 'modelLoad']) {
      test('a generation started during $teardown waits for the run it '
          'cancels', () async {
        final first = _CollectedGeneration(
          backend.generate(1, 'first', params),
        );
        final firstRun = await service.started(0);
        await first.firstChunk;

        final settled = switch (teardown) {
          'modelFree' => backend.modelFree(1),
          'contextFree' => backend.contextFree(1),
          _ => backend.modelLoad(modelFile.path, const ModelParams()),
        }.then<void>((_) {}, onError: (Object _) {});
        final second = _CollectedGeneration(
          backend.generate(1, 'second', params),
        );
        await _settle();
        expect(second.error, isNull);

        firstRun.finish();
        await settled;
        final secondRun = await service.started(1);
        secondRun.finish();
        await second.done;
        expect(second.error, isNull);
        expect(second.text, 'second;');
      });
    }

    test(
      'a generation requested during dispose reports the disposed backend',
      () async {
        final first = _CollectedGeneration(
          backend.generate(1, 'first', params),
        );
        final firstRun = await service.started(0);
        await first.firstChunk;

        final disposed = backend.dispose();
        final second = _CollectedGeneration(
          backend.generate(1, 'second', params),
        );
        await _settle();
        firstRun.finish();
        await disposed;
        await second.done;
        expect(
          second.error,
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('disposed'),
          ),
        );
        expect(service.runs, hasLength(1));
      },
    );

    test('a generation requested right after cancelGeneration ends the '
        'queued one takes its place', () async {
      final first = _CollectedGeneration(backend.generate(1, 'first', params));
      final firstRun = await service.started(0);
      await first.firstChunk;

      backend.cancelGeneration();
      final second = _CollectedGeneration(
        backend.generate(1, 'second', params),
      );
      await _settle();
      backend.cancelGeneration();
      final third = _CollectedGeneration(backend.generate(1, 'third', params));
      await _settle();
      expect(third.error, isNull);

      firstRun.finish();
      final thirdRun = await service.started(1);
      thirdRun.finish();
      await third.done;
      expect(second.text, isEmpty);
      expect(third.error, isNull);
      expect(third.text, 'third;');
      expect(service.runs.map((run) => run.prompt), ['first', 'third']);
    });

    test('a generation the worker fails frees the slot', () async {
      service.failPrompt = 'boom';
      final first = _CollectedGeneration(backend.generate(1, 'boom', params));
      await first.done;
      expect(first.error, isA<StateError>());

      final second = _CollectedGeneration(
        backend.generate(1, 'second', params),
      );
      final secondRun = await service.started(0);
      secondRun.finish();
      await second.done;
      expect(second.error, isNull);
      expect(second.text, 'second;');
    });

    test('a cancelled run that ends with a worker error starts the '
        'generation queued behind it', () async {
      service.failAfterFinish = true;
      final first = _CollectedGeneration(backend.generate(1, 'first', params));
      final firstRun = await service.started(0);
      await first.firstChunk;

      backend.cancelGeneration();
      final second = _CollectedGeneration(
        backend.generate(1, 'second', params),
      );
      await _settle();
      firstRun.finish();
      await first.done;
      expect(first.error, isA<StateError>());

      final secondRun = await service.started(1);
      service.failAfterFinish = false;
      secondRun.finish();
      await second.done;
      expect(second.error, isNull);
      expect(second.text, 'second;');
    });

    test('a token after a subscription cancel is dropped', () async {
      service.tokenAfterFinish = true;
      final first = _CollectedGeneration(backend.generate(1, 'first', params));
      final firstRun = await service.started(0);
      await first.firstChunk;

      await first.subscription.cancel();
      firstRun.finish();
      final second = _CollectedGeneration(
        backend.generate(1, 'second', params),
      );
      final secondRun = await service.started(1);
      service.tokenAfterFinish = false;
      secondRun.finish();
      await second.done;
      expect(
        service.lateTokens,
        1,
        reason: 'the late token reached the worker',
      );
      expect(second.error, isNull);
      expect(second.text, 'second;');
    });

    test('overlapping a generation that was not cancelled throws '
        'LlamaStateException', () async {
      final first = _CollectedGeneration(backend.generate(1, 'first', params));
      final firstRun = await service.started(0);
      await first.firstChunk;

      final second = _CollectedGeneration(
        backend.generate(1, 'second', params),
      );
      await second.done;
      expect(
        second.error,
        isA<LlamaStateException>().having(
          (error) => error.message,
          'message',
          contains('already in progress'),
        ),
      );

      firstRun.finish();
      await first.done;
      expect(first.error, isNull);
      expect(first.text, 'first;');
      expect(service.runs, hasLength(1));
    });

    test('a second generation queued behind a cancel throws '
        'LlamaStateException', () async {
      final first = _CollectedGeneration(backend.generate(1, 'first', params));
      final firstRun = await service.started(0);
      await first.firstChunk;

      backend.cancelGeneration();
      final second = _CollectedGeneration(
        backend.generate(1, 'second', params),
      );
      final third = _CollectedGeneration(backend.generate(1, 'third', params));
      await third.done;
      expect(third.error, isA<LlamaStateException>());

      firstRun.finish();
      final secondRun = await service.started(1);
      secondRun.finish();
      await second.done;
      expect(second.error, isNull);
      expect(second.text, 'second;');
      expect(service.runs.map((run) => run.prompt), ['first', 'second']);
    });
  });

  test(
    'quarantine settles all callers before queued generation dispatch',
    () async {
      final commands = ReceivePort();
      final generationRequest = Completer<LiteRtLmGenerateRequest>();
      final tokenizeRequest = Completer<void>();
      var generationCount = 0;
      commands.listen((message) {
        if (message is LiteRtLmGenerateRequest) {
          generationCount++;
          if (!generationRequest.isCompleted) {
            generationRequest.complete(message);
          }
        } else if (message is LiteRtLmTokenizeRequest) {
          tokenizeRequest.complete();
        } else if (message is LiteRtLmCancelGenerationRequest) {
          message.sendPort.send(
            LiteRtLmDoneResponse(
              nativeSettlement: LiteRtLmNativeSettlement.pending,
            ),
          );
        }
      });
      final backend = LiteRtLmBackend(initialSendPort: commands.sendPort);
      final subscription = backend
          .generate(1, 'first', const GenerationParams())
          .listen((_) {});
      final first = await generationRequest.future;
      final pending = expectLater(
        backend.tokenize(1, 'pending'),
        throwsA(isA<LlamaStateException>()),
      );
      await tokenizeRequest.future;
      await subscription.cancel();
      final queued = expectLater(
        backend.generate(1, 'queued', const GenerationParams()).toList(),
        throwsA(isA<LlamaStateException>()),
      );
      first.sendPort.send(
        LiteRtLmErrorResponse(
          'drain failed',
          kind: 'llamaModel',
          nativeSettlement: LiteRtLmNativeSettlement.quarantined,
        ),
      );
      await Future.wait([pending, queued]).timeout(const Duration(seconds: 2));
      expect(generationCount, 1);
      await expectLater(backend.dispose(), throwsA(isA<LlamaStateException>()));
      commands.close();
    },
  );

  test('a worker exit ends a generation queued behind a cancel', () async {
    final backend = LiteRtLmBackend(workerEntryPoint: _exitOnCancelWorker);
    const params = GenerationParams(streamBatchTokenThreshold: 1);
    final first = _CollectedGeneration(backend.generate(1, 'first', params));
    await first.firstChunk;

    backend.cancelGeneration();
    final second = _CollectedGeneration(backend.generate(1, 'second', params));
    await first.done;
    await second.done;
    expect(first.error, isA<LlamaStateException>());
    expect(second.error, isA<LlamaStateException>());
    expect(second.text, isEmpty);
    await expectLater(backend.dispose(), throwsA(isA<LlamaStateException>()));
  });

  test('a generation after a worker exit during a cancelled run reports the '
      'unsettled worker', () async {
    final backend = LiteRtLmBackend(workerEntryPoint: _exitOnCancelWorker);
    const params = GenerationParams(streamBatchTokenThreshold: 1);
    final first = _CollectedGeneration(backend.generate(1, 'first', params));
    await first.firstChunk;

    backend.cancelGeneration();
    await first.done;
    final second = _CollectedGeneration(backend.generate(1, 'second', params));
    await second.done;
    expect(
      second.error,
      isA<LlamaStateException>().having(
        (error) => error.message,
        'message',
        contains('native cleanup was confirmed'),
      ),
    );
    await expectLater(backend.dispose(), throwsA(isA<LlamaStateException>()));
  });

  test(
    'embedding startup timeout before request construction stays typed',
    () async {
      final worker = _FakeLiteRtLmWorker(
        tokenizeResponse: const [],
        detokenizeResponse: '',
        generationChunks: const [],
      );
      final backend = LiteRtLmBackend(
        initialSendPort: worker.sendPort,
        workerEntryPoint: _silentWorker,
        workerStartupTimeout: const Duration(milliseconds: 50),
      );
      final mirror = reflect(backend);
      final owner = mirror.type.owner as LibraryMirror;
      final portField = MirrorSystem.getSymbol('_sendPort', owner);
      addTearDown(() async {
        mirror.setField(portField, worker.sendPort);
        await backend.dispose();
        worker.close();
      });
      await backend.modelLoad(
        'fake.litertlm',
        const ModelParams(liteRtLmEmbeddingEngine: true),
      );
      // Normal lifecycle paths clear embedding mode with the port. Simulate
      // future startup/recovery wiring without adding a production test hook.
      mirror.setField(portField, null);
      await expectLater(
        backend.embed(1, 'hello'),
        throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.message,
            'startup diagnostic',
            contains('startup timed out'),
          ),
        ),
      );
      expect(worker.requests.whereType<LiteRtLmEmbedRequest>(), isEmpty);
      expect(
        worker.requests.whereType<LiteRtLmCancelGenerationRequest>(),
        isEmpty,
      );
    },
  );

  test('a worker startup timeout releases the generation slot', () async {
    final backend = LiteRtLmBackend(
      workerEntryPoint: _silentWorker,
      workerStartupTimeout: const Duration(milliseconds: 50),
    );
    const params = GenerationParams();
    final first = _CollectedGeneration(backend.generate(1, 'first', params));
    await first.doneWithin(const Duration(seconds: 2));
    expect(first.error, isA<TimeoutException>());

    // The retry makes its own startup attempt instead of waiting behind the
    // failed one.
    final second = _CollectedGeneration(backend.generate(1, 'second', params));
    await second.doneWithin(const Duration(seconds: 2));
    expect(second.error, isA<TimeoutException>());
    await backend.dispose();
  });

  test('a worker exit during startup releases the generation slot', () async {
    final backend = LiteRtLmBackend(workerEntryPoint: _exitBeforeHandshake);
    const params = GenerationParams();
    final first = _CollectedGeneration(backend.generate(1, 'first', params));
    await first.done;
    expect(first.error, isA<LlamaStateException>());

    final second = _CollectedGeneration(backend.generate(1, 'second', params));
    await second.done;
    expect(
      second.error,
      isA<LlamaStateException>().having(
        (error) => error.message,
        'message',
        allOf(
          contains('native cleanup was confirmed'),
          isNot(contains('already in progress')),
        ),
      ),
    );
    await expectLater(backend.dispose(), throwsA(isA<LlamaStateException>()));
  });

  test('LlamaEngine starts a generation requested right after '
      'cancelGeneration', () async {
    final worker = _FakeLiteRtLmWorker(
      tokenizeResponse: const <int>[],
      detokenizeResponse: '',
      holdGeneration: true,
      generationChunks: [utf8.encode('Hi')],
    );
    final backend = LiteRtLmBackend(initialSendPort: worker.sendPort);
    final engine = LlamaEngine(backend);

    try {
      await engine.loadModel(modelFile.path);
      final firstDone = Completer<void>();
      final first = engine
          .generate('first')
          .listen(
            (_) {},
            onError: firstDone.completeError,
            onDone: firstDone.complete,
          );
      await worker.generateReceived.future;

      engine.cancelGeneration();
      final second = engine.generate('second').join();
      await _settle();
      expect(
        worker.requests.whereType<LiteRtLmGenerateRequest>(),
        hasLength(1),
      );

      worker.releaseGeneration();
      await firstDone.future;
      await first.cancel();
      expect(await second, 'Hi');
      expect(
        worker.requests.whereType<LiteRtLmGenerateRequest>().map(
          (request) => request.prompt,
        ),
        ['first', 'second'],
      );
    } finally {
      worker.releaseGeneration();
      await backend.dispose();
      worker.close();
    }
  });
}

String _expectedAutoLiteRtLmBackend() {
  if (Platform.isAndroid || liteRtLmGateAbi() == Abi.macosArm64) {
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
    this.bundleCapabilitiesResponse,
    this.generationControlsResponse = (penalties: false, thinkingBudget: false),
    this.reportsFinishReasons = false,
    this.generationLimit,
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
  final ({bool vision, bool audio, bool speculativeDecoding})?
  bundleCapabilitiesResponse;
  final ({bool penalties, bool thinkingBudget}) generationControlsResponse;
  final bool reportsFinishReasons;
  final BackendGenerationLimit? generationLimit;
  LiteRtLmErrorResponse? modelLoadErrorResponse;
  LiteRtLmErrorResponse? schemaAdmissionError;
  bool schemaAdmitsThinking = false;
  Completer<void>? schemaAdmissionStarted;
  Completer<void>? schemaAdmissionGate;
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
              (_) => message.sendPort.send(
                LiteRtLmDoneResponse(generationLimit: generationLimit),
              ),
            ),
          );
        } else {
          message.sendPort.send(
            LiteRtLmDoneResponse(generationLimit: generationLimit),
          );
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
              (_) => message.sendPort.send(
                LiteRtLmDoneResponse(generationLimit: generationLimit),
              ),
            ),
          );
        } else {
          message.sendPort.send(
            LiteRtLmDoneResponse(generationLimit: generationLimit),
          );
        }
      case LiteRtLmJsonSchemaPrepareRequest():
        schemaAdmissionStarted?.complete();
        final gate = schemaAdmissionGate;
        Object admission() =>
            schemaAdmissionError ??
            LiteRtLmJsonSchemaAdmissionResponse(thinking: schemaAdmitsThinking);
        if (gate == null) {
          message.sendPort.send(admission());
        } else {
          unawaited(
            gate.future.then((_) => message.sendPort.send(admission())),
          );
        }
      case LiteRtLmModelLoadRequest():
        final loadError = modelLoadErrorResponse;
        if (loadError != null) {
          message.sendPort.send(loadError);
          break;
        }
        message.sendPort.send(
          LiteRtLmHandleResponse(1, reportsFinishReasons: reportsFinishReasons),
        );
      case LiteRtLmContextCreateRequest():
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
      case LiteRtLmBundleCapabilitiesRequest():
        message.sendPort.send(
          LiteRtLmBundleCapabilitiesResponse(bundleCapabilitiesResponse),
        );
      case LiteRtLmGenerationControlsRequest():
        message.sendPort.send(
          LiteRtLmGenerationControlsResponse(
            penalties: generationControlsResponse.penalties,
            thinkingBudget: generationControlsResponse.thinkingBudget,
          ),
        );
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

void _exitBeforeHandshake(SendPort port) => Isolate.exit();

void _silentWorker(SendPort port) {
  ReceivePort();
}

void _loggingWorkerEntry(SendPort port) {
  runLiteRtLmWorkerForTesting(port, _LoggingLiteRtLmService());
}

Future<void> _waitForRecords(List<LlamaLogRecord> records, int count) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (records.length < count && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _LoggingLiteRtLmService extends LiteRtLmService {
  @override
  void setLogLevel(LlamaLogLevel level) {}

  @override
  String getActiveBackendName() {
    LlamaLogger.instance.warn('worker warning', StateError('worker detail'));
    return 'logging';
  }

  @override
  void dispose() {}
}

void _exitingWorker(SendPort port) => _terminatingWorker(port, crash: false);

void _crashingWorker(SendPort port) => _terminatingWorker(port, crash: true);

void _terminatingWorker(SendPort port, {required bool crash}) {
  final receive = ReceivePort();
  port.send(receive.sendPort);
  var requests = 0;
  receive.listen((message) {
    if (message is LiteRtLmWorkerHandshake) return;
    if (++requests == 3) {
      if (crash) throw StateError('injected worker failure');
      Isolate.exit();
    }
  });
}

void _exitOnCancelWorker(SendPort port) {
  final receive = ReceivePort();
  port.send(receive.sendPort);
  receive.listen((message) {
    if (message is LiteRtLmGenerateRequest ||
        message is LiteRtLmGenerateChatRequest) {
      (message as LiteRtLmWorkerRequest).sendPort.send(
        LiteRtLmTokenResponse([65]),
      );
    } else if (message is LiteRtLmCancelGenerationRequest) {
      Isolate.exit();
    }
  });
}

void _exitDuringTeardownWorker(SendPort port) {
  final receive = ReceivePort();
  port.send(receive.sendPort);
  receive.listen((message) {
    if (message is LiteRtLmModelLoadRequest) {
      message.sendPort.send(LiteRtLmHandleResponse(1));
    } else if (message is LiteRtLmContextFreeRequest ||
        message is LiteRtLmModelFreeRequest ||
        message is LiteRtLmDisposeRequest) {
      (message as LiteRtLmWorkerRequest).sendPort.send(
        const LiteRtLmNativeTeardownStarted(),
      );
      Isolate.exit();
    } else if (message is LiteRtLmWorkerRequest) {
      message.sendPort.send(LiteRtLmDoneResponse());
    }
  });
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

Future<SendPort> _startWorkerInCurrentIsolate(LiteRtLmService service) async {
  final receivePort = ReceivePort();
  runLiteRtLmWorkerForTesting(
    receivePort.sendPort,
    service,
    exitOnDispose: false,
  );
  final sendPort = await receivePort.first as SendPort;
  receivePort.close();
  sendPort.send(LiteRtLmWorkerHandshake(LlamaLogLevel.warn));
  return sendPort;
}

final class _CollectedGeneration {
  _CollectedGeneration(Stream<List<int>> stream) {
    subscription = stream.listen(
      (bytes) {
        _bytes.addAll(bytes);
        if (!_firstChunk.isCompleted) _firstChunk.complete();
      },
      onError: (Object error) => this.error = error,
      onDone: _done.complete,
    );
  }

  late final StreamSubscription<List<int>> subscription;
  final List<int> _bytes = <int>[];
  final Completer<void> _firstChunk = Completer<void>();
  final Completer<void> _done = Completer<void>();
  Object? error;

  String get text => utf8.decode(_bytes);
  bool get isDone => _done.isCompleted;
  Future<void> get firstChunk =>
      _firstChunk.future.timeout(const Duration(seconds: 2));
  Future<void> get done => doneWithin(const Duration(seconds: 2));

  Future<void> doneWithin(Duration limit) => _done.future.timeout(limit);
}

final class _ServiceRun {
  _ServiceRun(this.prompt);

  final String prompt;
  final Completer<void> _stopped = Completer<void>();

  void finish() {
    if (!_stopped.isCompleted) _stopped.complete();
  }
}

/// Streams one token per run, then holds the run open until the test calls
/// [_ServiceRun.finish], like a native run that takes time to stop after a
/// cancel.
class _CancellableRunService extends LiteRtLmService {
  final List<_ServiceRun> runs = <_ServiceRun>[];
  final List<Completer<_ServiceRun>> _started = List.generate(
    8,
    (_) => Completer<_ServiceRun>(),
  );
  int cancelCount = 0;

  /// A prompt whose run fails before it starts.
  String? failPrompt;

  /// Whether a finished run fails instead of ending normally.
  bool failAfterFinish = false;

  /// Whether a finished run streams one more token before it ends.
  bool tokenAfterFinish = false;

  /// How many tokens finished runs streamed after [_ServiceRun.finish].
  int lateTokens = 0;

  Future<_ServiceRun> started(int index) =>
      _started[index].future.timeout(const Duration(seconds: 2));

  void finishAll() {
    for (final run in runs) {
      run.finish();
    }
  }

  Stream<List<int>> _run(String prompt) async* {
    if (prompt == failPrompt) throw StateError('native failure');
    final run = _ServiceRun(prompt);
    runs.add(run);
    _started[runs.length - 1].complete(run);
    yield utf8.encode('$prompt;');
    await run._stopped.future;
    if (tokenAfterFinish) {
      lateTokens += 1;
      yield utf8.encode('late;');
    }
    if (failAfterFinish) throw StateError('native failure after finish');
  }

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<api.LlamaContentPart>? parts,
  }) => _run(prompt);

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
  }) => _run(messages.last.content);

  @override
  void cancelGeneration() {
    cancelCount += 1;
  }

  @override
  Future<int> loadModel(
    String path,
    api.ModelParams params, {
    String? backendOverride,
  }) async => 1;

  @override
  void freeModel(int modelHandle) {}

  @override
  void freeContext(int contextHandle) {}
}

class _CounterRunService extends _CancellableRunService {
  BackendPerfContextData? metrics;
  Completer<void>? tokenizeGate;
  final tokenizeStarted = Completer<void>();

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text,
    bool addSpecial,
  ) async {
    tokenizeStarted.complete();
    await tokenizeGate?.future;
    return const [1];
  }

  @override
  Stream<List<int>> _run(String prompt) async* {
    metrics = null;
    try {
      yield* super._run(prompt);
    } finally {
      metrics = _completedMetrics;
    }
  }

  @override
  void resetPerformanceMetrics() {
    metrics = null;
  }

  @override
  BackendPerfContextData? getPerformanceContext(int contextHandle) => metrics;

  static const _completedMetrics = BackendPerfContextData(
    loadMs: 1,
    promptEvalMs: 1,
    evalMs: 1,
    sampleMs: 0,
    promptEvalTokens: 1,
    evalTokens: 7,
    sampleCount: 7,
    reusedGraphs: 0,
  );
}

void Function(SendPort) _embeddingStartupWorker(SendPort control) => (initial) {
  control.send(initial);
  ReceivePort().listen((_) {});
};
