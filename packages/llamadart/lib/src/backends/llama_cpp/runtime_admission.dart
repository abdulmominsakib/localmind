import 'dart:ffi';

import '../../core/exceptions.dart';
import 'build_identity.dart';

/// The only llama.cpp commit whose struct layouts the generated bindings
/// match. Every `llamadart-native` release built from it is admitted and no
/// other runtime is: a mismatched runtime reads and writes by-value structs at
/// the wrong offsets, so there is deliberately no override.
const String admittedLlamaCppCommit =
    'b1b770d90d94cad9e9ea5b993bdbc383a522fb28';

/// The llama.cpp release [admittedLlamaCppCommit] is tagged as.
const String admittedLlamaCppRelease = 'v1.0.0';

const String _identityPrefix = 'llamadart-native-build/1;';
const String _commitKey = ';llama.cpp=';

/// Whether [identity], as reported by `llama_dart_build_identity`, names a
/// runtime built from [admittedLlamaCppCommit].
bool admitsRuntimeBuildIdentity(String? identity) {
  if (identity == null || !identity.startsWith(_identityPrefix)) return false;
  final start = identity.indexOf(_commitKey);
  if (start < 0 || identity.indexOf(_commitKey, start + 1) >= 0) return false;
  final valueStart = start + _commitKey.length;
  final end = identity.indexOf(';', valueStart);
  return end >= 0 &&
      identity.substring(valueStart, end) == admittedLlamaCppCommit;
}

/// The refusal for a runtime that [admitsRuntimeBuildIdentity] rejects.
LlamaUnsupportedException runtimeNotAdmitted({
  required String capability,
  required String? identity,
}) {
  final reported = identity == null
      ? 'no build identity (it predates llama_dart_build_identity)'
      : identity.isEmpty
      ? 'an empty build identity'
      : 'the build identity "$identity"';
  return LlamaUnsupportedException(
    '$capability needs a llamadart-native runtime built from llama.cpp '
    '$admittedLlamaCppRelease ($admittedLlamaCppCommit), and the loaded '
    'runtime reports $reported. Use the llamadart-native '
    '$admittedLlamaCppRelease release and remove any native release override.',
  );
}

/// Refuses [library] unless it reports an admitted build identity.
///
/// A library without the export is refused too, unless [identityOptional]
/// marks it as a sibling of a runtime that was already admitted.
void requireAdmittedLibrary(
  DynamicLibrary library, {
  required String capability,
  bool identityOptional = false,
}) {
  final identity = readLibraryBuildIdentity(library);
  if (identity == null && identityOptional) return;
  if (!admitsRuntimeBuildIdentity(identity)) {
    throw runtimeNotAdmitted(capability: capability, identity: identity);
  }
}

/// Refuses the runtime the native assets resolve to unless it reports an
/// admitted build identity.
void requireAdmittedPrimaryRuntime({
  required bool isWindows,
  required String capability,
}) {
  final identity = readNativeBuildIdentity(isWindows: isWindows);
  if (!admitsRuntimeBuildIdentity(identity)) {
    throw runtimeNotAdmitted(capability: capability, identity: identity);
  }
}
