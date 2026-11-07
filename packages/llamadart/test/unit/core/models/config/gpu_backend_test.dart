import 'package:llamadart/src/core/models/config/gpu_backend.dart';
import 'package:test/test.dart';

void main() {
  test('GpuBackend enum contains expected values', () {
    expect(GpuBackend.values, contains(GpuBackend.auto));
    expect(GpuBackend.values, contains(GpuBackend.cpu));
    expect(GpuBackend.values, contains(GpuBackend.vulkan));
    expect(GpuBackend.values, contains(GpuBackend.metal));
    expect(GpuBackend.values, contains(GpuBackend.opencl));
    expect(GpuBackend.values, contains(GpuBackend.hip));
  });
}
