import '../exceptions.dart';
import 'image_editing_request.dart';
import 'image_generation_driver.dart';
import 'image_generation_request.dart';

/// A control image and how strongly a loaded ControlNet follows it.
///
/// [image] is the finished control map the ControlNet was trained on, such as
/// Canny edges, a depth map or a pose skeleton. No preprocessor runs: the
/// runtime receives these pixels unchanged, and producing the map is the
/// caller's job. Its dimensions set the output size.
final class ImageControlNetCondition {
  /// Largest accepted [strength].
  static const double maxStrength = 2;

  /// [strength] when unset: stable-diffusion.cpp's default.
  static const double defaultStrength = 0.9;

  /// Decoded RGB control map. A mask input cannot be used here.
  final ImageEditingPixels image;

  /// Scale of the ControlNet residuals added to the UNet, from 0 to
  /// [maxStrength]. 0 adds nothing; 1 adds them as trained.
  final double strength;

  /// Creates a condition. [image] and [strength] are checked when a request
  /// that carries this condition starts generating.
  const ImageControlNetCondition({
    required this.image,
    this.strength = defaultStrength,
  });
}

/// Text-to-image generation steered by a ControlNet loaded with the model.
///
/// Load the ControlNet as an `ImageModelComponent` next to its base
/// checkpoint; its role is detected as `ImageModelRole.controlNet`. The
/// bounded recipe requires the pinned stable_diffusion v0.3.0-1 runtime on
/// macOS CPU, an SD 1.x checkpoint with its embedded full VAE, and an SD 1.x
/// ControlNet in the original (lllyasviel) tensor layout whose header shows
/// a 768-wide text context and a three-channel hint, with no other
/// components and `flashAttention: false` and `vaeDirectConvolution: false`.
/// Other families, Diffusers or `.pth` ControlNets, devices and platforms
/// throw [LlamaUnsupportedException] when the model loads.
///
/// The output uses the control image's dimensions. The image is copied on
/// creation and stays owned through cancellation until the native call has
/// ended. The engine's ordinary requests generate without the ControlNet.
final class ControlNetImageGenerationRequest extends ImageGenerationRequest {
  /// The control image and its strength.
  final ImageControlNetCondition control;

  /// Creates a request. Image and strength checks precede inference.
  ControlNetImageGenerationRequest({
    required super.prompt,
    required this.control,
    super.negativePrompt,
    super.steps,
    super.guidanceScale,
    super.seed,
    super.count,
    super.sampler,
    super.scheduler,
  }) : super(width: control.image.width, height: control.image.height);
}

/// Validates ControlNet data and the bounded loaded-model recipe.
void validateImageControlNetRecipe(
  ImageGenerationSessionRequest request,
  ImageGenerationSessionConfig config,
  String modelVersion,
) {
  final image = request.controlImage;
  final strength = request.controlStrength;
  if (image == null) {
    if (strength != null) {
      throw LlamaImageGenerationException(
        'A ControlNet strength requires a control image.',
      );
    }
    return;
  }
  if (image.channels != 3 ||
      image.width != request.width ||
      image.height != request.height ||
      strength == null ||
      !strength.isFinite ||
      strength < 0 ||
      strength > ImageControlNetCondition.maxStrength) {
    throw LlamaImageGenerationException(
      'ControlNet conditioning requires an RGB control image aligned with the '
      'output and finite strength from 0 to '
      '${ImageControlNetCondition.maxStrength}.',
    );
  }
  if (!config.controlNetRecipeVerified ||
      modelVersion != 'SD 1.x' ||
      request.initialImage != null ||
      request.vaeTiling != null ||
      request.circularX ||
      request.circularY ||
      config.flashAttention ||
      config.vaeDirectConvolution) {
    throw LlamaUnsupportedException(
      'ControlNet conditioning requires stable_diffusion v0.3.0-1 on macOS CPU '
      'with an SD 1.x checkpoint and its embedded full VAE plus a '
      'header-verified SD 1.x ControlNet, without other components, image '
      'editing, VAE tiling, circular axes, flash attention or direct VAE '
      'convolution. Other families, ControlNet layouts, devices and '
      'platforms are not qualified.',
    );
  }
}
