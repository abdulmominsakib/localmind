@TestOn('vm')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_backend.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/worker.dart';
import 'package:llamadart/src/backends/native/native_backend.dart';
import 'package:llamadart/src/core/decision/decision_question.dart';
import 'package:llamadart/src/core/engine/engine.dart';
import 'package:llamadart/src/core/engine/engine_capabilities.dart';
import 'package:llamadart/src/core/engine/engine_observer.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/llama_logging.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/config/compute_device.dart';
import 'package:llamadart/src/core/models/config/gpu_backend.dart';
import 'package:llamadart/src/core/models/config/gpu_device_info.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/config/lora_config.dart';
import 'package:llamadart/src/core/models/download/model_download_manager.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/generation_usage.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:llamadart/src/core/models/inference/next_token_scores.dart';
import 'package:llamadart/src/core/models/inference/state_identity.dart';
import 'package:llamadart/src/core/models/model_format.dart';
import 'package:llamadart/src/core/models/model_load_options.dart';
import 'package:llamadart/src/core/models/model_source.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/models/inference/embedding.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:test/test.dart';

import '../../core/engine/engine_test.dart';
import '../../core/engine/multimodal_embeddings_test.dart';

void main() {
  test(
    'prompt penalty capability follows the loaded delegate and explicit false probe',
    () async {
      for (final supported in [false, true]) {
        final delegate = _PromptPenaltyDelegate(supported);
        final router = NativeAutoBackend(llamaCppFactory: () => delegate);
        expect(router.supportsPromptPenaltiesWithGrammar, isFalse);
        await router.modelLoad('fake.gguf', const ModelParams());
        expect(router.supportsPromptPenaltiesWithGrammar, supported);
        if (supported) {
          await router
              .generateWithPromptPenalties(
                1,
                'p',
                const GenerationParams(),
                mediaMarker: '<m>',
              )
              .drain<void>();
          expect(delegate.policyCalls, 1);
          expect(delegate.marker, '<m>');
        } else {
          expect(
            () => router.generateWithPromptPenalties(
              1,
              'p',
              const GenerationParams(),
            ),
            throwsA(isA<LlamaUnsupportedException>()),
          );
          expect(delegate.policyCalls, 0);
        }
        await router.dispose();
      }
      final router = NativeAutoBackend(
        llamaCppFactory: () => MockLlamaBackend(),
      );
      await router.modelLoad('fake.gguf', const ModelParams());
      expect(router.supportsPromptPenaltiesWithGrammar, isFalse);
      expect(
        () => router.generateWithPromptPenalties(
          1,
          'p',
          const GenerationParams(),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      await router.dispose();
    },
  );

  test('router cancels content during its own capability probe', () async {
    final delegate = ContentBackend()..probeGate = Completer<void>();
    final router = NativeAutoBackend(llamaCppFactory: () => delegate);
    addTearDown(router.dispose);
    final model = await router.modelLoad('fake.gguf', const ModelParams());
    final context = await router.contextCreate(model, const ModelParams());
    final input = LlamaEmbeddingInput([const LlamaTextContent('text')]);
    final future = router.embedContentBatch(context, List.filled(64, input));
    await pumpEventQueue();
    router.cancelGeneration();
    final cancelled = expectLater(
      future,
      throwsA(isA<LlamaInferenceException>()),
    );
    delegate.probeGate!.complete();
    await cancelled;
    expect(delegate.received, isEmpty);
    expect(await router.embedContentBatch(context, [input]), [
      [1.0],
    ]);
  });

  test(
    'unloaded context probes return all-false without creating a runtime',
    () async {
      final router = NativeAutoBackend(
        llamaCppFactory: () =>
            throw StateError('probe must not create a runtime'),
        liteRtLmFactory: () =>
            throw StateError('probe must not create a runtime'),
      );
      addTearDown(router.dispose);
      final capabilities = await router.getEmbeddingCapabilities(-1);
      expect(capabilities.text, isFalse);
      expect(capabilities.image, isFalse);
      expect(capabilities.audio, isFalse);
    },
  );

  for (final runtime in LlamaRuntime.values) {
    test(
      'embedding diagnostic identifies $runtime through the router',
      () async {
        final delegate = RuntimeContentBackend(runtime)
          ..supported = const LlamaEmbeddingCapabilities(text: true);
        final router = NativeAutoBackend(llamaCppFactory: () => delegate);
        final engine = LlamaEngine(router);
        addTearDown(engine.dispose);
        await engine.loadModel('fake.gguf');
        await expectLater(
          engine.embedContent(
            LlamaEmbeddingInput([const LlamaImageContent(path: 'secret.png')]),
          ),
          throwsA(
            isA<LlamaUnsupportedException>()
                .having((e) => e.message, 'runtime', contains(runtime.name))
                .having((e) => e.message, 'modality', contains('image'))
                .having(
                  (e) => e.message,
                  'condition',
                  contains('capability probe'),
                )
                .having(
                  (e) => e.message,
                  'redaction',
                  isNot(contains('secret')),
                ),
          ),
        );
      },
    );
  }

  test(
    'all current native backends reject image and audio embeddings before inference',
    () async {
      for (final backend in <LlamaBackend>[
        NativeLlamaBackend(),
        LiteRtLmBackend(),
        NativeAutoBackend(),
      ]) {
        addTearDown(backend.dispose);
        final capabilities = await backend.probeEmbeddingCapabilities(1);
        expect(capabilities.image, isFalse);
        expect(capabilities.audio, isFalse);
        for (final part in <LlamaContentPart>[
          const LlamaImageContent(path: 'secret.png'),
          const LlamaAudioContent(path: 'secret.wav'),
        ]) {
          final input = LlamaEmbeddingInput([part]);
          await expectLater(
            backend.embedContentWithFallback(1, [input]),
            throwsA(
              isA<LlamaUnsupportedException>()
                  .having(
                    (error) => error.message,
                    'modality',
                    contains(input.partKinds.single.name),
                  )
                  .having(
                    (error) => error.message,
                    'redaction',
                    isNot(contains('secret')),
                  ),
            ),
          );
        }
      }
    },
  );

  test(
    'router forwards loaded embedding probe and ordered content to its delegate',
    () async {
      final delegate = ContentBackend();
      final router = NativeAutoBackend(llamaCppFactory: () => delegate);
      final engine = LlamaEngine(router);
      addTearDown(engine.dispose);
      expect((await router.getEmbeddingCapabilities(1)).image, isFalse);
      await engine.loadModel('fake.gguf');
      expect((await engine.embeddingCapabilities).image, isTrue);
      final input = LlamaEmbeddingInput([
        const LlamaImageContent(path: 'image.png'),
        const LlamaTextContent('caption'),
      ]);
      expect(await engine.embedContent(input, normalize: false), [2.0]);
      expect(delegate.received.single, same(input));
      expect(delegate.normalized, isFalse);
    },
  );

  test(
    'router uses legacy text fallback and reports media unavailable',
    () async {
      final delegate = MockEmbeddingBackend();
      final router = NativeAutoBackend(llamaCppFactory: () => delegate);
      final engine = LlamaEngine(router);
      addTearDown(engine.dispose);
      await engine.loadModel('fake.gguf');
      final capabilities = await engine.embeddingCapabilities;
      expect(capabilities.text, isTrue);
      expect(capabilities.image, isFalse);
      final input = LlamaEmbeddingInput([const LlamaTextContent('same')]);
      expect(await engine.embedContent(input), await engine.embed('same'));
    },
  );

  for (final action in ['dispose', 'switch']) {
    test(
      'retains failed LiteRT cleanup through router $action and reload',
      () async {
        final port = ReceivePort();
        port.listen((message) {
          if (message is LiteRtLmDisposeRequest) {
            message.sendPort.send(
              LiteRtLmErrorResponse(
                'native operation unsettled',
                kind: 'state',
              ),
            );
          } else if (message is LiteRtLmModelLoadRequest) {
            message.sendPort.send(LiteRtLmHandleResponse(1));
          } else if (message is LiteRtLmWorkerRequest) {
            message.sendPort.send(LiteRtLmDoneResponse());
          }
        });
        var litertCreations = 0;
        var llamaCreations = 0;
        final backend = NativeAutoBackend(
          liteRtLmFactory: () {
            litertCreations++;
            return LiteRtLmBackend(initialSendPort: port.sendPort);
          },
          llamaCppFactory: () {
            llamaCreations++;
            return _FakeBackend(handle: 2);
          },
        );
        try {
          await backend.modelLoad('model.litertlm', const ModelParams());
          await expectLater(
            action == 'dispose'
                ? backend.dispose()
                : backend.modelLoad('model.gguf', const ModelParams()),
            throwsA(isA<LlamaStateException>()),
          );
          await expectLater(
            backend.modelLoad('model.litertlm', const ModelParams()),
            throwsA(isA<LlamaStateException>()),
          );
          await expectLater(
            backend.modelLoad('model.gguf', const ModelParams()),
            throwsA(isA<LlamaStateException>()),
          );
          await expectLater(
            backend.dispose(),
            throwsA(isA<LlamaStateException>()),
          );
          expect(litertCreations, 1);
          expect(llamaCreations, 0);
        } finally {
          port.close();
        }
      },
    );
  }

  test('default native backend factory returns the format router', () async {
    final backend = LlamaBackend();

    try {
      expect(backend, isA<NativeAutoBackend>());
      expect(await backend.getBackendName(), 'Native auto');
      expect(backend.supportsUrlLoading, isFalse);
    } finally {
      await backend.dispose();
    }
  });

  test(
    'text-history opt-in preserves native format checks and URL fallback',
    () async {
      final backend = LlamaBackend.withTextHistory();
      addTearDown(backend.dispose);
      final checks = backend as BackendLoadCheck;

      checks.checkLoad(const LlamaCppModelParams(), ModelFormat.gguf);
      expect(
        () => checks.checkLoad(const LiteRtLmModelParams(), ModelFormat.gguf),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'runtime mismatch',
            contains('LiteRtLmModelParams configures LiteRT-LM (.litertlm)'),
          ),
        ),
      );
      expect(
        () =>
            checks.checkLoad(const LlamaCppModelParams(), ModelFormat.liteRtLm),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'runtime mismatch',
            contains('LlamaCppModelParams configures llama.cpp (GGUF) models'),
          ),
        ),
      );
      expect(backend.supportsUrlLoading, isFalse);
      expect(
        () => backend.modelLoadFromUrl(
          'https://example.invalid/model.gguf',
          const ModelParams(),
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'download fallback',
            contains('llamadart download/cache before modelLoad'),
          ),
        ),
      );
    },
  );

  group('checkLoad before any download', () {
    void onAbi(Abi abi) {
      debugLiteRtLmAbiOverride = abi;
      addTearDown(() => debugLiteRtLmAbiOverride = null);
    }

    Matcher unsupported(String message) => throwsA(
      isA<LlamaUnsupportedException>().having(
        (error) => error.message,
        'message',
        contains(message),
      ),
    );

    test('rejects fields the runtime of a named format ignores', () {
      final backend = NativeAutoBackend();
      expect(
        () => backend.checkLoad(
          const ModelParams(liteRtLmCacheDir: '/cache'),
          ModelFormat.gguf,
        ),
        unsupported(
          'llama.cpp does not apply these ModelParams natively: '
          'liteRtLmCacheDir.',
        ),
      );
      expect(
        () => backend.checkLoad(
          const ModelParams(loadMtp: true),
          ModelFormat.liteRtLm,
        ),
        unsupported(
          'does not support llama.cpp-specific ModelParams: loadMtp.',
        ),
      );
      backend.checkLoad(
        const ModelParams(liteRtLmCacheDir: '/cache'),
        ModelFormat.liteRtLm,
      );
      backend.checkLoad(const ModelParams(batchSize: 256), ModelFormat.gguf);
    });

    test('rejects a runtime-specific subtype for the other runtime', () {
      final backend = NativeAutoBackend();
      expect(
        () => backend.checkLoad(
          const LlamaCppModelParams(),
          ModelFormat.liteRtLm,
        ),
        unsupported('LlamaCppModelParams configures llama.cpp (GGUF) models'),
      );
      expect(
        () => backend.checkLoad(const LiteRtLmModelParams(), ModelFormat.gguf),
        unsupported('LiteRtLmModelParams configures LiteRT-LM (.litertlm)'),
      );
      backend.checkLoad(const LlamaCppModelParams(), ModelFormat.gguf);
    });

    test('leaves a format only the file can tell to the load', () {
      NativeAutoBackend().checkLoad(
        const ModelParams(liteRtLmCacheDir: '/cache', loadMtp: true),
        null,
      );
    });

    test('rejects LiteRT-LM where no runtime is published', () {
      final cases = {
        Abi.macosX64: 'LiteRT-LM is not available on macOS x86_64',
        Abi.windowsArm64: 'LiteRT-LM is not available on Windows arm64',
        Abi.iosX64: 'LiteRT-LM is not available on the x86_64 iOS simulator',
      };
      for (final MapEntry(key: abi, value: message) in cases.entries) {
        onAbi(abi);
        expect(
          () => NativeAutoBackend().checkLoad(
            const ModelParams(),
            ModelFormat.liteRtLm,
          ),
          unsupported(message),
        );
        expect(
          NativeAutoBackend().checkLoad(const ModelParams(), ModelFormat.gguf),
          isNull,
        );
        // A custom LiteRT-LM factory can bring its own runtime library.
        expect(
          NativeAutoBackend(
            liteRtLmFactory: () => _FakeBackend(handle: 22),
          ).checkLoad(const ModelParams(), ModelFormat.liteRtLm),
          contains('custom LiteRT-LM factory'),
        );
      }
    });

    test('rejects an explicit LiteRT-LM device the target lacks', () {
      onAbi(Abi.linuxArm64);
      expect(
        () => NativeAutoBackend().checkLoad(
          const ModelParams(device: ComputeDevice.gpu),
          ModelFormat.liteRtLm,
        ),
        unsupported('ComputeDevice.gpu is not available for LiteRT-LM on '),
      );
      expect(
        () => NativeAutoBackend().checkLoad(
          const ModelParams(device: ComputeDevice.gpu),
          ModelFormat.liteRtLm,
        ),
        unsupported('(linux_arm64)'),
      );
      NativeAutoBackend().checkLoad(
        const ModelParams(device: ComputeDevice.cpu),
        ModelFormat.liteRtLm,
      );

      onAbi(Abi.linuxX64);
      NativeAutoBackend().checkLoad(
        const ModelParams(device: ComputeDevice.gpu),
        ModelFormat.liteRtLm,
      );
    });
  });

  test('pre-load router reports defaults and rejects direct calls', () async {
    final backend = NativeAutoBackend(
      llamaCppFactory: () => _FakeBackend(handle: 11),
      liteRtLmFactory: () => _FakeBackend(handle: 22),
    );

    try {
      expect(backend.isReady, isFalse);
      expect(backend.supportsUrlLoading, isFalse);
      expect(
        () => backend.modelLoadFromUrl(
          'https://example.test/model.gguf',
          const ModelParams(),
        ),
        throwsUnsupportedError,
      );
      expect(() => backend.tokenize(1, 'hello'), throwsStateError);
    } finally {
      await backend.dispose();
    }
  });

  test(
    'forwards the Dart log level to the loaded and diagnostic delegates',
    () async {
      final llama = _DartLogLevelFakeBackend(handle: 11)..gpuSupported = true;
      final litert = _DartLogLevelFakeBackend(handle: 22);
      final backend = NativeAutoBackend(
        llamaCppFactory: () => llama,
        liteRtLmFactory: () => litert,
      );

      try {
        expect(backend, isA<BackendDartLogLevel>());
        await backend.setDartLogLevel(LlamaLogLevel.debug);
        expect(await backend.isGpuSupported(), isTrue);
        await backend.setDartLogLevel(LlamaLogLevel.info);
        await backend.modelLoad('/models/model.litertlm', const ModelParams());
        await backend.setDartLogLevel(LlamaLogLevel.warn);

        expect(llama.dartLogLevels, [LlamaLogLevel.info]);
        expect(litert.dartLogLevels, [LlamaLogLevel.warn]);
      } finally {
        await backend.dispose();
      }
    },
  );

  test(
    'pre-load diagnostics use a llama.cpp probe without selecting a model backend',
    () async {
      final llama = _FakeBackend(handle: 11)
        ..gpuSupported = true
        ..vramInfo = (total: 1024, free: 512);
      final litert = _FakeBackend(handle: 22);
      final backend = NativeAutoBackend(
        llamaCppFactory: () => llama,
        liteRtLmFactory: () => litert,
      );

      try {
        await backend.setLogLevel(LlamaLogLevel.debug);

        expect(await backend.getBackendName(), 'Native auto');
        expect(await backend.isGpuSupported(), isTrue);
        expect(await backend.getVramInfo(), (total: 1024, free: 512));
        expect(await backend.getBackendName(), 'Native auto');
        expect(llama.loadedPaths, isEmpty);
        expect(litert.loadedPaths, isEmpty);
        expect(llama.logLevels, [LlamaLogLevel.debug]);
        expect(llama.disposeCount, 0);
      } finally {
        await backend.dispose();
      }

      expect(llama.disposeCount, 1);
      expect(litert.disposeCount, 0);
    },
  );

  test(
    'pre-load listGpuDevices forwards through the llama.cpp diagnostic delegate',
    () async {
      // The default LlamaBackend() resolves to NativeAutoBackend; listGpuDevices
      // must reach a GPU-enumeration-capable delegate, not return an empty list.
      const devices = [
        GpuDeviceInfo(
          backend: GpuBackend.vulkan,
          mainGpu: 0,
          name: 'Vulkan0',
          description: 'NVIDIA GeForce RTX 5050 Laptop GPU',
          deviceId: '0000:64:00.0',
          type: GpuDeviceType.discreteGpu,
          memoryFreeBytes: 7910,
          memoryTotalBytes: 8192,
        ),
      ];
      final llama = _FakeBackend(handle: 11)..gpuDevices = devices;
      final litert = _FakeBackend(handle: 22);
      final backend = NativeAutoBackend(
        llamaCppFactory: () => llama,
        liteRtLmFactory: () => litert,
      );

      try {
        final result = await backend.listGpuDevices();
        expect(result, hasLength(1));
        expect(result.single.description, 'NVIDIA GeForce RTX 5050 Laptop GPU');
        expect(result.single.type, GpuDeviceType.discreteGpu);
        expect(litert.loadedPaths, isEmpty);
      } finally {
        await backend.dispose();
      }
    },
  );

  test(
    'reuses pre-load diagnostic delegate for llama.cpp model loads',
    () async {
      var llamaFactoryCalls = 0;
      final llama = _FakeBackend(handle: 11)..gpuSupported = true;
      final litert = _FakeBackend(handle: 22);
      final backend = NativeAutoBackend(
        llamaCppFactory: () {
          llamaFactoryCalls += 1;
          return llama;
        },
        liteRtLmFactory: () => litert,
      );

      try {
        expect(await backend.isGpuSupported(), isTrue);
        expect(llamaFactoryCalls, 1);

        expect(
          await backend.modelLoad('/models/model.gguf', const ModelParams()),
          11,
        );

        expect(llamaFactoryCalls, 1);
        expect(llama.loadedPaths, ['/models/model.gguf']);
        expect(llama.disposeCount, 0);
        expect(litert.loadedPaths, isEmpty);
      } finally {
        await backend.dispose();
      }
    },
  );

  test(
    'disposes pre-load diagnostic delegate when routing to LiteRT-LM',
    () async {
      final llama = _FakeBackend(handle: 11)..gpuSupported = true;
      final litert = _FakeBackend(handle: 22);
      final backend = NativeAutoBackend(
        llamaCppFactory: () => llama,
        liteRtLmFactory: () => litert,
      );

      try {
        expect(await backend.isGpuSupported(), isTrue);

        expect(
          await backend.modelLoad(
            '/models/gemma-4-E2B-it.litertlm',
            const ModelParams(),
          ),
          22,
        );

        expect(llama.disposeCount, 1);
        expect(llama.loadedPaths, isEmpty);
        expect(litert.loadedPaths, ['/models/gemma-4-E2B-it.litertlm']);
      } finally {
        await backend.dispose();
      }
    },
  );

  test(
    'forwards grammar-constraint support from the active delegate',
    () async {
      final llama = _FakeBackend(handle: 11)
        ..grammarConstraintsSupported = true;
      final litert = _FakeBackend(handle: 22)
        ..grammarConstraintsSupported = false;
      final backend = NativeAutoBackend(
        llamaCppFactory: () => llama,
        liteRtLmFactory: () => litert,
      );
      final grammar = backend as BackendGrammarConstraintsSupport;

      try {
        // Defaults to true (llama.cpp) before any model is loaded.
        expect(grammar.supportsGrammarConstraints, isTrue);

        await backend.modelLoad('/models/model.litertlm', const ModelParams());
        // LiteRT-LM rejects grammar params, so the engine must learn to skip
        // them — otherwise hermes/Qwen tool calls throw.
        expect(grammar.supportsGrammarConstraints, isFalse);
      } finally {
        await backend.dispose();
      }
    },
  );

  test(
    'forwards deferred engine creation and the engine logs it on load',
    () async {
      final records = <LlamaLogRecord>[];
      await LlamaLogging.configure(
        level: LlamaLogLevel.info,
        handler: records.add,
      );
      addTearDown(LlamaLogging.configure);

      final llama = _FakeBackend(handle: 11);
      final litert = _DeferredEngineFakeBackend(handle: 22);
      final backend = NativeAutoBackend(
        llamaCppFactory: () => llama,
        liteRtLmFactory: () => litert,
      );
      final engine = LlamaEngine(backend);

      try {
        expect(backend, isA<BackendDeferredEngineCreation>());
        expect(backend.defersEngineCreation, isFalse);

        await engine.loadModel('/models/model.litertlm');
        expect(backend.defersEngineCreation, isTrue);
        final messages = records.map((record) => record.message).toList();
        expect(
          messages,
          contains(
            'Model model.litertlm loaded from /models/model.litertlm; native '
            'engine creation is deferred until the first generation or '
            'tokenizer call',
          ),
        );
        expect(messages, isNot(contains(contains('loaded successfully'))));

        await engine.unloadModel();
        records.clear();
        await engine.loadModel('/models/model.gguf');
        expect(backend.defersEngineCreation, isFalse);
        expect(
          records.map((record) => record.message),
          contains(
            'Model model.gguf loaded successfully from /models/model.gguf',
          ),
        );
      } finally {
        await engine.dispose();
      }
    },
  );

  test('routes GGUF and unknown formats to llama.cpp', () async {
    final llama = _FakeBackend(handle: 11);
    final litert = _FakeBackend(handle: 22);
    final backend = NativeAutoBackend(
      llamaCppFactory: () => llama,
      liteRtLmFactory: () => litert,
    );

    try {
      await backend.setLogLevel(LlamaLogLevel.debug);

      expect(
        await backend.modelLoad(
          '/models/gemma-4-E2B-it-Q4_K_S.gguf',
          const ModelParams(),
        ),
        11,
      );
      expect(llama.loadedPaths, ['/models/gemma-4-E2B-it-Q4_K_S.gguf']);
      expect(llama.logLevels, [LlamaLogLevel.debug]);
      expect(litert.loadedPaths, isEmpty);

      expect(
        await backend.modelLoad('/models/model.bin', const ModelParams()),
        11,
      );
      expect(llama.loadedPaths, [
        '/models/gemma-4-E2B-it-Q4_K_S.gguf',
        '/models/model.bin',
      ]);
      expect(llama.disposeCount, 0);
    } finally {
      await backend.dispose();
    }
  });

  test(
    'routes litertlm bundles to LiteRT-LM and disposes switched delegate',
    () async {
      final llama = _FakeBackend(handle: 11);
      final litert = _FakeBackend(handle: 22);
      final backend = NativeAutoBackend(
        llamaCppFactory: () => llama,
        liteRtLmFactory: () => litert,
      );

      try {
        await backend.modelLoad('/models/model.gguf', const ModelParams());
        expect(llama.loadedPaths, ['/models/model.gguf']);

        expect(
          await backend.modelLoad(
            '/models/gemma-4-E2B-it.litertlm',
            const ModelParams(),
          ),
          22,
        );
        expect(llama.disposeCount, 1);
        expect(litert.loadedPaths, ['/models/gemma-4-E2B-it.litertlm']);
        expect(await backend.getBackendName(), 'fake-22');
      } finally {
        await backend.dispose();
      }
    },
  );

  group('routes by file header', () {
    late Directory tempDir;
    late _FakeBackend llama;
    late _FakeBackend litert;
    late NativeAutoBackend backend;

    Future<String> writeModel(String name, String header) async {
      final file = File('${tempDir.path}/$name');
      await file.writeAsString('${header}rest of the model');
      return file.path;
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('llamadart_route_');
      llama = _FakeBackend(handle: 11);
      litert = _FakeBackend(handle: 22);
      backend = NativeAutoBackend(
        llamaCppFactory: () => llama,
        liteRtLmFactory: () => litert,
      );
    });

    tearDown(() async {
      await backend.dispose();
      await tempDir.delete(recursive: true);
    });

    test('loads an extensionless LiteRT-LM bundle in LiteRT-LM', () async {
      final path = await writeModel('download', 'LITERTLM');

      expect(await backend.modelLoad(path, const ModelParams()), 22);
      expect(litert.loadedPaths, [path]);
      expect(llama.loadedPaths, isEmpty);
    });

    test('loads an extensionless GGUF file in llama.cpp', () async {
      final path = await writeModel('blob', 'GGUF');

      expect(await backend.modelLoad(path, const ModelParams()), 11);
      expect(llama.loadedPaths, [path]);
      expect(litert.loadedPaths, isEmpty);
    });

    for (final (name, header, detected, declared) in [
      ('model.gguf', 'LITERTLM', ModelFormat.liteRtLm, ModelFormat.gguf),
      ('model.litertlm', 'GGUF', ModelFormat.gguf, ModelFormat.liteRtLm),
    ]) {
      test('rejects $name whose header is ${detected.name}', () async {
        final path = await writeModel(name, header);

        await expectLater(
          backend.modelLoad(path, const ModelParams()),
          throwsA(
            isA<LlamaModelFormatException>()
                .having((e) => e.detected, 'detected', detected)
                .having((e) => e.declared, 'declared', declared),
          ),
        );
        expect(llama.loadedPaths, isEmpty);
        expect(litert.loadedPaths, isEmpty);
      });
    }

    test('an explicit format overrides a contradicting extension', () async {
      final path = await writeModel('model.gguf', 'LITERTLM');

      expect(
        await backend.modelLoadAs(
          path,
          const ModelParams(),
          ModelFormat.liteRtLm,
        ),
        22,
      );
      expect(litert.loadedPaths, [path]);
    });

    test('an explicit format routes an unrecognized header', () async {
      final path = await writeModel('download', 'fake');

      expect(
        await backend.modelLoadAs(
          path,
          const ModelParams(),
          ModelFormat.liteRtLm,
        ),
        22,
      );
      expect(await backend.modelLoad(path, const ModelParams()), 11);
    });

    test('rejects an explicit format the header contradicts', () async {
      final path = await writeModel('download', 'GGUF');

      await expectLater(
        backend.modelLoadAs(path, const ModelParams(), ModelFormat.liteRtLm),
        throwsA(isA<LlamaModelFormatException>()),
      );
      expect(litert.loadedPaths, isEmpty);
    });

    test('an engine rejects ModelParams.loras that an extensionless '
        'LiteRT-LM bundle cannot take before it downloads any, and still '
        'downloads one adapter at scale 1.0', () async {
      final path = await writeModel('download', 'LITERTLM');
      final adapterFile = File('${tempDir.path}/adapter.bin');
      await adapterFile.writeAsString('adapter');
      final adapter = ModelSource.url(
        Uri.parse('https://example.test/adapter.bin'),
      );
      final manager = _FakeModelDownloadManager(
        ModelCacheEntry(
          sourceCanonicalKey: adapter.metadataSourceKey,
          cacheKey: adapter.cacheKey,
          fileName: adapter.fileName,
          filePath: adapterFile.path,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      final engine = LlamaEngine(backend, modelDownloadManager: manager);

      for (final (loras, reason) in [
        ([LoraAdapterConfig.source(adapter, scale: 0.5)], 'sets scale 0.5'),
        (
          [
            LoraAdapterConfig.source(adapter),
            LoraAdapterConfig.source(adapter),
          ],
          'has 2 adapters',
        ),
      ]) {
        await expectLater(
          engine.loadModel(path, modelParams: ModelParams(loras: loras)),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('LiteRT-LM takes one LoRA adapter at scale 1.0'),
                contains(reason),
              ),
            ),
          ),
        );
      }
      expect(manager.ensureModelCalls, 0);
      expect(litert.loadedPaths, isEmpty);

      await engine.loadModel(
        path,
        modelParams: ModelParams(loras: [LoraAdapterConfig.source(adapter)]),
      );
      expect(manager.ensureModelCalls, 1);
      expect(litert.loadedPaths, [path]);
      expect(litert.loadedParams.single.loras.single.path, adapterFile.path);
      await engine.dispose();
    });

    test('an engine downloads stacked adapters for an extensionless GGUF '
        'file', () async {
      final path = await writeModel('blob', 'GGUF');
      final adapter = ModelSource.url(
        Uri.parse('https://example.test/adapter.gguf'),
      );
      final manager = _FakeModelDownloadManager(
        ModelCacheEntry(
          sourceCanonicalKey: adapter.metadataSourceKey,
          cacheKey: adapter.cacheKey,
          fileName: adapter.fileName,
          filePath: '${tempDir.path}/adapter.gguf',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      final engine = LlamaEngine(backend, modelDownloadManager: manager);

      await engine.loadModel(
        path,
        modelParams: ModelParams(
          loras: [
            LoraAdapterConfig.source(adapter, scale: 0.5),
            LoraAdapterConfig.source(adapter),
          ],
        ),
      );
      expect(manager.ensureModelCalls, 2);
      expect(llama.loadedPaths, [path]);
      await engine.dispose();
    });

    test('an engine downloads stacked adapters for an extensionless file '
        'with an unrecognized header', () async {
      final path = await writeModel('unknown', 'fake');
      final adapter = ModelSource.url(
        Uri.parse('https://example.test/adapter.gguf'),
      );
      final manager = _FakeModelDownloadManager(
        ModelCacheEntry(
          sourceCanonicalKey: adapter.metadataSourceKey,
          cacheKey: adapter.cacheKey,
          fileName: adapter.fileName,
          filePath: '${tempDir.path}/adapter.gguf',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      final engine = LlamaEngine(backend, modelDownloadManager: manager);

      await engine.loadModel(
        path,
        modelParams: ModelParams(
          loras: [
            LoraAdapterConfig.source(adapter, scale: 0.5),
            LoraAdapterConfig.source(adapter),
          ],
        ),
      );
      expect(manager.ensureModelCalls, 2);
      expect(llama.loadedPaths, [path]);
      await engine.dispose();
    });

    test('rejects URL loads with an explicit format', () {
      expect(
        () => backend.modelLoadFromUrlAs(
          'https://example.test/download',
          const ModelParams(),
          ModelFormat.liteRtLm,
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('generateChatPrompt', () {
    test('gives a delegate that takes chat prompts the prompt and its '
        'marker', () async {
      final llama = _ChatPromptFakeBackend(handle: 11);
      final backend = NativeAutoBackend(
        llamaCppFactory: () => llama,
        liteRtLmFactory: () => _FakeBackend(handle: 22),
      );
      addTearDown(backend.dispose);
      await backend.modelLoad('/models/model.gguf', const ModelParams());

      await backend
          .generateChatPrompt(
            1,
            '<m>a <__media__>',
            const GenerationParams(),
            mediaMarker: '<m>',
          )
          .drain<void>();

      expect(llama.chatPrompts, [('<m>a <__media__>', '<m>')]);
      expect(llama.prompts, isEmpty);
    });

    test('gives any other delegate the prompt with the default marker '
        'through generate', () async {
      final litert = _PromptFakeBackend(handle: 22);
      final backend = NativeAutoBackend(
        llamaCppFactory: () => _FakeBackend(handle: 11),
        liteRtLmFactory: () => litert,
      );
      addTearDown(backend.dispose);
      await backend.modelLoad(
        '/models/gemma-4-E2B-it.litertlm',
        const ModelParams(),
      );

      await backend
          .generateChatPrompt(
            1,
            '<m>a',
            const GenerationParams(),
            mediaMarker: '<m>',
          )
          .drain<void>();

      expect(litert.prompts, ['<__media__>a']);
    });
  });

  test('forwards LiteRT-LM backend preference through the router', () async {
    final llama = _FakeBackend(handle: 11);
    final litert = _FakeBackend(handle: 22);
    final backend = NativeAutoBackend(
      llamaCppFactory: () => llama,
      liteRtLmFactory: () => litert,
    );

    try {
      await backend.modelLoad(
        '/models/gemma-4-E2B-it.litertlm',
        const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.npu),
      );

      expect(litert.loadedPaths, ['/models/gemma-4-E2B-it.litertlm']);
      expect(
        litert.loadedParams.single.liteRtLmBackend,
        LiteRtLmBackendPreference.npu,
      );
      expect(llama.loadedPaths, isEmpty);
    } finally {
      await backend.dispose();
    }
  });

  test('merges deprecated language codes for a LiteRT-LM delegate', () async {
    final requests = <LiteRtLmGenerateChatRequest>[];
    final port = ReceivePort();
    port.listen((message) {
      if (message is LiteRtLmModelLoadRequest) {
        message.sendPort.send(LiteRtLmHandleResponse(1));
      } else if (message is LiteRtLmGenerateChatRequest) {
        requests.add(message);
        message.sendPort.send(LiteRtLmDoneResponse());
      } else if (message is LiteRtLmWorkerRequest) {
        message.sendPort.send(LiteRtLmDoneResponse());
      }
    });
    final backend = NativeAutoBackend(
      llamaCppFactory: () => _FakeBackend(handle: 11),
      liteRtLmFactory: () => LiteRtLmBackend(initialSendPort: port.sendPort),
    );

    try {
      await backend.modelLoad('model.litertlm', const ModelParams());
      await backend
          .generateChat(
            1,
            const [
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
            ],
            const GenerationParams(),
            chatTemplateKwargs: const {'locale': 'en_CA'},
            // ignore: deprecated_member_use_from_same_package
            sourceLangCode: 'en',
            // ignore: deprecated_member_use_from_same_package
            targetLangCode: 'ko',
          )
          .drain<void>();

      expect(requests.single.chatTemplateKwargs, {
        'locale': 'en_CA',
        'source_lang_code': 'en',
        'target_lang_code': 'ko',
      });
    } finally {
      await backend.dispose();
      port.close();
    }
  });

  test('falls back when delegate lacks optional capabilities', () async {
    final llama = _FakeBackend(handle: 11);
    final backend = NativeAutoBackend(
      llamaCppFactory: () => llama,
      liteRtLmFactory: () => _FakeBackend(handle: 22),
    );

    try {
      await backend.modelLoad('/models/model.gguf', const ModelParams());

      expect(await backend.getAvailableBackends(), 'llama.cpp, LiteRT-LM');
      expect(await backend.getResolvedGpuLayers(), isNull);
      expect(await backend.getPerformanceContext(1), isNull);
      expect(backend.supportsEmbeddings, isFalse);
      expect(backend.supportsStatePersistence, isFalse);
      expect(backend.supportsNextTokenScoring, isFalse);

      expect(() => backend.embed(1, 'hello'), throwsUnsupportedError);
      expect(
        () => backend.scoreNextToken(
          1,
          'hello',
          candidates: const [1],
          topK: 0,
          reusePromptPrefix: true,
        ),
        throwsUnsupportedError,
      );
      await expectLater(
        backend.embedBatch(1, const ['hello']),
        throwsUnsupportedError,
      );
      expect(
        () => backend.stateSaveFile(1, '/tmp/state.bin', const [1, 2]),
        throwsUnsupportedError,
      );
      expect(
        () => backend.stateLoadFile(1, '/tmp/state.bin', 16),
        throwsUnsupportedError,
      );
      expect(() => backend.stateIdentity(1), throwsUnsupportedError);
    } finally {
      await backend.dispose();
    }
  });

  test('routes optional native delegate capabilities', () async {
    final llama = _CapabilityFakeBackend(handle: 11);
    final backend = NativeAutoBackend(
      llamaCppFactory: () => llama,
      liteRtLmFactory: () => _FakeBackend(handle: 22),
    );

    try {
      await backend.modelLoad('/models/model.gguf', const ModelParams());

      expect(await backend.getAvailableBackends(), 'capability-backends');
      expect(await backend.getResolvedGpuLayers(), 123);
      final perf = await backend.getPerformanceContext(1);
      expect(perf, isNotNull);
      expect(perf!.evalTokens, 7);
      expect(backend.supportsEmbeddings, isTrue);
      expect(await backend.embed(1, 'hello', normalize: false), [1.0, 2.0]);
      expect(await backend.embedBatch(1, const ['a', 'b']), [
        [1.0],
        [2.0],
      ]);
      expect(backend.supportsStatePersistence, isTrue);
      expect(
        await backend.stateSaveFile(1, '/tmp/state.bin', const [3]),
        isTrue,
      );
      expect((await backend.stateLoadFile(1, '/tmp/state.bin', 16)).tokens, [
        3,
      ]);
      expect(await backend.stateIdentity(5), _capabilityStateIdentity);
      expect(llama.stateIdentityContexts, [5]);
      expect(backend.supportsNextTokenScoring, isTrue);
      final scores = await backend.scoreNextToken(
        4,
        'Answer:',
        candidates: const [8, 9],
        topK: 2,
        reusePromptPrefix: false,
      );
      expect(scores.candidates.map((t) => t.token), [8, 9]);
      expect(llama.scoreCalls.single, (4, 'Answer:', 2, false));
    } finally {
      await backend.dispose();
    }
  });

  test(
    'falls back to single embedding calls when selected backend lacks batch embeddings',
    () async {
      final llama = _EmbeddingOnlyFakeBackend(handle: 11);
      final backend = NativeAutoBackend(
        llamaCppFactory: () => llama,
        liteRtLmFactory: () => _FakeBackend(handle: 22),
      );

      try {
        await backend.modelLoad('/models/model.gguf', const ModelParams());

        expect(backend.supportsEmbeddings, isTrue);
        expect(await backend.embedBatch(1, const ['a', 'bb']), [
          [1.0],
          [2.0],
        ]);
        expect(llama.embeddedTexts, ['a', 'bb']);
      } finally {
        await backend.dispose();
      }
    },
  );

  test('forwards generation limits from a reporting delegate only', () async {
    final llama = _LimitReportingFakeBackend(handle: 11);
    final backend = NativeAutoBackend(
      llamaCppFactory: () => llama,
      liteRtLmFactory: () => _FakeBackend(handle: 22),
    );
    final generation = Stream<List<int>>.empty();
    llama.limits[generation] = BackendGenerationLimit.maxTokens;

    try {
      expect(backend.generationLimitOf(generation), isNull);

      await backend.modelLoad('/models/model.gguf', const ModelParams());
      expect(
        backend.generationLimitOf(generation),
        BackendGenerationLimit.maxTokens,
      );
      expect(backend.generationLimitOf(Stream<List<int>>.empty()), isNull);

      await backend.modelLoad(
        '/models/gemma-4-E2B-it.litertlm',
        const ModelParams(),
      );
      expect(backend.generationLimitOf(generation), isNull);
    } finally {
      await backend.dispose();
    }
  });

  test('tokenizes runtime prompts with the delegate runtime prompt '
      'tokenizer, else as text', () async {
    final llama = _FakeBackend(handle: 11)..tokenizeResult = const [1, 2, 3];
    final liteRt = _FakeBackend(handle: 22);
    registerRuntimePromptTokenizer(liteRt, _FixedRuntimePromptTokenizer());
    final backend = NativeAutoBackend(
      llamaCppFactory: () => llama,
      liteRtLmFactory: () => liteRt,
    );

    try {
      await backend.modelLoad('/models/model.gguf', const ModelParams());
      expect(await backend.tokenizeRuntimePrompt(11, '<bos>hi'), [1, 2, 3]);
      expect(llama.lastTokenizeText, '<bos>hi');
      expect(llama.lastTokenizeAddSpecial, isFalse);

      await backend.modelLoad(
        '/models/gemma-4-E2B-it.litertlm',
        const ModelParams(),
      );
      expect(await backend.tokenizeRuntimePrompt(22, '<bos>hi'), [22, 7]);
    } finally {
      await backend.dispose();
    }
  });

  test('forwards generation usage from a reporting delegate only', () async {
    final llama = _UsageReportingFakeBackend(handle: 11);
    final backend = NativeAutoBackend(
      llamaCppFactory: () => llama,
      liteRtLmFactory: () => _FakeBackend(handle: 22),
    );
    final generation = Stream<List<int>>.empty();
    const usage = LlamaGenerationUsage(
      promptTokens: 3,
      completionTokens: 1,
      duration: Duration(milliseconds: 5),
    );
    llama.usages[generation] = usage;

    try {
      expect(backend.generationUsageOf(generation), isNull);

      await backend.modelLoad('/models/model.gguf', const ModelParams());
      expect(backend.generationUsageOf(generation), same(usage));
      expect(backend.generationUsageOf(Stream<List<int>>.empty()), isNull);

      await backend.modelLoad(
        '/models/gemma-4-E2B-it.litertlm',
        const ModelParams(),
      );
      expect(backend.generationUsageOf(generation), isNull);
    } finally {
      await backend.dispose();
    }
  });

  test('reports the runtime of the selected delegate', () async {
    final backend = NativeAutoBackend(
      llamaCppFactory: () =>
          _RuntimeFakeBackend(handle: 11, runtime: LlamaRuntime.llamaCpp),
      liteRtLmFactory: () =>
          _RuntimeFakeBackend(handle: 22, runtime: LlamaRuntime.liteRtLm),
    );

    try {
      expect(backend.runtime, isNull);
      await backend.modelLoad('/models/model.gguf', const ModelParams());
      expect(backend.runtime, LlamaRuntime.llamaCpp);
      await backend.modelLoad(
        '/models/gemma-4-E2B-it.litertlm',
        const ModelParams(),
      );
      expect(backend.runtime, LlamaRuntime.liteRtLm);
    } finally {
      await backend.dispose();
    }
  });

  test('forwards LoRA calls to a delegate with BackendLoraSupport', () async {
    final llama = _LoraFakeBackend(handle: 11);
    final backend = NativeAutoBackend(
      llamaCppFactory: () => llama,
      liteRtLmFactory: () => _FakeBackend(handle: 22),
    );
    try {
      await backend.modelLoad('/models/model.gguf', const ModelParams());
      await backend.setLoraAdapter(111, 'a.gguf', 0.5);
      await backend.removeLoraAdapter(111, 'a.gguf');
      await backend.clearLoraAdapters(111);
      expect(llama.loraCalls, [
        'set 111 a.gguf 0.5',
        'remove 111 a.gguf',
        'clear 111',
      ]);
    } finally {
      await backend.dispose();
    }
  });

  test('rejects LoRA and projector calls for a delegate without the '
      'capabilities', () async {
    final backend = NativeAutoBackend(
      llamaCppFactory: () => _FakeBackend(handle: 11),
      liteRtLmFactory: _TextOnlyFakeBackend.new,
    );
    try {
      await backend.modelLoad('/models/model.litertlm', const ModelParams());
      Matcher unsupported(String operation) => throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          '$operation are not supported by the active native runtime.',
        ),
      );
      expect(
        () => backend.setLoraAdapter(1, 'a.gguf', 1),
        unsupported('LoRA adapters'),
      );
      expect(
        () => backend.removeLoraAdapter(1, 'a.gguf'),
        unsupported('LoRA adapters'),
      );
      expect(() => backend.clearLoraAdapters(1), unsupported('LoRA adapters'));
      expect(
        () => backend.multimodalContextCreate(1, 'mmproj.gguf'),
        unsupported('Multimodal projectors'),
      );
      expect(
        () => backend.multimodalContextFree(1),
        unsupported('Multimodal projectors'),
      );
      expect(
        () => backend.supportsVision(1),
        unsupported('Multimodal projectors'),
      );
      expect(
        () => backend.supportsAudio(1),
        unsupported('Multimodal projectors'),
      );
    } finally {
      await backend.dispose();
    }
  });

  test(
    'routes multimodal, template, and VRAM calls to selected delegate',
    () async {
      final litert = _FakeBackend(handle: 22)
        ..vramInfo = (total: 2048, free: 1024)
        ..chatTemplateResponse = 'templated'
        ..videoRuntimeSupport = null;
      final backend = NativeAutoBackend(
        llamaCppFactory: () => _FakeBackend(handle: 11),
        liteRtLmFactory: () => litert,
      );

      try {
        await backend.modelLoad(
          '/models/gemma-4-E2B-it.litertlm',
          const ModelParams(),
        );

        expect(await backend.getVramInfo(), (total: 2048, free: 1024));
        expect(await backend.multimodalContextCreate(22, 'mmproj.task'), 222);
        await backend.multimodalContextFree(222);
        expect(await backend.supportsVision(222), isTrue);
        expect(await backend.supportsAudio(222), isFalse);
        expect(await backend.supportsVideoRuntime(222), isNull);
        expect(
          await backend.applyChatTemplate(
            22,
            const [
              {'role': 'user', 'content': 'hi'},
            ],
            customTemplate: 'custom',
            addAssistant: false,
          ),
          'templated',
        );

        expect(litert.lastMultimodalCreateModelHandle, 22);
        expect(litert.lastMultimodalProjectorPath, 'mmproj.task');
        expect(litert.lastMultimodalFreeHandle, 222);
        expect(litert.lastSupportsVisionHandle, 222);
        expect(litert.lastSupportsAudioHandle, 222);
        expect(litert.lastChatTemplateCustomTemplate, 'custom');
        expect(litert.lastChatTemplateAddAssistant, isFalse);
      } finally {
        await backend.dispose();
      }
    },
  );

  test('forwards decision calls to a llama.cpp delegate', () async {
    final llama = _DecisionFakeBackend(handle: 11);
    final backend = NativeAutoBackend(
      llamaCppFactory: () => llama,
      liteRtLmFactory: () => _FakeBackend(handle: 22),
    );

    try {
      await backend.modelLoad('/models/laya-Q8_0.gguf', const ModelParams());

      final capabilities = await backend.decisionCapabilities(11);
      expect(capabilities.isSupported, isTrue);
      final head = await backend.decisionHeadLoad(
        11,
        'head.safetensors',
        configPath: 'config.json',
      );
      expect(head.handle, 77);
      final sequence = BackendDecisionSequence(
        tokens: Int32List.fromList([1, 2]),
        markers: Int32List.fromList([1]),
        questionType: DecisionQuestionType.score,
      );
      final outputs = await backend.decisionRun(77, [sequence]);
      expect(outputs.single.logits, [0.25]);
      await backend.decisionHeadFree(77);

      expect(llama.decisionCalls, [
        'capabilities 11',
        'load 11 head.safetensors config.json',
        'run 77 1',
        'free 77',
      ]);
    } finally {
      await backend.dispose();
    }
  });

  test('reports decision models unsupported on LiteRT-LM', () async {
    final backend = NativeAutoBackend(
      llamaCppFactory: () => _DecisionFakeBackend(handle: 11),
      liteRtLmFactory: () => _FakeBackend(handle: 22),
    );

    try {
      await backend.modelLoad(
        '/models/gemma-4-E2B-it.litertlm',
        const ModelParams(),
      );

      final capabilities = await backend.decisionCapabilities(22);
      expect(capabilities.isSupported, isFalse);
      expect(capabilities.unsupportedReason, contains('ModernBERT'));
      expect(
        () => backend.decisionHeadLoad(22, 'head.safetensors'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(
        () => backend.decisionRun(1, const []),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      await backend.decisionHeadFree(1);
    } finally {
      await backend.dispose();
    }
  });

  test('reports generation capabilities of the loaded runtime', () async {
    final liteRtLm = LiteRtLmBackend();
    final liteRtLmCapabilities = await liteRtLm.generationCapabilities();
    final backend = NativeAutoBackend(
      llamaCppFactory: () => _GenerationCapabilitiesFakeBackend(handle: 11),
      liteRtLmFactory: () => _GenerationCapabilitiesFakeBackend(
        handle: 22,
        capabilities: liteRtLmCapabilities,
      ),
    );

    try {
      final beforeLoad = await backend.generationCapabilities();
      expect(beforeLoad.minP, isFalse);

      await backend.modelLoad('/models/qwen.gguf', const ModelParams());
      final llamaCpp = await backend.generationCapabilities();
      expect(llamaCpp.presencePenalty, isTrue);
      expect(llamaCpp.minP, isTrue);
      expect(llamaCpp.thinkingBudget, isTrue);

      await backend.modelLoad(
        '/models/gemma-4-E2B-it.litertlm',
        const ModelParams(),
      );
      final liteRt = await backend.generationCapabilities();
      // Penalty and thinking support depend on whether this host's LiteRT-LM
      // runtime exports those APIs.
      expect(liteRt.presencePenalty, liteRtLmCapabilities.presencePenalty);
      expect(liteRt.minP, isFalse);
      expect(liteRt.thinkingBudget, liteRtLmCapabilities.thinkingBudget);
      expect(
        liteRt.speculativeDecodingStrategies,
        <SpeculativeDecodingStrategy>{
          SpeculativeDecodingStrategy.backendDefault,
          SpeculativeDecodingStrategy.mtp,
        },
      );
    } finally {
      await backend.dispose();
      await liteRtLm.dispose();
    }
  });

  test('reports the direct media input of the loaded runtime', () async {
    final backend = NativeAutoBackend(
      llamaCppFactory: () => _FakeBackend(handle: 11),
      liteRtLmFactory: () => _DirectMediaFakeBackend(handle: 22),
    );

    try {
      expect(await backend.directMediaInput(), (vision: false, audio: false));

      await backend.modelLoad(
        '/models/gemma-4-E2B-it.litertlm',
        const ModelParams(),
      );
      expect(await backend.directMediaInput(), (vision: true, audio: true));

      await backend.modelLoad('/models/qwen.gguf', const ModelParams());
      expect(await backend.directMediaInput(), (vision: false, audio: false));
    } finally {
      await backend.dispose();
    }
  });

  test('reports the tool-result media of the loaded runtime', () async {
    final backend = NativeAutoBackend(
      llamaCppFactory: () => _ToolResultMediaFakeBackend(handle: 11),
      liteRtLmFactory: () => _FakeBackend(handle: 22),
    );

    try {
      expect(backend.toolResultMedia, isEmpty);

      await backend.modelLoad('/models/qwen.gguf', const ModelParams());
      expect(backend.toolResultMedia, {LlamaToolResultMedia.image});

      await backend.modelLoad(
        '/models/gemma-4-E2B-it.litertlm',
        const ModelParams(),
      );
      expect(backend.toolResultMedia, isEmpty);
    } finally {
      await backend.dispose();
    }
  });

  test('forwards text-to-speech handles to the loaded runtime', () async {
    final llama = _TextToSpeechFakeBackend(handle: 11);
    final backend = NativeAutoBackend(
      llamaCppFactory: () => llama,
      liteRtLmFactory: () => _FakeBackend(handle: 22),
    );

    try {
      await backend.modelLoad('/models/qwen3-tts.gguf', const ModelParams());
      await backend.textToSpeechCapabilities(2, 3);
      await backend.synthesizeTextToSpeech(
        2,
        3,
        const BackendTextToSpeechRequest(text: 'Hello.'),
      );

      expect(llama.capabilityHandles, (2, 3));
      expect(llama.synthesisHandles, (2, 3));
    } finally {
      await backend.dispose();
    }
  });

  test('asks the llama.cpp runtime which text-to-speech models it drives '
      'before a load and keeps that runtime for the load', () async {
    var created = 0;
    final llama = _TextToSpeechFakeBackend(handle: 11);
    final backend = NativeAutoBackend(
      llamaCppFactory: () {
        created++;
        return llama;
      },
      liteRtLmFactory: () => _FakeBackend(handle: 22),
    );

    try {
      expect(
        await backend.textToSpeechModelUnsupportedReason(
          BackendTextToSpeechModel.soprano,
        ),
        'no soprano',
      );
      expect(
        await backend.textToSpeechModelUnsupportedReason(
          BackendTextToSpeechModel.lfm3Audio,
        ),
        isNull,
      );
      await backend.modelLoad('/models/lfm3.gguf', const ModelParams());
      expect(
        await backend.textToSpeechModelUnsupportedReason(
          BackendTextToSpeechModel.lfm3Audio,
        ),
        isNull,
      );
      expect(llama.probedModels, [
        BackendTextToSpeechModel.soprano,
        BackendTextToSpeechModel.lfm3Audio,
        BackendTextToSpeechModel.lfm3Audio,
      ]);
      expect(created, 1);
    } finally {
      await backend.dispose();
    }
  });

  test('rejects decision calls before a model load', () async {
    final llama = _DecisionFakeBackend(handle: 11);
    final backend = NativeAutoBackend(
      llamaCppFactory: () => llama,
      liteRtLmFactory: () => _FakeBackend(handle: 22),
    );

    try {
      expect(() => backend.decisionCapabilities(1), throwsStateError);
      expect(
        () => backend.decisionHeadLoad(1, 'head.safetensors'),
        throwsStateError,
      );
      expect(() => backend.decisionRun(1, const []), throwsStateError);
      await backend.decisionHeadFree(1);
      expect(llama.decisionCalls, isEmpty);
    } finally {
      await backend.dispose();
    }
  });

  test('updates an existing pre-load diagnostic delegate log level', () async {
    final llama = _FakeBackend(handle: 11)..gpuSupported = true;
    final backend = NativeAutoBackend(
      llamaCppFactory: () => llama,
      liteRtLmFactory: () => _FakeBackend(handle: 22),
    );

    try {
      expect(await backend.isGpuSupported(), isTrue);
      await backend.setLogLevel(LlamaLogLevel.debug);

      expect(llama.logLevels, [LlamaLogLevel.warn, LlamaLogLevel.debug]);
    } finally {
      await backend.dispose();
    }
  });

  test('updates diagnostic log level while probe startup is pending', () async {
    final llama = _BlockingLogLevelBackend(handle: 11)..gpuSupported = true;
    final backend = NativeAutoBackend(
      llamaCppFactory: () => llama,
      liteRtLmFactory: () => _FakeBackend(handle: 22),
    );

    try {
      final gpuSupport = backend.isGpuSupported();
      await llama.firstLogLevelStarted.future;

      final update = backend.setLogLevel(LlamaLogLevel.debug);
      await Future<void>.delayed(Duration.zero);
      expect(llama.logLevels, [LlamaLogLevel.warn]);

      llama.releaseFirstLogLevel();
      expect(await gpuSupport, isTrue);
      await update;
      expect(llama.logLevels, [LlamaLogLevel.warn, LlamaLogLevel.debug]);
    } finally {
      await backend.dispose();
    }
  });

  test('disposes failed diagnostic probes', () async {
    final llama = _FailingLogLevelBackend(handle: 11);
    final backend = NativeAutoBackend(
      llamaCppFactory: () => llama,
      liteRtLmFactory: () => _FakeBackend(handle: 22),
    );

    try {
      await expectLater(backend.isGpuSupported(), throwsA(isA<StateError>()));
      expect(llama.disposeCount, 1);
    } finally {
      await backend.dispose();
    }
  });

  test(
    'loadModelSource downloads litertlm bundles and routes them to LiteRT-LM',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'llamadart_native_auto_litert_source_',
      );
      final modelFile = File('${tempDir.path}/gemma-4-E2B-it.litertlm');
      await modelFile.writeAsString('fake model');

      final source = ModelSource.parse(
        'hf://litert-community/gemma-4-E2B-it-litert-lm/gemma-4-E2B-it.litertlm',
      );
      final entry = ModelCacheEntry(
        sourceCanonicalKey: source.metadataSourceKey,
        cacheKey: source.cacheKey,
        fileName: source.fileName,
        filePath: modelFile.path,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        bytes: await modelFile.length(),
      );
      final downloadManager = _FakeModelDownloadManager(entry);
      final llama = _FakeBackend(handle: 11);
      final litert = _FakeBackend(handle: 22);
      final backend = NativeAutoBackend(
        llamaCppFactory: () => llama,
        liteRtLmFactory: () => litert,
      );
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: downloadManager,
      );
      final options = ModelLoadOptions(
        cachePolicy: ModelCachePolicy.refresh,
        bearerToken: 'secret-token',
      );

      try {
        await engine.loadModelSource(
          source,
          modelParams: const ModelParams(
            liteRtLmBackend: LiteRtLmBackendPreference.npu,
          ),
          options: options,
        );

        expect(downloadManager.ensureModelCalls, 1);
        expect(downloadManager.lastSource?.resolvedUri, source.resolvedUri);
        expect(downloadManager.lastSource?.fileName, 'gemma-4-E2B-it.litertlm');
        expect(downloadManager.lastOptions!.cachePolicy, options.cachePolicy);
        expect(downloadManager.lastOptions!.bearerToken, options.bearerToken);
        expect(downloadManager.lastOptions!.headers, options.headers);
        expect(downloadManager.lastOptions!.sha256, options.sha256);
        expect(
          downloadManager.lastOptions!.cacheDirectory,
          options.cacheDirectory,
        );
        expect(downloadManager.lastOptions!.resume, options.resume);
        expect(downloadManager.lastOptions!.maxRetries, options.maxRetries);
        expect(downloadManager.lastOptions!.cancelToken!.isCancelled, isFalse);
        expect(llama.loadedPaths, isEmpty);
        expect(litert.loadedPaths, [modelFile.path]);
        expect(
          litert.loadedParams.single.liteRtLmBackend,
          LiteRtLmBackendPreference.npu,
        );
        expect(
          litert.contextParams.single.liteRtLmBackend,
          LiteRtLmBackendPreference.npu,
        );
        expect(engine.isReady, isTrue);
      } finally {
        await engine.dispose();
        await tempDir.delete(recursive: true);
      }
    },
  );

  for (final format in [null, ModelFormat.liteRtLm]) {
    test(
      'high-level engine loads an extensionless URL download, format $format',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'llamadart_native_auto_download_',
        );
        final modelFile = File('${tempDir.path}/download');
        await modelFile.writeAsString('LITERTLM fake model');
        final source = ModelSource.url(
          Uri.parse('https://host.test/download?id=42'),
          format: format,
        );
        final entry = ModelCacheEntry(
          sourceCanonicalKey: source.metadataSourceKey,
          cacheKey: source.cacheKey,
          fileName: source.fileName,
          filePath: modelFile.path,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
        final downloadManager = _FakeModelDownloadManager(entry);
        final llama = _FakeBackend(handle: 11);
        final litert = _FakeBackend(handle: 22);
        final engine = LlamaEngine(
          NativeAutoBackend(
            llamaCppFactory: () => llama,
            liteRtLmFactory: () => litert,
          ),
          modelDownloadManager: downloadManager,
        );

        try {
          await engine.loadModelSource(source);

          expect(downloadManager.lastSource?.fileName, 'download');
          expect(downloadManager.lastSource?.format, format);
          expect(litert.loadedPaths, [modelFile.path]);
          expect(llama.loadedPaths, isEmpty);
        } finally {
          await engine.dispose();
          await tempDir.delete(recursive: true);
        }
      },
    );
  }

  test('high-level engine loads litertlm with the default backend', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'llamadart_native_auto_litert_',
    );
    final modelFile = File('${tempDir.path}/model.litertlm');
    await modelFile.writeAsString('fake model');
    final engine = LlamaEngine(LlamaBackend());

    try {
      await engine.loadModel(
        modelFile.path,
        modelParams: const ModelParams(preferredBackend: GpuBackend.cpu),
      );

      expect(await engine.getBackendName(), 'LiteRT-LM cpu');
      expect(engine.isReady, isTrue);
    } finally {
      await engine.dispose();
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'high-level engine loads an extensionless LiteRT-LM bundle from a source',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'llamadart_native_auto_litert_extensionless_',
      );
      final modelFile = File('${tempDir.path}/download');
      await modelFile.writeAsString('LITERTLM fake model');
      final links = await Directory('${tempDir.path}/links').create();
      final engine = LlamaEngine(_routerWithLinkDirectory(links.path));

      try {
        await engine.loadModelSource(
          ModelSource.path(modelFile.path),
          modelParams: const ModelParams(preferredBackend: GpuBackend.cpu),
        );

        expect(await engine.getBackendName(), 'LiteRT-LM cpu');
        expect((await engine.getMetadata())['general.name'], 'download');
        expect(links.listSync(), hasLength(1));
        await engine.unloadModel();
        expect(links.listSync(), isEmpty);
      } finally {
        await engine.dispose();
        await tempDir.delete(recursive: true);
      }
    },
  );

  test('high-level engine reports a mislabelled model file', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'llamadart_native_auto_mislabelled_',
    );
    final modelFile = File('${tempDir.path}/model.gguf');
    await modelFile.writeAsString('LITERTLM fake model');
    final links = await Directory('${tempDir.path}/links').create();
    final engine = LlamaEngine(_routerWithLinkDirectory(links.path));

    try {
      await expectLater(
        engine.loadModel(modelFile.path),
        throwsA(isA<LlamaModelFormatException>()),
      );
      expect(engine.isReady, isFalse);
      await engine.loadModelSource(
        ModelSource.path(modelFile.path, format: ModelFormat.liteRtLm),
        modelParams: const ModelParams(preferredBackend: GpuBackend.cpu),
      );
      expect(await engine.getBackendName(), 'LiteRT-LM cpu');
      expect(links.listSync(), hasLength(1));
      await engine.dispose();
      expect(links.listSync(), isEmpty);
    } finally {
      await engine.dispose();
      await tempDir.delete(recursive: true);
    }
  });

  test('high-level engine routes uppercase litertlm extensions', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'llamadart_native_auto_litert_upper_',
    );
    final modelFile = File('${tempDir.path}/MODEL.LITERTLM');
    await modelFile.writeAsString('fake model');
    final engine = LlamaEngine(LlamaBackend());

    try {
      await engine.loadModel(
        modelFile.path,
        modelParams: const ModelParams(preferredBackend: GpuBackend.cpu),
      );

      expect(await engine.getBackendName(), 'LiteRT-LM cpu');
      expect((await engine.getMetadata())['general.name'], 'MODEL.LITERTLM');
    } finally {
      await engine.dispose();
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'high-level engine applies Gemma 4 template for litertlm bundles',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'llamadart_native_auto_gemma4_litert_',
      );
      final modelFile = File('${tempDir.path}/gemma-4-E2B-it.litertlm');
      await modelFile.writeAsString('fake model');
      final engine = LlamaEngine(LlamaBackend());

      try {
        await engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(preferredBackend: GpuBackend.cpu),
        );

        final metadata = await engine.getMetadata();
        expect(metadata['tokenizer.chat_template'], contains('<|turn>'));

        final template = await engine.chatTemplate(const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ], includeTokenCount: false);

        expect(template.format, ChatFormat.gemma4.index);
        expect(template.prompt, contains('<|turn>user\nhi<turn|>'));
        // Canonical Gemma 4 template: thinking on emits a `<|think|>` system
        // block and leaves the model turn open.
        expect(template.prompt, contains('<|turn>system\n<|think|>'));
        expect(template.prompt, endsWith('<|turn>model\n'));
      } finally {
        await engine.dispose();
        await tempDir.delete(recursive: true);
      }
    },
  );

  test('high-level engine rejects unsupported litertlm load params', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'llamadart_native_auto_load_params_litert_',
    );
    final modelFile = File('${tempDir.path}/gemma-4-E2B-it.litertlm');
    await modelFile.writeAsString('fake model');
    final engine = LlamaEngine(LlamaBackend());

    try {
      await expectLater(
        () => engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(
            preferredBackend: GpuBackend.cpu,
            batchSize: 128,
          ),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('batchSize'),
          ),
        ),
      );
      expect(engine.isReady, isFalse);
    } finally {
      await engine.dispose();
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'high-level engine rejects LoRA operations for litertlm bundles',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'llamadart_native_auto_lora_litert_',
      );
      final modelFile = File('${tempDir.path}/gemma-4-E2B-it.litertlm');
      await modelFile.writeAsString('fake model');
      final engine = LlamaEngine(LlamaBackend());

      try {
        await engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(preferredBackend: GpuBackend.cpu),
        );

        await expectLater(
          engine.setLora('adapter.bin'),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        await expectLater(
          engine.removeLora('adapter.bin'),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        await expectLater(
          engine.clearLoras(),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      } finally {
        await engine.dispose();
        await tempDir.delete(recursive: true);
      }
    },
  );

  test('high-level engine delegates litertlm tokenization APIs', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'llamadart_native_auto_token_litert_',
    );
    final modelFile = File('${tempDir.path}/gemma-4-E2B-it.litertlm');
    await modelFile.writeAsString('fake model');
    final litert = _FakeBackend(handle: 22)
      ..tokenizeResult = const <int>[2, 10, 11]
      ..detokenizeResult = 'hello';
    final backend = NativeAutoBackend(
      llamaCppFactory: () => _FakeBackend(handle: 11),
      liteRtLmFactory: () => litert,
    );
    final engine = LlamaEngine(backend);

    try {
      await engine.loadModel(
        modelFile.path,
        modelParams: const ModelParams(preferredBackend: GpuBackend.cpu),
      );

      expect(await engine.tokenize('hello'), [2, 10, 11]);
      expect(await engine.detokenize([10, 11]), 'hello');
      expect(await engine.getTokenCount('hello'), 3);
      expect(litert.lastTokenizeText, 'hello');
      expect(litert.lastTokenizeAddSpecial, isFalse);
      expect(litert.lastDetokenizeTokens, [10, 11]);
    } finally {
      await engine.dispose();
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'high-level engine reports embeddings unsupported for litertlm bundles',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'llamadart_native_auto_embed_litert_',
      );
      final modelFile = File('${tempDir.path}/gemma-4-E2B-it.litertlm');
      await modelFile.writeAsString('fake model');
      final backend = LlamaBackend();
      final engine = LlamaEngine(backend);

      try {
        await engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(preferredBackend: GpuBackend.cpu),
        );

        expect(backend, isA<BackendEmbeddingsSupport>());
        expect(
          (backend as BackendEmbeddingsSupport).supportsEmbeddings,
          isFalse,
        );
        await expectLater(
          engine.embed('hello'),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        await expectLater(
          engine.embedBatch(['hello']),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      } finally {
        await engine.dispose();
        await tempDir.delete(recursive: true);
      }
    },
  );

  test(
    'high-level engine reports state persistence unsupported for litertlm bundles',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'llamadart_native_auto_state_litert_',
      );
      final modelFile = File('${tempDir.path}/gemma-4-E2B-it.litertlm');
      await modelFile.writeAsString('fake model');
      final engine = LlamaEngine(LlamaBackend());

      try {
        await engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(preferredBackend: GpuBackend.cpu),
        );

        expect(engine.supportsStatePersistence, isFalse);
        final throwsLiteRtLmStateUnsupported = throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(contains('LiteRT-LM'), isNot(contains('WebGPU'))),
          ),
        );
        await expectLater(
          engine.stateSaveFile('${tempDir.path}/state.bin', tokens: const []),
          throwsLiteRtLmStateUnsupported,
        );
        await expectLater(
          engine.stateLoadFile('${tempDir.path}/state.bin', tokenCapacity: 16),
          throwsLiteRtLmStateUnsupported,
        );
      } finally {
        await engine.dispose();
        await tempDir.delete(recursive: true);
      }
    },
  );

  test(
    'high-level engine rejects multimodal projectors for litertlm bundles',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'llamadart_native_auto_mm_litert_',
      );
      final modelFile = File('${tempDir.path}/gemma-4-E2B-it.litertlm');
      await modelFile.writeAsString('fake model');
      final engine = LlamaEngine(LlamaBackend());

      try {
        await engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(preferredBackend: GpuBackend.cpu),
        );

        await expectLater(
          engine.loadMultimodalProjector('mmproj.bin'),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      } finally {
        await engine.dispose();
        await tempDir.delete(recursive: true);
      }
    },
  );

  test(
    'high-level engine rejects unsupported litertlm generation options',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'llamadart_native_auto_generate_litert_',
      );
      final modelFile = File('${tempDir.path}/gemma-4-E2B-it.litertlm');
      await modelFile.writeAsString('fake model');
      final engine = LlamaEngine(LlamaBackend());

      try {
        await engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(preferredBackend: GpuBackend.cpu),
        );

        await expectLater(
          engine
              .generate(
                'hello',
                params: const GenerationParams(grammar: 'root ::= "x"'),
              )
              .join(),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        await expectLater(
          engine
              .generate('hello', params: const GenerationParams(minP: 0.1))
              .join(),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      } finally {
        await engine.dispose();
        await tempDir.delete(recursive: true);
      }
    },
  );
}

class _PromptFakeBackend extends _FakeBackend {
  _PromptFakeBackend({required super.handle});

  final List<String> prompts = <String>[];

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) {
    prompts.add(prompt);
    return const Stream<List<int>>.empty();
  }
}

class _ChatPromptFakeBackend extends _PromptFakeBackend
    implements BackendChatPromptGeneration {
  _ChatPromptFakeBackend({required super.handle});

  final List<(String, String)> chatPrompts = <(String, String)>[];

  @override
  Stream<List<int>> generateChatPrompt(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    required String mediaMarker,
    List<LlamaContentPart>? parts,
  }) {
    chatPrompts.add((prompt, mediaMarker));
    return const Stream<List<int>>.empty();
  }
}

class _RuntimeFakeBackend extends _FakeBackend
    implements BackendRuntimeIdentity {
  _RuntimeFakeBackend({required super.handle, required this.runtime});

  @override
  final LlamaRuntime runtime;
}

class _FixedRuntimePromptTokenizer implements BackendRuntimePromptTokenization {
  @override
  Future<List<int>> tokenizeRuntimePrompt(
    int modelHandle,
    String prompt,
  ) async => [modelHandle, prompt.length];
}

class _UsageReportingFakeBackend extends _FakeBackend
    implements BackendGenerationUsageReporting {
  _UsageReportingFakeBackend({required super.handle});

  final Map<Stream<List<int>>, LlamaGenerationUsage> usages =
      <Stream<List<int>>, LlamaGenerationUsage>{};

  @override
  LlamaGenerationUsage? generationUsageOf(Stream<List<int>> generation) =>
      usages[generation];
}

class _LimitReportingFakeBackend extends _FakeBackend
    implements BackendGenerationLimitReporting {
  _LimitReportingFakeBackend({required super.handle});

  final Map<Stream<List<int>>, BackendGenerationLimit> limits =
      <Stream<List<int>>, BackendGenerationLimit>{};

  @override
  BackendGenerationLimit? generationLimitOf(Stream<List<int>> generation) =>
      limits[generation];
}

NativeAutoBackend _routerWithLinkDirectory(String links) {
  return NativeAutoBackend(
    liteRtLmFactory: () => LiteRtLmBackend(
      workerEntryPoint: (sendPort) => runLiteRtLmWorkerForTesting(
        sendPort,
        LiteRtLmService(
          linkParentDirectory: Directory(links),
          useTempCacheDir: false,
        ),
      ),
    ),
  );
}

class _FakeBackend
    implements
        LlamaBackend,
        BackendMultimodalSupport,
        BackendGrammarConstraintsSupport,
        BackendGpuEnumeration,
        BackendVideoRuntimeSupport {
  final int handle;
  bool grammarConstraintsSupported = true;
  final List<String> loadedPaths = <String>[];
  final List<ModelParams> loadedParams = <ModelParams>[];
  final List<ModelParams> contextParams = <ModelParams>[];
  final List<int> freedModels = <int>[];
  final List<int> freedContexts = <int>[];
  final List<LlamaLogLevel> logLevels = <LlamaLogLevel>[];
  int cancelGenerationCalls = 0;
  List<int> tokenizeResult = const <int>[];
  String detokenizeResult = '';
  String? lastTokenizeText;
  bool? lastTokenizeAddSpecial;
  List<int>? lastDetokenizeTokens;
  bool gpuSupported = false;
  ({int total, int free}) vramInfo = (total: 0, free: 0);
  List<GpuDeviceInfo> gpuDevices = const [];
  int disposeCount = 0;
  int? lastMultimodalCreateModelHandle;
  String? lastMultimodalProjectorPath;
  int? lastMultimodalFreeHandle;
  int? lastSupportsVisionHandle;
  int? lastSupportsAudioHandle;
  int? lastSupportsVideoHandle;
  bool? videoRuntimeSupport = false;
  String chatTemplateResponse = '';
  List<Map<String, dynamic>>? lastChatTemplateMessages;
  String? lastChatTemplateCustomTemplate;
  bool? lastChatTemplateAddAssistant;

  _FakeBackend({required this.handle});

  @override
  bool get isReady => loadedPaths.isNotEmpty && disposeCount == 0;

  @override
  bool get supportsUrlLoading => false;

  @override
  bool get supportsGrammarConstraints => grammarConstraintsSupported;

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    loadedPaths.add(path);
    loadedParams.add(params);
    return handle;
  }

  @override
  Future<void> modelFree(int modelHandle) async {
    freedModels.add(modelHandle);
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async {
    contextParams.add(params);
    return handle + 100;
  }

  @override
  Future<void> contextFree(int contextHandle) async {
    freedContexts.add(contextHandle);
  }

  @override
  void cancelGeneration() {
    cancelGenerationCalls += 1;
  }

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    lastTokenizeText = text;
    lastTokenizeAddSpecial = addSpecial;
    return tokenizeResult;
  }

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async {
    lastDetokenizeTokens = List<int>.from(tokens);
    return detokenizeResult;
  }

  @override
  Future<String> getBackendName() async => 'fake-$handle';

  @override
  Future<bool> isGpuSupported() async => gpuSupported;

  @override
  Future<({int total, int free})> getVramInfo() async => vramInfo;

  @override
  Future<List<GpuDeviceInfo>> listGpuDevices({
    List<GpuBackend> probeBackends = const [],
  }) async => gpuDevices;

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async {
    lastMultimodalCreateModelHandle = modelHandle;
    lastMultimodalProjectorPath = mmProjPath;
    return handle + 200;
  }

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {
    lastMultimodalFreeHandle = mmContextHandle;
  }

  @override
  Future<bool> supportsVision(int mmContextHandle) async {
    lastSupportsVisionHandle = mmContextHandle;
    return true;
  }

  @override
  Future<bool> supportsAudio(int mmContextHandle) async {
    lastSupportsAudioHandle = mmContextHandle;
    return false;
  }

  @override
  Future<bool?> supportsVideoRuntime(int mmContextHandle) async {
    lastSupportsVideoHandle = mmContextHandle;
    return videoRuntimeSupport;
  }

  @override
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) async {
    lastChatTemplateMessages = messages;
    lastChatTemplateCustomTemplate = customTemplate;
    lastChatTemplateAddAssistant = addAssistant;
    return chatTemplateResponse;
  }

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {
    logLevels.add(level);
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LoraFakeBackend extends _FakeBackend implements BackendLoraSupport {
  _LoraFakeBackend({required super.handle});

  final List<String> loraCalls = <String>[];

  @override
  Future<void> setLoraAdapter(
    int contextHandle,
    String path,
    double scale,
  ) async => loraCalls.add('set $contextHandle $path $scale');

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) async =>
      loraCalls.add('remove $contextHandle $path');

  @override
  Future<void> clearLoraAdapters(int contextHandle) async =>
      loraCalls.add('clear $contextHandle');
}

/// A delegate with neither LoRA nor projector support.
class _TextOnlyFakeBackend implements LlamaBackend {
  @override
  Future<int> modelLoad(String path, ModelParams params) async => 1;

  @override
  Future<void> modelFree(int modelHandle) async {}

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmbeddingOnlyFakeBackend extends _FakeBackend
    implements BackendEmbeddings {
  _EmbeddingOnlyFakeBackend({required super.handle});

  final List<String> embeddedTexts = <String>[];

  @override
  Future<List<double>> embed(
    int contextHandle,
    String text, {
    bool normalize = true,
  }) async {
    embeddedTexts.add(text);
    return <double>[text.length.toDouble()];
  }
}

class _BlockingLogLevelBackend extends _FakeBackend {
  _BlockingLogLevelBackend({required super.handle});

  final Completer<void> firstLogLevelStarted = Completer<void>();
  final Completer<void> _releaseFirstLogLevel = Completer<void>();
  var _blockedFirstLogLevel = false;

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {
    logLevels.add(level);
    if (!_blockedFirstLogLevel) {
      _blockedFirstLogLevel = true;
      firstLogLevelStarted.complete();
      await _releaseFirstLogLevel.future;
    }
  }

  void releaseFirstLogLevel() {
    if (!_releaseFirstLogLevel.isCompleted) {
      _releaseFirstLogLevel.complete();
    }
  }
}

class _FailingLogLevelBackend extends _FakeBackend {
  _FailingLogLevelBackend({required super.handle});

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {
    logLevels.add(level);
    throw StateError('diagnostic log level failed');
  }
}

class _DartLogLevelFakeBackend extends _FakeBackend
    implements BackendDartLogLevel {
  _DartLogLevelFakeBackend({required super.handle});

  final List<LlamaLogLevel> dartLogLevels = <LlamaLogLevel>[];

  @override
  Future<void> setDartLogLevel(LlamaLogLevel level) async {
    dartLogLevels.add(level);
  }
}

class _DeferredEngineFakeBackend extends _FakeBackend
    implements BackendDeferredEngineCreation {
  _DeferredEngineFakeBackend({required super.handle});

  @override
  bool get defersEngineCreation => true;
}

final _capabilityStateIdentity = LlamaStateIdentity(
  runtimeBuild: 'llamadart-native-build/1;owner=abc',
  sessionFormatVersion: 11,
  contextSize: 256,
  contextConfigDigest: 'digest',
);

class _CapabilityFakeBackend extends _FakeBackend
    implements
        BackendAvailability,
        BackendRuntimeDiagnostics,
        BackendPerformanceDiagnostics,
        BackendEmbeddings,
        BackendEmbeddingsSupport,
        BackendBatchEmbeddings,
        BackendStatePersistence,
        BackendStatePersistenceSupport,
        BackendStateIdentity,
        BackendNextTokenScoring,
        BackendNextTokenScoringSupport {
  _CapabilityFakeBackend({required super.handle});

  final List<(int, String, int, bool)> scoreCalls = [];
  final List<int> stateIdentityContexts = [];

  @override
  Future<LlamaStateIdentity> stateIdentity(int contextHandle) async {
    stateIdentityContexts.add(contextHandle);
    return _capabilityStateIdentity;
  }

  @override
  bool get supportsNextTokenScoring => true;

  @override
  Future<LlamaNextTokenScores> scoreNextToken(
    int contextHandle,
    String prompt, {
    required List<int> candidates,
    required int topK,
    required bool reusePromptPrefix,
  }) async {
    scoreCalls.add((contextHandle, prompt, topK, reusePromptPrefix));
    return LlamaNextTokenScores(
      candidates: [
        for (final token in candidates)
          LlamaTokenLogprob(token: token, bytes: const [], logprob: -1),
      ],
      top: const [],
      promptTokens: 1,
    );
  }

  @override
  Future<String> getAvailableBackends() async => 'capability-backends';

  @override
  Future<int?> getResolvedGpuLayers() async => 123;

  @override
  Future<BackendPerfContextData?> getPerformanceContext(
    int contextHandle,
  ) async {
    return const BackendPerfContextData(
      loadMs: 1,
      promptEvalMs: 2,
      evalMs: 3,
      sampleMs: 4,
      promptEvalTokens: 5,
      evalTokens: 7,
      sampleCount: 8,
      reusedGraphs: 9,
    );
  }

  @override
  bool get supportsEmbeddings => true;

  @override
  Future<List<double>> embed(
    int contextHandle,
    String text, {
    bool normalize = true,
  }) async {
    return const <double>[1.0, 2.0];
  }

  @override
  Future<List<List<double>>> embedBatch(
    int contextHandle,
    List<String> texts, {
    bool normalize = true,
  }) async {
    return [
      for (var i = 0; i < texts.length; i++) <double>[i + 1.0],
    ];
  }

  @override
  bool get supportsStatePersistence => true;

  @override
  Future<bool> stateSaveFile(
    int contextHandle,
    String path,
    List<int> tokens,
  ) async {
    return true;
  }

  @override
  Future<StateLoadResult> stateLoadFile(
    int contextHandle,
    String path,
    int tokenCapacity,
  ) async {
    return const StateLoadResult(tokens: [3]);
  }
}

class _GenerationCapabilitiesFakeBackend extends _FakeBackend
    implements BackendGenerationCapabilitiesSupport {
  _GenerationCapabilitiesFakeBackend({
    required super.handle,
    this.capabilities = const BackendGenerationCapabilities(
      presencePenalty: true,
      minP: true,
      thinkingBudget: true,
    ),
  });

  final BackendGenerationCapabilities capabilities;

  @override
  Future<BackendGenerationCapabilities> generationCapabilities() async {
    return capabilities;
  }
}

class _DirectMediaFakeBackend extends _FakeBackend
    implements BackendDirectMediaInput {
  _DirectMediaFakeBackend({required super.handle});

  @override
  Future<({bool vision, bool audio})> directMediaInput() async =>
      (vision: true, audio: true);
}

class _ToolResultMediaFakeBackend extends _FakeBackend
    implements BackendToolResultMedia {
  _ToolResultMediaFakeBackend({required super.handle});

  @override
  Set<LlamaToolResultMedia> get toolResultMedia => const {
    LlamaToolResultMedia.image,
  };
}

class _TextToSpeechFakeBackend extends _FakeBackend
    implements BackendTextToSpeech, BackendTextToSpeechModelSupport {
  _TextToSpeechFakeBackend({required super.handle});

  (int, int)? capabilityHandles;
  (int, int)? synthesisHandles;
  final List<BackendTextToSpeechModel> probedModels = [];

  @override
  Future<String?> textToSpeechModelUnsupportedReason(
    BackendTextToSpeechModel model,
  ) async {
    probedModels.add(model);
    return model == BackendTextToSpeechModel.soprano ? 'no soprano' : null;
  }

  @override
  Future<BackendTextToSpeechCapabilities> textToSpeechCapabilities(
    int contextHandle,
    int mmContextHandle,
  ) async {
    capabilityHandles = (contextHandle, mmContextHandle);
    return const BackendTextToSpeechCapabilities(isSupported: true);
  }

  @override
  Future<BackendTextToSpeechResult> synthesizeTextToSpeech(
    int contextHandle,
    int mmContextHandle,
    BackendTextToSpeechRequest request, {
    void Function(BackendTextToSpeechProgress progress)? onProgress,
  }) async {
    synthesisHandles = (contextHandle, mmContextHandle);
    return BackendTextToSpeechResult(
      samples: Float32List(0),
      sampleRateHz: 24000,
      channelCount: 1,
      framesGenerated: 0,
      truncated: false,
    );
  }

  @override
  void cancelTextToSpeech() {}
}

class _DecisionFakeBackend extends _FakeBackend implements BackendDecision {
  _DecisionFakeBackend({required super.handle});

  final List<String> decisionCalls = <String>[];

  @override
  Future<BackendDecisionCapabilities> decisionCapabilities(
    int modelHandle,
  ) async {
    decisionCalls.add('capabilities $modelHandle');
    return const BackendDecisionCapabilities(isSupported: true);
  }

  @override
  Future<BackendDecisionHeadInfo> decisionHeadLoad(
    int modelHandle,
    String headPath, {
    String? configPath,
  }) async {
    decisionCalls.add('load $modelHandle $headPath $configPath');
    return const BackendDecisionHeadInfo(
      handle: 77,
      hiddenSize: 4,
      clsToken: 1,
      sepToken: 2,
      maskToken: 3,
      maskText: '[MASK]',
      configJson: '{}',
      deviceName: 'CPU',
    );
  }

  @override
  Future<List<BackendDecisionOutput>> decisionRun(
    int headHandle,
    List<BackendDecisionSequence> sequences,
  ) async {
    decisionCalls.add('run $headHandle ${sequences.length}');
    return [
      BackendDecisionOutput(
        logits: Float32List.fromList([0.25]),
        actLogits: Float32List.fromList([0.0, 0.0]),
      ),
    ];
  }

  @override
  Future<void> decisionHeadFree(int headHandle) async {
    decisionCalls.add('free $headHandle');
  }
}

class _FakeModelDownloadManager implements ModelDownloadManager {
  _FakeModelDownloadManager(this.entry);

  final ModelCacheEntry entry;
  ModelSource? lastSource;
  ModelLoadOptions? lastOptions;
  int ensureModelCalls = 0;

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    ensureModelCalls += 1;
    lastSource = source;
    lastOptions = options;
    return entry;
  }

  @override
  Future<void> clear({String? cacheDirectory}) async {}

  @override
  Future<ModelCacheEntry?> get(
    String cacheKey, {
    String? cacheDirectory,
  }) async {
    return cacheKey == entry.cacheKey ? entry : null;
  }

  @override
  Future<List<ModelCacheEntry>> list({String? cacheDirectory}) async {
    return <ModelCacheEntry>[entry];
  }

  @override
  Future<List<ModelCacheEntry>> prune({
    Duration? maxAge,
    int? maxBytes,
    String? cacheDirectory,
  }) async {
    return const <ModelCacheEntry>[];
  }

  @override
  Future<void> remove(String cacheKey, {String? cacheDirectory}) async {}
}

class _PromptPenaltyDelegate extends MockLlamaBackend
    implements BackendPromptPenaltyGeneration {
  _PromptPenaltyDelegate(this.supportsPromptPenaltiesWithGrammar);
  @override
  final bool supportsPromptPenaltiesWithGrammar;
  int policyCalls = 0;
  String? marker;
  @override
  Stream<List<int>> generateWithPromptPenalties(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    String? mediaMarker,
    List<LlamaContentPart>? parts,
  }) {
    policyCalls++;
    marker = mediaMarker;
    return super.generate(contextHandle, prompt, params, parts: parts);
  }
}
