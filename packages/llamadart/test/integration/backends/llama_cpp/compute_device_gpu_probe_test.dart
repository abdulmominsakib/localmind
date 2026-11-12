@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:test/test.dart';

/// Runs the registered-device probe of `ComputeDevice.gpu` against the real
/// ggml registry. Only a header-only GGUF is needed: the probe runs before
/// llama.cpp reads the model, so a host with a GPU fails later, in the load.
void main() {
  late Directory dir;
  late String modelPath;
  late LlamaCppService service;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('compute_device_probe_');
    modelPath = '${dir.path}/header_only.gguf';
    File(
      modelPath,
    ).writeAsBytesSync([0x47, 0x47, 0x55, 0x46, ...List.filled(64, 0)]);
    service = LlamaCppService();
  });

  tearDownAll(() {
    service.dispose();
    dir.deleteSync(recursive: true);
  });

  Object? loadOnGpu(GpuBackend backend) {
    try {
      service.loadModel(
        modelPath,
        ModelParams(device: ComputeDevice.gpu, preferredBackend: backend),
      );
    } catch (error) {
      return error;
    }
    return null;
  }

  bool isNoGpu(Object? error) =>
      error is LlamaUnsupportedException &&
      error.toString().contains('ComputeDevice.gpu needs');

  bool hostHasGpu() {
    const gpuTypes = {
      ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU,
      ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU,
    };
    for (var i = 0; i < ggml_backend_dev_count(); i++) {
      final device = ggml_backend_dev_get(i);
      if (device != nullptr &&
          gpuTypes.contains(ggml_backend_dev_type$1(device))) {
        return true;
      }
    }
    return false;
  }

  test('the CPU backend never counts as a GPU device', () async {
    expect(isNoGpu(loadOnGpu(GpuBackend.cpu)), isTrue);
  });

  test(
    'an automatic backend finds a GPU exactly when one is registered',
    skip: Platform.isWindows
        ? 'On Windows the ggml symbols live in a separate DLL that the '
              'binding used to count devices does not resolve.'
        : null,
    () async {
      final error = loadOnGpu(GpuBackend.auto);

      expect(isNoGpu(error), !hostHasGpu(), reason: '$error');
    },
  );
}
