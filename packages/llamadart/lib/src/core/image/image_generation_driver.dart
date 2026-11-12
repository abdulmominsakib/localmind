import 'dart:typed_data';

import '../../backends/stable_diffusion/stable_diffusion_runtime_status.dart';
import 'generated_image.dart';
import 'image_editing_request.dart';
import 'image_generation_model.dart';
import 'image_hires_fix_request.dart';
import 'image_generation_request.dart';
import 'image_reference_editing_request.dart';

/// Model files and runtime settings for one native image-generation context.
final class ImageGenerationSessionConfig {
  /// Local weight files keyed by runtime role: `model` (a checkpoint),
  /// `diffusionModel`, `vae`, `taesd`, `clipL`, `clipG`, `t5xxl`, `llm` or
  /// `controlNet`.
  final Map<String, String> files;

  /// stable-diffusion.cpp backend assignment: a device (`cpu`, `gpu`),
  /// module assignments such as `gpu,te=cpu`, or `null` for the runtime
  /// default.
  final String? backend;

  /// Per-GPU memory budget in GiB, or `null` for the runtime default.
  final int? maxGpuMemoryGiB;

  /// Whether the runtime's automatic fit places the weights.
  final bool autoFit;

  /// Conditioning-cache entry limit; `null` preserves the runtime default.
  final int? conditioningCacheSize;

  /// Whether headers verified an embedded tiny decoder without overrides
  /// on a qualified CPU or Metal device.
  /// Used only by the bounded SDXS seamless-texture recipe.
  final bool seamlessRecipeVerified;

  /// Header-role and device evidence for the bounded SD 2.x tiling recipe.
  final bool vaeTilingRecipeVerified;

  /// Header, runtime and host evidence for the macOS CPU full-VAE SD 2.x
  /// image-editing recipe.
  final bool imageEditingRecipeVerified;

  /// Header, runtime and host evidence for the macOS CPU SD 1.x ControlNet
  /// recipe.
  final bool controlNetRecipeVerified;

  /// Header, runtime, host and device evidence for the macOS CPU or Metal
  /// SD 1.x and 2.x full-VAE hires-fix recipe.
  final bool hiresFixRecipeVerified;

  /// Header, runtime, host and device evidence for the macOS Metal
  /// FLUX.1 Kontext reference-editing recipe.
  final bool referenceEditingRecipeVerified;

  /// CPU threads; `0` uses the physical core count.
  final int threads;

  /// Whether the diffusion model uses flash attention.
  final bool flashAttention;

  /// Whether the VAE decodes with direct convolutions.
  final bool vaeDirectConvolution;

  /// Requires the native context to preserve its intrinsic tiny decoder
  /// across model refreshes, including load-time and refresh-time probes.
  final bool requiresIntrinsicTinyDecoderV1;

  /// Creates a session configuration.
  const ImageGenerationSessionConfig({
    required this.files,
    required this.backend,
    required this.threads,
    this.conditioningCacheSize,
    this.maxGpuMemoryGiB,
    this.autoFit = true,
    this.seamlessRecipeVerified = false,
    this.vaeTilingRecipeVerified = false,
    this.imageEditingRecipeVerified = false,
    this.controlNetRecipeVerified = false,
    this.hiresFixRecipeVerified = false,
    this.referenceEditingRecipeVerified = false,
    this.flashAttention = false,
    this.vaeDirectConvolution = false,
    this.requiresIntrinsicTinyDecoderV1 = false,
  });
}

/// Fully resolved parameters for one native generation.
final class ImageGenerationSessionRequest {
  /// Prompt.
  final String prompt;

  /// Negative prompt.
  final String negativePrompt;

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Sampling steps.
  final int steps;

  /// Classifier-free guidance scale.
  final double guidanceScale;

  /// Seed of the first image.
  final int seed;

  /// Number of images.
  final int count;

  /// Sampling method, or `null` for the runtime default.
  final ImageGenerationSampler? sampler;

  /// Noise schedule, or `null` for the runtime default.
  final ImageGenerationScheduler? scheduler;

  /// Flow shift, or `null` for the runtime default.
  final double? flowShift;

  /// VAE decode tiling, or `null` to decode the whole image at once.
  final ImageVaeTiling? vaeTiling;

  /// Whether convolution boundaries wrap horizontally.
  final bool circularX;

  /// Whether convolution boundaries wrap vertically.
  final bool circularY;

  /// Owned RGB image, or `null` for ordinary text-to-image generation.
  final ImageEditingPixels? initialImage;

  /// Optional owned binary mask, aligned with [initialImage].
  final ImageEditingPixels? mask;

  /// Denoising strength for [initialImage], otherwise unused.
  final double? strength;

  /// Owned RGB ControlNet control image, or `null` to generate without it.
  final ImageEditingPixels? controlImage;

  /// ControlNet strength for [controlImage], otherwise unused.
  final double? controlStrength;

  /// Second, refining pass, or `null` for one pass.
  final ImageGenerationSessionHiresFix? hiresFix;

  /// Owned RGB references in model order, or `null` to generate without
  /// them.
  final List<ImageEditingPixels>? references;

  /// How the model uses [references], otherwise unused.
  final ImageReferenceEditingRecipe? referenceRecipe;

  /// Creates resolved generation parameters.
  const ImageGenerationSessionRequest({
    required this.prompt,
    required this.negativePrompt,
    required this.width,
    required this.height,
    required this.steps,
    required this.guidanceScale,
    required this.seed,
    required this.count,
    this.sampler,
    this.scheduler,
    this.flowShift,
    this.vaeTiling,
    this.circularX = false,
    this.circularY = false,
    this.initialImage,
    this.mask,
    this.strength,
    this.controlImage,
    this.controlStrength,
    this.hiresFix,
    this.references,
    this.referenceRecipe,
  });
}

/// Fully resolved hires-fix pass of one native generation.
final class ImageGenerationSessionHiresFix {
  /// Final width in pixels.
  final int width;

  /// Final height in pixels.
  final int height;

  /// Sampling steps of the second pass.
  final int steps;

  /// Noise the second pass adds, from 0 to 1.
  final double denoisingStrength;

  /// How the first pass is enlarged.
  final ImageHiresUpscaler upscaler;

  /// Creates a resolved pass.
  const ImageGenerationSessionHiresFix({
    required this.width,
    required this.height,
    required this.steps,
    required this.denoisingStrength,
    required this.upscaler,
  });
}

/// Memory the device can give an image model, and where the figure came from.
typedef ImageGenerationMemoryBudget = ({int bytes, String source});

/// The memory of a GPU as the stable_diffusion runtime reports it, in bytes.
/// [name] is the device name with its description, such as
/// `Vulkan0 (NVIDIA L4)`.
typedef StableDiffusionGpuMemory = ({
  String name,
  int totalBytes,
  int freeBytes,
  bool integrated,
});

/// What the memory of a device means for a load: a model that needs more than
/// [refuse] cannot load, and one that needs more than [slower] loads with
/// part of it outside the device's own memory, which makes generation slower.
/// Either is `null` when it is not known or does not apply.
typedef ImageGenerationMemoryLimits = ({
  ImageGenerationMemoryBudget? refuse,
  ImageGenerationMemoryBudget? slower,
});

/// Kind of device a model loads on, which decides whose memory bounds it.
enum ImageGenerationComputeDevice {
  /// The CPU: host memory.
  cpu,

  /// An Apple GPU through Metal: unified memory, bounded by Metal's
  /// recommended working set.
  metal,

  /// Any other GPU, such as Vulkan: its own device memory as the runtime
  /// reports it, with host memory behind it for what does not fit, or host
  /// memory alone when the GPU is an integrated one.
  otherGpu,
}

/// Optional session support for honoring per-request spatial VAE tiling.
/// Sessions without this contract are refused for opt-in tiled requests.
abstract interface class ImageVaeTilingSession {
  /// Whether this session can honor tiling for its loaded recipe and runtime.
  bool get supportsVaeTiling;
}

/// Optional active-session capability for the bounded image-editing recipe.
abstract interface class ImageEditingSession {
  /// Whether this loaded session can honor RGB/mask/strength input mapping.
  bool get supportsImageEditing;
}

/// Optional active-session capability for the bounded ControlNet recipe.
abstract interface class ImageControlNetSession {
  /// Whether this loaded session holds a ControlNet and can honor a control
  /// image and strength.
  bool get supportsControlNet;
}

/// Optional active-session capability for the bounded hires-fix recipe.
abstract interface class ImageHiresFixSession {
  /// Whether this loaded session can honor a second, refining pass.
  bool get supportsHiresFix;
}

/// Optional active-session capability for the bounded reference-editing
/// recipe.
abstract interface class ImageReferenceEditingSession {
  /// Whether this loaded session can honor ordered reference images.
  bool get supportsReferenceImageEditing;
}

/// A loaded native image-generation context.
abstract interface class ImageGenerationSession {
  /// Model family the runtime detected, such as `SD 2.x`.
  String get modelVersion;

  /// Runs one generation, reporting native `(step, steps)` progress.
  ///
  /// Returns `null` when the runtime reports failure, which includes a
  /// cancelled generation; the session stays usable afterwards. Throws
  /// `LlamaInferenceException` when a failed GPU command buffer left the
  /// backend in an error state, and from then on throws it again at once:
  /// only a new session recovers.
  Future<List<GeneratedImage>?> generate(
    ImageGenerationSessionRequest request,
    void Function(int step, int steps) onProgress,
  );

  /// Asks a running [generate] to stop. Safe to call at any time; the
  /// runtime clears the request when the next generation starts.
  void cancel();

  /// Frees the native context. Must not overlap [generate].
  Future<void> dispose();
}

/// Platform services behind `ImageGenerationEngine`.
abstract interface class ImageGenerationDriver {
  /// The operating system the runtime runs on, as `Platform.operatingSystem`
  /// names it (`ios`, `macos`, `android`, ...), or `web`.
  String get operatingSystem;

  /// Whether the process is a macOS x86_64 process, Rosetta included.
  bool get isMacosX64;

  /// Probes the stable_diffusion runtime without loading a model or blocking
  /// the calling isolate: on native platforms it runs in a short-lived
  /// isolate, because the first probe in a process can compile GPU shaders
  /// for seconds.
  Future<StableDiffusionRuntimeStatus> probeInBackground();

  /// Size of the file at [path] in bytes, or `null` when it does not exist.
  int? fileSize(String path);

  /// Up to [length] bytes of the file at [path] from [offset], for reading
  /// model file headers; fewer at the end of the file.
  Future<Uint8List> readFileRange(String path, int offset, int length);

  /// The memory limits of a new model on [device]. [runtimePicksGpu] says
  /// that the load names no backend, so with several GPUs the runtime
  /// computes on the one with the most free memory, not on the first.
  /// [gpus] is what [readGpuMemory] returned; only a GPU other than Metal
  /// reads it, and `null` means the runtime did not say.
  Future<ImageGenerationMemoryLimits> memoryLimits(
    ImageGenerationComputeDevice device, {
    required bool runtimePicksGpu,
    List<StableDiffusionGpuMemory>? gpus,
  });

  /// The memory of every GPU other than Metal that the runtime lists, or
  /// `null` when it does not say (see `readStableDiffusionGpuMemory`). A
  /// native call that can block, so on native platforms it runs in a
  /// short-lived isolate. One load reads it once and passes it to
  /// [memoryLimits].
  Future<List<StableDiffusionGpuMemory>?> readGpuMemory();

  /// Loads a native context. On native platforms the runtime's messages
  /// reach `LlamaLogger` from then on, at the levels `LlamaLogging` has when
  /// this is called.
  ///
  /// Throws `LlamaModelException` when the runtime rejects the files, with
  /// the runtime's reason when it gives one.
  Future<ImageGenerationSession> start(ImageGenerationSessionConfig config);
}

/// Test-only driver override used by focused public API tests.
ImageGenerationDriver? debugImageGenerationDriverOverride;
