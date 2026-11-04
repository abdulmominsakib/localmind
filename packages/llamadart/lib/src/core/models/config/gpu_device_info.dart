import 'gpu_backend.dart';

/// The kind of compute device a backend enumerated.
enum GpuDeviceType {
  /// Host CPU.
  cpu,

  /// Dedicated GPU with its own VRAM.
  discreteGpu,

  /// Integrated GPU sharing system memory.
  integratedGpu,

  /// Dedicated accelerator (e.g. NPU).
  accelerator,

  /// Unrecognized device type.
  unknown,
}

/// One inference-capable GPU-class device, as returned by `listGpuDevices`.
class GpuDeviceInfo {
  /// The backend that exposes this device.
  final GpuBackend backend;

  /// Offload index within [backend]: the value to pass as
  /// `ModelParams.mainGpu` (with `splitMode` none) to pin to this device.
  /// Counted over that backend's offload devices only.
  final int mainGpu;

  /// Short device name reported by the backend (e.g. `Vulkan1`).
  final String name;

  /// Human-readable description (e.g. `NVIDIA GeForce RTX 5050 Laptop GPU`).
  /// Falls back to [name] when the backend reports no description.
  final String description;

  /// Stable device identifier when the backend reports one (e.g. a PCI
  /// address); empty otherwise.
  final String deviceId;

  /// Device category. Integrated GPUs report shared system memory, so callers
  /// preferring dedicated VRAM should favor [GpuDeviceType.discreteGpu].
  final GpuDeviceType type;

  /// Free device memory in bytes at enumeration time.
  final int memoryFreeBytes;

  /// Total device memory in bytes.
  final int memoryTotalBytes;

  /// Creates a [GpuDeviceInfo].
  const GpuDeviceInfo({
    required this.backend,
    required this.mainGpu,
    required this.name,
    required this.description,
    required this.deviceId,
    required this.type,
    required this.memoryFreeBytes,
    required this.memoryTotalBytes,
  });

  /// A dedicated GPU with its own VRAM (not an integrated/shared-memory GPU).
  bool get isDiscreteGpu => type == GpuDeviceType.discreteGpu;

  @override
  String toString() =>
      'GpuDeviceInfo(backend: ${backend.name}, mainGpu: $mainGpu, '
      'name: $name, description: $description, deviceId: $deviceId, '
      'type: ${type.name}, memoryFree: $memoryFreeBytes, '
      'memoryTotal: $memoryTotalBytes)';
}
