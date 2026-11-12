@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/gpu_device_placement.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/load_device_selection.dart';
import 'package:test/test.dart';

import '../../../support/recording_allocator.dart';

final int _gpu = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value;
final int _igpu = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU.value;
final int _cpu = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value;

GgmlDeviceEntry _device(String name, String registry, {int? type}) =>
    GgmlDeviceEntry(name: name, registry: registry, type: type ?? _gpu);

final _cuda0 = _device('CUDA0', 'CUDA');
final _cuda1 = _device('CUDA1', 'CUDA');
final _cuda2 = _device('CUDA2', 'CUDA');
final _vulkan0 = _device('Vulkan0', 'Vulkan');
final _vulkan1 = _device('Vulkan1', 'Vulkan');
final _host = _device('CPU', 'CPU', type: _cpu);

void main() {
  GpuDevicePlacement? resolve(
    ModelParams params, {
    GpuBackend backend = GpuBackend.cuda,
    List<GgmlDeviceEntry>? registered,
    int maxDevices = 16,
  }) => resolveGpuDevicePlacement(
    params,
    backend: backend,
    registered: registered ?? [_host, _cuda0, _vulkan0, _cuda1, _cuda2],
    backendOf: LlamaCppService.gpuBackendFromRegName,
    maxDevices: maxDevices,
    platform: 'linux',
  );

  Matcher unsupported(Object message) => throwsA(
    isA<LlamaUnsupportedException>().having(
      (e) => e.message,
      'message',
      allOf(
        contains('llama.cpp multi-GPU placement'),
        contains('linux'),
        message,
      ),
    ),
  );

  test('offload devices are numbered per backend as listGpuDevices does', () {
    expect(
      offloadDevicesOf(
        [_host, _cuda0, _vulkan0, _cuda1, _vulkan1],
        GpuBackend.cuda,
        LlamaCppService.gpuBackendFromRegName,
      ),
      [_cuda0, _cuda1],
    );
    expect(
      offloadDevicesOf(
        [_host, _cuda0, _vulkan0, _cuda1, _vulkan1],
        GpuBackend.vulkan,
        LlamaCppService.gpuBackendFromRegName,
      ),
      [_vulkan0, _vulkan1],
    );
  });

  test('a CPU-type device of a GPU registry is not an offload device', () {
    expect(
      offloadDevicesOf(
        [_device('CUDA-host', 'CUDA', type: _cpu), _cuda0],
        GpuBackend.cuda,
        LlamaCppService.gpuBackendFromRegName,
      ),
      [_cuda0],
    );
  });

  test('neither field leaves the placement to llama.cpp', () {
    expect(resolve(const ModelParams()), isNull);
  });

  test('gpuDevices picks the listed devices in the listed order', () {
    final placement = resolve(const ModelParams(gpuDevices: [2, 0]))!;
    expect(placement.devices, [_cuda2, _cuda0]);
    expect(placement.tensorSplit, isNull);
    expect(placement.deviceNames, 'CUDA2, CUDA0');
  });

  test('tensorSplit follows gpuDevices', () {
    final placement = resolve(
      const ModelParams(gpuDevices: [0, 2], tensorSplit: [3, 1]),
    )!;
    expect(placement.devices, [_cuda0, _cuda2]);
    expect(placement.tensorSplit, [3, 1]);
  });

  test('tensorSplit alone covers every device of the backend', () {
    final placement = resolve(const ModelParams(tensorSplit: [1, 1, 2]))!;
    expect(placement.devices, [_cuda0, _cuda1, _cuda2]);
    expect(placement.tensorSplit, [1, 1, 2]);
  });

  test('a device index the host does not have is refused', () {
    expect(
      () => resolve(
        const ModelParams(gpuDevices: [0, 1]),
        registered: [_host, _cuda0],
      ),
      unsupported(
        allOf(
          contains('gpuDevices names cuda device 1'),
          contains('this host has 1 (CUDA0)'),
        ),
      ),
    );
  });

  test('a split whose length differs from the device count is refused', () {
    expect(
      () => resolve(const ModelParams(tensorSplit: [1, 1])),
      unsupported(
        allOf(
          contains('tensorSplit holds 2 proportions'),
          contains('3 cuda devices (CUDA0, CUDA1, CUDA2)'),
        ),
      ),
    );
    expect(
      () =>
          resolve(const ModelParams(tensorSplit: [1, 1]), registered: [_cuda0]),
      unsupported(contains('1 cuda device (CUDA0)')),
    );
  });

  test('a backend without devices is refused', () {
    expect(
      () => resolve(
        const ModelParams(gpuDevices: [0]),
        backend: GpuBackend.metal,
      ),
      unsupported(contains('lists no metal device')),
    );
  });

  test('more devices than llama.cpp supports are refused', () {
    expect(
      () => resolve(const ModelParams(gpuDevices: [0, 1]), maxDevices: 1),
      unsupported(contains('at most 1')),
    );
    expect(
      resolve(const ModelParams(gpuDevices: [0, 1]), maxDevices: 2)!.devices,
      [_cuda0, _cuda1],
    );
  });

  group('preferredBackend auto', () {
    test('uses the only GPU backend with devices', () {
      final placement = resolve(
        const ModelParams(gpuDevices: [1]),
        backend: GpuBackend.auto,
        registered: [_host, _cuda0, _cuda1],
      )!;
      expect(placement.devices, [_cuda1]);
      final metal = _device('MTL0', 'MTL', type: _igpu);
      expect(
        resolve(
          const ModelParams(gpuDevices: [0]),
          backend: GpuBackend.auto,
          registered: [_host, metal],
        )!.devices,
        [metal],
      );
    });

    test('is refused when several GPU backends have devices', () {
      expect(
        () => resolve(
          const ModelParams(gpuDevices: [0]),
          backend: GpuBackend.auto,
        ),
        unsupported(
          allOf(
            contains('more than one GPU backend'),
            contains('cuda, vulkan'),
            contains('Set preferredBackend'),
          ),
        ),
      );
    });

    test('is refused without a GPU', () {
      expect(
        () => resolve(
          const ModelParams(tensorSplit: [1]),
          backend: GpuBackend.auto,
          registered: [_host],
        ),
        unsupported(contains('lists no GPU device')),
      );
    });
  });

  group('allocateTensorSplit', () {
    List<double> allocate(List<double> split, {int maxDevices = 4}) {
      final allocator = RecordingAllocator();
      final array = allocateTensorSplit(
        split,
        maxDevices: maxDevices,
        allocator: allocator,
      );
      try {
        // llama.cpp copies llama_max_devices() floats from the array.
        expect(allocator.byteCounts, [maxDevices * sizeOf<Float>()]);
        return [for (var i = 0; i < maxDevices; i++) array[i]];
      } finally {
        allocator.free(array);
        allocator.expectAllFreed();
      }
    }

    for (final split in <List<double>>[
      [1.7e308, 1.7e308],
      [double.infinity, 1],
      [double.nan, 1],
    ]) {
      test('rejects non-finite sum $split before allocating', () {
        final allocator = RecordingAllocator();
        Pointer<Float>? array;
        Object? failure;
        try {
          array = allocateTensorSplit(
            split,
            maxDevices: 4,
            allocator: allocator,
          );
        } catch (error) {
          failure = error;
        } finally {
          if (array != null) allocator.free(array);
        }
        allocator.expectAllFreed();
        expect(allocator.allocations, 0);
        expect(
          failure,
          isA<LlamaArgumentException>()
              .having((error) => error.name, 'name', 'tensorSplit')
              .having(
                (error) => error.message,
                'message',
                contains('finite sum'),
              ),
        );
      });
    }

    test('scales a very large finite float64 sum without erasing it', () {
      final scaled = allocate([double.maxFinite / 2, double.maxFinite / 2]);
      expect(scaled.take(2), everyElement(isPositive));
      expect(scaled.take(2).every((value) => value.isFinite), isTrue);
      expect(scaled[0], scaled[1]);
      expect(scaled[0] + scaled[1], lessThanOrEqualTo(math.pow(2.0, 64)));
      expect(scaled.skip(2), [0, 0]);
    });

    test('holds llama_max_devices() floats, zero after the split', () {
      expect(allocate(const [3, 1]), [3, 1, 0, 0]);
      expect(allocate(const [2], maxDevices: 16), [2, ...List.filled(15, 0)]);
    });

    test('keeps a sum of at most 2^64 as given', () {
      final limit = math.pow(2.0, 64).toDouble();
      expect(allocate([limit / 2, limit / 2]), [limit / 2, limit / 2, 0, 0]);
    });

    test('scales a larger sum down by a power of two', () {
      for (final split in <List<double>>[
        const [1e35, 1.0],
        const [3.4028234663852886e38, 5.070602400912918e30, 1.0],
        List.filled(4, 2.1e37),
      ]) {
        final scaled = allocate(split).sublist(0, split.length);
        final ratio = scaled.first / Float32List.fromList(split).first;
        final scale = math
            .pow(2.0, (math.log(ratio) / math.ln2).round())
            .toDouble();
        expect(ratio, scale, reason: 'a power of two keeps float32 ratios');
        expect(scale, lessThan(1), reason: '$split');
        expect(
          scaled,
          Float32List.fromList([for (final value in split) value * scale]),
        );
        expect(
          scaled.fold<double>(0, (a, b) => a + b),
          lessThanOrEqualTo(math.pow(2.0, 64)),
        );
      }
    });

    // Mirrors llama-model.cpp 620d2225 tensor split mode: every rotation of
    // the float32 running sum, with `ne_s * scan[j] / scan.back()` in float32.
    List<double>? tensorRows(List<double> stored, int rows) {
      final n = stored.length;
      final result = <double>[];
      final f = Float32List(3);
      for (var rotation = 0; rotation < n; rotation++) {
        final scan = Float32List(n);
        for (var j = 0; j < n; j++) {
          scan[j] = stored[(j + rotation) % n];
          if (j > 0) scan[j] = scan[j] + scan[j - 1];
        }
        for (var j = 0; j < n - 1; j++) {
          f[0] = rows.toDouble();
          f[1] = f[0] * scan[j];
          f[2] = f[1] / scan[n - 1];
          if (!f[2].isFinite) return null;
          result.add(f[2]);
        }
      }
      return result;
    }

    test('keeps tensor split mode row counts finite and unchanged', () {
      for (final rows in [4096, 262144, 1 << 31]) {
        for (final split in <List<double>>[
          const [3.0, 1.0],
          const [1.0, 1.0, 1.0],
          const [5.0, 3.0, 2.0, 7.0],
          const [0.3, 0.7],
          const [1e34, 1.0],
          const [1e35, 1.0],
          const [3.4028234663852886e38, 5.070602400912918e30, 5.07e30],
          List.filled(16, 2.1e37),
        ]) {
          final stored = Float32List.fromList(split);
          final scaled = allocate(
            split,
            maxDevices: 16,
          ).sublist(0, split.length);
          final expected = tensorRows(stored, rows);
          final actual = tensorRows(scaled, rows);
          expect(actual, isNotNull, reason: '$split over $rows rows');
          if (expected != null) {
            expect(actual, expected, reason: '$split over $rows rows');
          }
        }
      }
      expect(
        tensorRows(Float32List.fromList(const [1e35, 1.0]), 4096),
        isNull,
        reason: 'the unscaled split overflows, as the issue reports',
      );
    });
  });

  group('auxiliaryPlacementDevice', () {
    GgmlDeviceEntry device(String name, int address, {int? type}) =>
        GgmlDeviceEntry(
          name: name,
          registry: 'CUDA',
          type: type ?? _gpu,
          device: Pointer.fromAddress(address),
        );
    final cuda1 = device('CUDA1', 0x10);
    final cuda3 = device('CUDA3', 0x20, type: _igpu);
    final accel = device(
      'ACCEL',
      0x30,
      type: ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_ACCEL.value,
    );

    test('is the listed GPU mainGpu names, or the first listed', () {
      final placement = GpuDevicePlacement(devices: [cuda3, cuda1]);
      expect(auxiliaryPlacementDevice(placement, 0), cuda3);
      expect(auxiliaryPlacementDevice(placement, 1), cuda1);
      for (final outOfRange in [-1, 2, 99]) {
        expect(auxiliaryPlacementDevice(placement, outOfRange), cuda3);
      }
    });

    test('counts and picks GPUs and integrated GPUs only', () {
      expect(
        auxiliaryPlacementDevice(
          GpuDevicePlacement(devices: [accel, cuda1, cuda3]),
          1,
        ),
        cuda3,
      );
      expect(
        auxiliaryPlacementDevice(GpuDevicePlacement(devices: [accel]), 0),
        isNull,
      );
      expect(
        auxiliaryPlacementDevice(
          GpuDevicePlacement(devices: [_cuda0, cuda1]),
          0,
        ),
        cuda1,
        reason: 'a device without a ggml handle cannot run a component',
      );
    });

    test('ignores null and nullptr handles before counting mainGpu', () {
      final noHandle = GgmlDeviceEntry(
        name: 'missing',
        registry: 'CUDA',
        type: _gpu,
      );
      final nullPointer = device('nullptr', 0, type: _igpu);
      for (final unavailable in [noHandle, nullPointer]) {
        expect(
          auxiliaryPlacementDevice(
            GpuDevicePlacement(devices: [unavailable, cuda1, cuda3]),
            0,
          ),
          cuda1,
        );
        expect(
          auxiliaryPlacementDevice(
            GpuDevicePlacement(devices: [unavailable, cuda1, cuda3]),
            1,
          ),
          cuda3,
        );
        expect(
          auxiliaryPlacementDevice(
            GpuDevicePlacement(devices: [unavailable, accel]),
            0,
          ),
          isNull,
        );
      }
    });
  });
}
