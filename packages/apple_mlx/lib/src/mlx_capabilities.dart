/// Runtime capabilities of the native packages wrapped by `apple_mlx`.
///
/// Keep these flags conservative. A capability should only become available
/// after the native dependency performs real inference on a supported device.
abstract final class AppleMlxCapabilities {
  /// `lib_mlx` 0.1.1 ships a mock native model core, not MLX inference.
  ///
  /// LocalMind uses this flag to keep the MLX download and chat path out of the
  /// production catalog until the native backend is replaced by a real one.
  static const bool nativeLlmInferenceAvailable = false;

  static const String nativeLlmUnavailableReason =
      'Apple MLX text generation is unavailable because the current native '
      'lib_mlx backend is a mock scaffold and does not run model inference.';
}
