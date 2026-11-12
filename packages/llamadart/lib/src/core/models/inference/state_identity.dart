import '../../exceptions.dart';

/// The runtime and context a saved KV-cache state belongs to, from
/// `LlamaEngine.stateIdentity`.
///
/// llama.cpp checks a state file's magic, session version and KV cache layout
/// (layer count, cache types and sizes, V transposition, cell capacity), but
/// not the runtime build that wrote it or the RoPE settings its keys were
/// computed with. Store this identity with a state file you save, and before
/// loading a file another process saved, check that it [matches] the identity
/// of the engine that loads it.
///
/// It names the runtime build and the context settings that change the saved
/// state. It does not name the model: store a digest of the model file, its
/// adapters and projector with the state yourself. It does not name the device
/// a process selects either, only the backends the runtime was built with.
/// Matching identities do not guarantee a load: flash attention `auto`
/// resolves per device, and llama.cpp then rejects a different V layout with
/// `LlamaStateException`. Handle it by evaluating the prompt again. A
/// restored state matches a fresh evaluation only within numerical
/// tolerance.
final class LlamaStateIdentity {
  /// Creates a state identity, for example from one stored with a state file.
  ///
  /// Throws [LlamaArgumentException] when [runtimeBuild] or
  /// [contextConfigDigest] is empty, or [sessionFormatVersion] or
  /// [contextSize] is not positive.
  LlamaStateIdentity({
    required this.runtimeBuild,
    required this.sessionFormatVersion,
    required this.contextSize,
    required this.contextConfigDigest,
  }) {
    if (runtimeBuild.trim().isEmpty) {
      throw LlamaArgumentException(
        'A state identity needs a non-empty runtime build identity.',
        name: 'runtimeBuild',
        invalidValue: runtimeBuild,
      );
    }
    if (sessionFormatVersion <= 0) {
      throw LlamaArgumentException(
        'A state identity needs a positive session format version.',
        name: 'sessionFormatVersion',
        invalidValue: sessionFormatVersion,
      );
    }
    if (contextSize <= 0) {
      throw LlamaArgumentException(
        'A state identity needs a positive context size.',
        name: 'contextSize',
        invalidValue: contextSize,
      );
    }
    if (contextConfigDigest.trim().isEmpty) {
      throw LlamaArgumentException(
        'A state identity needs a non-empty context configuration digest.',
        name: 'contextConfigDigest',
        invalidValue: contextConfigDigest,
      );
    }
  }

  /// The build identity of the native runtime, which names the sources,
  /// patches, compiler, target and ggml backends it was built from. It holds
  /// no path, host name, user or time.
  final String runtimeBuild;

  /// The llama.cpp session file format version (`LLAMA_SESSION_VERSION`).
  final int sessionFormatVersion;

  /// The allocated context size, in tokens.
  final int contextSize;

  /// A digest of the context settings that change the saved state: the K and
  /// V cache types, the requested flash-attention mode, the sequence count,
  /// unified KV, full-size SWA cache, and the RoPE frequency base and scale.
  /// Batch sizes, threads and GPU offload are not part of it.
  final String contextConfigDigest;

  /// Whether a state saved under this identity belongs to an engine that
  /// reports [other]: every field is equal.
  bool matches(LlamaStateIdentity other) =>
      runtimeBuild == other.runtimeBuild &&
      sessionFormatVersion == other.sessionFormatVersion &&
      contextSize == other.contextSize &&
      contextConfigDigest == other.contextConfigDigest;

  @override
  bool operator ==(Object other) =>
      other is LlamaStateIdentity && matches(other);

  @override
  int get hashCode => Object.hash(
    runtimeBuild,
    sessionFormatVersion,
    contextSize,
    contextConfigDigest,
  );

  @override
  String toString() =>
      'LlamaStateIdentity(runtimeBuild: $runtimeBuild, '
      'sessionFormatVersion: $sessionFormatVersion, '
      'contextSize: $contextSize, contextConfigDigest: $contextConfigDigest)';
}
