import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../core/models/inference/model_params.dart';
import 'bindings.dart';
import 'load_device_selection.dart';

/// llama.cpp's `LLM_FFN_EXPS_REGEX` (`common/common.h`): the expert tensors
/// of a layer.
const String _expertTensorPattern = r'\.ffn_(up|down|gate|gate_up)_(ch|)exps';

/// The ggml registries of the GPU backends whose MoE expert cache llamadart
/// qualifies: Metal and CUDA.
const Set<String> moeCacheQualifiedRegistries = {'MTL', 'CUDA'};

final int _typeGpu = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value;
final int _typeIgpu = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU.value;
final int _splitTensor = llama_split_mode.LLAMA_SPLIT_MODE_TENSOR.value;

/// The `llama_model_params.tensor_buft_overrides` patterns that keep the
/// expert tensors of the first [cpuMoeLayers] layers in host memory, as
/// llama.cpp's `--n-cpu-moe` builds them, or of every layer for a negative
/// value, as `--cpu-moe` does. Empty for `0`.
List<String> cpuMoeOverridePatterns(int cpuMoeLayers) {
  if (cpuMoeLayers < 0) return const [_expertTensorPattern];
  return [
    for (var layer = 0; layer < cpuMoeLayers; layer++)
      'blk\\.$layer$_expertTensorPattern',
  ];
}

/// The number of layers whose experts llama.cpp's MoE cache can hold: the
/// layers [gpuLayers] offloads, out of [layerCount], among those
/// [cpuMoeLayers] keeps in host memory.
///
/// llama.cpp offloads the last layers and [cpuMoeLayers] keeps the first
/// ones, so a partial offload can leave none. A negative [gpuLayers] or
/// [cpuMoeLayers] means every layer.
int moeCacheableLayerCount({
  required int layerCount,
  required int gpuLayers,
  required int cpuMoeLayers,
}) {
  final offloaded = gpuLayers < 0 ? layerCount + 1 : gpuLayers;
  final firstOffloaded = layerCount + 1 - offloaded;
  final hostExperts = cpuMoeLayers < 0 || cpuMoeLayers > layerCount
      ? layerCount
      : cpuMoeLayers;
  final start = firstOffloaded < 0 ? 0 : firstOffloaded;
  return hostExperts > start ? hostExperts - start : 0;
}

/// Why llama.cpp's MoE expert cache cannot run for a load with [gpuLayers]
/// and [splitMode] on the model [devices] (`selectModelDevices`), or `null`
/// when it can.
///
/// The cache needs an offloaded layer on a GPU, and llama.cpp refuses tensor
/// parallelism. Every GPU device must belong to a backend in
/// [moeCacheQualifiedRegistries]: llama.cpp's Vulkan backend aborts the
/// process with the cache (ggml-org/llama.cpp#30697), and the others are
/// unqualified.
String? moeCacheUnsupportedReason({
  required int gpuLayers,
  required int splitMode,
  required List<GgmlDeviceEntry> devices,
}) {
  final gpus = [
    for (final device in devices)
      if (device.type == _typeGpu || device.type == _typeIgpu) device,
  ];
  if (gpuLayers == 0 || gpus.isEmpty) {
    return 'it caches experts on a GPU, and this load offloads no layer to '
        'one';
  }
  if (splitMode == _splitTensor) {
    return 'llama.cpp does not support it with tensor parallelism '
        '(ModelSplitMode.tensor)';
  }
  for (final gpu in gpus) {
    if (moeCacheQualifiedRegistries.contains(gpu.registry)) continue;
    return gpu.isVulkan
        ? "llama.cpp's Vulkan backend aborts the process with it "
              '(https://github.com/ggml-org/llama.cpp/issues/30697), and this '
              'load uses ${gpu.name}'
        : 'it is qualified only on Metal and CUDA, and this load uses '
              '${gpu.name} (${gpu.registry})';
  }
  return null;
}

/// Allocates with [allocator] the null-terminated
/// `llama_model_tensor_buft_override` list that places the tensors matching
/// each of [patterns] in [buft].
///
/// llama.cpp reads it only while the model loads; free it with
/// [freeTensorBufferOverrides] and the same [allocator] afterwards.
Pointer<llama_model_tensor_buft_override> allocateTensorBufferOverrides(
  List<String> patterns,
  ggml_backend_buffer_type_t buft, {
  required Allocator allocator,
}) {
  final overrides = allocator<llama_model_tensor_buft_override>(
    patterns.length + 1,
  );
  for (final (index, pattern) in patterns.indexed) {
    overrides[index]
      ..pattern = pattern.toNativeUtf8(allocator: allocator).cast()
      ..buft = buft;
  }
  overrides[patterns.length]
    ..pattern = nullptr
    ..buft = nullptr;
  return overrides;
}

/// Frees with [allocator] a list [allocateTensorBufferOverrides] returned.
void freeTensorBufferOverrides(
  Pointer<llama_model_tensor_buft_override> overrides, {
  required Allocator allocator,
}) {
  for (var index = 0; overrides[index].pattern != nullptr; index++) {
    allocator.free(overrides[index].pattern);
  }
  allocator.free(overrides);
}

/// Applies the model fields of [params] that the MoE expert cache needs.
///
/// With a [ModelParams.moeCacheBytes] budget, llama.cpp's CPU weight
/// repacking is disabled: the cache copies host experts only from plain
/// host buffers, and repacked experts would leave nothing to cache.
void applyMoeCacheModelParams(llama_model_params mparams, ModelParams params) {
  if (params.moeCacheBytes > 0) {
    mparams.use_extra_bufts = false;
  }
}
