import 'dart:io';

import 'litert_lm/litert_lm_gpu_adapter.dart';

/// Returns why Linux cannot create a Vulkan instance or enumerate devices.
///
/// Returns `null` on other hosts, where this Linux-specific preflight imposes
/// no restriction. On Linux, `null` means only that the system loader lists a
/// device; it does not qualify a runtime's Vulkan version, extensions or driver.
/// CPU-only native builds do not need this preflight. The probe loads system
/// drivers, so call it only before starting a Vulkan runtime, off the UI isolate.
String? probeLinuxVulkanUnavailableReason() => linuxVulkanUnavailableReason(
  isLinux: Platform.isLinux,
  probe: probeLiteRtLmVulkanAdapters,
);

/// Evaluates the Linux loader probe; arguments allow model-free host controls.
String? linuxVulkanUnavailableReason({
  required bool isLinux,
  required LiteRtLmVulkanAdapters Function() probe,
}) {
  if (!isLinux) return null;
  final adapters = probe();
  final reason = adapters.unavailableReason;
  if (reason != null) {
    return 'The Linux Vulkan runtime is unavailable: $reason. '
        'Install a compatible Vulkan driver and ICD, or use a CPU-only build.';
  }
  if (adapters.devices!.isEmpty) {
    return 'The Linux Vulkan loader reported no devices. '
        'Install a compatible Vulkan driver and ICD, or use a CPU-only build.';
  }
  return null;
}
