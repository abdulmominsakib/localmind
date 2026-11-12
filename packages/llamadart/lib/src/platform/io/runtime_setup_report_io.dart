import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:code_assets/code_assets.dart';

import '../../core/diagnostics/runtime_setup_report.dart';
import '../../core/exceptions.dart';
import '../../hook/native_bundle_config.dart';
import '../../hook/native_release_pins.dart';

/// Collects host metadata without touching a native runtime or subprocess.
Future<LlamaRuntimeSetupReport> collectRuntimeSetupReport() async {
  requireDesktopSetupHost(Platform.operatingSystem);
  Uri? library;
  try {
    library = await Isolate.resolvePackageUri(
      Uri.parse('package:llamadart/llamadart.dart'),
    );
  } on Exception {
    // AOT executables may not retain source-package metadata.
  }
  return buildDesktopSetupReport(
    os: Platform.operatingSystem,
    osVersion: Platform.operatingSystemVersion,
    abi: Abi.current().toString(),
    dartVersion: Platform.version,
    packageVersion: await readSetupPackageVersion(library),
    environment: Platform.environment,
  );
}

/// Mobile IO is intentionally outside this first desktop report contract.
void requireDesktopSetupHost(String os) {
  if (!const {'macos', 'linux', 'windows'}.contains(os)) {
    throw LlamaUnsupportedException(
      'Runtime setup reports require a macOS, Linux or Windows Dart IO process. '
      'Mobile and other hosts require separate app/device validation.',
    );
  }
}

/// Pure host-to-publication policy; no native service imports are needed.
LlamaRuntimeSetupReport buildDesktopSetupReport({
  required String os,
  required String osVersion,
  required String abi,
  required String dartVersion,
  required String packageVersion,
  required Map<String, String> environment,
}) {
  final targetOs = switch (os) {
    'macos' => OS.macOS,
    'linux' => OS.linux,
    'windows' => OS.windows,
    _ => null,
  };
  // Match the complete ABI, including OS. Unknown and mismatched future ABIs
  // must not inherit a host policy by a string suffix alone.
  final architecture = switch (abi) {
    'macos_arm64' when os == 'macos' => Architecture.arm64,
    'macos_x64' when os == 'macos' => Architecture.x64,
    'linux_arm64' when os == 'linux' => Architecture.arm64,
    'linux_x64' when os == 'linux' => Architecture.x64,
    'linux_arm' when os == 'linux' => Architecture.arm,
    'linux_ia32' when os == 'linux' => Architecture.ia32,
    'windows_arm64' when os == 'windows' => Architecture.arm64,
    'windows_x64' when os == 'windows' => Architecture.x64,
    'windows_ia32' when os == 'windows' => Architecture.ia32,
    _ => null,
  };
  final known = targetOs != null && architecture != null;
  final spec = known
      ? resolveNativeBundleSpec(
          os: targetOs,
          arch: architecture,
          isIosSimulator: false,
        )
      : null;
  final sdBundle = spec == null
      ? null
      : stableDiffusionBundleForNativeBundle(
          spec: spec,
          rawBackendConfig: null,
        );
  String publication(bool published) => !known
      ? 'unknown'
      : published
      ? 'published'
      : 'unavailable';
  final dartToken = dartVersion.length <= 1024
      ? dartVersion.split(' ').first
      : 'unknown';
  return buildRuntimeSetupReport(
    os: os,
    osVersion: osVersion,
    architecture: architecture?.name ?? 'unknown',
    dartVersion: dartToken,
    packageVersion: packageVersion,
    policies: [
      (
        name: 'llama_cpp',
        tag: llamaCppTag,
        publication: publication(spec != null),
      ),
      (
        name: 'litert_lm',
        tag: liteRtLmReleaseTag,
        publication: publication(
          liteRtLmBundleSpecs.any((item) => item.bundle == spec?.bundle),
        ),
      ),
      (
        name: 'stable_diffusion',
        tag: stableDiffusionReleaseTag,
        publication: publication(
          stableDiffusionBundleSpecs.any((item) => item.bundle == sdBundle),
        ),
      ),
    ],
    environment: environment,
  );
}

/// Reads only bounded local metadata belonging to the resolved package URI.
/// Never falls back to the consuming app's working directory or pubspec.
Future<String> readSetupPackageVersion(Uri? packageLibrary) async {
  if (packageLibrary == null || packageLibrary.scheme != 'file') {
    return 'unknown';
  }
  RandomAccessFile? handle;
  try {
    handle = await File.fromUri(
      packageLibrary.resolve('../pubspec.yaml'),
    ).open();
    const limit = 64 * 1024;
    final bytes = await handle.read(limit + 1);
    if (bytes.length > limit) return 'unknown';
    return parseSetupPackageVersion(utf8.decode(bytes));
  } on Exception {
    return 'unknown';
  } finally {
    try {
      await handle?.close();
    } on Exception {
      // Source metadata is optional, including close failures.
    }
  }
}

/// Accepts only canonical top-level package identity/version scalars.
String parseSetupPackageVersion(String contents) {
  if (contents.length > 64 * 1024) return 'unknown';
  final names = RegExp(
    r'^name: *([^\r\n]*)\r?$',
    multiLine: true,
  ).allMatches(contents).toList();
  final versions = RegExp(
    r'^version: *([^\r\n]*)\r?$',
    multiLine: true,
  ).allMatches(contents).toList();
  if (names.length != 1 ||
      names.single.group(1) != 'llamadart' ||
      versions.length != 1) {
    return 'unknown';
  }
  return normalizeSetupVersion(versions.single.group(1)!);
}
