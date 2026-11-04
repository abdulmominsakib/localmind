import 'dart:io';

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
  if (Platform.isIOS || Platform.isMacOS) {
    return const <String>[liteRtLmCpuBackend, liteRtLmGpuBackend];
  }
  return const <String>[liteRtLmCpuBackend];
}

/// Returns the native LiteRT-LM backend used for automatic selection.
String liteRtLmDefaultNativeBackendForCurrentPlatform() {
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    return liteRtLmGpuBackend;
  }
  return liteRtLmCpuBackend;
}

/// Returns whether the current native LiteRT-LM target exposes a GPU backend.
bool liteRtLmNativeGpuSupportedOnCurrentPlatform() {
  return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
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
