import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/image/image_generation_driver.dart';
import 'package:llamadart/src/core/image/image_reference_editing_request.dart';
import 'package:test/test.dart';

ImageEditingPixels _rgb(int width, int height, [int value = 7]) =>
    ImageEditingPixels.rgb(
      width: width,
      height: height,
      pixels: Uint8List(width * height * 3)..fillRange(0, 3, value),
    );

const _qualified = ImageGenerationSessionConfig(
  files: {
    'diffusionModel': 'flux1-kontext-dev.gguf',
    'vae': 'ae.safetensors',
    'clipL': 'clip_l.gguf',
    't5xxl': 't5xxl.gguf',
  },
  backend: 'gpu',
  threads: 0,
  referenceEditingRecipeVerified: true,
  flashAttention: true,
);

ImageGenerationSessionRequest _request({
  List<ImageEditingPixels>? references,
  int width = 512,
  int height = 384,
  ImageEditingPixels? initialImage,
  ImageEditingPixels? controlImage,
  ImageGenerationSessionHiresFix? hiresFix,
  ImageVaeTiling? vaeTiling,
  bool circularX = false,
  bool circularY = false,
}) => ImageGenerationSessionRequest(
  prompt: 'make the fox blue',
  negativePrompt: '',
  width: width,
  height: height,
  steps: 20,
  guidanceScale: 1,
  seed: 1,
  count: 1,
  references: references ?? [_rgb(width, height)],
  referenceRecipe: ImageReferenceEditingRecipe.fluxKontext,
  initialImage: initialImage,
  strength: initialImage == null ? null : 0.5,
  controlImage: controlImage,
  controlStrength: controlImage == null ? null : 1,
  hiresFix: hiresFix,
  vaeTiling: vaeTiling,
  circularX: circularX,
  circularY: circularY,
);

Matcher _unsupported(Object message) => throwsA(
  isA<LlamaUnsupportedException>().having(
    (error) => error.message,
    'message',
    message,
  ),
);

void main() {
  test('the output takes the first reference size, and references are '
      'owned in order', () {
    final first = Uint8List(512 * 384 * 3)..[0] = 1;
    final references = [
      ImageEditingPixels.rgb(width: 512, height: 384, pixels: first),
      _rgb(512, 384, 2),
    ];
    final request = ReferenceImageEditingRequest(
      prompt: 'make the fox blue',
      recipe: ImageReferenceEditingRecipe.fluxKontext,
      references: references,
    );
    first[0] = 9;
    references.removeLast();

    expect((request.width, request.height), (512, 384));
    expect([for (final image in request.references) image.pixels[0]], [1, 2]);
    expect(() => request.references.add(_rgb(64, 64)), throwsUnsupportedError);
  });

  test('no reference, or a mask as one, is invalid', () {
    for (final references in [
      <ImageEditingPixels>[],
      [ImageEditingPixels.mask(width: 64, height: 64, pixels: Uint8List(4096))],
    ]) {
      expect(
        () => ReferenceImageEditingRequest(
          prompt: 'edit',
          recipe: ImageReferenceEditingRecipe.fluxKontext,
          references: references,
        ),
        throwsA(isA<LlamaImageGenerationException>()),
      );
    }
  });

  test('references must be RGB at the output size within 1024x1024, never '
      'resized', () {
    validateImageReferenceEditingRecipe(
      _request(width: 1024, height: 1024),
      _qualified,
      'Flux',
    );
    for (final (name, request) in [
      ('larger than the output', _request(references: [_rgb(576, 384)])),
      ('smaller than the output', _request(references: [_rgb(448, 384)])),
      (
        'mask',
        _request(
          references: [
            ImageEditingPixels.mask(
              width: 512,
              height: 384,
              pixels: Uint8List(512 * 384),
            ),
          ],
        ),
      ),
      ('none', _request(references: const [])),
      ('above the pixel budget', _request(width: 1088, height: 1024)),
    ]) {
      expect(
        () => validateImageReferenceEditingRecipe(request, _qualified, 'Flux'),
        throwsA(
          isA<LlamaImageGenerationException>().having(
            (error) => error.message,
            'message',
            contains('crop or resize'),
          ),
        ),
        reason: name,
      );
    }
  });

  test('the recipe takes exactly one reference', () {
    expect(
      () => validateImageReferenceEditingRecipe(
        _request(references: [_rgb(512, 384), _rgb(512, 384)]),
        _qualified,
        'Flux',
      ),
      _unsupported(contains('exactly one reference image; 2 were given')),
    );
  });

  test('references combined with another opt-in input are refused even on '
      'the qualified recipe', () {
    for (final (name, request) in [
      ('image editing', _request(initialImage: _rgb(512, 384))),
      ('ControlNet', _request(controlImage: _rgb(512, 384))),
      (
        'hires fix',
        _request(
          hiresFix: const ImageGenerationSessionHiresFix(
            width: 768,
            height: 576,
            steps: 4,
            denoisingStrength: 0.5,
            upscaler: ImageHiresUpscaler.latent,
          ),
        ),
      ),
      (
        'VAE tiling',
        _request(
          vaeTiling: const ImageVaeTiling(tileWidth: 256, tileHeight: 256),
        ),
      ),
      ('circular X', _request(circularX: true)),
      ('circular Y', _request(circularY: true)),
    ]) {
      expect(
        () => validateImageReferenceEditingRecipe(request, _qualified, 'Flux'),
        _unsupported(contains('combined with')),
        reason: name,
      );
    }
  });

  test('the recipe admits the Flux family with recipe proof only, and '
      'ignores requests without references', () {
    for (final (config, family) in [
      (_qualified, 'Flux Fill'),
      (_qualified, 'SD 2.x'),
      (_qualified, ''),
      (
        const ImageGenerationSessionConfig(
          files: {'diffusionModel': 'flux1-kontext-dev.gguf'},
          backend: 'gpu',
          threads: 0,
        ),
        'Flux',
      ),
    ]) {
      expect(
        () => validateImageReferenceEditingRecipe(_request(), config, family),
        _unsupported(allOf(contains('v0.3.0-1'), contains('not qualified'))),
        reason: family,
      );
    }
    validateImageReferenceEditingRecipe(
      const ImageGenerationSessionRequest(
        prompt: 'a fox',
        negativePrompt: '',
        width: 512,
        height: 512,
        steps: 4,
        guidanceScale: 1,
        seed: 1,
        count: 1,
      ),
      const ImageGenerationSessionConfig(
        files: {'model': 'sd-turbo.gguf'},
        backend: null,
        threads: 0,
      ),
      'SD 2.x',
    );
  });
}
