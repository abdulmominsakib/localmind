import 'dart:typed_data';

import 'png_encoder.dart';

/// A generated image with 8-bit interleaved channels.
class GeneratedImage {
  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Channels per pixel: 3 (RGB) for the stable_diffusion runtime.
  final int channels;

  /// Row-major pixel bytes, `width * height * channels` long.
  final Uint8List pixels;

  /// Creates a generated image.
  const GeneratedImage({
    required this.width,
    required this.height,
    required this.channels,
    required this.pixels,
  });

  /// Encodes this image as PNG bytes.
  ///
  /// Throws `LlamaImageGenerationException` when [pixels] does not match the
  /// dimensions or [channels] is not 1, 3 or 4.
  Uint8List toPng() => encodePng(
    width: width,
    height: height,
    channels: channels,
    pixels: pixels,
  );
}

/// The images of one completed generation.
class ImageGenerationResult {
  /// Generated images, one per requested image, in seed order.
  final List<GeneratedImage> images;

  /// Seed of the first image; image `i` used `seed + i`.
  final int seed;

  /// Wall-clock generation time, excluding model load.
  final Duration elapsed;

  /// Creates a generation result.
  const ImageGenerationResult({
    required this.images,
    required this.seed,
    required this.elapsed,
  });
}
