import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// `VK_PHYSICAL_DEVICE_TYPE_CPU`: a software rasterizer such as Mesa
/// llvmpipe (lavapipe) or SwiftShader.
const int vulkanPhysicalDeviceTypeCpu = 4;

const int _vkStructureTypeInstanceCreateInfo = 1;
const int _vkSuccess = 0;

// sizeof(VkPhysicalDeviceProperties) is 824 on LP64; the extra room keeps a
// driver that writes a larger struct from overrunning the buffer.
const int _physicalDevicePropertiesBytes = 2048;
const int _deviceTypeOffset = 16;
const int _deviceNameOffset = 20;
const int _deviceNameCapacity = 256;

/// One Vulkan physical device as the system Vulkan loader reports it.
final class LiteRtLmVulkanAdapter {
  /// Creates the facts of the device called [name].
  const LiteRtLmVulkanAdapter({required this.name, required this.deviceType});

  /// `VkPhysicalDeviceProperties.deviceName`.
  final String name;

  /// `VkPhysicalDeviceProperties.deviceType`, a `VkPhysicalDeviceType`.
  final int deviceType;

  /// Whether the device is a CPU (software) implementation.
  bool get isSoftware => deviceType == vulkanPhysicalDeviceTypeCpu;
}

/// The Vulkan devices LiteRT-LM's Linux GPU backend can choose from.
///
/// That backend runs WebGPU (Dawn) on the system Vulkan loader and picks a
/// software adapter only when no hardware one is present.
final class LiteRtLmVulkanAdapters {
  /// The loader listed [devices].
  const LiteRtLmVulkanAdapters.devices(List<LiteRtLmVulkanAdapter> this.devices)
    : unavailableReason = null;

  /// The devices could not be listed, for [unavailableReason].
  const LiteRtLmVulkanAdapters.unavailable(String this.unavailableReason)
    : devices = null;

  /// The devices, or `null` when they are unknown.
  final List<LiteRtLmVulkanAdapter>? devices;

  /// Why [devices] is `null`.
  final String? unavailableReason;

  /// The devices when every one is software, so the GPU backend can only
  /// select a software adapter; otherwise `null`, including when no device
  /// is listed or the probe was unavailable.
  List<LiteRtLmVulkanAdapter>? get softwareOnly {
    final listed = devices;
    if (listed == null || listed.isEmpty) return null;
    return listed.every((device) => device.isSoftware) ? listed : null;
  }
}

typedef _CreateInstanceNative =
    Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _EnumeratePhysicalDevicesNative =
    Int32 Function(Pointer<Void>, Pointer<Uint32>, Pointer<Pointer<Void>>);
typedef _GetPhysicalDevicePropertiesNative =
    Void Function(Pointer<Void>, Pointer<Void>);
typedef _DestroyInstanceNative = Void Function(Pointer<Void>, Pointer<Void>);

final class _VkInstanceCreateInfo extends Struct {
  @Uint32()
  external int sType;
  external Pointer<Void> pNext;
  @Uint32()
  external int flags;
  external Pointer<Void> pApplicationInfo;
  @Uint32()
  external int enabledLayerCount;
  external Pointer<Pointer<Char>> ppEnabledLayerNames;
  @Uint32()
  external int enabledExtensionCount;
  external Pointer<Pointer<Char>> ppEnabledExtensionNames;
}

/// The Vulkan 1.0 loader entry points the adapter probe calls.
final class LiteRtLmVulkanLoader {
  /// Creates a loader from resolved functions.
  const LiteRtLmVulkanLoader({
    required this.createInstance,
    required this.enumeratePhysicalDevices,
    required this.getPhysicalDeviceProperties,
    required this.destroyInstance,
  });

  /// The Linux Vulkan loader's soname.
  static const String libraryName = 'libvulkan.so.1';

  /// Resolves the entry points from [libraryName], or returns `null` when it
  /// cannot be opened or lacks one. [openLibrary] replaces
  /// [DynamicLibrary.open].
  static LiteRtLmVulkanLoader? tryOpen({
    DynamicLibrary Function(String name)? openLibrary,
  }) {
    try {
      final library = (openLibrary ?? DynamicLibrary.open)(libraryName);
      return LiteRtLmVulkanLoader(
        createInstance: library
            .lookupFunction<
              _CreateInstanceNative,
              int Function(Pointer<Void>, Pointer<Void>, Pointer<Pointer<Void>>)
            >('vkCreateInstance'),
        enumeratePhysicalDevices: library
            .lookupFunction<
              _EnumeratePhysicalDevicesNative,
              int Function(
                Pointer<Void>,
                Pointer<Uint32>,
                Pointer<Pointer<Void>>,
              )
            >('vkEnumeratePhysicalDevices'),
        getPhysicalDeviceProperties: library
            .lookupFunction<
              _GetPhysicalDevicePropertiesNative,
              void Function(Pointer<Void>, Pointer<Void>)
            >('vkGetPhysicalDeviceProperties'),
        destroyInstance: library
            .lookupFunction<
              _DestroyInstanceNative,
              void Function(Pointer<Void>, Pointer<Void>)
            >('vkDestroyInstance'),
      );
    } on ArgumentError {
      return null;
    }
  }

  /// `vkCreateInstance(createInfo, allocator, instance)`.
  final int Function(
    Pointer<Void> createInfo,
    Pointer<Void> allocator,
    Pointer<Pointer<Void>> instance,
  )
  createInstance;

  /// `vkEnumeratePhysicalDevices(instance, count, devices)`.
  final int Function(
    Pointer<Void> instance,
    Pointer<Uint32> count,
    Pointer<Pointer<Void>> devices,
  )
  enumeratePhysicalDevices;

  /// `vkGetPhysicalDeviceProperties(device, properties)`.
  final void Function(Pointer<Void> device, Pointer<Void> properties)
  getPhysicalDeviceProperties;

  /// `vkDestroyInstance(instance, allocator)`.
  final void Function(Pointer<Void> instance, Pointer<Void> allocator)
  destroyInstance;

  /// Lists the physical devices through a short-lived instance.
  LiteRtLmVulkanAdapters listAdapters() {
    final createInfo = calloc<_VkInstanceCreateInfo>();
    final instanceOut = calloc<Pointer<Void>>();
    final count = calloc<Uint32>();
    try {
      createInfo.ref.sType = _vkStructureTypeInstanceCreateInfo;
      final created = createInstance(createInfo.cast(), nullptr, instanceOut);
      if (created != _vkSuccess) {
        return LiteRtLmVulkanAdapters.unavailable(
          'vkCreateInstance returned $created',
        );
      }
      final instance = instanceOut.value;
      try {
        return _listDevices(instance, count);
      } finally {
        destroyInstance(instance, nullptr);
      }
    } finally {
      calloc.free(count);
      calloc.free(instanceOut);
      calloc.free(createInfo);
    }
  }

  LiteRtLmVulkanAdapters _listDevices(
    Pointer<Void> instance,
    Pointer<Uint32> count,
  ) {
    final counted = enumeratePhysicalDevices(instance, count, nullptr);
    if (counted != _vkSuccess) {
      return LiteRtLmVulkanAdapters.unavailable(
        'vkEnumeratePhysicalDevices returned $counted',
      );
    }
    if (count.value == 0) return const LiteRtLmVulkanAdapters.devices([]);
    final handles = calloc<Pointer<Void>>(count.value);
    final properties = calloc<Uint8>(_physicalDevicePropertiesBytes);
    try {
      final listed = enumeratePhysicalDevices(instance, count, handles);
      // VK_INCOMPLETE means more devices exist than were written; a partial
      // list could look software-only, so it counts as unavailable.
      if (listed != _vkSuccess) {
        return LiteRtLmVulkanAdapters.unavailable(
          'vkEnumeratePhysicalDevices returned $listed',
        );
      }
      final devices = <LiteRtLmVulkanAdapter>[];
      for (var index = 0; index < count.value; index++) {
        properties
            .asTypedList(_physicalDevicePropertiesBytes)
            .fillRange(0, _physicalDevicePropertiesBytes, 0);
        getPhysicalDeviceProperties(handles[index], properties.cast());
        devices.add(
          LiteRtLmVulkanAdapter(
            name: _deviceName(properties + _deviceNameOffset),
            deviceType: (properties + _deviceTypeOffset).cast<Int32>().value,
          ),
        );
      }
      return LiteRtLmVulkanAdapters.devices(List.unmodifiable(devices));
    } finally {
      calloc.free(properties);
      calloc.free(handles);
    }
  }
}

String _deviceName(Pointer<Uint8> name) {
  final bytes = name.asTypedList(_deviceNameCapacity);
  final end = bytes.indexOf(0);
  return utf8.decode(
    bytes.sublist(0, end < 0 ? _deviceNameCapacity : end),
    allowMalformed: true,
  );
}

/// Lists the Vulkan devices of the system loader; unavailable when the
/// loader cannot be opened or queried.
///
/// Listing loads the system's Vulkan drivers into the process, as the GPU
/// backend itself does, so probe only when that backend is about to start.
LiteRtLmVulkanAdapters probeLiteRtLmVulkanAdapters({
  DynamicLibrary Function(String name)? openLibrary,
}) {
  final loader = LiteRtLmVulkanLoader.tryOpen(openLibrary: openLibrary);
  return loader == null
      ? const LiteRtLmVulkanAdapters.unavailable(
          'the Vulkan loader ${LiteRtLmVulkanLoader.libraryName} could not be '
          'opened',
        )
      : loader.listAdapters();
}
