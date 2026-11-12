import 'dart:ffi';
import 'dart:io';

import '../../core/exceptions.dart';
import '../../core/models/config/compute_device.dart';
import 'litert_lm_runtime.dart';

/// CPU backend selector accepted by the native LiteRT-LM runtime.
const String liteRtLmCpuBackend = 'cpu';

/// GPU backend selector accepted by the native LiteRT-LM runtime.
const String liteRtLmGpuBackend = 'gpu';

/// Android NPU backend selector accepted by the native LiteRT-LM runtime.
const String liteRtLmNpuBackend = 'npu';

/// Returns the LiteRT-LM native backend names available on this platform.
List<String> liteRtLmAvailableNativeBackendsForCurrentPlatform() {
  if (Platform.isAndroid) {
    return const <String>[
      liteRtLmCpuBackend,
      liteRtLmGpuBackend,
      liteRtLmNpuBackend,
    ];
  }
  if (liteRtLmNativeGpuSupportedOnCurrentPlatform()) {
    return const <String>[liteRtLmCpuBackend, liteRtLmGpuBackend];
  }
  return const <String>[liteRtLmCpuBackend];
}

/// Returns the native LiteRT-LM backend used for automatic selection.
///
/// Linux and Windows default to CPU; GPU execution there requires explicit
/// selection. macOS x86_64 reports CPU, but LiteRT-LM has no runtime there.
String liteRtLmDefaultNativeBackendForCurrentPlatform() {
  if (Platform.isAndroid ||
      Platform.isIOS ||
      liteRtLmGateAbi() == Abi.macosArm64) {
    return liteRtLmGpuBackend;
  }
  return liteRtLmCpuBackend;
}

/// Returns whether the current native LiteRT-LM target exposes a GPU backend.
bool liteRtLmNativeGpuSupportedOnCurrentPlatform() {
  final abi = liteRtLmGateAbi();
  return Platform.isAndroid ||
      Platform.isIOS ||
      abi == Abi.macosArm64 ||
      liteRtLmDesktopGpuSupportedForAbi(abi);
}

/// Throws a [LlamaUnsupportedException] when the current target cannot run
/// the native LiteRT-LM [backend] and the request must fail with a typed
/// error instead of an unavailable-backend [ArgumentError].
///
/// litert-lm-native publishes arm64-only macOS runtimes
/// ([leehack/litert-lm-native#72](https://github.com/leehack/litert-lm-native/issues/72)),
/// so macOS x86_64, including an Apple-silicon app under Rosetta, has no
/// LiteRT-LM runtime at all.
void liteRtLmEnsureNativeBackendSupported(String backend) {
  if (backend != liteRtLmGpuBackend || liteRtLmGateAbi() != Abi.macosX64) {
    return;
  }
  throw LlamaUnsupportedException(
    'LiteRT-LM GPU is not available on macOS x86_64 because LiteRT-LM is not '
    'available there; litert-lm-native publishes arm64-only macOS runtimes '
    '(leehack/litert-lm-native#72). Run the app natively on Apple silicon, '
    'not under Rosetta, or use the llama.cpp backend.',
  );
}

/// Throws a [LlamaUnsupportedException] naming the ABI when this target has
/// no native LiteRT-LM backend for an explicit [device].
void liteRtLmEnsureDeviceAvailable(ComputeDevice device) {
  final backend = switch (device) {
    ComputeDevice.auto => null,
    ComputeDevice.cpu => liteRtLmCpuBackend,
    ComputeDevice.gpu => liteRtLmGpuBackend,
    ComputeDevice.npu => liteRtLmNpuBackend,
  };
  if (backend == null) return;
  liteRtLmEnsureNativeBackendSupported(backend);
  final available = liteRtLmAvailableNativeBackendsForCurrentPlatform();
  if (available.contains(backend)) return;
  throw LlamaUnsupportedException(
    'ComputeDevice.${device.name} is not available for LiteRT-LM on '
    '${Platform.operatingSystem} (${liteRtLmGateAbi()}). Available LiteRT-LM '
    'backends: ${available.join(', ')}. Use ComputeDevice.auto or cpu.',
  );
}

/// Returns whether LiteRT-LM native embedding engines are qualified on [abi].
bool liteRtLmNativeEmbeddingsQualifiedForAbi(Abi abi) {
  return abi == Abi.macosArm64 ||
      abi == Abi.iosArm64 ||
      abi == Abi.androidArm64 ||
      abi == Abi.linuxArm64 ||
      abi == Abi.linuxX64 ||
      abi == Abi.windowsX64;
}

/// Throws a [LlamaUnsupportedException] when this target has no qualified
/// LiteRT-LM native embedding engine.
///
/// This runs before any native call, whichever runtime library is loaded, so
/// an unqualified target never reaches native embedding engine creation.
void liteRtLmEnsureNativeEmbeddingsQualified() {
  final abi = liteRtLmGateAbi();
  if (liteRtLmNativeEmbeddingsQualifiedForAbi(abi)) return;
  throw LlamaUnsupportedException(
    'LiteRT-LM native embeddings are unsupported on $abi: they are not '
    'qualified there. This applies to every LiteRT-LM runtime library, '
    'including a custom one. Embeddings run on macOS arm64, iOS arm64, '
    'Android arm64, Linux x64 and arm64, and Windows x64; use the llama.cpp '
    'backend for embeddings on this platform.',
  );
}

/// Returns whether a legacy LiteRT-LM runtime, one without the C API 1
/// version export, may create native embedding engines on [abi].
///
/// Legacy v0.18.x desktop runtimes crash creating embedding engines (#1367);
/// Linux and Windows embeddings are qualified only on C API 1 runtimes that
/// report in-process LiteRT, from litert-lm-native v0.19.1-2.
bool liteRtLmLegacyNativeEmbeddingsQualifiedForAbi(Abi abi) {
  return liteRtLmNativeEmbeddingsQualifiedForAbi(abi) &&
      abi != Abi.linuxArm64 &&
      abi != Abi.linuxX64 &&
      abi != Abi.windowsX64;
}

/// Throws a [LlamaUnsupportedException] when a legacy LiteRT-LM runtime
/// cannot create native embedding engines on this target.
///
/// Runs before any native embedding call on the legacy client.
void liteRtLmEnsureLegacyNativeEmbeddingsQualified() {
  liteRtLmEnsureNativeEmbeddingsQualified();
  final abi = liteRtLmGateAbi();
  if (liteRtLmLegacyNativeEmbeddingsQualifiedForAbi(abi)) return;
  throw LlamaUnsupportedException(
    'LiteRT-LM native embeddings on $abi require a C API 1 runtime from '
    'litert-lm-native v0.19.1-2 or newer. The loaded runtime is a legacy one '
    'without litert_lm_get_api_version, such as a v0.18.x custom runtime, '
    'whose desktop embedding engine crashes (#1367). Use the bundled runtime '
    'or a v0.19.1-2 or newer custom runtime, or the llama.cpp backend.',
  );
}

/// The `litert_lm_native_in_process_litert_abi_version` value that admits
/// Linux and Windows native embeddings.
const int liteRtLmInProcessLiteRtAbiVersion = 1;

/// Throws a [LlamaUnsupportedException] when a C API 1 runtime on Linux or
/// Windows does not report [liteRtLmInProcessLiteRtAbiVersion].
///
/// [abiVersion] is the runtime's in-process LiteRT marker, null when not
/// exported. Custom v0.19.0 and v0.19.1 desktop runtimes report the same C API
/// version but load a separate `libLiteRt` and crash creating embedding
/// engines (#1367); only the marker tells them apart. Unknown values carry
/// guarantees this package does not know, so they are refused too. Apple and
/// Android runtimes are unaffected. Runs before any native embedding call.
void liteRtLmEnsureInProcessLiteRtForNativeEmbeddings(int? abiVersion) {
  final abi = liteRtLmGateAbi();
  if (abi != Abi.linuxArm64 && abi != Abi.linuxX64 && abi != Abi.windowsX64) {
    return;
  }
  if (abiVersion == liteRtLmInProcessLiteRtAbiVersion) return;
  final reported = abiVersion == null
      ? 'does not export litert_lm_native_in_process_litert_abi_version'
      : 'reports litert_lm_native_in_process_litert_abi_version $abiVersion';
  throw LlamaUnsupportedException(
    'LiteRT-LM native embeddings on $abi need LiteRT compiled into the '
    'runtime (in-process LiteRT ABI $liteRtLmInProcessLiteRtAbiVersion), and '
    'the loaded runtime $reported. Custom v0.19.0 and v0.19.1 desktop '
    'runtimes load a separate libLiteRt and crash creating embedding engines '
    '(#1367). Use the bundled runtime or a custom runtime from '
    'litert-lm-native v0.19.1-2 or newer, or the llama.cpp backend.',
  );
}

/// Returns whether a Linux or Windows ABI exposes the explicit GPU backend.
///
/// Backend availability does not establish model or hardware qualification.
/// ARM64 desktop GPU backends remain unavailable.
bool liteRtLmDesktopGpuSupportedForAbi(Abi abi) {
  return abi == Abi.linuxX64 || abi == Abi.windowsX64;
}

/// Normalizes an optional direct LiteRT-LM native backend override.
String? normalizeLiteRtLmNativeBackendOverride(String? backend) {
  if (backend == null) {
    return null;
  }
  final normalized = backend.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  if (normalized == liteRtLmCpuBackend ||
      normalized == liteRtLmGpuBackend ||
      normalized == liteRtLmNpuBackend) {
    return normalized;
  }
  throw ArgumentError(
    'LiteRtLmBackend backend must be cpu, gpu, or npu; got $backend',
  );
}

/// Refuses the C API 1 runtime's macOS floor before any owned library load.
/// Unknown version strings fail closed; custom paths obey the same floor.
void liteRtLmEnsureV1PlatformFloor({
  bool? isMacOS,
  String? operatingSystemVersion,
}) {
  if (!(isMacOS ?? Platform.isMacOS)) return;
  final version = operatingSystemVersion ?? Platform.operatingSystemVersion;
  final match = RegExp(
    r'^(?:Version\s+)?(\d+)\.(\d+)(?:\.\d+)?(?:\s|$)',
  ).firstMatch(version);
  if (match != null && int.parse(match.group(1)!) >= 14) return;
  throw LlamaUnsupportedException(
    'LiteRT-LM C API 1 native runtime requires macOS 14 or newer on Apple silicon, including custom library paths. The OS version is older or could not be verified. Upgrade macOS or use the llama.cpp backend.',
  );
}
