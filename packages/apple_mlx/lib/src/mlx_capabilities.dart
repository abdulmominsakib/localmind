/// Runtime capabilities of the native packages wrapped by `apple_mlx`.
///
/// Keep these flags conservative. A capability should only become available
/// after the native dependency performs real inference on a supported device.
abstract final class AppleMlxCapabilities {
  /// Whether native MLX LLM inference is available on supported Apple platforms (iOS, iPadOS, macOS).
  static const bool nativeLlmInferenceAvailable = true;

  static const String nativeLlmUnavailableReason =
      'Apple MLX text generation is only supported on Apple platforms (iOS, iPadOS, macOS).';
}
