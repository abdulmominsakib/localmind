import 'bindings.dart';
import 'vulkan_device_probe.dart';

/// One registered ggml device, as llama.cpp reads it when it picks the
/// devices of a model.
final class GgmlDeviceEntry {
  /// Describes the registered [device].
  const GgmlDeviceEntry({
    required this.name,
    required this.type,
    required this.registry,
    this.description = '',
    this.deviceId,
    this.device,
  });

  /// `ggml_backend_dev_name`, such as `Vulkan0` or `CUDA1`.
  final String name;

  /// The raw `ggml_backend_dev_type` value.
  final int type;

  /// `ggml_backend_reg_name` of the device's backend, such as `Vulkan`.
  final String registry;

  /// `ggml_backend_dev_description`: for a ggml-vulkan device the
  /// `VkPhysicalDeviceProperties.deviceName`. Empty when it was not read.
  final String description;

  /// `ggml_backend_dev_props.device_id`, which names one physical GPU across
  /// backends, or `null` when the backend reports none.
  final String? deviceId;

  /// The device itself; `null` for a description that stands in for one.
  final ggml_backend_dev_t? device;

  /// Whether the device belongs to ggml-vulkan.
  bool get isVulkan => registry.toLowerCase() == 'vulkan';

  @override
  String toString() => name;
}

final int _typeCpu = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value;
final int _typeAccel =
    ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_ACCEL.value;
final int _typeGpu = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value;
final int _typeIgpu = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU.value;
final int _splitNone = llama_split_mode.LLAMA_SPLIT_MODE_NONE.value;
final int _splitRow = llama_split_mode.LLAMA_SPLIT_MODE_ROW.value;
final int _splitTensor = llama_split_mode.LLAMA_SPLIT_MODE_TENSOR.value;

/// Whether llama.cpp clears the model's GPU device list for this placement.
///
/// Mirrors `llama_prepare_model_devices` in llama.cpp `v0.7.0`: a negative
/// [mainGpu] selects no GPU only in single-device ([splitMode] NONE) mode.
/// Other split modes do not use [mainGpu] to prune devices.
bool selectsNoGpuDevice({required int splitMode, required int mainGpu}) =>
    splitMode == _splitNone && mainGpu < 0;

/// The devices llama.cpp `v0.6.0` uses for a model, in its order.
///
/// Mirrors `llama_prepare_model_devices` (`src/llama.cpp`). With [listed]
/// (`llama_model_params.devices`) those devices are used. Without it the
/// [registered] devices are searched: in tensor split mode every device that
/// is not a CPU or an accelerator; otherwise RPC servers, then the discrete
/// GPUs, skipping one whose device id an earlier GPU has, and the integrated
/// GPUs of one backend only when there is no discrete GPU. In
/// `LLAMA_SPLIT_MODE_NONE` only the device [mainGpu] indexes is left, and
/// none for a negative or out-of-range [mainGpu].
List<GgmlDeviceEntry> selectModelDevices({
  required List<GgmlDeviceEntry> registered,
  required List<GgmlDeviceEntry>? listed,
  required int splitMode,
  required int mainGpu,
}) {
  final List<GgmlDeviceEntry> devices;
  if (listed != null) {
    devices = listed;
  } else if (splitMode == _splitTensor) {
    devices = [
      for (final device in registered)
        if (device.type != _typeCpu && device.type != _typeAccel) device,
    ];
  } else {
    final rpcServers = <GgmlDeviceEntry>[];
    final gpus = <GgmlDeviceEntry>[];
    final igpus = <GgmlDeviceEntry>[];
    for (final device in registered) {
      if (device.type == _typeGpu) {
        if (device.registry == 'RPC') {
          rpcServers.add(device);
        } else if (!gpus.any(
          (gpu) =>
              gpu.deviceId != null &&
              device.deviceId != null &&
              gpu.deviceId == device.deviceId,
        )) {
          gpus.add(device);
        }
      } else if (device.type == _typeIgpu &&
          (igpus.isEmpty || igpus.last.registry == device.registry)) {
        igpus.add(device);
      }
    }
    devices = [...rpcServers, ...gpus, if (gpus.isEmpty) ...igpus];
  }
  if (splitMode != _splitNone || devices.isEmpty) return devices;
  return mainGpu >= 0 && mainGpu < devices.length
      ? [devices[mainGpu]]
      : const <GgmlDeviceEntry>[];
}

/// Why llama.cpp cannot load in [splitMode] row on the model [devices]
/// (`selectModelDevices`, or the list the load passes), or `null` when it can
/// or [splitMode] is not row.
///
/// Mirrors `make_gpu_buft_list` (`src/llama-model.cpp`): in row split mode
/// llama.cpp fails the load of a model device, the CPU of a CPU list
/// included, whose backend registry does not export
/// `ggml_backend_split_buffer_type`. [hasSplitBufferType] probes that.
String? rowSplitUnsupportedReason({
  required int splitMode,
  required List<GgmlDeviceEntry> devices,
  required bool Function(GgmlDeviceEntry device) hasSplitBufferType,
}) {
  if (splitMode != _splitRow) return null;
  for (final device in devices) {
    if (hasSplitBufferType(device)) continue;
    final named = device.registry.isEmpty
        ? device.name
        : '${device.name} (${device.registry})';
    return 'it needs llama.cpp split buffer types '
        '(ggml_backend_split_buffer_type) on every model device, and the '
        'backend of $named provides none';
  }
  return null;
}

/// What a model load does about selected Vulkan devices ggml-vulkan cannot
/// drive.
final class VulkanLoadDecision {
  const VulkanLoadDecision._({this.unsupported, this.devices});

  /// Every selected device is usable or unknown: the load goes ahead as it
  /// is.
  static const VulkanLoadDecision unchanged = VulkanLoadDecision._();

  /// Why the load must not start a device, or `null`. Names the first
  /// unusable device and its versions.
  final String? unsupported;

  /// The usable devices to list for the load in place of the selected ones;
  /// `null` when no listed load can avoid the unusable devices, which is when
  /// every selected device is one, or an unsafe Android driver is registered,
  /// and when nothing changes.
  final List<GgmlDeviceEntry>? devices;

  /// Whether no usable device is left, so the load cannot run on the GPU.
  bool get refused => unsupported != null && devices == null;
}

/// The facts of the ggml-vulkan [device] among [facts], or `null` when they
/// cannot be told.
///
/// The two lists are not matched by position: ggml-vulkan and the facts can
/// disagree on which devices exist, as for a device below Vulkan 1.2 beside
/// other GPUs. What both report of a device is its Vulkan device name, which
/// is ggml's description, and whether it is an integrated GPU. Facts of that
/// name and kind are the device's only when all of them agree on whether
/// they meet Vulkan 1.2, as identical GPUs on one driver do; otherwise, and
/// without any, the device is unknown.
VulkanDeviceFacts? vulkanFactsOf(
  GgmlDeviceEntry device,
  List<VulkanDeviceFacts> facts,
) {
  if (!device.isVulkan || device.description.isEmpty) return null;
  final integrated = device.type == _typeIgpu;
  final named = [
    for (final fact in facts)
      if (fact.name == device.description && fact.isIntegratedGpu == integrated)
        fact,
  ];
  if (named.isEmpty ||
      named.any((fact) => fact.meetsVulkan12 != named.first.meetsVulkan12)) {
    return null;
  }
  return named.first;
}

/// Decides what a model load does about Vulkan devices below Vulkan 1.2 or,
/// on [isAndroid], the known unsafe Adreno 750 driver.
///
/// [usesGpu] is false for a load that offloads nothing, which never starts a
/// device. [backendRegistry] is the ggml registry of an explicit GPU backend,
/// whose devices the load lists (`llama_model_params.devices`) when it has
/// any, or `null` when llama.cpp selects among every registered device.
///
/// Vulkan API floors apply to selected model devices. On Android the driver
/// guard also covers registered devices that auxiliary GPU selectors could
/// choose independently. [registered] is read only for a load that [usesGpu].
/// A device whose facts cannot be matched is taken as usable.
VulkanLoadDecision resolveVulkanLoadDecision({
  required bool usesGpu,
  required String? backendRegistry,
  required int splitMode,
  required int mainGpu,
  required List<GgmlDeviceEntry> Function() registered,
  required VulkanDeviceProbe Function() probe,
  bool isAndroid = false,
}) {
  if (!usesGpu) return VulkanLoadDecision.unchanged;
  final devices = registered();
  final registry = backendRegistry?.toLowerCase();
  final ofBackend = [
    for (final device in devices)
      if (device.registry.toLowerCase() == registry) device,
  ];
  final selected = selectModelDevices(
    registered: devices,
    listed: ofBackend.isEmpty ? null : ofBackend,
    splitMode: splitMode,
    mainGpu: mainGpu,
  );

  final inspected = isAndroid ? devices : selected;
  if (!inspected.any((device) => device.isVulkan)) {
    return VulkanLoadDecision.unchanged;
  }
  final facts = probe().devices;
  if (facts == null) return VulkanLoadDecision.unchanged;

  // Projector and decision-head GPU selection is independent of the model's
  // list. Refuse GPU work if any registered Android device has this driver.
  if (isAndroid) {
    for (final device in devices.where((device) => device.isVulkan)) {
      if (facts.any(
        (fact) =>
            fact.name == device.description &&
            fact.isIntegratedGpu == (device.type == _typeIgpu) &&
            fact.hasAdreno750DriverDefect,
      )) {
        return VulkanLoadDecision._(
          unsupported:
              '"${device.description}" (${device.name}) on Android driver '
              '2150604839 has known llama.cpp Vulkan shader-compiler crashes '
              'and incorrect quantized results. GPU work is excluded until '
              'a native workaround and the model are qualified',
        );
      }
    }
  }
  String? unsupported;
  final usable = <GgmlDeviceEntry>[];
  for (final device in selected) {
    final fact = vulkanFactsOf(device, facts);
    if (fact == null || fact.meetsVulkan12) {
      usable.add(device);
      continue;
    }
    String version(int value) => VulkanDeviceFacts.formatApiVersion(value);
    unsupported ??=
        "llama.cpp's Vulkan backend needs Vulkan 1.2 or later from both "
        'the Vulkan loader and the GPU driver, and "${fact.name}" '
        '(${device.name}) reports driver API ${version(fact.apiVersion)} '
        'with loader API ${version(fact.instanceApiVersion)}';
  }
  if (unsupported == null) return VulkanLoadDecision.unchanged;
  return VulkanLoadDecision._(
    unsupported: unsupported,
    devices: usable.isEmpty ? null : usable,
  );
}
