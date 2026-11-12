import '../exceptions.dart';
import 'generated_image.dart';

/// Stage of an image generation.
enum ImageGenerationPhase {
  /// The runtime is loading weights it did not load with the model.
  loading,

  /// The text encoder is encoding the prompt.
  encodingPrompt,

  /// The diffusion model is denoising the latent image.
  sampling,

  /// The VAE is decoding latents into pixels.
  decoding,
}

/// Base class for image-generation events.
sealed class ImageGenerationEvent {
  /// Creates an image-generation event.
  const ImageGenerationEvent();
}

/// Progress emitted before the final images are available.
class ImageGenerationProgressEvent extends ImageGenerationEvent {
  /// Current phase.
  final ImageGenerationPhase phase;

  /// Completed units of the current phase. During
  /// [ImageGenerationPhase.sampling] these are sampling steps, and `0` means
  /// sampling of [imageIndex] has started. During
  /// [ImageGenerationPhase.loading] they are the tensors the runtime reports
  /// loading. [ImageGenerationPhase.decoding] starts at `0` of [imageCount]
  /// images and counts tiles if the runtime decodes in tiles.
  final int step;

  /// Total units of the current phase.
  final int steps;

  /// Zero-based index of the image being generated.
  final int imageIndex;

  /// Number of images requested.
  final int imageCount;

  /// Zero-based sampling pass: `1` while a hires fix refines the images,
  /// `0` otherwise. Decoding follows the last pass.
  final int pass;

  /// Number of sampling passes: `2` with a hires fix, otherwise `1`.
  final int passCount;

  /// Creates a progress event.
  const ImageGenerationProgressEvent({
    required this.phase,
    required this.step,
    required this.steps,
    required this.imageIndex,
    required this.imageCount,
    this.pass = 0,
    this.passCount = 1,
  });
}

/// Final event carrying the generated images.
class ImageGenerationFinalEvent extends ImageGenerationEvent {
  /// The generation result.
  final ImageGenerationResult result;

  /// Creates a final event.
  const ImageGenerationFinalEvent(this.result);
}

/// Terminal state of an image-generation task.
enum ImageGenerationCompletionState {
  /// Generation produced images.
  completed,

  /// Generation was cancelled.
  cancelled,

  /// Generation failed.
  failed,
}

/// Terminal details of an image-generation task.
class ImageGenerationCompletion {
  /// Terminal state.
  final ImageGenerationCompletionState state;

  /// Result when [state] is [ImageGenerationCompletionState.completed].
  final ImageGenerationResult? result;

  /// Failure when [state] is [ImageGenerationCompletionState.failed].
  final LlamaException? error;

  const ImageGenerationCompletion._({
    required this.state,
    this.result,
    this.error,
  });

  /// Creates a successful completion.
  factory ImageGenerationCompletion.completed(ImageGenerationResult result) =>
      ImageGenerationCompletion._(
        state: ImageGenerationCompletionState.completed,
        result: result,
      );

  /// Creates a cancelled completion.
  const factory ImageGenerationCompletion.cancelled() =
      _CancelledImageGenerationCompletion;

  /// Creates a failed completion.
  factory ImageGenerationCompletion.failed(LlamaException error) =>
      ImageGenerationCompletion._(
        state: ImageGenerationCompletionState.failed,
        error: error,
      );
}

class _CancelledImageGenerationCompletion extends ImageGenerationCompletion {
  const _CancelledImageGenerationCompletion()
    : super._(state: ImageGenerationCompletionState.cancelled);
}
