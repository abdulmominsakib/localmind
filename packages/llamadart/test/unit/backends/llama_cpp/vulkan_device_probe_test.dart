@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/vulkan_device_probe.dart';
import 'package:test/test.dart';

const _symbols = [
  'llama_dart_vulkan_get_device_count',
  'llama_dart_vulkan_get_device_info',
];

int _version(int major, int minor, [int patch = 0]) =>
    major << 22 | minor << 12 | patch;

VulkanDeviceFacts _device({
  String name = 'Mali-G715',
  int deviceType = 1,
  int? instanceApiVersion,
  int? apiVersion,
  int subgroupSize = 16,
}) => VulkanDeviceFacts(
  name: name,
  deviceType: deviceType,
  instanceApiVersion: instanceApiVersion ?? _version(1, 3),
  apiVersion: apiVersion ?? _version(1, 3),
  subgroupSize: subgroupSize,
);

void main() {
  group('VulkanDeviceFacts', () {
    test('needs Vulkan 1.2 from the loader and from the driver', () {
      expect(VulkanDeviceFacts.vulkan12, _version(1, 2));
      expect(_device().meetsVulkan12, isTrue);
      expect(
        _device(
          instanceApiVersion: _version(1, 2),
          apiVersion: _version(1, 2),
        ).meetsVulkan12,
        isTrue,
      );
      expect(
        _device(apiVersion: _version(1, 1, 4095)).meetsVulkan12,
        isFalse,
        reason: 'a driver below 1.2 lacks the functions ggml-vulkan calls',
      );
      expect(
        _device(instanceApiVersion: _version(1, 1, 4095)).meetsVulkan12,
        isFalse,
        reason: 'ggml-vulkan registers no device on a loader below 1.2',
      );
    });

    test('matches the Adreno defect by vendor, driver and device name', () {
      VulkanDeviceFacts fact({
        int vendor = 0x5143,
        int driver = 2150604839,
        String name = 'Adreno (TM) 750',
      }) => VulkanDeviceFacts(
        name: name,
        deviceType: 1,
        instanceApiVersion: _version(1, 3),
        apiVersion: _version(1, 3),
        subgroupSize: 64,
        vendorId: vendor,
        driverVersion: driver,
      );
      expect(fact().hasAdreno750DriverDefect, isTrue);
      expect(fact(vendor: 0).hasAdreno750DriverDefect, isFalse);
      expect(fact(driver: 2150604840).hasAdreno750DriverDefect, isFalse);
      expect(fact(name: 'Adreno (TM) 740').hasAdreno750DriverDefect, isFalse);
    });

    test('has the small matmul tile defect at every subgroup size '
        'ggml-vulkan mis-tiles', () {
      // ggml before 0.28.0 gives a warp 8 rows of the 32-row block only at a
      // subgroup size of exactly 8, where the block has max(size, 32) /
      // max(size, 8) warps.
      bool tiled(int size) {
        final warps = (size < 32 ? 32 : size) ~/ (size < 8 ? 8 : size);
        final rowsPerWarp = size == 8 ? 8 : 32;
        return warps * rowsPerWarp == 32;
      }

      for (final size in [0, 1, 2, 4, 8, 16, 32, 64, 128]) {
        expect(
          _device(subgroupSize: size).hasSmallMatmulTileDefect,
          size == 0 || !tiled(size),
          reason: 'subgroup size $size',
        );
      }
      expect(_device(subgroupSize: 16).hasSmallMatmulTileDefect, isTrue);
      expect(_device(subgroupSize: 4).hasSmallMatmulTileDefect, isTrue);
      expect(_device(subgroupSize: 0).hasSmallMatmulTileDefect, isTrue);
      expect(_device(subgroupSize: 8).hasSmallMatmulTileDefect, isFalse);
      expect(_device(subgroupSize: 64).hasSmallMatmulTileDefect, isFalse);
    });

    test('describes itself with its versions and subgroup size', () {
      expect(VulkanDeviceFacts.formatApiVersion(_version(1, 3, 280)), '1.3');
      expect(
        _device(
          apiVersion: _version(1, 1, 177),
          instanceApiVersion: _version(1, 3, 275),
        ).toString(),
        '"Mali-G715" (API 1.1, loader 1.3, subgroup size 16)',
      );
    });
  });

  group('ggmlHasSmallMatmulTileFix', () {
    test('needs ggml 0.28.0 or newer', () {
      for (final version in ['0.28.0', '0.28.3', '0.29.0', '1.0.0', '1.2.3']) {
        expect(ggmlHasSmallMatmulTileFix(version), isTrue, reason: version);
      }
      // 0.27.0 spans llama.cpp commits from before and after the fix.
      for (final version in ['0.27.0', '0.27.9', '0.9.4', '0.0.0']) {
        expect(ggmlHasSmallMatmulTileFix(version), isFalse, reason: version);
      }
    });

    test('treats a missing or unparsable version as unfixed', () {
      for (final version in [
        null,
        '',
        'unknown',
        '0.28',
        'v0.28.0',
        ' 0.28.0',
      ]) {
        expect(ggmlHasSmallMatmulTileFix(version), isFalse, reason: version);
      }
    });
  });

  group('readGgmlVersion', () {
    test('is null for a runtime without ggml_version', () {
      expect(
        readGgmlVersion(call: () => throw ArgumentError('not exported')),
        isNull,
      );
      expect(readGgmlVersion(call: () => nullptr), isNull);
    });

    // Runs the real llama.cpp runtime. Windows bundles keep ggml symbols out
    // of the default asset, so the read returns null there.
    test('the pinned runtime has the small matmul tile fix', () {
      LlamaCppService().initializeBackend();

      final version = readGgmlVersion();

      expect(version, isNotNull);
      expect(ggmlHasSmallMatmulTileFix(version), isTrue, reason: version);
    }, testOn: '!windows');
  });

  group('VulkanDeviceInfoApi', () {
    test('binds both functions through the lookup, and resolves nothing '
        'when one is missing', () {
      final requested = <String>[];
      Pointer<NativeType> exported(String name) {
        requested.add(name);
        return Pointer.fromAddress(0x1000 + requested.length);
      }

      expect(
        VulkanDeviceInfoApi.tryResolve(isWindows: false, symbol: exported),
        isNotNull,
      );
      expect(requested, _symbols);

      for (final missing in _symbols) {
        expect(
          VulkanDeviceInfoApi.tryResolve(
            isWindows: false,
            symbol: (name) => name == missing
                ? throw ArgumentError(
                    "Couldn't resolve native function '$name'",
                  )
                : exported(name),
          ),
          isNull,
          reason: missing,
        );
      }
    });

    test('resolves nothing from a library that exports neither', () {
      final library = DynamicLibrary.open(switch (Platform.operatingSystem) {
        'macos' => '/usr/lib/libSystem.B.dylib',
        'windows' => 'kernel32.dll',
        _ => 'libc.so.6',
      });

      expect(
        VulkanDeviceInfoApi.tryResolve(
          isWindows: false,
          symbol: library.lookup,
        ),
        isNull,
      );
    });

    test('calls the function exported under the name of each member', () {
      final called = <String>[];
      final count = NativeCallable<Int32 Function()>.isolateLocal(() {
        called.add(_symbols[0]);
        return 0;
      }, exceptionalReturn: 0);
      final info =
          NativeCallable<
            Int32 Function(Int32, Pointer<llama_dart_vulkan_device_info>)
          >.isolateLocal((int _, Pointer<llama_dart_vulkan_device_info> _) {
            called.add(_symbols[1]);
            return 0;
          }, exceptionalReturn: 0);
      addTearDown(count.close);
      addTearDown(info.close);
      final api = VulkanDeviceInfoApi.tryResolve(
        isWindows: false,
        symbol: (name) =>
            name == _symbols[0] ? count.nativeFunction : info.nativeFunction,
      )!;

      api.getDeviceCount();
      api.getDeviceInfo(0, nullptr);

      expect(called, _symbols);
    });

    test(
      'lists each device with its name, type, versions and subgroup size',
      () {
        final structSizes = <int>[];
        final api = VulkanDeviceInfoApi(
          getDeviceCount: () => 2,
          getDeviceInfo: (index, info) {
            structSizes.add(info.ref.struct_size);
            final name = utf8.encode(index == 0 ? 'Mali-G715' : 'Xclipse 940');
            for (var i = 0; i < name.length; i++) {
              info.ref.device_name[i] = name[i];
            }
            info.ref.device_name[name.length] = 0;
            info.ref.device_type = index == 0 ? 1 : 2;
            info.ref.instance_api_version = _version(1, 3, 275);
            info.ref.api_version = _version(1, 3 - index, 7);
            info.ref.subgroup_size = index == 0 ? 16 : 64;
            info.ref.vendor_id = 0x5143 + index;
            info.ref.driver_version = 2150604839 + index;
            return 0;
          },
        );

        final devices = api.probe().devices!;

        expect(structSizes, [
          sizeOf<llama_dart_vulkan_device_info>(),
          sizeOf<llama_dart_vulkan_device_info>(),
        ]);
        expect(devices.map((device) => device.toString()), [
          '"Mali-G715" (API 1.3, loader 1.3, subgroup size 16)',
          '"Xclipse 940" (API 1.2, loader 1.3, subgroup size 64)',
        ]);
        expect(devices.map((device) => device.isIntegratedGpu), [true, false]);
        expect(devices.map((device) => device.deviceType), [1, 2]);
        expect(devices.map((device) => device.vendorId), [0x5143, 0x5144]);
        expect(devices.map((device) => device.driverVersion), [
          2150604839,
          2150604840,
        ]);
        expect(api.probe().unavailableReason, isNull);
      },
    );

    test('lists no device when the loader works and ggml would use none', () {
      final api = VulkanDeviceInfoApi(
        getDeviceCount: () => 0,
        getDeviceInfo: (_, _) => fail('no device to describe'),
      );

      expect(api.probe().devices, isEmpty);
    });

    for (final status in llama_dart_vulkan_status.values.where(
      (status) => status.value < 0,
    )) {
      test('is unavailable when the count is ${status.name}', () {
        final api = VulkanDeviceInfoApi(
          getDeviceCount: () => status.value,
          getDeviceInfo: (_, _) => fail('no device to describe'),
        );

        final probe = api.probe();

        expect(probe.devices, isNull);
        expect(
          probe.unavailableReason,
          'llama_dart_vulkan_get_device_count returned ${status.name}',
        );
      });
    }

    test('is unavailable when a device cannot be described, or with a status '
        'this package does not know', () {
      expect(
        VulkanDeviceInfoApi(
          getDeviceCount: () => 2,
          getDeviceInfo: (index, _) => index == 0
              ? 0
              : llama_dart_vulkan_status
                    .LLAMA_DART_VULKAN_STATUS_NO_DEVICE
                    .value,
        ).probe().unavailableReason,
        'llama_dart_vulkan_get_device_info(1) returned '
        'LLAMA_DART_VULKAN_STATUS_NO_DEVICE',
      );
      expect(
        VulkanDeviceInfoApi(
          getDeviceCount: () => -99,
          getDeviceInfo: (_, _) => 0,
        ).probe().unavailableReason,
        'llama_dart_vulkan_get_device_count returned status -99',
      );
    });

    // Runs the real llama.cpp runtime.
    test('the pinned runtime exports the probe', () {
      LlamaCppService().initializeBackend();

      expect(
        VulkanDeviceInfoApi.tryResolve(isWindows: Platform.isWindows),
        isNotNull,
      );
    });

    // Reading the facts loads the system's Vulkan drivers, so this only runs
    // where there is no Vulkan to load.
    test('the pinned runtime reports Apple platforms as unsupported', () {
      LlamaCppService().initializeBackend();

      final probe = VulkanDeviceInfoApi.probeRuntime(isWindows: false);

      expect(probe.devices, isNull);
      expect(
        probe.unavailableReason,
        'llama_dart_vulkan_get_device_count returned '
        'LLAMA_DART_VULKAN_STATUS_UNSUPPORTED',
      );
    }, testOn: 'mac-os');
  });
}
