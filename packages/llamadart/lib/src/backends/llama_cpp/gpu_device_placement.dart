import 'dart:ffi';

import '../../core/exceptions.dart';
import '../../core/models/config/gpu_backend.dart';
import '../../core/models/inference/model_params.dart';
import 'bindings.dart';
import 'load_device_selection.dart';

final int _typeGpu = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value;
final int _typeIgpu = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU.value;
final int _typeAccel =
    ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_ACCEL.value;

/// The devices and tensor split a model load passes to llama.cpp for
/// [ModelParams.gpuDevices] and [ModelParams.tensorSplit].
final class GpuDevicePlacement {
  /// Places the model on [devices], split by [tensorSplit] when it is set.
  const GpuDevicePlacement({required this.devices, this.tensorSplit});

  /// `llama_model_params.devices`, in order.
  final List<GgmlDeviceEntry> devices;

  /// `llama_model_params.tensor_split`, one proportion per device, or `null`
  /// for llama.cpp's split by free memory.
  final List<double>? tensorSplit;

  /// The device names, as backend names report them, such as `CUDA0, CUDA2`.
  String get deviceNames => devices.map((device) => device.name).join(', ');
}

/// The offload devices of [backend] among [registered], in registry order:
/// position `i` is the device `LlamaEngine.listGpuDevices` reports with
/// `GpuDeviceInfo.mainGpu` `i` for [backend].
///
/// [backendOf] maps a ggml registry name to its [GpuBackend], as the device
/// listing does.
List<GgmlDeviceEntry> offloadDevicesOf(
  List<GgmlDeviceEntry> registered,
  GpuBackend backend,
  GpuBackend Function(String registry) backendOf,
) => [
  for (final device in registered)
    if ((device.type == _typeGpu ||
            device.type == _typeIgpu ||
            device.type == _typeAccel) &&
        backendOf(device.registry) == backend)
      device,
];

/// Resolves the [ModelParams.gpuDevices] and [ModelParams.tensorSplit] of
/// [params] for a load on [backend] among the [registered] devices, or
/// returns `null` when neither is set.
///
/// [backend] is the load's effective backend; under [GpuBackend.auto] the
/// only GPU backend with devices is used. Throws [LlamaUnsupportedException]
/// when no backend can be chosen, for an index this host does not have, for
/// a split whose length differs from the number of devices, and for more
/// devices than llama.cpp's [maxDevices].
GpuDevicePlacement? resolveGpuDevicePlacement(
  ModelParams params, {
  required GpuBackend backend,
  required List<GgmlDeviceEntry> registered,
  required GpuBackend Function(String registry) backendOf,
  required int maxDevices,
  required String platform,
}) {
  final indices = params.gpuDevices;
  final split = params.tensorSplit;
  if (indices == null && split == null) return null;
  final field = indices != null ? 'gpuDevices' : 'tensorSplit';
  final capability =
      'ModelParams.$field, llama.cpp multi-GPU placement, is not available '
      'on $platform';

  var placed = backend;
  if (placed == GpuBackend.auto) {
    final backends = {
      for (final device in registered)
        if (device.type == _typeGpu || device.type == _typeIgpu)
          backendOf(device.registry),
    }..remove(GpuBackend.auto);
    if (backends.length != 1) {
      throw LlamaUnsupportedException(
        backends.isEmpty
            ? '$capability: llama.cpp lists no GPU device.'
            : '$capability with preferredBackend auto, because more than one '
                  'GPU backend has devices '
                  '(${backends.map((backend) => backend.name).join(', ')}). '
                  'Set preferredBackend to the backend whose listGpuDevices '
                  'indices it names.',
      );
    }
    placed = backends.single;
  }
  final available = offloadDevicesOf(registered, placed, backendOf);
  String listed() => available.isEmpty
      ? 'none'
      : available.map((device) => device.name).join(', ');
  if (available.isEmpty) {
    throw LlamaUnsupportedException(
      '$capability: llama.cpp lists no ${placed.name} device.',
    );
  }

  final List<GgmlDeviceEntry> devices;
  if (indices == null) {
    devices = available;
  } else {
    final missing = indices.where((index) => index >= available.length);
    if (missing.isNotEmpty) {
      throw LlamaUnsupportedException(
        '$capability: gpuDevices names ${placed.name} device '
        '${missing.join(', ')}, and this host has ${available.length} '
        '(${listed()}). Use the GpuDeviceInfo.mainGpu indices '
        'listGpuDevices reports.',
      );
    }
    devices = [for (final index in indices) available[index]];
  }
  if (devices.length > maxDevices) {
    throw LlamaUnsupportedException(
      '$capability: the load would use ${devices.length} devices, and '
      'llama.cpp supports at most $maxDevices.',
    );
  }
  if (split != null && split.length != devices.length) {
    throw LlamaUnsupportedException(
      '$capability: tensorSplit holds ${split.length} proportions, and the '
      'load uses ${devices.length} ${placed.name} '
      '${devices.length == 1 ? 'device' : 'devices'} '
      '(${devices.map((device) => device.name).join(', ')}). Give one '
      'proportion per device.',
    );
  }
  return GpuDevicePlacement(devices: devices, tensorSplit: split);
}

/// The device the decision heads and mtmd projectors of a model placed by
/// [placement] run on: the GPU or integrated GPU [mainGpu] counts among its
/// devices, or the first one when [mainGpu] is out of range; `null`, the CPU,
/// when it has none.
GgmlDeviceEntry? auxiliaryPlacementDevice(
  GpuDevicePlacement placement,
  int mainGpu,
) {
  final gpus = [
    for (final device in placement.devices)
      if ((device.type == _typeGpu || device.type == _typeIgpu) &&
          device.device != null &&
          device.device != nullptr)
        device,
  ];
  if (gpus.isEmpty) return null;
  return mainGpu >= 0 && mainGpu < gpus.length ? gpus[mainGpu] : gpus.first;
}

/// The largest proportion sum [allocateTensorSplit] passes on unscaled.
///
/// Tensor split mode computes `rows * runningSum` in float32, and rows stay
/// below 2^63, so a sum of at most 2^64 keeps that product below the float32
/// maximum of about 2^128.
const double _maxTensorSplitSum = 18446744073709551616.0;

/// Allocates the `llama_model_params.tensor_split` array of [split] with
/// [allocator]: [maxDevices] floats, as llama.cpp copies that many, with 0
/// after the proportions.
///
/// A sum above 2^64 is scaled down by a power of two, which leaves every
/// float32 sum and ratio llama.cpp computes from the proportions unchanged
/// unless one falls below float32's normal range (2^-126). Unscaled,
/// tensor split mode overflows to infinity once a running sum times a
/// tensor's row count exceeds the float32 maximum, about 8e34 for 4096 rows.
/// Throws [LlamaArgumentException] before allocating when the float64 sum is
/// not finite, including a direct backend load that bypasses validation.
Pointer<Float> allocateTensorSplit(
  List<double> split, {
  required int maxDevices,
  required Allocator allocator,
}) {
  final sum = split.fold<double>(0, (sum, value) => sum + value);
  if (!sum.isFinite) {
    throw LlamaArgumentException(
      'ModelParams.tensorSplit must have a finite sum.',
      name: 'tensorSplit',
      invalidValue: split,
    );
  }
  var scale = 1.0;
  while (sum * scale > _maxTensorSplitSum) {
    scale /= 2;
  }
  final array = allocator<Float>(maxDevices);
  for (var index = 0; index < maxDevices; index++) {
    array[index] = index < split.length ? split[index] * scale : 0;
  }
  return array;
}
