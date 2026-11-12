import 'dart:io';

import 'mobile_app_cache_directory.dart';

/// Whether this process runs in an iOS simulator.
///
/// CoreSimulator sets `SIMULATOR_UDID` in every process of a simulator, and a
/// process on a device has no such variable. `Abi.current()` cannot tell the
/// two apart: it is `Abi.iosArm64` on a device and on the arm64 simulator.
///
/// Tests replace [isIOS] (default `Platform.isIOS`) and [readVariable]
/// (default [environmentVariable], which reads libc on iOS).
bool isIosSimulatorProcess({
  bool? isIOS,
  String? Function(String name) readVariable = environmentVariable,
}) {
  if (!(isIOS ?? Platform.isIOS)) {
    return false;
  }
  return readVariable('SIMULATOR_UDID')?.isNotEmpty ?? false;
}
