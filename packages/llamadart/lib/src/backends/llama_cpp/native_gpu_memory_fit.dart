import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../core/models/config/gpu_device_info.dart';
import 'bindings.dart';
import 'gpu_memory_fit.dart';

const _wrapperAsset = 'package:llamadart/llamadart_wrapper';
const _supportedFitApiVersion = 1;
const _statusException = -2147483648;

typedef _FitParams =
    int Function(
      Pointer<Char>,
      Pointer<llama_model_params>,
      Pointer<llama_context_params>,
      Pointer<Float>,
      Pointer<llama_model_tensor_buft_override>,
      Pointer<Size>,
      int,
      Pointer<llama_dart_fit_report>,
    );

// The Windows bundle exports the wrapper functions from a separate library,
// which the generated bindings' default asset does not name.
@Native<Uint32 Function()>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_fit_api_version',
)
external int _wrapperFitApiVersion();

@Native<
  Int32 Function(
    Pointer<Char>,
    Pointer<llama_model_params>,
    Pointer<llama_context_params>,
    Pointer<Float>,
    Pointer<llama_model_tensor_buft_override>,
    Pointer<Size>,
    Uint32,
    Pointer<llama_dart_fit_report>,
  )
>(assetId: _wrapperAsset, symbol: 'llama_dart_fit_params')
external int _wrapperFitParams(
  Pointer<Char> pathModel,
  Pointer<llama_model_params> modelParams,
  Pointer<llama_context_params> contextParams,
  Pointer<Float> tensorSplit,
  Pointer<llama_model_tensor_buft_override> tensorBufferOverrides,
  Pointer<Size> margins,
  int minContextSize,
  Pointer<llama_dart_fit_report> report,
);

@Native<Pointer<Char> Function()>(
  assetId: _wrapperAsset,
  symbol: 'llama_dart_last_error',
)
external Pointer<Char> _wrapperLastError();

/// The runner for the loaded runtime's `llama_dart_fit_params`, or `null` when
/// the runtime does not export fit API version 1.
///
/// [isWindows] selects the wrapper library the Windows bundle splits out.
GpuMemoryFitRunner? resolveNativeGpuMemoryFitRunner({bool? isWindows}) {
  final windows = isWindows ?? Platform.isWindows;
  final int Function() version = windows
      ? _wrapperFitApiVersion
      : llama_dart_fit_api_version;
  final _FitParams fit = windows ? _wrapperFitParams : llama_dart_fit_params;
  final Pointer<Char> Function() lastError = windows
      ? _wrapperLastError
      : llama_dart_last_error;
  try {
    if (version() != _supportedFitApiVersion) return null;
  } on ArgumentError {
    return null;
  }
  return (request) => _run(request, fit, lastError);
}

GpuMemoryFitNativeResult _run(
  GpuMemoryFitRequest request,
  _FitParams fit,
  Pointer<Char> Function() lastError,
) {
  final report = calloc<llama_dart_fit_report>();
  try {
    final code = fit(
      request.modelPath,
      request.modelParams,
      request.contextParams,
      request.tensorSplit,
      request.tensorBufferOverrides,
      request.margins,
      request.minContextSize,
      report,
    );
    final status = switch (code) {
      0 => GpuMemoryFitStatus.success,
      1 => GpuMemoryFitStatus.failure,
      _statusException => GpuMemoryFitStatus.exception,
      _ => GpuMemoryFitStatus.error,
    };
    if (status != GpuMemoryFitStatus.success) {
      final message = lastError();
      return GpuMemoryFitNativeResult(
        status: status,
        error: message == nullptr
            ? null
            : message.cast<Utf8>().toDartString().trim(),
      );
    }
    final fitted = report.ref;
    return GpuMemoryFitNativeResult(
      status: status,
      offloadableLayers: fitted.n_layers,
      skippedLayers: fitted.n_layers_skipped,
      trainedContextSize: fitted.n_ctx_train,
      devices: [
        for (var i = 0; i < fitted.n_devices && i < 16; i++)
          _device(fitted.devices[i]),
      ],
    );
  } finally {
    calloc.free(report);
  }
}

GpuMemoryFitDevice _device(llama_dart_fit_device device) {
  final name = StringBuffer();
  for (var i = 0; i < 64 && device.name[i] != 0; i++) {
    name.writeCharCode(device.name[i]);
  }
  return GpuMemoryFitDevice(
    name: name.toString(),
    freeBytes: device.free_bytes,
    totalBytes: device.total_bytes,
    modelBytes: device.model_bytes,
    contextBytes: device.context_bytes,
    computeBytes: device.compute_bytes,
  );
}
