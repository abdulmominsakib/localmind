import '../exceptions.dart';
import 'image_generation_model.dart';
import 'image_generation_driver.dart';

/// A request to generate one or more images from a text prompt.
class ImageGenerationRequest {
  /// Smallest accepted [width] and [height].
  static const int minDimension = 64;

  /// Largest accepted [width] and [height].
  static const int maxDimension = 2048;

  /// Largest accepted [steps].
  static const int maxSteps = 150;

  /// Largest accepted [guidanceScale].
  static const double maxGuidanceScale = 30;

  /// Largest accepted [count].
  static const int maxCount = 16;

  /// Largest accepted [flowShift].
  static const double maxFlowShift = 100;

  /// Width and height used when a request leaves them unset.
  static const int defaultDimension = 512;

  /// Steps used when a request leaves them unset.
  static const int defaultSteps = 20;

  /// Guidance scale used when a request leaves it unset.
  static const double defaultGuidanceScale = 7;

  /// Text prompt.
  final String prompt;

  /// Negative prompt. Ignored when the guidance scale is 1, as distilled
  /// models such as SDXS and SD-Turbo use.
  final String negativePrompt;

  /// Output width in pixels: a multiple of 8 from [minDimension] to
  /// [maxDimension]. `null` uses [defaultDimension]. Use the model's native
  /// size: 512 for SD 1.x and 2.x models such as SDXS and SD-Turbo, 1024 for
  /// SDXL and newer families. The runtime rounds SD 1.x and 2.x sizes up to a
  /// multiple of 64; `GeneratedImage.width` reports the size produced.
  final int? width;

  /// Output height in pixels, with the same range, default and rounding as
  /// [width].
  final int? height;

  /// Sampling steps from 1 to [maxSteps]. `null` uses [defaultSteps], which
  /// suits undistilled SD 1.x and 2.x models; distilled models such as SDXS,
  /// SD-Turbo or FLUX.1-schnell need 1 to 8.
  final int? steps;

  /// Classifier-free guidance scale from 0 to [maxGuidanceScale]. `null` uses
  /// [defaultGuidanceScale]; distilled models use 1, which also skips the
  /// negative prompt and halves the work per step.
  final double? guidanceScale;

  /// Random seed, 0 or greater. `null` picks a random seed; the result
  /// reports the seed used either way.
  final int? seed;

  /// Number of images, from 1 to [maxCount]. Image `i` uses seed `seed + i`.
  final int count;

  /// Sampling method. `null` uses the runtime's default for the model.
  final ImageGenerationSampler? sampler;

  /// Noise schedule. `null` uses the runtime's default for the model and
  /// sampler.
  final ImageGenerationScheduler? scheduler;

  /// Timestep shift of flow-matching models, greater than 0 and at most
  /// [maxFlowShift]. `null` uses the runtime's default for the model; other
  /// models ignore it.
  final double? flowShift;

  /// Creates an image-generation request.
  const ImageGenerationRequest({
    required this.prompt,
    this.negativePrompt = '',
    this.width,
    this.height,
    this.steps,
    this.guidanceScale,
    this.seed,
    this.count = 1,
    this.sampler,
    this.scheduler,
    this.flowShift,
  });
}

/// A request that opts into spatial VAE decode tiling.
///
/// Supported for SD 2.x checkpoints with their embedded full VAE or a TAESD
/// override on CPU or Metal. SD-Turbo is the measured recipe; other SD 2.x
/// checkpoints and platforms remain unqualified. Other families, decoder
/// overrides and devices throw [LlamaUnsupportedException] before a task starts.
/// Ordinary [ImageGenerationRequest] implementations keep their original API.
final class TiledImageGenerationRequest extends ImageGenerationRequest {
  /// Overlapping spatial tiles used by the decoder.
  final ImageVaeTiling vaeTiling;

  /// Creates an opt-in tiled request.
  const TiledImageGenerationRequest({
    required super.prompt,
    required this.vaeTiling,
    super.negativePrompt,
    super.width,
    super.height,
    super.steps,
    super.guidanceScale,
    super.seed,
    super.count,
    super.sampler,
    super.scheduler,
    super.flowShift,
  });
}

/// Returns opt-in decode settings without extending the ordinary interface.
ImageVaeTiling? imageRequestVaeTiling(ImageGenerationRequest request) =>
    switch (request) {
      TiledImageGenerationRequest() => request.vaeTiling,
      SeamlessImageGenerationRequest() => request.vaeTiling,
      _ => null,
    };

/// Spatial VAE decode tiling for [TiledImageGenerationRequest].
///
/// The decoder (the VAE, or the tiny autoencoder that replaces it) runs on
/// one [tileWidth] by [tileHeight] tile of the image at a time instead of on
/// the whole image, and blends where tiles overlap. Its compute buffer then
/// scales with the tile instead of the image, which lowers peak memory most
/// for large images and full VAEs. Decoding takes longer, and pixels change
/// slightly, mostly near tile seams. Sampling, the prompt encoders and the
/// weights are unaffected. A tile larger than the image covers the whole
/// image on that axis.
///
/// Without tiling, the runtime already retries a decode that fails to
/// allocate its buffers with tiles; tiling from the start avoids reaching that
/// limit, as where the system ends an app before an allocation fails. If a
/// tile still does not fit, the runtime retries with smaller tiles.
class ImageVaeTiling {
  /// Smallest accepted [tileWidth] and [tileHeight], and the step both
  /// take: a multiple of every supported decoder's downscale factor.
  static const int minTileSize = 64;

  /// Largest accepted [tileWidth] and [tileHeight].
  static const int maxTileSize = ImageGenerationRequest.maxDimension;

  /// [tileWidth] and [tileHeight] when unset: stable-diffusion.cpp's default.
  static const int defaultTileSize = 256;

  /// Largest accepted [overlap].
  static const double maxOverlap = 0.5;

  /// [overlap] when unset: stable-diffusion.cpp's default.
  static const double defaultOverlap = 0.5;

  /// Tile width in output pixels: a multiple of [minTileSize] up to
  /// [maxTileSize].
  final int tileWidth;

  /// Tile height in output pixels, with the same range as [tileWidth].
  final int tileHeight;

  /// Target fraction of a tile that overlaps its neighbour, from 0 to
  /// [maxOverlap]. More overlap blends seams better and decodes more tiles.
  /// The runtime spaces tiles evenly, so the overlap it uses is close to this
  /// one, and neighbouring tiles always overlap a little.
  final double overlap;

  /// Creates tiling settings.
  const ImageVaeTiling({
    this.tileWidth = defaultTileSize,
    this.tileHeight = defaultTileSize,
    this.overlap = defaultOverlap,
  });
}

/// A text-to-image request with independently repeatable texture axes.
///
/// Both axes default to off. When either is enabled, the initial qualified
/// recipe is SDXS (512-DS) with its header-detected embedded tiny decoder,
/// no component overrides, 512 by 512 pixels, and CPU or Metal computation.
/// Load with `flashAttention: false` and `vaeDirectConvolution: false`.
/// Other families, decoders, sizes and runtime options throw
/// [LlamaUnsupportedException] before generation starts.
///
/// The runtime applies circular padding to both diffusion and decoder
/// convolutions. Inspect a repeated tile: this improves continuity but does
/// not promise that every prompt and seed produces a useful texture.
///
/// This separate type preserves existing implementations and subclasses of
/// [ImageGenerationRequest]. Ordinary requests keep their original behavior.
final class SeamlessImageGenerationRequest extends ImageGenerationRequest {
  /// Wraps left and right convolution boundaries.
  final bool circularX;

  /// Wraps top and bottom convolution boundaries.
  final bool circularY;

  /// Optional decode tiling. Combining tiling with an enabled circular axis
  /// is unqualified and throws [LlamaUnsupportedException].
  final ImageVaeTiling? vaeTiling;

  /// Creates a request with independently optional circular axes.
  const SeamlessImageGenerationRequest({
    required super.prompt,
    super.negativePrompt,
    super.width,
    super.height,
    super.steps,
    super.guidanceScale,
    super.seed,
    super.count,
    super.sampler,
    super.scheduler,
    super.flowShift,
    this.circularX = false,
    this.circularY = false,
    this.vaeTiling,
  });
}

/// Throws [LlamaImageGenerationException] naming the first invalid field of
/// [request].
void validateImageGenerationRequest(ImageGenerationRequest request) {
  Never reject(String message, Object? value) =>
      throw LlamaImageGenerationException(message, value);

  if (request.prompt.trim().isEmpty) {
    reject('The image-generation prompt must not be empty.', null);
  }
  for (final (name, value) in [
    ('width', request.width),
    ('height', request.height),
  ]) {
    if (value != null &&
        (value < ImageGenerationRequest.minDimension ||
            value > ImageGenerationRequest.maxDimension ||
            value % 8 != 0)) {
      reject(
        '$name must be a multiple of 8 from '
        '${ImageGenerationRequest.minDimension} to '
        '${ImageGenerationRequest.maxDimension}.',
        value,
      );
    }
  }
  final steps = request.steps;
  if (steps != null && (steps < 1 || steps > ImageGenerationRequest.maxSteps)) {
    reject(
      'steps must be from 1 to ${ImageGenerationRequest.maxSteps}.',
      steps,
    );
  }
  final guidanceScale = request.guidanceScale;
  if (guidanceScale != null &&
      (!guidanceScale.isFinite ||
          guidanceScale < 0 ||
          guidanceScale > ImageGenerationRequest.maxGuidanceScale)) {
    reject(
      'guidanceScale must be from 0 to '
      '${ImageGenerationRequest.maxGuidanceScale}.',
      guidanceScale,
    );
  }
  final seed = request.seed;
  if (seed != null && seed < 0) {
    reject('seed must be 0 or greater.', seed);
  }
  if (request.count < 1 || request.count > ImageGenerationRequest.maxCount) {
    reject(
      'count must be from 1 to ${ImageGenerationRequest.maxCount}.',
      request.count,
    );
  }
  final flowShift = request.flowShift;
  if (flowShift != null &&
      (!flowShift.isFinite ||
          flowShift <= 0 ||
          flowShift > ImageGenerationRequest.maxFlowShift)) {
    reject(
      'flowShift must be greater than 0 and at most '
      '${ImageGenerationRequest.maxFlowShift}.',
      flowShift,
    );
  }
  final vaeTiling = imageRequestVaeTiling(request);
  if (vaeTiling != null) {
    for (final (name, value) in [
      ('vaeTiling.tileWidth', vaeTiling.tileWidth),
      ('vaeTiling.tileHeight', vaeTiling.tileHeight),
    ]) {
      if (value < ImageVaeTiling.minTileSize ||
          value > ImageVaeTiling.maxTileSize ||
          value % ImageVaeTiling.minTileSize != 0) {
        reject(
          '$name must be a multiple of ${ImageVaeTiling.minTileSize} from '
          '${ImageVaeTiling.minTileSize} to ${ImageVaeTiling.maxTileSize}.',
          value,
        );
      }
    }
    final overlap = vaeTiling.overlap;
    if (!overlap.isFinite ||
        overlap < 0 ||
        overlap > ImageVaeTiling.maxOverlap) {
      reject(
        'vaeTiling.overlap must be from 0 to ${ImageVaeTiling.maxOverlap}.',
        overlap,
      );
    }
  }
}

/// Rejects circular generation outside the measured SDXS decoder recipe.
/// Checks the native family and header evidence, never the model filename.
void validateSeamlessImageGenerationRecipe(
  ImageGenerationSessionRequest request,
  ImageGenerationSessionConfig config,
  String modelVersion,
) {
  if (!request.circularX && !request.circularY) return;
  if (request.vaeTiling != null) {
    throw LlamaUnsupportedException(
      'VAE tiling combined with seamless circular axes is not qualified. '
      'Use a tiled request without circular axes or the qualified untiled '
      'SDXS seamless recipe.',
    );
  }
  if (modelVersion != 'SDXS (512-DS)' ||
      !config.seamlessRecipeVerified ||
      config.files.length != 1 ||
      !config.files.containsKey('model') ||
      request.width != 512 ||
      request.height != 512 ||
      config.flashAttention ||
      config.vaeDirectConvolution) {
    throw LlamaUnsupportedException(
      'Seamless textures require stable_diffusion v0.3.0-1 SDXS (512-DS), '
      'its header-detected embedded tiny decoder without component overrides '
      'on CPU or Metal, '
      '512 by 512 pixels, flashAttention: false and '
      'vaeDirectConvolution: false. This model or decoder recipe is '
      'not qualified for circular padding.',
    );
  }
}

/// Refuses opt-in tiling outside the bounded CPU/Metal SD 2.x recipe.
void validateImageVaeTilingRecipe(
  ImageGenerationSessionRequest request,
  ImageGenerationSessionConfig config,
  String modelVersion,
) {
  if (request.vaeTiling == null) return;
  if (request.circularX ||
      request.circularY ||
      modelVersion != 'SD 2.x' ||
      !config.vaeTilingRecipeVerified) {
    throw LlamaUnsupportedException(
      'VAE tiling requires stable_diffusion v0.3.0-1, an SD 2.x checkpoint '
      'with its embedded full VAE or a TAESD override on CPU or Metal, '
      'without circular axes or other component overrides. SD-Turbo is '
      'the qualified model; this model, decoder or device recipe is '
      'not qualified for VAE tiling.',
    );
  }
}
