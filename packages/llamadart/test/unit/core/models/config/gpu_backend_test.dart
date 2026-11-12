import 'package:llamadart/src/core/models/config/gpu_backend.dart';
import 'package:test/test.dart';

void main() {
  test('GpuBackend names are the native module and display-name keys', () {
    expect(GpuBackend.values.map((backend) => backend.name), [
      'auto',
      'cpu',
      'vulkan',
      'metal',
      'cuda',
      'blas',
      'opencl',
      'hip',
    ]);
  });
}
