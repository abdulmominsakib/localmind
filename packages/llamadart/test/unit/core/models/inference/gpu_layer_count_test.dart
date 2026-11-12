import 'package:llamadart/src/core/models/inference/gpu_layer_count.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

void main() {
  test('a negative count resolves to every layer', () {
    for (final gpuLayers in [-1, -2, -999, -2147483648]) {
      expect(
        resolveGpuLayerCount(gpuLayers),
        ModelParams.maxGpuLayers,
        reason: 'gpuLayers $gpuLayers',
      );
    }
  });

  test('zero and positive counts are unchanged', () {
    for (final gpuLayers in [0, 1, 33, ModelParams.maxGpuLayers, 1000]) {
      expect(
        resolveGpuLayerCount(gpuLayers),
        gpuLayers,
        reason: 'gpuLayers $gpuLayers',
      );
    }
  });
}
