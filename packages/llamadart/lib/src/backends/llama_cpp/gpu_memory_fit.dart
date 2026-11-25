import 'dart:ffi';

import '../../core/models/config/gpu_device_info.dart';
import 'bindings.dart';

/// The status of a native fit call, as `llama_dart_fit_params` returns it.
enum GpuMemoryFitStatus {
  /// The load is projected to fit, with parameters possibly unchanged.
  success,

  /// No fitting allocation exists, or the parameters cannot be adjusted.
  failure,

  /// A hard error, such as an unreadable model.
  error,

  /// The native call caught an exception.
  exception,
}

/// The default `llama_model_params.n_gpu_layers` the fit requires as input and
/// leaves unchanged when everything fits.
const int gpuMemoryFitDefaultLayers = -1;

/// `n_ctx_min` that keeps the context as requested.
const int gpuMemoryFitKeepContext = 0xFFFFFFFF;

/// What a [GpuMemoryFitRunner] works on.
///
/// The pointers are owned by the caller and valid for the call only. The
/// runner reads and writes the fitted values in place.
final class GpuMemoryFitRequest {
  /// Creates a request.
  const GpuMemoryFitRequest({
    required this.modelPath,
    required this.modelParams,
    required this.contextParams,
    required this.tensorSplit,
    required this.tensorBufferOverrides,
    required this.margins,
    required this.deviceSlots,
    required this.overrideSlots,
    required this.minContextSize,
  });

  /// The GGUF path.
  final Pointer<Char> modelPath;

  /// In and out: `n_gpu_layers`, which must be [gpuMemoryFitDefaultLayers].
  final Pointer<llama_model_params> modelParams;

  /// In and out: `n_ctx`, where `0` lets the fit pick one.
  final Pointer<llama_context_params> contextParams;

  /// Out: [deviceSlots] proportions.
  final Pointer<Float> tensorSplit;

  /// Out: [overrideSlots] overrides, ended by a null pattern.
  final Pointer<llama_model_tensor_buft_override> tensorBufferOverrides;

  /// In: [deviceSlots] bytes to keep free per device.
  final Pointer<Size> margins;

  /// `llama_max_devices()`.
  final int deviceSlots;

  /// `llama_max_tensor_buft_overrides()`.
  final int overrideSlots;

  /// The smallest context the fit may pick, or [gpuMemoryFitKeepContext].
  final int minContextSize;
}

/// What a [GpuMemoryFitRunner] measured.
final class GpuMemoryFitNativeResult {
  /// Creates a result.
  const GpuMemoryFitNativeResult({
    required this.status,
    this.error,
    this.offloadableLayers = 0,
    this.skippedLayers = 0,
    this.trainedContextSize = 0,
    this.devices = const [],
  });

  /// How the fit ended.
  final GpuMemoryFitStatus status;

  /// The native error message of a status other than success.
  final String? error;

  /// Offloadable layers of the model, the output layer and the skipped layers
  /// excluded.
  final int offloadableLayers;

  /// Layers llama.cpp counts for offload but never runs in the main graph,
  /// such as NextN/MTP layers.
  final int skippedLayers;

  /// The `n_gpu_layers` that offloads everything: every layer, the skipped
  /// ones and the output layer.
  int get modelLayers => offloadableLayers + skippedLayers + 1;

  /// The context size the model was trained with.
  final int trainedContextSize;

  /// The GPUs of the load, projected with the fitted parameters.
  final List<GpuMemoryFitDevice> devices;
}

/// Runs llama.cpp's fit on [request].
typedef GpuMemoryFitRunner =
    GpuMemoryFitNativeResult Function(GpuMemoryFitRequest request);

/// Why a load is not fitted, or `null` when it is.
String? gpuMemoryFitSkipReason({
  required String operatingSystem,
  required int gpuLayers,
  required bool noGpuDevice,
}) {
  if (operatingSystem != 'linux' && operatingSystem != 'windows') {
    return 'GPU memory fit applies to Linux and Windows loads; $operatingSystem '
        'shares memory between the CPU and the GPU.';
  }
  if (gpuLayers == 0) {
    return 'The load offloads no layer to a GPU.';
  }
  if (noGpuDevice) {
    return 'The load selects no GPU device.';
  }
  return null;
}

/// How a successful fit changed a load.
///
/// [fittedLayers] is the `n_gpu_layers` the fit left; [offloadableLayers]
/// counts the output layer.
GpuMemoryFitOutcome gpuMemoryFitOutcome({
  required int fittedLayers,
  required int offloadableLayers,
  required bool contextReduced,
}) {
  if (fittedLayers == 0) return GpuMemoryFitOutcome.cpu;
  final allLayers =
      fittedLayers == gpuMemoryFitDefaultLayers ||
      fittedLayers >= offloadableLayers;
  return allLayers && !contextReduced
      ? GpuMemoryFitOutcome.unchanged
      : GpuMemoryFitOutcome.reduced;
}

/// The message logged for [report] of a fit that ran.
String gpuMemoryFitLogMessage(GpuMemoryFitReport report) {
  final devices = [
    for (final device in report.devices)
      '${device.name}: ${device.freeBytes} bytes free, '
          '${device.projectedBytes} projected',
  ].join('; ');
  final suffix = devices.isEmpty ? '' : ' ($devices)';
  return switch (report.outcome) {
    GpuMemoryFitOutcome.unchanged =>
      'gpuMemoryFit: all ${report.modelLayers} layers fit with a '
          '${report.marginBytes}-byte margin$suffix.',
    GpuMemoryFitOutcome.reduced =>
      'gpuMemoryFit: offloading ${report.gpuLayers} of ${report.modelLayers} '
          'layers, context ${report.contextSize}, to fit free GPU memory '
          'with a ${report.marginBytes}-byte margin$suffix.',
    GpuMemoryFitOutcome.cpu =>
      'gpuMemoryFit: no layer fits free GPU memory with a '
          '${report.marginBytes}-byte margin, so the model loads on the '
          'CPU$suffix.',
    GpuMemoryFitOutcome.skipped => 'gpuMemoryFit skipped: ${report.reason}',
  };
}
