@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/native/native_backend.dart';
import 'package:llamadart/src/core/engine/engine.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/config/gpu_backend.dart';
import 'package:llamadart/src/core/models/config/gpu_device_info.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/download/model_download_manager.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:llamadart/src/core/models/model_load_options.dart';
import 'package:llamadart/src/core/models/model_source.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:test/test.dart';

void main() {
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

      expect(() => backend.embed(1, 'hello'), throwsUnsupportedError);
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

  test(
    'routes multimodal, template, and VRAM calls to selected delegate',
    () async {
      final litert = _FakeBackend(handle: 22)
        ..vramInfo = (total: 2048, free: 1024)
        ..chatTemplateResponse = 'templated';
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
        expect(downloadManager.lastOptions, same(options));
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
          isA<LlamaModelException>().having(
            (error) => error.details.toString(),
            'details',
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

class _FakeBackend
    implements
        LlamaBackend,
        BackendGrammarConstraintsSupport,
        BackendGpuEnumeration {
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

class _CapabilityFakeBackend extends _FakeBackend
    implements
        BackendAvailability,
        BackendRuntimeDiagnostics,
        BackendPerformanceDiagnostics,
        BackendEmbeddings,
        BackendEmbeddingsSupport,
        BackendBatchEmbeddings,
        BackendStatePersistence,
        BackendStatePersistenceSupport {
  _CapabilityFakeBackend({required super.handle});

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
