import 'dart:ffi';
import 'dart:io';

import 'native_diagnostics.dart';

/// The only native operations of the isolated diagnostic child.
abstract interface class NativeDiagnosticLibrary {
  /// Resolves a symbol without invoking it.
  bool hasSymbol(String name);

  /// Calls one fixed no-argument, compile-time ABI marker.
  int marker(String name);
}

final class _DynamicDiagnosticLibrary implements NativeDiagnosticLibrary {
  _DynamicDiagnosticLibrary(String file) : library = DynamicLibrary.open(file);
  final DynamicLibrary library;
  @override
  bool hasSymbol(String name) => library.providesSymbol(name);
  @override
  int marker(String name) => name == 'llama_dart_tts_api_version'
      ? library.lookupFunction<Uint32 Function(), int Function()>(name)()
      : library.lookupFunction<Int32 Function(), int Function()>(name)();
}

/// Classifies loader failures without retaining any loader-controlled string.
String nativeDiagnosticLoaderCode(Object error) {
  final value = error.toString().toLowerCase();
  if (RegExp(
    r'incompatible architecture|wrong elf class|invalid elf header|not a valid win32 application|error code:? 193\b',
  ).hasMatch(value)) {
    return 'BINARY_INCOMPATIBLE';
  }
  if (RegExp(
    r'library not loaded|cannot open shared object|error code:? 126\b',
  ).hasMatch(value)) {
    return 'DEPENDENCY_UNAVAILABLE';
  }
  return 'LOADER_FAILED';
}

/// Checks explicit declared files and fixed symbols, without engine creation.
Map<String, Object> probeNativeDiagnostic(
  String runtime,
  NativeDiagnosticTarget target, {
  NativeDiagnosticLibrary Function(String)? open,
  bool Function(String)? exists,
  void Function(String)? onPhase,
}) {
  var phase = 'open';
  Map<String, Object> result(String code, [String marker = 'not_checked']) =>
      nativeDiagnosticObservation(runtime, code, phase: phase, marker: marker);
  void at(String value) {
    phase = value;
    try {
      onPhase?.call(value);
    } catch (_) {
      throw const _PhaseWriteFailure();
    }
  }

  final handles = <NativeDiagnosticLibrary>[];
  try {
    at('open');
    for (final file in {...target.companions, target.primary, target.wrapper}) {
      if (!(exists?.call(file) ?? File(file).existsSync())) {
        return result('ARTIFACT_MISSING');
      }
    }
    final load = open ?? _DynamicDiagnosticLibrary.new;
    for (final companion in target.companions) {
      handles.add(load(companion));
    }
    final primary = load(target.primary);
    handles.add(primary);
    final wrapper = target.wrapper == target.primary
        ? primary
        : load(target.wrapper);
    handles.add(wrapper);
    at('symbols');
    final coreSymbols = switch (runtime) {
      'llama_cpp' => [
        'llama_model_default_params',
        'llama_model_load_from_file',
        'llama_decode',
      ],
      'litert_lm' => [
        'litert_lm_engine_settings_create',
        'litert_lm_engine_create',
        'litert_lm_engine_delete',
        'stream_proxy_create',
        'stream_proxy_free_string',
        'stream_proxy_delete',
        'stream_proxy_callback_abi_version',
        'stream_proxy_finish_reason_abi_version',
      ],
      'stable_diffusion' => [
        'sd_version',
        'sd_dart_progress_enable',
        'sd_dart_progress_read',
        'sd_dart_new_sd_ctx',
        'sd_dart_generate_image',
        'sd_dart_cancel_generation',
        'sd_dart_exit_free',
      ],
      _ => throw const FormatException('Invalid runtime'),
    };
    if (!coreSymbols.every(primary.hasSymbol)) return result('SYMBOL_MISSING');
    if (runtime == 'llama_cpp' &&
        ![
          'llama_dart_model_load_from_file',
          'llama_dart_init_from_model',
          'llama_dart_sampler_sample',
          'llama_dart_tts_api_version',
        ].every(wrapper.hasSymbol)) {
      return result('SYMBOL_MISSING');
    }
    at('abi');
    final marker = switch (runtime) {
      'llama_cpp' =>
        wrapper.marker('llama_dart_tts_api_version') == 1
            ? 'tts_v1'
            : 'unknown',
      'litert_lm' =>
        primary.marker('stream_proxy_callback_abi_version') == 2 &&
                primary.marker('stream_proxy_finish_reason_abi_version') == 1
            ? 'callback_v2_finish_v1'
            : 'unknown',
      _ => 'not_available',
    };
    if (marker == 'unknown') return result('ABI_UNKNOWN', marker);
    at('complete');
    return result('SURFACE_OBSERVED', marker);
  } catch (error) {
    if (error is _PhaseWriteFailure) rethrow;
    return result(
      phase == 'open' ? nativeDiagnosticLoaderCode(error) : 'LOADER_FAILED',
    );
  } finally {
    // Keep all dependency handles alive through the last symbol/marker read.
    _keepAlive(handles);
  }
}

void _keepAlive(Object value) {}

final class _PhaseWriteFailure implements Exception {
  const _PhaseWriteFailure();
}
