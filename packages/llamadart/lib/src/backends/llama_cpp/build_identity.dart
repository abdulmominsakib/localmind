import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'bindings.dart';

/// The oldest `llamadart-native` release that exports
/// `llama_dart_build_identity`.
const String minimumBuildIdentityNativeRelease = 'v0.7.0-3';

/// The build identity the loaded libllamadart reports, or `null` when it does
/// not export `llama_dart_build_identity`.
///
/// The string is a constant of the library, and the call touches no llama.cpp
/// object, so it needs no exit-teardown guard. On Windows the `llama_dart_`
/// functions are in llamadart.dll, not in the llama.dll the bindings default
/// to. [call] replaces the native function and, like a runtime without the
/// symbol, throws [ArgumentError] to report it missing.
String? readNativeBuildIdentity({
  required bool isWindows,
  Pointer<Char> Function()? call,
}) {
  final Pointer<Char> identity;
  try {
    identity =
        (call ??
        (isWindows ? _wrapperBuildIdentity : llama_dart_build_identity))();
  } on ArgumentError {
    return null;
  }
  return identity == nullptr ? '' : identity.cast<Utf8>().toDartString();
}

@Native<Pointer<Char> Function()>(
  assetId: 'package:llamadart/llamadart_wrapper',
  symbol: 'llama_dart_build_identity',
)
external Pointer<Char> _wrapperBuildIdentity();
