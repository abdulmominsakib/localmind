import 'dart:typed_data';

import '../exceptions.dart';
import 'image_generation_driver.dart';
import 'image_generation_request.dart';

/// Owned, decoded pixels for [ImageEditingRequest].
///
/// Encoded PNG/JPEG files must be decoded by the caller. No image decoding,
/// resizing, alpha compositing or orientation change happens during generation.
/// Dimensions must be multiples of 64 from 64 through 2048, matching the output.
final class ImageEditingPixels {
  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Three interleaved RGB channels, or one binary mask channel.
  final int channels;

  final Uint8List _pixels;

  /// Copies row-major, interleaved 8-bit RGB pixels without an alpha channel.
  ImageEditingPixels.rgb({
    required this.width,
    required this.height,
    required Uint8List pixels,
  }) : channels = 3,
       _pixels = _copy(width, height, 3, pixels);

  /// Copies a one-channel binary mask: 255 edits and 0 preserves the latent.
  ///
  /// Preservation occurs in latent space; black regions are still encoded and
  /// decoded, so their output pixels need not exactly equal the input pixels.
  /// Intermediate mask values are rejected instead of applying an implicit
  /// threshold. The mask must have the same dimensions as the RGB input.
  ImageEditingPixels.mask({
    required this.width,
    required this.height,
    required Uint8List pixels,
  }) : channels = 1,
       _pixels = _copy(width, height, 1, pixels) {
    if (_pixels.any((value) => value != 0 && value != 255)) {
      throw LlamaImageGenerationException(
        'Image-editing masks accept only 0 (preserve) and 255 (edit).',
      );
    }
  }

  /// A copy of the owned pixels. Mutating it cannot change this input.
  Uint8List get pixels => Uint8List.fromList(_pixels);

  static Uint8List _copy(
    int width,
    int height,
    int channels,
    Uint8List pixels,
  ) {
    if (width < 64 ||
        height < 64 ||
        width > ImageGenerationRequest.maxDimension ||
        height > ImageGenerationRequest.maxDimension ||
        width % 64 != 0 ||
        height % 64 != 0 ||
        pixels.length != width * height * channels) {
      throw LlamaImageGenerationException(
        'Image-editing pixels require dimensions that are multiples of 64 '
        'from 64 through 2048 and exactly width * height * channels bytes.',
      );
    }
    return Uint8List.fromList(pixels);
  }
}

/// Image-to-image generation, optionally restricted by a binary [mask].
///
/// The bounded recipe requires the pinned stable_diffusion v0.3.0-1 runtime,
/// an SD 2.x checkpoint with its embedded full VAE on macOS CPU, and no
/// component overrides, circular axes or VAE tiling. SD-Turbo is the measured
/// model; other SD 2.x checkpoints in this recipe are unmeasured.
/// Other families, decoders, devices and platforms throw
/// [LlamaUnsupportedException] before starting a generation.
///
/// The output uses [initialImage]'s dimensions. Supply decoded RGB bytes;
/// input alpha must be composited by the caller. Inputs are copied on creation
/// and remain owned through cancellation until the native call has ended.
final class ImageEditingRequest extends ImageGenerationRequest {
  /// Decoded RGB input. A mask input cannot be used here.
  final ImageEditingPixels initialImage;

  /// Optional binary mask with the input dimensions; white edits, black keeps
  /// the encoded latent. An omitted mask edits the whole image.
  final ImageEditingPixels? mask;

  /// Denoising strength, greater than 0 and at most 1. Higher values add more
  /// noise and permit larger changes; 1 still encodes the supplied image.
  final double strength;

  /// Creates a request. Pixel, mask and strength checks precede inference.
  ImageEditingRequest({
    required super.prompt,
    required this.initialImage,
    this.mask,
    this.strength = 0.75,
    super.negativePrompt,
    super.steps,
    super.guidanceScale,
    super.seed,
    super.count,
    super.sampler,
    super.scheduler,
  }) : super(width: initialImage.width, height: initialImage.height);
}

/// Validates image-editing data and the bounded loaded-model recipe.
void validateImageEditingRecipe(
  ImageGenerationSessionRequest request,
  ImageGenerationSessionConfig config,
  String modelVersion,
) {
  final image = request.initialImage;
  if (image == null) {
    if (request.mask != null || request.strength != null) {
      throw LlamaImageGenerationException(
        'An image-editing mask or strength requires an initial RGB image.',
      );
    }
    return;
  }
  final mask = request.mask;
  final strength = request.strength;
  if (image.channels != 3 ||
      image.width != request.width ||
      image.height != request.height ||
      (mask != null &&
          (mask.channels != 1 ||
              mask.width != image.width ||
              mask.height != image.height)) ||
      strength == null ||
      !strength.isFinite ||
      strength <= 0 ||
      strength > 1) {
    throw LlamaImageGenerationException(
      'Image editing requires RGB input aligned with the output, an optional '
      'one-channel mask with matching dimensions, and finite strength '
      'greater than 0 and at most 1.',
    );
  }
  if (!config.imageEditingRecipeVerified ||
      modelVersion != 'SD 2.x' ||
      request.vaeTiling != null ||
      request.circularX ||
      request.circularY ||
      config.flashAttention ||
      config.vaeDirectConvolution) {
    throw LlamaUnsupportedException(
      'Image editing requires stable_diffusion v0.3.0-1 with an SD 2.x '
      'checkpoint and its embedded full VAE on macOS CPU, without component '
      'overrides, VAE tiling, circular axes, flash attention or direct VAE '
      'convolution. Other model, decoder, platform and device recipes are '
      'not qualified.',
    );
  }
}
