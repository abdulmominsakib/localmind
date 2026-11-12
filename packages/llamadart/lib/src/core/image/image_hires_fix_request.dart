import '../exceptions.dart';
import 'image_generation_driver.dart';
import 'image_generation_request.dart';

/// How [ImageHiresFix] enlarges the first pass before refining it.
enum ImageHiresUpscaler {
  /// Bilinear interpolation of the first pass's latent image, before it is
  /// decoded: stable-diffusion.cpp's `latent` hires upscaler. No extra model
  /// is loaded.
  latent,
}

/// A second, refining pass at a larger size: the "hires fix".
///
/// The runtime samples the first pass at the request's width and height,
/// enlarges each latent with [upscaler] to the final size, adds noise and
/// samples it again at the final size with [denoisingStrength], then decodes
/// only the final latents. Image `i` uses seed `seed + i` in both passes.
///
/// Give exactly one of a [scale] ([ImageHiresFix.scale]) or a final
/// [width] and [height] ([ImageHiresFix.size]). The first-pass and final
/// sizes must be multiples of [alignment]; nothing is rounded. Each final
/// axis is at least the first-pass axis and at most [maxScale] times it, the
/// final image is larger than the first pass and has at most
/// [maxFinalPixels] pixels, and a request makes at most [maxCount] images.
final class ImageHiresFix {
  /// Largest accepted [scale], and the largest final-to-first ratio of each
  /// axis.
  static const double maxScale = 2;

  /// Largest final image: 1024 by 1024 pixels.
  static const int maxFinalPixels = 1024 * 1024;

  /// Largest `count` of a [HiresFixImageGenerationRequest].
  static const int maxCount = 4;

  /// Multiple that the first-pass and final widths and heights take: the
  /// latent and UNet downscale of SD 1.x and 2.x models.
  static const int alignment = 64;

  /// Smallest accepted [denoisingStrength].
  static const double minDenoisingStrength = 0.05;

  /// [denoisingStrength] when unset: stable-diffusion.cpp's default.
  static const double defaultDenoisingStrength = 0.7;

  /// Final size as a multiple of the first pass, greater than 1 and at most
  /// [maxScale]; `null` when [width] and [height] give the final size. The
  /// final size is the first-pass size times this, rounded to the nearest
  /// pixel, and must be a multiple of [alignment].
  final double? scale;

  /// Final width in pixels; `null` when [scale] gives the final size.
  final int? width;

  /// Final height in pixels; `null` when [scale] gives the final size.
  final int? height;

  /// Sampling steps of the second pass, from 1 to
  /// [ImageGenerationRequest.maxSteps]. `null` uses the first pass's steps.
  /// As in stable-diffusion.cpp, the pass runs the last steps of a schedule
  /// of `steps / denoisingStrength` steps, which can be one more than this.
  final int? steps;

  /// How much noise the second pass adds, from [minDenoisingStrength] to 1.
  /// Lower values keep more of the enlarged first pass.
  final double denoisingStrength;

  /// How the first pass is enlarged.
  final ImageHiresUpscaler upscaler;

  /// Refines at [scale] times the first-pass size.
  const ImageHiresFix.scale(
    double this.scale, {
    this.steps,
    this.denoisingStrength = defaultDenoisingStrength,
    this.upscaler = ImageHiresUpscaler.latent,
  }) : width = null,
       height = null;

  /// Refines at [width] by [height] pixels.
  const ImageHiresFix.size({
    required int this.width,
    required int this.height,
    this.steps,
    this.denoisingStrength = defaultDenoisingStrength,
    this.upscaler = ImageHiresUpscaler.latent,
  }) : scale = null;
}

/// Text-to-image generation followed by an [ImageHiresFix] refinement pass.
///
/// [width] and [height] are the first-pass size; the images have the final
/// size of [hiresFix]. The bounded recipe requires the pinned
/// stable_diffusion v0.3.0-1 runtime on macOS with the CPU or Metal, and an
/// SD 1.x or SD 2.x checkpoint with its embedded full VAE and no component
/// overrides; check `ImageGenerationCapabilities.supportsHiresFix`. Other
/// recipes, and requests that combine it with image editing, ControlNet,
/// VAE tiling or circular axes, throw [LlamaUnsupportedException] before a
/// task starts. Ordinary requests keep their one-pass behavior.
///
/// Both passes run in one native generation. Cancelling stops it before the
/// next sampling step of either pass, or between the passes, and returns no
/// images: a cancelled or failed second pass never returns first-pass
/// images.
final class HiresFixImageGenerationRequest extends ImageGenerationRequest {
  /// The refinement pass.
  final ImageHiresFix hiresFix;

  /// Creates a request whose [width] and [height] are the first-pass size.
  const HiresFixImageGenerationRequest({
    required super.prompt,
    required this.hiresFix,
    super.negativePrompt,
    super.width,
    super.height,
    super.steps,
    super.guidanceScale,
    super.seed,
    super.count,
    super.sampler,
    super.scheduler,
  });
}

/// The resolved refinement pass of [hiresFix] after a first pass of [width]
/// by [height] pixels, [steps] steps and [count] images.
///
/// Throws [LlamaImageGenerationException] naming the first rule the sizes,
/// steps, strength or count break.
ImageGenerationSessionHiresFix resolveImageHiresFix(
  ImageHiresFix hiresFix, {
  required int width,
  required int height,
  required int steps,
  required int count,
}) {
  Never reject(String message, Object? value) =>
      throw LlamaImageGenerationException(message, value);

  const alignment = ImageHiresFix.alignment;
  if (width % alignment != 0 || height % alignment != 0) {
    reject(
      'A hires fix needs a first-pass width and height that are multiples of '
          '$alignment.',
      '${width}x$height',
    );
  }
  final int finalWidth;
  final int finalHeight;
  if (hiresFix.scale case final scale?) {
    if (!scale.isFinite || scale <= 1 || scale > ImageHiresFix.maxScale) {
      reject('hiresFix.scale must be greater than 1 and at most 2.', scale);
    }
    finalWidth = (width * scale).round();
    finalHeight = (height * scale).round();
  } else {
    finalWidth = hiresFix.width!;
    finalHeight = hiresFix.height!;
  }
  final size = '${finalWidth}x$finalHeight';
  if (finalWidth % alignment != 0 || finalHeight % alignment != 0) {
    reject(
      'The hires-fix final width and height must be multiples of $alignment.',
      size,
    );
  }
  if (finalWidth < width ||
      finalHeight < height ||
      finalWidth > width * ImageHiresFix.maxScale ||
      finalHeight > height * ImageHiresFix.maxScale ||
      finalWidth * finalHeight == width * height) {
    reject(
      'The hires-fix final size must be larger than the ${width}x$height '
      'first pass, with each side at least the first pass and at most '
      'twice it.',
      size,
    );
  }
  if (finalWidth * finalHeight > ImageHiresFix.maxFinalPixels) {
    reject(
      'The hires-fix final size must have at most '
      '${ImageHiresFix.maxFinalPixels} pixels (1024x1024).',
      size,
    );
  }
  final hiresSteps = hiresFix.steps ?? steps;
  if (hiresSteps < 1 || hiresSteps > ImageGenerationRequest.maxSteps) {
    reject(
      'hiresFix.steps must be from 1 to ${ImageGenerationRequest.maxSteps}.',
      hiresSteps,
    );
  }
  final strength = hiresFix.denoisingStrength;
  if (!strength.isFinite ||
      strength < ImageHiresFix.minDenoisingStrength ||
      strength > 1) {
    reject(
      'hiresFix.denoisingStrength must be from '
      '${ImageHiresFix.minDenoisingStrength} to 1.',
      strength,
    );
  }
  if (count > ImageHiresFix.maxCount) {
    reject(
      'A hires-fix request makes at most ${ImageHiresFix.maxCount} images.',
      count,
    );
  }
  return ImageGenerationSessionHiresFix(
    width: finalWidth,
    height: finalHeight,
    steps: hiresSteps,
    denoisingStrength: strength,
    upscaler: hiresFix.upscaler,
  );
}

/// Model families whose latent hires fix is qualified.
const Set<String> imageHiresFixModelVersions = {'SD 1.x', 'SD 2.x'};

/// Refuses a hires fix outside the bounded recipe, and one combined with
/// another opt-in input.
void validateImageHiresFixRecipe(
  ImageGenerationSessionRequest request,
  ImageGenerationSessionConfig config,
  String modelVersion,
) {
  if (request.hiresFix == null) return;
  if (request.initialImage != null ||
      request.controlImage != null ||
      request.vaeTiling != null ||
      request.circularX ||
      request.circularY) {
    throw LlamaUnsupportedException(
      'A hires fix combined with image editing, ControlNet, VAE tiling or '
      'circular axes is not qualified. Use HiresFixImageGenerationRequest '
      'for text-to-image generation only.',
    );
  }
  if (!config.hiresFixRecipeVerified ||
      !imageHiresFixModelVersions.contains(modelVersion)) {
    throw LlamaUnsupportedException(
      'A hires fix requires the stable_diffusion v0.3.0-1 runtime on macOS '
      'with the CPU or Metal, and an SD 1.x or SD 2.x checkpoint with its '
      'embedded full VAE and no component overrides. This model '
      '(${modelVersion.isEmpty ? 'no detected family' : modelVersion}), '
      'runtime or device recipe is not qualified for a hires fix.',
    );
  }
}
