import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../core/exceptions.dart';
import '../../hook/native_release_pins.dart';

typedef _GetApiVersionNative =
    Int Function(Pointer<Int>, Pointer<Int>, Pointer<Int>);
typedef _GetApiVersionDart =
    int Function(Pointer<Int>, Pointer<Int>, Pointer<Int>);

/// Reads the only admitted versioned ABI without calling any engine function.
/// A missing marker means legacy; every malformed or unknown version is refused.
({int major, int minor, int patch})? readLiteRtLmCApiVersion(
  DynamicLibrary library,
) {
  if (!library.providesSymbol('litert_lm_get_api_version')) return null;
  final getVersion = library
      .lookupFunction<_GetApiVersionNative, _GetApiVersionDart>(
        'litert_lm_get_api_version',
      );
  final parts = calloc<Int>(3);
  try {
    parts[0] = parts[1] = parts[2] = -1;
    final status = getVersion(parts, parts + 1, parts + 2);
    if (status != 0 || parts[0] != 1 || parts[1] != 0 || parts[2] < 0) {
      throw LlamaUnsupportedException(
        'LiteRT-LM rejects C API ${parts[0]}.${parts[1]}.${parts[2]} (version probe status $status). '
        'Use the packaged litert-lm-native $liteRtLmReleaseTag runtime with supported C API 1.0.x. '
        'See https://github.com/leehack/llamadart/issues/1677 for the admitted ABI contract. '
        'No legacy engine call was attempted.',
      );
    }
    return (major: parts[0], minor: parts[1], patch: parts[2]);
  } finally {
    calloc.free(parts);
  }
}

/// Reads litert-lm-native's `litert_lm_native_in_process_litert_abi_version`
/// marker, or returns null when the runtime predates the export.
///
/// The caller interprets the value: 1 means LiteRT is compiled into the
/// runtime with no separate `libLiteRt` import, 0 or a missing export means
/// that is not established, and later values carry guarantees this package
/// does not know. It never establishes GPU qualification.
int? readLiteRtLmInProcessLiteRtAbiVersion(DynamicLibrary library) {
  const symbol = 'litert_lm_native_in_process_litert_abi_version';
  if (!library.providesSymbol(symbol)) return null;
  return library.lookupFunction<Int32 Function(), int Function()>(symbol)();
}

/// Refuses versioned C APIs before using the pre-1.0 LiteRT-LM bindings.
///
/// LiteRT-LM 0.19 introduces `litert_lm_get_api_version` alongside status-return
/// and output-parameter signatures. Reusing the legacy function names does not
/// make their calling conventions compatible. Compatible legacy runtime
/// overrides have no version export and continue through capability checks.
/// The packaged 0.19 runtime requires the default ABI-selecting client.
void requireLiteRtLmLegacyCApi(DynamicLibrary library) {
  if (!library.providesSymbol('litert_lm_get_api_version')) {
    return;
  }
  final getVersion = library
      .lookupFunction<_GetApiVersionNative, _GetApiVersionDart>(
        'litert_lm_get_api_version',
      );
  final parts = calloc<Int>(3);
  try {
    final status = getVersion(parts, parts + 1, parts + 2);
    final version = status == 0
        ? '${parts[0]}.${parts[1]}.${parts[2]}'
        : 'unknown (version probe status $status)';
    throw LlamaUnsupportedException(
      'Native LiteRT-LM C API $version is incompatible with the pre-1.0 bindings. '
      'Use the default LiteRtLmRuntimeClient or LiteRtLmService to select the '
      'admitted C API 1.0.x route for the packaged litert-lm-native $liteRtLmReleaseTag '
      'runtime, or select a compatible legacy runtime override for these bindings. '
      'See https://github.com/leehack/llamadart/issues/1677 for the admitted ABI contract. '
      'No legacy engine call was attempted.',
    );
  } finally {
    calloc.free(parts);
  }
}
