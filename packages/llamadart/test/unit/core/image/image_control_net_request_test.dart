import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/image/image_control_net_request.dart';
import 'package:llamadart/src/core/image/image_generation_driver.dart';
import 'package:test/test.dart';

ImageEditingPixels _rgb([int width = 64, int height = 64]) =>
    ImageEditingPixels.rgb(
      width: width,
      height: height,
      pixels: Uint8List(width * height * 3),
    );

ImageGenerationSessionRequest _request({
  ImageEditingPixels? control,
  double? strength = 0.9,
  ImageEditingPixels? initialImage,
  bool circularY = false,
  ImageVaeTiling? tiling,
}) => ImageGenerationSessionRequest(
  prompt: 'a house',
  negativePrompt: '',
  width: 64,
  height: 64,
  steps: 4,
  guidanceScale: 7,
  seed: 42,
  count: 1,
  controlImage: control,
  controlStrength: strength,
  initialImage: initialImage,
  strength: initialImage == null ? null : 0.5,
  circularY: circularY,
  vaeTiling: tiling,
);

const _qualified = ImageGenerationSessionConfig(
  files: {'model': 'sd15.safetensors', 'controlNet': 'canny.safetensors'},
  backend: 'cpu',
  threads: 1,
  controlNetRecipeVerified: true,
);

void main() {
  test('the request takes its size and default strength from the control', () {
    final source = Uint8List(128 * 64 * 3)..[2] = 9;
    final image = ImageEditingPixels.rgb(
      width: 128,
      height: 64,
      pixels: source,
    );
    final request = ControlNetImageGenerationRequest(
      prompt: 'a house',
      control: ImageControlNetCondition(image: image),
    );
    source[2] = 77;
    expect((request.width, request.height), (128, 64));
    expect(request.control.strength, ImageControlNetCondition.defaultStrength);
    expect(ImageControlNetCondition.defaultStrength, 0.9);
    expect(request.control.image.pixels[2], 9);
  });

  test('channel, alignment and strength checks reject invalid input', () {
    final mask = ImageEditingPixels.mask(
      width: 64,
      height: 64,
      pixels: Uint8List(64 * 64),
    );
    for (final strength in [
      null,
      -0.01,
      2.01,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => validateImageControlNetRecipe(
          _request(control: _rgb(), strength: strength),
          _qualified,
          'SD 1.x',
        ),
        throwsA(isA<LlamaImageGenerationException>()),
        reason: '$strength',
      );
    }
    for (final request in [
      _request(control: mask),
      _request(control: _rgb(128, 64)),
      _request(),
    ]) {
      expect(
        () => validateImageControlNetRecipe(request, _qualified, 'SD 1.x'),
        throwsA(isA<LlamaImageGenerationException>()),
      );
    }
    for (final strength in [0.0, 1.0, ImageControlNetCondition.maxStrength]) {
      validateImageControlNetRecipe(
        _request(control: _rgb(), strength: strength),
        _qualified,
        'SD 1.x',
      );
    }
  });

  test('unqualified recipes refuse while ordinary requests pass', () {
    final request = _request(control: _rgb());
    for (final config in [
      const ImageGenerationSessionConfig(files: {}, backend: 'cpu', threads: 1),
      const ImageGenerationSessionConfig(
        files: {},
        backend: 'cpu',
        threads: 1,
        controlNetRecipeVerified: true,
        flashAttention: true,
      ),
      const ImageGenerationSessionConfig(
        files: {},
        backend: 'cpu',
        threads: 1,
        controlNetRecipeVerified: true,
        vaeDirectConvolution: true,
      ),
    ]) {
      expect(
        () => validateImageControlNetRecipe(request, config, 'SD 1.x'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      validateImageControlNetRecipe(_request(strength: null), config, 'x');
    }
    for (final combined in [
      _request(control: _rgb(), initialImage: _rgb()),
      _request(control: _rgb(), circularY: true),
      _request(control: _rgb(), tiling: const ImageVaeTiling()),
    ]) {
      expect(
        () => validateImageControlNetRecipe(combined, _qualified, 'SD 1.x'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    }
    for (final family in ['SD 2.x', 'SD 1.x Inpaint', 'SDXL', '']) {
      expect(
        () => validateImageControlNetRecipe(request, _qualified, family),
        throwsA(isA<LlamaUnsupportedException>()),
        reason: family,
      );
    }
  });
}
