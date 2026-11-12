import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  group('encoderModelParams', () {
    test('uses a 512-token context on the best device by default', () {
      final params = const DecisionModelParams().encoderModelParams;

      expect(params.contextSize, 512);
      expect(params.device, ComputeDevice.auto);
      expect(params.preferredBackend, GpuBackend.auto);
      expect(params.gpuLayers, ModelParams.maxGpuLayers);
      expect(params.numberOfThreads, 0);
      expect(params.numberOfThreadsBatch, 0);
    });

    test('requires a GPU for ComputeDevice.gpu', () {
      final params = const DecisionModelParams(
        device: ComputeDevice.gpu,
      ).encoderModelParams;

      expect(params.device, ComputeDevice.gpu);
      expect(params.gpuLayers, ModelParams.maxGpuLayers);
      expect(params.validate, returnsNormally);
    });

    test('keeps ComputeDevice.cpu off the GPU and applies threads', () {
      final params = const DecisionModelParams(
        device: ComputeDevice.cpu,
        threads: 6,
      ).encoderModelParams;

      expect(params.contextSize, 512);
      expect(params.device, ComputeDevice.cpu);
      expect(params.numberOfThreads, 6);
      expect(params.numberOfThreadsBatch, 6);
    });
  });
}
