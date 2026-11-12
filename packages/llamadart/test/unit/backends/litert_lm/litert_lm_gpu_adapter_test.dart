@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_gpu_adapter.dart';
import 'package:test/test.dart';

void main() {
  group('LiteRtLmVulkanAdapters.softwareOnly', () {
    const llvmpipe = LiteRtLmVulkanAdapter(
      name: 'llvmpipe (LLVM 20.1.2, 256 bits)',
      deviceType: 4,
    );
    const swiftShader = LiteRtLmVulkanAdapter(
      name: 'SwiftShader Device (Subzero)',
      deviceType: 4,
    );

    test('lists the devices when every one is a CPU device', () {
      const adapters = LiteRtLmVulkanAdapters.devices([llvmpipe, swiftShader]);
      expect(adapters.softwareOnly, [llvmpipe, swiftShader]);
    });

    for (final (name, type) in [
      ('other', 0),
      ('integrated', 1),
      ('discrete', 2),
      ('virtual', 3),
    ]) {
      test('is null beside a $name GPU', () {
        final adapters = LiteRtLmVulkanAdapters.devices([
          llvmpipe,
          LiteRtLmVulkanAdapter(name: 'gpu', deviceType: type),
        ]);
        expect(adapters.softwareOnly, isNull);
      });
    }

    test('is null without devices or facts', () {
      expect(const LiteRtLmVulkanAdapters.devices([]).softwareOnly, isNull);
      expect(
        const LiteRtLmVulkanAdapters.unavailable('no loader').softwareOnly,
        isNull,
      );
    });
  });

  group('LiteRtLmVulkanLoader.listAdapters', () {
    late _FakeVulkan vulkan;

    setUp(() => vulkan = _FakeVulkan());
    tearDown(() => vulkan.dispose());

    test('reads each device name and type from VkPhysicalDeviceProperties', () {
      vulkan.devices = [
        ('llvmpipe (LLVM 20.1.2, 256 bits)', 4),
        ('NVIDIA L4', 2),
      ];

      final adapters = vulkan.loader.listAdapters();

      expect(adapters.unavailableReason, isNull);
      expect(
        [
          for (final device in adapters.devices!)
            (device.name, device.deviceType),
        ],
        [('llvmpipe (LLVM 20.1.2, 256 bits)', 4), ('NVIDIA L4', 2)],
      );
      expect(vulkan.createInfoStructureType, 1);
      expect(vulkan.destroyedInstances, 1);
    });

    test('is unavailable when the loader reports VK_INCOMPLETE', () {
      vulkan.devices = [('llvmpipe', 4), ('NVIDIA L4', 2)];
      vulkan.countedDevices = 1;

      final adapters = vulkan.loader.listAdapters();

      expect(adapters.devices, isNull);
      expect(
        adapters.unavailableReason,
        'vkEnumeratePhysicalDevices returned 5',
      );
      expect(vulkan.destroyedInstances, 1);
    });

    test('reads the count the second call rewrites', () {
      vulkan.devices = [('llvmpipe', 4), ('NVIDIA L4', 2), ('gone', 2)];
      vulkan.writtenDevices = 2;

      final adapters = vulkan.loader.listAdapters();

      expect(adapters.unavailableReason, isNull);
      expect(
        [for (final device in adapters.devices!) device.name],
        ['llvmpipe', 'NVIDIA L4'],
      );
      expect(vulkan.destroyedInstances, 1);
    });

    test('lists no device when the loader reports none', () {
      final adapters = vulkan.loader.listAdapters();

      expect(adapters.devices, isEmpty);
      expect(vulkan.destroyedInstances, 1);
    });

    test('is unavailable when the instance cannot be created', () {
      vulkan.createResult = -9;

      final adapters = vulkan.loader.listAdapters();

      expect(adapters.devices, isNull);
      expect(adapters.unavailableReason, 'vkCreateInstance returned -9');
      expect(vulkan.destroyedInstances, 0);
    });

    test('is unavailable when the devices cannot be enumerated', () {
      vulkan.enumerateResult = -3;

      final adapters = vulkan.loader.listAdapters();

      expect(adapters.devices, isNull);
      expect(
        adapters.unavailableReason,
        'vkEnumeratePhysicalDevices returned -3',
      );
      expect(vulkan.destroyedInstances, 1);
    });
  });

  group('probeLiteRtLmVulkanAdapters', () {
    test('is unavailable when the loader cannot be opened', () {
      String? opened;
      final adapters = probeLiteRtLmVulkanAdapters(
        openLibrary: (name) {
          opened = name;
          throw ArgumentError('not found');
        },
      );

      expect(opened, 'libvulkan.so.1');
      expect(adapters.devices, isNull);
      expect(adapters.unavailableReason, contains('libvulkan.so.1'));
    });

    test('is unavailable when the library lacks the entry points', () {
      final adapters = probeLiteRtLmVulkanAdapters(
        openLibrary: (_) => DynamicLibrary.process(),
      );

      expect(adapters.devices, isNull);
    });
  });
}

/// A Vulkan loader whose instance and devices are Dart memory.
final class _FakeVulkan {
  final Pointer<Uint8> _instance = calloc<Uint8>();
  final List<Pointer<Uint8>> _handles = [];

  List<(String, int)> devices = [];
  int createResult = 0;
  int enumerateResult = 0;

  /// The count the first call reports when it is below [devices], as when a
  /// device appears between the two calls.
  int? countedDevices;

  /// The devices the second call writes and reports with `VK_SUCCESS` when
  /// fewer than the first count, as when a device disappears between calls.
  int? writtenDevices;
  int? createInfoStructureType;
  int destroyedInstances = 0;

  LiteRtLmVulkanLoader get loader => LiteRtLmVulkanLoader(
    createInstance: (createInfo, allocator, instance) {
      createInfoStructureType = createInfo.cast<Uint32>().value;
      if (createResult == 0) instance.value = _instance.cast();
      return createResult;
    },
    enumeratePhysicalDevices: (instance, count, handles) {
      expect(instance, _instance.cast<Void>());
      if (enumerateResult != 0) return enumerateResult;
      if (handles == nullptr) {
        count.value = countedDevices ?? devices.length;
        return 0;
      }
      final available = writtenDevices ?? devices.length;
      final written = count.value < available ? count.value : available;
      for (var index = 0; index < written; index++) {
        final handle = calloc<Uint8>()..value = index;
        _handles.add(handle);
        handles[index] = handle.cast();
      }
      count.value = written;
      return written < available ? 5 : 0;
    },
    getPhysicalDeviceProperties: (device, properties) {
      if (device == nullptr) {
        throw StateError('Read an unwritten device handle.');
      }
      final (name, type) = devices[device.cast<Uint8>().value];
      final bytes = properties.cast<Uint8>();
      (bytes + 16).cast<Int32>().value = type;
      final encoded = utf8.encode(name);
      (bytes + 20).asTypedList(256).setAll(0, encoded);
    },
    destroyInstance: (instance, allocator) {
      expect(instance, _instance.cast<Void>());
      destroyedInstances++;
    },
  );

  void dispose() {
    for (final handle in _handles) {
      calloc.free(handle);
    }
    calloc.free(_instance);
  }
}
