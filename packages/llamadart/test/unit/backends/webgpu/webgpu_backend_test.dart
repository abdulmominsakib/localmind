@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/webgpu/interop.dart';
import 'package:llamadart/src/backends/web/web_backend.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_backend.dart';
import 'package:test/test.dart';
import 'package:web/web.dart'
    show
        AbortSignal,
        Blob,
        BlobPropertyBag,
        DOMException,
        Event,
        Response,
        URL,
        document,
        window;

import '../../../support/fake_navigator_gpu.dart';
import '../../../support/fake_webgpu_decision_bridge.dart';
import '../../../support/fake_webgpu_feature_bridge.dart';

@JS('Promise.reject')
external JSPromise<JSAny?> _rejectPromise(JSAny? reason);

@JS('Error')
external JSObject _jsError(String message);

@JS('RangeError')
external JSObject _jsRangeError(String message);

@JS('TypeError')
external JSObject _jsTypeError(String message);

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
    late List<int?> requestedThreadCounts;
    late List<int?> requestedGpuLayerCounts;
    late List<bool?> requestedForceRemoteFetchBackends;
    late List<int?> requestedRemoteFetchChunkBytes;
    late Map<String, String> bridgeRuntimeHints;
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
    String? lastGrammar;
    JSObject? lastCompletionOptions;
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

      final nThreads = config.getProperty('nThreads'.toJS);
      requestedThreadCounts.add(
        nThreads.isA<JSNumber>() ? (nThreads as JSNumber).toDartInt : null,
      );

      final nGpuLayers = config.getProperty('nGpuLayers'.toJS);
      final nGpuLayersValue = nGpuLayers.isA<JSNumber>()
          ? (nGpuLayers as JSNumber).toDartInt
          : null;
      if (nGpuLayersValue != null) {
        lastRequestedGpuLayers = nGpuLayersValue;
      }
      requestedGpuLayerCounts.add(nGpuLayersValue);

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
        requestedForceRemoteFetchBackends.add(
          lastRequestedForceRemoteFetchBackend,
        );
      } else {
        requestedForceRemoteFetchBackends.add(null);
      }

      final remoteFetchChunkBytes = config.getProperty(
        'remoteFetchChunkBytes'.toJS,
      );
      requestedRemoteFetchChunkBytes.add(
        remoteFetchChunkBytes.isA<JSNumber>()
            ? (remoteFetchChunkBytes as JSNumber).toDartInt
            : null,
      );

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
      requestedThreadCounts = <int?>[];
      requestedGpuLayerCounts = <int?>[];
      requestedForceRemoteFetchBackends = <bool?>[];
      requestedRemoteFetchChunkBytes = <int?>[];
      bridgeRuntimeHints = <String, String>{};
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
      lastGrammar = null;
      lastCompletionOptions = null;
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
          lastCompletionOptions = opts;
          final grammarRaw = opts.getProperty('grammar'.toJS);
          lastGrammar = grammarRaw.isA<JSString>()
              ? (grammarRaw as JSString).toDart
              : null;

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
          for (final entry in bridgeRuntimeHints.entries) {
            meta.setProperty(entry.key.toJS, entry.value.toJS);
          }
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

    test('names the subtype mismatch before the embedding-engine '
        'rejection', () async {
      await expectLater(
        backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const LiteRtLmModelParams(embeddingEngine: true),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'message',
            contains('Use LlamaCppModelParams.'),
          ),
        ),
      );
    });

    test('rejects LiteRT-LM embedding mode before any bridge call', () async {
      await expectLater(
        backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(liteRtLmEmbeddingEngine: true),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'runtime',
            contains('llama.cpp'),
          ),
        ),
      );
    });

    test(
      'rejects options the Web runtime ignores before any bridge call',
      () async {
        for (final (params, field) in [
          (const ModelParams(useMmap: false), 'useMmap=false'),
          (const ModelParams(useMlock: true), 'useMlock'),
          (const ModelParams(liteRtLmCacheDir: '/cache'), 'liteRtLmCacheDir'),
        ]) {
          await expectLater(
            backend.modelLoadFromUrl('https://example.com/model.gguf', params),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (e) => e.message,
                'message',
                contains(
                  'llama.cpp on the Web does not apply these ModelParams: '
                  '$field.',
                ),
              ),
            ),
          );
        }
      },
    );

    test('reports the llama.cpp runtime', () {
      expect(WebGpuLlamaBackend().runtime, LlamaRuntime.llamaCpp);
    });

    test(
      'drives Qwen3-TTS only and refuses other models before loading',
      () async {
        for (final model in BackendTextToSpeechModel.values) {
          final reason = await backend.textToSpeechModelUnsupportedReason(
            model,
          );
          if (model == BackendTextToSpeechModel.qwen3Tts) {
            expect(reason, isNull);
          } else {
            expect(
              reason,
              contains('Web text-to-speech drives Qwen3-TTS only'),
            );
          }
        }

        var bridgesCreated = 0;
        await expectLater(
          TextToSpeechEngine.load(
            TextToSpeechModel(
              ModelSource.url(Uri.parse('https://example.com/soprano.gguf')),
              projector: ModelSource.url(
                Uri.parse('https://example.com/mmproj.gguf'),
              ),
              adapter: const SopranoTtsAdapter(),
            ),
            backend: WebGpuLlamaBackend(
              bridgeFactory: ([config]) {
                bridgesCreated++;
                return bridge as LlamaWebGpuBridge;
              },
            ),
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              contains('Qwen3-TTS only'),
            ),
          ),
        );
        expect(bridgesCreated, 0);
      },
    );

    test('rejects bridge calls before a model loads', () async {
      await expectLater(
        backend.getContextSize(1),
        throwsA(
          isA<LlamaStateException>().having(
            (e) => e.message,
            'message',
            contains('LlamaEngine.load or setModel'),
          ),
        ),
      );
    });

    test('loads the bridge module named by bridgeScriptUrl', () async {
      const stubGlobal = '__llamadartTestBridgeInstance';
      globalContext.setProperty(stubGlobal.toJS, bridge);
      addTearDown(() => globalContext.delete(stubGlobal.toJS));
      // The constructor returns the shared fake so the loaded module drives
      // the same bridge as the factory-based tests.
      final moduleUrl = URL.createObjectURL(
        Blob(
          <JSAny>[
            'export class LlamaWebGpuBridge { '
                    'constructor() { return globalThis.$stubGlobal; } }'
                .toJS,
          ].toJS,
          BlobPropertyBag(type: 'text/javascript'),
        ),
      );
      addTearDown(() => URL.revokeObjectURL(moduleUrl));
      final scriptBackend = WebGpuLlamaBackend(bridgeScriptUrl: moduleUrl);
      addTearDown(scriptBackend.dispose);

      final modelHandle = await scriptBackend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(contextSize: 4096),
      );

      expect(modelHandle, 1);
      expect(await scriptBackend.getBackendName(), 'WebGPU (Mock)');
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

    test('applyChatTemplate rejects custom templates the bridge would '
        'ignore', () async {
      const messages = [
        {'role': 'user', 'content': 'hi'},
      ];
      final unsupported = throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          allOf(contains('WebGPU'), contains('LlamaEngine.chatTemplate')),
        ),
      );

      final handle = await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );
      expect(await backend.applyChatTemplate(handle, messages), 'templated');
      await expectLater(
        backend.applyChatTemplate(handle, messages, customTemplate: 'X'),
        unsupported,
      );
      await expectLater(
        backend.applyChatTemplate(handle, messages, customTemplate: ''),
        unsupported,
      );
      await backend.modelFree(handle);

      final overridden = await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(chatTemplate: '{{ messages[0]["content"] }}'),
      );
      await expectLater(
        backend.applyChatTemplate(overridden, messages),
        unsupported,
      );
      await backend.modelFree(overridden);

      final emptyOverride = await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(chatTemplate: ''),
      );
      expect(
        await backend.applyChatTemplate(emptyOverride, messages),
        'templated',
      );
      await backend.modelFree(emptyOverride);

      final reloaded = await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );
      expect(await backend.applyChatTemplate(reloaded, messages), 'templated');
    });

    test('forwards bridge load progress to onProgress', () async {
      bridge.setProperty(
        'loadModelFromUrl'.toJS,
        ((String url, JSObject? config) {
          final callback = config?.getProperty('progressCallback'.toJS);
          if (callback.isA<JSFunction>()) {
            final fraction = JSObject()
              ..setProperty('loaded'.toJS, 25.toJS)
              ..setProperty('total'.toJS, 100.toJS);
            (callback as JSFunction).callAsFunction(null, fraction);
            callback.callAsFunction(null, 0.75.toJS);
          }
          return Future<void>.value().toJS;
        }).toJS,
      );
      final progress = <double>[];

      await backend.modelLoadFromUrl(
        'https://example.com/progress-model.gguf',
        const ModelParams(),
        onProgress: progress.add,
      );

      expect(progress, <double>[0.25, 0.75]);
    });

    test(
      'forwards object progress only for numeric fields with a positive total',
      () async {
        bridge.setProperty(
          'loadModelFromUrl'.toJS,
          ((String url, JSObject? config) {
            final callback = config?.getProperty('progressCallback'.toJS);
            if (callback.isA<JSFunction>()) {
              for (final report in <JSObject>[
                JSObject()..setProperty('total'.toJS, 100.toJS),
                JSObject()..setProperty('loaded'.toJS, 25.toJS),
                JSObject()
                  ..setProperty('loaded'.toJS, 0.toJS)
                  ..setProperty('total'.toJS, 0.toJS),
                JSObject()
                  ..setProperty('loaded'.toJS, 1.toJS)
                  ..setProperty('total'.toJS, 1.toJS),
              ]) {
                (callback as JSFunction).callAsFunction(null, report);
              }
            }
            return Future<void>.value().toJS;
          }).toJS,
        );
        final progress = <double>[];

        await backend.modelLoadFromUrl(
          'https://example.com/progress-model.gguf',
          const ModelParams(),
          onProgress: progress.add,
        );

        expect(progress, <double>[1.0]);
      },
    );

    test('requires explicit prompt speech runtime capability', () async {
      expect(backend.supportsPromptSpeechToText, isFalse);
      expect(backend.promptSpeechToTextUnsupportedReason, contains('v0.1.30'));

      final supportedBackend = WebGpuLlamaBackend(
        promptSpeechToTextSupported: true,
      );
      expect(supportedBackend.supportsPromptSpeechToText, isTrue);
      expect(supportedBackend.promptSpeechToTextUnsupportedReason, isNull);
      await supportedBackend.dispose();
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

    test('the size hint ceiling that auto-enables mem64 is 2 GiB', () async {
      const ceiling = 2 * 1024 * 1024 * 1024;

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(modelBytesHint: ceiling - 1),
      );
      expect(capturedPreferMemory64(), isNull);

      await backend.dispose();
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(modelBytesHint: ceiling),
      );
      expect(capturedPreferMemory64(), isTrue);
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

    test(
      'omits unset batch threads and floors sequence slots at one',
      () async {
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(maxParallelSequences: 0),
        );

        expect(lastRequestedThreadsBatch, isNull);
        expect(lastRequestedSeqMax, 1);
      },
    );

    test('forwards a single batch thread and sequence slot', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(numberOfThreadsBatch: 1),
      );

      expect(lastRequestedThreadsBatch, 1);
      expect(lastRequestedSeqMax, 1);
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
        throwsA(isA<LlamaArgumentException>()),
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

    for (final gpuLayers in const [-1, -2]) {
      test('sends every layer for gpuLayers $gpuLayers', () async {
        await backend.modelLoadFromUrl(
          'https://example.com/llama-3.2-3b.gguf',
          ModelParams(contextSize: 4096, gpuLayers: gpuLayers),
        );

        expect(lastRequestedGpuLayers, ModelParams.maxGpuLayers);
      });
    }

    test('caps negative gpuLayers for qwen3.5-0.8b', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/Qwen_Qwen3.5-0.8B-Q4_K_M.gguf',
        const ModelParams(contextSize: 4096, gpuLayers: -1),
      );

      expect(lastRequestedGpuLayers, 2);
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

    for (final (label, params) in const [
      ('CPU preference', ModelParams(preferredBackend: GpuBackend.cpu)),
      ('zero GPU layers', ModelParams(gpuLayers: 0)),
      (
        'memory64 CPU',
        ModelParams(preferredBackend: GpuBackend.cpu, preferMemory64: true),
      ),
    ]) {
      test('keeps long encoder batches with $label', () async {
        // The URL deliberately gives no architecture hint. The bridge creates
        // the context before Dart can inspect model metadata.
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          params,
        );

        expect(requestedContextSizes, <int>[4096]);
        expect(lastRequestedGpuLayers, 0);
        expect(lastRequestedBatchSize, 4096);
        expect(lastRequestedMicroBatchSize, 4096);
      });
    }

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

    for (final (label, params) in const [
      ('the CPU backend', ModelParams(preferredBackend: GpuBackend.cpu)),
      ('zero GPU layers', ModelParams(gpuLayers: 0)),
    ]) {
      test('uses native decoder batch defaults for $label', () async {
        await backend.modelLoadFromUrl(
          'https://example.com/Qwen3.5-0.8B-Q4_K_M.gguf',
          params,
        );

        expect(requestedContextSizes, <int>[4096]);
        expect(lastRequestedGpuLayers, 0);
        expect(lastRequestedBatchSize, 2048);
        expect(lastRequestedMicroBatchSize, 512);
      });
    }

    for (final (batch, microBatch, expected) in const [
      (2048, 1024, (2048, 1024)),
      (0, 1024, (2048, 1024)),
      (4096, 0, (4096, 512)),
    ]) {
      test('keeps explicit CPU batches $batch / $microBatch', () async {
        await backend.modelLoadFromUrl(
          'https://example.com/Qwen3.5-0.8B-Q4_K_M.gguf',
          ModelParams(
            preferredBackend: GpuBackend.cpu,
            batchSize: batch,
            microBatchSize: microBatch,
          ),
        );

        expect(lastRequestedBatchSize, expected.$1);
        expect(lastRequestedMicroBatchSize, expected.$2);
      });
    }

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
        expect(requestedGpuLayerCounts, <int?>[99, 0, 99]);
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

    JSPromise<JSAny?> rejectLoadWith(String message) {
      final error = JSObject();
      error.setProperty('message'.toJS, message.toJS);
      return _rejectPromise(error);
    }

    void failLoads({required String message, required int firstAttempts}) {
      var loadCallCount = 0;
      bridge.setProperty(
        'loadModelFromUrl'.toJS,
        ((String url, JSObject? config) {
          loadCallCount += 1;
          recordLoadConfig(config);
          if (loadCallCount <= firstAttempts) {
            return rejectLoadWith(message);
          }
          return Future<void>.value().toJS;
        }).toJS,
      );
    }

    void failLoadsInOrder(List<(String, String, String)> failures) {
      bridge.setProperty(
        'loadModelFromUrl'.toJS,
        ((String url, JSObject? config) {
          recordLoadConfig(config);
          if (failures.isEmpty) {
            return Future<void>.value().toJS;
          }
          final (coreVariant, runtimeNotes, message) = failures.removeAt(0);
          bridgeRuntimeHints['llamadart.webgpu.core_variant'] = coreVariant;
          bridgeRuntimeHints['llamadart.webgpu.runtime_notes'] = runtimeNotes;
          return rejectLoadWith(message);
        }).toJS,
      );
    }

    List<String> captureConsole(String method) {
      final messages = <String>[];
      final consoleObject =
          globalContext.getProperty('console'.toJS) as JSObject;
      final original = consoleObject.getProperty(method.toJS) as JSFunction;
      consoleObject.setProperty(
        method.toJS,
        ((JSAny? message) {
          messages.add(message?.toString() ?? '');
          original.callAsFunction(consoleObject, message);
        }).toJS,
      );
      addTearDown(() {
        consoleObject.setProperty(method.toJS, original);
      });
      return messages;
    }

    List<String> captureConsoleWarnings() => captureConsole('warn');

    test(
      'advances the fallback ladder with descending attempt limits',
      () async {
        final warnings = captureConsoleWarnings();
        bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm64';
        failLoads(message: 'array buffer allocation failed', firstAttempts: 4);

        await backend.modelLoadFromUrl(
          'https://example.com/ladder-model.gguf',
          const ModelParams(
            contextSize: 4096,
            gpuLayers: 99,
            numberOfThreads: 8,
            preferMemory64: true,
          ),
        );

        expect(requestedContextSizes, <int>[4096, 4096, 2048, 2048, 1024]);
        expect(requestedGpuLayerCounts, <int?>[99, 0, 99, 0, 99]);
        expect(requestedThreadCounts, <int?>[8, 4, 4, 2, 2]);
        expect(
          warnings
              .where((message) => message.contains('reduced settings'))
              .toList(),
          <String>[
            'WebGpuLlamaBackend: retrying web model load with reduced settings '
                '(nCtx=4096, nGpuLayers=0, nThreads=4)',
            'WebGpuLlamaBackend: retrying web model load with reduced settings '
                '(nCtx=2048, nGpuLayers=99, nThreads=4)',
            'WebGpuLlamaBackend: retrying web model load with reduced settings '
                '(nCtx=2048, nGpuLayers=0, nThreads=2)',
            'WebGpuLlamaBackend: retrying web model load with reduced settings '
                '(nCtx=1024, nGpuLayers=99, nThreads=2)',
          ],
        );
        expect(
          warnings
              .where((message) => message.contains('loaded after fallback'))
              .toList(),
          <String>[
            'WebGpuLlamaBackend: model loaded after fallback '
                '(nCtx=1024, nGpuLayers=99, nThreads=2)',
          ],
        );
      },
    );

    test('falls back to the CPU for negative gpuLayers', () async {
      bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm64';
      failLoads(message: 'array buffer allocation failed', firstAttempts: 1);

      await backend.modelLoadFromUrl(
        'https://example.com/negative-layers-model.gguf',
        const ModelParams(contextSize: 4096, gpuLayers: -1),
      );

      expect(requestedGpuLayerCounts, <int?>[ModelParams.maxGpuLayers, 0]);
    });

    test('leaves the first rung thread count unset by default', () async {
      bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm64';
      failLoads(message: 'array buffer allocation failed', firstAttempts: 1);

      await backend.modelLoadFromUrl(
        'https://example.com/default-threads-model.gguf',
        const ModelParams(contextSize: 4096, gpuLayers: 99),
      );

      expect(requestedThreadCounts, <int?>[null, 4]);
    });

    test('keeps a single requested thread after an advance', () async {
      final warnings = captureConsoleWarnings();
      bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm64';
      failLoads(message: 'array buffer allocation failed', firstAttempts: 1);

      await backend.modelLoadFromUrl(
        'https://example.com/single-thread-model.gguf',
        const ModelParams(contextSize: 4096, gpuLayers: 99, numberOfThreads: 1),
      );

      expect(requestedThreadCounts, <int?>[1, 1]);
      expect(
        warnings
            .where((message) => message.contains('reduced settings'))
            .toList(),
        <String>[
          'WebGpuLlamaBackend: retrying web model load with reduced settings '
              '(nCtx=4096, nGpuLayers=0, nThreads=1)',
        ],
      );
    });

    test('logs the Qwen3.5-0.8B layer cap at info level', () async {
      final logs = captureConsole('log');

      await backend.modelLoadFromUrl(
        'https://example.com/Qwen_Qwen3.5-0.8B-Q4_K_M.gguf',
        const ModelParams(gpuLayers: 99),
      );

      expect(
        logs.where((message) => message.contains('Capping')).toList(),
        <String>[
          'WebGpuLlamaBackend: Capping Qwen3.5-0.8B WebGPU layers from 99 to 2 '
              'for stable browser output.',
        ],
      );
    });

    test('logs no layer cap for other models', () async {
      final logs = captureConsole('log');

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(gpuLayers: 99),
      );

      expect(logs.where((message) => message.contains('Capping')), isEmpty);
    });

    test('logs no Qwen layer cap when Safari forces the CPU', () async {
      final logs = captureConsole('log');
      globalContext.setProperty(
        '__llamadartBridgeUserAgent'.toJS,
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 '
                '(KHTML, like Gecko) Version/17.5 Safari/605.1.15'
            .toJS,
      );

      await backend.modelLoadFromUrl(
        'https://example.com/Qwen_Qwen3.5-0.8B-Q4_K_M.gguf',
        const ModelParams(gpuLayers: 99),
      );

      expect(lastRequestedGpuLayers, 0);
      expect(logs.where((message) => message.contains('Capping')), isEmpty);
    });

    test('logs no fallback warning when the first rung loads', () async {
      final warnings = captureConsoleWarnings();

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      expect(
        warnings.where((message) => message.contains('after fallback')),
        isEmpty,
      );
    });

    test('caps the first rung context at 32768', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/long-context-model.gguf',
        const ModelParams(contextSize: 131072),
      );

      expect(requestedContextSizes, <int>[32768]);
    });

    group('ComputeDevice', () {
      const url = 'https://example.com/model.gguf';
      Matcher unsupported(String text) => throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'message',
          allOf(contains('ComputeDevice.'), contains(text)),
        ),
      );

      test('gpu needs a WebGPU adapter before the bridge loads', () async {
        addTearDown(fakeNavigatorGpu(FakeWebGpu.noAdapter));

        await expectLater(
          backend.modelLoadFromUrl(
            url,
            const ModelParams(device: ComputeDevice.gpu),
          ),
          unsupported('no WebGPU adapter'),
        );
        expect(requestedGpuLayerCounts, isEmpty);
      });

      for (final mainGpu in [-1, -2]) {
        for (final gpuState in ['active', 'no adapter', 'inactive runtime']) {
          test('engine routes gpu with negative mainGpu $mainGpu to WebGPU '
              '($gpuState)', () async {
            addTearDown(
              fakeNavigatorGpu(
                gpuState == 'no adapter'
                    ? FakeWebGpu.noAdapter
                    : FakeWebGpu.adapter,
              ),
            );
            runtimeGpuActive = gpuState != 'inactive runtime';
            final engine = LlamaEngine(
              WebAutoBackend(webGpuFactory: () => backend),
            );
            addTearDown(engine.dispose);
            final load = engine.setModel(
              LlamaModel(ModelSource.parse(url)),
              params: ModelParams(
                device: ComputeDevice.gpu,
                splitMode: ModelSplitMode.none,
                mainGpu: mainGpu,
              ),
            );

            if (gpuState == 'no adapter') {
              await expectLater(load, unsupported('no WebGPU adapter'));
              expect(requestedGpuLayerCounts, isEmpty);
              expect(engine.isReady, isFalse);
            } else {
              if (gpuState == 'active') {
                await load;
                expect(engine.isReady, isTrue);
              } else {
                await expectLater(load, unsupported('without GPU layers'));
                expect(engine.isReady, isFalse);
              }
              expect(requestedGpuLayerCounts, [ModelParams.maxGpuLayers]);
              expect(lastRequestedSplitMode, ModelSplitMode.none.llamaCppValue);
              expect(lastRequestedMainGpu, mainGpu);
            }
          });
        }
      }

      test('gpu never retries on a CPU rung', () async {
        addTearDown(fakeNavigatorGpu(FakeWebGpu.adapter));
        failLoads(message: 'memory access out of bounds', firstAttempts: 1);

        await backend.modelLoadFromUrl(
          url,
          const ModelParams(
            contextSize: 4096,
            gpuLayers: 1,
            device: ComputeDevice.gpu,
          ),
        );

        expect(requestedGpuLayerCounts, <int?>[1, 1]);
        expect(requestedContextSizes, <int>[4096, 2048]);
      });

      test('gpu throws and unloads when the runtime runs without GPU '
          'layers', () async {
        addTearDown(fakeNavigatorGpu(FakeWebGpu.adapter));
        runtimeGpuActive = false;

        await expectLater(
          backend.modelLoadFromUrl(
            url,
            const ModelParams(device: ComputeDevice.gpu),
          ),
          unsupported('without GPU layers'),
        );
        expect(requestedGpuLayerCounts, <int?>[ModelParams.maxGpuLayers]);
        expect(backend.isReady, isFalse);
      });

      test('auto keeps loading without WebGPU', () async {
        addTearDown(fakeNavigatorGpu(FakeWebGpu.missing));
        runtimeGpuActive = false;

        await backend.modelLoadFromUrl(url, const ModelParams());

        expect(backend.isReady, isTrue);
      });

      test('cpu sends no GPU layers', () async {
        await backend.modelLoadFromUrl(
          url,
          const ModelParams(device: ComputeDevice.cpu),
        );

        expect(lastRequestedGpuLayers, 0);
      });

      test('gpu on Safari with legacy bridge assets throws', () async {
        addTearDown(fakeNavigatorGpu(FakeWebGpu.adapter));
        globalContext.setProperty(
          '__llamadartBridgeUserAgent'.toJS,
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 '
                  '(KHTML, like Gecko) Version/17.5 Safari/605.1.15'
              .toJS,
        );

        await expectLater(
          backend.modelLoadFromUrl(
            url,
            const ModelParams(device: ComputeDevice.gpu),
          ),
          unsupported('Safari'),
        );
        expect(requestedGpuLayerCounts, isEmpty);
      });

      test('npu throws', () async {
        await expectLater(
          backend.modelLoadFromUrl(
            url,
            const ModelParams(device: ComputeDevice.npu),
          ),
          unsupported('llama.cpp on the Web'),
        );
        expect(requestedGpuLayerCounts, isEmpty);
      });
    });

    test('falls back to a CPU rung from a single GPU layer', () async {
      bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm64';
      bridgeRuntimeHints['llamadart.webgpu.runtime_notes'] =
          'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
          'threads_capped_pool:4;thread_pool_size:4;threads_batch:4;'
          'model_network_stream;model_response_stream;model_load_ccall_failed';
      failLoads(message: 'memory access out of bounds', firstAttempts: 1);

      await backend.modelLoadFromUrl(
        'https://example.com/one-layer-model.gguf',
        const ModelParams(contextSize: 4096, gpuLayers: 1),
      );

      expect(requestedContextSizes, <int>[4096, 4096]);
      expect(requestedGpuLayerCounts, <int?>[1, 0]);
    });

    test(
      'restarts the ladder on wasm32 after a wasm64 BigInt failure',
      () async {
        final warnings = captureConsoleWarnings();
        bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm64';
        failLoads(
          message: 'Cannot convert a BigInt value to a number',
          firstAttempts: 1,
        );

        await backend.modelLoadFromUrl(
          'https://example.com/bigint-model.gguf',
          const ModelParams(
            contextSize: 4096,
            gpuLayers: 99,
            numberOfThreads: 8,
            preferMemory64: true,
          ),
        );

        expect(requestedContextSizes, <int>[4096, 4096]);
        expect(requestedGpuLayerCounts, <int?>[99, 99]);
        expect(requestedThreadCounts, <int?>[8, 8]);
        expect(requestedForceRemoteFetchBackends, <bool?>[null, false]);
        expect(capturedPreferMemory64(), isFalse);
        expect(
          warnings
              .where((message) => message.contains('retrying with wasm32'))
              .toList(),
          <String>[
            'WebGpuLlamaBackend: wasm64 BigInt interop failure detected; '
                'retrying with wasm32 core.',
          ],
        );
      },
    );

    test('restarts from the first rung after the ladder advanced', () async {
      bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm64';
      final errors = <String>[
        'array buffer allocation failed',
        'Cannot convert a BigInt value to a number',
      ];
      bridge.setProperty(
        'loadModelFromUrl'.toJS,
        ((String url, JSObject? config) {
          recordLoadConfig(config);
          if (errors.isEmpty) {
            return Future<void>.value().toJS;
          }
          return rejectLoadWith(errors.removeAt(0));
        }).toJS,
      );

      await backend.modelLoadFromUrl(
        'https://example.com/restart-rung-model.gguf',
        const ModelParams(
          contextSize: 4096,
          gpuLayers: 99,
          numberOfThreads: 8,
          preferMemory64: true,
        ),
      );

      expect(requestedContextSizes, <int>[4096, 4096, 4096]);
      expect(requestedGpuLayerCounts, <int?>[99, 0, 99]);
      expect(requestedThreadCounts, <int?>[8, 4, 8]);
    });

    test('resets both overrides at the start of every load', () async {
      bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm64';
      failLoads(
        message: 'Cannot convert a BigInt value to a number',
        firstAttempts: 1,
      );

      await backend.modelLoadFromUrl(
        'https://example.com/first-model.gguf',
        const ModelParams(preferMemory64: true),
      );
      expect(requestedForceRemoteFetchBackends, <bool?>[null, false]);
      expect(capturedPreferMemory64(), isFalse);

      await backend.dispose();
      await backend.modelLoadFromUrl(
        'https://example.com/second-model.gguf',
        const ModelParams(),
      );

      expect(requestedForceRemoteFetchBackends, <bool?>[null, false, null]);
      expect(capturedPreferMemory64(), isNull);
    });

    test('restarts without the remote fetch backend after an abort', () async {
      bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm32';
      bridgeRuntimeHints['llamadart.webgpu.runtime_notes'] =
          'model_fetch_backend_attempt;model_fetch_backend_abort';
      failLoads(message: 'bridge model load failed', firstAttempts: 1);

      await backend.modelLoadFromUrl(
        'https://example.com/fetch-abort-model.gguf',
        const ModelParams(contextSize: 4096, gpuLayers: 99, numberOfThreads: 8),
      );

      expect(requestedContextSizes, <int>[4096, 4096]);
      expect(requestedGpuLayerCounts, <int?>[99, 99]);
      expect(requestedThreadCounts, <int?>[8, 8]);
      expect(requestedForceRemoteFetchBackends, <bool?>[null, false]);
      expect(capturedPreferMemory64(), isTrue);
    });

    test('caps forced remote fetch chunk halving at ten restarts', () async {
      globalContext.setProperty(
        '__llamadartBridgeForceRemoteFetchBackend'.toJS,
        true.toJS,
      );
      globalContext.setProperty(
        '__llamadartBridgeRemoteFetchChunkBytes'.toJS,
        (16 * 1024 * 1024).toJS,
      );
      bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm32';
      bridgeRuntimeHints['llamadart.webgpu.runtime_notes'] =
          'model_fetch_backend_attempt;model_fetch_backend_abort';
      failLoads(message: 'bridge model load failed', firstAttempts: 11);

      await expectLater(
        backend.modelLoadFromUrl(
          'https://example.com/forced-fetch-model.gguf',
          const ModelParams(
            contextSize: 4096,
            gpuLayers: 99,
            numberOfThreads: 8,
          ),
        ),
        throwsA(anything),
      );

      expect(requestedContextSizes, List<int>.filled(11, 4096));
      expect(requestedForceRemoteFetchBackends, List<bool?>.filled(11, true));
      expect(requestedRemoteFetchChunkBytes, <int?>[
        16 * 1024 * 1024,
        8 * 1024 * 1024,
        4 * 1024 * 1024,
        2 * 1024 * 1024,
        1024 * 1024,
        512 * 1024,
        256 * 1024,
        128 * 1024,
        64 * 1024,
        32 * 1024,
        16 * 1024,
      ]);
    });

    test('gives up with the memory limit error after the last rung', () async {
      bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm64';
      failLoads(message: 'Array buffer allocation failed', firstAttempts: 2);

      await expectLater(
        backend.modelLoadFromUrl(
          'https://example.com/exhausted-model.gguf',
          const ModelParams(contextSize: 512, gpuLayers: 99),
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            startsWith('Model loading exceeded browser memory limits.'),
          ),
        ),
      );

      expect(requestedContextSizes, <int>[512, 512]);
      expect(requestedGpuLayerCounts, <int?>[99, 0]);
    });

    test('stops forced remote fetch chunk halving at the minimum', () async {
      globalContext.setProperty(
        '__llamadartBridgeForceRemoteFetchBackend'.toJS,
        true.toJS,
      );
      globalContext.setProperty(
        '__llamadartBridgeRemoteFetchChunkBytes'.toJS,
        (20 * 1024).toJS,
      );
      bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm32';
      bridgeRuntimeHints['llamadart.webgpu.runtime_notes'] =
          'model_fetch_backend_attempt;model_fetch_backend_abort';
      failLoads(message: 'bridge model load failed', firstAttempts: 4);

      await expectLater(
        backend.modelLoadFromUrl(
          'https://example.com/min-chunk-model.gguf',
          const ModelParams(
            contextSize: 4096,
            gpuLayers: 99,
            numberOfThreads: 8,
          ),
        ),
        throwsA(anything),
      );

      expect(requestedContextSizes, List<int>.filled(4, 4096));
      expect(requestedForceRemoteFetchBackends, List<bool?>.filled(4, true));
      expect(requestedRemoteFetchChunkBytes, <int?>[
        20 * 1024,
        10 * 1024,
        5 * 1024,
        4 * 1024,
      ]);
    });

    for (final message in const [
      'thread constructor failed',
      'bridge model load failed: error 138',
    ]) {
      for (final forcedFetchAbort in const [false, true]) {
        test('maps "$message" to the cross-origin isolation error '
            '(forced fetch abort: $forcedFetchAbort)', () async {
          if (forcedFetchAbort) {
            globalContext.setProperty(
              '__llamadartBridgeForceRemoteFetchBackend'.toJS,
              true.toJS,
            );
            bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm32';
            bridgeRuntimeHints['llamadart.webgpu.runtime_notes'] =
                'model_fetch_backend_attempt;model_fetch_backend_abort';
          }
          failLoads(message: message, firstAttempts: 99);

          await expectLater(
            backend.modelLoadFromUrl(
              'https://example.com/thread-constructor-model.gguf',
              const ModelParams(contextSize: 4096, gpuLayers: 99),
            ),
            throwsA(
              isA<UnsupportedError>().having(
                (error) => error.message,
                'message',
                startsWith(
                  'Browser runtime blocked worker thread creation required '
                  'by the fetch-backed web model loader.',
                ),
              ),
            ),
          );
          expect(requestedContextSizes, <int>[4096]);
        });
      }
    }

    test('treats "error 1380" as an ordinary fetch abort', () async {
      globalContext.setProperty(
        '__llamadartBridgeForceRemoteFetchBackend'.toJS,
        true.toJS,
      );
      globalContext.setProperty(
        '__llamadartBridgeRemoteFetchChunkBytes'.toJS,
        (16 * 1024 * 1024).toJS,
      );
      bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm32';
      bridgeRuntimeHints['llamadart.webgpu.runtime_notes'] =
          'model_fetch_backend_attempt;model_fetch_backend_abort';
      failLoads(
        message: 'bridge model load failed: error 1380',
        firstAttempts: 99,
      );

      await expectLater(
        backend.modelLoadFromUrl(
          'https://example.com/error-1380-model.gguf',
          const ModelParams(contextSize: 4096, gpuLayers: 99),
        ),
        throwsA(isNot(isA<UnsupportedError>())),
      );
      expect(requestedRemoteFetchChunkBytes, hasLength(11));
    });

    test(
      'surfaces the memory limit error after an opted-in wasm64 staging failure',
      () async {
        globalContext.setProperty(
          '__llamadartBridgeAllowAutoRemoteFetchBackend'.toJS,
          true.toJS,
        );
        bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm64';
        bridgeRuntimeHints['llamadart.webgpu.runtime_notes'] =
            'model_fs_write_arraybuffer_oom';
        failLoads(message: 'array buffer allocation failed', firstAttempts: 2);

        await expectLater(
          backend.modelLoadFromUrl(
            'https://example.com/opted-in-staging-model.gguf',
            const ModelParams(
              contextSize: 4096,
              gpuLayers: 99,
              preferMemory64: true,
            ),
          ),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'message',
              startsWith('Model loading exceeded browser memory limits.'),
            ),
          ),
        );

        expect(requestedForceRemoteFetchBackends, <bool?>[null, true]);
        expect(requestedRemoteFetchChunkBytes, <int?>[
          4 * 1024 * 1024,
          128 * 1024,
        ]);
      },
    );

    test(
      'warns before giving up on wasm64 staging without the opt-in',
      () async {
        final warnings = captureConsoleWarnings();
        bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm64';
        bridgeRuntimeHints['llamadart.webgpu.runtime_notes'] =
            'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
            'threads_capped_pool:4;thread_pool_size:4;threads_batch:4;'
            'model_network_stream;model_response_stream;'
            'model_fs_write_loaded:0;model_fs_write_arraybuffer_oom';
        failLoads(message: 'Array buffer allocation failed', firstAttempts: 1);

        await expectLater(
          backend.modelLoadFromUrl(
            'https://example.com/staging-model.gguf',
            const ModelParams(contextSize: 4096, gpuLayers: 99),
          ),
          throwsA(isA<UnsupportedError>()),
        );

        expect(
          warnings,
          contains(
            'WebGpuLlamaBackend: wasm64 model staging failed; fetch-backed '
            'recovery requires explicit opt-in, so no unsafe remote-fetch retry '
            'will be attempted.',
          ),
        );
      },
    );

    test(
      'reports staging failures on pages without cross-origin isolation',
      () async {
        bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm64';
        bridgeRuntimeHints['llamadart.webgpu.runtime_notes'] =
            'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
            'thread_pool_size:4;threads_capped_no_coi;threads_batch:1;'
            'model_network_stream;model_response_stream;'
            'model_fs_write_loaded:0;model_fs_write_arraybuffer_oom';
        failLoads(message: 'Array buffer allocation failed', firstAttempts: 1);

        await expectLater(
          backend.modelLoadFromUrl(
            'https://example.com/no-coi-model.gguf',
            const ModelParams(contextSize: 4096, gpuLayers: 99),
          ),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'message',
              startsWith(
                'Web model staging failed before the GGUF could be loaded '
                'safely.',
              ),
            ),
          ),
        );
      },
    );

    group('on a page without cross-origin isolation', () {
      const noCoiNotes =
          'core_wasm32_active;core_pthreads:1;thread_pool_size:4;'
          'threads_capped_no_coi;threads_batch:1;model_network_stream';

      test('reports an ordinary load failure as a model error', () async {
        bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm32';
        bridgeRuntimeHints['llamadart.webgpu.runtime_notes'] = noCoiNotes;
        failLoads(
          message: 'Failed to fetch model shard: 404',
          firstAttempts: 99,
        );

        await expectLater(
          backend.modelLoadFromUrl(
            'https://example.com/missing.gguf',
            const ModelParams(contextSize: 4096, gpuLayers: 99),
          ),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => '${error.details}',
              'details',
              contains('Failed to fetch model shard: 404'),
            ),
          ),
        );
      });

      test('still maps a thread constructor failure to the isolation '
          'error', () async {
        bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm32';
        bridgeRuntimeHints['llamadart.webgpu.runtime_notes'] =
            '$noCoiNotes;thread_constructor_failed';
        failLoads(message: 'Aborted()', firstAttempts: 99);

        await expectLater(
          backend.modelLoadFromUrl(
            'https://example.com/thread-model.gguf',
            const ModelParams(contextSize: 4096, gpuLayers: 99),
          ),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'message',
              startsWith(
                'Browser runtime blocked worker thread creation required '
                'by the fetch-backed web model loader.',
              ),
            ),
          ),
        );
      });
    });

    test('logs the runtime hints before disposing the failed bridge', () async {
      final events = captureConsoleWarnings();
      bridge.setProperty(
        'dispose'.toJS,
        (() {
          events.add('<dispose>');
          return Future<void>.value().toJS;
        }).toJS,
      );
      bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm64';
      bridgeRuntimeHints['llamadart.webgpu.runtime_notes'] =
          'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
          'threads_capped_pool:4;thread_pool_size:4;threads_batch:4;'
          'model_network_stream;model_response_stream;model_load_ccall_failed';
      failLoads(message: 'memory access out of bounds', firstAttempts: 1);

      await backend.modelLoadFromUrl(
        'https://example.com/hints-model.gguf',
        const ModelParams(contextSize: 4096, gpuLayers: 99),
      );

      final hints = events.indexWhere(
        (event) => event.startsWith('WebGpuLlamaBackend: bridge runtime hints'),
      );
      expect(hints, isNonNegative);
      expect(hints, lessThan(events.indexOf('<dispose>')));
    });

    test('walks every ladder rung with its thread cap', () async {
      final warnings = captureConsoleWarnings();
      bridgeRuntimeHints['llamadart.webgpu.core_variant'] = 'wasm64';
      bridgeRuntimeHints['llamadart.webgpu.runtime_notes'] =
          'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
          'threads_capped_pool:4;thread_pool_size:4;threads_batch:4;'
          'model_network_stream;model_response_stream;model_load_ccall_failed';
      failLoads(message: 'memory access out of bounds', firstAttempts: 9);

      await backend.modelLoadFromUrl(
        'https://example.com/full-ladder-model.gguf',
        const ModelParams(
          contextSize: 4096,
          gpuLayers: 99,
          preferMemory64: true,
        ),
      );

      expect(requestedContextSizes, <int>[
        4096,
        4096,
        2048,
        2048,
        1024,
        1024,
        768,
        768,
        512,
        512,
      ]);
      expect(requestedGpuLayerCounts, <int?>[
        99,
        0,
        99,
        0,
        99,
        0,
        99,
        0,
        99,
        0,
      ]);
      expect(requestedThreadCounts, <int?>[null, 4, 4, 2, 2, 2, 2, 1, 1, 1]);
      expect(
        warnings
            .where((message) => message.contains('reduced settings'))
            .skip(4)
            .toList(),
        <String>[
          'WebGpuLlamaBackend: retrying web model load with reduced settings '
              '(nCtx=1024, nGpuLayers=0, nThreads=2)',
          'WebGpuLlamaBackend: retrying web model load with reduced settings '
              '(nCtx=768, nGpuLayers=99, nThreads=2)',
          'WebGpuLlamaBackend: retrying web model load with reduced settings '
              '(nCtx=768, nGpuLayers=0, nThreads=1)',
          'WebGpuLlamaBackend: retrying web model load with reduced settings '
              '(nCtx=512, nGpuLayers=99, nThreads=1)',
          'WebGpuLlamaBackend: retrying web model load with reduced settings '
              '(nCtx=512, nGpuLayers=0, nThreads=1)',
        ],
      );
      expect(
        warnings
            .where((message) => message.contains('loaded after fallback'))
            .toList(),
        <String>[
          'WebGpuLlamaBackend: model loaded after fallback '
              '(nCtx=512, nGpuLayers=0, nThreads=1)',
        ],
      );
    });

    test(
      'keeps an explicit mem64 preference when the ladder advances',
      () async {
        failLoadsInOrder([
          (
            'wasm64',
            'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
                'threads_capped_pool:4;thread_pool_size:4;threads_batch:4;'
                'model_network_stream;model_response_stream;'
                'model_load_ccall_failed',
            'memory access out of bounds',
          ),
        ]);

        await backend.modelLoadFromUrl(
          'https://example.com/mem64-advance-model.gguf',
          const ModelParams(
            contextSize: 4096,
            gpuLayers: 99,
            preferMemory64: true,
          ),
        );

        expect(requestedGpuLayerCounts, <int?>[99, 0]);
        expect(capturedPreferMemory64(), isTrue);
      },
    );

    test('keeps the forced fetch retry when the ladder advances', () async {
      globalContext.setProperty(
        '__llamadartBridgeAllowAutoRemoteFetchBackend'.toJS,
        true.toJS,
      );
      failLoadsInOrder([
        (
          'wasm64',
          'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
              'threads_capped_pool:4;thread_pool_size:4;threads_batch:4;'
              'model_fetch_backend_attempt;model_fetch_chunk:4194304;'
              'model_fetch_backend_failed;model_network_stream;'
              'model_response_stream;model_fs_write_loaded:0;'
              'model_fs_write_arraybuffer_oom',
          'Array buffer allocation failed',
        ),
        (
          'wasm64',
          'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
              'threads_capped_pool:4;thread_pool_size:4;threads_batch:4;'
              'model_fetch_backend_attempt;model_fetch_chunk:131072',
          'memory access out of bounds',
        ),
      ]);

      await backend.modelLoadFromUrl(
        'https://example.com/staging-advance-model.gguf',
        const ModelParams(contextSize: 4096, gpuLayers: 99),
      );

      expect(requestedGpuLayerCounts, <int?>[99, 99, 0]);
      expect(requestedForceRemoteFetchBackends, <bool?>[null, true, true]);
      expect(requestedRemoteFetchChunkBytes, <int?>[
        4 * 1024 * 1024,
        128 * 1024,
        128 * 1024,
      ]);
    });

    test(
      'keeps a core abort from an advanced attempt for the wasm64 restart',
      () async {
        final warnings = captureConsoleWarnings();
        globalContext.setProperty(
          '__llamadartBridgeForceRemoteFetchBackend'.toJS,
          true.toJS,
        );
        globalContext.setProperty(
          '__llamadartBridgeRemoteFetchChunkBytes'.toJS,
          4096.toJS,
        );
        failLoadsInOrder([
          (
            'wasm64',
            'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
                'threads_capped_pool:4;thread_pool_size:4;threads_batch:4;'
                'model_fetch_backend_attempt;model_fetch_chunk:16384;core_abort',
            'memory access out of bounds',
          ),
          (
            'wasm32',
            'core_mem64_attempt;core_mem64_unavailable;core_wasm32_active;'
                'core_pthreads:1;threads_capped_pool:4;thread_pool_size:4;'
                'threads_batch:4;model_network_stream;model_response_stream;'
                'model_fs_write_loaded:0;model_fs_write_arraybuffer_oom',
            'Array buffer allocation failed',
          ),
        ]);

        await backend.modelLoadFromUrl(
          'https://example.com/abort-advance-model.gguf',
          const ModelParams(contextSize: 4096, gpuLayers: 99),
        );

        expect(requestedGpuLayerCounts, <int?>[99, 0, 99]);
        expect(requestedForceRemoteFetchBackends, <bool?>[true, true, false]);
        expect(capturedPreferMemory64(), isTrue);
        expect(
          warnings
              .where((message) => message.contains('wasm32 memory pressure'))
              .toList(),
          <String>[
            'WebGpuLlamaBackend: wasm32 memory pressure detected; '
                'retrying with wasm64 core and streamed network loading.',
          ],
        );
      },
    );

    const nativeAbort = 'Aborted(). Build with -sASSERTIONS for more info.';
    const mem64Notes =
        'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
        'thread_pool_size:4;threads_batch:4;';

    test('keeps counting chunk restarts across a ladder advance', () async {
      final warnings = captureConsoleWarnings();
      globalContext.setProperty(
        '__llamadartBridgeForceRemoteFetchBackend'.toJS,
        true.toJS,
      );
      globalContext.setProperty(
        '__llamadartBridgeRemoteFetchChunkBytes'.toJS,
        (20 * 1024).toJS,
      );
      failLoadsInOrder([
        (
          'wasm64',
          '${mem64Notes}model_fetch_backend_attempt;model_fetch_chunk:20480;'
              'core_abort',
          nativeAbort,
        ),
        (
          'wasm64',
          '${mem64Notes}model_fetch_backend_attempt;model_fetch_chunk:16384',
          'memory access out of bounds',
        ),
        (
          'wasm64',
          '${mem64Notes}model_fetch_backend_attempt;model_fetch_chunk:16384;'
              'core_abort',
          nativeAbort,
        ),
      ]);

      await backend.modelLoadFromUrl(
        'https://example.com/chunk-advance-model.gguf',
        const ModelParams(contextSize: 4096, gpuLayers: 99),
      );

      expect(requestedGpuLayerCounts, <int?>[99, 99, 0, 99]);
      expect(requestedRemoteFetchChunkBytes, <int?>[
        20 * 1024,
        10 * 1024,
        10 * 1024,
        5 * 1024,
      ]);
      expect(
        warnings
            .where((message) => message.contains('smaller fetch chunks'))
            .toList(),
        <String>[
          'WebGpuLlamaBackend: fetch-backed model loading aborted; retrying '
              'with smaller fetch chunks (10 KiB, attempt #1).',
          'WebGpuLlamaBackend: fetch-backed model loading aborted; retrying '
              'with smaller fetch chunks (5 KiB, attempt #2).',
        ],
      );
    });

    void failFirstLoadAfterSetting(
      String global,
      (String, String, String) failure,
    ) {
      var loadCallCount = 0;
      bridge.setProperty(
        'loadModelFromUrl'.toJS,
        ((String url, JSObject? config) {
          loadCallCount += 1;
          recordLoadConfig(config);
          if (loadCallCount > 1) {
            return Future<void>.value().toJS;
          }
          globalContext.setProperty(global.toJS, true.toJS);
          final (coreVariant, runtimeNotes, message) = failure;
          bridgeRuntimeHints['llamadart.webgpu.core_variant'] = coreVariant;
          bridgeRuntimeHints['llamadart.webgpu.runtime_notes'] = runtimeNotes;
          return rejectLoadWith(message);
        }).toJS,
      );
    }

    test(
      'forces the fetch backend after an opted-in wasm32 staging failure',
      () async {
        final warnings = captureConsoleWarnings();
        globalContext.setProperty(
          '__llamadartBridgeAllowAutoRemoteFetchBackend'.toJS,
          true.toJS,
        );
        failLoadsInOrder([
          (
            'wasm32',
            'core_wasm32_active;core_pthreads:1;thread_pool_size:4;'
                'threads_batch:4;model_network_stream;model_response_stream;'
                'model_fs_write_loaded:0;model_fs_write_arraybuffer_oom',
            'Array buffer allocation failed',
          ),
        ]);

        await backend.modelLoadFromUrl(
          'https://example.com/opted-in-wasm32-model.gguf',
          const ModelParams(contextSize: 4096, gpuLayers: 99),
        );

        expect(requestedForceRemoteFetchBackends, <bool?>[null, true]);
        expect(
          warnings,
          contains(
            'WebGpuLlamaBackend: wasm32 memory pressure detected; '
            'retrying with wasm64 core and explicitly enabled '
            'fetch-backed loading.',
          ),
        );
      },
    );

    test('keeps the load-start opt-in when a page opts in mid-load', () async {
      final warnings = captureConsoleWarnings();
      failFirstLoadAfterSetting(
        '__llamadartBridgeAllowAutoRemoteFetchBackend',
        (
          'wasm32',
          'core_wasm32_active;core_pthreads:1;thread_pool_size:4;'
              'threads_batch:4;model_network_stream;model_response_stream;'
              'model_fs_write_loaded:0;model_fs_write_arraybuffer_oom',
          'Array buffer allocation failed',
        ),
      );

      await backend.modelLoadFromUrl(
        'https://example.com/mid-load-opt-in-model.gguf',
        const ModelParams(contextSize: 4096, gpuLayers: 99),
      );

      expect(requestedForceRemoteFetchBackends, <bool?>[null, false]);
      expect(
        warnings,
        contains(
          'WebGpuLlamaBackend: wasm32 memory pressure detected; '
          'retrying with wasm64 core and streamed network loading.',
        ),
      );
    });

    test(
      'surfaces the staging error when a page opts in during a failed load',
      () async {
        failFirstLoadAfterSetting(
          '__llamadartBridgeAllowAutoRemoteFetchBackend',
          (
            'wasm64',
            '${mem64Notes}model_network_stream;model_response_stream;'
                'model_fs_write_loaded:0;model_fs_write_arraybuffer_oom',
            'Array buffer allocation failed',
          ),
        );

        await expectLater(
          backend.modelLoadFromUrl(
            'https://example.com/mid-load-staging-model.gguf',
            const ModelParams(contextSize: 4096, gpuLayers: 99),
          ),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'message',
              startsWith(
                'Web model staging failed before the GGUF could be loaded '
                'safely.',
              ),
            ),
          ),
        );

        expect(requestedForceRemoteFetchBackends, <bool?>[null]);
      },
    );

    test('classifies an attempt by the fetch mode it requested', () async {
      globalContext.setProperty(
        '__llamadartBridgeAllowAutoRemoteFetchBackend'.toJS,
        true.toJS,
      );
      failFirstLoadAfterSetting('__llamadartBridgeForceRemoteFetchBackend', (
        'wasm32',
        'core_wasm32_active;core_pthreads:1;thread_pool_size:4;'
            'threads_batch:4;model_fetch_backend_attempt;'
            'model_fetch_chunk:4194304;core_abort',
        nativeAbort,
      ));

      await backend.modelLoadFromUrl(
        'https://example.com/mid-attempt-force-model.gguf',
        const ModelParams(contextSize: 4096, gpuLayers: 99),
      );

      expect(requestedForceRemoteFetchBackends, <bool?>[null, false]);
      expect(requestedRemoteFetchChunkBytes, <int?>[
        4 * 1024 * 1024,
        4 * 1024 * 1024,
      ]);
      expect(capturedPreferMemory64(), isTrue);
    });

    test(
      'surfaces a BigInt worker crash that reports no core variant',
      () async {
        final warnings = captureConsoleWarnings();
        bridge.setProperty(
          'getModelMetadata'.toJS,
          (() {
            final meta = JSObject();
            meta.setProperty('llamadart.webgpu.execution'.toJS, 'worker'.toJS);
            return meta;
          }).toJS,
        );
        failLoads(
          message:
              'Uncaught TypeError: Cannot convert a BigInt value to a number',
          firstAttempts: 1,
        );

        await expectLater(
          backend.modelLoadFromUrl(
            'https://example.com/worker-crash-model.gguf',
            const ModelParams(
              contextSize: 4096,
              gpuLayers: 99,
              preferMemory64: true,
            ),
          ),
          throwsA(isNot(isA<UnsupportedError>())),
        );

        expect(requestedForceRemoteFetchBackends, <bool?>[null]);
        expect(capturedPreferMemory64(), isTrue);
        expect(
          warnings.where((message) => message.contains('BigInt')),
          isEmpty,
        );
      },
    );

    test('skips the bridge when generation is cancelled first', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );
      final chunks = <List<int>>[];
      final done = Completer<void>();

      backend
          .generate(1, 'Hello', const GenerationParams())
          .listen(chunks.add, onDone: done.complete);
      backend.cancelGeneration();
      await done.future;

      expect(createCompletionCallCount, 0);
      expect(chunks, isEmpty);

      final next = await backend
          .generate(1, 'Hello', const GenerationParams())
          .toList();
      expect(createCompletionCallCount, 1);
      expect(next, isNotEmpty);
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

    test(
      'emits a returned completion when token callbacks are absent',
      () async {
        bridge.setProperty(
          'createCompletion'.toJS,
          ((String prompt, JSObject opts) {
            return Future<JSString>.value('Final transcript'.toJS).toJS;
          }).toJS,
        );

        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );

        final chunks = await backend
            .generate(1, 'Transcribe', const GenerationParams())
            .toList();

        expect(
          utf8.decode(chunks.expand((chunk) => chunk).toList()),
          'Final transcript',
        );
      },
    );

    test(
      'reconciles a returned completion after partial token callbacks',
      () async {
        bridge.setProperty(
          'createCompletion'.toJS,
          ((String prompt, JSObject opts) {
            final onToken = opts.getProperty('onToken'.toJS) as JSFunction?;
            onToken?.callAsFunction(null, 'Final '.toJS, null);
            return Future<JSString>.value('Final transcript'.toJS).toJS;
          }).toJS,
        );

        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );

        final chunks = await backend
            .generate(1, 'Transcribe', const GenerationParams())
            .toList();

        expect(
          utf8.decode(chunks.expand((chunk) => chunk).toList()),
          'Final transcript',
        );
      },
    );

    group('generation limits', () {
      void reportCompletion({
        Object? reason = 'length',
        String text = 'partial reply',
        bool usageSupported = true,
        bool workerDelivery = false,
        bool failAfterUsage = false,
        void Function()? afterToken,
        int completionTokens = 1,
      }) {
        final constructor = (() {}).toJS;
        constructor.setProperty(
          'supportsCompletionUsage'.toJS,
          usageSupported.toJS,
        );
        bridge.setProperty('constructor'.toJS, constructor);
        bridge.setProperty(
          'createCompletion'.toJS,
          ((String prompt, JSObject opts) {
            final mediaCap = opts.getProperty('mediaMaxPredict'.toJS);
            lastMediaMaxPredict = mediaCap.isA<JSNumber>()
                ? (mediaCap as JSNumber).toDartInt
                : null;
            Future<JSString> complete() async {
              if (workerDelivery) await Future<void>.delayed(Duration.zero);
              final onToken = opts.getProperty('onToken'.toJS) as JSFunction?;
              onToken?.callAsFunction(null, text.toJS, text.toJS);
              afterToken?.call();
              final onUsage = opts.getProperty('onUsage'.toJS) as JSFunction?;
              expect(onUsage != null, usageSupported);
              onUsage?.callAsFunction(
                null,
                <String, Object?>{
                  'promptTokens': 4095,
                  'completionTokens': completionTokens,
                  'finishReason': ?reason,
                }.jsify(),
              );
              if (failAfterUsage) throw StateError('bridge failed');
              return text.toJS;
            }

            return complete().toJS;
          }).toJS,
        );
      }

      Future<LlamaEngine> loadEngine() async {
        final engine = LlamaEngine(WebAutoBackend(webBackend: backend));
        await engine.loadModelFromUrl('https://example.com/model.gguf');
        addTearDown(engine.dispose);
        return engine;
      }

      for (final workerDelivery in [false, true]) {
        final delivery = workerDelivery ? 'worker event' : 'direct callback';
        test(
          '$delivery length reaches public completion and rolls back tools',
          () async {
            reportCompletion(workerDelivery: workerDelivery);
            final engine = await loadEngine();
            final session = ChatSession(engine, maxContextTokens: 0);
            final result = await session.sendWithTools(
              'Reply',
              tools: const [],
              params: const GenerationParams(maxTokens: 100),
            );
            expect(result.completion.finishReason, LlamaFinishReason.length);
            expect(result.stopReason, LlamaToolLoopStopReason.truncated);
            expect(result.rolledBack, isTrue);
            expect(session.history, isEmpty);
          },
        );

        test(
          '$delivery stop at maxTokens is complete, without counter inference',
          () async {
            reportCompletion(
              reason: 'stop',
              completionTokens: 1,
              workerDelivery: workerDelivery,
            );
            final engine = await loadEngine();
            final session = ChatSession(engine, maxContextTokens: 0);
            final result = await session.sendWithTools(
              'Reply',
              tools: const [],
              params: const GenerationParams(maxTokens: 1),
            );
            expect(result.completion.finishReason, LlamaFinishReason.stop);
            expect(result.stopReason, LlamaToolLoopStopReason.completed);
            expect(result.rolledBack, isFalse);
            expect(session.history.last.content, 'partial reply');
          },
        );

        test('$delivery cancellation wins over a reported length', () async {
          late LlamaEngine engine;
          reportCompletion(
            workerDelivery: workerDelivery,
            afterToken: () => engine.cancelGeneration(),
            failAfterUsage: workerDelivery,
          );
          engine = await loadEngine();
          final session = ChatSession(engine, maxContextTokens: 0);
          final result = await session.sendWithTools('Reply', tools: const []);
          expect(result.stopReason, LlamaToolLoopStopReason.cancelled);
          expect(
            result.completion.finishReason,
            isNot(LlamaFinishReason.length),
          );
        });
      }

      test(
        'publishes only after EOF, isolates requests and names no guessed cause',
        () async {
          await backend.modelLoadFromUrl(
            'https://example.com/model.gguf',
            const ModelParams(),
          );
          reportCompletion();
          final limited = backend.generate(
            1,
            'Reply',
            const GenerationParams(maxTokens: 100),
          );
          expect(backend.generationLimitOf(limited), isNull);
          await limited.drain<void>();
          expect(
            backend.generationLimitOf(limited),
            BackendGenerationLimit.runtime,
          );
          reportCompletion(reason: 'stop');
          final stopped = backend.generate(
            1,
            'Reply',
            const GenerationParams(maxTokens: 1),
          );
          await stopped.drain<void>();
          expect(backend.generationLimitOf(stopped), isNull);
          expect(
            backend.generationLimitOf(limited),
            BackendGenerationLimit.runtime,
          );
          expect(
            backend.generationLimitOf(const Stream<List<int>>.empty()),
            isNull,
          );
        },
      );

      for (final reason in [null, 'stop', 'cancelled', 'other', 1]) {
        test(
          'never infers a limit from missing or unrecognized reason $reason',
          () async {
            reportCompletion(reason: reason);
            final engine = await loadEngine();
            final completion = await engine.create([
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: 'Reply',
              ),
            ], params: const GenerationParams(maxTokens: 1)).collect();
            expect(completion.finishReason, LlamaFinishReason.stop);
          },
        );
      }

      test(
        'older bridge without usage capability never receives function option',
        () async {
          reportCompletion(usageSupported: false);
          final engine = await loadEngine();
          final completion = await engine.create([
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Reply'),
          ], params: const GenerationParams(maxTokens: 1)).collect();
          expect(completion.finishReason, LlamaFinishReason.stop);
        },
      );

      test(
        'subscription cancellation discards a pending length report',
        () async {
          reportCompletion();
          final started = Completer<void>();
          final completion = Completer<JSString>();
          bridge.setProperty(
            'createCompletion'.toJS,
            ((String prompt, JSObject opts) {
              final onUsage = opts.getProperty('onUsage'.toJS) as JSFunction;
              onUsage.callAsFunction(
                null,
                <String, Object?>{'finishReason': 'length'}.jsify(),
              );
              started.complete();
              return completion.future.toJS;
            }).toJS,
          );
          await backend.modelLoadFromUrl(
            'https://example.com/model.gguf',
            const ModelParams(),
          );
          final generation = backend.generate(
            1,
            'Reply',
            const GenerationParams(),
          );
          final subscription = generation.listen((_) {});
          await started.future;
          expect(backend.generationLimitOf(generation), isNull);
          await subscription.cancel();
          completion.complete('partial'.toJS);
          await Future<void>.delayed(Duration.zero);
          expect(backend.generationLimitOf(generation), isNull);
        },
      );

      test(
        'failure after a length report stays an error without limit metadata',
        () async {
          reportCompletion(failAfterUsage: true);
          await backend.modelLoadFromUrl(
            'https://example.com/model.gguf',
            const ModelParams(),
          );
          final generation = backend.generate(
            1,
            'Reply',
            const GenerationParams(),
          );
          await expectLater(generation.toList(), throwsA(anything));
          expect(backend.generationLimitOf(generation), isNull);
        },
      );

      test(
        'Web speech uses a generic runtime truncation error for a media cap',
        () async {
          runtimeGpuActive = false;
          runtimeGpuLayers = 0;
          bridge.setProperty('supportsAudio'.toJS, (() => true).toJS);
          backend = WebGpuLlamaBackend(
            promptSpeechToTextSupported: true,
            bridgeFactory: ([WebGpuBridgeConfig? config]) =>
                bridge as LlamaWebGpuBridge,
          );
          reportCompletion(
            text: 'language English<asr_text>partial transcript',
          );
          final engine = await loadEngine();
          await engine.loadMultimodalProjectorSource(
            ModelSource.parse('https://example.com/mmproj.gguf'),
          );
          final recognizer = SpeechToTextEngine.attach(
            engine,
            adapter: const Qwen3AsrAdapter(),
          );
          addTearDown(recognizer.dispose);
          expect((await recognizer.capabilities).isSupported, isTrue);
          final request = SpeechToTextRequest(
            audio: SpeechAudioBytesInput(
              Uint8List.fromList([1, 2, 3]),
              format: const SpeechAudioFormat(encoding: 'wav'),
            ),
            maxOutputTokens: 4096,
          );
          await expectLater(
            recognizer.transcribeOnce(request),
            throwsA(
              isA<LlamaSpeechTranscriptTruncatedException>()
                  .having(
                    (error) => error.limit,
                    'limit',
                    LlamaSpeechTranscriptLimit.runtime,
                  )
                  .having(
                    (error) => error.partialTranscript,
                    'partialTranscript',
                    'partial transcript',
                  ),
            ),
          );
          expect(lastMediaMaxPredict, isNotNull);
          expect(lastMediaMaxPredict, lessThan(request.maxOutputTokens));
          reportCompletion(
            reason: 'stop',
            text: 'language English<asr_text>complete transcript',
          );
          expect(
            (await recognizer.transcribeOnce(request)).text,
            'complete transcript',
          );
        },
      );

      test(
        'stop sequence suppresses a length report from the same completion',
        () async {
          reportCompletion(text: 'Reply STOP tail');
          await backend.modelLoadFromUrl(
            'https://example.com/model.gguf',
            const ModelParams(),
          );
          final generation = backend.generate(
            1,
            'Reply',
            const GenerationParams(stopSequences: ['STOP']),
          );
          final bytes = (await generation.toList()).expand((c) => c).toList();
          expect(utf8.decode(bytes), 'Reply ');
          expect(backend.generationLimitOf(generation), isNull);
        },
      );
    });

    group('generation usage', () {
      JSAny? bridgeUsage({int? promptTokens = 5}) => <String, Object?>{
        'promptTokens': ?promptTokens,
        'cachedPromptTokens': 2,
        'completionTokens': 3,
        'timeToFirstTokenMs': 1.5,
        'durationMs': 4.25,
        'finishReason': 'stop',
      }.jsify();

      late bool sawOnUsage;

      void advertiseUsage() {
        final constructor = (() {}).toJS;
        constructor.setProperty('supportsCompletionUsage'.toJS, true.toJS);
        bridge.setProperty('constructor'.toJS, constructor);
      }

      void completeWith({
        JSAny? usage,
        String? currentText,
        bool rejectWithAbort = false,
      }) {
        sawOnUsage = false;
        bridge.setProperty(
          'createCompletion'.toJS,
          ((String prompt, JSObject opts) {
            sawOnUsage = opts.getProperty('onUsage'.toJS).isA<JSFunction>();
            final onToken = opts.getProperty('onToken'.toJS) as JSFunction?;
            onToken?.callAsFunction(null, 'Hi'.toJS, currentText?.toJS);
            if (usage != null) {
              final onUsage = opts.getProperty('onUsage'.toJS) as JSFunction?;
              onUsage?.callAsFunction(null, usage);
            }
            if (rejectWithAbort) {
              return Future<JSString>.error(
                StateError('Generation was cancelled.'),
              ).toJS;
            }
            return Future<JSString>.value('Hi'.toJS).toJS;
          }).toJS,
        );
      }

      test('reports the usage the bridge passes to onUsage', () async {
        advertiseUsage();
        completeWith(usage: bridgeUsage());
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );

        final generation = backend.generate(
          1,
          'Hello',
          const GenerationParams(),
        );
        expect(backend.generationUsageOf(generation), isNull);
        await generation.toList();

        final usage = backend.generationUsageOf(generation)!;
        expect(usage.promptTokens, 5);
        expect(usage.cachedPromptTokens, 2);
        expect(usage.completionTokens, 3);
        expect(usage.timeToFirstToken, const Duration(microseconds: 1500));
        expect(usage.duration, const Duration(microseconds: 4250));
      });

      test('reports no usage from a bridge that sends none or an '
          'incomplete one', () async {
        advertiseUsage();
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );

        completeWith();
        final withoutUsage = backend.generate(
          1,
          'Hello',
          const GenerationParams(),
        );
        await withoutUsage.toList();
        expect(backend.generationUsageOf(withoutUsage), isNull);

        completeWith(usage: bridgeUsage(promptTokens: null));
        final incomplete = backend.generate(
          1,
          'Hello',
          const GenerationParams(),
        );
        await incomplete.toList();
        expect(backend.generationUsageOf(incomplete), isNull);
      });

      test('keeps the usage of a generation a stop sequence aborted', () async {
        advertiseUsage();
        completeWith(
          usage: bridgeUsage(),
          currentText: 'Hi STOP more',
          rejectWithAbort: true,
        );
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );

        final generation = backend.generate(
          1,
          'Hello',
          const GenerationParams(stopSequences: ['STOP']),
        );
        expect(
          utf8.decode((await generation.toList()).expand((c) => c).toList()),
          'Hi ',
        );
        expect(backend.generationUsageOf(generation)?.completionTokens, 3);
      });

      test(
        'reports no usage for a generation that fails after onUsage',
        () async {
          advertiseUsage();
          completeWith(usage: bridgeUsage(), rejectWithAbort: true);
          await backend.modelLoadFromUrl(
            'https://example.com/model.gguf',
            const ModelParams(),
          );

          final generation = backend.generate(
            1,
            'Hello',
            const GenerationParams(),
          );
          await expectLater(generation.toList(), throwsA(anything));
          expect(backend.generationUsageOf(generation), isNull);
        },
      );

      test('passes no onUsage to a bridge without supportsCompletionUsage, '
          'whose worker cannot clone a function', () async {
        completeWith(usage: bridgeUsage());
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );

        final generation = backend.generate(
          1,
          'Hello',
          const GenerationParams(),
        );
        await generation.toList();
        expect(sawOnUsage, isFalse);
        expect(backend.generationUsageOf(generation), isNull);

        advertiseUsage();
        completeWith(usage: bridgeUsage());
        await backend.generate(1, 'Hello', const GenerationParams()).toList();
        expect(sawOnUsage, isTrue);
      });
    });

    group('a cancelGeneration during a completion', () {
      late _ResultRecorder recorder;

      setUp(() => recorder = _ResultRecorder());

      /// Emits `partial`, runs [afterToken], then settles as the pinned
      /// bridge does once the caller's signal aborts: the worker path rejects
      /// with [abortRejection], the direct path resolves with the text so
      /// far.
      void completeOnAbort({
        required JSAny? abortRejection,
        void Function()? afterToken,
      }) {
        bridge.setProperty(
          'createCompletion'.toJS,
          ((String prompt, JSObject opts) {
            final signal = opts.getProperty<AbortSignal>('signal'.toJS);
            final onToken = opts.getProperty('onToken'.toJS) as JSFunction;
            return JSPromise<JSAny?>(
              ((JSFunction resolve, JSFunction reject) {
                signal.addEventListener(
                  'abort',
                  ((JSAny? _) {
                    if (abortRejection == null) {
                      resolve.callAsFunction(null, 'partial'.toJS);
                    } else {
                      reject.callAsFunction(null, abortRejection);
                    }
                  }).toJS,
                );
                onToken.callAsFunction(null, 'partial'.toJS, 'partial'.toJS);
                afterToken?.call();
              }).toJS,
            );
          }).toJS,
        );
      }

      Future<LlamaEngine> loadEngine() async {
        final engine = LlamaEngine(backend, observers: [recorder]);
        await engine.loadModelFromUrl('https://example.com/model.gguf');
        return engine;
      }

      final userTurn = [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Reply'),
      ];

      for (final worker in [true, false]) {
        final path = worker
            ? 'worker AbortError rejection'
            : 'direct-mode resolution';
        test('ends normally as cancelled after a $path', () async {
          late LlamaEngine engine;
          completeOnAbort(
            abortRejection: worker
                ? DOMException('Generation was cancelled.', 'AbortError')
                : null,
            afterToken: () => engine.cancelGeneration(),
          );
          engine = await loadEngine();

          final completion = await engine.complete(userTurn);
          expect(completion.text, 'partial');
          expect(completion.finishReason, LlamaFinishReason.stop);
          expect(await engine.generate('Hello').join(), 'partial');
          expect(recorder.results, hasLength(2));
          for (final result in recorder.results) {
            expect(result.error, isNull);
            expect(result.cancelled, isTrue);
          }
        });
      }

      test('parses a required tool call cut short by a cancel as partial, as '
          'native does', () async {
        bridgeRuntimeHints['tokenizer.chat_template'] =
            '{#- [SYSTEM_PROMPT] [TOOL_CALLS] [ARGS] -#}'
            '{% for message in messages %}[INST]{{ message["content"] }}'
            '[/INST]{% endfor %}';
        const partialCall = '[TOOL_CALLS]get_weather[ARGS]{"ci';
        late LlamaEngine engine;
        bridge.setProperty(
          'createCompletion'.toJS,
          ((String prompt, JSObject opts) {
            final signal = opts.getProperty<AbortSignal>('signal'.toJS);
            final onToken = opts.getProperty('onToken'.toJS) as JSFunction;
            return JSPromise<JSAny?>(
              ((JSFunction resolve, JSFunction reject) {
                signal.addEventListener(
                  'abort',
                  ((JSAny? _) => reject.callAsFunction(
                    null,
                    DOMException('Generation was cancelled.', 'AbortError'),
                  )).toJS,
                );
                onToken.callAsFunction(
                  null,
                  partialCall.toJS,
                  partialCall.toJS,
                );
                engine.cancelGeneration();
              }).toJS,
            );
          }).toJS,
        );
        engine = await loadEngine();

        final completion = await engine.complete(
          userTurn,
          tools: [
            ToolDefinition(
              name: 'get_weather',
              description: 'Get weather',
              parameters: [ToolParam.string('city', required: true)],
              handler: (_) async => 'ok',
            ),
          ],
          toolChoice: ToolChoice.required,
        );
        expect(completion.finishReason, LlamaFinishReason.stop);
        expect(completion.toolCalls, isEmpty);
        expect(recorder.results.single.cancelled, isTrue);
      });

      test('surfaces an AbortError that no cancel requested', () async {
        bridge.setProperty(
          'createCompletion'.toJS,
          ((String prompt, JSObject opts) => _rejectPromise(
            DOMException('The worker aborted.', 'AbortError'),
          )).toJS,
        );
        final engine = await loadEngine();

        await expectLater(
          engine.complete(userTurn),
          throwsA(isA<LlamaInferenceException>()),
        );
        expect(recorder.results.single.error, isA<LlamaInferenceException>());
        expect(recorder.results.single.cancelled, isFalse);
      });

      test('surfaces a failure other than the abort after a cancel', () async {
        late LlamaEngine engine;
        completeOnAbort(
          abortRejection: _jsError('device lost'),
          afterToken: () => engine.cancelGeneration(),
        );
        engine = await loadEngine();

        await expectLater(
          engine.complete(userTurn),
          throwsA(isA<LlamaInferenceException>()),
        );
        expect(recorder.results.single.error, isA<LlamaInferenceException>());
      });

      test(
        'keeps a later generation unaffected by an earlier cancel',
        () async {
          late LlamaEngine engine;
          completeOnAbort(
            abortRejection: DOMException(
              'Generation was cancelled.',
              'AbortError',
            ),
            afterToken: () => engine.cancelGeneration(),
          );
          engine = await loadEngine();
          await engine.complete(userTurn);

          bridge.setProperty(
            'createCompletion'.toJS,
            ((String prompt, JSObject opts) => _rejectPromise(
              DOMException('The worker aborted.', 'AbortError'),
            )).toJS,
          );
          await expectLater(
            engine.complete(userTurn),
            throwsA(isA<LlamaInferenceException>()),
          );
        },
      );
    });

    test(
      'canceling a generation subscription aborts only its bridge signal',
      () async {
        final completion = Completer<void>();
        final started = Completer<void>();
        late AbortSignal signal;
        bridge.setProperty(
          'createCompletion'.toJS,
          ((String prompt, JSObject opts) {
            signal = opts.getProperty<AbortSignal>('signal'.toJS);
            signal.addEventListener(
              'abort',
              ((Event _) {
                if (!completion.isCompleted) completion.complete();
              }).toJS,
            );
            final onToken = opts.getProperty('onToken'.toJS) as JSFunction?;
            onToken?.callAsFunction(null, 'Hello'.toJS, 'Hello'.toJS);
            started.complete();
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
        await started.future;
        await subscription.cancel();
        expect(signal.aborted, isTrue);
        expect(completion.isCompleted, isTrue);
        expect(cancelCallCount, 0);
      },
    );

    test('an engine subscription cancel before the first token aborts its '
        'signal before the cancel returns', () async {
      final completion = Completer<void>();
      final started = Completer<void>();
      late AbortSignal signal;
      bridge.setProperty(
        'createCompletion'.toJS,
        ((String prompt, JSObject opts) {
          signal = opts.getProperty<AbortSignal>('signal'.toJS);
          signal.addEventListener(
            'abort',
            ((Event _) {
              if (!completion.isCompleted) completion.complete();
            }).toJS,
          );
          started.complete();
          return completion.future.toJS;
        }).toJS,
      );
      final engine = LlamaEngine(backend);
      await engine.loadModelFromUrl(
        'https://example.com/model.gguf',
        modelParams: const ModelParams(),
      );
      final subscription = engine.generate('Hello').listen((_) {});
      await started.future;
      final cancelled = subscription.cancel();
      expect(signal.aborted, isTrue);
      expect(cancelCallCount, 0);
      await cancelled;
    });

    test(
      'cancelling a queued completion leaves the active request intact',
      () async {
        final activeCompletion = Completer<JSString>();
        final queuedCompletion = Completer<JSString>();
        final signals = <String, AbortSignal>{};
        final dispatched = <String, Completer<void>>{
          'active': Completer<void>(),
          'queued': Completer<void>(),
        };
        bridge.setProperty(
          'cancel'.toJS,
          (() {
            cancelCallCount += 1;
            if (!activeCompletion.isCompleted) {
              activeCompletion.complete('cut short'.toJS);
            }
          }).toJS,
        );
        bridge.setProperty(
          'createCompletion'.toJS,
          ((String prompt, JSObject opts) {
            final signal = opts.getProperty<AbortSignal>('signal'.toJS);
            signals[prompt] = signal;
            final completion = prompt == 'active'
                ? activeCompletion
                : queuedCompletion;
            signal.addEventListener(
              'abort',
              ((Event _) {
                if (!completion.isCompleted) completion.complete(''.toJS);
              }).toJS,
            );
            dispatched[prompt]!.complete();
            return completion.future.toJS;
          }).toJS,
        );
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );
        final active = backend
            .generate(1, 'active', const GenerationParams())
            .toList();
        await dispatched['active']!.future;
        final queued = backend
            .generate(1, 'queued', const GenerationParams())
            .listen((_) {});
        await dispatched['queued']!.future;
        await queued.cancel();
        expect(signals['queued']!.aborted, isTrue);
        expect(signals['active']!.aborted, isFalse);
        if (!activeCompletion.isCompleted) {
          activeCompletion.complete('kept alive'.toJS);
        }
        final chunks = await active;
        expect(
          utf8.decode(chunks.expand((chunk) => chunk).toList()),
          'kept alive',
        );
        expect(cancelCallCount, 0);
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

    group('next-token scoring', () {
      JSObject? lastScoreOptions;
      String? lastScorePrompt;

      JSObject jsError(String message) => globalContext
          .getProperty<JSFunction>('Error'.toJS)
          .callAsConstructor<JSObject>(message.toJS);

      JSObject scoredToken(int token, List<int> bytes, double? logprob) {
        final entry = JSObject();
        entry.setProperty('token'.toJS, token.toJS);
        entry.setProperty('bytes'.toJS, Uint8List.fromList(bytes).toJS);
        entry.setProperty('logprob'.toJS, logprob?.toJS);
        return entry;
      }

      void installScoring(JSPromise<JSAny?> Function() respond) {
        bridge.setProperty(
          'scoreNextToken'.toJS,
          ((String prompt, JSObject options) {
            lastScorePrompt = prompt;
            lastScoreOptions = options;
            return respond();
          }).toJS,
        );
      }

      setUp(() {
        lastScoreOptions = null;
        lastScorePrompt = null;
      });

      test('reports support only when the bridge has the method', () async {
        installScoring(() => Future<JSAny?>.value(null).toJS);
        expect(backend.supportsNextTokenScoring, isFalse);
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );
        expect(backend.supportsNextTokenScoring, isTrue);

        bridge.delete('scoreNextToken'.toJS);
        expect(backend.supportsNextTokenScoring, isFalse);
        await expectLater(
          () => backend.scoreNextToken(
            1,
            'hi',
            candidates: const <int>[1],
            topK: 0,
            reusePromptPrefix: true,
          ),
          throwsA(
            isA<UnsupportedError>().having(
              (UnsupportedError error) => error.message,
              'message',
              contains('v0.1.52+'),
            ),
          ),
        );
      });

      test('forwards the request and parses the scores', () async {
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );
        installScoring(() {
          final result = JSObject();
          result.setProperty(
            'candidates'.toJS,
            <JSObject>[
              scoredToken(7, const <int>[0xe2, 0x82], -0.25),
              scoredToken(9, const <int>[], null),
            ].toJS,
          );
          result.setProperty(
            'top'.toJS,
            <JSObject>[
              scoredToken(7, const <int>[0x41], -0.25),
            ].toJS,
          );
          result.setProperty('promptTokens'.toJS, 3.toJS);
          return Future<JSAny?>.value(result).toJS;
        });

        final scores = await backend.scoreNextToken(
          1,
          'The answer is',
          candidates: const <int>[7, 9],
          topK: 1,
          reusePromptPrefix: false,
        );

        expect(lastScorePrompt, 'The answer is');

        final options = lastScoreOptions!;
        expect(
          options
              .getProperty<JSArray<JSNumber>>('candidates'.toJS)
              .toDart
              .map((token) => token.toDartInt),
          <int>[7, 9],
        );
        expect(options.getProperty<JSNumber>('topK'.toJS).toDartInt, 1);
        expect(
          options.getProperty<JSBoolean>('reusePromptPrefix'.toJS).toDart,
          isFalse,
        );

        expect(scores.candidates.map((entry) => entry.token), <int>[7, 9]);
        expect(scores.candidates.first.bytes, <int>[0xe2, 0x82]);
        expect(scores.candidates.first.logprob, -0.25);
        expect(scores.candidates.last.logprob, double.negativeInfinity);
        expect(scores.top.single.text, 'A');
        expect(scores.promptTokens, 3);

        await backend.scoreNextToken(
          1,
          '<s>The answer is',
          candidates: const <int>[7],
          topK: 0,
          reusePromptPrefix: true,
        );
        expect(
          lastScorePrompt,
          'The answer is',
          reason: 'the bridge adds BOS itself, as for generation',
        );
      });

      test('maps bridge errors to the native error types', () async {
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );
        Future<void> expectRejection(String message, Matcher matcher) async {
          installScoring(() => _rejectPromise(jsError(message)));
          await expectLater(
            () => backend.scoreNextToken(
              1,
              'hi',
              candidates: const <int>[99],
              topK: 0,
              reusePromptPrefix: true,
            ),
            throwsA(matcher),
          );
        }

        const outOfVocabulary =
            'Next-token scoring failed: Token id 99 is outside the vocabulary '
            'of 32 tokens';
        await expectRejection(
          outOfVocabulary,
          isA<RangeError>().having(
            (error) => error.message,
            'message',
            outOfVocabulary,
          ),
        );
        await expectRejection(
          'Next-token scoring failed: Next-token scoring needs a decoder-only '
          'model',
          isA<LlamaUnsupportedException>(),
        );
        await expectRejection(
          'Next-token scoring failed: llama_decode failed while processing '
          'prompt',
          isNot(
            anyOf(
              isA<LlamaArgumentException>(),
              isA<LlamaUnsupportedException>(),
            ),
          ),
        );

        lastScorePrompt = null;
        for (final (candidates, topK) in <(List<int>, int)>[
          (const <int>[0x80000000], 0),
          (const <int>[1], 0x80000000),
        ]) {
          await expectLater(
            () => backend.scoreNextToken(
              1,
              'hi',
              candidates: candidates,
              topK: topK,
              reusePromptPrefix: true,
            ),
            throwsRangeError,
          );
        }
        expect(lastScorePrompt, isNull, reason: 'rejected before the bridge');
      });
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

    test('raises a global remote fetch chunk override to 4 KiB', () async {
      globalContext.setProperty(
        '__llamadartBridgeRemoteFetchChunkBytes'.toJS,
        1024.toJS,
      );

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      final config = lastBridgeConfig as JSObject;
      final remoteFetchChunkBytes = config.getProperty(
        'remoteFetchChunkBytes'.toJS,
      );
      expect((remoteFetchChunkBytes as JSNumber).toDartInt, 4 * 1024);
      expect(requestedRemoteFetchChunkBytes, <int?>[4 * 1024]);
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

    test('forces CPU fallback on Safari for negative gpuLayers', () async {
      globalContext.setProperty(
        '__llamadartBridgeUserAgent'.toJS,
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 '
                '(KHTML, like Gecko) Version/17.5 Safari/605.1.15'
            .toJS,
      );

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(gpuLayers: -1),
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

    test('warns only when Safari forces GPU layers down to the CPU', () async {
      final warnings = captureConsoleWarnings();
      globalContext.setProperty(
        '__llamadartBridgeUserAgent'.toJS,
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 '
                '(KHTML, like Gecko) Version/17.5 Safari/605.1.15'
            .toJS,
      );

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(gpuLayers: 0),
      );
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(gpuLayers: 1),
      );

      expect(requestedGpuLayerCounts, <int?>[0, 0]);
      expect(
        warnings.where((message) => message.contains('Safari')).toList(),
        <String>[
          'WebGpuLlamaBackend: Safari WebGPU generation is unstable for legacy '
              'bridge assets; forcing CPU fallback. Use bridge assets with '
              'adaptive Safari GPU probe support, or set '
              'window.__llamadartAllowSafariWebGpu = true to bypass this '
              'safeguard.',
        ],
      );
    });

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

    group('tool grammar', () {
      const hermesTemplate =
          '{%- if tools %}<tools>{{ tools[0] | tojson }}</tools>'
          '<tool_call>{"name": <function-name>, "arguments": <args-json-object>}</tool_call>{% endif %}'
          '{% for message in messages %}<|im_start|>{{ message["role"] }}\n{{ message["content"] }}<|im_end|>\n{% endfor %}'
          '{% if add_generation_prompt %}<|im_start|>assistant\n{% endif %}';
      final weatherTool = ToolDefinition(
        name: 'get_weather',
        description: 'Returns current weather for a city.',
        parameters: [ToolParam.string('city', description: 'City name')],
        handler: (_) async => 'Sunny',
      );

      Future<LlamaEngine> loadHermesEngine() async {
        bridgeRuntimeHints['tokenizer.chat_template'] = hermesTemplate;
        final engine = LlamaEngine(backend);
        await engine.loadModelFromUrl(
          'https://example.com/model.gguf',
          modelParams: const ModelParams(),
        );
        return engine;
      }

      Future<void> createWithTools(LlamaEngine engine, ToolChoice choice) {
        return engine
            .create(
              <LlamaChatMessage>[
                LlamaChatMessage.fromText(
                  role: LlamaChatRole.user,
                  text: 'Say hello in French. Do not use tools.',
                ),
              ],
              tools: <ToolDefinition>[weatherTool],
              toolChoice: choice,
            )
            .drain<void>();
      }

      test('ToolChoice.auto sends no tool grammar to the bridge', () async {
        final engine = await loadHermesEngine();

        await createWithTools(engine, ToolChoice.auto);

        expect(lastPrompt, contains('get_weather'));
        expect(lastGrammar, isNull);
        expect(backend.supportsLazyGrammar, isFalse);
      });

      test('ToolChoice.auto retains a supported lazy tool grammar', () async {
        bridge.setProperty(
          'getCompletionCapabilities'.toJS,
          (() => Future<JSObject>.value(
            JSObject()
              ..setProperty('lazyGrammar'.toJS, true.toJS)
              ..setProperty('penaltyPromptTokens'.toJS, true.toJS),
          ).toJS).toJS,
        );
        final engine = await loadHermesEngine();

        await createWithTools(engine, ToolChoice.auto);

        expect(backend.supportsLazyGrammar, isTrue);
        expect(lastGrammar, contains('get_weather'));
        expect(lastCompletionOptions!['grammarLazy'].dartify(), isTrue);
        expect(lastCompletionOptions!['grammarTriggers'].dartify(), isNotEmpty);
        expect(
          lastCompletionOptions!.hasProperty('penaltyPromptTokens'.toJS).toDart,
          isFalse,
        );
      });

      void replayBridgeEmission(List<String> pieces) {
        bridge.setProperty(
          'createCompletion'.toJS,
          ((String prompt, JSObject opts) {
            final grammarRaw = opts.getProperty('grammar'.toJS);
            lastGrammar = grammarRaw.isA<JSString>()
                ? (grammarRaw as JSString).toDart
                : null;
            final onToken = opts.getProperty('onToken'.toJS) as JSFunction?;
            var text = '';
            for (final piece in pieces) {
              text += piece;
              onToken?.callAsFunction(null, piece.toJS, text.toJS);
            }
            return Future<JSString>.value(text.toJS).toJS;
          }).toJS,
        );
      }

      Future<List<LlamaCompletionChunk>> createAuto(
        LlamaEngine engine,
        String text,
      ) {
        return engine
            .create(
              <LlamaChatMessage>[
                LlamaChatMessage.fromText(role: LlamaChatRole.user, text: text),
              ],
              tools: <ToolDefinition>[weatherTool],
              toolChoice: ToolChoice.auto,
            )
            .toList();
      }

      test(
        'ToolChoice.auto parses a tool call from unconstrained output',
        () async {
          final engine = await loadHermesEngine();
          replayBridgeEmission(<String>[
            '<tool_call>',
            '\n{{"name": "get_',
            'weather", "arguments": {"ci',
            'ty": "Paris"}}\n',
            '</tool_call>',
          ]);

          final chunks = await createAuto(
            engine,
            'What is the weather in Paris right now?',
          );

          expect(lastGrammar, isNull);
          final toolCalls = chunks
              .expand((chunk) => chunk.choices.first.delta.toolCalls ?? [])
              .toList();
          expect(toolCalls, hasLength(1));
          expect(toolCalls.single.function?.name, 'get_weather');
          expect(
            jsonDecode(toolCalls.single.function!.arguments!),
            <String, dynamic>{'city': 'Paris'},
          );
          expect(chunks.last.choices.first.finishReason, 'tool_calls');
        },
      );

      test('ToolChoice.auto keeps a truncated tool call as content', () async {
        final engine = await loadHermesEngine();
        replayBridgeEmission(<String>[
          '<tool_call>',
          '\n{"name": "get_weather", ',
          '"arguments": {"city": "Par',
        ]);

        final chunks = await createAuto(
          engine,
          'What is the weather in Paris right now?',
        );

        expect(lastGrammar, isNull);
        expect(
          chunks.expand((chunk) => chunk.choices.first.delta.toolCalls ?? []),
          isEmpty,
        );
        expect(
          chunks.map((chunk) => chunk.choices.first.delta.content ?? '').join(),
          contains('"city": "Par'),
        );
      });

      test('ToolChoice.required still sends the strict tool grammar', () async {
        final engine = await loadHermesEngine();

        await createWithTools(engine, ToolChoice.required);

        expect(lastGrammar, contains('get_weather'));
      });

      group('prompt penalty window', () {
        void reportPenaltyPromptTokens(JSAny? reported) {
          bridge.setProperty(
            'getCompletionCapabilities'.toJS,
            (() => Future<JSObject>.value(
              JSObject()..setProperty('penaltyPromptTokens'.toJS, reported),
            ).toJS).toJS,
          );
        }

        bool sentPenaltyPromptTokens() => lastCompletionOptions!
            .hasProperty('penaltyPromptTokens'.toJS)
            .toDart;

        test('ToolChoice.auto keeps the prompt out on assets that report '
            'penaltyPromptTokens', () async {
          reportPenaltyPromptTokens(true.toJS);
          final engine = await loadHermesEngine();

          await createWithTools(engine, ToolChoice.auto);
          expect(lastGrammar, isNull);
          expect(sentPenaltyPromptTokens(), isTrue);
          expect(
            lastCompletionOptions!.getProperty<JSAny?>(
              'penaltyPromptTokens'.toJS,
            ),
            false.toJS,
          );

          await createWithTools(engine, ToolChoice.required);
          expect(sentPenaltyPromptTokens(), isFalse);

          await engine.create(<LlamaChatMessage>[
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
          ]).drain<void>();
          expect(sentPenaltyPromptTokens(), isFalse);
        });

        test('ToolChoice.auto keeps the prompt out when draft resolution '
            'copies the params', () async {
          bridge.setProperty(
            'getCompletionCapabilities'.toJS,
            (() => Future<JSObject>.value(
              JSObject()
                ..setProperty('penaltyPromptTokens'.toJS, true.toJS)
                ..setProperty(
                  'speculativeDecoding'.toJS,
                  JSObject()..setProperty('ngram-simple'.toJS, true.toJS),
                ),
            ).toJS).toJS,
          );
          final engine = await loadHermesEngine();

          await engine
              .create(
                <LlamaChatMessage>[
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: 'Say hello in French. Do not use tools.',
                  ),
                ],
                params: GenerationParams(
                  speculativeDecodingConfig: SpeculativeDecodingConfig(
                    strategy: SpeculativeDecodingStrategy.ngramSimple,
                    strategies: const [SpeculativeDecodingStrategy.ngramSimple],
                    draftModelDownload: ModelLoadOptions(),
                  ),
                ),
                tools: <ToolDefinition>[weatherTool],
                toolChoice: ToolChoice.auto,
              )
              .drain<void>();

          expect(lastGrammar, isNull);
          expect(sentPenaltyPromptTokens(), isTrue);
          expect(
            lastCompletionOptions!.getProperty<JSAny?>(
              'penaltyPromptTokens'.toJS,
            ),
            false.toJS,
          );
        });

        test('ToolChoice.auto sends no penaltyPromptTokens on assets that do '
            'not report it', () async {
          for (final reported in <JSAny?>[
            null,
            false.toJS,
            'true'.toJS,
            1.toJS,
          ]) {
            if (reported != null) reportPenaltyPromptTokens(reported);
            final engine = await loadHermesEngine();

            await createWithTools(engine, ToolChoice.auto);

            expect(lastGrammar, isNull);
            expect(sentPenaltyPromptTokens(), isFalse, reason: '$reported');
            await engine.unloadModel();
          }
        });
      });

      test(
        'generate rejects lazy grammar and a non-root start symbol',
        () async {
          await backend.modelLoadFromUrl(
            'https://example.com/model.gguf',
            const ModelParams(),
          );

          for (final params in <GenerationParams>[
            const GenerationParams(grammar: 'root ::= "a"', grammarLazy: true),
            const GenerationParams(
              grammar: 'start ::= "a"',
              grammarRoot: 'start',
            ),
          ]) {
            expect(
              () => backend.generate(1, 'Hello', params),
              throwsA(isA<LlamaUnsupportedException>()),
            );
          }
          expect(createCompletionCallCount, 0);
        },
      );
    });

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
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('needs a multimodal projector'),
              contains('LlamaModel(source, projector: ...)'),
            ),
          ),
        ),
      );
      expect(sawMediaParts, isFalse);
    });

    test('rejects video parts instead of silently dropping them', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      expect(
        () => backend.generate(
          1,
          'Describe this video',
          const GenerationParams(),
          parts: <LlamaContentPart>[LlamaVideoContent(path: '/tmp/clip.mp4')],
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('image frames'),
          ),
        ),
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

      final retainedResponse = await window.fetch(lastMmprojPath!.toJS).toDart;
      expect(retainedResponse.ok, isTrue);
      expect(await retainedResponse.text().toDart, 'cached projector');

      await backend.multimodalContextFree(mmHandle!);
      await expectLater(
        window.fetch(lastMmprojPath!.toJS).toDart,
        throwsA(anything),
      );
    });

    test('revokes cached projector blob when projector load fails', () async {
      const cacheName = 'llamadart-webgpu-model-cache-v1';
      const mmprojUrl = 'https://example.com/mmproj-failing.gguf';
      final cache = await window.caches.open(cacheName).toDart;
      await cache.put(mmprojUrl.toJS, Response('cached projector'.toJS)).toDart;
      addTearDown(() async {
        await window.caches.delete(cacheName).toDart;
      });
      bridge.setProperty(
        'loadMultimodalProjector'.toJS,
        ((String path) {
          lastMmprojPath = path;
          return Future<void>.error(Exception('projector load failed')).toJS;
        }).toJS,
      );

      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );

      await expectLater(
        backend.multimodalContextCreate(1, mmprojUrl),
        throwsA(anything),
      );
      expect(lastMmprojPath, startsWith('blob:'));
      await expectLater(
        window.fetch(lastMmprojPath!.toJS).toDart,
        throwsA(anything),
      );
    });

    test('hands the bridge a path as a URL of the document, and a URL or '
        'blob as written', () async {
      final loaded = <String>[];
      bridge.setProperty(
        'loadModelFromUrl'.toJS,
        ((String url, JSObject? config) {
          loaded.add(url);
          return Future<void>.value().toJS;
        }).toJS,
      );
      String ofDocument(String path) =>
          '${Uri.parse(document.baseURI).resolve(path)}';
      final engine = LlamaEngine(backend);

      await engine.setModel(
        LlamaModel(
          ModelSource.path('models/tiny.gguf'),
          projector: ModelSource.path('../shared/mmproj.gguf'),
        ),
      );
      expect(lastMmprojPath, ofDocument('../shared/mmproj.gguf'));
      await engine.loadMultimodalProjectorSource(
        ModelSource.path('models/other-mmproj.gguf'),
      );
      expect(lastMmprojPath, ofDocument('models/other-mmproj.gguf'));
      for (final source in [
        ModelSource.path('/models/root.gguf'),
        ModelSource.parse('https://example.com/m.gguf?sig=a%2Fb'),
        ModelSource.path('blob:https://app.example/3f2a'),
      ]) {
        await engine.setModel(LlamaModel(source));
      }

      expect(loaded, [
        ofDocument('models/tiny.gguf'),
        ofDocument('/models/root.gguf'),
        'https://example.com/m.gguf?sig=a%2Fb',
        'blob:https://app.example/3f2a',
      ]);
      expect(ofDocument('models/tiny.gguf'), startsWith('http'));
      await engine.dispose();
    });

    group('a rejected model load', () {
      void loadModelsWith(JSAny? Function(String url) load) {
        bridge.setProperty(
          'loadModelFromUrl'.toJS,
          ((String url, JSObject options) => load(url)).toJS,
        );
      }

      Matcher modelException(Matcher details) => isA<LlamaModelException>()
          .having(
            (error) => error.message,
            'message',
            'The Web runtime could not load the model.',
          )
          .having((error) => '${error.details}', 'details', details);

      Matcher withoutSecrets(List<String> secrets) => allOf(<Matcher>[
        for (final secret in secrets) isNot(contains(secret)),
      ]);

      test('keeps credentials of a real Chrome fetch error out', () async {
        final errors = captureConsole('error');
        loadModelsWith((url) => window.fetch(url.toJS));
        for (final (url, redacted, secrets) in const [
          (
            'https://u:SEKRIT@example.com/m.gguf?token=Q1secret',
            'credentials: https://example.com/m.gguf',
            <String>['SEKRIT', 'Q1secret', 'u:'],
          ),
          (
            '//u:S13@example.com/m.gguf?t=Q1',
            'credentials: //example.com/m.gguf',
            <String>['S13', 't=Q1', 'u:'],
          ),
        ]) {
          errors.clear();
          await backend.setLogLevel(LlamaLogLevel.error);
          await expectLater(
            backend.modelLoadFromUrl(url, const ModelParams()),
            throwsA(
              modelException(
                allOf(contains(redacted), withoutSecrets(secrets)),
              ),
            ),
            reason: url,
          );
          expect(errors, isNotEmpty, reason: url);
          expect(errors.join('\n'), withoutSecrets(secrets), reason: url);

          final engine = LlamaEngine(backend);
          await expectLater(
            engine.loadModelFromUrl(url),
            throwsA(
              isA<LlamaModelException>().having(
                (error) => '$error',
                'error',
                withoutSecrets(secrets),
              ),
            ),
            reason: url,
          );
        }
      });

      test('redacts a signed URL in a bridge load error', () async {
        loadModelsWith(
          (url) => _rejectPromise(
            _jsError(
              'Failed to fetch model $url '
              '(403 Forbidden: signature SIGsecret123 expired)',
            ),
          ),
        );
        await expectLater(
          backend.modelLoadFromUrl(
            'https://bucket.example.com/m.gguf'
            '?X-Amz-Credential=AKIASECRET&X-Amz-Signature=SIGsecret123',
            const ModelParams(),
          ),
          throwsA(
            modelException(
              equals(
                'Failed to fetch model https://bucket.example.com/m.gguf '
                '(403 Forbidden: signature  expired)',
              ),
            ),
          ),
        );
      });

      test('keeps the host of a credential-free URL', () async {
        loadModelsWith(
          (url) => _rejectPromise(
            _jsError('Failed to fetch model $url (404 Not Found)'),
          ),
        );
        await expectLater(
          backend.modelLoadFromUrl(
            'https://huggingface.co/leehack/m/resolve/main/m.gguf',
            const ModelParams(),
          ),
          throwsA(
            modelException(
              equals(
                'Failed to fetch model '
                'https://huggingface.co/leehack/m/resolve/main/m.gguf '
                '(404 Not Found)',
              ),
            ),
          ),
        );
      });
    });

    group('an unmapped bridge error', () {
      const signedPath = 'https://example.com/s.bin?sig=SIGsecret123';
      final rejection = _jsError(
        'Bridge failed for $signedPath (signature SIGsecret123 expired)',
      );
      const redacted =
          'Bridge failed for https://example.com/s.bin '
          '(signature SIGsecret123 expired)';

      setUp(() async {
        for (final method in const [
          'embed',
          'embedBatch',
          'scoreNextToken',
          'stateSaveFile',
          'stateLoadFile',
        ]) {
          bridge.setProperty(
            method.toJS,
            ((JSAny? _, JSAny? _) => _rejectPromise(rejection)).toJS,
          );
        }
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );
      });

      Matcher throwsTyped<T extends LlamaException>(
        String message,
        String details,
      ) => throwsA(
        isA<T>()
            .having((error) => error.message, 'message', message)
            .having((error) => error.details, 'details', details),
      );

      test('fails embeddings with LlamaInferenceException', () async {
        final throwsEmbeddingError = throwsTyped<LlamaInferenceException>(
          'The Web runtime could not compute embeddings.',
          redacted,
        );
        await expectLater(backend.embed(1, 'a'), throwsEmbeddingError);
        await expectLater(
          backend.embedBatch(1, const ['a', 'b']),
          throwsEmbeddingError,
        );
      });

      test('fails next-token scoring with LlamaInferenceException', () async {
        await expectLater(
          backend.scoreNextToken(
            1,
            'hi',
            candidates: const <int>[1],
            topK: 0,
            reusePromptPrefix: false,
          ),
          throwsTyped<LlamaInferenceException>(
            'The Web runtime could not score the next token.',
            redacted,
          ),
        );
      });

      test('fails state persistence with the path secrets redacted', () async {
        const pathRedacted =
            'Bridge failed for https://example.com/s.bin (signature  expired)';
        await expectLater(
          backend.stateSaveFile(1, signedPath, const <int>[1]),
          throwsTyped<LlamaStateException>(
            'The Web runtime could not save the state.',
            pathRedacted,
          ),
        );
        await expectLater(
          backend.stateLoadFile(1, signedPath, 128),
          throwsTyped<LlamaStateException>(
            'The Web runtime could not load the state.',
            pathRedacted,
          ),
        );
      });
    });

    group('a string embedding rejection', () {
      const rankMessage =
          'Embedding generation failed: Embeddings are not supported for '
          'rank-pooled models such as rerankers: llama.cpp returns classifier '
          'scores, not an embedding, for pooling type RANK';
      const tooLongMessage =
          'Embedding generation failed: The embedding input has 600 tokens, '
          'but this model embeds its input in one pass of at most 512 tokens '
          '(n_ubatch). Shorten the input or raise nUbatch and nBatch.';

      Future<void> rejectEmbeddingsWith(String message) async {
        for (final method in const ['embed', 'embedBatch']) {
          bridge.setProperty(
            method.toJS,
            ((JSAny? _, JSAny? _) => _rejectPromise(_jsError(message))).toJS,
          );
        }
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );
      }

      Future<void> expectBothEmbedCalls(Matcher matcher) async {
        await expectLater(backend.embed(1, 'a'), matcher);
        await expectLater(backend.embedBatch(1, const ['a', 'b']), matcher);
      }

      Matcher throwsEmbeddingInference(String details) => throwsA(
        isA<LlamaInferenceException>()
            .having(
              (error) => error,
              'type',
              isNot(isA<LlamaEmbeddingInputTooLongException>()),
            )
            .having(
              (error) => error.message,
              'message',
              'The Web runtime could not compute embeddings.',
            )
            .having((error) => error.details, 'details', details),
      );

      test('maps rank pooling to LlamaUnsupportedException', () async {
        await rejectEmbeddingsWith(rankMessage);
        await expectBothEmbedCalls(
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              startsWith(
                'Embeddings are not supported for rank-pooled models such as '
                'rerankers',
              ),
            ),
          ),
        );
      });

      test('maps an over-long input to the typed overflow error', () async {
        await rejectEmbeddingsWith(tooLongMessage);
        await expectBothEmbedCalls(
          throwsA(
            isA<LlamaEmbeddingInputTooLongException>()
                .having((error) => error.maxInputTokens, 'maxInputTokens', 512)
                .having((error) => error.actualTokens, 'actualTokens', 600)
                .having(
                  (error) => error.message,
                  'message',
                  'The embedding input has 600 tokens, but this model embeds '
                      'its input in one pass of at most 512 tokens (n_ubatch). '
                      'Shorten the input or raise ModelParams.microBatchSize '
                      'and ModelParams.batchSize.',
                ),
          ),
        );
      });

      test('keeps the abort of an older bridge an inference error', () async {
        const abort =
            'RuntimeError: Aborted(GGML_ASSERT(cparams.n_ubatch >= n_tokens '
            '&& "encoder requires n_ubatch >= n_tokens") failed)';
        await rejectEmbeddingsWith(abort);
        await expectBothEmbedCalls(throwsEmbeddingInference(abort));
      });

      test('keeps an unprefixed core message an inference error', () async {
        final message = tooLongMessage.substring(
          'Embedding generation failed: '.length,
        );
        await rejectEmbeddingsWith(message);
        await expectBothEmbedCalls(throwsEmbeddingInference(message));
      });

      test('keeps an unprefixed rank message an inference error', () async {
        final message = rankMessage.substring(
          'Embedding generation failed: '.length,
        );
        await rejectEmbeddingsWith(message);
        await expectBothEmbedCalls(throwsEmbeddingInference(message));
      });

      test('keeps a message with leading text an inference error', () async {
        for (final base in const [rankMessage, tooLongMessage]) {
          final message = 'Worker failed: $base';
          await rejectEmbeddingsWith(message);
          await expectBothEmbedCalls(throwsEmbeddingInference(message));
        }
      });

      test('keeps a zero pass limit an inference error', () async {
        final message = tooLongMessage.replaceFirst('512', '0');
        await rejectEmbeddingsWith(message);
        await expectBothEmbedCalls(throwsEmbeddingInference(message));
      });
    });

    group('a rejected projector load', () {
      setUp(() {
        bridge.setProperty(
          'loadMultimodalProjector'.toJS,
          ((String path) {
            return _rejectPromise(
              _jsError(
                'Failed to fetch multimodal projector '
                'https://user:pw@example.com/mmproj.gguf?X-Amz-Signature=secret '
                '(404 Not Found)',
              ),
            );
          }).toJS,
        );
      });

      final throwsRedactedModelException = throwsA(
        isA<LlamaModelException>().having(
          (error) => error.details,
          'details',
          'Failed to fetch multimodal projector '
              'https://example.com/mmproj.gguf (404 Not Found)',
        ),
      );

      test('throws LlamaModelException from the backend', () async {
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );
        await expectLater(
          backend.multimodalContextCreate(1, 'https://example.com/mmproj.gguf'),
          throwsRedactedModelException,
        );
      });

      test('throws LlamaModelException from LlamaEngine', () async {
        final engine = LlamaEngine(backend);
        await engine.loadModelFromUrl(
          'https://example.com/model.gguf',
          modelParams: const ModelParams(),
        );
        await expectLater(
          engine.loadMultimodalProjector('https://example.com/mmproj.gguf'),
          throwsRedactedModelException,
        );
      });

      const credentials = 'includes credentials';
      const password = <String>[
        'S1ab',
        'S2cd',
        's2cd',
        'S3ef',
        'S4gh',
        'S5ij',
        'S6kl',
        '\u00fc',
        '%C3%BC',
        '%40',
      ];
      const passwordUrl =
          'https://u:S1ab@S2cd#S3ef%40S4gh?S5ij\u00fcS6kl@example.com/m.gguf';

      Future<void> expectRedactedFetchError(
        String url,
        String phrase,
        String redacted,
        List<String> secrets,
      ) async {
        await expectLater(
          backend.multimodalContextCreate(1, url),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => '${error.details}',
              'details',
              allOf(<Matcher>[
                contains(phrase),
                contains(redacted),
                isNot(contains('u:')),
                for (final secret in secrets) isNot(contains(secret)),
              ]),
            ),
          ),
          reason: url,
        );
      }

      test('keeps the message of credential-free projector URLs', () async {
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );
        for (final message in const [
          'Failed to fetch multimodal projector: 404 Not Found',
          'Projector expects 512 tokens, got 256 at v2.',
        ]) {
          bridge.setProperty(
            'loadMultimodalProjector'.toJS,
            ((String path) => _rejectPromise(_jsError(message))).toJS,
          );
          for (final url in const [
            'https://huggingface.co/leehack/Qwen3-1.7B-head/resolve/main/'
                'mmproj.gguf?v=1',
            'https://huggingface.co/leehack/Qwen3-1.7B-head/resolve/main/'
                'mmproj.gguf?revision=main',
            'https://acct.blob.core.windows.net/heads/mmproj.gguf'
                '?sv=2022-11-02&ss=b&sig=AbCdEfGhIjKlMnOpQrStUvWxYz0123456789',
            'https://example.com/mmproj.gguf?download',
            'https://example.com:8080/mmproj.gguf?port=8080',
            'http://127.0.0.1:9/mmproj.gguf?t=1',
            'https://[::1]:8443/mmproj.gguf?x=2',
            '/heads/mmproj.gguf?token=t',
          ]) {
            await expectLater(
              backend.multimodalContextCreate(1, url),
              throwsA(
                isA<LlamaModelException>().having(
                  (error) => error.details,
                  'details',
                  message,
                ),
              ),
              reason: '$url: $message',
            );
          }
        }
        bridge.setProperty(
          'loadMultimodalProjector'.toJS,
          ((String path) => window.fetch(path.toJS)).toJS,
        );
        await expectLater(
          backend.multimodalContextCreate(1, 'http://127.0.0.1:9/m.gguf?t=1'),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => error.details,
              'details',
              'Failed to fetch',
            ),
          ),
        );
      });

      test('keeps credentials of a real Chrome fetch error out', () async {
        bridge.setProperty(
          'loadMultimodalProjector'.toJS,
          ((String path) => window.fetch(path.toJS)).toJS,
        );
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );
        const unparsable = 'Failed to parse URL from';
        for (final (url, phrase, redacted, secrets) in const [
          (
            '//u:S13@example.com/m.gguf?t=Q1',
            credentials,
            '//example.com/m.gguf',
            <String>['S13', 't=Q1'],
          ),
          (
            'https://u:S14@example.com/m.gguf#t=Q2',
            credentials,
            'https://example.com/m.gguf',
            <String>['S14', 't=Q2'],
          ),
          (
            'https://u:SEK"RIT@example.com/m.gguf',
            credentials,
            'https://example.com/m.gguf',
            <String>['SEK', 'RIT'],
          ),
          (
            'https://u:SEKRIT/w@example.com/m.gguf',
            unparsable,
            'https://example.com/m.gguf',
            <String>['SEKRIT', '/w@'],
          ),
          (
            '//u:SEKRIT/w@example.com/m.gguf',
            unparsable,
            '//example.com/m.gguf',
            <String>['SEKRIT', '/w@'],
          ),
          (
            'https://u:SEK RIT@example.com/m.gguf',
            credentials,
            'https://example.com/m.gguf',
            <String>['SEK', 'RIT'],
          ),
          (passwordUrl, credentials, 'credentials: https://', password),
          (
            'https://u:P7@example.com/h.bin?token=abc@SEKsecret',
            credentials,
            'credentials: https://example.com/h.bin',
            <String>['P7', 'abc', 'SEKsecret', 'seksecret'],
          ),
          (
            'https://u:P7@example.com/h.bin#frag@SEKsecret',
            credentials,
            'credentials: https://example.com/h.bin',
            <String>['P7', 'frag', 'SEKsecret', 'seksecret'],
          ),
          (
            'https://u:P7@example.com/path@SEKpath/h.bin',
            credentials,
            'credentials: https://example.com/path@SEKpath/h.bin',
            <String>['P7', 'sekpath'],
          ),
        ]) {
          await expectRedactedFetchError(url, phrase, redacted, secrets);
        }
      });

      test(
        'keeps credentials of a Chrome fetch error that normalises the URL out',
        () async {
          bridge.setProperty(
            'loadMultimodalProjector'.toJS,
            ((String path) => window.fetch(URL(path, document.baseURI))).toJS,
          );
          await backend.modelLoadFromUrl(
            'https://example.com/model.gguf',
            const ModelParams(),
          );
          for (final (url, redacted, secrets) in const [
            (
              'https://u:SEKRIT@ex\u00e4mple.com/m.gguf',
              'https://ex%C3%A4mple.com/m.gguf',
              <String>['SEKRIT'],
            ),
            (
              'https://u:P\u00e4ss@EXAMPLE.com/m.gguf?t=Q1',
              'https://example.com/m.gguf',
              <String>['P\u00e4ss', 'P%C3%A4ss', 'Q1'],
            ),
            (
              'HTTPS://u:SEKRIT@example.com:443/./a/../m.gguf#frag',
              'https://example.com/m.gguf',
              <String>['SEKRIT', 'frag'],
            ),
            (passwordUrl, 'credentials: https://', password),
          ]) {
            await expectRedactedFetchError(url, credentials, redacted, secrets);
          }
        },
      );
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
      bridge.setProperty('supportsVision'.toJS, (() => false).toJS);
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
      expect(warmupCallCount, 0);

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
      expect(warmupCallCount, 0);
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

    test('requires versioned bridge methods for text-to-speech', () async {
      await backend.modelLoadFromUrl(
        'https://example.com/model.gguf',
        const ModelParams(),
      );
      final mmHandle = await backend.multimodalContextCreate(
        1,
        'https://example.com/mmproj.gguf',
      );

      final capabilities = await backend.textToSpeechCapabilities(1, mmHandle!);

      expect(capabilities.isSupported, isFalse);
      expect(capabilities.unsupportedReason, contains('v0.1.33'));
    });

    test(
      'routes text-to-speech capability, progress, PCM, and bytes',
      () async {
        JSObject? capturedOptions;
        bridge.setProperty(
          'getTextToSpeechCapabilities'.toJS,
          (() {
            final result = JSObject()
              ..setProperty('apiVersion'.toJS, 1.toJS)
              ..setProperty('supported'.toJS, true.toJS)
              ..setProperty('modelType'.toJS, 1.toJS)
              ..setProperty('capabilities'.toJS, 3.toJS)
              ..setProperty('supportsLanguage'.toJS, true.toJS)
              ..setProperty('supportsSpeakerReference'.toJS, true.toJS)
              ..setProperty('sampleRate'.toJS, 24000.toJS)
              ..setProperty('channels'.toJS, 1.toJS)
              ..setProperty('reason'.toJS, ''.toJS);
            return Future<JSObject>.value(result).toJS;
          }).toJS,
        );
        bridge.setProperty(
          'synthesizeSpeech'.toJS,
          ((JSObject options) {
            capturedOptions = options;
            final progress = JSObject()
              ..setProperty('state'.toJS, 1.toJS)
              ..setProperty('promptTokensRemaining'.toJS, 4.toJS)
              ..setProperty('framesGenerated'.toJS, 2.toJS)
              ..setProperty('truncated'.toJS, false.toJS);
            final callback = options.getProperty('onProgress'.toJS);
            if (callback.isA<JSFunction>()) {
              (callback as JSFunction).callAsFunction(null, progress);
            }
            final pcm = JSFloat32Array.withLength(3);
            pcm.toDart.setAll(0, <double>[0.25, -0.5, 0.75]);
            final result = JSObject()
              ..setProperty('pcm'.toJS, pcm)
              ..setProperty('sampleRate'.toJS, 24000.toJS)
              ..setProperty('channels'.toJS, 1.toJS)
              ..setProperty('sampleCount'.toJS, 3.toJS)
              ..setProperty('framesGenerated'.toJS, 8.toJS)
              ..setProperty('truncated'.toJS, false.toJS);
            return Future<JSObject>.value(result).toJS;
          }).toJS,
        );

        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );
        final mmHandle = await backend.multimodalContextCreate(
          1,
          'https://example.com/mmproj.gguf',
        );
        final capabilities = await backend.textToSpeechCapabilities(
          1,
          mmHandle!,
        );
        final progress = <BackendTextToSpeechProgress>[];
        final result = await backend.synthesizeTextToSpeech(
          1,
          mmHandle,
          BackendTextToSpeechRequest(
            text: 'Hello from Web.',
            language: 'en',
            speakerAudioBytes: Uint8List.fromList(<int>[1, 2, 3]),
            promptBatchSize: 128,
            maxFrames: 64,
            topK: 20,
            topP: 0.9,
            minP: 0.1,
            temperature: 0.7,
            seed: 7,
          ),
          onProgress: progress.add,
        );

        expect(capabilities.isSupported, isTrue);
        expect(capabilities.model, BackendTextToSpeechModel.qwen3Tts);
        expect(capabilities.sampleRateHz, 24000);
        expect(capabilities.supportsSpeakerReference, isTrue);
        expect(progress, hasLength(1));
        expect(
          progress.single.phase,
          BackendTextToSpeechPhase.processingPrompt,
        );
        expect(progress.single.promptTokensRemaining, 4);
        expect(result.samples, <double>[0.25, -0.5, 0.75]);
        expect(result.sampleRateHz, 24000);
        expect(result.framesGenerated, 8);
        expect(
          (capturedOptions!.getProperty('speakerAudio'.toJS) as JSUint8Array)
              .toDart,
          <int>[1, 2, 3],
        );
        expect(
          (capturedOptions!.getProperty('language'.toJS) as JSString).toDart,
          'en',
        );
      },
    );

    test(
      'public TTS startup cancellation preserves another active generation',
      () async {
        final engine = LlamaEngine(backend);
        addTearDown(engine.dispose);
        await engine.loadModelFromUrl('https://example.com/model.gguf');
        await engine.loadMultimodalProjector('https://example.com/mmproj.gguf');
        final firstProbe = Completer<JSObject>();
        final secondProbe = Completer<JSObject>();
        final secondProbeStarted = Completer<void>();
        final activeStarted = Completer<void>();
        final activeCompletion = Completer<JSString>();
        var capabilityCalls = 0;
        var synthesizeCalls = 0;
        final capabilities = JSObject()
          ..setProperty('apiVersion'.toJS, 1.toJS)
          ..setProperty('supported'.toJS, true.toJS)
          ..setProperty('modelType'.toJS, 1.toJS)
          ..setProperty('supportsLanguage'.toJS, true.toJS)
          ..setProperty('sampleRate'.toJS, 24000.toJS)
          ..setProperty('channels'.toJS, 1.toJS);
        bridge.setProperty(
          'getTextToSpeechCapabilities'.toJS,
          (() {
            capabilityCalls++;
            if (capabilityCalls == 1) return firstProbe.future.toJS;
            secondProbeStarted.complete();
            return secondProbe.future.toJS;
          }).toJS,
        );
        bridge.setProperty(
          'createCompletion'.toJS,
          ((String prompt, JSObject options) {
            activeStarted.complete();
            return activeCompletion.future.toJS;
          }).toJS,
        );
        bridge.setProperty(
          'synthesizeSpeech'.toJS,
          ((JSObject options) {
            synthesizeCalls++;
            return Future<JSAny?>.error(
              StateError('unexpected synthesis'),
            ).toJS;
          }).toJS,
        );
        bridge.setProperty(
          'cancel'.toJS,
          (() {
            cancelCallCount++;
            if (!activeCompletion.isCompleted) {
              activeCompletion.complete('cut short'.toJS);
            }
          }).toJS,
        );
        final speech = TextToSpeechEngine.attach(
          engine,
          adapter: const Qwen3TtsAdapter(),
        );
        addTearDown(speech.dispose);
        final taskFuture = speech.synthesize(
          const TextToSpeechRequest(text: 'Queued speech.'),
        );
        final other = engine.generate('other request').join();
        await activeStarted.future;
        firstProbe.complete(capabilities);
        final task = await taskFuture;
        final events = task.events.toList();
        await secondProbeStarted.future;
        task.cancel();
        secondProbe.complete(capabilities);
        expect((await task.done).state, TextToSpeechCompletionState.cancelled);
        expect((await events).whereType<TextToSpeechFinalEvent>(), isEmpty);
        if (!activeCompletion.isCompleted) {
          activeCompletion.complete('kept alive'.toJS);
        }
        expect(await other, 'kept alive');
        expect(synthesizeCalls, 0);
        expect(cancelCallCount, 0);
      },
    );

    test(
      'rejects local speaker paths and routes active cancellation',
      () async {
        final synthesis = Completer<JSAny?>();
        late AbortSignal signal;
        bridge.setProperty(
          'getTextToSpeechCapabilities'.toJS,
          (() {
            final result = JSObject()
              ..setProperty('apiVersion'.toJS, 1.toJS)
              ..setProperty('supported'.toJS, true.toJS)
              ..setProperty('modelType'.toJS, 1.toJS)
              ..setProperty('supportsLanguage'.toJS, true.toJS)
              ..setProperty('supportsSpeakerReference'.toJS, true.toJS)
              ..setProperty('sampleRate'.toJS, 24000.toJS)
              ..setProperty('channels'.toJS, 1.toJS);
            return Future<JSObject>.value(result).toJS;
          }).toJS,
        );
        bridge.setProperty(
          'synthesizeSpeech'.toJS,
          ((JSObject options) {
            signal = options.getProperty<AbortSignal>('signal'.toJS);
            return synthesis.future.toJS;
          }).toJS,
        );
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );
        final mmHandle = await backend.multimodalContextCreate(
          1,
          'https://example.com/mmproj.gguf',
        );

        await expectLater(
          backend.synthesizeTextToSpeech(
            1,
            mmHandle!,
            const BackendTextToSpeechRequest(
              text: 'Hello.',
              speakerAudioPath: '/tmp/speaker.wav',
            ),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );

        final active = backend.synthesizeTextToSpeech(
          1,
          mmHandle,
          const BackendTextToSpeechRequest(text: 'Cancel me.'),
        );
        await Future<void>.delayed(Duration.zero);
        backend.cancelTextToSpeech();
        expect(signal.aborted, isTrue);
        expect(cancelCallCount, 0);
        synthesis.completeError(StateError('cancelled'));
        await expectLater(active, throwsA(isA<LlamaTextToSpeechException>()));
      },
    );

    test(
      'honours cancellation requested before the capability probe resolves',
      () async {
        final capabilityProbe = Completer<JSObject>();
        var synthesizeCallCount = 0;
        bridge.setProperty(
          'getTextToSpeechCapabilities'.toJS,
          (() => capabilityProbe.future.toJS).toJS,
        );
        bridge.setProperty(
          'synthesizeSpeech'.toJS,
          ((JSObject options) {
            synthesizeCallCount += 1;
            return Completer<JSAny?>().future.toJS;
          }).toJS,
        );
        await backend.modelLoadFromUrl(
          'https://example.com/model.gguf',
          const ModelParams(),
        );
        final mmHandle = await backend.multimodalContextCreate(
          1,
          'https://example.com/mmproj.gguf',
        );

        final active = backend.synthesizeTextToSpeech(
          1,
          mmHandle!,
          const BackendTextToSpeechRequest(text: 'Cancel me.'),
        );
        backend.cancelTextToSpeech();
        expect(cancelCallCount, 0);

        capabilityProbe.complete(
          JSObject()
            ..setProperty('apiVersion'.toJS, 1.toJS)
            ..setProperty('supported'.toJS, true.toJS)
            ..setProperty('modelType'.toJS, 1.toJS)
            ..setProperty('supportsLanguage'.toJS, true.toJS)
            ..setProperty('supportsSpeakerReference'.toJS, true.toJS)
            ..setProperty('sampleRate'.toJS, 24000.toJS)
            ..setProperty('channels'.toJS, 1.toJS),
        );
        await expectLater(active, throwsA(isA<LlamaTextToSpeechException>()));
        expect(synthesizeCallCount, 0);
      },
    );
  });

  group('WebGpuLlamaBackend decision heads', () {
    late List<FakeDecisionBridge> bridges;
    late bool withDecisionApi;
    late WebGpuLlamaBackend backend;

    setUp(() {
      bridges = <FakeDecisionBridge>[];
      withDecisionApi = true;
      backend = WebGpuLlamaBackend(
        bridgeFactory: ([config]) {
          final fake = FakeDecisionBridge(
            withDecisionApi: withDecisionApi,
            withModelApi: true,
          );
          bridges.add(fake);
          return fake.bridge;
        },
      );
    });

    tearDown(() => backend.dispose());

    Future<void> loadModel() => backend.modelLoadFromUrl(
      'laya-Q8_0.gguf',
      const ModelParams(contextSize: 512),
    );

    final sequence = BackendDecisionSequence(
      tokens: Int32List.fromList([1, 3, 20, 2]),
      markers: Int32List.fromList([1]),
      questionType: DecisionQuestionType.choice,
    );

    test('reports no model before a bridge is active', () async {
      expect(backend, isA<BackendDecision>());
      final capabilities = await backend.decisionCapabilities(1);

      expect(capabilities.isSupported, isFalse);
      expect(
        capabilities.unsupportedReason,
        'No model is loaded on the Web bridge. Load a ModernBERT encoder GGUF '
        'first.',
      );
      await expectLater(
        backend.decisionHeadLoad(1, 'laya-head.safetensors'),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            'No model is loaded on the Web bridge. Load the decision encoder '
                'before its head.',
          ),
        ),
      );
      await expectLater(
        backend.decisionRun(1, [sequence]),
        throwsA(isA<LlamaStateException>()),
      );
      await backend.decisionHeadFree(1);
      expect(bridges, isEmpty);
    });

    test('reports bridge assets without the decision API', () async {
      withDecisionApi = false;
      await loadModel();

      final capabilities = await backend.decisionCapabilities(1);

      expect(capabilities.isSupported, isFalse);
      expect(
        capabilities.unsupportedReason,
        contains(
          'llama-web-bridge assets v0.1.47+ with the decision API '
          '(apiVersion 1)',
        ),
      );
      await expectLater(
        backend.decisionHeadLoad(1, 'laya-head.safetensors'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('loads, runs and frees heads on the active bridge', () async {
      await loadModel();
      final fake = bridges.single;

      final capabilities = await backend.decisionCapabilities(1);
      final head = await backend.decisionHeadLoad(1, 'laya-head.safetensors');
      final outputs = await backend.decisionRun(head.handle, [sequence]);
      await backend.decisionHeadFree(head.handle);

      expect(capabilities.isSupported, isTrue);
      expect(head.handle, 1);
      expect(outputs.single.logits, [1.0]);
      expect(fake.calls, [
        'loadModel ${Uri.parse(document.baseURI).resolve('laya-Q8_0.gguf')}',
        'capabilities',
        'capabilities',
        'load ${Uri.parse(document.baseURI).resolve('laya-head.safetensors')}',
        'run 7 1',
        'free 7',
      ]);
      expect(fake.liveHandles, isEmpty);
    });

    test('frees heads with the model and never reuses handles', () async {
      await loadModel();
      final first = await backend.decisionHeadLoad(1, 'laya-head.safetensors');

      await backend.modelFree(1);
      await expectLater(
        backend.decisionRun(first.handle, [sequence]),
        throwsA(isA<LlamaStateException>()),
      );
      await backend.decisionHeadFree(first.handle);

      await loadModel();
      await expectLater(
        backend.decisionRun(first.handle, [sequence]),
        throwsA(isA<LlamaStateException>()),
      );
      final second = await backend.decisionHeadLoad(1, 'laya-head.safetensors');

      expect(bridges, hasLength(2));
      expect(bridges.first.disposeCalls, 1);
      expect(
        bridges.first.calls.where((call) => call.startsWith('free')),
        isEmpty,
      );
      expect(second.handle, 2);
      expect(
        bridges.last.calls.where((call) => call.startsWith('run')),
        isEmpty,
      );
    });

    test('forgets heads when a model reloads on the same bridge', () async {
      await loadModel();
      final head = await backend.decisionHeadLoad(1, 'laya-head.safetensors');

      await loadModel();

      expect(bridges, hasLength(1));
      await expectLater(
        backend.decisionRun(head.handle, [sequence]),
        throwsA(isA<LlamaStateException>()),
      );
      expect(
        bridges.single.calls.where((call) => call.startsWith('run')),
        isEmpty,
      );
    });

    test('forgets heads on dispose', () async {
      await loadModel();
      final head = await backend.decisionHeadLoad(1, 'laya-head.safetensors');

      await backend.dispose();

      await expectLater(
        backend.decisionRun(head.handle, [sequence]),
        throwsA(isA<LlamaStateException>()),
      );
      await backend.decisionHeadFree(head.handle);
      expect(bridges.single.disposeCalls, 1);
      expect(
        bridges.single.calls.where((call) => call.startsWith('free')),
        isEmpty,
      );
    });
  });

  group('WebGpuLlamaBackend optional generation features', () {
    late List<FakeFeatureBridge> bridges;
    late FakeFeatureBridge Function() newBridge;
    late WebGpuLlamaBackend backend;

    FakeFeatureBridge fake() => bridges.last;

    setUp(() {
      bridges = <FakeFeatureBridge>[];
      newBridge = FakeFeatureBridge.new;
      backend = WebGpuLlamaBackend(
        bridgeFactory: ([config]) {
          final created = newBridge();
          bridges.add(created);
          return created.bridge;
        },
      );
    });

    tearDown(() => backend.dispose());

    Future<void> loadModel() =>
        backend.modelLoadFromUrl('model.gguf', const ModelParams());

    Future<String> generate(GenerationParams params) async {
      final chunks = await backend.generate(1, 'Hello', params).toList();
      return utf8.decode(chunks.expand((chunk) => chunk).toList());
    }

    group('audit runtime and scoring regression', () {
      for (final worker in [false, true]) {
        for (final (label, directError, message)
            in <(String, JSObject, String)>[
              ('network', _jsTypeError('Failed to fetch'), 'Failed to fetch'),
              (
                'stack',
                _jsRangeError('Maximum call stack size exceeded'),
                'Maximum call stack size exceeded',
              ),
            ]) {
          for (final operation in [
            'lora',
            'generate',
            'speculative',
            'embed',
            'embedBatch',
            'scoreNextToken',
          ]) {
            test(
              '$operation keeps $label failure category (worker=$worker)',
              () async {
                await loadModel();
                final method = switch (operation) {
                  'lora' => 'loadLoraAdapter',
                  'generate' || 'speculative' => 'createCompletion',
                  _ => operation,
                };
                fake().object.setProperty(
                  method.toJS,
                  ((JSAny? _, JSAny? _) => _rejectPromise(
                    worker ? _jsError(message) : directError,
                  )).toJS,
                );
                final Future<Object?> result = switch (operation) {
                  'lora' => backend.setLoraAdapter(1, 'adapter.gguf', 1),
                  'generate' =>
                    backend
                        .generate(1, 'hi', const GenerationParams())
                        .toList(),
                  'speculative' =>
                    backend
                        .generate(
                          1,
                          'hi',
                          const GenerationParams(
                            speculativeDecodingConfig:
                                SpeculativeDecodingConfig.ngramSimple(),
                          ),
                        )
                        .toList(),
                  'embed' => backend.embed(1, 'hi'),
                  'embedBatch' => backend.embedBatch(1, ['hi']),
                  _ => backend.scoreNextToken(
                    1,
                    'hi',
                    candidates: [1],
                    topK: 0,
                    reusePromptPrefix: false,
                  ),
                };
                await expectLater(
                  result,
                  throwsA(
                    operation == 'lora'
                        ? isA<LlamaModelException>()
                        : isA<LlamaInferenceException>(),
                  ),
                );
              },
            );
          }
        }
      }

      test('scoring bounds preserve the shared RangeError contract', () async {
        await loadModel();
        fake().object.setProperty(
          'scoreNextToken'.toJS,
          ((JSAny? _, JSAny? _) => JSObject()).toJS,
        );
        for (final (candidates, topK) in <(List<int>, int)>[
          ([-1], 0),
          ([0x80000000], 0),
          ([1], -1),
          ([1], 0x80000000),
        ]) {
          await expectLater(
            backend.scoreNextToken(
              1,
              'hi',
              candidates: candidates,
              topK: topK,
              reusePromptPrefix: false,
            ),
            throwsRangeError,
          );
        }
      });

      for (final worker in [false, true]) {
        test(
          'scoring vocabulary preserves RangeError (worker=$worker)',
          () async {
            await loadModel();
            const message =
                'Next-token scoring failed: Token id 99 is outside the vocabulary of 32 tokens';
            fake().object.setProperty(
              'scoreNextToken'.toJS,
              ((JSAny? _, JSAny? _) => _rejectPromise(
                worker ? _jsError(message) : _jsRangeError(message),
              )).toJS,
            );
            await expectLater(
              backend.scoreNextToken(
                1,
                'hi',
                candidates: [99],
                topK: 0,
                reusePromptPrefix: false,
              ),
              throwsRangeError,
            );
          },
        );
      }
    });

    group('argument rejection regression', () {
      test('public generation preserves Dart argument validation', () async {
        final engine = LlamaEngine(backend);
        await engine.loadModelFromUrl('model.gguf');
        await expectLater(
          engine
              .generate(
                'hello',
                params: const GenerationParams(
                  speculativeDecodingConfig:
                      SpeculativeDecodingConfig.ngramSimple(
                        ngramSizeN: 0x10000,
                      ),
                ),
              )
              .toList(),
          throwsA(
            isA<LlamaArgumentException>().having(
              (error) => error.name,
              'name',
              'ngramSizeN',
            ),
          ),
        );
        expect(fake().completionCalls, 0);
      });

      for (final (label, rejection, matcher) in <(String, JSObject, Matcher)>[
        (
          'range',
          _jsRangeError(
            'CompletionOptions.minP must be a finite number from 0 to 1; got 2.',
          ),
          isA<LlamaArgumentException>(),
        ),
        (
          'worker',
          _jsError(
            'CompletionOptions.speculativeDecoding.draftTokenMin (9) must not exceed the draft token maximum (3).',
          ),
          isA<LlamaArgumentException>(),
        ),
        (
          'runtime',
          _jsError('GPU dispatch failed'),
          isA<LlamaInferenceException>(),
        ),
      ]) {
        for (final operation in [
          'generate',
          'speculative',
          'embed',
          'embedBatch',
          'scoreNextToken',
        ]) {
          test('$operation classifies $label bridge rejection', () async {
            await loadModel();
            final method = switch (operation) {
              'generate' || 'speculative' => 'createCompletion',
              _ => operation,
            };
            fake().object.setProperty(
              method.toJS,
              ((JSAny? _, JSAny? _) => _rejectPromise(rejection)).toJS,
            );
            final Future<Object?> result = switch (operation) {
              'generate' =>
                backend.generate(1, 'hello', const GenerationParams()).toList(),
              'speculative' =>
                backend
                    .generate(
                      1,
                      'hello',
                      const GenerationParams(
                        speculativeDecodingConfig:
                            SpeculativeDecodingConfig.ngramSimple(),
                      ),
                    )
                    .toList(),
              'embed' => backend.embed(1, 'hello'),
              'embedBatch' => backend.embedBatch(1, ['hello']),
              _ => backend.scoreNextToken(
                1,
                'hello',
                candidates: [1],
                topK: 0,
                reusePromptPrefix: false,
              ),
            };
            await expectLater(result, throwsA(matcher));
          });
        }
      }

      test(
        'LoRA bridge argument rejection stays an argument exception',
        () async {
          await loadModel();
          fake().object.setProperty(
            'setLoraAdapter'.toJS,
            ((JSAny? _, JSAny? _) => _rejectPromise(
              _jsTypeError(
                'LoRA adapter scale must be a finite number, got NaN.',
              ),
            )).toJS,
          );
          await expectLater(
            backend.setLoraAdapter(1, 'adapter.gguf', 1),
            throwsA(isA<LlamaArgumentException>()),
          );
        },
      );
    });

    const thinkingBudget = ThinkingBudget(
      maxTokens: 8,
      startTag: '<think>',
      endTag: '</think>',
    );

    final rejectsPresencePenalty = throwsA(
      isA<UnsupportedError>().having(
        (error) => '${error.message}',
        'message',
        allOf(contains('presence penalty'), contains('presencePenalty')),
      ),
    );
    final rejectsMinP = throwsA(
      isA<LlamaUnsupportedException>().having(
        (error) => error.message,
        'message',
        allOf(contains('Min-P'), contains('GenerationParams.minP')),
      ),
    );
    final rejectsThinkingBudget = throwsA(
      isA<UnsupportedError>().having(
        (error) => '${error.message}',
        'message',
        allOf(contains('thinking-budget control'), contains('thinkingBudget')),
      ),
    );

    void expectEachOptionRejected() {
      expect(
        () => backend.generate(
          1,
          'Hello',
          const GenerationParams(presencePenalty: 1.5),
        ),
        rejectsPresencePenalty,
      );
      expect(
        () => backend.generate(1, 'Hello', const GenerationParams(minP: 0.05)),
        rejectsMinP,
      );
      expect(
        () => backend.generate(
          1,
          'Hello',
          const GenerationParams(thinkingBudget: thinkingBudget),
        ),
        rejectsThinkingBudget,
      );
    }

    group('completion options', () {
      test('engine capabilities follow the loaded assets', () async {
        final engine = LlamaEngine(backend);
        expect((await engine.capabilities).isSupported, isFalse);

        newBridge = () =>
            FakeFeatureBridge()
              ..completionCapabilities = <String, bool>{'minP': true};
        await engine.loadModelFromUrl('model.gguf');
        final capabilities = await engine.capabilities;

        expect(engine.runtime, LlamaRuntime.llamaCpp);
        expect(capabilities.runtime, LlamaRuntime.llamaCpp);
        expect(capabilities.supportsMultiTurnChat, isTrue);
        expect(capabilities.supportsToolCalling, isTrue);
        expect(capabilities.supportsGrammar, isTrue);
        expect(capabilities.supportsStructuredOutput, isTrue);
        expect(capabilities.supportsLazyGrammar, isFalse);
        expect(capabilities.supportsPenalty, isTrue);
        expect(capabilities.supportsMinP, isTrue);
        expect(capabilities.supportsPresencePenalty, isFalse);
        expect(capabilities.supportsThinkingBudget, isFalse);
        expect(capabilities.supportsStreamBatching, isFalse);
        expect(capabilities.supportsVision, isFalse);

        await engine.unloadModel();
        expect(engine.runtime, isNull);
        expect((await engine.capabilities).supportsPenalty, isFalse);
      });

      test('forwards the options the loaded assets report', () async {
        await loadModel();
        await generate(
          const GenerationParams(
            minP: 0.05,
            presencePenalty: 1.5,
            thinkingBudget: ThinkingBudget(
              maxTokens: 8,
              startTag: '<think>',
              endTag: '</think>',
              forcedMessage: 'Done.',
            ),
          ),
        );

        expect(fake().calls, <String>['load', 'probe']);
        expect(fake().completionOption('minP'), 0.05);
        expect(fake().completionOption('presencePenalty'), 1.5);
        expect(fake().completionOption('thinkingBudget'), <String, Object?>{
          'maxTokens': 8,
          'startTag': '<think>',
          'endTag': '</think>',
          'forcedMessage': 'Done.',
        });

        await generate(const GenerationParams(thinkingBudget: thinkingBudget));
        expect(
          fake().completionOption('thinkingBudget'),
          containsPair('forcedMessage', ''),
        );
      });

      test('sends default options as before', () async {
        for (final withProbe in <bool>[true, false]) {
          newBridge = () => FakeFeatureBridge(withCompletionProbe: withProbe);
          await loadModel();
          expect(await generate(const GenerationParams()), 'Hello');
          for (final name in <String>[
            'minP',
            'presencePenalty',
            'thinkingBudget',
          ]) {
            expect(
              fake().completionOption(name),
              isNull,
              reason: '$name, probe: $withProbe',
            );
          }
          await backend.modelFree(1);
        }
      });

      group('penaltyPromptTokensWithGrammar', () {
        const params = GenerationParams(grammar: 'root ::= "hello"');

        test(
          'probe controls the explicit route and resets on unload',
          () async {
            expect(backend.supportsPromptPenaltiesWithGrammar, isFalse);
            newBridge = () => FakeFeatureBridge()
              ..completionCapabilities = <String, bool>{
                'penaltyPromptTokensWithGrammar': true,
              };
            await loadModel();
            expect(backend.supportsPromptPenaltiesWithGrammar, isTrue);
            for (final grammar in ['', 'root ::= "hello"']) {
              await backend
                  .generateWithPromptPenalties(
                    1,
                    'Hello',
                    GenerationParams(grammar: grammar),
                  )
                  .toList();
              expect(
                fake().completionOption('penaltyPromptTokensWithGrammar'),
                isTrue,
              );
              expect(fake().completionOption('grammar'), grammar);
              expect(
                fake().hasCompletionOption('penaltyPromptTokens'),
                isFalse,
              );
            }
            await generate(params);
            expect(
              fake().hasCompletionOption('penaltyPromptTokensWithGrammar'),
              isFalse,
            );
            await backend.modelFree(1);
            expect(backend.supportsPromptPenaltiesWithGrammar, isFalse);
          },
        );

        test(
          'rejects missing, false and nonboolean loaded-core reports',
          () async {
            final bridges = <FakeFeatureBridge Function()>[
              () => FakeFeatureBridge(withCompletionProbe: false),
              FakeFeatureBridge.new,
              () => FakeFeatureBridge()
                ..completionCapabilities = <String, bool>{
                  'penaltyPromptTokensWithGrammar': false,
                },
              () => FakeFeatureBridge()
                ..completionCapabilitiesResult = (JSObject()
                  ..setProperty(
                    'penaltyPromptTokensWithGrammar'.toJS,
                    'true'.toJS,
                  )),
            ];
            for (final create in bridges) {
              newBridge = create;
              await loadModel();
              expect(backend.supportsPromptPenaltiesWithGrammar, isFalse);
              expect(
                () => backend.generateWithPromptPenalties(1, 'Hello', params),
                throwsA(isA<LlamaUnsupportedException>()),
              );
              expect(fake().completionCalls, 0);
              await backend.modelFree(1);
            }
          },
        );

        test('keeps lazy grammar options and typed runtime refusal', () async {
          newBridge = () => FakeFeatureBridge()
            ..completionCapabilities = <String, bool>{
              'penaltyPromptTokensWithGrammar': true,
              'lazyGrammar': true,
            };
          await loadModel();
          const lazy = GenerationParams(
            grammar: 'root ::= "hello"',
            grammarLazy: true,
            grammarTriggers: [
              GenerationGrammarTrigger.typed(
                type: GrammarTriggerType.word,
                value: 'hello',
              ),
            ],
          );
          await backend.generateWithPromptPenalties(1, 'Hello', lazy).toList();
          expect(fake().completionOption('grammarLazy'), isTrue);
          expect(fake().completionOption('grammarTriggers'), [
            {'type': 'word', 'value': 'hello'},
          ]);
          fake().object.setProperty(
            'createCompletion'.toJS,
            ((JSAny? _, JSAny? _) => _rejectPromise(
              _jsError(
                'The loaded WebGPU core does not support CompletionOptions.penaltyPromptTokensWithGrammar.',
              ),
            )).toJS,
          );
          await expectLater(
            backend.generateWithPromptPenalties(1, 'Hello', lazy).toList(),
            throwsA(isA<LlamaUnsupportedException>()),
          );
        });

        for (final (index, media) in <LlamaContentPart>[
          const LlamaImageContent(),
          LlamaImageContent(bytes: Uint8List(0)),
          LlamaImageContent(bytes: Uint8List.fromList([1, 2, 3])),
          const LlamaAudioContent(),
          LlamaAudioContent(bytes: Uint8List(0)),
          LlamaAudioContent(samples: Float32List(0)),
          LlamaAudioContent(samples: Float32List.fromList([0.1])),
          LlamaVideoContent(bytes: Uint8List(0)),
        ].indexed) {
          test(
            'rejects typed media before generation: ${media.runtimeType} case $index',
            () async {
              newBridge = () => FakeFeatureBridge()
                ..completionCapabilities = <String, bool>{
                  'penaltyPromptTokensWithGrammar': true,
                };
              await loadModel();
              expect(
                () => backend.generateWithPromptPenalties(
                  1,
                  'Hello',
                  params,
                  parts: [media],
                ),
                throwsA(
                  isA<LlamaUnsupportedException>().having(
                    (error) => error.message,
                    'message',
                    contains('text-only'),
                  ),
                ),
              );
              expect(fake().completionCalls, 0);
            },
          );
        }

        test(
          'rejects absent grammar and conflicting penalty exclusion before inference',
          () async {
            newBridge = () => FakeFeatureBridge()
              ..completionCapabilities = <String, bool>{
                'penaltyPromptTokensWithGrammar': true,
              };
            await loadModel();
            final excluded = GenerationParams(grammar: params.grammar);
            markPromptExcludedFromPenalties(excluded);
            for (final invalid in [const GenerationParams(), excluded]) {
              expect(
                () => backend.generateWithPromptPenalties(1, 'Hello', invalid),
                throwsA(isA<LlamaUnsupportedException>()),
              );
            }
            expect(fake().completionCalls, 0);
          },
        );
      });

      group('penaltyPromptTokens', () {
        GenerationParams marked([String? grammar]) {
          final params = GenerationParams(grammar: grammar);
          markPromptExcludedFromPenalties(params);
          return params;
        }

        FakeFeatureBridge reportingBridge() => FakeFeatureBridge()
          ..completionCapabilities = <String, bool>{
            'penaltyPromptTokens': true,
          };

        test('sends false only for a marked request', () async {
          newBridge = reportingBridge;
          await loadModel();

          await generate(marked());
          expect(fake().hasCompletionOption('penaltyPromptTokens'), isTrue);
          expect(fake().completionOption('penaltyPromptTokens'), isFalse);

          await generate(const GenerationParams());
          expect(fake().hasCompletionOption('penaltyPromptTokens'), isFalse);
        });

        test('sends nothing on assets that do not report it', () async {
          final unreported = <FakeFeatureBridge Function()>[
            () => FakeFeatureBridge(withCompletionProbe: false),
            FakeFeatureBridge.new,
            () =>
                FakeFeatureBridge()
                  ..completionCapabilitiesResult = (JSObject()
                    ..setProperty('penaltyPromptTokens'.toJS, 'true'.toJS)),
          ];
          for (final (index, create) in unreported.indexed) {
            newBridge = create;
            await loadModel();

            expect(await generate(marked()), 'Hello');
            expect(
              fake().hasCompletionOption('penaltyPromptTokens'),
              isFalse,
              reason: 'bridge $index',
            );
            await backend.modelFree(1);
          }
        });

        test('passes the grammar through unchanged, empty included', () async {
          newBridge = reportingBridge;
          await loadModel();

          for (final grammar in <String?>[null, '', 'root ::= "a"']) {
            for (final params in <GenerationParams>[
              marked(grammar),
              GenerationParams(grammar: grammar),
            ]) {
              await generate(params);
              expect(fake().completionOption('grammar'), grammar);
            }
          }
        });
      });

      test('rejects every option on assets without the probe', () async {
        newBridge = () => FakeFeatureBridge(withCompletionProbe: false);
        await loadModel();

        expectEachOptionRejected();
        expect(fake().completionCalls, 0);
      });

      test('rejects each option the probe does not report', () async {
        newBridge = () => FakeFeatureBridge()
          ..completionCapabilities = <String, bool>{
            'presencePenalty': false,
            'minP': true,
            'thinkingBudget': false,
          };
        await loadModel();

        expect(
          () => backend.generate(
            1,
            'Hello',
            const GenerationParams(presencePenalty: 1.5),
          ),
          rejectsPresencePenalty,
        );
        expect(
          () => backend.generate(
            1,
            'Hello',
            const GenerationParams(thinkingBudget: thinkingBudget),
          ),
          rejectsThinkingBudget,
        );
        expect(fake().completionCalls, 0);

        await generate(const GenerationParams(minP: 0.05));
        expect(fake().completionOption('minP'), 0.05);
      });

      test('rejects every option after a failed or malformed probe', () async {
        final probes = <void Function(FakeFeatureBridge)>[
          (bridge) => bridge.completionProbeError = 'Bridge has been disposed.',
          (bridge) => bridge.completionCapabilitiesResult = 'all'.toJS,
          (bridge) => bridge.completionCapabilitiesResult = JSObject()
            ..setProperty('minP'.toJS, 'true'.toJS)
            ..setProperty('presencePenalty'.toJS, 1.toJS),
        ];
        for (final breakProbe in probes) {
          newBridge = () {
            final created = FakeFeatureBridge();
            breakProbe(created);
            return created;
          };
          await loadModel();
          expect(backend.isReady, isTrue);
          expectEachOptionRejected();
          expect(fake().completionCalls, 0);
          await backend.modelFree(1);
        }
      });

      test('rejects every option before a model load', () {
        expectEachOptionRejected();
        expect(bridges, isEmpty);
      });

      test('probes again on each load and forgets on free', () async {
        await loadModel();
        await generate(const GenerationParams(minP: 0.05));

        fake().completionCapabilities = <String, bool>{};
        await loadModel();
        expectEachOptionRejected();

        fake().completionCapabilities = <String, bool>{'minP': true};
        await loadModel();
        await generate(const GenerationParams(minP: 0.05));

        await backend.modelFree(1);
        expect(
          () =>
              backend.generate(1, 'Hello', const GenerationParams(minP: 0.05)),
          rejectsMinP,
        );
      });

      test('reports the options the probe reports as capabilities', () async {
        Future<List<bool>> reported() async {
          final capabilities = await backend.generationCapabilities();
          expect(capabilities.streamBatching, isFalse);
          return <bool>[
            capabilities.penalty,
            capabilities.presencePenalty,
            capabilities.minP,
            capabilities.thinkingBudget,
          ];
        }

        expect(await reported(), <bool>[false, false, false, false]);

        await loadModel();
        expect(await reported(), <bool>[true, true, true, true]);

        fake().completionCapabilities = <String, bool>{'minP': true};
        await loadModel();
        expect(await reported(), <bool>[true, false, true, false]);

        await backend.modelFree(1);
        expect(await reported(), <bool>[false, false, false, false]);

        newBridge = () => FakeFeatureBridge(withCompletionProbe: false);
        await loadModel();
        expect(await reported(), <bool>[true, false, false, false]);
      });

      test('validates a thinking budget as native generation does', () async {
        await loadModel();

        for (final budget in const <ThinkingBudget>[
          ThinkingBudget(maxTokens: 8),
          ThinkingBudget(maxTokens: 8, startTag: '<think>', endTag: ' '),
        ]) {
          expect(
            () => backend.generate(
              1,
              'Hello',
              GenerationParams(thinkingBudget: budget),
            ),
            throwsA(
              isA<LlamaArgumentException>().having(
                (error) => error.message,
                'message',
                contains('non-empty startTag and endTag'),
              ),
            ),
          );
        }
        expect(
          () => backend.generate(
            1,
            'Hello',
            const GenerationParams(
              thinkingBudget: ThinkingBudget(
                maxTokens: 0x80000000,
                startTag: '<think>',
                endTag: '</think>',
              ),
            ),
          ),
          throwsA(isA<LlamaArgumentException>()),
        );

        await backend.multimodalContextCreate(1, 'mmproj.gguf');
        expect(
          () => backend.generate(
            1,
            'Describe',
            const GenerationParams(thinkingBudget: thinkingBudget),
            parts: <LlamaContentPart>[
              LlamaImageContent(bytes: Uint8List.fromList(<int>[1, 2, 3])),
            ],
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              contains('text-only'),
            ),
          ),
        );
        expect(fake().completionCalls, 0);
      });

      test('LlamaEngine reports rejections as unsupported', () async {
        newBridge = () => FakeFeatureBridge(withCompletionProbe: false);
        final engine = LlamaEngine(backend);
        await engine.loadModelFromUrl('model.gguf');

        for (final params in const <GenerationParams>[
          GenerationParams(presencePenalty: 1.5),
          GenerationParams(minP: 0.05),
          GenerationParams(thinkingBudget: thinkingBudget),
        ]) {
          await expectLater(
            engine.generate('Hello', params: params).toList(),
            throwsA(isA<LlamaUnsupportedException>()),
          );
        }
        expect(fake().completionCalls, 0);
      });
    });

    group('preserved tokens', () {
      setUp(() async {
        await loadModel();
        fake().completionPieces = <String>['a', '<tool_call>', 'b'];
      });

      test('keep a stop sequence equal to one from ending output', () async {
        expect(
          await generate(
            const GenerationParams(
              stopSequences: <String>['<tool_call>'],
              preservedTokens: <String>['<tool_call>'],
            ),
          ),
          'a<tool_call>b',
        );
      });

      test('leave other stop sequences in effect', () async {
        expect(
          await generate(
            const GenerationParams(
              stopSequences: <String>['<tool_call>', 'b'],
              preservedTokens: <String>['<tool_call>'],
            ),
          ),
          'a<tool_call>',
        );
        expect(
          await generate(
            const GenerationParams(
              stopSequences: <String>['<tool_call>'],
              preservedTokens: <String>['<tool'],
            ),
          ),
          'a',
        );
      });
    });

    group('LoRA adapters', () {
      test('applies adapters through the active bridge', () async {
        await loadModel();
        await backend.setLoraAdapter(1, 'adapter.gguf', 0.5);
        await backend.setLoraAdapter(1, 'other.gguf', 0.25);
        await backend.removeLoraAdapter(1, 'adapter.gguf');
        expect(fake().appliedAdapters, <int, double>{8: 0.25});

        await backend.clearLoraAdapters(1);
        expect(fake().appliedAdapters, isEmpty);
        expect(fake().loraLoads, hasLength(2));
      });

      test('loads adapters again after a model load', () async {
        await loadModel();
        await backend.setLoraAdapter(1, 'adapter.gguf', 0.5);
        await loadModel();
        await backend.setLoraAdapter(1, 'adapter.gguf', 0.5);

        expect(fake().loraLoads, hasLength(2));
        expect(fake().appliedAdapters, <int, double>{8: 0.5});
      });

      test('rejects every call without a model', () async {
        await loadModel();
        await backend.setLoraAdapter(1, 'adapter.gguf', 0.5);
        await backend.modelFree(1);

        for (final call in <Future<void> Function()>[
          () => backend.setLoraAdapter(1, 'adapter.gguf', 0.5),
          () => backend.removeLoraAdapter(1, 'adapter.gguf'),
          () => backend.clearLoraAdapters(1),
        ]) {
          await expectLater(
            call(),
            throwsA(
              isA<UnsupportedError>().having(
                (error) => '${error.message}',
                'message',
                contains('no model is loaded'),
              ),
            ),
          );
        }
      });

      test('LlamaEngine maps the bridge errors', () async {
        final engine = LlamaEngine(backend);
        await engine.loadModelFromUrl('model.gguf');
        fake().loraLoadError =
            'Failed to load LoRA adapter: the adapter is an aLoRA adapter (3 '
            'invocation token(s)).';
        await expectLater(
          engine.setLora('alora.gguf'),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        fake().loraLoadError =
            "Failed to load LoRA adapter: tensor 'blk.0.attn_k.weight' has "
            'incorrect shape (hint: maybe wrong base model?)';
        await expectLater(
          engine.setLora('adapter.gguf'),
          throwsA(isA<LlamaModelException>()),
        );
        fake().loraLoadError = null;
        await engine.setLora('adapter.gguf', scale: 0.5);
        expect(fake().appliedAdapters.values, <double>[0.5]);

        newBridge = () => FakeFeatureBridge(withLoraApi: false);
        await engine.unloadModel();
        await engine.loadModelFromUrl('model.gguf');
        for (final call in <Future<void> Function()>[
          () => engine.setLora('adapter.gguf'),
          () => engine.removeLora('adapter.gguf'),
          engine.clearLoras,
        ]) {
          await expectLater(
            call(),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'message',
                allOf(contains('lack the LoRA methods'), contains('v0.1.54+')),
              ),
            ),
          );
        }
      });

      const modelParamsLoras = ModelParams(
        loras: [
          LoraAdapterConfig(path: 'style.gguf', scale: 0.5),
          LoraAdapterConfig(path: 'domain.gguf'),
        ],
      );

      test('contextCreate applies ModelParams.loras at their scales', () async {
        await loadModel();
        expect(await backend.contextCreate(1, modelParamsLoras), 1);

        expect(fake().loraLoads.map((load) => load.source), <String>[
          '${Uri.parse(document.baseURI).resolve('style.gguf')}',
          '${Uri.parse(document.baseURI).resolve('domain.gguf')}',
        ]);
        expect(fake().appliedAdapters, <int, double>{7: 0.5, 8: 1.0});
      });

      test('LlamaEngine applies ModelParams.loras on every load', () async {
        final engine = LlamaEngine(backend);
        await engine.loadModelFromUrl(
          'model.gguf',
          modelParams: modelParamsLoras,
        );
        expect(fake().appliedAdapters.values, <double>[0.5, 1.0]);

        await engine.unloadModel();
        await engine.loadModelFromUrl(
          'model.gguf',
          modelParams: modelParamsLoras,
        );
        expect(bridges, hasLength(2));
        expect(fake().appliedAdapters.values, <double>[0.5, 1.0]);

        await engine.unloadModel();
        await engine.loadModelFromUrl('model.gguf');
        expect(fake().loraLoads, isEmpty);
        await engine.unloadModel();
      });

      test('a failing ModelParams.loras adapter rolls back the load', () async {
        const signed = 'https://example.com/domain.gguf?token=secret';
        newBridge = () => FakeFeatureBridge()
          ..loraLoadErrorsBySource[signed] =
              "Failed to load LoRA adapter: tensor 'blk.0.attn_k.weight' has "
              'incorrect shape (hint: maybe wrong base model?)';
        final engine = LlamaEngine(backend);

        await expectLater(
          engine.loadModelFromUrl(
            'model.gguf',
            modelParams: const ModelParams(
              loras: [
                LoraAdapterConfig(path: 'style.gguf', scale: 0.5),
                LoraAdapterConfig(path: signed),
              ],
            ),
          ),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => error.toString(),
              'toString',
              allOf(
                contains('ModelParams.loras adapter'),
                contains('domain.gguf'),
                contains('incorrect shape'),
                isNot(contains('secret')),
              ),
            ),
          ),
        );
        expect(engine.isReady, isFalse);
        expect(fake().calls, contains('lora:clear'));
        expect(fake().calls.last, 'dispose');
        expect(fake().appliedAdapters, isEmpty);
      });

      test('bridge assets without runtime LoRA reject ModelParams.loras '
          'before loading an adapter', () async {
        final engine = LlamaEngine(backend);
        for (final older in <FakeFeatureBridge Function()>[
          () => FakeFeatureBridge(withLoraApi: false),
          () => FakeFeatureBridge()..loraApiVersion = 2,
          () => FakeFeatureBridge()..loraSupported = false,
        ]) {
          newBridge = older;
          await expectLater(
            engine.loadModelFromUrl(
              'model.gguf',
              modelParams: const ModelParams(
                loras: [LoraAdapterConfig(path: 'style.gguf')],
              ),
            ),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'message',
                allOf(
                  contains('ModelParams.loras adapter style.gguf'),
                  contains('v0.1.54+'),
                ),
              ),
            ),
          );
          expect(engine.isReady, isFalse);
          expect(fake().loraLoads, isEmpty);
          expect(fake().calls.last, 'dispose');
        }

        newBridge = () => FakeFeatureBridge(withLoraApi: false);
        await engine.loadModelFromUrl('model.gguf');
        expect(engine.isReady, isTrue);
        await engine.unloadModel();
      });
    });

    group('speculative decoding', () {
      const ngram = SpeculativeDecodingConfig.ngramSimple(ngramSizeN: 3);
      const draft = SpeculativeDecodingConfig.draftSimple(
        draftModelPath: 'draft.gguf',
      );

      GenerationParams speculative(SpeculativeDecodingConfig config) =>
          GenerationParams(temp: 0, speculativeDecodingConfig: config);

      Map<String, Object?>? sentSpeculative() =>
          (fake().completionOption('speculativeDecoding') as Map?)
              ?.cast<String, Object?>();

      Future<Object?> generationError(GenerationParams params) => generate(
        params,
      ).then<Object?>((_) => null, onError: (Object error) => error);

      Matcher unsupported(Object message) => throwsA(
        isA<UnsupportedError>().having(
          (error) => '${error.message}',
          'message',
          message,
        ),
      );

      Matcher llamaUnsupported(Object message) => throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          message,
        ),
      );

      Future<Set<SpeculativeDecodingStrategy>> reported() async =>
          (await backend.generationCapabilities())
              .speculativeDecodingStrategies;

      const ngramStrategies = <SpeculativeDecodingStrategy>{
        SpeculativeDecodingStrategy.ngramSimple,
        SpeculativeDecodingStrategy.ngramMapK,
        SpeculativeDecodingStrategy.ngramMapK4v,
        SpeculativeDecodingStrategy.ngramMod,
        SpeculativeDecodingStrategy.ngramCache,
      };
      const draftStrategies = <SpeculativeDecodingStrategy>{
        SpeculativeDecodingStrategy.draftSimple,
        SpeculativeDecodingStrategy.draftEagle3,
        SpeculativeDecodingStrategy.draftDflash,
        SpeculativeDecodingStrategy.draftDspark,
      };

      test('reports the strategies the probe reports', () async {
        expect(await reported(), isEmpty);

        await loadModel();
        expect(await reported(), <SpeculativeDecodingStrategy>{
          SpeculativeDecodingStrategy.backendDefault,
          ...ngramStrategies,
          ...draftStrategies,
        });

        fake().speculativeCapabilities = <String, bool>{
          'ngram-simple': true,
          'draft-mtp': true,
        };
        await loadModel();
        expect(await reported(), <SpeculativeDecodingStrategy>{
          SpeculativeDecodingStrategy.ngramSimple,
          SpeculativeDecodingStrategy.mtp,
          ...draftStrategies,
        });

        fake().speculativeCapabilities = <String, bool>{'draft-mtp': true};
        await loadModel();
        expect(await reported(), isEmpty);

        await backend.modelFree(1);
        expect(await reported(), isEmpty);

        newBridge = () => FakeFeatureBridge(withDraftModelApi: false);
        await loadModel();
        expect(await reported(), <SpeculativeDecodingStrategy>{
          SpeculativeDecodingStrategy.backendDefault,
          ...ngramStrategies,
        });

        for (final older in <FakeFeatureBridge Function()>[
          () => FakeFeatureBridge(withCompletionProbe: false),
          () => FakeFeatureBridge()..speculativeCapabilities = null,
          () => FakeFeatureBridge()..completionProbeError = 'failed',
        ]) {
          await backend.modelFree(1);
          newBridge = older;
          await loadModel();
          expect(await reported(), isEmpty);
        }
      });

      test('rejects every strategy on assets without the probe', () async {
        for (final older in <FakeFeatureBridge Function()>[
          () => FakeFeatureBridge(withCompletionProbe: false),
          () => FakeFeatureBridge()..speculativeCapabilities = null,
          () =>
              FakeFeatureBridge()
                ..completionCapabilitiesResult = (JSObject()
                  ..setProperty('speculativeDecoding'.toJS, true.toJS)),
          () => FakeFeatureBridge()..completionProbeError = 'failed',
        ]) {
          await backend.modelFree(1);
          newBridge = older;
          await loadModel();
          for (final strategy in SpeculativeDecodingStrategy.values) {
            expect(
              () => backend.generate(
                1,
                'Hello',
                speculative(
                  SpeculativeDecodingConfig.mixed(
                    strategies: <SpeculativeDecodingStrategy>[strategy],
                    draftModelPath: 'draft.gguf',
                  ),
                ),
              ),
              unsupported(contains('the loaded assets report none')),
              reason: '$strategy',
            );
          }
          expect(
            () => backend.generate(
              1,
              'Hello',
              const GenerationParams(speculativeDecoding: true),
            ),
            unsupported(contains('getCompletionCapabilities()')),
          );
          expect(fake().completionCalls, 0);
          expect(fake().draftLoads, isEmpty);
        }
      });

      test('rejects each strategy the probe does not report', () async {
        newBridge = () =>
            FakeFeatureBridge(withDraftModelApi: false)
              ..speculativeCapabilities = <String, bool>{'ngram-simple': true};
        await loadModel();

        final messages = <SpeculativeDecodingStrategy, String>{
          SpeculativeDecodingStrategy.backendDefault: 'runs ngram-mod',
          SpeculativeDecodingStrategy.mtp: 'ModelParams(loadMtp: true)',
          SpeculativeDecodingStrategy.ngramMapK: 'ngram-map-k',
          SpeculativeDecodingStrategy.ngramMapK4v: 'ngram-map-k4v',
          SpeculativeDecodingStrategy.ngramMod: 'ngram-mod',
          SpeculativeDecodingStrategy.ngramCache: 'ngram-cache',
          SpeculativeDecodingStrategy.draftSimple: 'draft-simple',
          SpeculativeDecodingStrategy.draftEagle3: 'draft-eagle3',
          SpeculativeDecodingStrategy.draftDflash: 'draft-dflash',
          SpeculativeDecodingStrategy.draftDspark: 'draft-dspark',
        };
        for (final MapEntry(key: strategy, value: message)
            in messages.entries) {
          expect(
            () => backend.generate(
              1,
              'Hello',
              speculative(
                SpeculativeDecodingConfig.mixed(
                  strategies: <SpeculativeDecodingStrategy>[
                    SpeculativeDecodingStrategy.ngramSimple,
                    strategy,
                  ],
                ),
              ),
            ),
            unsupported(
              allOf(
                contains('WebGPU'),
                contains(message),
                contains('the loaded assets do not'),
              ),
            ),
            reason: '$strategy',
          );
        }
        expect(
          () => backend.generate(
            1,
            'Hello',
            const GenerationParams(speculativeDecoding: true),
          ),
          unsupported(contains('runs ngram-mod')),
        );
        expect(fake().completionCalls, 0);

        await generate(speculative(ngram));
        expect(
          sentSpeculative(),
          containsPair('strategies', <String>['ngram-simple']),
        );
      });

      test('sends each n-gram strategy with native options', () async {
        await loadModel();

        final cases = <SpeculativeDecodingConfig, Map<String, Object?>>{
          const SpeculativeDecodingConfig.ngramSimple(
            ngramSize: 3,
            ngramSizeM: 8,
            ngramMinHits: 2,
          ): <String, Object?>{
            'strategies': <String>['ngram-simple'],
            'ngramSizeN': 3,
            'ngramSizeM': 8,
            'ngramMinHits': 2,
          },
          const SpeculativeDecodingConfig.ngramMapK(
            draftTokenMax: 6,
            ngramSizeN: 4,
          ): <String, Object?>{
            'strategies': <String>['ngram-map-k'],
            'draftTokenMax': 6,
            'ngramSizeN': 4,
          },
          const SpeculativeDecodingConfig.ngramMapK4v(
            ngramSizeM: 5,
          ): <String, Object?>{
            'strategies': <String>['ngram-map-k4v'],
            'ngramSizeM': 5,
          },
          const SpeculativeDecodingConfig.ngramMod(
            ngramMatch: 3,
            ngramTokenMin: 1,
            ngramTokenMax: 16,
          ): <String, Object?>{
            'strategies': <String>['ngram-mod'],
            'ngramMatch': 3,
            'ngramTokenMin': 1,
            'ngramTokenMax': 16,
          },
          const SpeculativeDecodingConfig.ngramCache(
            draftTokenMax: 8,
            ngramCacheStaticPath: 'static.lcs',
            ngramCacheDynamicPath: 'dynamic.lcs',
          ): <String, Object?>{
            'strategies': <String>['ngram-cache'],
            'draftTokenMax': 8,
            'ngramCacheStatic': 'static.lcs',
            'ngramCacheDynamic': 'dynamic.lcs',
          },
          const SpeculativeDecodingConfig.backendDefault(): <String, Object?>{
            'strategies': <String>['ngram-mod'],
          },
          const SpeculativeDecodingConfig.mixed(
            strategies: <SpeculativeDecodingStrategy>[
              SpeculativeDecodingStrategy.backendDefault,
              SpeculativeDecodingStrategy.ngramMod,
              SpeculativeDecodingStrategy.ngramSimple,
            ],
            ngramCacheStaticPath: 'static.lcs',
          ): <String, Object?>{
            'strategies': <String>['ngram-mod', 'ngram-simple'],
          },
        };
        for (final MapEntry(key: config, value: expected) in cases.entries) {
          expect(await generate(speculative(config)), 'Hello');
          final sent = sentSpeculative()!
            ..removeWhere((key, value) => value == null);
          expect(sent, expected, reason: '${config.effectiveStrategies}');
        }

        await generate(const GenerationParams(speculativeDecoding: true));
        expect(
          sentSpeculative(),
          containsPair('strategies', <String>['ngram-mod']),
        );

        await generate(const GenerationParams());
        expect(fake().completionOption('speculativeDecoding'), isNull);
        expect(fake().draftLoads, isEmpty);
      });

      test('validates a configuration as native generation does', () async {
        await loadModel();

        final invalid = <SpeculativeDecodingConfig, Matcher>{
          const SpeculativeDecodingConfig.mixed(
            strategies: <SpeculativeDecodingStrategy>[
              SpeculativeDecodingStrategy.draftSimple,
              SpeculativeDecodingStrategy.draftEagle3,
            ],
            draftModelPath: 'draft.gguf',
          ): llamaUnsupported(
            contains('at most one draft-model strategy'),
          ),
          const SpeculativeDecodingConfig.mixed(
            strategies: <SpeculativeDecodingStrategy>[
              SpeculativeDecodingStrategy.draftEagle3,
            ],
          ): throwsA(
            isA<LlamaArgumentException>().having(
              (error) => error.message,
              'message',
              contains(
                'draft-eagle3 requires SpeculativeDecodingConfig.draftModel',
              ),
            ),
          ),
          const SpeculativeDecodingConfig.draftSimple(draftModelPath: ' '):
              throwsA(isA<LlamaArgumentException>()),
          const SpeculativeDecodingConfig.mixed(
            strategies: <SpeculativeDecodingStrategy>[
              SpeculativeDecodingStrategy.ngramSimple,
            ],
            draftModelPath: 'draft.gguf',
          ): llamaUnsupported(
            contains('unless a draft-model strategy is also enabled'),
          ),
          const SpeculativeDecodingConfig.mixed(
            strategies: <SpeculativeDecodingStrategy>[
              SpeculativeDecodingStrategy.ngramMod,
            ],
            minProbability: 0.5,
          ): llamaUnsupported(
            contains('unless a draft-model strategy is also enabled'),
          ),
          const SpeculativeDecodingConfig.draftSimple(
            draftTokenMax: 2,
            draftTokenMin: 3,
            draftModelPath: 'draft.gguf',
          ): throwsA(
            isA<LlamaArgumentException>().having(
              (error) => error.name,
              'name',
              'draftTokenMin',
            ),
          ),
          const SpeculativeDecodingConfig.ngramMod(
            ngramTokenMin: 9,
            ngramTokenMax: 8,
          ): throwsA(
            isA<LlamaArgumentException>().having(
              (error) => error.name,
              'name',
              'ngramTokenMin',
            ),
          ),
          const SpeculativeDecodingConfig.ngramSimple(
            ngramSizeN: 0x10000,
          ): throwsA(
            isA<LlamaArgumentException>().having(
              (error) => error.name,
              'name',
              'ngramSizeN',
            ),
          ),
          const SpeculativeDecodingConfig.ngramCache(ngramCacheStaticPath: ''):
              throwsA(isA<LlamaArgumentException>()),
        };
        for (final MapEntry(key: config, value: matcher) in invalid.entries) {
          expect(
            () => backend.generate(1, 'Hello', speculative(config)),
            matcher,
            reason: '${config.effectiveStrategies}',
          );
        }

        for (final params in <GenerationParams>[
          speculative(ngram).copyWith(grammar: 'root ::= "a"'),
          speculative(ngram).copyWith(
            thinkingBudget: const ThinkingBudget(
              maxTokens: 8,
              startTag: '<think>',
              endTag: '</think>',
            ),
          ),
        ]) {
          expect(
            () => backend.generate(1, 'Hello', params),
            llamaUnsupported(contains('as on native llama.cpp')),
          );
        }
        await backend.multimodalContextCreate(1, 'mmproj.gguf');
        expect(
          () => backend.generate(
            1,
            'Describe',
            speculative(ngram),
            parts: <LlamaContentPart>[
              LlamaImageContent(bytes: Uint8List.fromList(<int>[1, 2, 3])),
            ],
          ),
          llamaUnsupported(contains('text-only')),
        );
        expect(fake().completionCalls, 0);
        expect(fake().draftLoads, isEmpty);
      });

      test("runs draft-mtp on the loaded model's MTP layers", () async {
        newBridge = () => FakeFeatureBridge()
          ..speculativeCapabilities = <String, bool>{
            'ngram-mod': true,
            'draft-mtp': true,
          };
        await backend.modelLoadFromUrl(
          'model.gguf',
          const ModelParams(loadMtp: true, speculativeRollbackTokenMax: 16),
        );
        expect(
          fake().lastLoadOptions.dartify(),
          allOf(
            containsPair('loadMtp', true),
            containsPair('speculativeRollbackTokenMax', 16),
          ),
        );

        await generate(
          speculative(const SpeculativeDecodingConfig.mtp(draftTokenMax: 4)),
        );
        expect(
          sentSpeculative(),
          allOf(
            containsPair('strategies', <String>['draft-mtp']),
            containsPair('draftTokenMax', 4),
          ),
        );

        expect(
          () => backend.generate(
            1,
            'Hello',
            speculative(
              const SpeculativeDecodingConfig.mtp(draftModelPath: 'mtp.gguf'),
            ),
          ),
          llamaUnsupported(contains('draftModel must be null')),
        );
        expect(fake().draftLoads, isEmpty);
      });

      test('omits default MTP load options', () async {
        await loadModel();
        final options = fake().lastLoadOptions.dartify()! as Map;
        expect(options['loadMtp'], isNull);
        expect(options['speculativeRollbackTokenMax'], isNull);
      });

      test('loads the draft model once and keeps it loaded', () async {
        await loadModel();
        await generate(speculative(draft));
        await generate(speculative(ngram));
        await generate(speculative(draft));

        expect(fake().draftLoads.map((load) => load.url), <String>[
          '${Uri.parse(document.baseURI).resolve('draft.gguf')}',
        ]);
        expect(fake().draftLoads.single.useCache, isTrue);
        expect(fake().draftLoads.single.signal, isNotNull);
        expect(
          sentSpeculative(),
          containsPair('strategies', <String>['draft-simple']),
        );
        expect(fake().calls, isNot(contains('draft:unload')));

        await generate(
          speculative(
            const SpeculativeDecodingConfig.mixed(
              strategies: <SpeculativeDecodingStrategy>[
                SpeculativeDecodingStrategy.ngramMod,
                SpeculativeDecodingStrategy.draftSimple,
              ],
              draftModelPath: 'other.gguf',
            ),
          ),
        );
        expect(fake().draftLoads.map((load) => load.url), <String>[
          '${Uri.parse(document.baseURI).resolve('draft.gguf')}',
          '${Uri.parse(document.baseURI).resolve('other.gguf')}',
        ]);
        expect(
          sentSpeculative(),
          containsPair('strategies', <String>['ngram-mod', 'draft-simple']),
        );
      });

      test('loads the draft model again after a model load', () async {
        await loadModel();
        await generate(speculative(draft));
        await loadModel();
        await generate(speculative(draft));
        await backend.modelFree(1);
        await loadModel();
        await generate(speculative(draft));

        expect(bridges.expand((bridge) => bridge.draftLoads), hasLength(3));
        expect(fake().draftLoads, hasLength(1));
      });

      test('loads the draft model again when the bridge dropped it', () async {
        await loadModel();
        await generate(speculative(draft));
        fake().loadedDraft = null;
        await generate(speculative(draft));

        expect(fake().draftLoads, hasLength(2));
      });

      test('skips Cache Storage for a draft URL with credentials', () async {
        await loadModel();
        await generate(
          speculative(
            const SpeculativeDecodingConfig.draftSimple(
              draftModelPath: 'https://example.com/draft.gguf?token=secret',
            ),
          ),
        );
        expect(fake().draftLoads.single.useCache, isFalse);
      });

      test('rejects and unloads a draft that does not fit', () async {
        await loadModel();
        fake()
          ..draftRuns = <String>{'draft-dspark'}
          ..draftArchitecture = 'dflash';

        final error = await generationError(
          speculative(
            const SpeculativeDecodingConfig.draftDflash(
              draftModelPath: 'dspark.gguf',
            ),
          ),
        );
        expect(
          error,
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(contains('draft-dflash'), contains('architecture is dflash')),
          ),
        );
        expect(fake().calls, contains('draft:unload'));
        expect(fake().loadedDraft, isNull);
        expect(fake().completionCalls, 0);

        await generate(
          speculative(
            const SpeculativeDecodingConfig.draftDspark(
              draftModelPath: 'dspark.gguf',
            ),
          ),
        );
        expect(
          sentSpeculative(),
          containsPair('strategies', <String>['draft-dspark']),
        );
      });

      test('maps draft load errors and redacts the draft URL', () async {
        await loadModel();
        const url = 'https://user:pass@example.com/draft.gguf?token=secret';
        fake().draftLoadError = 'Failed to fetch draft model $url: 404';
        final error = await generationError(
          speculative(
            const SpeculativeDecodingConfig.draftSimple(draftModelPath: url),
          ),
        );
        expect(error, isA<LlamaModelException>());
        final exception = error! as LlamaModelException;
        expect(
          '${exception.message} ${exception.details}',
          allOf(
            contains('draft model'),
            contains('404'),
            isNot(contains('secret')),
            isNot(contains('pass')),
          ),
        );

        fake().draftLoadError =
            'The draft model cannot be replaced during active generation or '
            'text-to-speech synthesis';
        expect(
          await generationError(speculative(draft)),
          isA<LlamaStateException>(),
        );

        fake().draftLoadError =
            'The eagle3 draft model reads target hidden states of size 1024, '
            "but the loaded model's hidden size is 960";
        expect(
          await generationError(speculative(draft)),
          isA<LlamaUnsupportedException>(),
        );

        fake().draftLoadError = null;
        await generate(speculative(draft));
        expect(fake().completionCalls, 1);
      });

      test('cancelling during the draft load aborts it', () async {
        await loadModel();
        final gate = Completer<void>();
        fake().draftLoadGate = gate;
        final subscription = backend
            .generate(1, 'Hello', speculative(draft))
            .listen((_) {});
        while (fake().draftLoads.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        await subscription.cancel();
        final signal = fake().draftLoads.single.signal! as JSObject;
        expect(signal.getProperty<JSBoolean>('aborted'.toJS).toDart, isTrue);
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(fake().loadedDraft, isNull);
        expect(fake().completionCalls, 0);

        fake().draftLoadGate = null;
        await generate(speculative(draft));
        expect(fake().draftLoads, hasLength(2));
      });

      test('cancelGeneration during the draft load ends the stream', () async {
        await loadModel();
        final gate = Completer<void>();
        fake().draftLoadGate = gate;
        final errors = <Object>[];
        final done = Completer<void>();
        backend
            .generate(1, 'Hello', speculative(draft))
            .listen((_) {}, onError: errors.add, onDone: done.complete);
        while (fake().draftLoads.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        backend.cancelGeneration();
        gate.complete();
        await done.future;
        expect(errors, isEmpty);
        expect(fake().completionCalls, 0);
      });

      test('maps speculative completion errors', () async {
        await loadModel();
        const cache = 'https://example.com/static.lcs?token=secret';
        final cases = <String, Matcher>{
          "draft-mtp needs the model's MTP head: load a model with MTP "
                  'layers with loadMtp: true':
              isA<LlamaUnsupportedException>(),
          'this model has recurrent state, so draft-model and MTP '
                  'speculative decoding need rollback snapshots':
              isA<LlamaUnsupportedException>(),
          'speculative draft token limits exceed the context size of 512 '
                  'tokens':
              isA<LlamaUnsupportedException>(),
          'Failed to fetch $cache': isA<LlamaInferenceException>(),
          'The static n-gram cache is malformed':
              isA<LlamaInferenceException>(),
        };
        for (final MapEntry(key: message, value: matcher) in cases.entries) {
          fake().completionError = message;
          final error = await generationError(
            speculative(
              const SpeculativeDecodingConfig.ngramCache(
                ngramCacheStaticPath: cache,
              ),
            ),
          );
          expect(error, matcher, reason: message);
          final exception = error! as LlamaException;
          expect(
            '${exception.message} ${exception.details}',
            isNot(contains('secret')),
            reason: message,
          );
        }
      });

      test('LlamaEngine reports rejections as unsupported', () async {
        newBridge = () => FakeFeatureBridge()..speculativeCapabilities = null;
        final engine = LlamaEngine(backend);
        await engine.loadModelFromUrl('model.gguf');

        await expectLater(
          engine.generate('Hello', params: speculative(ngram)).toList(),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(
          (await engine.backendGenerationCapabilities)
              .speculativeDecodingStrategies,
          isEmpty,
        );

        newBridge = FakeFeatureBridge.new;
        await engine.unloadModel();
        await engine.loadModelFromUrl('model.gguf');
        expect(
          (await engine.backendGenerationCapabilities)
              .speculativeDecodingStrategies,
          contains(SpeculativeDecodingStrategy.ngramSimple),
        );
        expect(
          await engine.generate('Hello', params: speculative(ngram)).join(),
          'Hello',
        );
        await expectLater(
          engine
              .generate(
                'Hello',
                params: speculative(const SpeculativeDecodingConfig.mtp()),
              )
              .toList(),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      });
    });
  });
}

final class _ResultRecorder extends LlamaEngineObserver {
  final List<LlamaOperationResult> results = <LlamaOperationResult>[];

  @override
  LlamaOperationObserver? onStart(LlamaOperation operation) =>
      operation is LlamaModelLoadOperation ? null : _ResultObserver(results);
}

final class _ResultObserver extends LlamaOperationObserver {
  _ResultObserver(this.results);

  final List<LlamaOperationResult> results;

  @override
  void onEnd(LlamaOperationResult result) => results.add(result);
}
