import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/models/inference/model_params_runtime_support.dart';
import 'package:test/test.dart';

void main() {
  const liteRtLmFields = ModelParams(
    liteRtLmBackend: LiteRtLmBackendPreference.cpu,
    liteRtLmActivationDataType: LiteRtLmActivationDataType.float16,
    liteRtLmPrefillChunkSize: 128,
    liteRtLmParallelFileSectionLoading: false,
    liteRtLmDispatchLibDir: '/vendor/litert',
    liteRtLmCacheDir: '/data/litert-cache',
    liteRtLmMaxProgramCacheBytes: 1024,
  );
  const liteRtLmFieldNames = [
    'liteRtLmBackend',
    'liteRtLmActivationDataType',
    'liteRtLmPrefillChunkSize',
    'liteRtLmParallelFileSectionLoading',
    'liteRtLmDispatchLibDir',
    'liteRtLmCacheDir',
    'liteRtLmMaxProgramCacheBytes',
  ];
  const webGpuHints = ModelParams(
    preferMemory64: true,
    modelBytesHint: 1 << 30,
  );
  const llamaCppFields = ModelParams(
    numberOfThreadsBatch: 2,
    batchSize: 256,
    microBatchSize: 64,
    maxParallelSequences: 2,
    speculativeRollbackTokenMax: 4,
    useMmap: false,
    useMlock: true,
    loadMtp: true,
    flashAttention: FlashAttention.enabled,
    cacheTypeK: KvCacheType.q8_0,
    cacheTypeV: KvCacheType.q8_0,
    kvUnified: true,
    ropeFrequencyBase: 10000,
    ropeFrequencyScale: 1,
    cpuMoeLayers: -1,
    moeCacheBytes: 1 << 30,
    splitMode: ModelSplitMode.none,
    mainGpu: 1,
    gpuDevices: [0, 1],
    tensorSplit: [1, 1],
    gpuLayers: 12,
  );

  List<String> unsupported(
    ModelParams params,
    LlamaRuntime runtime, {
    required bool web,
  }) => modelParamsUnsupportedBy(params, runtime, web: web);

  test('unsupported LiteRT options do not advertise unavailable LoRA', () {
    try {
      checkModelParamsSupportedBy(
        const ModelParams(batchSize: 128),
        LlamaRuntime.liteRtLm,
        web: false,
      );
      fail('llama.cpp-only batch size must be rejected');
    } on LlamaUnsupportedException catch (error) {
      expect(error.toString(), contains('batchSize'));
      expect(error.toString().toLowerCase(), isNot(contains('lora')));
    }
  });
  test('defaults apply on every runtime', () {
    for (final runtime in LlamaRuntime.values) {
      for (final web in [false, true]) {
        expect(
          unsupported(const ModelParams(), runtime, web: web),
          isEmpty,
          reason: '$runtime web=$web',
        );
      }
    }
  });

  group('native llama.cpp', () {
    test('rejects every liteRtLm* field and the WebGPU memory hints', () {
      expect(
        unsupported(liteRtLmFields, LlamaRuntime.llamaCpp, web: false),
        liteRtLmFieldNames,
      );
      expect(unsupported(webGpuHints, LlamaRuntime.llamaCpp, web: false), [
        'preferMemory64',
        'modelBytesHint',
      ]);
    });

    test('applies its own fields', () {
      expect(
        unsupported(llamaCppFields, LlamaRuntime.llamaCpp, web: false),
        isEmpty,
      );
    });
  });

  group('llama.cpp on the Web', () {
    test('rejects liteRtLm* fields, memory mapping and MoE expert '
        'options', () {
      expect(
        unsupported(liteRtLmFields, LlamaRuntime.llamaCpp, web: true),
        liteRtLmFieldNames,
      );
      expect(unsupported(llamaCppFields, LlamaRuntime.llamaCpp, web: true), [
        'gpuDevices',
        'tensorSplit',
        'useMmap=false',
        'useMlock',
        'cpuMoeLayers',
        'moeCacheBytes',
      ]);
      expect(
        unsupported(
          const ModelParams(tensorSplit: [1]),
          LlamaRuntime.llamaCpp,
          web: true,
        ),
        ['tensorSplit'],
      );
      expect(
        unsupported(
          const ModelParams(cpuMoeLayers: 2),
          LlamaRuntime.llamaCpp,
          web: true,
        ),
        ['cpuMoeLayers'],
      );
    });

    test('applies the WebGPU memory hints', () {
      expect(unsupported(webGpuHints, LlamaRuntime.llamaCpp, web: true), []);
    });
  });

  group('native LiteRT-LM', () {
    test('applies its own fields', () {
      expect(
        unsupported(liteRtLmFields, LlamaRuntime.liteRtLm, web: false),
        isEmpty,
      );
    });

    test('rejects llama.cpp fields and the WebGPU memory hints', () {
      expect(unsupported(llamaCppFields, LlamaRuntime.liteRtLm, web: false), [
        'gpuLayers=12',
        'splitMode',
        'mainGpu',
        'gpuDevices',
        'tensorSplit',
        'numberOfThreadsBatch',
        'batchSize',
        'microBatchSize',
        'maxParallelSequences',
        'speculativeRollbackTokenMax',
        'useMmap=false',
        'useMlock',
        'loadMtp',
        'flashAttention',
        'cacheTypeK',
        'cacheTypeV',
        'kvUnified',
        'ropeFrequencyBase',
        'ropeFrequencyScale',
        'cpuMoeLayers',
        'moeCacheBytes',
      ]);
      expect(unsupported(webGpuHints, LlamaRuntime.liteRtLm, web: false), [
        'preferMemory64',
        'modelBytesHint',
      ]);
    });

    test('takes all-or-CPU gpuLayers hints', () {
      for (final gpuLayers in [0, -1, ModelParams.maxGpuLayers]) {
        expect(
          unsupported(
            ModelParams(gpuLayers: gpuLayers),
            LlamaRuntime.liteRtLm,
            web: false,
          ),
          isEmpty,
        );
      }
    });
  });

  group('LiteRT-LM on the Web', () {
    test('rejects native LiteRT-LM fields, threads and adapters', () {
      expect(
        unsupported(
          liteRtLmFields.copyWith(
            numberOfThreads: 4,
            loras: const [LoraAdapterConfig(path: 'adapter.bin')],
          ),
          LlamaRuntime.liteRtLm,
          web: true,
        ),
        ['loras', ...liteRtLmFieldNames.skip(1), 'numberOfThreads'],
      );
    });

    test('takes the deprecated runtime selector', () {
      expect(
        unsupported(
          const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.gpu),
          LlamaRuntime.liteRtLm,
          web: true,
        ),
        isEmpty,
      );
    });
  });

  test('checkModelParamsSupportedBy names the runtime and every field', () {
    expect(
      () => checkModelParamsSupportedBy(
        const ModelParams(liteRtLmCacheDir: '/cache', modelBytesHint: 1),
        LlamaRuntime.llamaCpp,
        web: false,
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          allOf(
            startsWith(
              'llama.cpp does not apply these ModelParams natively: '
              'liteRtLmCacheDir, modelBytesHint.',
            ),
            contains('only to LiteRT-LM (.litertlm) models'),
          ),
        ),
      ),
    );
    expect(
      () => checkModelParamsSupportedBy(
        const ModelParams(useMlock: true),
        LlamaRuntime.llamaCpp,
        web: true,
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          startsWith(
            'llama.cpp on the Web does not apply these ModelParams: '
            'useMlock.',
          ),
        ),
      ),
    );
    checkModelParamsSupportedBy(
      const ModelParams(),
      LlamaRuntime.liteRtLm,
      web: true,
    );
  });

  test('a runtime-specific subtype is rejected by the other runtime', () {
    for (final web in [false, true]) {
      checkModelParamsSupportedBy(
        const LlamaCppModelParams(),
        LlamaRuntime.llamaCpp,
        web: web,
      );
      checkModelParamsSupportedBy(
        const LiteRtLmModelParams(),
        LlamaRuntime.liteRtLm,
        web: web,
      );
      expect(
        () => checkModelParamsSupportedBy(
          const LlamaCppModelParams(),
          LlamaRuntime.liteRtLm,
          web: web,
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'message',
            'LlamaCppModelParams configures llama.cpp (GGUF) models, but this '
                'model runs on LiteRT-LM (.litertlm). Use LiteRtLmModelParams.',
          ),
        ),
      );
      expect(
        () => checkModelParamsSupportedBy(
          const LiteRtLmModelParams(),
          LlamaRuntime.llamaCpp,
          web: web,
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'message',
            'LiteRtLmModelParams configures LiteRT-LM (.litertlm) models, but '
                'this model runs on llama.cpp (GGUF). Use LlamaCppModelParams.',
          ),
        ),
      );
    }
    checkModelParamsTypeFor(const ModelParams(), LlamaRuntime.llamaCpp);
    checkModelParamsTypeFor(const ModelParams(), LlamaRuntime.liteRtLm);
  });

  test('LiteRT-LM Web names options the way LiteRtLmModelParams spells '
      'them', () {
    expect(
      unsupported(
        const LiteRtLmModelParams(cacheDir: '/c', prefillChunkSize: 8),
        LlamaRuntime.liteRtLm,
        web: true,
      ),
      ['prefillChunkSize', 'cacheDir'],
    );
    expect(
      unsupported(
        const ModelParams(liteRtLmCacheDir: '/c'),
        LlamaRuntime.liteRtLm,
        web: true,
      ),
      ['liteRtLmCacheDir'],
    );
  });
}
