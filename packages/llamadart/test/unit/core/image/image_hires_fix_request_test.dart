import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/image/image_generation_driver.dart';
import 'package:llamadart/src/core/image/image_hires_fix_request.dart';
import 'package:test/test.dart';

ImageGenerationSessionHiresFix _resolve(
  ImageHiresFix hiresFix, {
  int width = 512,
  int height = 512,
  int steps = 20,
  int count = 1,
}) => resolveImageHiresFix(
  hiresFix,
  width: width,
  height: height,
  steps: steps,
  count: count,
);

Matcher _rejects(String message, Object? value) => throwsA(
  isA<LlamaImageGenerationException>()
      .having((error) => error.message, 'message', contains(message))
      .having((error) => error.details, 'details', value),
);

const _pass = ImageGenerationSessionHiresFix(
  width: 768,
  height: 768,
  steps: 10,
  denoisingStrength: 0.5,
  upscaler: ImageHiresUpscaler.latent,
);

ImageGenerationSessionRequest _request({
  ImageGenerationSessionHiresFix? hiresFix = _pass,
  ImageEditingPixels? initialImage,
  ImageEditingPixels? controlImage,
  ImageVaeTiling? vaeTiling,
  bool circularX = false,
  bool circularY = false,
}) => ImageGenerationSessionRequest(
  prompt: 'a fox',
  negativePrompt: '',
  width: 512,
  height: 512,
  steps: 20,
  guidanceScale: 7,
  seed: 42,
  count: 1,
  hiresFix: hiresFix,
  initialImage: initialImage,
  strength: initialImage == null ? null : 0.5,
  controlImage: controlImage,
  controlStrength: controlImage == null ? null : 1,
  vaeTiling: vaeTiling,
  circularX: circularX,
  circularY: circularY,
);

const _qualified = ImageGenerationSessionConfig(
  files: {'model': 'sd15.safetensors'},
  backend: 'cpu',
  threads: 1,
  hiresFixRecipeVerified: true,
);

void main() {
  test('the two forms are mutually exclusive and default to the latent '
      'upscaler, the first pass steps and strength 0.7', () {
    const scaled = ImageHiresFix.scale(1.5);
    expect((scaled.scale, scaled.width, scaled.height), (1.5, null, null));
    const sized = ImageHiresFix.size(width: 768, height: 640);
    expect((sized.scale, sized.width, sized.height), (null, 768, 640));
    for (final hiresFix in [scaled, sized]) {
      expect(hiresFix.upscaler, ImageHiresUpscaler.latent);
      expect(hiresFix.steps, isNull);
      expect(hiresFix.denoisingStrength, 0.7);
    }
    const request = HiresFixImageGenerationRequest(
      prompt: 'a fox',
      hiresFix: scaled,
      width: 512,
      height: 384,
    );
    expect((request.width, request.height), (512, 384));
    expect(request, isA<ImageGenerationRequest>());
  });

  test('a scale resolves to the rounded first-pass size, and a size is used '
      'as given', () {
    final scaled = _resolve(
      const ImageHiresFix.scale(1.5, steps: 8, denoisingStrength: 0.45),
      height: 384,
    );
    expect((scaled.width, scaled.height), (768, 576));
    expect((scaled.steps, scaled.denoisingStrength), (8, 0.45));
    expect(scaled.upscaler, ImageHiresUpscaler.latent);
    final doubled = _resolve(const ImageHiresFix.scale(2));
    expect((doubled.width, doubled.height), (1024, 1024));
    expect(doubled.steps, 20, reason: 'unset steps reuse the first pass');
    final sized = _resolve(
      const ImageHiresFix.size(width: 640, height: 512),
      steps: 6,
    );
    expect((sized.width, sized.height, sized.steps), (640, 512, 6));
    final widened = _resolve(
      const ImageHiresFix.size(width: 1024, height: 512),
    );
    expect((widened.width, widened.height), (1024, 512));
  });

  test('scale bounds and unaligned resolved sizes are rejected, never '
      'rounded', () {
    for (final scale in [
      1.0,
      0.5,
      2.01,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => _resolve(ImageHiresFix.scale(scale)),
        _rejects('hiresFix.scale', scale),
        reason: '$scale',
      );
    }
    expect(
      () => _resolve(const ImageHiresFix.scale(1.3)),
      _rejects('multiples of 64', '666x666'),
    );
    expect(
      () => _resolve(const ImageHiresFix.scale(1.5), height: 320),
      _rejects('multiples of 64', '768x480'),
    );
  });

  test('final sizes must be aligned, enlarge the first pass within twice '
      'each side and stay within the pixel budget', () {
    for (final (width, height, message) in [
      (768, 600, 'multiples of 64'),
      (512, 512, 'larger than the 512x512 first pass'),
      (448, 768, 'larger than the 512x512 first pass'),
      (1088, 512, 'at most twice'),
      (512, 1088, 'at most twice'),
    ]) {
      expect(
        () => _resolve(ImageHiresFix.size(width: width, height: height)),
        _rejects(message, '${width}x$height'),
      );
    }
    expect(
      () => _resolve(
        const ImageHiresFix.size(width: 1024, height: 1088),
        width: 768,
        height: 768,
      ),
      _rejects('at most 1048576 pixels', '1024x1088'),
    );
    expect(
      () => _resolve(const ImageHiresFix.scale(2), width: 576, height: 512),
      _rejects('at most 1048576 pixels', '1152x1024'),
    );
    expect(
      () => _resolve(const ImageHiresFix.scale(2), width: 520, height: 512),
      _rejects('first-pass width and height', '520x512'),
    );
    final largest = _resolve(
      const ImageHiresFix.size(width: 1024, height: 1024),
    );
    expect(largest.width * largest.height, ImageHiresFix.maxFinalPixels);
  });

  test('steps, strength and count limits', () {
    for (final steps in [0, -1, 151]) {
      expect(
        () => _resolve(ImageHiresFix.scale(1.5, steps: steps)),
        _rejects('hiresFix.steps', steps),
      );
    }
    expect(_resolve(const ImageHiresFix.scale(1.5, steps: 150)).steps, 150);
    for (final strength in [0.0, 0.049, 1.01, double.nan, double.infinity]) {
      expect(
        () => _resolve(ImageHiresFix.scale(1.5, denoisingStrength: strength)),
        _rejects('denoisingStrength', strength),
      );
    }
    for (final strength in [0.05, 1.0]) {
      expect(
        _resolve(
          ImageHiresFix.scale(1.5, denoisingStrength: strength),
        ).denoisingStrength,
        strength,
      );
    }
    expect(_resolve(const ImageHiresFix.scale(2), count: 4).steps, 20);
    expect(
      () => _resolve(const ImageHiresFix.scale(2), count: 5),
      _rejects('at most 4 images', 5),
    );
  });

  test('the recipe admits SD 1.x and SD 2.x with recipe proof only, and '
      'ignores requests without a hires fix', () {
    for (final family in ['SD 1.x', 'SD 2.x']) {
      validateImageHiresFixRecipe(_request(), _qualified, family);
    }
    for (final (config, family) in [
      (_qualified, 'SDXL'),
      (_qualified, 'SDXS (512-DS)'),
      (_qualified, ''),
      (
        const ImageGenerationSessionConfig(
          files: {'model': 'sd15.safetensors'},
          backend: 'cpu',
          threads: 1,
        ),
        'SD 1.x',
      ),
    ]) {
      expect(
        () => validateImageHiresFixRecipe(_request(), config, family),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(contains('v0.3.0-1'), contains('not qualified')),
          ),
        ),
        reason: family,
      );
    }
    validateImageHiresFixRecipe(
      _request(hiresFix: null),
      const ImageGenerationSessionConfig(
        files: {'model': 'sdxl.safetensors'},
        backend: null,
        threads: 0,
      ),
      'SDXL',
    );
  });

  test('a hires fix combined with another opt-in input is refused even on '
      'the qualified recipe', () {
    final rgb = ImageEditingPixels.rgb(
      width: 512,
      height: 512,
      pixels: Uint8List(512 * 512 * 3),
    );
    for (final (name, request) in [
      ('editing', _request(initialImage: rgb)),
      ('ControlNet', _request(controlImage: rgb)),
      ('tiling', _request(vaeTiling: const ImageVaeTiling())),
      ('circular X', _request(circularX: true)),
      ('circular Y', _request(circularY: true)),
    ]) {
      expect(
        () => validateImageHiresFixRecipe(request, _qualified, 'SD 2.x'),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('combined with'),
          ),
        ),
        reason: name,
      );
    }
  });
}
