@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/webgpu/interop.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_backend.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' show Response, window;

@JS('Promise.reject')
external JSPromise<JSAny?> _rejectPromise(JSAny? reason);

void main() {
  group('WebGpuLlamaBackend Unit', () {
    late JSObject bridge;
    late WebGpuLlamaBackend backend;
    late bool mmLoaded;
    late bool sawMediaParts;
    late bool sawAudioParts;
    late bool sawAudioBytes;
    int? lastRequestedGpuLayers;
    int? lastModelBytesHint;
    int? lastRequestedThreadsBatch;
    int? lastRequestedBatchSize;
    int? lastRequestedMicroBatchSize;
    late List<int> requestedContextSizes;
    late List<int> requestedBatchSizes;
    late List<int> requestedMicroBatchSizes;
    int? lastRequestedSeqMax;
    int? lastRequestedFlashAttention;
    int? lastRequestedCacheTypeK;
    int? lastRequestedCacheTypeV;
    bool? lastRequestedUseCache;
    bool? lastRequestedForceRemoteFetchBackend;
    bool? lastRequestedKvUnified;
    double? lastRequestedRopeFrequencyBase;
    double? lastRequestedRopeFrequencyScale;
    int? lastRequestedSplitMode;
    int? lastRequestedMainGpu;
    int? lastMediaMaxPredict;
    int? lastMediaMaxImagePixels;
    int? lastMediaMaxImageEdge;
    int? lastBridgeLogLevel;
    bool? lastEmitCurrentTextOnToken;
    String? lastTokenEventEncoding;
    int? lastTokenEventFlushMs;
    int? lastTokenEventFlushChars;
    String? lastMmprojPath;
    String? lastPrompt;
    String? lastStateSavePath;
    List<int>? lastStateSaveTokens;
    String? lastStateLoadPath;
    int? lastStateLoadCapacity;
    WebGpuBridgeConfig? lastBridgeConfig;
    late int runtimeGpuLayers;
    late bool runtimeGpuActive;
    late int runtimeThreads;
    late bool stateSaveResult;
    late String stateLoadReturnShape;
    int createCompletionCallCount = 0;
    int warmupCallCount = 0;
    int cancelCallCount = 0;

    void clearBridgeGlobals() {
      globalContext.delete('LlamaWebGpuBridge'.toJS);
      globalContext.delete('__llamadartBridgeLoadError'.toJS);
      globalContext.delete('__llamadartBridgeAssetSource'.toJS);
      globalContext.delete('__llamadartBridgeModuleUrl'.toJS);
      globalContext.delete('__llamadartBridgeCoreModuleUrl'.toJS);
      globalContext.delete('__llamadartBridgeWasmUrl'.toJS);
      globalContext.delete('__llamadartBridgeWasmUrlMem64'.toJS);
      globalContext.delete('__llamadartBridgeUserAgent'.toJS);
      globalContext.delete('__llamadartAllowSafariWebGpu'.toJS);
      globalContext.delete('__llamadartBridgeAdaptiveSafariGpu'.toJS);
      globalContext.delete('__llamadartBridgeRemoteFetchChunkBytes'.toJS);
      globalContext.delete('__llamadartBridgeAllowAutoRemoteFetchBackend'.toJS);
      globalContext.delete('__llamadartBridgeForceRemoteFetchBackend'.toJS);
      globalContext.delete('__llamadartBridgeThreadPoolSize'.toJS);
    }

    void recordLoadConfig(JSObject? config) {
      if (config == null) {
        return;
      }

      final nCtx = config.getProperty('nCtx'.toJS);
      if (nCtx.isA<JSNumber>()) {
        requestedContextSizes.add((nCtx as JSNumber).toDartInt);
      }

      final nGpuLayers = config.getProperty('nGpuLayers'.toJS);
      if (nGpuLayers.isA<JSNumber>()) {
        lastRequestedGpuLayers = (nGpuLayers as JSNumber).toDartInt;
      }

      final modelBytesHint = config.getProperty('modelBytesHint'.toJS);
      if (modelBytesHint.isA<JSNumber>()) {
        lastModelBytesHint = (modelBytesHint as JSNumber).toDartInt;
      }

      final nThreadsBatch = config.getProperty('nThreadsBatch'.toJS);
      if (nThreadsBatch.isA<JSNumber>()) {
        lastRequestedThreadsBatch = (nThreadsBatch as JSNumber).toDartInt;
      }

      final nBatch = config.getProperty('nBatch'.toJS);
      if (nBatch.isA<JSNumber>()) {
        lastRequestedBatchSize = (nBatch as JSNumber).toDartInt;
        requestedBatchSizes.add(lastRequestedBatchSize!);
      }

      final nUbatch = config.getProperty('nUbatch'.toJS);
      if (nUbatch.isA<JSNumber>()) {
        lastRequestedMicroBatchSize = (nUbatch as JSNumber).toDartInt;
        requestedMicroBatchSizes.add(lastRequestedMicroBatchSize!);
      }

      final nSeqMax = config.getProperty('nSeqMax'.toJS);
      if (nSeqMax.isA<JSNumber>()) {
        lastRequestedSeqMax = (nSeqMax as JSNumber).toDartInt;
      }

      final flashAttention = config.getProperty('flashAttention'.toJS);
      if (flashAttention.isA<JSNumber>()) {
        lastRequestedFlashAttention = (flashAttention as JSNumber).toDartInt;
      }

      final cacheTypeK = config.getProperty('cacheTypeK'.toJS);
      if (cacheTypeK.isA<JSNumber>()) {
        lastRequestedCacheTypeK = (cacheTypeK as JSNumber).toDartInt;
      }

      final cacheTypeV = config.getProperty('cacheTypeV'.toJS);
      if (cacheTypeV.isA<JSNumber>()) {
        lastRequestedCacheTypeV = (cacheTypeV as JSNumber).toDartInt;
      }

      final useCache = config.getProperty('useCache'.toJS);
      if (useCache.isA<JSBoolean>()) {
        lastRequestedUseCache = (useCache as JSBoolean).toDart;
      }

      final forceRemoteFetchBackend = config.getProperty(
        'forceRemoteFetchBackend'.toJS,
      );
      if (forceRemoteFetchBackend.isA<JSBoolean>()) {
        lastRequestedForceRemoteFetchBackend =
            (forceRemoteFetchBackend as JSBoolean).toDart;
      }

      final kvUnified = config.getProperty('kvUnified'.toJS);
      if (kvUnified.isA<JSBoolean>()) {
        lastRequestedKvUnified = (kvUnified as JSBoolean).toDart;
      }

      final ropeFrequencyBase = config.getProperty('ropeFrequencyBase'.toJS);
      if (ropeFrequencyBase.isA<JSNumber>()) {
        lastRequestedRopeFrequencyBase =
            (ropeFrequencyBase as JSNumber).toDartDouble;
      }

      final ropeFrequencyScale = config.getProperty('ropeFrequencyScale'.toJS);
      if (ropeFrequencyScale.isA<JSNumber>()) {
        lastRequestedRopeFrequencyScale =
            (ropeFrequencyScale as JSNumber).toDartDouble;
      }

      final splitMode = config.getProperty('splitMode'.toJS);
      if (splitMode.isA<JSNumber>()) {
        lastRequestedSplitMode = (splitMode as JSNumber).toDartInt;
      }

      final mainGpu = config.getProperty('mainGpu'.toJS);
      if (mainGpu.isA<JSNumber>()) {
        lastRequestedMainGpu = (mainGpu as JSNumber).toDartInt;
      }
    }

    setUp(() {
      clearBridgeGlobals();

      bridge = JSObject();
      mmLoaded = false;
      sawMediaParts = false;
      sawAudioParts = false;
      sawAudioBytes = false;
      lastRequestedGpuLayers = null;
      lastModelBytesHint = null;
      lastRequestedThreadsBatch = null;
      lastRequestedBatchSize = null;
      lastRequestedMicroBatchSize = null;
      requestedContextSizes = <int>[];
      requestedBatchSizes = <int>[];
      requestedMicroBatchSizes = <int>[];
      lastRequestedSeqMax = null;
      lastRequestedFlashAttention = null;
      lastRequestedCacheTypeK = null;
      lastRequestedCacheTypeV = null;
      lastRequestedUseCache = null;
      lastRequestedForceRemoteFetchBackend = null;
      lastRequestedKvUnified = null;
      lastRequestedRopeFrequencyBase = null;
      lastRequestedRopeFrequencyScale = null;
      lastRequestedSplitMode = null;
      lastRequestedMainGpu = null;
      lastMediaMaxPredict = null;
      lastMediaMaxImagePixels = null;
      lastMediaMaxImageEdge = null;
      lastBridgeLogLevel = null;
      lastEmitCurrentTextOnToken = null;
      lastTokenEventEncoding = null;
      lastTokenEventFlushMs = null;
      lastTokenEventFlushChars = null;
      lastMmprojPath = null;
      lastPrompt = null;
      lastStateSavePath = null;
      lastStateSaveTokens = null;
      lastStateLoadPath = null;
      lastStateLoadCapacity = null;
      lastBridgeConfig = null;
      runtimeGpuLayers = 99;
      runtimeGpuActive = true;
      runtimeThreads = 4;
      stateSaveResult = true;
      stateLoadReturnShape = 'object';
      createCompletionCallCount = 0;
      warmupCallCount = 0;
      cancelCallCount = 0;

      bridge.setProperty(
        'loadModelFromUrl'.toJS,
        ((String url, JSObject? config) {
          recordLoadConfig(config);
          return Future<void>.value().toJS;
        }).toJS,
      );

      bridge.setProperty(
        'createCompletion'.toJS,
        ((String prompt, JSObject opts) {
          createCompletionCallCount += 1;
          lastPrompt = prompt;

          final emitCurrentTextRaw = opts.getProperty(
            'emitCurrentTextOnToken'.toJS,
          );
          if (emitCurrentTextRaw.isA<JSBoolean>()) {
            lastEmitCurrentTextOnToken =
                (emitCurrentTextRaw as JSBoolean).toDart;
          }

          final tokenEventEncodingRaw = opts.getProperty(
            'tokenEventEncoding'.toJS,
          );
          if (tokenEventEncodingRaw.isA<JSString>()) {
            lastTokenEventEncoding = (tokenEventEncodingRaw as JSString).toDart;
          }

          final tokenEventFlushMsRaw = opts.getProperty(
            'tokenEventFlushMs'.toJS,
          );
          if (tokenEventFlushMsRaw.isA<JSNumber>()) {
            lastTokenEventFlushMs =
                (tokenEventFlushMsRaw as JSNumber).toDartInt;
          }

          final tokenEventFlushCharsRaw = opts.getProperty(
            'tokenEventFlushChars'.toJS,
          );
          if (tokenEventFlushCharsRaw.isA<JSNumber>()) {
            lastTokenEventFlushChars =
                (tokenEventFlushCharsRaw as JSNumber).toDartInt;
          }

          final mediaMaxPredictRaw = opts.getProperty('mediaMaxPredict'.toJS);
          if (mediaMaxPredictRaw.isA<JSNumber>()) {
            lastMediaMaxPredict = (mediaMaxPredictRaw as JSNumber).toDartInt;
          }

          final mediaMaxImagePixelsRaw = opts.getProperty(
            'mediaMaxImagePixels'.toJS,
          );
          if (mediaMaxImagePixelsRaw.isA<JSNumber>()) {
            lastMediaMaxImagePixels =
                (mediaMaxImagePixelsRaw as JSNumber).toDartInt;
          }

          final mediaMaxImageEdgeRaw = opts.getProperty(
            'mediaMaxImageEdge'.toJS,
          );
          if (mediaMaxImageEdgeRaw.isA<JSNumber>()) {
            lastMediaMaxImageEdge =
                (mediaMaxImageEdgeRaw as JSNumber).toDartInt;
          }

          int? nPredict;
          final nPredictRaw = opts.getProperty('nPredict'.toJS);
          if (nPredictRaw.isA<JSNumber>()) {
            nPredict = (nPredictRaw as JSNumber).toDartInt;
          }

          final isWarmupCall =
              nPredict == 1 &&
              lastMediaMaxPredict == 1 &&
              !opts.getProperty('onToken'.toJS).isA<JSFunction>();
          if (isWarmupCall) {
            warmupCallCount += 1;
            return Future<void>.value().toJS;
          }

          final parts = opts.getProperty('parts'.toJS);
          if (parts.isA<JSArray>()) {
            final jsParts = parts as JSArray;
            final partCount = jsParts.length;
            if (partCount > 0) {
              sawMediaParts = true;

              for (int i = 0; i < partCount; i++) {
                final rawPart = jsParts.getProperty(i.toJS);
                if (!rawPart.isA<JSObject>()) {
                  continue;
                }

                final part = rawPart as JSObject;
                final type = part.getProperty('type'.toJS);
                if (type.isA<JSString>() &&
                    (type as JSString).toDart == 'audio') {
                  sawAudioParts = true;

                  final bytes = part.getProperty('bytes'.toJS);
                  if (bytes.isA<JSUint8Array>() &&
                      (bytes as JSUint8Array).toDart.isNotEmpty) {
                    sawAudioBytes = true;
                  }
                }
              }
            }
          }

          final onToken = opts.getProperty('onToken'.toJS) as JSFunction?;
          if (onToken != null) {
            onToken.callAsFunction(null, 'Hello'.toJS, 'Hello'.toJS);
          }
          return Future<void>.value().toJS;
        }).toJS,
      );

      bridge.setProperty(
        'loadMultimodalProjector'.toJS,
        ((String path) {
          mmLoaded = true;
          lastMmprojPath = path;
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
      bridge.setProperty('supportsVision'.toJS, (() => mmLoaded).toJS);
      bridge.setProperty('supportsAudio'.toJS, (() => false).toJS);

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
          return Future<JSBoolean>.value(stateSaveResult.toJS).toJS;
        }).toJS,
      );

      bridge.setProperty(
        'stateLoadFile'.toJS,
        ((String path, int tokenCapacity) {
          lastStateLoadPath = path;
          lastStateLoadCapacity = tokenCapacity;

          JSAny result;
          if (stateLoadReturnShape == 'array') {
            result = <JSNumber>[7.toJS, 8.toJS, 9.toJS].toJS;
          } else if (stateLoadReturnShape == 'uint32') {
            final arr = JSUint32Array.withLength(3);
            arr.toDart[0] = 7;
            arr.toDart[1] = 8;
            arr.toDart[2] = 9;
            result = arr;
          } else {
            final obj = JSObject();
            obj.setProperty(
              'tokens'.toJS,
              <JSNumber>[7.toJS, 8.toJS, 9.toJS].toJS,
            );
            result = obj;
          }

          return Future<JSAny>.value(result).toJS;
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
          meta.setProperty(
            'llamadart.webgpu.n_gpu_layers'.toJS,
            runtimeGpuLayers.toString().toJS,
          );
          meta.setProperty(
            'llamadart.webgpu.n_threads'.toJS,
            runtimeThreads.toString().toJS,
          );
          return meta;
        }).toJS,
      );

      bridge.setProperty('getContextSize'.toJS, (() => 4096).toJS);
      bridge.setProperty('isGpuActive'.toJS, (() => runtimeGpuActive).toJS);
      bridge.setProperty('getBackendName'.toJS, (() => 'WebGPU (Mock)').toJS);
      bridge.setProperty('cancel'.toJS, (() => cancelCallCount += 1).toJS);
      bridge.setProperty(
        'setLogLevel'.toJS,
        ((int level) {
          lastBridgeLogLevel = level;
        }).toJS,
      );
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
          lastBridgeConfig = config;
          return bridge as LlamaWebGpuBridge;
        },
      );
    });

    tearDown(() async {
      await backend.dispose();
      clearBridgeGlobals();
    });

    test('uses bridge when available', () async {
      final modelHandle = await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(contextSize: 4096),
      );

      expect(modelHandle, 1);
      expect(await backend.getBackendName(), 'WebGPU (Mock)');
      expect(await backend.isGpuSupported(), isTrue);
      expect(await backend.getContextSize(1), 4096);
    });

    bool? capturedPreferMemory64() {
      final config = lastBridgeConfig;
      if (config == null) {
        return null;
      }
      final value = config.getProperty('preferMemory64'.toJS);
      if (value.isA<JSBoolean>()) {
        return (value as JSBoolean).toDart;
      }
      return null;
    }

    test('explicit preferMemory64 is forwarded to the bridge config', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(preferMemory64: true),
      );
      expect(capturedPreferMemory64(), isTrue);

      await backend.dispose();
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(preferMemory64: false),
      );
      expect(capturedPreferMemory64(), isFalse);
    });

    test('auto-enables mem64 for large model size hints', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(modelBytesHint: 3 * 1024 * 1024 * 1024),
      );
      expect(capturedPreferMemory64(), isTrue);
      expect(lastModelBytesHint, 3 * 1024 * 1024 * 1024);
    });

    test('leaves mem64 unset for a sub-ceiling size hint', () async {
      // Selection is size-driven, not model-name based: a known-large model
      // name with a small/absent hint must NOT force mem64.
      await backend.modelLoadFromUrl(
        'https://example.com/gemma-4-E2B-it-Q4_K_S.gguf',
        const ModelParams(modelBytesHint: 100 * 1024 * 1024),
      );
      expect(capturedPreferMemory64(), isNull);
    });

    test('leaves mem64 unset for small models without a hint', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/tiny-model.gguf',
        const ModelParams(),
      );
      expect(capturedPreferMemory64(), isNull);
    });

    test('keeps cache enabled for benign download query URLs', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf?download=true',
        const ModelParams(),
      );

      expect(lastRequestedUseCache, isTrue);
    });

    test('disables cache for signed query URLs', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf?token=secret',
        const ModelParams(),
      );

      expect(lastRequestedUseCache, isFalse);
    });

    test('prefers cached model stream over remote fetch backend', () async {
      const cacheName = 'llamadart-webgpu-model-cache-v1';
      const modelUrl = 'https://example.com/model.gguf?download=true';
      final cache = await window.caches.open(cacheName).toDart;
      await cache.put(modelUrl.toJS, Response('cached model'.toJS)).toDart;
      addTearDown(() async {
        await window.caches.delete(cacheName).toDart;
      });

      await backend.modelLoadFromUrl(
        modelUrl,
        const ModelParams(modelBytesHint: 3 * 1024 * 1024 * 1024),
      );

      expect(lastRequestedUseCache, isTrue);
      expect(lastRequestedForceRemoteFetchBackend, isFalse);
    });

    test('forwards batch threading and batching model params', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(
          numberOfThreadsBatch: 3,
          batchSize: 768,
          microBatchSize: 384,
        ),
      );

      expect(lastRequestedThreadsBatch, 3);
      expect(lastRequestedBatchSize, 768);
      expect(lastRequestedMicroBatchSize, 384);
    });

    test('clamps explicit web batch sizes to context bounds', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(
          contextSize: 512,
          batchSize: 2048,
          microBatchSize: 1024,
        ),
      );

      expect(lastRequestedBatchSize, 512);
      expect(lastRequestedMicroBatchSize, 512);
    });

    test('forwards native-compatible load tuning params', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(
          maxParallelSequences: 4,
          flashAttention: FlashAttention.auto,
          cacheTypeK: KvCacheType.q8_0,
          cacheTypeV: KvCacheType.q4_0,
          kvUnified: false,
          ropeFrequencyBase: 1000000,
          ropeFrequencyScale: 0.5,
          splitMode: ModelSplitMode.none,
          mainGpu: 2,
        ),
      );

      expect(lastRequestedSeqMax, 4);
      expect(lastRequestedFlashAttention, 1);
      expect(lastRequestedCacheTypeK, 8);
      expect(lastRequestedCacheTypeV, 2);
      expect(lastRequestedKvUnified, isFalse);
      expect(lastRequestedRopeFrequencyBase, 1000000.0);
      expect(lastRequestedRopeFrequencyScale, 0.5);
      expect(lastRequestedSplitMode, 0);
      expect(lastRequestedMainGpu, 2);
    });

    test('auto-enables unified KV for multiple web sequence slots', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(maxParallelSequences: 3),
      );

      expect(lastRequestedSeqMax, 3);
      expect(lastRequestedKvUnified, isTrue);
    });

    test('validates KV cache and flash attention combinations', () async {
      await expectLater(
        backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(
            flashAttention: FlashAttention.disabled,
            cacheTypeK: KvCacheType.q8_0,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('applies qwen3.5-0.8b batch tuning when unset', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/Qwen_Qwen3.5-0.8B-Q4_K_M.gguf',
        const ModelParams(contextSize: 4096),
      );

      expect(lastRequestedGpuLayers, 2);
      expect(lastRequestedBatchSize, 32);
      expect(lastRequestedMicroBatchSize, 8);
    });

    test('preserves architecture-agnostic web batch defaults', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/llama-3.2-3b.gguf',
        const ModelParams(contextSize: 4096, gpuLayers: 99),
      );

      expect(lastRequestedGpuLayers, 99);
      expect(lastRequestedBatchSize, 4096);
      expect(lastRequestedMicroBatchSize, 4096);
    });

    test('bounds size-hinted large model batches when unset', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/local-large-model.gguf',
        const ModelParams(
          contextSize: 2048,
          gpuLayers: 0,
          modelBytesHint: 3 * 1024 * 1024 * 1024,
        ),
      );

      expect(lastRequestedGpuLayers, 0);
      expect(lastRequestedBatchSize, 512);
      expect(lastRequestedMicroBatchSize, 512);
    });

    test(
      'bounds large model batch while preserving explicit micro batch',
      () async {
        await backend.modelLoadFromUrl(
          'https://example.com/gemma-4-E2B-it-Q4_K_S.gguf',
          const ModelParams(contextSize: 4096, microBatchSize: 128),
        );

        expect(lastRequestedBatchSize, 512);
        expect(lastRequestedMicroBatchSize, 128);
      },
    );

    test(
      'keeps full-context batches for short WebGPU encoder contexts',
      () async {
        await backend.modelLoadFromUrl(
          'https://example.com/multilingual-e5-small-Q8_0.gguf',
          const ModelParams(contextSize: 512, gpuLayers: 99),
        );

        expect(lastRequestedGpuLayers, 99);
        expect(lastRequestedBatchSize, 512);
        expect(lastRequestedMicroBatchSize, 512);

        final vectors = await backend.embedBatch(1, const <String>[
          'first sentence',
          'second sentence',
        ]);
        expect(vectors, <List<double>>[
          <double>[14.0, 1.0],
          <double>[15.0, 1.0],
        ]);
      },
    );

    test(
      'preserves automatic full-context batches for long encoders',
      () async {
        await backend.modelLoadFromUrl(
          'https://example.com/multilingual-e5-large-Q8_0.gguf',
          const ModelParams(contextSize: 4096, gpuLayers: 99),
        );

        expect(lastRequestedBatchSize, 4096);
        expect(lastRequestedMicroBatchSize, 4096);

        final vectors = await backend.embedBatch(1, const <String>[
          'long-context encoder input',
        ]);
        expect(vectors, <List<double>>[
          <double>[26.0, 1.0],
        ]);
      },
    );

    test('caps default batches to a short CPU context', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/multilingual-e5-small-Q8_0.gguf',
        const ModelParams(
          contextSize: 512,
          preferredBackend: GpuBackend.cpu,
          gpuLayers: 0,
        ),
      );

      expect(lastRequestedBatchSize, 512);
      expect(lastRequestedMicroBatchSize, 512);
    });

    test(
      'recomputes full-context batches when fallback context shrinks',
      () async {
        var loadCallCount = 0;
        bridge.setProperty(
          'loadModelFromUrl'.toJS,
          ((String url, JSObject? config) {
            loadCallCount += 1;
            recordLoadConfig(config);

            if (loadCallCount <= 2) {
              final error = JSObject();
              error.setProperty(
                'message'.toJS,
                'array buffer allocation failed'.toJS,
              );
              return _rejectPromise(error);
            }
            return Future<void>.value().toJS;
          }).toJS,
        );

        await backend.modelLoadFromUrl(
          'https://example.com/multilingual-e5-small-Q8_0.gguf',
          const ModelParams(contextSize: 4096, gpuLayers: 99),
        );

        expect(requestedContextSizes, <int>[4096, 4096, 2048]);
        expect(requestedBatchSizes, <int>[4096, 4096, 2048]);
        expect(requestedMicroBatchSizes, <int>[4096, 4096, 2048]);
      },
    );

    test('Gemma 4 CPU fallback uses capped web batch sizes', () async {
      var loadCallCount = 0;
      bridge.setProperty(
        'loadModelFromUrl'.toJS,
        ((String url, JSObject? config) {
          loadCallCount += 1;
          recordLoadConfig(config);

          if (loadCallCount == 1) {
            final error = JSObject();
            error.setProperty(
              'message'.toJS,
              'array buffer allocation failed'.toJS,
            );
            return _rejectPromise(error);
          }
          return Future<void>.value().toJS;
        }).toJS,
      );

      await backend.modelLoadFromUrl(
        'https://example.com/gemma-4-E2B-it-Q4_K_S.gguf',
        const ModelParams(contextSize: 4096, gpuLayers: 99),
      );

      expect(requestedContextSizes, <int>[4096, 4096]);
      expect(requestedBatchSizes, <int>[512, 512]);
      expect(requestedMicroBatchSizes, <int>[512, 512]);
      expect(lastRequestedGpuLayers, 0);
    });

    test('streams generated tokens from bridge callback', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final chunks = await backend
          .generate(1, 'Hello', const GenerationParams())
          .toList();

      expect(chunks, isNotEmpty);
      expect(chunks.first, <int>[72, 101, 108, 108, 111]);
      expect(lastEmitCurrentTextOnToken, isFalse);
      expect(lastTokenEventEncoding, 'bytes');
      expect(lastTokenEventFlushMs, 28);
      expect(lastTokenEventFlushChars, 48);
    });

    test('rejects speculative decoding', () {
      expect(
        () => backend.generate(
          1,
          'Hello',
          const GenerationParams(speculativeDecoding: true),
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            contains('speculative decoding'),
          ),
        ),
      );
    });

    test('rejects presence penalty', () {
      expect(
        () => backend.generate(
          1,
          'Hello',
          const GenerationParams(presencePenalty: 1.5),
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            contains('presence penalty'),
          ),
        ),
      );
    });

    test('rejects thinking budget', () {
      expect(
        () => backend.generate(
          1,
          'Hello',
          const GenerationParams(thinkingBudget: ThinkingBudget(maxTokens: 16)),
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            contains('thinking-budget control'),
          ),
        ),
      );
    });

    test('rejects speculative decoding config', () {
      expect(
        () => backend.generate(
          1,
          'Hello',
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(),
          ),
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message.toString(),
            'message',
            contains('speculative decoding'),
          ),
        ),
      );
    });

    test(
      'canceling generation subscription aborts active bridge completion',
      () async {
        final completion = Completer<void>();
        bridge.setProperty(
          'cancel'.toJS,
          (() {
            cancelCallCount += 1;
            if (!completion.isCompleted) {
              completion.complete();
            }
          }).toJS,
        );
        bridge.setProperty(
          'createCompletion'.toJS,
          ((String prompt, JSObject opts) {
            final onToken = opts.getProperty('onToken'.toJS) as JSFunction?;
            onToken?.callAsFunction(null, 'Hello'.toJS, 'Hello'.toJS);
            return completion.future.toJS;
          }).toJS,
        );

        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );

        final subscription = backend
            .generate(1, 'Hello', const GenerationParams())
            .listen((_) {});
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();

        expect(cancelCallCount, 1);
        if (!completion.isCompleted) {
          completion.complete();
        }
      },
    );

    test('generates embedding vector from bridge', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final vector = await backend.embed(1, 'hello world');
      expect(vector, <double>[11.0, 1.0]);

      final rawVector = await backend.embed(1, 'hello world', normalize: false);
      expect(rawVector, <double>[11.0, 0.0]);
    });

    test('generates embedding batch from bridge', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final vectors = await backend.embedBatch(1, const <String>[
        'hello',
        'world!',
      ]);
      expect(vectors, <List<double>>[
        <double>[5.0, 1.0],
        <double>[6.0, 1.0],
      ]);
    });

    test(
      'falls back to sequential embed when batch API is unavailable',
      () async {
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );

        bridge.delete('embedBatch'.toJS);
        final vectors = await backend.embedBatch(1, const <String>[
          'hello',
          'dart',
        ], normalize: false);

        expect(vectors, <List<double>>[
          <double>[5.0, 0.0],
          <double>[4.0, 0.0],
        ]);
      },
    );

    test('throws clear error when embedding API is unavailable', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      bridge.delete('embed'.toJS);
      await expectLater(
        () => backend.embed(1, 'hello'),
        throwsA(
          isA<UnsupportedError>().having(
            (UnsupportedError error) => error.message,
            'message',
            contains('v0.1.7'),
          ),
        ),
      );
    });

    test('throws clear error for unsupported runtime LoRA updates', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      Future<void> expectLoraUnsupported(Future<void> Function() action) {
        return expectLater(
          action,
          throwsA(
            isA<UnsupportedError>().having(
              (UnsupportedError error) => error.message,
              'message',
              allOf(contains('WebGPU LoRA'), contains('native llama.cpp')),
            ),
          ),
        );
      }

      await expectLoraUnsupported(
        () => backend.setLoraAdapter(1, '/adapter.gguf', 0.7),
      );
      await expectLoraUnsupported(
        () => backend.removeLoraAdapter(1, '/adapter.gguf'),
      );
      await expectLoraUnsupported(() => backend.clearLoraAdapters(1));
    });

    test('forwards state persistence calls to bridge', () async {
      expect(backend.supportsStatePersistence, isFalse);
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );
      expect(backend.supportsStatePersistence, isTrue);

      final saved = await backend.stateSaveFile(
        1,
        '/prompt-prefix.state',
        const <int>[1, 2, 3],
      );
      expect(saved, isTrue);
      expect(lastStateSavePath, '/prompt-prefix.state');
      expect(lastStateSaveTokens, <int>[1, 2, 3]);

      final loaded = await backend.stateLoadFile(
        1,
        '/prompt-prefix.state',
        128,
      );
      expect(lastStateLoadPath, '/prompt-prefix.state');
      expect(lastStateLoadCapacity, 128);
      expect(loaded.tokens, <int>[7, 8, 9]);
    });

    test('propagates false state save bridge result', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      stateSaveResult = false;
      expect(
        await backend.stateSaveFile(1, '/prompt-prefix.state', const <int>[1]),
        isFalse,
      );
    });

    test('accepts direct array and typed array state load results', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      stateLoadReturnShape = 'array';
      expect(
        (await backend.stateLoadFile(1, '/array.state', 128)).tokens,
        <int>[7, 8, 9],
      );

      stateLoadReturnShape = 'uint32';
      expect(
        (await backend.stateLoadFile(1, '/typed.state', 128)).tokens,
        <int>[7, 8, 9],
      );
    });

    test(
      'throws clear error when state persistence API is unavailable',
      () async {
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );

        expect(backend.supportsStatePersistence, isTrue);
        bridge.delete('stateSaveFile'.toJS);
        expect(backend.supportsStatePersistence, isFalse);
        await expectLater(
          () => backend.stateSaveFile(1, '/missing.state', const <int>[1]),
          throwsA(
            isA<UnsupportedError>().having(
              (UnsupportedError error) => error.message,
              'message',
              contains('v0.1.15'),
            ),
          ),
        );

        bridge.setProperty(
          'stateSaveFile'.toJS,
          ((String path, JSArray tokens) {
            return Future<JSBoolean>.value(true.toJS).toJS;
          }).toJS,
        );
        expect(backend.supportsStatePersistence, isTrue);
        bridge.delete('stateLoadFile'.toJS);
        expect(backend.supportsStatePersistence, isFalse);
        await expectLater(
          () => backend.stateLoadFile(1, '/missing.state', 128),
          throwsA(
            isA<UnsupportedError>().having(
              (UnsupportedError error) => error.message,
              'message',
              contains('v0.1.15'),
            ),
          ),
        );
      },
    );

    test(
      'passes core module URL from bootstrap global to bridge config',
      () async {
        globalContext.setProperty(
          '__llamadartBridgeCoreModuleUrl'.toJS,
          'https://example.com/core.js'.toJS,
        );

        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );

        final config = lastBridgeConfig as JSObject?;
        expect(config, isNotNull);

        final value = config!.getProperty('coreModuleUrl'.toJS);
        expect(value.isA<JSString>(), isTrue);
        expect((value as JSString).toDart, 'https://example.com/core.js');

        final logLevel = config.getProperty('logLevel'.toJS);
        expect(logLevel.isA<JSNumber>(), isTrue);
        expect((logLevel as JSNumber).toDartInt, LlamaLogLevel.info.index);

        final remoteFetchChunkBytes = config.getProperty(
          'remoteFetchChunkBytes'.toJS,
        );
        expect(remoteFetchChunkBytes.isA<JSNumber>(), isTrue);
        expect((remoteFetchChunkBytes as JSNumber).toDartInt, 4 * 1024 * 1024);
      },
    );

    test('keeps automatic remote fetch disabled by default', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final config = lastBridgeConfig as JSObject?;
      expect(config, isNotNull);
      final allowAutoRemoteFetchBackend = config!.getProperty(
        'allowAutoRemoteFetchBackend'.toJS,
      );
      expect(allowAutoRemoteFetchBackend.isA<JSBoolean>(), isTrue);
      expect((allowAutoRemoteFetchBackend as JSBoolean).toDart, isFalse);
    });

    test('allows explicit automatic remote fetch opt-in', () async {
      globalContext.setProperty(
        '__llamadartBridgeAllowAutoRemoteFetchBackend'.toJS,
        true.toJS,
      );

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final config = lastBridgeConfig as JSObject?;
      expect(config, isNotNull);
      final allowAutoRemoteFetchBackend = config!.getProperty(
        'allowAutoRemoteFetchBackend'.toJS,
      );
      expect(allowAutoRemoteFetchBackend.isA<JSBoolean>(), isTrue);
      expect((allowAutoRemoteFetchBackend as JSBoolean).toDart, isTrue);
    });

    test('allows explicit forced remote fetch opt-in', () async {
      globalContext.setProperty(
        '__llamadartBridgeForceRemoteFetchBackend'.toJS,
        true.toJS,
      );

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final config = lastBridgeConfig as JSObject?;
      expect(config, isNotNull);
      final allowAutoRemoteFetchBackend = config!.getProperty(
        'allowAutoRemoteFetchBackend'.toJS,
      );
      expect(allowAutoRemoteFetchBackend.isA<JSBoolean>(), isTrue);
      expect((allowAutoRemoteFetchBackend as JSBoolean).toDart, isTrue);
      expect(lastRequestedForceRemoteFetchBackend, isTrue);
    });

    test('uses global remote fetch chunk override in bridge config', () async {
      globalContext.setProperty(
        '__llamadartBridgeRemoteFetchChunkBytes'.toJS,
        (2 * 1024 * 1024).toJS,
      );

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final config = lastBridgeConfig as JSObject?;
      expect(config, isNotNull);
      final remoteFetchChunkBytes = config!.getProperty(
        'remoteFetchChunkBytes'.toJS,
      );
      expect(remoteFetchChunkBytes.isA<JSNumber>(), isTrue);
      expect((remoteFetchChunkBytes as JSNumber).toDartInt, 2 * 1024 * 1024);
    });

    test('passes thread pool size hint to bridge config', () async {
      globalContext.setProperty('__llamadartBridgeThreadPoolSize'.toJS, 2.toJS);

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final config = lastBridgeConfig as JSObject?;
      expect(config, isNotNull);
      final threadPoolSize = config!.getProperty('threadPoolSize'.toJS);
      expect(threadPoolSize.isA<JSNumber>(), isTrue);
      expect((threadPoolSize as JSNumber).toDartInt, 2);
    });

    test('passes global wasm URLs to bridge config', () async {
      globalContext.setProperty(
        '__llamadartBridgeWasmUrl'.toJS,
        'https://example.com/core.wasm?v=1'.toJS,
      );
      globalContext.setProperty(
        '__llamadartBridgeWasmUrlMem64'.toJS,
        'https://example.com/core_mem64.wasm?v=1'.toJS,
      );

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final config = lastBridgeConfig as JSObject?;
      expect(config, isNotNull);

      final wasmUrl = config!.getProperty('wasmUrl'.toJS);
      expect(wasmUrl.isA<JSString>(), isTrue);
      expect((wasmUrl as JSString).toDart, 'https://example.com/core.wasm?v=1');

      final wasmUrlMem64 = config.getProperty('wasmUrlMem64'.toJS);
      expect(wasmUrlMem64.isA<JSString>(), isTrue);
      expect(
        (wasmUrlMem64 as JSString).toDart,
        'https://example.com/core_mem64.wasm?v=1',
      );
    });

    test('propagates runtime log level updates to bridge', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      expect(lastBridgeLogLevel, LlamaLogLevel.info.index);

      await backend.setLogLevel(LlamaLogLevel.error);
      expect(lastBridgeLogLevel, LlamaLogLevel.error.index);
    });

    test('suppresses bridge logger callbacks when log level is none', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final config = lastBridgeConfig as JSObject?;
      expect(config, isNotNull);
      final logger = config!.getProperty('logger'.toJS);
      expect(logger.isA<JSObject>(), isTrue);
      final loggerObject = logger as JSObject;

      final debugFn = loggerObject.getProperty('debug'.toJS) as JSFunction?;
      final logFn = loggerObject.getProperty('log'.toJS) as JSFunction?;
      final warnFn = loggerObject.getProperty('warn'.toJS) as JSFunction?;
      final errorFn = loggerObject.getProperty('error'.toJS) as JSFunction?;

      final consoleObject =
          globalContext.getProperty('console'.toJS) as JSObject;
      final originalDebug = consoleObject.getProperty('debug'.toJS);
      final originalLog = consoleObject.getProperty('log'.toJS);
      final originalWarn = consoleObject.getProperty('warn'.toJS);
      final originalError = consoleObject.getProperty('error'.toJS);

      var debugCalls = 0;
      var logCalls = 0;
      var warnCalls = 0;
      var errorCalls = 0;

      consoleObject.setProperty(
        'debug'.toJS,
        ((JSAny? _) => debugCalls += 1).toJS,
      );
      consoleObject.setProperty('log'.toJS, ((JSAny? _) => logCalls += 1).toJS);
      consoleObject.setProperty(
        'warn'.toJS,
        ((JSAny? _) => warnCalls += 1).toJS,
      );
      consoleObject.setProperty(
        'error'.toJS,
        ((JSAny? _) => errorCalls += 1).toJS,
      );

      try {
        await backend.setLogLevel(LlamaLogLevel.none);

        debugFn?.callAsFunction(null, 'debug'.toJS);
        logFn?.callAsFunction(null, 'log'.toJS);
        warnFn?.callAsFunction(null, 'warn'.toJS);
        errorFn?.callAsFunction(null, 'error'.toJS);

        expect(debugCalls, 0);
        expect(logCalls, 0);
        expect(warnCalls, 0);
        expect(errorCalls, 0);
      } finally {
        consoleObject.setProperty('debug'.toJS, originalDebug);
        consoleObject.setProperty('log'.toJS, originalLog);
        consoleObject.setProperty('warn'.toJS, originalWarn);
        consoleObject.setProperty('error'.toJS, originalError);
      }
    });

    test('forces CPU fallback on Safari unless override is enabled', () async {
      globalContext.setProperty(
        '__llamadartBridgeUserAgent'.toJS,
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 '
                '(KHTML, like Gecko) Version/17.5 Safari/605.1.15'
            .toJS,
      );

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(gpuLayers: 42),
      );

      expect(lastRequestedGpuLayers, 0);
    });

    test('keeps Safari GPU layers when override flag is set', () async {
      globalContext.setProperty(
        '__llamadartBridgeUserAgent'.toJS,
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 '
                '(KHTML, like Gecko) Version/17.5 Safari/605.1.15'
            .toJS,
      );
      globalContext.setProperty('__llamadartAllowSafariWebGpu'.toJS, true.toJS);

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(gpuLayers: 42),
      );

      expect(lastRequestedGpuLayers, 42);
    });

    test(
      'keeps Safari GPU layers when adaptive bridge flag is present',
      () async {
        globalContext.setProperty(
          '__llamadartBridgeUserAgent'.toJS,
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 '
                  '(KHTML, like Gecko) Version/17.5 Safari/605.1.15'
              .toJS,
        );
        globalContext.setProperty(
          '__llamadartBridgeAdaptiveSafariGpu'.toJS,
          true.toJS,
        );

        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(gpuLayers: 42),
        );

        expect(lastRequestedGpuLayers, 42);
      },
    );

    test('suppresses stop sequence text from streamed output', () async {
      bridge.setProperty(
        'createCompletion'.toJS,
        ((String prompt, JSObject opts) {
          final emitCurrentTextRaw = opts.getProperty(
            'emitCurrentTextOnToken'.toJS,
          );
          if (emitCurrentTextRaw.isA<JSBoolean>()) {
            lastEmitCurrentTextOnToken =
                (emitCurrentTextRaw as JSBoolean).toDart;
          }

          final tokenEventEncodingRaw = opts.getProperty(
            'tokenEventEncoding'.toJS,
          );
          if (tokenEventEncodingRaw.isA<JSString>()) {
            lastTokenEventEncoding = (tokenEventEncodingRaw as JSString).toDart;
          }

          final tokenEventFlushMsRaw = opts.getProperty(
            'tokenEventFlushMs'.toJS,
          );
          if (tokenEventFlushMsRaw.isA<JSNumber>()) {
            lastTokenEventFlushMs =
                (tokenEventFlushMsRaw as JSNumber).toDartInt;
          }

          final tokenEventFlushCharsRaw = opts.getProperty(
            'tokenEventFlushChars'.toJS,
          );
          if (tokenEventFlushCharsRaw.isA<JSNumber>()) {
            lastTokenEventFlushChars =
                (tokenEventFlushCharsRaw as JSNumber).toDartInt;
          }

          final onToken = opts.getProperty('onToken'.toJS) as JSFunction?;
          if (onToken != null) {
            final firstPiece = JSUint8Array.withLength(2);
            firstPiece.toDart.setAll(0, <int>[104, 105]);
            onToken.callAsFunction(null, firstPiece, 'hi'.toJS);

            final stopBytes = '<|im_end|>\n'.codeUnits;
            final secondPiece = JSUint8Array.withLength(stopBytes.length);
            secondPiece.toDart.setAll(0, stopBytes);
            onToken.callAsFunction(null, secondPiece, 'hi<|im_end|>\n'.toJS);
          }
          return Future<void>.value().toJS;
        }).toJS,
      );

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final chunks = await backend
          .generate(
            1,
            'Hello',
            const GenerationParams(stopSequences: <String>['<|im_end|>']),
          )
          .toList();

      final output = utf8.decode(chunks.expand((b) => b).toList());
      expect(output, 'hi');
      expect(output.contains('<|im_end|>'), isFalse);
      expect(lastEmitCurrentTextOnToken, isTrue);
      expect(lastTokenEventEncoding, 'bytes');
      expect(lastTokenEventFlushMs, 0);
      expect(lastTokenEventFlushChars, isNull);
    });

    test('preserves split utf8 token bytes across callbacks', () async {
      bridge.setProperty(
        'createCompletion'.toJS,
        ((String prompt, JSObject opts) {
          lastPrompt = prompt;
          final onToken = opts.getProperty('onToken'.toJS) as JSFunction?;
          if (onToken != null) {
            final firstPiece = JSUint8Array.withLength(2);
            firstPiece.toDart.setAll(0, <int>[0xF0, 0x9F]);
            onToken.callAsFunction(null, firstPiece, null);

            final secondPiece = JSUint8Array.withLength(2);
            secondPiece.toDart.setAll(0, <int>[0x98, 0x80]);
            onToken.callAsFunction(null, secondPiece, null);
          }
          return Future<void>.value().toJS;
        }).toJS,
      );

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final chunks = await backend
          .generate(1, 'Hello', const GenerationParams())
          .toList();

      expect(utf8.decode(chunks.expand((chunk) => chunk).toList()), '😀');
    });

    test('preserves chat template control token prefixes in prompts', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      await backend
          .generate(
            1,
            '<|im_start|>user\nhi<|im_end|>\n<|im_start|>assistant\n',
            const GenerationParams(),
          )
          .drain<void>();

      expect(
        lastPrompt,
        '<|im_start|>user\nhi<|im_end|>\n<|im_start|>assistant\n',
      );
    });

    test('strips real bos token prefixes before bridge generation', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      await backend
          .generate(1, '<s>Hello', const GenerationParams())
          .drain<void>();

      expect(lastPrompt, 'Hello');
    });

    test(
      'engine.create preserves leading chat template control tokens',
      () async {
        final engine = LlamaEngine(backend);
        await engine.loadModelFromUrl(
          'https://example.com/model.gguf',
          modelParams: const ModelParams(),
        );

        await engine.create(<LlamaChatMessage>[
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ]).drain<void>();

        expect(lastPrompt, startsWith('<|im_start|>user\nhi<|im_end|>'));
      },
    );

    test(
      'engine.create preserves leading chat tokens for multimodal turns',
      () async {
        final engine = LlamaEngine(backend);
        await engine.loadModelFromUrl(
          'https://example.com/model.gguf',
          modelParams: const ModelParams(),
        );
        await engine.loadMultimodalProjector('https://example.com/mmproj.gguf');

        await engine.create(<LlamaChatMessage>[
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: <LlamaContentPart>[
              LlamaImageContent(bytes: Uint8List.fromList(<int>[1, 2, 3])),
              LlamaTextContent('describe this image'),
            ],
          ),
        ]).drain<void>();

        expect(lastPrompt, startsWith('<|im_start|>user\n'));
        expect(sawMediaParts, isTrue);
      },
    );

    test(
      'buffers partial stop sequence prefixes across token callbacks',
      () async {
        bridge.setProperty(
          'createCompletion'.toJS,
          ((String prompt, JSObject opts) {
            lastPrompt = prompt;
            final onToken = opts.getProperty('onToken'.toJS) as JSFunction?;
            if (onToken != null) {
              for (final text in <String>[
                'hi<',
                'hi<|',
                'hi<|im_',
                'hi<|im_end',
                'hi<|im_end|>',
              ]) {
                onToken.callAsFunction(null, null, text.toJS);
              }
            }
            return Future<void>.error(Exception('aborted')).toJS;
          }).toJS,
        );

        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );

        final chunks = await backend
            .generate(
              1,
              'Hello',
              const GenerationParams(stopSequences: <String>['<|im_end|>']),
            )
            .toList();

        expect(utf8.decode(chunks.expand((chunk) => chunk).toList()), 'hi');
        expect(cancelCallCount, 0);
      },
    );

    test('closes generation stream after bridge completion errors', () async {
      bridge.setProperty(
        'createCompletion'.toJS,
        ((String prompt, JSObject opts) {
          return Future<void>.error(Exception('completion failed')).toJS;
        }).toJS,
      );

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final errors = <Object>[];
      final done = Completer<void>();
      backend
          .generate(1, 'Hello', const GenerationParams())
          .listen(
            (_) {},
            onError: errors.add,
            onDone: () {
              if (!done.isCompleted) {
                done.complete();
              }
            },
          );

      await done.future.timeout(const Duration(seconds: 1));
      expect(errors, hasLength(1));
      expect(errors.single.toString(), contains('Dart exception thrown'));
    });

    test('throws when bridge load fails', () async {
      bridge.setProperty(
        'loadModelFromUrl'.toJS,
        ((String url, JSObject? config) {
          return Future<void>.error(Exception('bridge load failed')).toJS;
        }).toJS,
      );

      await expectLater(
        () => backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        ),
        throwsA(anything),
      );
      expect(await backend.getBackendName(), contains('not loaded'));
    });

    test(
      'surfaces Safari compatibility hint from bridge loader errors',
      () async {
        final failingBackend = WebGpuLlamaBackend();

        globalContext.setProperty(
          '__llamadartBridgeLoadError'.toJS,
          'Local load failed: This page was compiled without support for Safari browser.'
              .toJS,
        );
        globalContext.setProperty(
          '__llamadartBridgeAssetSource'.toJS,
          'cdn'.toJS,
        );
        globalContext.setProperty(
          '__llamadartBridgeModuleUrl'.toJS,
          'https://cdn.example/bridge.js'.toJS,
        );

        await expectLater(
          () => failingBackend.modelLoadFromUrl(
            'https://example.com/model.gguf',
            const ModelParams(),
          ),
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.toString(),
              'message',
              allOf(
                contains('Safari support'),
                contains('source=cdn'),
                contains('module=https://cdn.example/bridge.js'),
              ),
            ),
          ),
        );

        await failingBackend.dispose();
      },
    );

    test('throws on multimodal prompt parts before projector load', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      expect(
        () => backend.generate(
          1,
          'Describe this image',
          const GenerationParams(),
          parts: <LlamaContentPart>[
            LlamaImageContent(bytes: Uint8List.fromList(<int>[1, 2, 3])),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('creates and uses multimodal context with media parts', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final mmHandle = await backend.multimodalContextCreate(
        1,
        'https://example.com/mmproj.gguf',
      );

      expect(mmHandle, 1);
      expect(await backend.supportsVision(mmHandle!), isTrue);
      expect(await backend.supportsAudio(mmHandle), isFalse);

      final chunks = await backend
          .generate(
            1,
            'Describe this image',
            const GenerationParams(),
            parts: <LlamaContentPart>[
              LlamaImageContent(bytes: Uint8List.fromList(<int>[1, 2, 3])),
            ],
          )
          .toList();

      expect(chunks, isNotEmpty);
      expect(sawMediaParts, isTrue);
      expect(mmLoaded, isTrue);
      expect(warmupCallCount, 1);
      expect(lastMediaMaxImagePixels, 1048576);
      expect(lastMediaMaxImageEdge, 1280);

      await backend.multimodalContextFree(mmHandle);
      expect(mmLoaded, isFalse);
      expect(await backend.supportsVision(mmHandle), isFalse);
    });

    test('loads cached projector through blob URL', () async {
      const cacheName = 'llamadart-webgpu-model-cache-v1';
      const mmprojUrl = 'https://example.com/mmproj-cached.gguf?download=true';
      final cache = await window.caches.open(cacheName).toDart;
      await cache.put(mmprojUrl.toJS, Response('cached projector'.toJS)).toDart;
      addTearDown(() async {
        await window.caches.delete(cacheName).toDart;
      });

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final mmHandle = await backend.multimodalContextCreate(1, mmprojUrl);

      expect(mmHandle, 1);
      expect(lastMmprojPath, startsWith('blob:'));
      expect(lastMmprojPath, isNot(mmprojUrl));
    });

    test('runs WebGPU multimodal warmup once per projector load', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final firstHandle = await backend.multimodalContextCreate(
        1,
        'https://example.com/mmproj.gguf',
      );
      expect(firstHandle, isNotNull);
      expect(warmupCallCount, 1);

      await backend
          .generate(
            1,
            'Describe this image',
            const GenerationParams(maxTokens: 64),
            parts: <LlamaContentPart>[
              LlamaImageContent(bytes: Uint8List.fromList(<int>[1, 2, 3])),
            ],
          )
          .toList();
      await backend
          .generate(
            1,
            'Describe this image again',
            const GenerationParams(maxTokens: 64),
            parts: <LlamaContentPart>[
              LlamaImageContent(bytes: Uint8List.fromList(<int>[4, 5, 6])),
            ],
          )
          .toList();

      expect(warmupCallCount, 1);
      expect(createCompletionCallCount, 3);

      await backend.multimodalContextFree(firstHandle!);
      final secondHandle = await backend.multimodalContextCreate(
        1,
        'https://example.com/mmproj.gguf',
      );
      expect(secondHandle, isNotNull);
      expect(warmupCallCount, 2);
    });

    test('applies adaptive CPU multimodal caps for 4-thread runtime', () async {
      runtimeGpuLayers = 0;
      runtimeGpuActive = false;

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(preferredBackend: GpuBackend.cpu, gpuLayers: 0),
      );

      final mmHandle = await backend.multimodalContextCreate(
        1,
        'https://example.com/mmproj.gguf',
      );

      expect(mmHandle, isNotNull);

      final chunks = await backend
          .generate(
            1,
            'Describe this image',
            const GenerationParams(maxTokens: 1024),
            parts: <LlamaContentPart>[
              LlamaImageContent(bytes: Uint8List.fromList(<int>[1, 2, 3])),
            ],
          )
          .toList();

      expect(chunks, isNotEmpty);
      expect(lastMediaMaxPredict, 192);
      expect(lastMediaMaxImagePixels, 307200);
      expect(lastMediaMaxImageEdge, 768);
    });

    test(
      'applies tighter CPU multimodal caps for low-thread runtime',
      () async {
        runtimeGpuLayers = 0;
        runtimeGpuActive = false;
        runtimeThreads = 1;

        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(preferredBackend: GpuBackend.cpu, gpuLayers: 0),
        );

        final mmHandle = await backend.multimodalContextCreate(
          1,
          'https://example.com/mmproj.gguf',
        );

        expect(mmHandle, isNotNull);

        final chunks = await backend
            .generate(
              1,
              'Describe this image',
              const GenerationParams(maxTokens: 1024),
              parts: <LlamaContentPart>[
                LlamaImageContent(bytes: Uint8List.fromList(<int>[1, 2, 3])),
              ],
            )
            .toList();

        expect(chunks, isNotEmpty);
        expect(lastMediaMaxPredict, 128);
        expect(lastMediaMaxImagePixels, 196608);
        expect(lastMediaMaxImageEdge, 640);
        expect(warmupCallCount, 0);
      },
    );

    test('reports audio support and forwards audio parts', () async {
      bridge.setProperty('supportsAudio'.toJS, (() => mmLoaded).toJS);

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final mmHandle = await backend.multimodalContextCreate(
        1,
        'https://example.com/mmproj.gguf',
      );

      expect(mmHandle, isNotNull);
      expect(await backend.supportsAudio(mmHandle!), isTrue);

      final chunks = await backend
          .generate(
            1,
            'Transcribe this audio',
            const GenerationParams(),
            parts: <LlamaContentPart>[
              LlamaAudioContent(
                samples: Float32List.fromList(<double>[0.1, -0.2, 0.3]),
              ),
            ],
          )
          .toList();

      expect(chunks, isNotEmpty);
      expect(sawAudioParts, isTrue);
    });

    test('forwards encoded audio bytes parts', () async {
      bridge.setProperty('supportsAudio'.toJS, (() => mmLoaded).toJS);

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final mmHandle = await backend.multimodalContextCreate(
        1,
        'https://example.com/mmproj.gguf',
      );

      expect(mmHandle, isNotNull);
      expect(await backend.supportsAudio(mmHandle!), isTrue);

      final chunks = await backend
          .generate(
            1,
            'Transcribe this audio',
            const GenerationParams(),
            parts: <LlamaContentPart>[
              LlamaAudioContent(bytes: Uint8List.fromList(<int>[1, 2, 3])),
            ],
          )
          .toList();

      expect(chunks, isNotEmpty);
      expect(sawAudioParts, isTrue);
      expect(sawAudioBytes, isTrue);
    });
  });
}
