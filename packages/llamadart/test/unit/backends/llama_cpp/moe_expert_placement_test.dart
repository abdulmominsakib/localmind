@TestOn('vm')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/load_device_selection.dart';
import 'package:llamadart/src/backends/llama_cpp/load_param_helpers.dart';
import 'package:llamadart/src/backends/llama_cpp/moe_expert_placement.dart';
import 'package:test/test.dart';

import '../../../support/recording_allocator.dart';

final int _gpu = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value;
final int _igpu = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU.value;
final int _cpu = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value;
final int _layer = llama_split_mode.LLAMA_SPLIT_MODE_LAYER.value;
final int _tensor = llama_split_mode.LLAMA_SPLIT_MODE_TENSOR.value;

GgmlDeviceEntry _device(String name, String registry, {int? type}) =>
    GgmlDeviceEntry(name: name, registry: registry, type: type ?? _gpu);

void main() {
  group('cpuMoeOverridePatterns', () {
    bool matches(List<String> patterns, String tensor) =>
        patterns.any((pattern) => RegExp(pattern).hasMatch(tensor));

    test('keeps nothing for 0', () {
      expect(cpuMoeOverridePatterns(0), isEmpty);
    });

    test('keeps the experts of the first layers, as --n-cpu-moe does', () {
      final patterns = cpuMoeOverridePatterns(2);
      expect(patterns, [
        r'blk\.0\.ffn_(up|down|gate|gate_up)_(ch|)exps',
        r'blk\.1\.ffn_(up|down|gate|gate_up)_(ch|)exps',
      ]);
      for (final tensor in [
        'blk.0.ffn_up_exps.weight',
        'blk.0.ffn_down_exps.weight',
        'blk.1.ffn_gate_exps.weight',
        'blk.1.ffn_gate_up_exps.weight',
        'blk.1.ffn_down_chexps.weight',
      ]) {
        expect(matches(patterns, tensor), isTrue, reason: tensor);
      }
      for (final tensor in [
        'blk.2.ffn_up_exps.weight',
        'blk.10.ffn_up_exps.weight',
        'blk.0.ffn_up.weight',
        'blk.0.ffn_gate_inp.weight',
        'blk.0.ffn_up_shexp.weight',
        'blk.0.attn_q.weight',
      ]) {
        expect(matches(patterns, tensor), isFalse, reason: tensor);
      }
    });

    test('keeps the experts of every layer for a negative value, as '
        '--cpu-moe does', () {
      final patterns = cpuMoeOverridePatterns(-1);
      expect(patterns, [r'\.ffn_(up|down|gate|gate_up)_(ch|)exps']);
      expect(matches(patterns, 'blk.47.ffn_down_exps.weight'), isTrue);
      expect(matches(patterns, 'blk.47.ffn_down.weight'), isFalse);
    });
  });

  group('moeCacheableLayerCount', () {
    int count(int gpuLayers, int cpuMoeLayers) => moeCacheableLayerCount(
      layerCount: 16,
      gpuLayers: gpuLayers,
      cpuMoeLayers: cpuMoeLayers,
    );

    test('counts every host-expert layer of a full offload', () {
      expect(count(ModelParams.maxGpuLayers, -1), 16);
      expect(count(-1, -1), 16);
      expect(count(17, 4), 4);
      expect(count(ModelParams.maxGpuLayers, 40), 16);
    });

    test('counts only the offloaded layers of a partial offload', () {
      // gpuLayers counts the output layer too, so 9 offloads blocks 8-15.
      expect(count(9, -1), 8);
      expect(count(9, 10), 2);
      expect(count(9, 8), 0);
      expect(count(1, -1), 0);
      expect(count(0, -1), 0);
    });

    test('counts nothing without host experts', () {
      expect(count(ModelParams.maxGpuLayers, 0), 0);
    });
  });

  group('moeCacheUnsupportedReason', () {
    String? reason(
      List<GgmlDeviceEntry> devices, {
      int gpuLayers = ModelParams.maxGpuLayers,
      int? splitMode,
    }) => moeCacheUnsupportedReason(
      gpuLayers: gpuLayers,
      splitMode: splitMode ?? _layer,
      devices: devices,
    );

    test('accepts Metal and CUDA devices', () {
      expect(reason([_device('MTL0', 'MTL')]), isNull);
      expect(reason([_device('MTL0', 'MTL', type: _igpu)]), isNull);
      expect(
        reason([_device('CUDA0', 'CUDA'), _device('CUDA1', 'CUDA')]),
        isNull,
      );
      expect(
        reason([_device('CPU', 'CPU', type: _cpu), _device('CUDA0', 'CUDA')]),
        isNull,
      );
    });

    test('refuses a load that offloads nothing', () {
      expect(
        reason([_device('CUDA0', 'CUDA')], gpuLayers: 0),
        contains('offloads no layer'),
      );
      expect(reason(const []), contains('offloads no layer'));
      expect(
        reason([_device('CPU', 'CPU', type: _cpu)]),
        contains('offloads no layer'),
      );
    });

    test('refuses tensor parallelism', () {
      expect(
        reason([_device('CUDA0', 'CUDA')], splitMode: _tensor),
        contains('ModelSplitMode.tensor'),
      );
    });

    test('refuses Vulkan, naming the upstream abort', () {
      final message = reason([
        _device('CUDA0', 'CUDA'),
        _device('Vulkan0', 'Vulkan'),
      ]);
      expect(message, contains('Vulkan backend aborts'));
      expect(message, contains('ggml-org/llama.cpp/issues/30697'));
      expect(message, contains('Vulkan0'));
    });

    test('refuses other unqualified GPU backends', () {
      expect(
        reason([_device('GPUOpenCL', 'OpenCL')]),
        allOf(contains('only on Metal and CUDA'), contains('OpenCL')),
      );
      expect(
        reason([_device('ROCm0', 'ROCm')]),
        allOf(contains('only on Metal and CUDA'), contains('ROCm0')),
      );
    });
  });

  test('tensor buffer overrides are null-terminated and freed', () {
    final buft = Pointer<ggml_backend_buffer_type>.fromAddress(0x40);
    final allocator = RecordingAllocator(poison: true);
    final overrides = allocateTensorBufferOverrides(
      ['a', 'b'],
      buft,
      allocator: allocator,
    );
    // Freeing walks to the terminator, so check it before freeing.
    expect(overrides[2].pattern, nullptr);
    expect(overrides[2].buft, nullptr);
    expect(overrides[0].pattern.cast<Utf8>().toDartString(), 'a');
    expect(overrides[1].pattern.cast<Utf8>().toDartString(), 'b');
    expect(overrides[0].buft, buft);
    expect(overrides[1].buft, buft);
    freeTensorBufferOverrides(overrides, allocator: allocator);
    expect(allocator.allocations, 3);
    final empty = allocateTensorBufferOverrides(
      const [],
      buft,
      allocator: allocator,
    );
    expect(empty[0].pattern, nullptr);
    freeTensorBufferOverrides(empty, allocator: allocator);
    allocator.expectAllFreed();
  });

  group('MoE cache parameters', () {
    late Pointer<llama_model_params> model;
    late Pointer<llama_context_params> context;

    setUp(() {
      model = calloc<llama_model_params>()..ref.use_extra_bufts = true;
      context = calloc<llama_context_params>();
    });

    tearDown(() {
      calloc.free(model);
      calloc.free(context);
    });

    test('a budget disables CPU weight repacking', () {
      applyMoeCacheModelParams(
        model.ref,
        const ModelParams(cpuMoeLayers: -1, moeCacheBytes: 1 << 30),
      );
      expect(model.ref.use_extra_bufts, isFalse);
    });

    test('host experts without a budget keep repacking', () {
      applyMoeCacheModelParams(model.ref, const ModelParams(cpuMoeLayers: -1));
      expect(model.ref.use_extra_bufts, isTrue);
    });

    test('the budget is the context moe_cache_size', () {
      context.ref.moe_cache_size = 7;
      applyContextParams(context.ref, const ModelParams());
      expect(context.ref.moe_cache_size, 0);
      applyContextParams(
        context.ref,
        const ModelParams(cpuMoeLayers: 2, moeCacheBytes: 512 << 20),
      );
      expect(context.ref.moe_cache_size, 512 << 20);
    });
  });
}
