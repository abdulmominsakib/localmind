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

/// How a [ModelParams.gpuMemoryFit] request changed a load.
enum GpuMemoryFitOutcome {
  /// Everything fits: the load keeps its requested layers and context.
  unchanged,

  /// Fewer layers, or a smaller context, than requested.
  reduced,

  /// No layer fits, so the model loads on the CPU.
  cpu,

  /// The load was not fitted; [GpuMemoryFitReport.reason] says why.
  skipped,
}

/// One GPU's memory in a [GpuMemoryFitReport].
class GpuMemoryFitDevice {
  /// The ggml device name, such as `Vulkan0`.
  final String name;

  /// Free device memory in bytes when the fit measured it.
  final int freeBytes;

  /// Total device memory in bytes.
  final int totalBytes;

  /// Bytes the fitted load puts on the device for model weights.
  final int modelBytes;

  /// Bytes the fitted load puts on the device for the context (KV cache).
  final int contextBytes;

  /// Bytes the fitted load puts on the device for compute buffers.
  final int computeBytes;

  /// Creates a [GpuMemoryFitDevice].
  const GpuMemoryFitDevice({
    required this.name,
    required this.freeBytes,
    required this.totalBytes,
    required this.modelBytes,
    required this.contextBytes,
    required this.computeBytes,
  });

  /// Bytes the fitted load is projected to use on the device.
  int get projectedBytes => modelBytes + contextBytes + computeBytes;

  @override
  String toString() =>
      'GpuMemoryFitDevice(name: $name, free: $freeBytes, total: $totalBytes, '
      'projected: $projectedBytes)';
}

/// What a [ModelParams.gpuMemoryFit] request did to a load.
class GpuMemoryFitReport {
  /// How the fit changed the load.
  final GpuMemoryFitOutcome outcome;

  /// Why the load was not fitted, for [GpuMemoryFitOutcome.skipped].
  final String? reason;

  /// Offloadable layers of the model, the output layer included.
  final int modelLayers;

  /// GPU layers the load uses.
  final int gpuLayers;

  /// Context size the load uses; `0` when the fit did not choose one.
  final int contextSize;

  /// The free memory left on each GPU that the fit was asked for.
  final int marginBytes;

  /// The GPUs of the load, empty when the load was not fitted.
  final List<GpuMemoryFitDevice> devices;

  /// How long the fit took.
  final Duration elapsed;

  /// Creates a [GpuMemoryFitReport].
  const GpuMemoryFitReport({
    required this.outcome,
    this.reason,
    this.modelLayers = 0,
    this.gpuLayers = 0,
    this.contextSize = 0,
    this.marginBytes = 0,
    this.devices = const [],
    this.elapsed = Duration.zero,
  });

  @override
  String toString() {
    final buffer = StringBuffer(
      'GpuMemoryFitReport(${outcome.name}, gpuLayers: $gpuLayers of '
      '$modelLayers, contextSize: $contextSize, marginBytes: $marginBytes',
    );
    for (final device in devices) {
      buffer.write(
        ', ${device.name}: free ${device.freeBytes}, projected '
        '${device.projectedBytes}',
      );
    }
    if (reason != null) buffer.write(', reason: $reason');
    buffer.write(')');
    return buffer.toString();
  }
}
