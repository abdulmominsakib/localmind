@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/config/gpu_backend.dart';
import 'package:llamadart/src/core/models/config/gpu_device_info.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('LlamaCppService can be instantiated', () {
    final service = LlamaCppService();
    expect(service, isA<LlamaCppService>());
  });

  group('getVramInfo', () {
    test('returns a non-negative (total, free) record without throwing', () {
      // Shape invariant: callers destructure these two fields. A
      // rename or struct change in `LlamaCppService.getVramInfo`
      // would break every backend that forwards the worker
      // SystemInfoResponse fields. Hosts with GPU runtimes available
      // may return real memory here; hosts without them return (0, 0).
      final service = LlamaCppService();
      final info = service.getVramInfo();
      expect(info.total, isA<int>());
      expect(info.free, isA<int>());
      expect(info.total, greaterThanOrEqualTo(0));
      expect(info.free, greaterThanOrEqualTo(0));
    });
  });

  group('listGpuDevices', () {
    test('returns a List<GpuDeviceInfo> without throwing', () {
      // Hosts with a GPU runtime return real devices; CI hosts without one
      // return an empty list. Either way the call must not throw and every
      // element must satisfy the field contract callers rely on. A rename or
      // struct change in `LlamaCppService.listGpuDevices` breaks this.
      final service = LlamaCppService();
      final devices = service.listGpuDevices();
      expect(devices, isA<List<GpuDeviceInfo>>());
      for (final device in devices) {
        expect(device.type, isNot(GpuDeviceType.cpu));
        expect(device.mainGpu, greaterThanOrEqualTo(0));
        expect(device.memoryFreeBytes, greaterThanOrEqualTo(0));
        expect(device.memoryTotalBytes, greaterThanOrEqualTo(0));
      }
    });

    test('does not throw when probing an unavailable backend', () {
      // probeBackends opt-in must stay safe: requesting a backend whose module
      // or symbols are absent (as on CI hosts) returns a list rather than
      // throwing.
      final service = LlamaCppService();
      final devices = service.listGpuDevices(
        probeBackends: const [GpuBackend.vulkan, GpuBackend.cuda],
      );
      expect(devices, isA<List<GpuDeviceInfo>>());
    });
  });

  group('gpuBackendFromRegName', () {
    test('maps ggml registry names (incl. Metal MTL) to GpuBackend', () {
      expect(
        LlamaCppService.gpuBackendFromRegName('Vulkan'),
        GpuBackend.vulkan,
      );
      expect(LlamaCppService.gpuBackendFromRegName('CUDA'), GpuBackend.cuda);
      expect(LlamaCppService.gpuBackendFromRegName('Metal'), GpuBackend.metal);
      // Regression: macOS reports the registry name as "MTL", which previously
      // fell through to GpuBackend.auto.
      expect(LlamaCppService.gpuBackendFromRegName('MTL'), GpuBackend.metal);
      expect(LlamaCppService.gpuBackendFromRegName('ROCm'), GpuBackend.hip);
      expect(LlamaCppService.gpuBackendFromRegName('HIP'), GpuBackend.hip);
      expect(
        LlamaCppService.gpuBackendFromRegName('OpenCL'),
        GpuBackend.opencl,
      );
      expect(LlamaCppService.gpuBackendFromRegName('BLAS'), GpuBackend.blas);
      expect(LlamaCppService.gpuBackendFromRegName('CPU'), GpuBackend.cpu);
      expect(
        LlamaCppService.gpuBackendFromRegName('SomethingElse'),
        GpuBackend.auto,
      );
    });
  });

  group('loadModel preflight validation', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('llamadart-loadmodel-');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('throws when model file does not exist', () {
      final service = LlamaCppService();
      final missingPath = path.join(tempDir.path, 'missing.gguf');

      expect(
        () => service.loadModel(missingPath, const ModelParams()),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when model file is empty', () {
      final service = LlamaCppService();
      final emptyFile = File(path.join(tempDir.path, 'empty.gguf'))
        ..writeAsBytesSync(const <int>[]);

      expect(
        () => service.loadModel(emptyFile.path, const ModelParams()),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when model file does not look like GGUF', () {
      final service = LlamaCppService();
      final badFile = File(path.join(tempDir.path, 'bad.gguf'))
        ..writeAsBytesSync(const <int>[0x00, 0x01, 0x02, 0x03]);

      expect(
        () => service.loadModel(badFile.path, const ModelParams()),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('speculative validation', () {
    late LlamaCppService service;
    late Directory tempDir;

    setUp(() {
      service = LlamaCppService();
      tempDir = Directory.systemTemp.createTempSync('llamadart-spec-');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('de-duplicates mixed strategies before native mapping', () {
      final typeNames = service.debugResolveSpeculativeTypeNamesForTesting(
        const GenerationParams(
          speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
            strategies: [
              SpeculativeDecodingStrategy.ngramMod,
              SpeculativeDecodingStrategy.ngramMod,
              SpeculativeDecodingStrategy.mtp,
              SpeculativeDecodingStrategy.mtp,
            ],
            draftTokenMax: 4,
          ),
        ),
      );

      expect(typeNames, 'ngram-mod,draft-mtp');
    });

    test('rejects speculative decoding with a thinking budget', () {
      expect(
        () => service.debugResolveSpeculativeTypeNamesForTesting(
          const GenerationParams(
            thinkingBudget: ThinkingBudget(maxTokens: 64),
            speculativeDecodingConfig: SpeculativeDecodingConfig.ngramMod(),
          ),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('uses ngram size M as native draft cap for map strategies', () {
      final configs = <String, SpeculativeDecodingConfig>{
        'ngram-simple': const SpeculativeDecodingConfig.ngramSimple(
          draftTokenMax: 8,
        ),
        'ngram-map-k': const SpeculativeDecodingConfig.ngramMapK(
          draftTokenMax: 8,
        ),
        'ngram-map-k4v': const SpeculativeDecodingConfig.ngramMapK4v(
          draftTokenMax: 8,
        ),
      };

      for (final entry in configs.entries) {
        final defaults = service.debugResolveSpeculativeNativeParamsForTesting(
          GenerationParams(speculativeDecodingConfig: entry.value),
        );

        expect(defaults['typeNames'], entry.key);
        expect(defaults['draftTokenMax'], 48);
        expect(defaults['ngramSizeM'], isNull);
      }

      final explicitConfigs = <String, SpeculativeDecodingConfig>{
        'ngram-simple': const SpeculativeDecodingConfig.ngramSimple(
          draftTokenMax: 8,
          ngramSizeM: 16,
        ),
        'ngram-map-k': const SpeculativeDecodingConfig.ngramMapK(
          draftTokenMax: 8,
          ngramSizeM: 16,
        ),
        'ngram-map-k4v': const SpeculativeDecodingConfig.ngramMapK4v(
          draftTokenMax: 8,
          ngramSizeM: 16,
        ),
      };

      for (final entry in explicitConfigs.entries) {
        final explicit = service.debugResolveSpeculativeNativeParamsForTesting(
          GenerationParams(speculativeDecodingConfig: entry.value),
        );

        expect(explicit['typeNames'], entry.key);
        expect(explicit['draftTokenMax'], 16);
        expect(explicit['ngramSizeM'], 16);
      }
    });

    test('uses upstream ngram size M default when draft cap is omitted', () {
      final resolved = service.debugResolveSpeculativeNativeParamsForTesting(
        const GenerationParams(
          speculativeDecodingConfig: SpeculativeDecodingConfig.ngramMapK(),
        ),
      );

      expect(resolved['draftTokenMax'], 48);
      expect(resolved['ngramSizeM'], isNull);
    });

    test('rejects mixed configs with more than one draft strategy', () {
      expect(
        () => service.debugResolveSpeculativeTypeNamesForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
              strategies: [
                SpeculativeDecodingStrategy.mtp,
                SpeculativeDecodingStrategy.draftSimple,
              ],
              draftModelPath: 'draft.gguf',
            ),
          ),
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('at most one draft-model strategy'),
          ),
        ),
      );
    });

    test('requires draftModelPath for external draft strategies', () {
      expect(
        () => service.debugResolveSpeculativeTypeNamesForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
              strategies: [SpeculativeDecodingStrategy.draftEagle3],
            ),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('requires draftModelPath'),
          ),
        ),
      );
    });

    test('suppresses process logits only for external draft strategies', () {
      expect(
        service.debugSuppressesDraftProcessLogitsForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(
              draftModelPath: 'draft.gguf',
            ),
          ),
        ),
        isTrue,
      );
      expect(
        service.debugSuppressesDraftProcessLogitsForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.draftEagle3(
              draftModelPath: 'draft.gguf',
            ),
          ),
        ),
        isTrue,
      );
      expect(
        service.debugSuppressesDraftProcessLogitsForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(),
          ),
        ),
        isFalse,
      );
      expect(
        service.debugSuppressesDraftProcessLogitsForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.ngramSimple(),
          ),
        ),
        isFalse,
      );
    });

    test('requires loadMtp for bundled MTP tensors', () {
      const generationParams = GenerationParams(
        speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(),
      );

      expect(
        () => service.debugValidateMtpModelLoadForTesting(
          generationParams,
          const ModelParams(),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('ModelParams(loadMtp: true)'),
          ),
        ),
      );
      expect(
        () => service.debugValidateMtpModelLoadForTesting(
          generationParams,
          const ModelParams(loadMtp: true),
        ),
        returnsNormally,
      );
    });

    test('external MTP draft does not require target bundled tensors', () {
      expect(
        () => service.debugValidateMtpModelLoadForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(
              draftModelPath: 'draft.gguf',
            ),
          ),
          const ModelParams(),
        ),
        returnsNormally,
      );
    });

    test('temporarily zeros and restores suppressed batch logits', () {
      final logits = malloc<Int8>(3);
      addTearDown(() => malloc.free(logits));
      logits[0] = 1;
      logits[1] = 0;
      logits[2] = 1;

      final seenLogits = <int>[];
      final result = LlamaCppService.debugWithSuppressedBatchLogitsForTesting(
        logits,
        3,
        true,
        () {
          seenLogits.addAll([logits[0], logits[1], logits[2]]);
          logits[1] = 7;
          return 'processed';
        },
      );

      expect(result, 'processed');
      expect(seenLogits, [0, 0, 0]);
      expect([logits[0], logits[1], logits[2]], [1, 0, 1]);
    });

    test('leaves batch logits untouched when suppression is disabled', () {
      final logits = malloc<Int8>(2);
      addTearDown(() => malloc.free(logits));
      logits[0] = 1;
      logits[1] = 0;

      final seenLogits = <int>[];
      LlamaCppService.debugWithSuppressedBatchLogitsForTesting(
        logits,
        2,
        false,
        () {
          seenLogits.addAll([logits[0], logits[1]]);
        },
      );

      expect(seenLogits, [1, 0]);
      expect([logits[0], logits[1]], [1, 0]);
    });

    test('rejects invalid ngram-cache paths', () {
      expect(
        () => service.debugResolveSpeculativeTypeNamesForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.ngramCache(
              ngramCacheStaticPath: ' ',
            ),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('must be null or a non-empty path'),
          ),
        ),
      );

      final missingPath = path.join(tempDir.path, 'missing.ngram');
      expect(
        () => service.debugResolveSpeculativeTypeNamesForTesting(
          GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.ngramCache(
              ngramCacheStaticPath: missingPath,
            ),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('must exist before enabling llama.cpp ngram-cache'),
          ),
        ),
      );
    });
  });

  test('maps presence penalty to the native penalty sampler', () {
    final service = LlamaCppService();

    expect(
      service.debugResolvePenaltySamplerParamsForTesting(
        const GenerationParams(penalty: 1.0, presencePenalty: 1.5),
      ),
      <String, Object>{
        'lastN': 64,
        'repeat': 1.0,
        'frequency': 0.0,
        'presence': 1.5,
      },
    );
  });

  group('thinking-budget validation', () {
    test(
      'rejects a token budget that exceeds the native signed 32-bit limit',
      () {
        final service = LlamaCppService();

        expect(
          () => service.debugValidateThinkingBudgetForTesting(
            const GenerationParams(
              thinkingBudget: ThinkingBudget(maxTokens: 2147483648),
            ),
          ),
          throwsA(
            isA<RangeError>().having(
              (error) => error.toString(),
              'message',
              contains('signed 32-bit'),
            ),
          ),
        );
      },
    );
  });

  group('invalid-handle guard rails', () {
    late LlamaCppService service;

    setUp(() {
      service = LlamaCppService();
    });

    test('createContext throws for unknown model handle', () {
      expect(
        () => service.createContext(-1, const ModelParams()),
        throwsA(isA<Exception>()),
      );
    });

    test('generate stream reports error for unknown context handle', () async {
      expect(
        service
            .generate(-1, 'hello', const GenerationParams(), 0)
            .drain<void>(),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'generate reports unknown context before speculative decoding',
      () async {
        expect(
          service
              .generate(
                -1,
                'hello',
                const GenerationParams(speculativeDecoding: true),
                0,
              )
              .drain<void>(),
          throwsA(isA<Exception>()),
        );
      },
    );

    test(
      'generate reports unknown context before speculative config',
      () async {
        expect(
          service
              .generate(
                -1,
                'hello',
                const GenerationParams(
                  speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(),
                ),
                0,
              )
              .drain<void>(),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('embed and embedBatch throw for unknown context handle', () {
      expect(() => service.embed(-1, 'hello'), throwsA(isA<Exception>()));
      expect(
        () => service.embedBatch(-1, const <String>['hello']),
        throwsA(isA<Exception>()),
      );
    });

    test('stateSaveFile throws for unknown context handle', () {
      expect(
        () => service.stateSaveFile(-1, '/tmp/state.bin', const <int>[]),
        throwsA(isA<StateError>()),
      );
    });

    test('createMultimodalContext throws for unknown model handle', () {
      expect(
        () => service.createMultimodalContext(-1, 'mmproj.gguf'),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'token and metadata methods return safe defaults for unknown model',
      () {
        expect(service.tokenize(-1, 'hello', true), isEmpty);
        expect(service.detokenize(-1, const <int>[1, 2, 3], false), isEmpty);
        expect(service.getMetadata(-1), isEmpty);
      },
    );

    test(
      'state/introspection methods return safe defaults before model load',
      () {
        expect(service.getContextSize(-1), 0);
        expect(service.hasMultimodalContext(-1), isFalse);
        expect(service.getResolvedGpuLayers(), isNull);
        expect(service.getActiveBackendName(), 'CPU');
        expect(service.getAvailableBackendInfo(), contains('CPU'));
      },
    );

    test('handleLora and free methods are no-op for unknown handles', () {
      service.handleLora(-1, '/tmp/a.lora', 0.5, 'set');
      service.freeModel(-1);
      service.freeContext(-1);
      service.freeMultimodalContext(-1);
    });
  });

  group('resolveGpuLayersForLoad', () {
    test('prefers CPU for Android auto mode', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.auto,
      );

      expect(
        LlamaCppService.resolvePreferredBackendForLoad(params, isAndroid: true),
        GpuBackend.cpu,
      );
    });

    test('keeps auto mode on non-Android hosts', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.auto,
      );

      expect(
        LlamaCppService.resolvePreferredBackendForLoad(params),
        GpuBackend.auto,
      );
    });

    test('forces CPU mode to zero gpu layers', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.cpu,
      );

      expect(LlamaCppService.resolveGpuLayersForLoad(params), 0);
    });

    test('forces Android auto mode to zero gpu layers', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.auto,
      );

      expect(
        LlamaCppService.resolveGpuLayersForLoad(params, isAndroid: true),
        0,
      );
    });

    test('preserves configured gpu layers for non-CPU backends', () {
      const params = ModelParams(
        gpuLayers: 42,
        preferredBackend: GpuBackend.vulkan,
      );

      expect(LlamaCppService.resolveGpuLayersForLoad(params), 42);
    });
  });

  group('resolveContextBatchSizes', () {
    test('uses llama.cpp defaults when generative batch sizes are unset', () {
      const params = ModelParams(contextSize: 16384);

      final resolved = LlamaCppService.resolveContextBatchSizes(params, 16384);

      expect(resolved.batchSize, 2048);
      expect(resolved.microBatchSize, 512);
    });

    test('clamps automatic defaults to small contexts', () {
      const params = ModelParams(contextSize: 256);

      final resolved = LlamaCppService.resolveContextBatchSizes(params, 256);

      expect(resolved.batchSize, 256);
      expect(resolved.microBatchSize, 256);
    });

    test('preserves full-context defaults for encoder-only models', () {
      const params = ModelParams(contextSize: 4096);

      final resolved = LlamaCppService.resolveContextBatchSizes(
        params,
        4096,
        useFullContextDefaults: true,
      );

      expect(resolved.batchSize, 4096);
      expect(resolved.microBatchSize, 4096);
    });

    test('uses explicit batch and micro-batch values', () {
      const params = ModelParams(
        contextSize: 4096,
        batchSize: 512,
        microBatchSize: 128,
      );

      final resolved = LlamaCppService.resolveContextBatchSizes(params, 4096);

      expect(resolved.batchSize, 512);
      expect(resolved.microBatchSize, 128);
    });

    test('clamps automatic micro-batch to a smaller explicit batch', () {
      const params = ModelParams(contextSize: 4096, batchSize: 384);

      final resolved = LlamaCppService.resolveContextBatchSizes(params, 4096);

      expect(resolved.batchSize, 384);
      expect(resolved.microBatchSize, 384);
    });

    test('caps an unset micro-batch at the llama.cpp default', () {
      const params = ModelParams(contextSize: 4096, batchSize: 1024);

      final resolved = LlamaCppService.resolveContextBatchSizes(params, 4096);

      expect(resolved.batchSize, 1024);
      expect(resolved.microBatchSize, 512);
    });

    test('clamps micro-batch to batch when only micro-batch is oversized', () {
      const params = ModelParams(contextSize: 1024, microBatchSize: 2048);

      final resolved = LlamaCppService.resolveContextBatchSizes(params, 1024);

      expect(resolved.batchSize, 1024);
      expect(resolved.microBatchSize, 1024);
    });

    test('clamps batch sizes to safe bounds', () {
      const params = ModelParams(
        contextSize: 512,
        batchSize: 2048,
        microBatchSize: 1024,
      );

      final resolved = LlamaCppService.resolveContextBatchSizes(params, 512);

      expect(resolved.batchSize, 512);
      expect(resolved.microBatchSize, 512);
    });

    test('falls back from invalid values to sane minimums', () {
      const params = ModelParams(
        contextSize: 0,
        batchSize: -10,
        microBatchSize: -20,
      );

      final resolved = LlamaCppService.resolveContextBatchSizes(params, 0);

      expect(resolved.batchSize, 1);
      expect(resolved.microBatchSize, 1);
    });
  });

  group('backend asset candidate scoring', () {
    test('accepts missing score symbol for compatibility', () {
      expect(LlamaCppService.isBackendCandidateScoreSupported(null), isTrue);
    });

    test('rejects non-positive scores', () {
      expect(LlamaCppService.isBackendCandidateScoreSupported(0), isFalse);
      expect(LlamaCppService.isBackendCandidateScoreSupported(-1), isFalse);
      expect(LlamaCppService.isBackendCandidateScoreSupported(1), isTrue);
    });

    test('skips unsupported Android CPU variants until score passes', () {
      final selected = LlamaCppService.selectFirstSupportedBackendCandidate(
        const <String>[
          'package:llamadart/ggml-cpu-android_armv9_2_2',
          'package:llamadart/ggml-cpu-android_armv8_6_1',
          'package:llamadart/ggml-cpu-android_armv8_2_2',
          'package:llamadart/ggml-cpu-android_armv8_0_1',
        ],
        scoreForCandidate: (candidate) {
          switch (candidate) {
            case 'package:llamadart/ggml-cpu-android_armv9_2_2':
            case 'package:llamadart/ggml-cpu-android_armv8_6_1':
              return 0;
            case 'package:llamadart/ggml-cpu-android_armv8_2_2':
              return 7;
            case 'package:llamadart/ggml-cpu-android_armv8_0_1':
              return 1;
          }
          return 0;
        },
      );

      expect(selected, 'package:llamadart/ggml-cpu-android_armv8_2_2');
    });

    test('keeps older backends without score symbol eligible', () {
      final selected = LlamaCppService.selectFirstSupportedBackendCandidate(
        const <String>[
          'package:llamadart/ggml-cpu-android_armv8_0_1',
          'package:llamadart/ggml-cpu',
        ],
        scoreForCandidate: (candidate) {
          if (candidate == 'package:llamadart/ggml-cpu-android_armv8_0_1') {
            return null;
          }
          return 1;
        },
      );

      expect(selected, 'package:llamadart/ggml-cpu-android_armv8_0_1');
    });

    test('returns null when every candidate is unsupported', () {
      final selected =
          LlamaCppService.selectFirstSupportedBackendCandidate(const <String>[
            'package:llamadart/ggml-cpu-android_armv9_2_2',
            'package:llamadart/ggml-cpu-android_armv8_6_1',
          ], scoreForCandidate: (_) => 0);

      expect(selected, isNull);
    });

    test('formats skipped backend asset diagnostics', () {
      expect(
        LlamaCppService.describeSkippedBackendAssetCandidate(
          'package:llamadart/ggml-cpu-android_armv8_6_1',
          0,
        ),
        'Skipped backend asset '
        '`package:llamadart/ggml-cpu-android_armv8_6_1` because '
        '`ggml_backend_score` returned 0.',
      );
    });

    test('formats loaded backend asset diagnostics with a score', () {
      expect(
        LlamaCppService.describeLoadedBackendAssetCandidate(
          'package:llamadart/ggml-cpu-android_armv8_2_2',
          7,
        ),
        'Loaded backend asset '
        '`package:llamadart/ggml-cpu-android_armv8_2_2` with '
        '`ggml_backend_score`=7.',
      );
    });

    test('formats loaded backend asset diagnostics without a score', () {
      expect(
        LlamaCppService.describeLoadedBackendAssetCandidate(
          'package:llamadart/ggml-cpu',
          null,
        ),
        'Loaded backend asset `package:llamadart/ggml-cpu` without '
        '`ggml_backend_score`.',
      );
    });
  });

  group('shouldDisableContextGpuOffload', () {
    test('disables offload for explicit CPU backend', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.cpu,
      );

      expect(LlamaCppService.shouldDisableContextGpuOffload(params), isTrue);
    });

    test('disables offload when effective gpu layers are zero', () {
      const params = ModelParams(
        gpuLayers: 0,
        preferredBackend: GpuBackend.auto,
      );

      expect(LlamaCppService.shouldDisableContextGpuOffload(params), isTrue);
    });

    test('keeps offload enabled for non-CPU backend with gpu layers', () {
      const params = ModelParams(
        gpuLayers: 12,
        preferredBackend: GpuBackend.hip,
      );

      expect(LlamaCppService.shouldDisableContextGpuOffload(params), isFalse);
    });

    test('honors resolved load-time fallback to zero gpu layers', () {
      const params = ModelParams(
        gpuLayers: 32,
        preferredBackend: GpuBackend.vulkan,
      );

      expect(
        LlamaCppService.shouldDisableContextGpuOffload(
          params,
          resolvedGpuLayers: 0,
        ),
        isTrue,
      );
    });
  });

  group('shouldUseConservativeAndroidVulkanContextConfig', () {
    test('returns false off Android', () {
      const params = ModelParams(
        gpuLayers: 16,
        preferredBackend: GpuBackend.vulkan,
      );

      expect(
        LlamaCppService.shouldUseConservativeAndroidVulkanContextConfig(params),
        isFalse,
      );
    });

    test('returns true for Android Vulkan with GPU layers', () {
      const params = ModelParams(
        gpuLayers: 16,
        preferredBackend: GpuBackend.vulkan,
      );

      expect(
        LlamaCppService.shouldUseConservativeAndroidVulkanContextConfig(
          params,
          isAndroid: true,
        ),
        isTrue,
      );
    });

    test('returns false for Android CPU mode', () {
      const params = ModelParams(
        gpuLayers: 0,
        preferredBackend: GpuBackend.cpu,
      );

      expect(
        LlamaCppService.shouldUseConservativeAndroidVulkanContextConfig(
          params,
          isAndroid: true,
        ),
        isFalse,
      );
    });

    test('returns false after effective Vulkan fallback to zero layers', () {
      const params = ModelParams(
        gpuLayers: 16,
        preferredBackend: GpuBackend.vulkan,
      );

      expect(
        LlamaCppService.shouldUseConservativeAndroidVulkanContextConfig(
          params,
          resolvedGpuLayers: 0,
          isAndroid: true,
        ),
        isFalse,
      );
    });
  });

  group('resolveMtmdUseGpuForLoad', () {
    test('forces CPU mode to disable projector GPU offload', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.cpu,
      );

      expect(LlamaCppService.resolveMtmdUseGpuForLoad(params, 0), isFalse);
    });

    test(
      'disables projector GPU offload when effective gpu layers are zero',
      () {
        const params = ModelParams(
          gpuLayers: 0,
          preferredBackend: GpuBackend.auto,
        );

        expect(LlamaCppService.resolveMtmdUseGpuForLoad(params, 0), isFalse);
      },
    );

    test(
      'enables projector GPU offload for non-CPU backend with gpu layers',
      () {
        const params = ModelParams(
          gpuLayers: 42,
          preferredBackend: GpuBackend.vulkan,
        );

        expect(LlamaCppService.resolveMtmdUseGpuForLoad(params, 42), isTrue);
      },
    );

    test(
      'keeps projector GPU offload disabled after effective CPU fallback',
      () {
        const params = ModelParams(
          gpuLayers: 42,
          preferredBackend: GpuBackend.vulkan,
        );

        expect(LlamaCppService.resolveMtmdUseGpuForLoad(params, 0), isFalse);
      },
    );
  });

  group('parseBackendModuleDirectoryFromProcMaps', () {
    test('extracts lib directory from standard maps entry', () {
      const maps = '''
7f8a0000-7f8b0000 r-xp 00000000 103:04 12345 /data/app/~~pkg/lib/arm64/libllamadart.so
''';

      expect(
        LlamaCppService.parseBackendModuleDirectoryFromProcMaps(maps),
        '/data/app/~~pkg/lib/arm64',
      );
    });

    test('handles deleted mapping suffix', () {
      const maps = '''
7f8a0000-7f8b0000 r-xp 00000000 103:04 12345 /tmp/libllamadart.so (deleted)
''';

      expect(
        LlamaCppService.parseBackendModuleDirectoryFromProcMaps(maps),
        '/tmp',
      );
    });

    test('accepts versioned Linux libllamadart mappings', () {
      const maps = '''
7f8a0000-7f8b0000 r-xp 00000000 103:04 12345 /opt/app/lib/libllamadart.so.0
''';

      expect(
        LlamaCppService.parseBackendModuleDirectoryFromProcMaps(maps),
        '/opt/app/lib',
      );
    });

    test('returns null when libllamadart mapping is missing', () {
      const maps = '''
7f8a0000-7f8b0000 r-xp 00000000 103:04 12345 /system/lib64/libc.so
''';

      expect(
        LlamaCppService.parseBackendModuleDirectoryFromProcMaps(maps),
        isNull,
      );
    });

    test('forces CPU projector mode for Android Qwen3.5 0.8B', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.vulkan,
      );

      expect(
        LlamaCppService.resolveMtmdUseGpuForLoad(
          params,
          ModelParams.maxGpuLayers,
          modelPath: '/data/user/0/app/models/Qwen3.5-0.8B-Q4_K_M.gguf',
          isAndroid: true,
        ),
        isFalse,
      );
    });

    test('keeps projector GPU path for unrelated Android models', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.vulkan,
      );

      expect(
        LlamaCppService.resolveMtmdUseGpuForLoad(
          params,
          ModelParams.maxGpuLayers,
          modelPath: '/data/user/0/app/models/Llama-3.2-3B.gguf',
          isAndroid: true,
        ),
        isTrue,
      );
    });
  });

  group('resolveWindowsBackendModuleDirectory', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync(
        'llamadart-windows-modules-',
      );
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('uses explicit environment override when valid', () {
      final overrideDir = Directory(path.join(tempRoot.path, 'override'))
        ..createSync(recursive: true);
      _createWindowsBundleMarkerFiles(overrideDir.path);

      final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: path.join(tempRoot.path, 'dart.exe'),
        currentDirectoryPath: tempRoot.path,
        environment: {'LLAMADART_NATIVE_LIB_DIR': overrideDir.path},
      );

      expect(path.normalize(resolved!), path.normalize(overrideDir.path));
    });

    test('uses altered search path for absolute Windows backend modules', () {
      expect(
        LlamaCppService.windowsBackendModuleLoadFlags(
          path.join(tempRoot.path, 'ggml-cuda.dll'),
        ),
        0x00000008,
      );
      expect(
        LlamaCppService.windowsBackendModuleLoadFlags('ggml-cuda.dll'),
        isZero,
      );
    });

    test('orders CUDA redistributable DLLs for best-effort preloading', () {
      final dependencyPaths = LlamaCppService.windowsBackendDependencyPaths(
        tempRoot.path,
        'cuda',
        fileNames: const <String>[
          'ggml-cuda.dll',
          'cublasLt64_12.dll',
          'notes.txt',
          'cudart64_12.dll',
          'cublas64_12.dll',
        ],
      );

      expect(dependencyPaths, <String>[
        path.join(tempRoot.path, 'cudart64_12.dll'),
        path.join(tempRoot.path, 'cublas64_12.dll'),
        path.join(tempRoot.path, 'cublasLt64_12.dll'),
      ]);
      expect(
        LlamaCppService.windowsBackendDependencyPaths(
          tempRoot.path,
          'vulkan',
          fileNames: const <String>['cudart64_12.dll'],
        ),
        isEmpty,
      );
    });

    test('falls back to hook cache extracted bundle directory', () {
      final extractedDir = Directory(
        path.join(
          tempRoot.path,
          '.dart_tool',
          'llamadart',
          'native_bundles',
          'b8095',
          'windows-x64',
          'extracted',
        ),
      )..createSync(recursive: true);
      _createWindowsBundleMarkerFiles(extractedDir.path);

      final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: path.join(
          tempRoot.path,
          'dart-sdk',
          'dart.exe',
        ),
        currentDirectoryPath: tempRoot.path,
        environment: const {},
      );

      expect(path.normalize(resolved!), path.normalize(extractedDir.path));
    });

    test('finds custom GitHub hook cache namespace', () {
      final extractedDir = Directory(
        path.join(
          tempRoot.path,
          '.dart_tool',
          'llamadart',
          'native_bundles',
          'github',
          'example',
          'native-fork',
          'b8095',
          'windows-x64',
          'extracted',
        ),
      )..createSync(recursive: true);
      _createWindowsBundleMarkerFiles(extractedDir.path);

      final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: path.join(
          tempRoot.path,
          'dart-sdk',
          'dart.exe',
        ),
        currentDirectoryPath: tempRoot.path,
        environment: const {},
      );

      expect(path.normalize(resolved!), path.normalize(extractedDir.path));
    });

    test('finds local archive hook cache namespace', () {
      final extractedDir = Directory(
        path.join(
          tempRoot.path,
          '.dart_tool',
          'llamadart',
          'native_bundles',
          'local',
          '0123456789abcdef',
          'b8095',
          'windows-x64',
          'extracted',
        ),
      )..createSync(recursive: true);
      _createWindowsBundleMarkerFiles(extractedDir.path);

      final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: path.join(
          tempRoot.path,
          'dart-sdk',
          'dart.exe',
        ),
        currentDirectoryPath: tempRoot.path,
        environment: const {},
      );

      expect(path.normalize(resolved!), path.normalize(extractedDir.path));
    });

    test('prefers .dart_tool/lib when suffixed native assets are present', () {
      final dartToolLibDir = Directory(
        path.join(tempRoot.path, '.dart_tool', 'lib'),
      )..createSync(recursive: true);
      _createWindowsBundleMarkerFiles(
        dartToolLibDir.path,
        suffix: '-windows-x64',
      );

      final extractedDir = Directory(
        path.join(
          tempRoot.path,
          '.dart_tool',
          'llamadart',
          'native_bundles',
          'b8095',
          'windows-x64',
          'extracted',
        ),
      )..createSync(recursive: true);
      _createWindowsBundleMarkerFiles(extractedDir.path);

      final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: path.join(
          tempRoot.path,
          'dart-sdk',
          'dart.exe',
        ),
        currentDirectoryPath: tempRoot.path,
        environment: const {},
      );

      expect(path.normalize(resolved!), path.normalize(dartToolLibDir.path));
    });

    test('uses current directory when executable dir is not a bundle', () {
      final currentDir = Directory(path.join(tempRoot.path, 'cwd'))
        ..createSync(recursive: true);
      _createWindowsBundleMarkerFiles(currentDir.path);

      final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: path.join(tempRoot.path, 'dart.exe'),
        currentDirectoryPath: currentDir.path,
        environment: const {},
      );

      expect(path.normalize(resolved!), path.normalize(currentDir.path));
    });

    test(
      'falls back to executable directory when no bundle can be detected',
      () {
        final exeDir = Directory(path.join(tempRoot.path, 'bin'))
          ..createSync(recursive: true);
        final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
          resolvedExecutablePath: path.join(exeDir.path, 'dart.exe'),
          currentDirectoryPath: tempRoot.path,
          environment: const {},
        );

        expect(path.normalize(resolved!), path.normalize(exeDir.path));
      },
    );
  });

  group('resolveLinuxPrimaryLibraryDirectory', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync(
        'llamadart-linux-primary-',
      );
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('uses explicit environment override when valid', () {
      final overrideDir = Directory(path.join(tempRoot.path, 'override'))
        ..createSync(recursive: true);
      _createLinuxBundleMarkerFiles(overrideDir.path);

      final resolved = LlamaCppService.resolveLinuxPrimaryLibraryDirectory(
        resolvedExecutablePath: path.join(tempRoot.path, 'dart'),
        currentDirectoryPath: tempRoot.path,
        environment: {'LLAMADART_NATIVE_LIB_DIR': overrideDir.path},
      );

      expect(path.normalize(resolved!), path.normalize(overrideDir.path));
    });

    test('prefers executable-adjacent lib directory for packaged bundles', () {
      final bundleDir = Directory(path.join(tempRoot.path, 'bundle'))
        ..createSync(recursive: true);
      final executableDir = Directory(path.join(bundleDir.path, 'app'))
        ..createSync(recursive: true);
      final libDir = Directory(path.join(executableDir.path, 'lib'))
        ..createSync(recursive: true);
      _createLinuxBundleMarkerFiles(libDir.path);

      final resolved = LlamaCppService.resolveLinuxPrimaryLibraryDirectory(
        resolvedExecutablePath: path.join(executableDir.path, 'my_app'),
        currentDirectoryPath: bundleDir.path,
        environment: const {},
      );

      expect(path.normalize(resolved!), path.normalize(libDir.path));
    });

    test('falls back to current working directory lib folder', () {
      final currentDir = Directory(path.join(tempRoot.path, 'cwd'))
        ..createSync(recursive: true);
      final libDir = Directory(path.join(currentDir.path, 'lib'))
        ..createSync(recursive: true);
      _createLinuxBundleMarkerFiles(libDir.path, versionedPrimary: true);

      final resolved = LlamaCppService.resolveLinuxPrimaryLibraryDirectory(
        resolvedExecutablePath: path.join(tempRoot.path, 'dart'),
        currentDirectoryPath: currentDir.path,
        environment: const {},
      );

      expect(path.normalize(resolved!), path.normalize(libDir.path));
    });
  });

  group('Linux runtime dependency helpers', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync(
        'llamadart-linux-runtime-helpers-',
      );
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('copyMissingLinuxLibrary copies from the first available source', () {
      final targetDir = Directory(path.join(tempRoot.path, 'target'))
        ..createSync(recursive: true);
      final sourceA = Directory(path.join(tempRoot.path, 'source-a'))
        ..createSync(recursive: true);
      final sourceB = Directory(path.join(tempRoot.path, 'source-b'))
        ..createSync(recursive: true);
      File(path.join(sourceB.path, 'libggml.so')).writeAsStringSync('ggml');

      final diagnostics = <String>[];
      final copied = LlamaCppService.copyMissingLinuxLibrary(
        targetDirectory: targetDir.path,
        sourceDirectories: <String>[sourceA.path, sourceB.path],
        fileName: 'libggml.so',
        onDiagnostic: diagnostics.add,
      );

      expect(copied, isTrue);
      expect(
        File(path.join(targetDir.path, 'libggml.so')).readAsStringSync(),
        'ggml',
      );
      expect(diagnostics, isEmpty);
    });

    test('copyMissingLinuxLibrary reports copy failures', () {
      final targetDir = Directory(path.join(tempRoot.path, 'target'))
        ..createSync(recursive: true);
      Directory(path.join(targetDir.path, 'libggml.so')).createSync();
      final sourceDir = Directory(path.join(tempRoot.path, 'source'))
        ..createSync(recursive: true);
      File(path.join(sourceDir.path, 'libggml.so')).writeAsStringSync('ggml');

      final diagnostics = <String>[];
      final copied = LlamaCppService.copyMissingLinuxLibrary(
        targetDirectory: targetDir.path,
        sourceDirectories: <String>[sourceDir.path],
        fileName: 'libggml.so',
        onDiagnostic: diagnostics.add,
      );

      expect(copied, isFalse);
      expect(diagnostics, hasLength(1));
      expect(
        diagnostics.single,
        contains('Failed to copy Linux runtime dependency'),
      );
    });

    test('ensureLinuxSonameAlias creates fallback alias when missing', () {
      final targetDir = Directory(path.join(tempRoot.path, 'target'))
        ..createSync(recursive: true);
      final sourcePath = path.join(targetDir.path, 'libllama.so');
      File(sourcePath).writeAsStringSync('llama');

      final diagnostics = <String>[];
      final created = LlamaCppService.ensureLinuxSonameAlias(
        directory: targetDir.path,
        baseFileName: 'libllama.so',
        onDiagnostic: diagnostics.add,
      );

      expect(created, isTrue);
      expect(
        File('$sourcePath.0').existsSync() ||
            Link('$sourcePath.0').existsSync(),
        isTrue,
      );
      expect(diagnostics, isEmpty);
    });

    test('ensureLinuxSonameAlias reports alias creation failures', () {
      final targetDir = Directory(path.join(tempRoot.path, 'target'))
        ..createSync(recursive: true);
      final sourcePath = path.join(targetDir.path, 'libllama.so');
      File(sourcePath).writeAsStringSync('llama');
      Directory('$sourcePath.0').createSync();

      final diagnostics = <String>[];
      final created = LlamaCppService.ensureLinuxSonameAlias(
        directory: targetDir.path,
        baseFileName: 'libllama.so',
        onDiagnostic: diagnostics.add,
      );

      expect(created, isFalse);
      expect(diagnostics, hasLength(1));
      expect(
        diagnostics.single,
        contains('Failed to create or copy Linux SONAME alias'),
      );
    });
  });

  test('resolveBackendModuleDirectory returns null on unsupported hosts', () {
    if (Platform.isAndroid || Platform.isLinux || Platform.isWindows) {
      return;
    }

    expect(LlamaCppService.resolveBackendModuleDirectory(), isNull);
  });
}

void _createWindowsBundleMarkerFiles(
  String directoryPath, {
  String suffix = '',
}) {
  final markerFiles = <String>[
    'llama$suffix.dll',
    'ggml$suffix.dll',
    'ggml-cpu$suffix.dll',
  ];
  for (final fileName in markerFiles) {
    File(path.join(directoryPath, fileName)).writeAsStringSync('');
  }
}

void _createLinuxBundleMarkerFiles(
  String directoryPath, {
  bool versionedPrimary = false,
}) {
  final markerFiles = <String>[
    versionedPrimary ? 'libllamadart.so.0' : 'libllamadart.so',
    'libllama.so',
    'libggml.so',
  ];
  for (final fileName in markerFiles) {
    File(path.join(directoryPath, fileName)).writeAsStringSync('');
  }
}
