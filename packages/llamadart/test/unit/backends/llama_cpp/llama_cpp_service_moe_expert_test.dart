@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/load_device_selection.dart';
import 'package:llamadart/src/backends/llama_cpp/vulkan_device_probe.dart';
import 'package:test/test.dart';

import '../../../support/recording_exit_teardown.dart';
import '../../../support/synthetic_embedding_gguf.dart';

const _load = 'llama_dart_model_load_from_file';
const _budget = 64 << 20;

// Runs the real runtime with a dense synthetic model, so every MoE request
// ends in a refusal; the recorder shows what reached llama.cpp first.
void main() {
  late Directory dir;
  late String model;
  late RecordingExitTeardown recorder;
  late LlamaCppService service;

  void start({List<GgmlDeviceEntry> Function()? registeredDevices}) {
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
      vulkanDeviceProbe: () => const VulkanDeviceProbe.unavailable('test'),
    )..initializeBackend();
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('llamadart_moe_expert_');
    model = writeSyntheticLlamaGguf('${dir.path}/model.gguf').path;
  });

  tearDown(() {
    service.dispose();
    dir.deleteSync(recursive: true);
  });

  test('cpuMoeLayers keeps the experts of its layers in host memory, and a '
      'model without experts is refused and freed', () {
    start();
    expect(
      () => service.loadModel(model, const ModelParams(cpuMoeLayers: 2)),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('cpuMoeLayers'),
            contains('llama model has no experts'),
          ),
        ),
      ),
    );
    expect(recorder.loadTensorOverrides, [
      [
        r'blk\.0\.ffn_(up|down|gate|gate_up)_(ch|)exps',
        r'blk\.1\.ffn_(up|down|gate|gate_up)_(ch|)exps',
      ],
    ]);
    expect(recorder.loadUseExtraBufts, [isTrue]);
    expect(recorder.freed, contains(recorder.owned.single));

    service.loadModel(model, const ModelParams());
    expect(recorder.loadTensorOverrides.last, isEmpty);
  });

  test('a model whose expert_count is 0 is refused and freed', () {
    start();
    final dense = writeSyntheticLlamaGguf(
      '${dir.path}/dense.gguf',
      uint32Metadata: const {'llama.expert_count': 0},
    ).path;
    expect(
      () => service.loadModel(dense, const ModelParams(cpuMoeLayers: -1)),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'message',
          contains('llama model has no experts'),
        ),
      ),
    );
    expect(recorder.freed, contains(recorder.owned.single));
  });

  test('a cache budget on a Metal device loads without repacking', () {
    start(
      registeredDevices: () => [
        GgmlDeviceEntry(
          name: 'MTL0',
          registry: 'MTL',
          type: ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value,
          device: Pointer.fromAddress(0x1000),
        ),
      ],
    );
    expect(
      () => service.loadModel(
        model,
        const ModelParams(cpuMoeLayers: -1, moeCacheBytes: _budget),
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'message',
          contains('has no experts'),
        ),
      ),
    );
    expect(recorder.loadTensorOverrides, [
      [r'\.ffn_(up|down|gate|gate_up)_(ch|)exps'],
    ]);
    expect(recorder.loadUseExtraBufts, [isFalse]);
  });

  test('a cache budget on the CPU is refused before the model loads', () {
    start();
    expect(
      () => service.loadModel(
        model,
        const ModelParams(
          device: ComputeDevice.cpu,
          cpuMoeLayers: -1,
          moeCacheBytes: _budget,
        ),
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'message',
          allOf(contains('moeCacheBytes'), contains('offloads no layer')),
        ),
      ),
    );
    expect(recorder.calls, isNot(contains(_load)));
  });

  test('a cache budget on a Vulkan device is refused before the model '
      'loads', () {
    start(
      registeredDevices: () => [
        GgmlDeviceEntry(
          name: 'Vulkan0',
          registry: 'Vulkan',
          type: ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value,
          device: Pointer.fromAddress(0x1000),
        ),
      ],
    );
    expect(
      () => service.loadModel(
        model,
        const ModelParams(cpuMoeLayers: -1, moeCacheBytes: _budget),
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'message',
          allOf(contains('Vulkan backend aborts'), contains('Vulkan0')),
        ),
      ),
    );
    expect(recorder.calls, isNot(contains(_load)));
  });

  test('the context passes the budget to llama.cpp and names it when '
      'creation fails', () {
    start();
    final handle = service.loadModel(model, const ModelParams());
    expect(
      () => service.createContext(
        handle,
        const ModelParams(cpuMoeLayers: -1, moeCacheBytes: _budget),
      ),
      throwsA(
        isA<LlamaContextException>().having(
          (e) => e.message,
          'message',
          contains('$_budget-byte MoE expert cache'),
        ),
      ),
    );
    expect(recorder.contextMoeCacheSizes, [_budget]);

    service.createContext(handle, const ModelParams());
    expect(recorder.contextMoeCacheSizes.last, 0);
  });
}
