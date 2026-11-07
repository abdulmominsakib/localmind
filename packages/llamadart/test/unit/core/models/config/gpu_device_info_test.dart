import 'package:llamadart/src/core/models/config/gpu_backend.dart';
import 'package:llamadart/src/core/models/config/gpu_device_info.dart';
import 'package:test/test.dart';

void main() {
  test('GpuDeviceType enum contains expected values', () {
    expect(GpuDeviceType.values, contains(GpuDeviceType.cpu));
    expect(GpuDeviceType.values, contains(GpuDeviceType.discreteGpu));
    expect(GpuDeviceType.values, contains(GpuDeviceType.integratedGpu));
    expect(GpuDeviceType.values, contains(GpuDeviceType.accelerator));
    expect(GpuDeviceType.values, contains(GpuDeviceType.unknown));
  });

  test('GpuDeviceInfo exposes its fields', () {
    const device = GpuDeviceInfo(
      backend: GpuBackend.vulkan,
      mainGpu: 1,
      name: 'Vulkan1',
      description: 'NVIDIA GeForce RTX 5050 Laptop GPU',
      deviceId: '0000:64:00.0',
      type: GpuDeviceType.discreteGpu,
      memoryFreeBytes: 7910,
      memoryTotalBytes: 8192,
    );

    expect(device.backend, GpuBackend.vulkan);
    expect(device.mainGpu, 1);
    expect(device.name, 'Vulkan1');
    expect(device.description, 'NVIDIA GeForce RTX 5050 Laptop GPU');
    expect(device.deviceId, '0000:64:00.0');
    expect(device.type, GpuDeviceType.discreteGpu);
    expect(device.memoryFreeBytes, 7910);
    expect(device.memoryTotalBytes, 8192);
  });

  test('isDiscreteGpu is true only for a discrete GPU', () {
    const discrete = GpuDeviceInfo(
      backend: GpuBackend.vulkan,
      mainGpu: 1,
      name: 'Vulkan1',
      description: 'NVIDIA GeForce RTX 5050 Laptop GPU',
      deviceId: '',
      type: GpuDeviceType.discreteGpu,
      memoryFreeBytes: 0,
      memoryTotalBytes: 0,
    );
    const integrated = GpuDeviceInfo(
      backend: GpuBackend.vulkan,
      mainGpu: 0,
      name: 'Vulkan0',
      description: 'AMD Radeon 860M Graphics',
      deviceId: '',
      type: GpuDeviceType.integratedGpu,
      memoryFreeBytes: 0,
      memoryTotalBytes: 0,
    );

    expect(discrete.isDiscreteGpu, isTrue);
    expect(integrated.isDiscreteGpu, isFalse);
  });

  test('toString includes backend, description, and type', () {
    const device = GpuDeviceInfo(
      backend: GpuBackend.cuda,
      mainGpu: 0,
      name: 'CUDA0',
      description: 'NVIDIA RTX',
      deviceId: '',
      type: GpuDeviceType.discreteGpu,
      memoryFreeBytes: 1,
      memoryTotalBytes: 2,
    );

    final text = device.toString();
    expect(text, contains('cuda'));
    expect(text, contains('NVIDIA RTX'));
    expect(text, contains('discreteGpu'));
  });
}
