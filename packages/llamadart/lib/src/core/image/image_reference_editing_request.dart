import '../exceptions.dart';
import 'image_editing_request.dart';
import 'image_generation_driver.dart';
import 'image_generation_request.dart';

/// A model-specific way of conditioning generation on reference images.
enum ImageReferenceEditingRecipe {
  /// FLUX.1 Kontext [dev]: each reference is encoded with the FLUX
  /// autoencoder and given to the transformer at one fixed position index,
  /// stable-diffusion.cpp's `flux_kontext` reference preset.
  ///
  /// The load must be a FLUX transformer with a guidance embedder and
  /// 64-wide patch input, the 16-channel FLUX autoencoder, CLIP-L and
  /// T5-XXL. FLUX.1 [dev] has the same layout, so the headers cannot tell
  /// it from Kontext; with it, references do not steer the output as an
  /// edit.
  fluxKontext,
}

/// Generation that edits ordered reference images as the prompt describes,
/// such as FLUX.1 Kontext's instruction editing.
///
/// The output has the size of the first reference, and every reference must
/// have that size, with at most [maxPixels] pixels, so the runtime encodes
/// each one as given: crop or resize references before creating the request.
/// The [ImageReferenceEditingRecipe.fluxKontext] recipe takes exactly one
/// reference. References are copied on creation and stay owned until the
/// native call has ended, including after a cancel.
///
/// The bounded recipe requires the pinned stable_diffusion v0.3.0-1 runtime
/// on macOS with Metal; check
/// `ImageGenerationCapabilities.supportsReferenceImageEditing`. Other
/// models, components, runtimes, devices and platforms, more references,
/// and requests that combine it with image editing, ControlNet, a hires
/// fix, VAE tiling or circular axes throw [LlamaUnsupportedException]
/// before a task starts.
final class ReferenceImageEditingRequest extends ImageGenerationRequest {
  /// Largest output and reference size: 1024 by 1024 pixels. The runtime
  /// shrinks larger references before encoding them.
  static const int maxPixels = 1024 * 1024;

  /// How the model uses [references].
  final ImageReferenceEditingRecipe recipe;

  /// Decoded RGB references in the order the model receives them.
  final List<ImageEditingPixels> references;

  /// Creates a request whose output has the size of the first of
  /// [references].
  ///
  /// Throws [LlamaImageGenerationException] for no references or a mask
  /// among them.
  ReferenceImageEditingRequest({
    required super.prompt,
    required this.recipe,
    required List<ImageEditingPixels> references,
    super.negativePrompt,
    super.steps,
    super.guidanceScale,
    super.seed,
    super.count,
    super.sampler,
    super.scheduler,
  }) : references = List.unmodifiable(_checked(references)),
       super(width: references.first.width, height: references.first.height);

  static List<ImageEditingPixels> _checked(List<ImageEditingPixels> images) {
    if (images.isEmpty || images.any((image) => image.channels != 3)) {
      throw LlamaImageGenerationException(
        'Reference image editing needs at least one RGB reference; masks '
        'are not references.',
      );
    }
    return images;
  }
}

/// Validates reference images and the bounded loaded-model recipe.
void validateImageReferenceEditingRecipe(
  ImageGenerationSessionRequest request,
  ImageGenerationSessionConfig config,
  String modelVersion,
) {
  final references = request.references;
  if (references == null) return;
  if (references.isEmpty ||
      references.any(
        (image) =>
            image.channels != 3 ||
            image.width != request.width ||
            image.height != request.height,
      ) ||
      request.width * request.height > ReferenceImageEditingRequest.maxPixels) {
    throw LlamaImageGenerationException(
      'Reference image editing needs RGB references of the output size with '
          'at most ${ReferenceImageEditingRequest.maxPixels} pixels (1024x1024); '
          'crop or resize them first.',
      '${request.width}x${request.height}',
    );
  }
  if (request.initialImage != null ||
      request.controlImage != null ||
      request.hiresFix != null ||
      request.vaeTiling != null ||
      request.circularX ||
      request.circularY) {
    throw LlamaUnsupportedException(
      'Reference image editing combined with image editing, ControlNet, a '
      'hires fix, VAE tiling or circular axes is not qualified.',
    );
  }
  if (references.length != 1) {
    throw LlamaUnsupportedException(
      'The FLUX.1 Kontext reference-editing recipe takes exactly one '
      'reference image; ${references.length} were given.',
    );
  }
  if (!config.referenceEditingRecipeVerified || modelVersion != 'Flux') {
    throw LlamaUnsupportedException(
      'Reference image editing requires the stable_diffusion v0.3.0-1 '
      'runtime on macOS with Metal, and exactly a FLUX.1 Kontext [dev] '
      'transformer with the FLUX autoencoder, CLIP-L and T5-XXL. This model '
      '(${modelVersion.isEmpty ? 'no detected family' : modelVersion}), '
      'runtime or device recipe is not qualified for reference editing.',
    );
  }
}
