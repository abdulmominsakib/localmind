@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:mirrors';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/gpu_device_placement.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/load_device_selection.dart';
import 'package:llamadart/src/backends/llama_cpp/vulkan_device_probe.dart';
import 'package:test/test.dart';

import '../../../support/recording_allocator.dart';
import '../../../support/recording_exit_teardown.dart';
import '../../../support/synthetic_decision_head.dart';
import '../../../support/synthetic_embedding_gguf.dart';

const _load = 'llama_dart_model_load_from_file';
final int _gpu = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value;

GgmlDeviceEntry _fake(String name, String registry, int address) =>
    GgmlDeviceEntry(
      name: name,
      registry: registry,
      description: name,
      type: _gpu,
      device: Pointer.fromAddress(address),
    );

Object? _private(LlamaCppService service, String field) {
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  return reflect(
    service,
  ).getField(MirrorSystem.getSymbol(field, owner)).reflectee;
}

T _invokePrivate<T>(
  LlamaCppService service,
  String method,
  List<Object?> args,
) {
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  return reflect(
        service,
      ).invoke(MirrorSystem.getSymbol(method, owner), args).reflectee
      as T;
}

void _setPrivate(LlamaCppService service, String field, Object? value) {
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  reflect(service).setField(MirrorSystem.getSymbol(field, owner), value);
}

Object? _loadDraft(LlamaCppService service, int target, String model) {
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  return reflect(service)
      .invoke(
        MirrorSystem.getSymbol('_loadSpeculativeDraftModel', owner),
        [target, model, 'Draft model'],
        {#loadMtp: false},
      )
      .reflectee;
}

// Fake devices must never reach llama.cpp: tests either stop before the load
// or replace its device params at the recording boundary with a CPU load.
void main() {
  late Directory dir;
  late String model;
  late RecordingExitTeardown recorder;
  late LlamaCppService service;
  late RecordingAllocator allocator;

  void start({
    List<GgmlDeviceEntry> Function()? registeredDevices,
    VulkanDeviceProbe probe = const VulkanDeviceProbe.unavailable('test'),
    bool Function(GgmlDeviceEntry device)? splitBufferTypeProbe,
    List<ggml_backend_dev_t>? Function(GpuBackend backend)? backendDevices,
    List<int> Function(GpuBackend backend)? deviceTypes,
  }) {
    allocator = RecordingAllocator();
    recorder = RecordingExitTeardown(
      ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
    );
    service = LlamaCppService(
      isMacosX64: false,
      objectCalls: LlamaCppObjectCalls.tracked(
        recorder.api,
        isWindows: Platform.isWindows,
      ),
      registeredDevices: registeredDevices,
      vulkanDeviceProbe: () => probe,
      splitBufferTypeProbe: splitBufferTypeProbe,
      backendDevices: backendDevices,
      deviceTypes: deviceTypes,
      modelLoadAllocator: allocator,
    )..initializeBackend();
  }

  Matcher refused(Object message) => throwsA(
    isA<LlamaUnsupportedException>().having(
      (e) => e.message,
      'message',
      allOf(contains('llama.cpp multi-GPU placement'), message),
    ),
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('llamadart_gpu_devices_');
    model = writeSyntheticLlamaGguf('${dir.path}/model.gguf').path;
  });

  tearDown(() {
    service.dispose();
    dir.deleteSync(recursive: true);
  });

  test('a device index the host does not have is refused before the '
      'load', () {
    start(registeredDevices: () => [_fake('CUDA0', 'CUDA', 0x1000)]);
    expect(
      () => service.loadModel(model, const ModelParams(gpuDevices: [0, 1])),
      refused(contains('this host has 1 (CUDA0)')),
    );
    expect(recorder.calls, isNot(contains(_load)));
  });

  test('a split for another device count is refused before the load', () {
    start(
      registeredDevices: () => [
        _fake('CUDA0', 'CUDA', 0x1000),
        _fake('CUDA1', 'CUDA', 0x2000),
      ],
    );
    expect(
      () => service.loadModel(model, const ModelParams(tensorSplit: [1])),
      refused(contains('tensorSplit holds 1 proportions')),
    );
    expect(recorder.calls, isNot(contains(_load)));
  });

  test('several GPU backends under auto are refused before the load', () {
    start(
      registeredDevices: () => [
        _fake('CUDA0', 'CUDA', 0x1000),
        _fake('Vulkan0', 'Vulkan', 0x2000),
      ],
    );
    expect(
      () => service.loadModel(model, const ModelParams(gpuDevices: [0])),
      refused(contains('more than one GPU backend')),
    );
    expect(recorder.calls, isNot(contains(_load)));
  });

  test('a listed Vulkan device ggml-vulkan cannot drive is refused instead '
      'of left out', () {
    const vulkan11 = 1 << 22 | 1 << 12;
    start(
      registeredDevices: () => [
        _fake('Vulkan0', 'Vulkan', 0x1000),
        _fake('Vulkan1', 'Vulkan', 0x2000),
      ],
      probe: const VulkanDeviceProbe.devices([
        VulkanDeviceFacts(
          name: 'Vulkan0',
          deviceType: 2,
          instanceApiVersion: VulkanDeviceFacts.vulkan12,
          apiVersion: vulkan11,
          subgroupSize: 32,
        ),
        VulkanDeviceFacts(
          name: 'Vulkan1',
          deviceType: 2,
          instanceApiVersion: VulkanDeviceFacts.vulkan12,
          apiVersion: VulkanDeviceFacts.vulkan12,
          subgroupSize: 32,
        ),
      ]),
    );
    expect(
      () => service.loadModel(model, const ModelParams(gpuDevices: [0])),
      refused(contains('Vulkan 1.2')),
    );
    expect(recorder.calls, isNot(contains(_load)));
  });

  test('a load that falls back to the CPU is refused instead', () {
    const vulkan11 = 1 << 22 | 1 << 12;
    start(
      registeredDevices: () => [_fake('Vulkan0', 'Vulkan', 0x1000)],
      probe: const VulkanDeviceProbe.devices([
        VulkanDeviceFacts(
          name: 'Vulkan0',
          deviceType: 2,
          instanceApiVersion: VulkanDeviceFacts.vulkan12,
          apiVersion: vulkan11,
          subgroupSize: 32,
        ),
      ]),
    );
    expect(
      () => service.loadModel(model, const ModelParams(tensorSplit: [1])),
      refused(allOf(contains('no usable GPU'), contains('run on the CPU'))),
    );
    expect(recorder.calls, isNot(contains(_load)));
  });

  test('the listed devices and split reach llama.cpp and the backend '
      'name', () {
    start();
    final gpus = service.listGpuDevices();
    if (gpus.isEmpty) {
      markTestSkipped('No GPU device on this host.');
      return;
    }
    final first = gpus.first;
    final oneBackend = gpus.every(
      (gpu) =>
          gpu.backend == first.backend || gpu.type == GpuDeviceType.accelerator,
    );
    // Under auto without a list llama.cpp picks the devices itself, so the
    // load lists none; the placement must list the chosen one.
    service.loadModel(
      model,
      ModelParams(
        preferredBackend: oneBackend ? GpuBackend.auto : first.backend,
        gpuDevices: const [0],
        tensorSplit: const [2],
      ),
    );
    expect(recorder.loadDevices.single, hasLength(1));
    expect(recorder.loadDevices.single, isNot(contains(0)));
    expect(recorder.loadTensorSplits.single, [2.0]);
    expect(service.getActiveBackendName(), endsWith('(${first.name})'));

    service.loadModel(model, const ModelParams());
    expect(recorder.loadTensorSplits.last, isNull);
    allocator.expectAllFreed();
  });

  test(
    'a speculative draft model loads on the target devices and split',
    () async {
      start();
      final gpus = service.listGpuDevices();
      if (gpus.isEmpty) {
        markTestSkipped('No GPU device on this host.');
        return;
      }
      final params = ModelParams(
        contextSize: 256,
        preferredBackend: gpus.first.backend,
        gpuDevices: const [0],
        tensorSplit: const [2],
      );
      final target = service.loadModel(model, params);
      final context = service.createContext(target, params);
      final cancel = calloc<Int8>();
      try {
        await service
            .generate(
              context,
              'abababab',
              GenerationParams(
                maxTokens: 4,
                temp: 0,
                penalty: 1,
                speculativeDecodingConfig:
                    SpeculativeDecodingConfig.draftSimple(
                      // ignore: deprecated_member_use_from_same_package
                      draftModelPath: model,
                      draftTokenMax: 2,
                    ),
              ),
              cancel.address,
            )
            .drain<void>();
      } finally {
        calloc.free(cancel);
      }
      expect(recorder.loadDevices, hasLength(2));
      expect(recorder.loadDevices.last, recorder.loadDevices.first);
      expect(recorder.loadTensorSplits, [
        [2.0],
        [2.0],
      ]);
      allocator.expectAllFreed();
    },
  );

  test('a draft of a row-split target on the CPU loads on the CPU in layer '
      'mode, the only one llama.cpp allows a CPU list in', () {
    start();
    const target = 7;
    // A host with no GPU backend loads such a target with no device list and
    // reports the CPU; the draft load is all that is under test. A host with a
    // GPU stands in for one that registered it after the target loaded.
    (_private(service, '_modelLoadParams') as Map<int, ModelParams>)[target] =
        const ModelParams(gpuLayers: 0, splitMode: ModelSplitMode.row);
    (_private(service, '_modelBackendNames') as Map<int, String>)[target] =
        'CPU';
    _loadDraft(service, target, model);
    final cpu = _invokePrivate<List<ggml_backend_dev_t>>(
      service,
      '_resolvePreferredDevices',
      [GpuBackend.cpu],
    ).single;
    expect(recorder.loadDevices, [
      [cpu.address],
    ]);
    expect(recorder.loadSplitModes, [ModelSplitMode.layer.llamaCppValue]);
    allocator.expectAllFreed();
  });

  test('on a host with no GPU, a row-split target reports 0 GPU layers and its '
      'draft loads', () {
    start();
    if (!_invokePrivate<bool>(service, '_registryShowsNoGpuDevice', const [])) {
      markTestSkipped('This host has a GPU, and row split is refused on it.');
      return;
    }
    final target = service.loadModel(
      model,
      const ModelParams(contextSize: 256, splitMode: ModelSplitMode.row),
    );
    expect(service.getResolvedGpuLayers(), 0);
    expect(_loadDraft(service, target, model), isNotNull);
    allocator.expectAllFreed();
  });

  group('the device list of an explicit backend is freed', () {
    const vulkan11 = 1 << 22 | 1 << 12;
    const target = 7;
    final v0 = _fake('Vulkan0', 'Vulkan', 0x1000);
    final v1 = _fake('Vulkan1', 'Vulkan', 0x2000);
    const tooOld = VulkanDeviceFacts(
      name: 'Vulkan0',
      deviceType: 2,
      instanceApiVersion: VulkanDeviceFacts.vulkan12,
      apiVersion: vulkan11,
      subgroupSize: 32,
    );
    const usable = VulkanDeviceFacts(
      name: 'Vulkan1',
      deviceType: 2,
      instanceApiVersion: VulkanDeviceFacts.vulkan12,
      apiVersion: VulkanDeviceFacts.vulkan12,
      subgroupSize: 32,
    );
    const vulkanLoad = ModelParams(
      contextSize: 256,
      preferredBackend: GpuBackend.vulkan,
      gpuLayers: 99,
    );

    void startOnVulkan(
      List<GgmlDeviceEntry> devices, {
      VulkanDeviceProbe probe = const VulkanDeviceProbe.unavailable('test'),
      List<int> Function(GpuBackend backend)? deviceTypes,
    }) {
      start(
        registeredDevices: () => devices,
        backendDevices: (backend) => backend == GpuBackend.vulkan
            ? [for (final device in devices) device.device!]
            : null,
        probe: probe,
        deviceTypes: deviceTypes,
      );
    }

    void seedVulkanTarget(ModelParams params) {
      (_private(service, '_modelLoadParams') as Map<int, ModelParams>)[target] =
          params;
      (_private(service, '_modelBackendNames') as Map<int, String>)[target] =
          'Vulkan';
      (_private(service, '_modelResolvedGpuLayers') as Map<int, int>)[target] =
          99;
    }

    tearDown(() => allocator.expectAllFreed());

    test('when ComputeDevice.gpu finds no GPU', () {
      startOnVulkan(
        [v0],
        deviceTypes: (_) => [
          ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value,
        ],
      );
      expect(
        () => service.loadModel(
          model,
          vulkanLoad.copyWith(device: ComputeDevice.gpu),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(allocator.allocations, 1);
    });

    test('when Vulkan is refused and the load falls back to the CPU', () {
      startOnVulkan([v0], probe: const VulkanDeviceProbe.devices([tooOld]));
      service.loadModel(model, vulkanLoad);
      expect(recorder.loadGpuLayers, [0]);
    });

    test('when the usable Vulkan devices replace it', () {
      startOnVulkan([
        v0,
        v1,
      ], probe: const VulkanDeviceProbe.devices([tooOld, usable]));
      recorder.fail = (name) => name == _load;
      expect(() => service.loadModel(model, vulkanLoad), throwsException);
      expect(recorder.loadDevices, [
        [v1.device!.address],
      ]);
    });

    test('when the MoE cache is refused', () {
      startOnVulkan([v0]);
      expect(
        () => service.loadModel(
          model,
          vulkanLoad.copyWith(moeCacheBytes: 1 << 30),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'message',
            contains('moeCacheBytes'),
          ),
        ),
      );
    });

    test('when placement is refused', () {
      startOnVulkan([v0]);
      expect(
        () => service.loadModel(
          model,
          vulkanLoad.copyWith(gpuDevices: const [5]),
        ),
        refused(contains('this host has 1')),
      );
    });

    test('when the usable Vulkan devices replace it for a draft', () {
      startOnVulkan([
        v0,
        v1,
      ], probe: const VulkanDeviceProbe.devices([tooOld, usable]));
      seedVulkanTarget(vulkanLoad);
      recorder.fail = (name) => name == _load;
      expect(() => _loadDraft(service, target, model), throwsException);
      expect(recorder.loadDevices, [
        [v1.device!.address],
      ]);
    });

    test('and a draft of a row-split target on a GPU stays in row mode', () {
      startOnVulkan([v1]);
      seedVulkanTarget(vulkanLoad.copyWith(splitMode: ModelSplitMode.row));
      recorder.fail = (name) => name == _load;
      expect(() => _loadDraft(service, target, model), throwsException);
      expect(recorder.loadSplitModes, [ModelSplitMode.row.llamaCppValue]);
    });

    test('when placement is refused for a draft', () {
      startOnVulkan([v0]);
      seedVulkanTarget(vulkanLoad.copyWith(gpuDevices: const [5]));
      expect(
        () => _loadDraft(service, target, model),
        refused(contains('this host has 1')),
      );
      expect(recorder.calls, isNot(contains(_load)));
    });
  });

  test('a listed explicit backend keeps its layers on a host with no GPU, as '
      'BLAS does', () {
    final blas = _fake('BLAS', 'BLAS', 0x1000);
    start(
      registeredDevices: () => [blas],
      backendDevices: (backend) =>
          backend == GpuBackend.blas ? [blas.device!] : null,
      deviceTypes: (_) => [
        ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_ACCEL.value,
      ],
    );
    final modules = Directory('${dir.path}/modules')..createSync();
    _setPrivate(service, '_backendModuleDirectory', modules.path);
    recorder.fail = (name) => name == _load;
    expect(
      () => service.loadModel(
        model,
        const ModelParams(
          contextSize: 256,
          preferredBackend: GpuBackend.blas,
          gpuLayers: 99,
        ),
      ),
      throwsException,
    );
    expect(recorder.loadGpuLayers, [99]);
    expect(recorder.loadDevices, [
      [blas.device!.address],
    ]);
    allocator.expectAllFreed();
  });

  test('a load refused at placement allocates no tensor overrides', () {
    start(registeredDevices: () => [_fake('CUDA0', 'CUDA', 0x1000)]);
    expect(
      () => service.loadModel(
        model,
        const ModelParams(cpuMoeLayers: 1, gpuDevices: [0, 1]),
      ),
      refused(contains('this host has 1 (CUDA0)')),
    );
    expect(recorder.calls, isNot(contains(_load)));
    expect(allocator.allocations, 0);
  });

  test('tensor overrides and the model path are freed after the load', () {
    start();
    expect(
      () => service.loadModel(
        model,
        const ModelParams(gpuLayers: 0, cpuMoeLayers: 1),
      ),
      throwsA(isA<LlamaUnsupportedException>()),
    );
    expect(recorder.loadTensorOverrides.single, isNotEmpty);
    // The model path, the override list and its pattern.
    expect(allocator.allocations, 3);
    allocator.expectAllFreed();
  });

  group('row split', () {
    Matcher refusedRow(String device) => throwsA(
      isA<LlamaUnsupportedException>().having(
        (e) => e.message,
        'message',
        allOf(
          contains('ModelSplitMode.row'),
          contains('split buffer'),
          contains(device),
          contains('ModelSplitMode.layer'),
        ),
      ),
    );

    test('on a device whose backend has no split buffers is refused before '
        'the load', () {
      start();
      expect(
        () => service.loadModel(
          model,
          const ModelParams(
            preferredBackend: GpuBackend.cpu,
            splitMode: ModelSplitMode.row,
          ),
        ),
        refusedRow('CPU'),
      );
      expect(recorder.calls, isNot(contains(_load)));
      allocator.expectAllFreed();
    });

    test('on GPUs llama.cpp selects by itself is refused before the load', () {
      final probed = <String>[];
      start(
        registeredDevices: () => [
          _fake('Vulkan0', 'Vulkan', 0x1000),
          _fake('Vulkan1', 'Vulkan', 0x2000),
        ],
        splitBufferTypeProbe: (device) {
          probed.add(device.name);
          return false;
        },
      );
      expect(
        () => service.loadModel(
          model,
          const ModelParams(splitMode: ModelSplitMode.row),
        ),
        refusedRow('Vulkan0 (Vulkan)'),
      );
      expect(probed, ['Vulkan0']);
      expect(recorder.calls, isNot(contains(_load)));
    });

    test('on listed GPUs probes the listed ones before the split is '
        'allocated', () {
      final probed = <String>[];
      start(
        registeredDevices: () => [
          _fake('Vulkan0', 'Vulkan', 0x1000),
          _fake('Vulkan1', 'Vulkan', 0x2000),
        ],
        splitBufferTypeProbe: (device) {
          probed.add(device.name);
          return device.name == 'Vulkan1';
        },
      );
      expect(
        () => service.loadModel(
          model,
          const ModelParams(
            splitMode: ModelSplitMode.row,
            gpuDevices: [1, 0],
            tensorSplit: [1, 1],
          ),
        ),
        refusedRow('Vulkan0 (Vulkan)'),
      );
      expect(probed, ['Vulkan1', 'Vulkan0']);
      expect(recorder.calls, isNot(contains(_load)));
      // Only the device list, freed on the refusal: no split, no model path.
      expect(allocator.allocations, 1);
      allocator.expectAllFreed();
    });

    test('on GPUs llama.cpp selects by itself probes all of them, whatever '
        'the main GPU', () {
      final probed = <String>[];
      start(
        registeredDevices: () => [
          _fake('Vulkan0', 'Vulkan', 0x1000),
          _fake('Vulkan1', 'Vulkan', 0x2000),
        ],
        splitBufferTypeProbe: (device) {
          probed.add(device.name);
          return device.name == 'Vulkan0';
        },
      );
      expect(
        () => service.loadModel(
          model,
          const ModelParams(splitMode: ModelSplitMode.row, mainGpu: 1),
        ),
        refusedRow('Vulkan1 (Vulkan)'),
      );
      expect(probed, ['Vulkan0', 'Vulkan1']);
      expect(recorder.calls, isNot(contains(_load)));
    });

    test('leaves a device it cannot read to llama.cpp', () {
      start();
      for (final device in [null, nullptr]) {
        expect(
          _invokePrivate<bool>(service, '_hasSplitBufferType', [
            GgmlDeviceEntry(
              name: 'GPU0',
              registry: 'Vulkan',
              description: 'GPU0',
              type: _gpu,
              device: device,
            ),
          ]),
          isTrue,
        );
      }
    });

    test('on devices with split buffers goes on to the load', () {
      start(splitBufferTypeProbe: (_) => true);
      // llama.cpp's CPU backend has none, so its own check fails the load.
      expect(
        () => service.loadModel(
          model,
          const ModelParams(
            preferredBackend: GpuBackend.cpu,
            splitMode: ModelSplitMode.row,
          ),
        ),
        throwsA(isNot(isA<LlamaUnsupportedException>())),
      );
      expect(recorder.calls, contains(_load));
      allocator.expectAllFreed();
    });

    test('is not probed in layer mode', () {
      var listed = 0;
      start(
        registeredDevices: () {
          listed++;
          return const [];
        },
        splitBufferTypeProbe: (_) => fail('probed'),
      );
      service.loadModel(
        model,
        const ModelParams(preferredBackend: GpuBackend.cpu),
      );
      expect(recorder.calls, contains(_load));
      expect(listed, 0);
    });
  });

  group('non-finite tensor split sum', () {
    for (final initialList in [false, true]) {
      for (final draft in [false, true]) {
        test(
          '${draft ? 'draft' : 'main'} load frees '
          '${initialList ? 'a replaced' : 'a new'} device list before refusal',
          () {
            final devices = [
              _fake('CUDA0', 'CUDA', 0x1000),
              _fake('CUDA1', 'CUDA', 0x2000),
            ];
            start(
              registeredDevices: () => devices,
              backendDevices: (_) => initialList
                  ? [for (final entry in devices) entry.device!]
                  : const [],
              deviceTypes: (_) => [_gpu],
            );
            _setPrivate(service, '_backendModuleDirectory', null);
            recorder.fail = (name) => name == _load;
            final params = ModelParams(
              preferredBackend: GpuBackend.cuda,
              gpuDevices: const [0, 1],
              tensorSplit: const [1.7e308, 1.7e308],
              cpuMoeLayers: draft ? 0 : 1,
            );
            Object? failure;
            try {
              if (draft) {
                const target = 7;
                (_private(service, '_modelLoadParams')
                        as Map<int, ModelParams>)[target] =
                    params;
                (_private(service, '_modelBackendNames')
                        as Map<int, String>)[target] =
                    'CUDA';
                (_private(service, '_modelResolvedGpuLayers')
                        as Map<int, int>)[target] =
                    99;
                _loadDraft(service, target, model);
              } else {
                service.loadModel(model, params);
              }
            } catch (error) {
              failure = error;
            }
            expect(recorder.calls, isNot(contains(_load)));
            expect(
              allocator.byteCounts,
              List.filled(
                initialList ? 2 : 1,
                3 * sizeOf<ggml_backend_dev_t>(),
              ),
              reason:
                  'only device lists precede refusal; split, override '
                  'patterns and model path must not allocate',
            );
            allocator.expectAllFreed();
            expect(
              failure,
              isA<LlamaArgumentException>()
                  .having((error) => error.name, 'name', 'tensorSplit')
                  .having(
                    (error) => error.message,
                    'message',
                    contains('finite sum'),
                  ),
            );
          },
        );
      }
    }
  });

  test('the tensor split holds llama_max_devices() floats', () {
    start();
    final array = _invokePrivate<Pointer<Float>>(
      service,
      '_createTensorSplit',
      [
        GpuDevicePlacement(
          devices: [_fake('CUDA0', 'CUDA', 0x1000)],
          tensorSplit: const [2],
        ),
      ],
    );
    final maxDevices = llama_max_devices();
    try {
      expect(allocator.byteCounts, [maxDevices * sizeOf<Float>()]);
      expect(
        [for (var i = 0; i < maxDevices; i++) array[i]],
        [2, ...List.filled(maxDevices - 1, 0)],
      );
    } finally {
      allocator.free(array);
    }
    allocator.expectAllFreed();
  });

  group('decision heads and projectors of a placed model', () {
    const handle = 7;
    final cuda0 = _fake('CUDA0', 'CUDA', 0x1000);
    final cuda1 = _fake('CUDA1', 'CUDA', 0x2000);
    final cuda2 = _fake('CUDA2', 'CUDA', 0x3000);

    void place(ModelParams params, List<GgmlDeviceEntry> devices) {
      start(registeredDevices: () => [cuda0, cuda1, cuda2]);
      (_private(service, '_modelLoadParams') as Map<int, ModelParams>)[handle] =
          params;
      (_private(service, '_modelBackendNames') as Map<int, String>)[handle] =
          'CUDA (${devices.map((device) => device.name).join(', ')})';
      (_private(service, '_modelPlacements')
          as Map<int, GpuDevicePlacement>)[handle] = GpuDevicePlacement(
        devices: devices,
      );
      (_private(service, '_modelToMtmdUseGpu') as Map<int, bool>)[handle] =
          true;
    }

    ggml_backend_dev_t? headDevice() => _invokePrivate<ggml_backend_dev_t?>(
      service,
      '_decisionHeadDevice',
      [handle],
    );
    mtmd_context_params projectorParams() =>
        _invokePrivate<mtmd_context_params>(service, '_mtmdContextParamsFor', [
          handle,
        ]);

    test('run on the listed device mainGpu names', () {
      place(const ModelParams(gpuDevices: [2, 1], mainGpu: 1), [cuda2, cuda1]);
      expect(headDevice(), cuda1.device);
      expect(projectorParams().use_gpu, isTrue);
      expect(projectorParams().device, cuda1.device);
    });

    test('run on the first listed device, not on an excluded one', () {
      place(const ModelParams(gpuDevices: [2]), [cuda2]);
      expect(headDevice(), cuda2.device);
      expect(projectorParams().device, cuda2.device);
    });

    test('a projector the load keeps on the CPU names no device', () {
      place(const ModelParams(gpuDevices: [2]), [cuda2]);
      (_private(service, '_modelToMtmdUseGpu') as Map<int, bool>)[handle] =
          false;
      expect(projectorParams().use_gpu, isFalse);
      expect(projectorParams().device, nullptr);
    });

    test('without a listed GPU run on the CPU', () {
      final accel = GgmlDeviceEntry(
        name: 'ACCEL0',
        registry: 'CUDA',
        type: ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_ACCEL.value,
        device: Pointer.fromAddress(0x4000),
      );
      place(const ModelParams(gpuDevices: [0]), [accel]);
      expect(headDevice(), isNull);
      expect(projectorParams().use_gpu, isFalse);
      expect(projectorParams().device, nullptr);
    });

    test('forget the placement with the model', () {
      place(const ModelParams(gpuDevices: [2]), [cuda2]);
      service.freeModel(handle);
      expect(_private(service, '_modelPlacements'), isEmpty);
    });

    test('without a placement keep the default choice', () {
      start(registeredDevices: () => [cuda0, cuda1, cuda2]);
      (_private(service, '_modelLoadParams') as Map<int, ModelParams>)[handle] =
          const ModelParams(mainGpu: 1);
      (_private(service, '_modelBackendNames') as Map<int, String>)[handle] =
          'CUDA';
      expect(headDevice(), cuda1.device);
      expect(projectorParams().use_gpu, isTrue);
      expect(projectorParams().device, nullptr);
    });
  });

  group('placement retained by a successful load without a host GPU', () {
    final gpu = _fake('CUDA0', 'CUDA', 0x1000);
    final igpu = GgmlDeviceEntry(
      name: 'CUDA1',
      registry: 'CUDA',
      type: ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU.value,
      device: Pointer.fromAddress(0x2000),
    );
    final accel = GgmlDeviceEntry(
      name: 'ACCEL0',
      registry: 'CUDA',
      type: ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_ACCEL.value,
      device: Pointer.fromAddress(0x3000),
    );

    void cpuFixtureLoad() {
      start(
        registeredDevices: () => [gpu, igpu, accel],
        backendDevices: (_) => [gpu.device!, igpu.device!, accel.device!],
        deviceTypes: (_) => [_gpu],
      );
      recorder.modelLoad = (path, params) {
        // Preserve the real service's resolution and storage, but keep the
        // synthetic native fixture independent of GPU hardware and pointers.
        params.devices = nullptr;
        params.tensor_split = nullptr;
        params.n_gpu_layers = 0;
        return recorder.real.modelLoadFromFile(path, params);
      };
    }

    void expectAuxiliary(int handle, ggml_backend_dev_t? expected) {
      expect(
        _invokePrivate<ggml_backend_dev_t?>(service, '_decisionHeadDevice', [
          handle,
        ]),
        expected,
      );
      final projector = _invokePrivate<mtmd_context_params>(
        service,
        '_mtmdContextParamsFor',
        [handle],
      );
      expect(projector.use_gpu, expected != null);
      expect(projector.device, expected ?? nullptr);
    }

    for (final (label, indices, mainGpu, expected) in [
      ('GPU subset', [0], 1, gpu.device),
      ('iGPU reordered list', [1, 0], 0, igpu.device),
      ('negative mainGpu uses first listed GPU', [1, 0], -1, igpu.device),
      ('GPU after accelerator', [2, 0, 1], 0, gpu.device),
      ('iGPU after accelerator', [2, 0, 1], 1, igpu.device),
      ('accelerator-only CPU fallback', [2], 0, null),
      ('tensor split without device list', null, 1, igpu.device),
    ]) {
      test(label, () {
        cpuFixtureLoad();
        final handle = service.loadModel(
          model,
          ModelParams(
            preferredBackend: GpuBackend.cuda,
            gpuDevices: indices,
            tensorSplit: indices == null ? const [1, 2, 3] : null,
            mainGpu: mainGpu,
          ),
        );
        expect(recorder.loadDevices.single, [
          for (final index in indices ?? [0, 1, 2])
            [gpu, igpu, accel][index].device!.address,
        ]);
        expect(
          recorder.loadTensorSplits.single,
          indices == null ? [1, 2, 3] : null,
        );
        expectAuxiliary(handle, expected);
        allocator.expectAllFreed();
      });
    }

    test(
      'freeing one model preserves another and a reload stores its own list',
      () {
        cpuFixtureLoad();
        int load(List<int>? indices) => service.loadModel(
          model,
          ModelParams(preferredBackend: GpuBackend.cuda, gpuDevices: indices),
        );
        final first = load([1]);
        final second = load([0]);
        expectAuxiliary(first, igpu.device);
        expectAuxiliary(second, gpu.device);
        service.freeModel(first);
        expectAuxiliary(second, gpu.device);
        final reloaded = load([2]);
        expect(reloaded, isNot(first));
        expectAuxiliary(reloaded, null);
        service.freeModel(second);
        service.freeModel(reloaded);
        final unplaced = load(null);
        final projector = _invokePrivate<mtmd_context_params>(
          service,
          '_mtmdContextParamsFor',
          [unplaced],
        );
        expect(projector.use_gpu, isTrue);
        expect(projector.device, nullptr);
      },
    );
  });

  test('a decision head and projector of a model on a listed GPU use that '
      'GPU', () {
    start();
    final gpus = service.listGpuDevices();
    if (gpus.isEmpty) {
      markTestSkipped('No GPU device on this host.');
      return;
    }
    final first = gpus.first;
    final encoder = writeSyntheticModernBertGguf(
      '${dir.path}/encoder.gguf',
      decisionTokens: true,
    ).path;
    final headPath = '${dir.path}/head.safetensors';
    SyntheticDecisionHead(d: 16, layers: 1, seed: 1).write(headPath);
    final configPath = '${dir.path}/config.json';
    File(configPath).writeAsStringSync('{"max_len": 64, "head_layers": 1}');
    final handle = service.loadModel(
      encoder,
      ModelParams(preferredBackend: first.backend, gpuDevices: const [0]),
    );
    final listed = recorder.loadDevices.single!.single;
    expect(
      _invokePrivate<mtmd_context_params>(service, '_mtmdContextParamsFor', [
        handle,
      ]).device.address,
      listed,
    );
    final head = service.loadDecisionHead(handle, headPath, configPath);
    addTearDown(() => service.freeDecisionHead(head.handle));
    expect(head.deviceName, first.name);
  });
}
