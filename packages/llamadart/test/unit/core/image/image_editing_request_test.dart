import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/image/image_editing_request.dart';
import 'package:llamadart/src/core/image/image_generation_driver.dart';
import 'package:test/test.dart';

ImageEditingPixels _rgb([int width = 64, int height = 64]) =>
    ImageEditingPixels.rgb(
      width: width,
      height: height,
      pixels: Uint8List(width * height * 3),
    );

ImageGenerationSessionRequest _request({
  ImageEditingPixels? image,
  ImageEditingPixels? mask,
  double? strength = 0.75,
  bool circularX = false,
  ImageVaeTiling? tiling,
}) => ImageGenerationSessionRequest(
  prompt: 'edit',
  negativePrompt: '',
  width: 64,
  height: 64,
  steps: 4,
  guidanceScale: 1,
  seed: 42,
  count: 1,
  initialImage: image,
  mask: mask,
  strength: strength,
  circularX: circularX,
  vaeTiling: tiling,
);

const _qualified = ImageGenerationSessionConfig(
  files: {'model': 'model.gguf'},
  backend: 'cpu',
  threads: 1,
  imageEditingRecipeVerified: true,
);

void main() {
  test('RGB input and returned bytes cannot mutate owned pixels', () {
    final source = Uint8List(64 * 64 * 3)..[1] = 17;
    final image = ImageEditingPixels.rgb(width: 64, height: 64, pixels: source);
    source[1] = 99;
    final exposed = image.pixels..[1] = 88;
    expect(exposed[1], 88);
    expect(image.pixels[1], 17);
    expect(image.channels, 3);
    final request = ImageEditingRequest(prompt: 'edit', initialImage: image);
    expect((request.width, request.height, request.strength), (64, 64, 0.75));
  });

  test('binary masks own their bytes and reject implicit thresholds', () {
    final source = Uint8List(64 * 64)..[0] = 255;
    final mask = ImageEditingPixels.mask(width: 64, height: 64, pixels: source);
    source[0] = 0;
    mask.pixels[0] = 0;
    expect(mask.pixels[0], 255);
    expect(mask.channels, 1);
    source[4] = 128;
    expect(
      () => ImageEditingPixels.mask(width: 64, height: 64, pixels: source),
      throwsA(isA<LlamaImageGenerationException>()),
    );
  });

  test('dimensions and byte limits reject before copying', () {
    for (final dimensions in [(0, 64), (63, 64), (72, 64), (64, 2112)]) {
      expect(
        () => ImageEditingPixels.rgb(
          width: dimensions.$1,
          height: dimensions.$2,
          pixels: Uint8List(0),
        ),
        throwsA(isA<LlamaImageGenerationException>()),
      );
    }
    expect(
      () => ImageEditingPixels.rgb(width: 64, height: 64, pixels: Uint8List(3)),
      throwsA(isA<LlamaImageGenerationException>()),
    );
    expect(_rgb(2048, 2048).pixels.length, 2048 * 2048 * 3);
  });

  test(
    'strength, channel and alignment checks reject invalid session input',
    () {
      final rgb = _rgb();
      final mask = ImageEditingPixels.mask(
        width: 64,
        height: 64,
        pixels: Uint8List(64 * 64),
      );
      for (final strength in [
        null,
        0.0,
        -1.0,
        1.1,
        double.nan,
        double.infinity,
      ]) {
        expect(
          () => validateImageEditingRecipe(
            _request(image: rgb, strength: strength),
            _qualified,
            'SD 2.x',
          ),
          throwsA(isA<LlamaImageGenerationException>()),
        );
      }
      for (final request in [
        _request(image: mask),
        _request(image: rgb, mask: rgb),
        _request(image: _rgb(128, 64)),
        _request(mask: mask),
      ]) {
        expect(
          () => validateImageEditingRecipe(request, _qualified, 'SD 2.x'),
          throwsA(isA<LlamaImageGenerationException>()),
        );
      }
      for (final strength in [0.001, 1.0]) {
        validateImageEditingRecipe(
          _request(image: rgb, mask: mask, strength: strength),
          _qualified,
          'SD 2.x',
        );
      }
    },
  );

  test('unqualified recipes refuse without changing ordinary requests', () {
    final request = _request(image: _rgb());
    for (final config in [
      const ImageGenerationSessionConfig(files: {}, backend: 'cpu', threads: 1),
      const ImageGenerationSessionConfig(
        files: {},
        backend: 'cpu',
        threads: 1,
        imageEditingRecipeVerified: true,
        flashAttention: true,
      ),
      const ImageGenerationSessionConfig(
        files: {},
        backend: 'cpu',
        threads: 1,
        imageEditingRecipeVerified: true,
        vaeDirectConvolution: true,
      ),
    ]) {
      expect(
        () => validateImageEditingRecipe(request, config, 'SD 2.x'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      validateImageEditingRecipe(_request(strength: null), config, 'unknown');
    }
    for (final request in [
      _request(image: _rgb(), circularX: true),
      _request(image: _rgb(), tiling: const ImageVaeTiling()),
    ]) {
      expect(
        () => validateImageEditingRecipe(request, _qualified, 'SD 2.x'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    }
    expect(
      () => validateImageEditingRecipe(request, _qualified, 'SDXL'),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });
}
