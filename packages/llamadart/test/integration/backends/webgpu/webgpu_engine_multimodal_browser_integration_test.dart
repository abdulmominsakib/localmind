@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/webgpu/interop.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_backend.dart';
import 'package:test/test.dart';

void main() {
  group('WebGPU multimodal engine integration', () {
    late JSObject bridge;
    late WebGpuLlamaBackend backend;
    late LlamaEngine engine;
    late bool mmLoaded;
    late bool sawAudioPart;
    String? lastStateSavePath;
    List<int>? lastStateSaveTokens;
    String? lastStateLoadPath;
    int? lastStateLoadCapacity;
    int? lastLoadNBatch;
    int? lastLoadNUbatch;
    bool? lastLoadUseCache;
    var modelLoadCallCount = 0;
    var failFirstWasm32StagingAbort = false;
    var failWasm64StagingUntilRemoteFetch = false;
    late List<bool?> bridgePreferMemory64Values;
    late List<bool?> loadForceRemoteFetchValues;

    setUp(() {
      globalContext.delete('__llamadartBridgeAllowAutoRemoteFetchBackend'.toJS);
      globalContext.delete('__llamadartBridgeForceRemoteFetchBackend'.toJS);
      bridge = JSObject();
      mmLoaded = false;
      sawAudioPart = false;
      lastStateSavePath = null;
      lastStateSaveTokens = null;
      lastStateLoadPath = null;
      lastStateLoadCapacity = null;
      lastLoadNBatch = null;
      lastLoadNUbatch = null;
      lastLoadUseCache = null;
      modelLoadCallCount = 0;
      failFirstWasm32StagingAbort = false;
      failWasm64StagingUntilRemoteFetch = false;
      bridgePreferMemory64Values = <bool?>[];
      loadForceRemoteFetchValues = <bool?>[];

      bridge.setProperty(
        'loadModelFromUrl'.toJS,
        ((String url, JSObject? config) {
          modelLoadCallCount += 1;
          bool? forceRemoteFetchBackend;
          if (config != null) {
            final nBatch = config.getProperty('nBatch'.toJS);
            final nUbatch = config.getProperty('nUbatch'.toJS);
            lastLoadNBatch = nBatch.isA<JSNumber>()
                ? (nBatch as JSNumber).toDartInt
                : null;
            lastLoadNUbatch = nUbatch.isA<JSNumber>()
                ? (nUbatch as JSNumber).toDartInt
                : null;
            final useCache = config.getProperty('useCache'.toJS);
            lastLoadUseCache = useCache.isA<JSBoolean>()
                ? (useCache as JSBoolean).toDart
                : null;
            final forceRemoteFetch = config.getProperty(
              'forceRemoteFetchBackend'.toJS,
            );
            forceRemoteFetchBackend = forceRemoteFetch.isA<JSBoolean>()
                ? (forceRemoteFetch as JSBoolean).toDart
                : null;
          }
          loadForceRemoteFetchValues.add(forceRemoteFetchBackend);
          if (failFirstWasm32StagingAbort && modelLoadCallCount == 1) {
            return Future<void>.error(
              Exception('Aborted(). Build with -sASSERTIONS for more info.'),
            ).toJS;
          }
          if (failWasm64StagingUntilRemoteFetch &&
              forceRemoteFetchBackend != true) {
            return Future<void>.error(
              Exception('Aborted(). Build with -sASSERTIONS for more info.'),
            ).toJS;
          }
          return Future<void>.value().toJS;
        }).toJS,
      );

      bridge.setProperty(
        'createCompletion'.toJS,
        ((String prompt, JSObject opts) {
          final parts = opts.getProperty('parts'.toJS);
          if (parts.isA<JSArray>()) {
            final jsParts = parts as JSArray;
            final partCount = jsParts.length;
            for (int i = 0; i < partCount; i++) {
              final rawPart = jsParts.getProperty(i.toJS);
              if (!rawPart.isA<JSObject>()) {
                continue;
              }

              final part = rawPart as JSObject;
              final type = part.getProperty('type'.toJS);
              if (type.isA<JSString>() &&
                  (type as JSString).toDart == 'audio') {
                sawAudioPart = true;
              }
            }
          }

          final onToken = opts.getProperty('onToken'.toJS) as JSFunction?;
          if (onToken != null) {
            final piece = JSUint8Array.withLength(5);
            piece.toDart.setAll(0, <int>[72, 101, 108, 108, 111]);
            onToken.callAsFunction(null, piece, 'Hello'.toJS);
          }

          return Future<void>.value().toJS;
        }).toJS,
      );

      bridge.setProperty(
        'loadMultimodalProjector'.toJS,
        ((String path) {
          mmLoaded = true;
          return Future<JSNumber>.value(1.toJS).toJS;
        }).toJS,
      );
      bridge.setProperty(
        'unloadMultimodalProjector'.toJS,
        (() {
          mmLoaded = false;
          return Future<void>.value().toJS;
        }).toJS,
      );
      bridge.setProperty('supportsVision'.toJS, (() => false).toJS);
      bridge.setProperty('supportsAudio'.toJS, (() => mmLoaded).toJS);

      bridge.setProperty(
        'tokenize'.toJS,
        ((String text, bool addSpecial) {
          final arr = JSUint32Array.withLength(3);
          arr.toDart[0] = 1;
          arr.toDart[1] = 2;
          arr.toDart[2] = 3;
          return Future<JSUint32Array>.value(arr).toJS;
        }).toJS,
      );

      bridge.setProperty(
        'detokenize'.toJS,
        ((JSArray tokens, bool special) {
          return Future<JSString>.value('decoded'.toJS).toJS;
        }).toJS,
      );

      bridge.setProperty(
        'stateSaveFile'.toJS,
        ((String path, JSArray tokens) {
          lastStateSavePath = path;
          lastStateSaveTokens = <int>[];
          for (int i = 0; i < tokens.length; i++) {
            final raw = tokens.getProperty(i.toJS);
            if (raw.isA<JSNumber>()) {
              lastStateSaveTokens!.add((raw as JSNumber).toDartInt);
            }
          }
          return Future<JSBoolean>.value(true.toJS).toJS;
        }).toJS,
      );

      bridge.setProperty(
        'stateLoadFile'.toJS,
        ((String path, int tokenCapacity) {
          lastStateLoadPath = path;
          lastStateLoadCapacity = tokenCapacity;
          final result = JSObject();
          result.setProperty(
            'tokens'.toJS,
            <JSNumber>[7.toJS, 8.toJS, 9.toJS].toJS,
          );
          return Future<JSObject>.value(result).toJS;
        }).toJS,
      );

      bridge.setProperty(
        'embed'.toJS,
        ((String text, JSObject? options) {
          var normalize = true;
          if (options != null) {
            final rawNormalize = options.getProperty('normalize'.toJS);
            if (rawNormalize.isA<JSBoolean>()) {
              normalize = (rawNormalize as JSBoolean).toDart;
            }
          }

          final vector = <double>[
            text.length.toDouble(),
            normalize ? 1.0 : 0.0,
          ];
          return Future<JSArray>.value(
            vector.map((value) => value.toJS).toList(growable: false).toJS,
          ).toJS;
        }).toJS,
      );

      bridge.setProperty(
        'embedBatch'.toJS,
        ((JSArray texts, JSObject? options) {
          var normalize = true;
          if (options != null) {
            final rawNormalize = options.getProperty('normalize'.toJS);
            if (rawNormalize.isA<JSBoolean>()) {
              normalize = (rawNormalize as JSBoolean).toDart;
            }
          }

          final vectors = JSArray();
          for (int i = 0; i < texts.length; i++) {
            final raw = texts.getProperty(i.toJS);
            final text = raw.isA<JSString>() ? (raw as JSString).toDart : '';
            final vector = JSArray();
            vector.setProperty(0.toJS, text.length.toDouble().toJS);
            vector.setProperty(1.toJS, (normalize ? 1.0 : 0.0).toJS);
            vectors.setProperty(i.toJS, vector);
          }
          return Future<JSArray>.value(vectors).toJS;
        }).toJS,
      );

      bridge.setProperty(
        'getModelMetadata'.toJS,
        (() {
          final meta = JSObject();
          meta.setProperty('general.architecture'.toJS, 'llama'.toJS);
          if (failFirstWasm32StagingAbort && modelLoadCallCount == 1) {
            meta.setProperty(
              'llamadart.webgpu.core_variant'.toJS,
              'wasm32'.toJS,
            );
            meta.setProperty(
              'llamadart.webgpu.runtime_notes'.toJS,
              'core_wasm32_active;core_abort;model_fs_write_loaded:1073741824;model_fs_write_abort'
                  .toJS,
            );
          } else if (failWasm64StagingUntilRemoteFetch &&
              loadForceRemoteFetchValues.last != true) {
            meta.setProperty(
              'llamadart.webgpu.core_variant'.toJS,
              'wasm64'.toJS,
            );
            meta.setProperty(
              'llamadart.webgpu.runtime_notes'.toJS,
              'core_wasm64_active;core_abort;model_fs_write_abort'.toJS,
            );
          }
          return meta;
        }).toJS,
      );

      bridge.setProperty('getContextSize'.toJS, (() => 1024).toJS);
      bridge.setProperty('isGpuActive'.toJS, (() => true).toJS);
      bridge.setProperty('getBackendName'.toJS, (() => 'WebGPU (Mock)').toJS);
      bridge.setProperty('cancel'.toJS, (() {}).toJS);
      bridge.setProperty(
        'dispose'.toJS,
        (() {
          return Future<void>.value().toJS;
        }).toJS,
      );
      bridge.setProperty(
        'applyChatTemplate'.toJS,
        ((JSArray messages, bool addAssistant, String? customTemplate) {
          return Future<JSString>.value('templated'.toJS).toJS;
        }).toJS,
      );

      backend = WebGpuLlamaBackend(
        bridgeFactory: ([config]) {
          if (config == null) {
            bridgePreferMemory64Values.add(null);
          } else {
            final rawPreferMemory64 = config.getProperty('preferMemory64'.toJS);
            bridgePreferMemory64Values.add(
              rawPreferMemory64.isA<JSBoolean>()
                  ? (rawPreferMemory64 as JSBoolean).toDart
                  : null,
            );
          }
          return bridge as LlamaWebGpuBridge;
        },
      );
      engine = LlamaEngine(backend);
    });

    tearDown(() async {
      await engine.dispose();
      globalContext.delete('__llamadartBridgeAllowAutoRemoteFetchBackend'.toJS);
      globalContext.delete('__llamadartBridgeForceRemoteFetchBackend'.toJS);
    });

    test('WebGPU load bounds Gemma 4 batches for browser memory', () async {
      await engine.loadModelFromUrl(
        'https://example.com/gemma-4-E2B-it-Q4_K_S.gguf',
        modelParams: const ModelParams(contextSize: 4096, gpuLayers: 99),
      );

      expect(lastLoadNBatch, 512);
      expect(lastLoadNUbatch, 512);
      expect(lastLoadUseCache, isTrue);
    });

    test('WebGPU load retries wasm32 staging aborts with wasm64', () async {
      failFirstWasm32StagingAbort = true;

      // Use a model that is not pre-flagged for mem64 (not Gemma 4 and no size
      // hint), so the first attempt starts on wasm32 and the OOM/staging-abort
      // escalation to the wasm64 core is exercised. Known-large models like
      // Gemma 4 now start on wasm64 up front and would not hit this retry path.
      await engine.loadModelFromUrl(
        'https://example.com/large-model.gguf',
        modelParams: const ModelParams(contextSize: 4096, gpuLayers: 99),
      );

      expect(modelLoadCallCount, 2);
      expect(bridgePreferMemory64Values, <bool?>[null, true]);
      expect(loadForceRemoteFetchValues, <bool?>[null, false]);
    });

    test(
      'WebGPU load does not force remote fetch after wasm64 staging failure',
      () async {
        failWasm64StagingUntilRemoteFetch = true;

        await expectLater(
          () => engine.loadModelFromUrl(
            'https://example.com/large-model.gguf',
            modelParams: const ModelParams(
              contextSize: 4096,
              gpuLayers: 99,
              preferMemory64: true,
            ),
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.toString(),
              'message',
              allOf(
                contains('__llamadartBridgeAllowAutoRemoteFetchBackend = true'),
                contains('valid GGUF byte ranges'),
              ),
            ),
          ),
        );

        expect(modelLoadCallCount, 1);
        expect(loadForceRemoteFetchValues, <bool?>[null]);
      },
    );

    test(
      'WebGPU load retries wasm64 staging failure after explicit opt-in',
      () async {
        globalContext.setProperty(
          '__llamadartBridgeAllowAutoRemoteFetchBackend'.toJS,
          true.toJS,
        );
        failWasm64StagingUntilRemoteFetch = true;

        await engine.loadModelFromUrl(
          'https://example.com/large-model.gguf',
          modelParams: const ModelParams(
            contextSize: 4096,
            gpuLayers: 99,
            preferMemory64: true,
          ),
        );

        expect(modelLoadCallCount, 2);
        expect(loadForceRemoteFetchValues, <bool?>[null, true]);
      },
    );

    test('WebGPU load keeps Qwen3.5 0.8B browser-safe batch tuning', () async {
      await engine.loadModelFromUrl(
        'https://example.com/Qwen3.5-0.8B-Q4_K_M.gguf',
        modelParams: const ModelParams(contextSize: 4096, gpuLayers: 99),
      );

      expect(lastLoadNBatch, 32);
      expect(lastLoadNUbatch, 8);
    });

    test('WebGPU load forwards explicit batch sizing', () async {
      await engine.loadModelFromUrl(
        'https://example.com/gemma-4-E2B-it-Q4_K_S.gguf',
        modelParams: const ModelParams(
          contextSize: 4096,
          gpuLayers: 99,
          batchSize: 128,
          microBatchSize: 64,
        ),
      );

      expect(lastLoadNBatch, 128);
      expect(lastLoadNUbatch, 64);
    });

    test('WebGPU load disables cache for signed URLs', () async {
      await engine.loadModelFromUrl(
        'https://example.com/gemma-4-E2B-it-Q4_K_S.gguf?token=secret',
        modelParams: const ModelParams(contextSize: 4096, gpuLayers: 99),
      );

      expect(lastLoadUseCache, isFalse);
    });

    test('LlamaEngine create forwards multimodal audio parts', () async {
      await engine.loadModelFromUrl(
        'https://example.com/model.gguf',
        modelParams: const ModelParams(contextSize: 1024),
      );
      await engine.loadMultimodalProjector('https://example.com/mmproj.gguf');

      expect(await engine.supportsAudio, isTrue);
      expect(await engine.supportsVision, isFalse);

      final chunks = await engine.create(<LlamaChatMessage>[
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: <LlamaContentPart>[
            const LlamaTextContent('Transcribe this audio.'),
            LlamaAudioContent(
              samples: Float32List.fromList(<double>[0.1, -0.2, 0.3]),
            ),
          ],
        ),
      ], params: const GenerationParams(maxTokens: 8)).toList();

      final output = chunks
          .map((chunk) => chunk.choices.first.delta.content ?? '')
          .join();

      expect(output, contains('Hello'));
      expect(sawAudioPart, isTrue);
    });

    test('LlamaEngine embed and embedBatch work via web bridge', () async {
      await engine.loadModelFromUrl(
        'https://example.com/model.gguf',
        modelParams: const ModelParams(contextSize: 1024),
      );

      final vector = await engine.embed('hello world');
      expect(vector, <double>[11.0, 1.0]);

      final rawVector = await engine.embed('hello world', normalize: false);
      expect(rawVector, <double>[11.0, 0.0]);

      final batch = await engine.embedBatch(const <String>['hello', 'dart']);
      expect(batch, <List<double>>[
        <double>[5.0, 1.0],
        <double>[4.0, 1.0],
      ]);
    });

    test('LlamaEngine state persistence forwards to web bridge', () async {
      await engine.loadModelFromUrl(
        'https://example.com/model.gguf',
        modelParams: const ModelParams(contextSize: 1024),
      );

      expect(engine.supportsStatePersistence, isTrue);

      final saved = await engine.stateSaveFile(
        '/prompt-state.bin',
        tokens: const <int>[1, 2, 3],
      );
      expect(saved, isTrue);
      expect(lastStateSavePath, '/prompt-state.bin');
      expect(lastStateSaveTokens, <int>[1, 2, 3]);

      final restored = await engine.stateLoadFile(
        '/prompt-state.bin',
        tokenCapacity: 1024,
      );
      expect(restored.tokens, <int>[7, 8, 9]);
      expect(lastStateLoadPath, '/prompt-state.bin');
      expect(lastStateLoadCapacity, 1024);
    });
  });
}
