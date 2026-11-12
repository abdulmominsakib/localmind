import 'dart:math' as math;

import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/config/compute_device.dart';
import 'package:llamadart/src/core/models/config/flash_attention.dart';
import 'package:llamadart/src/core/models/config/gpu_backend.dart';
import 'package:llamadart/src/core/models/config/kv_cache_type.dart';
import 'package:llamadart/src/core/models/config/lora_config.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

void main() {
  test(
    'embedding-only loading is explicit and survives model parameter copies',
    () {
      expect(const ModelParams().liteRtLmEmbeddingEngine, isFalse);
      final params = const ModelParams(liteRtLmEmbeddingEngine: true);
      expect(params.copyWith(contextSize: 256).liteRtLmEmbeddingEngine, isTrue);
      expect(
        params.copyWith(liteRtLmEmbeddingEngine: false).liteRtLmEmbeddingEngine,
        isFalse,
      );
      expect(
        const ModelParams()
            .copyWith(liteRtLmEmbeddingEngine: true)
            .liteRtLmEmbeddingEngine,
        isTrue,
      );
    },
  );

  test('ModelParams defaults use automatic context batching', () {
    const params = ModelParams();

    expect(params.contextSize, 4096);
    expect(params.device, ComputeDevice.auto);
    expect(params.gpuLayers, ModelParams.maxGpuLayers);
    expect(params.preferredBackend, GpuBackend.auto);
    expect(params.liteRtLmBackend, LiteRtLmBackendPreference.auto);
    expect(params.liteRtLmActivationDataType, isNull);
    expect(params.liteRtLmPrefillChunkSize, isNull);
    expect(params.liteRtLmParallelFileSectionLoading, isNull);
    expect(params.liteRtLmDispatchLibDir, isNull);
    expect(params.splitMode, ModelSplitMode.layer);
    expect(params.mainGpu, 0);
    expect(params.chatTemplate, isNull);
    expect(params.numberOfThreads, 0);
    expect(params.numberOfThreadsBatch, 0);
    expect(params.batchSize, 0);
    expect(params.microBatchSize, 0);
    expect(ModelParams.defaultBatchSize, 2048);
    expect(ModelParams.defaultMicroBatchSize, 512);
    expect(params.maxParallelSequences, 1);
    expect(params.speculativeRollbackTokenMax, 0);
    expect(params.useMmap, isTrue);
    expect(params.useMlock, isFalse);
    expect(params.loadMtp, isFalse);
    expect(params.flashAttention, FlashAttention.auto);
    expect(params.cacheTypeK, KvCacheType.f16);
    expect(params.cacheTypeV, KvCacheType.f16);
    expect(params.kvUnified, isNull);
    expect(params.ropeFrequencyBase, isNull);
    expect(params.ropeFrequencyScale, isNull);
    expect(ModelParams.maxGpuLayers, 999);
  });

  group('resolveModelContextBatchSizes', () {
    test('uses standard defaults for a generative context', () {
      final resolved = resolveModelContextBatchSizes(
        const ModelParams(contextSize: 8192),
        8192,
      );

      expect(resolved.batchSize, ModelParams.defaultBatchSize);
      expect(resolved.microBatchSize, ModelParams.defaultMicroBatchSize);
    });

    test('supports the encoder-only full-context compatibility policy', () {
      final resolved = resolveModelContextBatchSizes(
        const ModelParams(contextSize: 8192),
        8192,
        useFullContextDefaults: true,
      );

      expect(resolved.batchSize, 8192);
      expect(resolved.microBatchSize, 8192);
    });

    test('explicit values override the encoder-only compatibility policy', () {
      final resolved = resolveModelContextBatchSizes(
        const ModelParams(
          contextSize: 8192,
          batchSize: 1024,
          microBatchSize: 256,
        ),
        8192,
        useFullContextDefaults: true,
      );

      expect(resolved.batchSize, 1024);
      expect(resolved.microBatchSize, 256);
    });
  });

  test('ModelParams copyWith updates selected fields', () {
    const params = ModelParams(contextSize: 1024);
    final updated = params.copyWith(
      device: ComputeDevice.gpu,
      gpuLayers: 2,
      preferredBackend: GpuBackend.metal,
      liteRtLmBackend: LiteRtLmBackendPreference.npu,
      liteRtLmActivationDataType: LiteRtLmActivationDataType.int8,
      liteRtLmPrefillChunkSize: 64,
      liteRtLmParallelFileSectionLoading: false,
      liteRtLmDispatchLibDir: '/tmp/dispatch',
      splitMode: ModelSplitMode.none,
      mainGpu: 1,
      batchSize: 256,
      microBatchSize: 64,
      maxParallelSequences: 8,
      speculativeRollbackTokenMax: 3,
    );

    expect(updated.contextSize, 1024);
    expect(updated.device, ComputeDevice.gpu);
    expect(updated.gpuLayers, 2);
    expect(updated.preferredBackend, GpuBackend.metal);
    expect(updated.liteRtLmBackend, LiteRtLmBackendPreference.npu);
    expect(updated.liteRtLmActivationDataType, LiteRtLmActivationDataType.int8);
    expect(updated.liteRtLmPrefillChunkSize, 64);
    expect(updated.liteRtLmParallelFileSectionLoading, isFalse);
    expect(updated.liteRtLmDispatchLibDir, '/tmp/dispatch');
    expect(updated.splitMode, ModelSplitMode.none);
    expect(updated.mainGpu, 1);
    expect(updated.batchSize, 256);
    expect(updated.microBatchSize, 64);
    expect(updated.maxParallelSequences, 8);
    expect(updated.speculativeRollbackTokenMax, 3);
  });

  test('ModelParams exposes load-time tuning knobs', () {
    const params = ModelParams(
      useMmap: false,
      useMlock: true,
      loadMtp: true,
      flashAttention: FlashAttention.enabled,
      cacheTypeK: KvCacheType.q8_0,
      cacheTypeV: KvCacheType.q8_0,
      kvUnified: true,
      ropeFrequencyBase: 1000000.0,
      ropeFrequencyScale: 0.5,
    );

    expect(params.useMmap, isFalse);
    expect(params.useMlock, isTrue);
    expect(params.loadMtp, isTrue);
    expect(params.flashAttention, FlashAttention.enabled);
    expect(params.cacheTypeK, KvCacheType.q8_0);
    expect(params.cacheTypeV, KvCacheType.q8_0);
    expect(params.kvUnified, isTrue);
    expect(params.ropeFrequencyBase, 1000000.0);
    expect(params.ropeFrequencyScale, 0.5);
  });

  test('ModelParams copyWith updates load-time tuning knobs', () {
    const params = ModelParams();
    final updated = params.copyWith(
      useMmap: false,
      useMlock: true,
      loadMtp: true,
      flashAttention: FlashAttention.enabled,
      cacheTypeK: KvCacheType.q4_0,
      cacheTypeV: KvCacheType.q8_0,
      kvUnified: false,
      ropeFrequencyBase: 500000.0,
      ropeFrequencyScale: 0.25,
    );

    expect(updated.useMmap, isFalse);
    expect(updated.useMlock, isTrue);
    expect(updated.loadMtp, isTrue);
    expect(updated.flashAttention, FlashAttention.enabled);
    expect(updated.cacheTypeK, KvCacheType.q4_0);
    expect(updated.cacheTypeV, KvCacheType.q8_0);
    expect(updated.kvUnified, isFalse);
    expect(updated.ropeFrequencyBase, 500000.0);
    expect(updated.ropeFrequencyScale, 0.25);
  });

  test('ModelParams copyWith preserves unspecified fields', () {
    const original = ModelParams(
      contextSize: 3072,
      device: ComputeDevice.cpu,
      gpuLayers: 8,
      preferredBackend: GpuBackend.cuda,
      liteRtLmBackend: LiteRtLmBackendPreference.gpu,
      liteRtLmActivationDataType: LiteRtLmActivationDataType.float16,
      liteRtLmPrefillChunkSize: 128,
      liteRtLmParallelFileSectionLoading: true,
      liteRtLmDispatchLibDir: '/opt/litert',
      splitMode: ModelSplitMode.row,
      mainGpu: 2,
      chatTemplate: 'custom-template',
      numberOfThreads: 6,
      numberOfThreadsBatch: 4,
      batchSize: 512,
      microBatchSize: 128,
      maxParallelSequences: 4,
      speculativeRollbackTokenMax: 3,
      useMmap: false,
      useMlock: true,
      loadMtp: true,
      flashAttention: FlashAttention.enabled,
      cacheTypeK: KvCacheType.q8_0,
      cacheTypeV: KvCacheType.q8_0,
      kvUnified: true,
      ropeFrequencyBase: 1000000.0,
      ropeFrequencyScale: 0.5,
    );

    final updated = original.copyWith(gpuLayers: 12);

    expect(updated.contextSize, 3072);
    expect(updated.device, ComputeDevice.cpu);
    expect(updated.gpuLayers, 12);
    expect(updated.preferredBackend, GpuBackend.cuda);
    expect(updated.liteRtLmBackend, LiteRtLmBackendPreference.gpu);
    expect(
      updated.liteRtLmActivationDataType,
      LiteRtLmActivationDataType.float16,
    );
    expect(updated.liteRtLmPrefillChunkSize, 128);
    expect(updated.liteRtLmParallelFileSectionLoading, isTrue);
    expect(updated.liteRtLmDispatchLibDir, '/opt/litert');
    expect(updated.splitMode, ModelSplitMode.row);
    expect(updated.mainGpu, 2);
    expect(updated.chatTemplate, 'custom-template');
    expect(updated.numberOfThreads, 6);
    expect(updated.numberOfThreadsBatch, 4);
    expect(updated.batchSize, 512);
    expect(updated.microBatchSize, 128);
    expect(updated.maxParallelSequences, 4);
    expect(updated.speculativeRollbackTokenMax, 3);
    expect(updated.useMmap, isFalse);
    expect(updated.useMlock, isTrue);
    expect(updated.loadMtp, isTrue);
    expect(updated.flashAttention, FlashAttention.enabled);
    expect(updated.cacheTypeK, KvCacheType.q8_0);
    expect(updated.cacheTypeV, KvCacheType.q8_0);
    expect(updated.kvUnified, isTrue);
    expect(updated.ropeFrequencyBase, 1000000.0);
    expect(updated.ropeFrequencyScale, 0.5);
  });

  group('validate(): speculative rollback settings', () {
    test('negative speculativeRollbackTokenMax throws '
        'LlamaArgumentException', () {
      const p = ModelParams(speculativeRollbackTokenMax: -1);
      expect(
        p.validate,
        throwsA(
          isA<LlamaArgumentException>()
              .having((e) => e.name, 'name', 'speculativeRollbackTokenMax')
              .having((e) => e.invalidValue, 'invalidValue', -1)
              .having(
                (e) => e.message,
                'message',
                'ModelParams.speculativeRollbackTokenMax must be '
                    'non-negative (got -1).',
              ),
        ),
      );
    });
  });

  group('validate(): GPU devices and tensor split', () {
    void rejects(ModelParams params, String name, String requirement) {
      expect(
        params.validate,
        throwsA(
          isA<LlamaArgumentException>()
              .having((e) => e.name, 'name', name)
              .having((e) => e.message, 'message', contains(requirement)),
        ),
        reason: requirement,
      );
    }

    test('rejects malformed device lists', () {
      rejects(const ModelParams(gpuDevices: []), 'gpuDevices', 'at least one');
      rejects(
        const ModelParams(gpuDevices: [0, -1]),
        'gpuDevices',
        'non-negative',
      );
      rejects(const ModelParams(gpuDevices: [1, 1]), 'gpuDevices', 'repeat');
    });

    test('rejects splits that are not finite, non-negative proportions', () {
      rejects(const ModelParams(tensorSplit: []), 'tensorSplit', 'at least');
      for (final bad in [-1.0, double.nan, double.infinity]) {
        rejects(
          ModelParams(tensorSplit: [1, bad]),
          'tensorSplit',
          'finite, non-negative',
        );
      }
      rejects(
        const ModelParams(tensorSplit: [0, 0]),
        'tensorSplit',
        'positive sum',
      );
    });

    test('rejects splits llama.cpp cannot hold as float32', () {
      const float32Max = 3.4028234663852886e38;
      for (final bad in [1e39, float32Max * 1.0000001]) {
        rejects(ModelParams(tensorSplit: [1, bad]), 'tensorSplit', 'float32');
      }
      // float32 rounds 2^-150, half the smallest subnormal, to 0 (ties to
      // even) and anything above it to the smallest subnormal.
      final halfSubnormal = math.pow(2.0, -150).toDouble();
      for (final bad in [1e-46, halfSubnormal]) {
        rejects(
          ModelParams(tensorSplit: [1, bad]),
          'tensorSplit',
          'nonzero proportion of at most 2^-150 '
              '(7.006492321624085e-46), which float32 rounds to 0',
        );
      }
      ModelParams(tensorSplit: [1, halfSubnormal * (1 + 1e-15)]).validate();
      const ModelParams(tensorSplit: [1, 1e-45]).validate();
      rejects(
        const ModelParams(tensorSplit: [float32Max, float32Max]),
        'tensorSplit',
        'sum',
      );
      // Rounded to float32, as llama.cpp stores it, this value is 2^103: half
      // an ulp of float32Max, so the float32 sum rounds to infinity.
      final roundsToHalfUlp = math.pow(2.0, 103) - math.pow(2.0, 77);
      rejects(
        ModelParams(tensorSplit: [float32Max, roundsToHalfUlp.toDouble()]),
        'tensorSplit',
        'sum',
      );
      const ModelParams(tensorSplit: [float32Max, 0]).validate();
      // The sum exceeds float32Max but rounds back to it in float32: below
      // half an ulp (2^103), so llama.cpp's float32 sum stays finite.
      ModelParams(
        tensorSplit: [float32Max, math.pow(2.0, 102).toDouble()],
      ).validate();
      const ModelParams(tensorSplit: [1, 1.5e-45]).validate();
    });

    test('rejects a split of another length than the device list', () {
      rejects(
        const ModelParams(gpuDevices: [0, 1], tensorSplit: [1]),
        'tensorSplit',
        'one proportion per gpuDevices entry (2)',
      );
    });

    test('rejects single-device and CPU loads', () {
      rejects(
        const ModelParams(gpuDevices: [0], splitMode: ModelSplitMode.none),
        'gpuDevices',
        'set mainGpu instead',
      );
      rejects(
        const ModelParams(tensorSplit: [1], splitMode: ModelSplitMode.none),
        'tensorSplit',
        'set mainGpu instead',
      );
      for (final params in [
        const ModelParams(gpuDevices: [0], gpuLayers: 0),
        const ModelParams(gpuDevices: [0], device: ComputeDevice.cpu),
        const ModelParams(gpuDevices: [0], preferredBackend: GpuBackend.cpu),
        const ModelParams(tensorSplit: [1], preferredBackend: GpuBackend.blas),
      ]) {
        rejects(
          params,
          params.gpuDevices != null ? 'gpuDevices' : 'tensorSplit',
          'offloads none',
        );
      }
    });

    test('copyWith clears both lists back to null', () {
      const params = ModelParams(gpuDevices: [1], tensorSplit: [1]);
      final cleared = params.copyWith(
        clearGpuDevices: true,
        clearTensorSplit: true,
      );
      expect(cleared.gpuDevices, isNull);
      expect(cleared.tensorSplit, isNull);
      final kept = params.copyWith(tensorSplit: [2]);
      expect(kept.gpuDevices, [1]);
      expect(kept.tensorSplit, [2]);
    });

    test('accepts lists for every multi-GPU split mode', () {
      for (final mode in [
        ModelSplitMode.layer,
        ModelSplitMode.row,
        ModelSplitMode.tensor,
      ]) {
        ModelParams(
          splitMode: mode,
          gpuDevices: const [2, 0],
          tensorSplit: const [3, 0],
        ).validate();
      }
      const ModelParams(tensorSplit: [1, 2, 0]).validate();
    });
  });

  group('validate(): MoE expert cache', () {
    test('a negative moeCacheBytes throws LlamaArgumentException', () {
      const p = LlamaCppModelParams(cpuMoeLayers: -1, moeCacheBytes: -1);
      expect(
        p.validate,
        throwsA(
          isA<LlamaArgumentException>()
              .having((e) => e.name, 'name', 'moeCacheBytes')
              .having((e) => e.invalidValue, 'invalidValue', -1)
              .having(
                (e) => e.message,
                'message',
                'LlamaCppModelParams.moeCacheBytes must be non-negative '
                    '(got -1).',
              ),
        ),
      );
    });

    test('a budget without host experts throws LlamaArgumentException', () {
      const p = ModelParams(moeCacheBytes: 1 << 20);
      expect(
        p.validate,
        throwsA(
          isA<LlamaArgumentException>()
              .having((e) => e.name, 'name', 'moeCacheBytes')
              .having(
                (e) => e.message,
                'message',
                contains('needs a nonzero cpuMoeLayers'),
              ),
        ),
      );
    });

    test('a budget with host experts, and host experts alone, pass', () {
      const ModelParams(cpuMoeLayers: -1, moeCacheBytes: 1 << 20).validate();
      const ModelParams(cpuMoeLayers: 3, moeCacheBytes: 1).validate();
      const ModelParams(cpuMoeLayers: 3).validate();
      const ModelParams().validate();
    });
  });

  group('validate(): device', () {
    Matcher rejects(String name, Object? value, String text) => throwsA(
      isA<LlamaArgumentException>()
          .having((e) => e.name, 'name', name)
          .having((e) => e.invalidValue, 'invalidValue', value)
          .having((e) => e.message, 'message', contains(text)),
    );

    test('auto accepts every llama.cpp and LiteRT-LM hint', () {
      for (final backend in GpuBackend.values) {
        for (final liteRtLm in LiteRtLmBackendPreference.values) {
          expect(
            ModelParams(
              preferredBackend: backend,
              gpuLayers: 0,
              liteRtLmBackend: liteRtLm,
            ).validate,
            returnsNormally,
          );
        }
      }
    });

    test('an explicit device rejects the deprecated liteRtLmBackend', () {
      for (final device in [
        ComputeDevice.cpu,
        ComputeDevice.gpu,
        ComputeDevice.npu,
      ]) {
        for (final liteRtLm in [
          LiteRtLmBackendPreference.cpu,
          LiteRtLmBackendPreference.gpu,
          LiteRtLmBackendPreference.npu,
        ]) {
          expect(
            ModelParams(device: device, liteRtLmBackend: liteRtLm).validate,
            rejects('liteRtLmBackend', liteRtLm.name, 'Set only device'),
            reason: '$device with $liteRtLm',
          );
        }
      }
    });

    test('cpu rejects a GPU preferredBackend', () {
      for (final backend in [
        GpuBackend.vulkan,
        GpuBackend.metal,
        GpuBackend.cuda,
        GpuBackend.opencl,
        GpuBackend.hip,
      ]) {
        expect(
          ModelParams(
            device: ComputeDevice.cpu,
            preferredBackend: backend,
          ).validate,
          rejects('preferredBackend', backend.name, 'device cpu'),
        );
      }
      for (final backend in [
        GpuBackend.auto,
        GpuBackend.cpu,
        GpuBackend.blas,
      ]) {
        expect(
          ModelParams(
            device: ComputeDevice.cpu,
            preferredBackend: backend,
          ).validate,
          returnsNormally,
        );
      }
      expect(
        const ModelParams(device: ComputeDevice.cpu, gpuLayers: 33).validate,
        returnsNormally,
      );
    });

    test('gpu and npu reject a CPU preferredBackend or 0 GPU layers', () {
      for (final device in [ComputeDevice.gpu, ComputeDevice.npu]) {
        for (final backend in [GpuBackend.cpu, GpuBackend.blas]) {
          expect(
            ModelParams(device: device, preferredBackend: backend).validate,
            rejects('preferredBackend', backend.name, 'runs on the CPU'),
          );
        }
        expect(
          ModelParams(device: device, gpuLayers: 0).validate,
          rejects('gpuLayers', 0, 'gpuLayers 0'),
        );
        expect(
          ModelParams(
            device: device,
            preferredBackend: GpuBackend.metal,
            gpuLayers: 20,
          ).validate,
          returnsNormally,
        );
      }
    });

    test('every device accepts negative gpuLayers, meaning all layers', () {
      for (final device in ComputeDevice.values) {
        for (final gpuLayers in [-1, -2]) {
          expect(
            ModelParams(device: device, gpuLayers: gpuLayers).validate,
            returnsNormally,
            reason: '$device with gpuLayers $gpuLayers',
          );
        }
      }
    });

    test('negative mainGpu with splitMode none uses platform semantics', () {
      for (final device in [ComputeDevice.gpu, ComputeDevice.npu]) {
        for (final mainGpu in [-1, -2]) {
          expect(
            ModelParams(
              device: device,
              splitMode: ModelSplitMode.none,
              mainGpu: mainGpu,
            ).validate,
            const bool.fromEnvironment('dart.library.js_interop')
                ? returnsNormally
                : rejects('mainGpu', mainGpu, 'splitMode none and mainGpu'),
            reason: '$device with mainGpu $mainGpu',
          );
        }
        expect(
          ModelParams(
            device: device,
            splitMode: ModelSplitMode.none,
            mainGpu: 0,
          ).validate,
          returnsNormally,
        );
        // llama.cpp reads main_gpu only under split_mode NONE.
        for (final splitMode in [ModelSplitMode.layer, ModelSplitMode.row]) {
          expect(
            ModelParams(
              device: device,
              splitMode: splitMode,
              mainGpu: -1,
            ).validate,
            returnsNormally,
          );
        }
      }
      for (final device in [ComputeDevice.auto, ComputeDevice.cpu]) {
        expect(
          ModelParams(
            device: device,
            splitMode: ModelSplitMode.none,
            mainGpu: -1,
          ).validate,
          returnsNormally,
        );
      }
    });
  });

  group('validate(): non-F16 KV requires flash attention', () {
    test('q8_0 K + flashAttention disabled throws LlamaArgumentException', () {
      const p = ModelParams(
        cacheTypeK: KvCacheType.q8_0,
        flashAttention: FlashAttention.disabled,
      );
      expect(
        p.validate,
        throwsA(
          isA<LlamaArgumentException>()
              .having((e) => e.name, 'name', isNull)
              .having((e) => e.message, 'message', contains('flashAttention')),
        ),
      );
    });

    test('q4_0 V + flashAttention disabled throws LlamaArgumentException', () {
      const p = ModelParams(
        cacheTypeV: KvCacheType.q4_0,
        flashAttention: FlashAttention.disabled,
      );
      expect(p.validate, throwsA(isA<LlamaArgumentException>()));
    });

    test('q8_0 K/V + flashAttention auto is allowed', () {
      const p = ModelParams(
        cacheTypeK: KvCacheType.q8_0,
        cacheTypeV: KvCacheType.q8_0,
        flashAttention: FlashAttention.auto,
      );
      expect(p.validate, returnsNormally);
    });

    test('q8_0 K/V + flashAttention enabled is allowed', () {
      const p = ModelParams(
        cacheTypeK: KvCacheType.q8_0,
        cacheTypeV: KvCacheType.q8_0,
        flashAttention: FlashAttention.enabled,
      );
      expect(p.validate, returnsNormally);
    });

    test('F16 K/V + flashAttention disabled is allowed', () {
      const p = ModelParams(flashAttention: FlashAttention.disabled);
      expect(p.validate, returnsNormally);
    });
  });

  group('validate(): LiteRT-LM runtime tuning fields', () {
    test('activation data type exposes upstream native values', () {
      expect(LiteRtLmActivationDataType.float32.nativeValue, 0);
      expect(LiteRtLmActivationDataType.float16.nativeValue, 1);
      expect(LiteRtLmActivationDataType.int16.nativeValue, 2);
      expect(LiteRtLmActivationDataType.int8.nativeValue, 3);
      expect(LiteRtLmActivationDataType.float16.optionName, 'float16');
    });

    test('positive prefill chunk size and dispatch dir are allowed', () {
      const p = ModelParams(
        liteRtLmPrefillChunkSize: 1,
        liteRtLmDispatchLibDir: '/vendor/litert',
      );
      expect(p.validate, returnsNormally);
    });

    test('non-positive prefill chunk size throws LlamaArgumentException', () {
      const p = ModelParams(liteRtLmPrefillChunkSize: 0);
      expect(
        p.validate,
        throwsA(
          isA<LlamaArgumentException>().having(
            (error) => error.name,
            'name',
            'liteRtLmPrefillChunkSize',
          ),
        ),
      );
    });

    test('LiteRT-LM cache options default to null', () {
      const p = ModelParams();
      expect(p.liteRtLmCacheDir, isNull);
      expect(p.liteRtLmMaxProgramCacheBytes, isNull);
      expect(p.validate, returnsNormally);
    });

    test('blank cache dir throws LlamaArgumentException', () {
      const p = ModelParams(liteRtLmCacheDir: ' ');
      expect(
        p.validate,
        throwsA(
          isA<LlamaArgumentException>().having(
            (error) => error.name,
            'name',
            'liteRtLmCacheDir',
          ),
        ),
      );
    });

    test('program cache cap below -1 throws LlamaArgumentException', () {
      const p = ModelParams(liteRtLmMaxProgramCacheBytes: -2);
      expect(
        p.validate,
        throwsA(
          isA<LlamaArgumentException>()
              .having(
                (error) => error.name,
                'name',
                'liteRtLmMaxProgramCacheBytes',
              )
              .having(
                (error) => error.message,
                'message',
                contains('unlimitedLiteRtLmProgramCacheBytes (-1)'),
              ),
        ),
      );
    });

    test('unlimited program cache cap is -1 and valid', () {
      expect(ModelParams.unlimitedLiteRtLmProgramCacheBytes, -1);
      const p = ModelParams(
        liteRtLmMaxProgramCacheBytes:
            ModelParams.unlimitedLiteRtLmProgramCacheBytes,
      );
      expect(p.validate, returnsNormally);
    });

    test('default program cache cap is 1 GiB', () {
      expect(
        ModelParams.defaultLiteRtLmMaxProgramCacheBytes,
        1024 * 1024 * 1024,
      );
    });

    test('zero program cache cap is valid', () {
      const p = ModelParams(liteRtLmMaxProgramCacheBytes: 0);
      expect(p.validate, returnsNormally);
    });

    test('blank dispatch dir throws LlamaArgumentException', () {
      const p = ModelParams(liteRtLmDispatchLibDir: '  ');
      expect(
        p.validate,
        throwsA(
          isA<LlamaArgumentException>().having(
            (error) => error.name,
            'name',
            'liteRtLmDispatchLibDir',
          ),
        ),
      );
    });
  });

  group('copyWith can clear nullable fields back to null', () {
    const populated = ModelParams(
      chatTemplate: 'custom-template',
      liteRtLmActivationDataType: LiteRtLmActivationDataType.float16,
      liteRtLmPrefillChunkSize: 128,
      liteRtLmParallelFileSectionLoading: false,
      liteRtLmDispatchLibDir: '/opt/litert',
      kvUnified: true,
      ropeFrequencyBase: 1000000.0,
      ropeFrequencyScale: 0.5,
    );

    test('clearChatTemplate: true sets chatTemplate to null', () {
      final cleared = populated.copyWith(clearChatTemplate: true);
      expect(cleared.chatTemplate, isNull);
      // Other fields preserved.
      expect(
        cleared.liteRtLmActivationDataType,
        LiteRtLmActivationDataType.float16,
      );
      expect(cleared.kvUnified, isTrue);
      expect(cleared.ropeFrequencyBase, 1000000.0);
    });

    test('clearLiteRtLmActivationDataType: true sets field to null', () {
      final cleared = populated.copyWith(clearLiteRtLmActivationDataType: true);
      expect(cleared.liteRtLmActivationDataType, isNull);
      expect(cleared.liteRtLmPrefillChunkSize, 128);
    });

    test('clearLiteRtLmPrefillChunkSize: true sets field to null', () {
      final cleared = populated.copyWith(clearLiteRtLmPrefillChunkSize: true);
      expect(cleared.liteRtLmPrefillChunkSize, isNull);
      expect(cleared.liteRtLmParallelFileSectionLoading, isFalse);
    });

    test(
      'clearLiteRtLmParallelFileSectionLoading: true sets field to null',
      () {
        final cleared = populated.copyWith(
          clearLiteRtLmParallelFileSectionLoading: true,
        );
        expect(cleared.liteRtLmParallelFileSectionLoading, isNull);
        expect(cleared.liteRtLmDispatchLibDir, '/opt/litert');
      },
    );

    test('copyWith sets, keeps, and clears LiteRT-LM cache options', () {
      final updated = populated.copyWith(
        liteRtLmCacheDir: '/data/litert-cache',
        liteRtLmMaxProgramCacheBytes: 1024,
      );
      expect(updated.liteRtLmCacheDir, '/data/litert-cache');
      expect(updated.liteRtLmMaxProgramCacheBytes, 1024);

      final kept = updated.copyWith(contextSize: 128);
      expect(kept.liteRtLmCacheDir, '/data/litert-cache');
      expect(kept.liteRtLmMaxProgramCacheBytes, 1024);

      final clearedDir = updated.copyWith(clearLiteRtLmCacheDir: true);
      expect(clearedDir.liteRtLmCacheDir, isNull);
      expect(clearedDir.liteRtLmMaxProgramCacheBytes, 1024);

      final clearedCap = updated.copyWith(
        clearLiteRtLmMaxProgramCacheBytes: true,
      );
      expect(clearedCap.liteRtLmCacheDir, '/data/litert-cache');
      expect(clearedCap.liteRtLmMaxProgramCacheBytes, isNull);
    });

    test('clearLiteRtLmDispatchLibDir: true sets field to null', () {
      final cleared = populated.copyWith(clearLiteRtLmDispatchLibDir: true);
      expect(cleared.liteRtLmDispatchLibDir, isNull);
      expect(
        cleared.liteRtLmActivationDataType,
        LiteRtLmActivationDataType.float16,
      );
    });

    test('clearKvUnified: true sets kvUnified to null', () {
      final cleared = populated.copyWith(clearKvUnified: true);
      expect(cleared.kvUnified, isNull);
      expect(cleared.chatTemplate, 'custom-template');
    });

    test('clearRopeFrequencyBase: true sets ropeFrequencyBase to null', () {
      final cleared = populated.copyWith(clearRopeFrequencyBase: true);
      expect(cleared.ropeFrequencyBase, isNull);
      expect(cleared.ropeFrequencyScale, 0.5);
    });

    test('clearRopeFrequencyScale: true sets ropeFrequencyScale to null', () {
      final cleared = populated.copyWith(clearRopeFrequencyScale: true);
      expect(cleared.ropeFrequencyScale, isNull);
      expect(cleared.ropeFrequencyBase, 1000000.0);
    });

    test('clear* flags can be combined with new value setters', () {
      final updated = populated.copyWith(
        clearKvUnified: true,
        ropeFrequencyBase: 2000000.0,
        clearRopeFrequencyScale: true,
      );
      expect(updated.kvUnified, isNull);
      expect(updated.ropeFrequencyBase, 2000000.0);
      expect(updated.ropeFrequencyScale, isNull);
    });

    test(
      'without clear flag, passing null does NOT clear (legacy behavior)',
      () {
        // This documents the pre-fix behavior: null means "argument omitted".
        final unchanged = populated.copyWith(kvUnified: null);
        expect(unchanged.kvUnified, isTrue);
      },
    );
  });

  group('runtime-specific subtypes', () {
    Matcher rejectsArgument(String name, String message) => throwsA(
      isA<LlamaArgumentException>()
          .having((e) => e.name, 'name', name)
          .having((e) => e.message, 'message', contains(message)),
    );

    test('LlamaCppModelParams sets llama.cpp fields only', () {
      const params = LlamaCppModelParams(
        contextSize: 8192,
        batchSize: 512,
        loadMtp: true,
        cacheTypeK: KvCacheType.q8_0,
        preferMemory64: true,
      );
      expect(params.contextSize, 8192);
      expect(params.batchSize, 512);
      expect(params.loadMtp, isTrue);
      expect(params.cacheTypeK, KvCacheType.q8_0);
      expect(params.preferMemory64, isTrue);
      expect(params.liteRtLmEmbeddingEngine, isFalse);
      expect(params.liteRtLmCacheDir, isNull);
      expect(params.gpuLayers, ModelParams.maxGpuLayers);
    });

    test('LiteRtLmModelParams maps unprefixed options to liteRtLm* fields', () {
      const params = LiteRtLmModelParams(
        contextSize: 2048,
        device: ComputeDevice.cpu,
        numberOfThreads: 4,
        embeddingEngine: true,
        activationDataType: LiteRtLmActivationDataType.float16,
        prefillChunkSize: 128,
        parallelFileSectionLoading: false,
        dispatchLibDir: '/vendor/litert',
        cacheDir: '/data/cache',
        maxProgramCacheBytes: 1024,
      );
      expect(params.liteRtLmEmbeddingEngine, isTrue);
      expect(
        params.liteRtLmActivationDataType,
        LiteRtLmActivationDataType.float16,
      );
      expect(params.liteRtLmPrefillChunkSize, 128);
      expect(params.liteRtLmParallelFileSectionLoading, isFalse);
      expect(params.liteRtLmDispatchLibDir, '/vendor/litert');
      expect(params.liteRtLmCacheDir, '/data/cache');
      expect(params.liteRtLmMaxProgramCacheBytes, 1024);
      expect(params.cacheDir, '/data/cache');
      expect(params.embeddingEngine, isTrue);
      expect(params.numberOfThreads, 4);
      expect(params.batchSize, 0);
      expect(params.useMmap, isTrue);
    });

    test('copyWith keeps the subtype, also through a ModelParams type', () {
      const ModelParams llamaCpp = LlamaCppModelParams(batchSize: 256);
      final copied = llamaCpp.copyWith(contextSize: 1024, kvUnified: true);
      expect(copied, isA<LlamaCppModelParams>());
      expect(copied.contextSize, 1024);
      expect(copied.batchSize, 256);
      expect(copied.kvUnified, isTrue);
      final LlamaCppModelParams cleared = (copied as LlamaCppModelParams)
          .copyWith(clearKvUnified: true);
      expect(cleared.kvUnified, isNull);

      const ModelParams liteRtLm = LiteRtLmModelParams(cacheDir: '/cache');
      final copiedLiteRtLm = liteRtLm.copyWith(contextSize: 1024);
      expect(copiedLiteRtLm, isA<LiteRtLmModelParams>());
      expect(copiedLiteRtLm.contextSize, 1024);
      expect(copiedLiteRtLm.liteRtLmCacheDir, '/cache');
    });

    test('LiteRtLmModelParams.copyWith sets and clears unprefixed options', () {
      const params = LiteRtLmModelParams(
        cacheDir: '/cache',
        prefillChunkSize: 64,
      );
      final updated = params.copyWith(
        cacheDir: '/other',
        clearPrefillChunkSize: true,
        dispatchLibDir: '/vendor',
        embeddingEngine: true,
      );
      expect(updated.cacheDir, '/other');
      expect(updated.prefillChunkSize, isNull);
      expect(updated.dispatchLibDir, '/vendor');
      expect(updated.embeddingEngine, isTrue);
      expect(updated.copyWith(clearCacheDir: true).cacheDir, isNull);
    });

    test('deprecated liteRtLm* arguments keep working', () {
      const base = ModelParams(liteRtLmCacheDir: '/cache');
      expect(
        base.copyWith(liteRtLmPrefillChunkSize: 32).liteRtLmCacheDir,
        '/cache',
      );
      expect(
        base.copyWith(clearLiteRtLmCacheDir: true).liteRtLmCacheDir,
        isNull,
      );

      const params = LiteRtLmModelParams(cacheDir: '/cache');
      final aliased = params.copyWith(
        liteRtLmDispatchLibDir: '/vendor',
        clearLiteRtLmCacheDir: true,
      );
      expect(aliased, isA<LiteRtLmModelParams>());
      expect(aliased.dispatchLibDir, '/vendor');
      expect(aliased.cacheDir, isNull);
      expect(
        params.copyWith(cacheDir: '/new', liteRtLmCacheDir: '/old').cacheDir,
        '/new',
      );
    });

    test('LiteRtLmModelParams.copyWith prefers the unprefixed embedding '
        'option and forwards the deprecated backend', () {
      const params = LiteRtLmModelParams();
      expect(
        params
            .copyWith(embeddingEngine: true, liteRtLmEmbeddingEngine: false)
            .embeddingEngine,
        isTrue,
      );
      expect(
        params
            .copyWith(embeddingEngine: false, liteRtLmEmbeddingEngine: true)
            .embeddingEngine,
        isFalse,
      );
      final updated = params.copyWith(
        liteRtLmBackend: LiteRtLmBackendPreference.gpu,
      );
      expect(updated, isA<LiteRtLmModelParams>());
      expect(updated.liteRtLmBackend, LiteRtLmBackendPreference.gpu);
    });

    test('copyWith rejects the other runtime\'s fields', () {
      const ModelParams llamaCpp = LlamaCppModelParams();
      expect(
        () => llamaCpp.copyWith(liteRtLmCacheDir: '/cache'),
        rejectsArgument(
          'liteRtLmCacheDir',
          'LlamaCppModelParams.copyWith does not take liteRtLmCacheDir',
        ),
      );
      const ModelParams liteRtLm = LiteRtLmModelParams();
      expect(
        () => liteRtLm.copyWith(batchSize: 256, loadMtp: false),
        rejectsArgument(
          'batchSize',
          'LiteRtLmModelParams.copyWith does not take batchSize, loadMtp',
        ),
      );
    });
  });

  group('runtime-specific subtypes keep every field', () {
    Map<String, Object?> fieldsOf(ModelParams p) => {
      'liteRtLmEmbeddingEngine': p.liteRtLmEmbeddingEngine,
      'contextSize': p.contextSize,
      'device': p.device,
      'gpuLayers': p.gpuLayers,
      'preferredBackend': p.preferredBackend,
      'liteRtLmBackend': p.liteRtLmBackend,
      'liteRtLmActivationDataType': p.liteRtLmActivationDataType,
      'liteRtLmPrefillChunkSize': p.liteRtLmPrefillChunkSize,
      'liteRtLmParallelFileSectionLoading':
          p.liteRtLmParallelFileSectionLoading,
      'liteRtLmDispatchLibDir': p.liteRtLmDispatchLibDir,
      'liteRtLmCacheDir': p.liteRtLmCacheDir,
      'liteRtLmMaxProgramCacheBytes': p.liteRtLmMaxProgramCacheBytes,
      'splitMode': p.splitMode,
      'mainGpu': p.mainGpu,
      'gpuDevices': p.gpuDevices,
      'tensorSplit': p.tensorSplit,
      'loras': p.loras.map((lora) => lora.path).toList(),
      'chatTemplate': p.chatTemplate,
      'numberOfThreads': p.numberOfThreads,
      'numberOfThreadsBatch': p.numberOfThreadsBatch,
      'batchSize': p.batchSize,
      'microBatchSize': p.microBatchSize,
      'maxParallelSequences': p.maxParallelSequences,
      'speculativeRollbackTokenMax': p.speculativeRollbackTokenMax,
      'useMmap': p.useMmap,
      'useMlock': p.useMlock,
      'loadMtp': p.loadMtp,
      'flashAttention': p.flashAttention,
      'cacheTypeK': p.cacheTypeK,
      'cacheTypeV': p.cacheTypeV,
      'kvUnified': p.kvUnified,
      'ropeFrequencyBase': p.ropeFrequencyBase,
      'ropeFrequencyScale': p.ropeFrequencyScale,
      'cpuMoeLayers': p.cpuMoeLayers,
      'moeCacheBytes': p.moeCacheBytes,
      'preferMemory64': p.preferMemory64,
      'modelBytesHint': p.modelBytesHint,
    };

    const llamaCpp = LlamaCppModelParams(
      contextSize: 1001,
      device: ComputeDevice.gpu,
      gpuLayers: 12,
      preferredBackend: GpuBackend.vulkan,
      splitMode: ModelSplitMode.row,
      mainGpu: 1,
      gpuDevices: [1, 0],
      tensorSplit: [0.75, 0.25],
      loras: [LoraAdapterConfig(path: '/a.gguf')],
      chatTemplate: 'template',
      numberOfThreads: 3,
      numberOfThreadsBatch: 4,
      batchSize: 256,
      microBatchSize: 64,
      maxParallelSequences: 2,
      speculativeRollbackTokenMax: 5,
      useMmap: false,
      useMlock: true,
      loadMtp: true,
      flashAttention: FlashAttention.enabled,
      cacheTypeK: KvCacheType.q8_0,
      cacheTypeV: KvCacheType.q4_0,
      kvUnified: true,
      ropeFrequencyBase: 10000,
      ropeFrequencyScale: 0.5,
      cpuMoeLayers: -1,
      moeCacheBytes: 1 << 30,
      preferMemory64: true,
      modelBytesHint: 123,
    );

    const liteRtLm = LiteRtLmModelParams(
      contextSize: 2002,
      device: ComputeDevice.cpu,
      gpuLayers: 0,
      preferredBackend: GpuBackend.cpu,
      loras: [LoraAdapterConfig(path: '/a.bin')],
      chatTemplate: 'template',
      numberOfThreads: 3,
      embeddingEngine: true,
      activationDataType: LiteRtLmActivationDataType.int8,
      prefillChunkSize: 64,
      parallelFileSectionLoading: true,
      dispatchLibDir: '/dispatch',
      cacheDir: '/cache',
      maxProgramCacheBytes: 77,
    );

    test('copyWith() copies every field', () {
      expect(fieldsOf(llamaCpp.copyWith()), fieldsOf(llamaCpp));
      expect(fieldsOf(liteRtLm.copyWith()), fieldsOf(liteRtLm));
    });

    test('LiteRtLmModelParams getters read their own fields', () {
      expect(liteRtLm.embeddingEngine, isTrue);
      expect(liteRtLm.activationDataType, LiteRtLmActivationDataType.int8);
      expect(liteRtLm.prefillChunkSize, 64);
      expect(liteRtLm.parallelFileSectionLoading, isTrue);
      expect(liteRtLm.dispatchLibDir, '/dispatch');
      expect(liteRtLm.cacheDir, '/cache');
      expect(liteRtLm.maxProgramCacheBytes, 77);
    });

    test('LlamaCppModelParams.copyWith replaces each field it takes', () {
      final replaced = llamaCpp.copyWith(
        contextSize: 2,
        device: ComputeDevice.cpu,
        gpuLayers: 0,
        preferredBackend: GpuBackend.cpu,
        splitMode: ModelSplitMode.layer,
        mainGpu: 0,
        gpuDevices: const [2],
        tensorSplit: const [1],
        loras: const [LoraAdapterConfig(path: '/b.gguf')],
        chatTemplate: 'other',
        numberOfThreads: 6,
        numberOfThreadsBatch: 7,
        batchSize: 128,
        microBatchSize: 32,
        maxParallelSequences: 3,
        speculativeRollbackTokenMax: 8,
        useMmap: true,
        useMlock: false,
        loadMtp: false,
        flashAttention: FlashAttention.disabled,
        cacheTypeK: KvCacheType.f16,
        cacheTypeV: KvCacheType.f16,
        kvUnified: false,
        ropeFrequencyBase: 20000,
        ropeFrequencyScale: 0.25,
        cpuMoeLayers: 4,
        moeCacheBytes: 1 << 20,
        preferMemory64: false,
        modelBytesHint: 456,
      );
      expect(fieldsOf(replaced), {
        ...fieldsOf(const ModelParams()),
        'contextSize': 2,
        'device': ComputeDevice.cpu,
        'gpuLayers': 0,
        'preferredBackend': GpuBackend.cpu,
        'gpuDevices': [2],
        'tensorSplit': [1.0],
        'loras': ['/b.gguf'],
        'chatTemplate': 'other',
        'numberOfThreads': 6,
        'numberOfThreadsBatch': 7,
        'batchSize': 128,
        'microBatchSize': 32,
        'maxParallelSequences': 3,
        'speculativeRollbackTokenMax': 8,
        'flashAttention': FlashAttention.disabled,
        'kvUnified': false,
        'ropeFrequencyBase': 20000.0,
        'ropeFrequencyScale': 0.25,
        'cpuMoeLayers': 4,
        'moeCacheBytes': 1 << 20,
        'preferMemory64': false,
        'modelBytesHint': 456,
      });
    });

    test('LiteRtLmModelParams.copyWith replaces each field it takes', () {
      final replaced = liteRtLm.copyWith(
        contextSize: 3,
        device: ComputeDevice.gpu,
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.auto,
        loras: const [LoraAdapterConfig(path: '/b.bin')],
        chatTemplate: 'other',
        numberOfThreads: 6,
        embeddingEngine: false,
        activationDataType: LiteRtLmActivationDataType.float32,
        prefillChunkSize: 32,
        parallelFileSectionLoading: false,
        dispatchLibDir: '/dispatch2',
        cacheDir: '/cache2',
        maxProgramCacheBytes: 88,
      );
      expect(fieldsOf(replaced), {
        ...fieldsOf(const ModelParams()),
        'contextSize': 3,
        'device': ComputeDevice.gpu,
        'loras': ['/b.bin'],
        'chatTemplate': 'other',
        'numberOfThreads': 6,
        'liteRtLmActivationDataType': LiteRtLmActivationDataType.float32,
        'liteRtLmPrefillChunkSize': 32,
        'liteRtLmParallelFileSectionLoading': false,
        'liteRtLmDispatchLibDir': '/dispatch2',
        'liteRtLmCacheDir': '/cache2',
        'liteRtLmMaxProgramCacheBytes': 88,
      });
    });

    test('copyWith rejects each argument and clear flag of the other '
        'runtime', () {
      const llamaCppOnly = <Symbol, Object>{
        #numberOfThreadsBatch: 1,
        #batchSize: 1,
        #microBatchSize: 1,
        #maxParallelSequences: 1,
        #speculativeRollbackTokenMax: 0,
        #splitMode: ModelSplitMode.layer,
        #mainGpu: 0,
        #gpuDevices: <int>[0],
        #clearGpuDevices: true,
        #tensorSplit: <double>[1],
        #clearTensorSplit: true,
        #useMmap: true,
        #useMlock: false,
        #loadMtp: false,
        #flashAttention: FlashAttention.auto,
        #cacheTypeK: KvCacheType.f16,
        #cacheTypeV: KvCacheType.f16,
        #kvUnified: true,
        #clearKvUnified: true,
        #ropeFrequencyBase: 1.0,
        #clearRopeFrequencyBase: true,
        #ropeFrequencyScale: 1.0,
        #clearRopeFrequencyScale: true,
        #cpuMoeLayers: -1,
        #moeCacheBytes: 1,
        #preferMemory64: true,
        #clearPreferMemory64: true,
        #modelBytesHint: 1,
        #clearModelBytesHint: true,
      };
      const liteRtLmOnly = <Symbol, Object>{
        #liteRtLmEmbeddingEngine: false,
        #liteRtLmBackend: LiteRtLmBackendPreference.auto,
        #liteRtLmActivationDataType: LiteRtLmActivationDataType.int8,
        #clearLiteRtLmActivationDataType: true,
        #liteRtLmPrefillChunkSize: 1,
        #clearLiteRtLmPrefillChunkSize: true,
        #liteRtLmParallelFileSectionLoading: true,
        #clearLiteRtLmParallelFileSectionLoading: true,
        #liteRtLmDispatchLibDir: '/d',
        #clearLiteRtLmDispatchLibDir: true,
        #liteRtLmCacheDir: '/c',
        #clearLiteRtLmCacheDir: true,
        #liteRtLmMaxProgramCacheBytes: 1,
        #clearLiteRtLmMaxProgramCacheBytes: true,
      };
      for (final (ModelParams params, arguments) in [
        (liteRtLm, llamaCppOnly),
        (llamaCpp, liteRtLmOnly),
      ]) {
        for (final MapEntry(key: argument, :value) in arguments.entries) {
          final name = argument.toString().split('"')[1];
          expect(
            () => Function.apply(params.copyWith, const [], {argument: value}),
            throwsA(
              isA<LlamaArgumentException>().having((e) => e.name, 'name', name),
            ),
            reason: '${params.runtimeType}.copyWith($name)',
          );
        }
      }
      expect(
        fieldsOf(llamaCpp.copyWith(clearKvUnified: false)),
        fieldsOf(llamaCpp),
      );
    });

    test('a clear flag of either spelling wins over a value for its field', () {
      expect(
        liteRtLm.copyWith(cacheDir: '/x', clearCacheDir: true).cacheDir,
        isNull,
      );
      expect(
        liteRtLm.copyWith(cacheDir: '/x', clearLiteRtLmCacheDir: true).cacheDir,
        isNull,
      );
      expect(
        liteRtLm.copyWith(liteRtLmCacheDir: '/x', clearCacheDir: true).cacheDir,
        isNull,
      );
      expect(
        liteRtLm
            .copyWith(activationDataType: LiteRtLmActivationDataType.float16)
            .activationDataType,
        LiteRtLmActivationDataType.float16,
      );
    });

    test('validation names a LiteRT-LM option as the type spells it', () {
      expect(
        () => const LiteRtLmModelParams(prefillChunkSize: 0).validate(),
        throwsA(
          isA<LlamaArgumentException>()
              .having((e) => e.name, 'name', 'prefillChunkSize')
              .having(
                (e) => e.message,
                'message',
                startsWith('LiteRtLmModelParams.prefillChunkSize must be'),
              ),
        ),
      );
      expect(
        () => const ModelParams(liteRtLmPrefillChunkSize: 0).validate(),
        throwsA(
          isA<LlamaArgumentException>()
              .having((e) => e.name, 'name', 'liteRtLmPrefillChunkSize')
              .having(
                (e) => e.message,
                'message',
                startsWith('ModelParams.liteRtLmPrefillChunkSize must be'),
              ),
        ),
      );
    });
  });
}
