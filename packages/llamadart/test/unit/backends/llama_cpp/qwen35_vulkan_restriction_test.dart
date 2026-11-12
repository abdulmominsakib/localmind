@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/load_device_selection.dart';
import 'package:llamadart/src/backends/llama_cpp/native_barrier_api.dart';
import 'package:llamadart/src/backends/llama_cpp/vulkan_device_probe.dart';
import 'package:llamadart/src/backends/llama_cpp/worker.dart';
import 'package:test/test.dart';

import '../../../support/fake_native_barrier.dart';
import '../../../support/recording_exit_teardown.dart';
import '../../../support/synthetic_embedding_gguf.dart';

void main() {
  late Directory temp;
  late String fixture;
  setUpAll(() => LlamaCppService().initializeBackend());
  setUp(() {
    temp = Directory.systemTemp.createTempSync('qwen35_restriction_');
    fixture = '${temp.path}/fixture.gguf';
    writeSyntheticLlamaGguf(fixture);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  ({
    LlamaCppService service,
    int model,
    RecordingExitTeardown calls,
    FakeNativeBarrier barrier,
  })
  load({
    String? architecture = 'qwen35',
    int subgroup = 16,
    bool android = true,
    bool cpu = false,
    int layers = ModelParams.maxGpuLayers,
    bool unknownFacts = false,
    bool noGpu = false,
    bool readNativeArchitecture = false,
    int probeCount = 1,
    bool cpuFallback = false,
    bool unreadableArchitecture = false,
    void Function()? onArchitectureRead,
    String? ggmlVersion = _unfixedGgml,
    void Function()? onGgmlVersionRead,
  }) {
    final real = ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!;
    final calls = RecordingExitTeardown(real);
    calls.modelLoad = (file, params) {
      // Only the model-load call is substituted: placement admission and
      // persisted backend identity still execute normally on the service.
      params.devices = nullptr;
      params.n_gpu_layers = 0;
      return real.modelLoadFromFile(file, params);
    };
    final barrier = FakeNativeBarrier(
      real: NativeBarrierApi.tryResolve(isWindows: Platform.isWindows),
    );
    final service = _VulkanService(
      isAndroid: android,
      objectCalls: LlamaCppObjectCalls.tracked(calls.api, barrier: barrier.api),
      modelArchitecture: readNativeArchitecture
          ? null
          : (_) {
              onArchitectureRead?.call();
              if (unreadableArchitecture) throw StateError('unreadable');
              return architecture;
            },
      deviceTypes: (_) => [
        ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value,
      ],
      registeredDevices: () => [
        GgmlDeviceEntry(
          name: 'Vulkan0',
          registry: 'Vulkan',
          type: ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value,
        ),
      ],
      backendDevices: (_) => null,
      ggmlVersion: () {
        onGgmlVersionRead?.call();
        return ggmlVersion;
      },
      vulkanDeviceProbe: () => unknownFacts
          ? const VulkanDeviceProbe.unavailable('unavailable')
          : VulkanDeviceProbe.devices([
              for (var i = 0; i < probeCount; i++)
                VulkanDeviceFacts(
                  name: 'Mali-G715',
                  deviceType: 1,
                  instanceApiVersion: VulkanDeviceFacts.vulkan12,
                  apiVersion: VulkanDeviceFacts.vulkan12,
                  subgroupSize: subgroup,
                ),
            ]),
    );
    addTearDown(barrier.dispose);
    addTearDown(service.dispose);
    if (cpuFallback) {
      service.initializeBackend();
      final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
      reflect(service).setField(
        MirrorSystem.getSymbol('_backendModuleDirectory', owner),
        temp.path,
      );
    }
    final model = service.loadModel(
      fixture,
      ModelParams(
        preferredBackend: cpu ? GpuBackend.cpu : GpuBackend.vulkan,
        gpuLayers: cpu ? 0 : layers,
        splitMode: noGpu ? ModelSplitMode.none : ModelSplitMode.layer,
        mainGpu: noGpu ? -1 : 0,
      ),
    );
    expect(
      service.getActiveBackendName(),
      cpu || noGpu || cpuFallback || layers == 0 ? 'CPU' : 'Vulkan',
    );
    return (service: service, model: model, calls: calls, barrier: barrier);
  }

  ModelParams contextParams([int microBatch = 0]) => ModelParams(
    contextSize: 128,
    numberOfThreads: 2,
    numberOfThreadsBatch: 2,
    microBatchSize: microBatch,
  );
  final refusal = throwsA(
    isA<LlamaUnsupportedException>().having(
      (e) => e.message,
      'diagnostic',
      allOf(contains('Android/Vulkan'), contains('948')),
    ),
  );

  for (final layers in [ModelParams.maxGpuLayers, -1]) {
    for (final size in [9, 32, 33, 64, 512]) {
      test(
        'persisted Vulkan load ($layers) refuses fresh context size $size before creation',
        () {
          final h = load(layers: layers);
          h.calls.clearCalls();
          expect(
            () => h.service.createContext(h.model, contextParams(size)),
            refusal,
          );
          expect(h.calls.calls, isEmpty);
        },
      );
    }
  }

  for (final size in [0, 1, 8]) {
    test(
      'fresh context size $size retains text cap, score and reuse after refusals',
      () async {
        final h = load();
        final context = h.service.createContext(h.model, contextParams(size));
        expect(
          h.calls.contextOffload.last.offloadKqv,
          isTrue,
          reason: 'fresh defaults preserve Qwen Vulkan KQV',
        );
        expect(h.calls.contextOffload.last.opOffload, isFalse);
        final cancel = calloc<Int8>();
        addTearDown(() => calloc.free(cancel));
        Future<void> generate(
          GenerationParams params, {
          List<LlamaContentPart>? parts,
        }) => h.service
            .generate(context, 'a' * 96, params, cancel.address, parts: parts)
            .drain<void>();
        final ordinary = GenerationParams(maxTokens: 1, temp: 0, seed: 1);
        h.calls.clearCalls();
        await generate(ordinary);
        expect(h.calls.decodedTokens.length, greaterThan(1));
        expect(
          h.calls.decodedTokens.every((n) => n <= (size == 1 ? 1 : 8)),
          isTrue,
        );
        final contexts = _private<Map>(h.service, '_contexts');
        final wrapper = contexts[context];
        final before = reflect(wrapper).getField(#cachedPromptTokens).reflectee;
        final requests = <(GenerationParams, List<LlamaContentPart>?)>[
          (ordinary, [const LlamaImageContent(path: 'not-opened')]),
          (ordinary, [const LlamaAudioContent(path: 'not-opened')]),
          (GenerationParams(speculativeDecoding: true), null),
          for (final strategy in SpeculativeDecodingStrategy.values)
            (
              GenerationParams(
                speculativeDecodingConfig: SpeculativeDecodingConfig(
                  strategy: strategy,
                ),
              ),
              null,
            ),
        ];
        for (final (params, parts) in requests) {
          h.calls.clearCalls();
          h.barrier.calls.clear();
          await expectLater(generate(params, parts: parts), refusal);
          expect(h.calls.calls, isEmpty);
          expect(h.barrier.calls, isEmpty);
          expect(
            reflect(wrapper).getField(#cachedPromptTokens).reflectee,
            same(before),
          );
          expect(
            reflect(wrapper).getField(#performanceAvailable).reflectee,
            isFalse,
          );
        }
        h.calls.clearCalls();
        h.barrier.calls.clear();
        expect(() => h.service.embed(context, 'a'), refusal);
        expect(() => h.service.embedBatch(context, ['a']), refusal);
        expect(
          () => h.service.embedContentBatch(context, [
            LlamaEmbeddingInput([const LlamaTextContent('a')]),
          ]),
          refusal,
        );
        expect(h.calls.calls, isEmpty);
        expect(h.barrier.calls, isEmpty);
        final capabilities = h.service.getEmbeddingCapabilities(context);
        expect(capabilities.text, isFalse);
        expect(capabilities.image, isFalse);
        expect(capabilities.audio, isFalse);
        expect(
          h.service
              .generationCapabilities(h.model)
              .speculativeDecodingStrategies,
          isEmpty,
        );
        _private<Map>(h.service, '_modelToMtmd')[h.model] = 1000;
        _private<Map>(h.service, '_mtmdContexts')[1000] =
            Pointer<mtmd_context>.fromAddress(0x30);
        expect(h.service.supportsVision(1000), isFalse);
        expect(h.service.supportsAudio(1000), isFalse);
        _private<Map>(h.service, '_mtmdContexts').clear();
        _private<Map>(h.service, '_modelToMtmd').clear();
        h.calls.clearCalls();
        await generate(ordinary);
        expect(h.calls.decodedTokens, isNotEmpty);
        expect(
          h.calls.decodedTokens.every((n) => n <= (size == 1 ? 1 : 8)),
          isTrue,
        );
        h.calls.clearCalls();
        await generate(
          const GenerationParams(
            maxTokens: 1,
            temp: 0,
            grammar: 'root ::= "a"',
            reusePromptPrefix: false,
          ),
        );
        expect(h.calls.calls, contains('llama_dart_sampler_sample'));
        expect(
          h.calls.decodedTokens.every((n) => n <= (size == 1 ? 1 : 8)),
          isTrue,
        );
        h.calls.clearCalls();
        h.service.scoreNextToken(
          context,
          'b' * 96,
          candidates: const [],
          topK: 1,
          reusePromptPrefix: false,
        );
        expect(
          h.calls.decodedTokens.every((n) => n <= (size == 1 ? 1 : 8)),
          isTrue,
        );
      },
    );
  }

  test(
    'speculation admission precedes every native reset and evaluation call',
    () async {
      final h = load();
      final context = h.service.createContext(h.model, contextParams());
      final cancel = calloc<Int8>();
      addTearDown(() => calloc.free(cancel));
      h.calls.clearCalls();
      h.barrier.calls.clear();
      Object? failure;
      try {
        await h.service
            .generate(
              context,
              'hello',
              const GenerationParams(maxTokens: 1, speculativeDecoding: true),
              cancel.address,
            )
            .drain<void>();
      } on Object catch (error) {
        failure = error;
      }
      expect(
        h.calls.calls,
        isEmpty,
        reason: 'no speculative init, decode or sampler calls',
      );
      expect(
        h.barrier.calls,
        isEmpty,
        reason: 'no context memory reset or tokenization',
      );
      expect(
        failure,
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'issue',
          contains('948'),
        ),
      );
    },
  );

  for (final cpuParams in [
    const ModelParams(device: ComputeDevice.cpu),
    const ModelParams(preferredBackend: GpuBackend.cpu),
  ]) {
    test(
      'CPU context preference cannot disable KQV on a loaded Vulkan Qwen model ($cpuParams)',
      () {
        final h = load();
        final context = h.service.createContext(
          h.model,
          cpuParams.copyWith(
            contextSize: 128,
            numberOfThreads: 2,
            numberOfThreadsBatch: 2,
          ),
        );
        expect(h.calls.contextOffload.single.offloadKqv, isTrue);
        expect(h.calls.contextOffload.single.opOffload, isFalse);
        expect(
          reflect(
            _private<Map>(h.service, '_contexts')[context],
          ).getField(#promptMicroBatchLimit).reflectee,
          8,
        );
      },
    );
  }
  test('admission and KQV policy reuse one native architecture value', () {
    var reads = 0;
    final h = load(onArchitectureRead: () => reads++);
    h.service.createContext(h.model, contextParams());
    h.service.generationCapabilities(h.model);
    expect(h.calls.contextOffload.single.offloadKqv, isTrue);
    expect(reads, 1);
    h.service.freeModel(h.model);
    expect(_private<Map>(h.service, '_modelArchitectures'), isEmpty);
  });
  for (final arch in ['Qwen3.5', 'qwen-3_5']) {
    test('native architecture normalization $arch restricts', () {
      final h = load(architecture: arch);
      expect(() => h.service.createContext(h.model, contextParams(9)), refusal);
    });
  }
  for (final architecture in [null, '']) {
    test('missing architecture refuses unsafe GPU admission', () {
      final h = load(architecture: architecture);
      h.calls.clearCalls();
      expect(() => h.service.createContext(h.model, contextParams()), refusal);
      expect(h.calls.calls, isEmpty);
    });
  }
  test('unreadable native architecture is a typed admission refusal', () {
    final h = load(unreadableArchitecture: true);
    h.calls.clearCalls();
    expect(() => h.service.createContext(h.model, contextParams()), refusal);
    expect(h.calls.calls, isEmpty);
  });
  test(
    'actual CPU fallback never probes missing architecture for admission',
    () {
      final h = load(cpuFallback: true, architecture: null);
      final context = h.service.createContext(h.model, contextParams(64));
      expect(h.service.getEmbeddingCapabilities(context).text, isTrue);
      expect(h.calls.contextOffload.last.offloadKqv, isFalse);
      expect(h.calls.contextOffload.last.opOffload, isFalse);
    },
  );
  test('unknown device facts retain conservative refusal', () {
    final h = load(unknownFacts: true);
    expect(() => h.service.createContext(h.model, contextParams(9)), refusal);
  });
  for (final subgroup in [0, 4, 16]) {
    test('unsafe or unknown subgroup $subgroup refuses larger batching', () {
      final h = load(subgroup: subgroup);
      expect(() => h.service.createContext(h.model, contextParams(9)), refusal);
    });
  }
  for (final count in [0, 2]) {
    test('empty or mismatched probe count $count cannot exempt Qwen', () {
      final h = load(subgroup: 32, probeCount: count);
      expect(() => h.service.createContext(h.model, contextParams(9)), refusal);
    });
  }
  for (final subgroup in [8, 32, 64]) {
    test('complete safe subgroup $subgroup retains features', () {
      final h = load(subgroup: subgroup);
      final context = h.service.createContext(h.model, contextParams(64));
      expect(
        h.service.generationCapabilities(h.model).speculativeDecodingStrategies,
        isNotEmpty,
      );
      expect(h.service.getEmbeddingCapabilities(context).text, isTrue);
    });
  }
  for (final architecture in ['llama', 'qwen35moe']) {
    test('known other architecture $architecture is unchanged', () {
      final h = load(architecture: architecture);
      final context = h.service.createContext(h.model, contextParams(64));
      expect(
        h.service.generationCapabilities(h.model).speculativeDecodingStrategies,
        isNotEmpty,
      );
      expect(h.service.getEmbeddingCapabilities(context).text, isTrue);
    });
  }
  test('CPU load with Vulkan context preference retains embeddings', () {
    final h = load(cpu: true);
    final context = h.service.createContext(
      h.model,
      const ModelParams(
        contextSize: 128,
        preferredBackend: GpuBackend.vulkan,
        microBatchSize: 64,
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
      ),
    );
    expect(h.service.getEmbeddingCapabilities(context).text, isTrue);
    expect(h.service.embed(context, 'a'), isNotEmpty);
    expect(h.calls.contextOffload.last.offloadKqv, isFalse);
    expect(h.calls.contextOffload.last.opOffload, isFalse);
  });
  for (final noGpu in [false, true]) {
    test('actual no-GPU placement disables context offload ($noGpu)', () {
      final h = load(layers: noGpu ? 999 : 0, noGpu: noGpu);
      final context = h.service.createContext(
        h.model,
        const ModelParams(
          contextSize: 128,
          preferredBackend: GpuBackend.vulkan,
          microBatchSize: 64,
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
        ),
      );
      expect(h.service.getEmbeddingCapabilities(context).text, isTrue);
      expect(h.calls.contextOffload.last.offloadKqv, isFalse);
      expect(h.calls.contextOffload.last.opOffload, isFalse);
    });
  }
  test('native architecture accessor exempts a known non-Qwen fixture', () {
    final h = load(readNativeArchitecture: true);
    expect(h.service.createContext(h.model, contextParams(64)), greaterThan(0));
  });
  test('another active CPU model cannot change the first model admission', () {
    final h = load();
    final cpu = h.service.loadModel(fixture, const ModelParams(gpuLayers: 0));
    expect(h.service.getActiveBackendName(), 'CPU');
    expect(() => h.service.createContext(h.model, contextParams(9)), refusal);
    expect(h.service.createContext(cpu, contextParams(64)), greaterThan(0));
    h.service.freeModel(h.model);
    expect(
      _private<Map>(h.service, '_modelResolvedBackends').containsKey(h.model),
      isFalse,
    );
  });
  test(
    'public worker and engine task preserve typed refusal, reuse and reload',
    () async {
      final backend = NativeLlamaBackend(workerEntrypoint: _restrictedWorker);
      final model = await backend.modelLoad(
        fixture,
        const ModelParams(preferredBackend: GpuBackend.vulkan),
      );
      await expectLater(
        backend.contextCreate(model, contextParams(9)),
        refusal,
      );
      await backend.dispose();
      final engine = LlamaEngine(
        NativeLlamaBackend(workerEntrypoint: _restrictedWorker),
      );
      addTearDown(engine.dispose);
      final llamaModel = LlamaModel(ModelSource.path(fixture));
      const params = ModelParams(
        preferredBackend: GpuBackend.vulkan,
        contextSize: 128,
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
      );
      await engine.setModel(llamaModel, params: params);
      expect(
        (await engine.capabilities).speculativeDecodingStrategies,
        isEmpty,
      );
      expect((await engine.embeddingCapabilities).text, isFalse);
      await expectLater(
        engine
            .generate(
              'hello',
              params: GenerationParams(
                speculativeDecodingConfig:
                    SpeculativeDecodingConfig.draftSimple(
                      draftModel: ModelSource.path(
                        '${temp.path}/must-not-be-opened.gguf',
                      ),
                    ),
              ),
            )
            .drain<void>(),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'pre-I/O refusal',
            contains('not downloaded'),
          ),
        ),
      );
      await expectLater(engine.embed('a'), refusal);
      await expectLater(engine.embedBatch(['a']), refusal);
      await expectLater(
        engine
            .generate(
              'hello',
              parts: [const LlamaImageContent(path: 'not-opened')],
            )
            .drain<void>(),
        refusal,
      );
      final task = engine.generateTask(
        'hello',
        params: const GenerationParams(speculativeDecoding: true),
      );
      final done = await task.done;
      expect(done.state, GenerationTaskState.failed);
      expect(done.error, isA<LlamaUnsupportedException>());
      expect(done.result, isNull);
      expect(done.partialResult, isEmpty);
      await task.events.drain<void>();
      await engine
          .generate('hello', params: const GenerationParams(maxTokens: 1))
          .drain<void>();
      await engine.setModel(llamaModel, params: params);
      await expectLater(
        engine
            .generate(
              'hello',
              params: const GenerationParams(
                speculativeDecodingConfig:
                    SpeculativeDecodingConfig.ngramSimple(),
              ),
            )
            .drain<void>(),
        refusal,
      );
      await engine
          .generate('hello', params: const GenerationParams(maxTokens: 1))
          .drain<void>();
    },
  );
  test('Vulkan outside Android retains feature admission', () {
    final h = load(android: false);
    expect(h.service.createContext(h.model, contextParams(64)), greaterThan(0));
  });

  for (final version in [null, '', 'unknown', '0.9.4']) {
    test(
      'runtime without a fixed ggml version ($version) keeps restriction',
      () {
        final h = load(ggmlVersion: version);
        expect(
          () => h.service.createContext(h.model, contextParams(9)),
          refusal,
        );
        expect(
          h.service
              .generationCapabilities(h.model)
              .speculativeDecodingStrategies,
          isEmpty,
        );
      },
    );
  }

  test('older-runtime refusals name the fix version, runtime and issue', () async {
    const restriction =
        'Qwen3.5 on Android/Vulkan with a llama.cpp runtime older than ggml '
        '0.28.0 (llamadart-native v0.8.0) and unsafe or unproven small-matmul '
        'subgroup facts supports ordinary text only, with microBatchSize unset '
        'or 1..8 (https://github.com/leehack/llamadart/issues/948). Use the '
        'bundled runtime, or ComputeDevice.cpu for larger batches, media, '
        'speculation or embeddings.';
    Matcher message(String text) => throwsA(
      isA<LlamaUnsupportedException>().having(
        (e) => e.message,
        'message',
        text,
      ),
    );
    final h = load();
    expect(
      () => h.service.createContext(h.model, contextParams(9)),
      message('microBatchSize=9 is unavailable. $restriction'),
    );
    final context = h.service.createContext(h.model, contextParams());
    expect(
      () => h.service.embed(context, 'a'),
      message('Embeddings are unavailable. $restriction'),
    );
    final cancel = calloc<Int8>();
    addTearDown(() => calloc.free(cancel));
    await expectLater(
      h.service
          .generate(
            context,
            'hello',
            const GenerationParams(speculativeDecoding: true),
            cancel.address,
          )
          .drain<void>(),
      message(restriction),
    );
    final missing = load(architecture: null);
    expect(
      () => missing.service.createContext(missing.model, contextParams()),
      message(
        'Cannot establish required model safety for Android/Vulkan with a '
        'llama.cpp runtime older than ggml 0.28.0 (llamadart-native v0.8.0) '
        'and unsafe or unproven small-matmul subgroup facts: native '
        'general.architecture is unavailable '
        '(https://github.com/leehack/llamadart/issues/948). Use the bundled '
        'runtime or ComputeDevice.cpu.',
      ),
    );
  });

  group('projector placement', () {
    for (final version in [_unfixedGgml, '0.29.0']) {
      test('keeps a Qwen3.5 projector on the CPU on ggml $version', () {
        final h = load(ggmlVersion: version);
        expect(_projectorUsesGpu(h.service, h.model), isFalse);
      });
    }
    test('keeps the projector on the CPU without an architecture', () {
      for (final unreadable in [false, true]) {
        final h = load(
          ggmlVersion: '0.29.0',
          architecture: null,
          unreadableArchitecture: unreadable,
        );
        expect(_projectorUsesGpu(h.service, h.model), isFalse);
      }
    });
    for (final architecture in ['llama', 'qwen3', 'qwen35moe']) {
      test('leaves $architecture projectors on the GPU', () {
        final h = load(ggmlVersion: '0.29.0', architecture: architecture);
        expect(_projectorUsesGpu(h.service, h.model), isTrue);
      });
    }
    test('leaves Qwen3.5 on the GPU with safe subgroup facts', () {
      final h = load(ggmlVersion: '0.29.0', subgroup: 32);
      expect(_projectorUsesGpu(h.service, h.model), isTrue);
    });
    test('leaves Qwen3.5 on the GPU outside Android', () {
      final h = load(ggmlVersion: '0.29.0', android: false);
      expect(_projectorUsesGpu(h.service, h.model), isTrue);
    });
  });

  group('runtime with the small matmul tile fix', () {
    for (final version in ['0.28.0', '0.29.0']) {
      test('admits Qwen3.5 batches above 8 on ggml $version', () async {
        final h = load(ggmlVersion: version);
        for (final size in [9, 32, 33, 64, 512]) {
          final context = h.service.createContext(h.model, contextParams(size));
          expect(
            h.calls.contextOffload.last.offloadKqv,
            isTrue,
            reason: 'Qwen3.5 keeps KQV on Vulkan',
          );
          expect(h.calls.contextOffload.last.opOffload, isFalse);
          expect(
            reflect(
              _private<Map>(h.service, '_contexts')[context],
            ).getField(#promptMicroBatchLimit).reflectee,
            isNull,
          );
          h.service.freeContext(context);
        }
        final context = h.service.createContext(h.model, contextParams(64));
        final cancel = calloc<Int8>();
        addTearDown(() => calloc.free(cancel));
        h.calls.clearCalls();
        await h.service
            .generate(
              context,
              'a' * 96,
              GenerationParams(maxTokens: 1, temp: 0, seed: 1),
              cancel.address,
            )
            .drain<void>();
        expect(h.calls.decodedTokens.first, greaterThan(8));
      });
    }

    test('keeps the 8-token prompt cap as the unset default', () async {
      final h = load(ggmlVersion: '0.29.0');
      final context = h.service.createContext(h.model, contextParams());
      expect(
        reflect(
          _private<Map>(h.service, '_contexts')[context],
        ).getField(#promptMicroBatchLimit).reflectee,
        8,
      );
      final cancel = calloc<Int8>();
      addTearDown(() => calloc.free(cancel));
      h.calls.clearCalls();
      await h.service
          .generate(
            context,
            'a' * 96,
            GenerationParams(maxTokens: 1, temp: 0, seed: 1),
            cancel.address,
          )
          .drain<void>();
      expect(h.calls.decodedTokens.length, greaterThan(1));
      expect(h.calls.decodedTokens.every((n) => n <= 8), isTrue);
    });

    test('admits speculation, embeddings and media projectors', () async {
      final h = load(ggmlVersion: '0.29.0');
      final context = h.service.createContext(h.model, contextParams(64));
      expect(
        h.service.generationCapabilities(h.model).speculativeDecodingStrategies,
        containsAll(SpeculativeDecodingStrategy.values),
      );
      expect(h.service.getEmbeddingCapabilities(context).text, isTrue);
      expect(h.service.embed(context, 'a'), isNotEmpty);
      expect(h.service.embedBatch(context, ['a', 'b']), hasLength(2));
      _private<Map>(h.service, '_modelToMtmd')[h.model] = 1000;
      addTearDown(() => _private<Map>(h.service, '_modelToMtmd').clear());
      final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
      expect(
        reflect(h.service).invoke(
          MirrorSystem.getSymbol('_projectorHasQwen35VulkanRestriction', owner),
          [1000],
        ).reflectee,
        isFalse,
      );
      final cancel = calloc<Int8>();
      addTearDown(() => calloc.free(cancel));
      h.calls.clearCalls();
      await h.service
          .generate(
            context,
            'a' * 96,
            GenerationParams(
              maxTokens: 2,
              temp: 0,
              seed: 1,
              speculativeDecodingConfig:
                  const SpeculativeDecodingConfig.ngramSimple(),
            ),
            cancel.address,
          )
          .drain<void>();
      expect(h.calls.decodedTokens, isNotEmpty);
    });

    test('a CPU context preference still keeps KQV on the Vulkan model', () {
      final h = load(ggmlVersion: '0.29.0');
      final context = h.service.createContext(
        h.model,
        const ModelParams(
          device: ComputeDevice.cpu,
          contextSize: 128,
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
          microBatchSize: 64,
        ),
      );
      expect(h.calls.contextOffload.single.offloadKqv, isTrue);
      expect(h.calls.contextOffload.single.opOffload, isFalse);
      expect(
        reflect(
          _private<Map>(h.service, '_contexts')[context],
        ).getField(#promptMicroBatchLimit).reflectee,
        isNull,
      );
    });

    test('does not need the model architecture', () {
      final h = load(ggmlVersion: '0.28.0', architecture: null);
      final context = h.service.createContext(h.model, contextParams(64));
      expect(h.service.getEmbeddingCapabilities(context).text, isTrue);
      expect(
        h.service.generationCapabilities(h.model).speculativeDecodingStrategies,
        isNotEmpty,
      );
    });

    test('reads the ggml version once per service', () {
      var reads = 0;
      final h = load(ggmlVersion: '0.29.0', onGgmlVersionRead: () => reads++);
      h.service.createContext(h.model, contextParams(64));
      h.service.createContext(h.model, contextParams(64));
      h.service.generationCapabilities(h.model);
      expect(reads, 1);
    });
  });
}

bool _projectorUsesGpu(LlamaCppService service, int model) {
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  final params =
      reflect(service).invoke(
            MirrorSystem.getSymbol('_mtmdContextParamsFor', owner),
            [model],
          ).reflectee
          as mtmd_context_params;
  return params.use_gpu;
}

/// The last ggml version some llama.cpp commits without the small matmul tile
/// fix report: the restriction applies on this runtime.
const _unfixedGgml = '0.27.0';

T _private<T>(Object target, String name) {
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  return reflect(target).getField(MirrorSystem.getSymbol(name, owner)).reflectee
      as T;
}

class _VulkanService extends LlamaCppService {
  _VulkanService({
    super.isAndroid,
    super.objectCalls,
    super.modelArchitecture,
    super.deviceTypes,
    super.registeredDevices,
    super.backendDevices,
    super.vulkanDeviceProbe,
    super.ggmlVersion,
  });
  @override
  List<String> getBackendInfo() => const ['CPU', 'Vulkan (injected registry)'];
}

void _restrictedWorker(SendPort initialSendPort) {
  final real = ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!;
  final calls = RecordingExitTeardown(real);
  calls.modelLoad = (file, params) {
    params.devices = nullptr;
    params.n_gpu_layers = 0;
    return real.modelLoadFromFile(file, params);
  };
  runLlamaWorkerForTesting(
    initialSendPort,
    _VulkanService(
      isAndroid: true,
      objectCalls: LlamaCppObjectCalls.tracked(
        calls.api,
        barrier: NativeBarrierApi.tryResolve(isWindows: Platform.isWindows),
      ),
      modelArchitecture: (_) => 'qwen35',
      deviceTypes: (_) => [
        ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value,
      ],
      registeredDevices: () => [
        GgmlDeviceEntry(
          name: 'Vulkan0',
          registry: 'Vulkan',
          type: ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value,
        ),
      ],
      backendDevices: (_) => null,
      ggmlVersion: () => _unfixedGgml,
      vulkanDeviceProbe: () =>
          const VulkanDeviceProbe.unavailable('not probed'),
    ),
  );
}
