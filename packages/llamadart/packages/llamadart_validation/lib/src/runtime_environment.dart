import 'runtime_environment_stub.dart'
    if (dart.library.io) 'runtime_environment_io.dart';

/// Validation must use the pinned runtime, without ambient library overrides.
/// Values are deliberately omitted from diagnostics because paths can be secret.
/// Dart tooling sets library search paths for JIT native assets; only portable
/// qualification forbids those paths. JIT results cannot qualify a desktop row.
void requireValidationRuntimeEnvironment({
  Map<String, String>? environment,
  bool portable = false,
}) {
  final values = environment ?? runtimeEnvironment();
  const overrides = {
    'LLAMADART_LITERT_LM_LIB_DIR',
    'LLAMADART_NATIVE_LIB_DIR',
    'LLAMADART_BACKEND_MODULE_DIR',
    'LLAMADART_ALLOW_LEGACY_LOCAL_BUNDLES',
    'GGML_BACKEND_PATH',
    'WEBGPU_BRIDGE_ASSETS_TAG',
    'WEBGPU_BRIDGE_ASSETS_REPO',
    'LD_PRELOAD',
    'DYLD_INSERT_LIBRARIES',
  };
  final active =
      values.keys
          .where(
            (key) =>
                (overrides.contains(key) ||
                    (portable &&
                        (key.startsWith('DYLD_') ||
                            key == 'LD_LIBRARY_PATH'))) &&
                values[key]!.isNotEmpty,
          )
          .toList()
        ..sort();
  if (active.isNotEmpty) {
    throw StateError(
      'Validation requires pinned runtime assets; unset ${active.join(', ')}',
    );
  }
}
