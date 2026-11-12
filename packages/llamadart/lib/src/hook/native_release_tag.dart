/// The `llamadart-native` release tag grammar shared by the build hook and the
/// release-doc/WebGPU verifiers.
///
/// `tool/native/sync_native_release_pins.py`,
/// `tool/native/sync_native_headers_and_bindings.sh` and this library compile
/// the same grammar; `tool/native/fixtures/native_release_tag_grammar.json`
/// pins it for all three so drift fails CI.
library;

/// Matches any supported `llamadart-native` release tag: stable
/// `vMAJOR.MINOR.PATCH`, stable wrapper rebuild `vMAJOR.MINOR.PATCH-N`,
/// historical/nightly `bNNNN`, nightly wrapper rebuild `bNNNN-N`, or
/// consumption-only legacy wrapper artifact `bNNNN-llamadart.N`.
final RegExp nativeReleaseTagPattern = RegExp(
  r'^(?:v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[1-9][0-9]*)?|'
  r'b(?:0|[1-9][0-9]*)(?:-[1-9][0-9]*|-llamadart\.[1-9][0-9]*)?)$',
);

/// Whether [tag] is a valid `llamadart-native` release tag.
///
/// Matches exactly: whitespace, path separators and shell metacharacters are
/// rejected rather than normalized, so an accepted tag is safe to interpolate
/// into a download URL or a shell command unchanged.
bool isValidNativeReleaseTag(String tag) =>
    nativeReleaseTagPattern.hasMatch(tag);

/// Normalizes a native release tag (e.g. `v0.2.0-1` or `b10514-1`) to its
/// upstream llama.cpp release tag (e.g. `v0.2.0` or `b10514`).
///
/// Returns `null` if [tag] is malformed or unsupported.
String? normalizeNativeLlamaCppTag(String tag) {
  if (!isValidNativeReleaseTag(tag)) return null;
  // Only the wrapper forms carry a `-`, and it always follows the upstream tag.
  final wrapperSuffix = tag.indexOf('-');
  return wrapperSuffix < 0 ? tag : tag.substring(0, wrapperSuffix);
}
