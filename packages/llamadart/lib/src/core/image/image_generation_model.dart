import '../models/model_source.dart';
import 'local_image_set_model.dart';

/// Runtime role of an image-model file.
///
/// `ImageGenerationEngine.load` detects each file's role from its header;
/// set one with [ImageModelComponent.new] only for a file it cannot
/// classify. Load errors also name files by role. Roles may be added; include
/// a default case in switches.
enum ImageModelRole {
  /// A full checkpoint: diffusion weights, usually with their VAE and text
  /// encoders, such as SD 1.x, 2.x, SDXL or SD 3.5 Medium single files.
  checkpoint,

  /// Standalone diffusion weights (UNet or transformer) of a split model.
  diffusionModel,

  /// A VAE.
  vae,

  /// A tiny autoencoder (TAESD), which replaces the VAE decoder for faster,
  /// lower-memory decoding at a small quality cost.
  taesd,

  /// A CLIP-L text encoder (or SD 2.x's OpenCLIP-H).
  clipL,

  /// A CLIP-G text encoder.
  clipG,

  /// A T5-XXL text encoder.
  t5xxl,

  /// A language-model text encoder, such as Qwen3-4B for Z-Image.
  llm,

  /// A ControlNet, which steers sampling toward the control image of a
  /// `ControlNetImageGenerationRequest`. It loads with the model and stays
  /// loaded until disposal; requests cannot swap it. Only the bounded recipe
  /// that `ControlNetImageGenerationRequest` describes loads one.
  controlNet,
}

/// A file of an image model besides its main file.
class ImageModelComponent {
  /// Where the file comes from.
  final ModelSource source;

  /// The role the caller set, or `null` to detect it from the file.
  final ImageModelRole? role;

  /// A file whose role is detected from its header.
  const ImageModelComponent.auto(this.source) : role = null;

  /// A file in [role], for a file the header check cannot classify, such as
  /// a `.ckpt` file, or to choose between layouts it cannot tell apart.
  const ImageModelComponent(this.source, {required ImageModelRole this.role});
}

/// An image-generation model: a main file and the other files it needs.
///
/// Compatible GGUF and Safetensors files load directly and can be mixed;
/// Safetensors does not need conversion to GGUF. Detection reads contents,
/// not filename extensions. A compatible PyTorch `.ckpt`, `.pth` or `.pt`
/// state-dict file needs an explicit [role] (or a component's role); this
/// forwards it to the native loader, not a conversion or compatibility check.
/// Real PyTorch checkpoint qualification remains incomplete. Individual local sources
/// must be regular files. [ImageGenerationModel.localSafetensorsSet] opts into
/// the separately bounded complete-checkpoint set contract; arbitrary
/// directories and Diffusers component layouts remain unsupported.
/// Leave [ModelSource.format] unset for image files. A recognized container
/// and role do not establish architecture, dtype or device compatibility.
///
/// Each file is a `ModelSource` (local path, HTTP(S) URL or Hugging Face
/// file) that `ImageGenerationEngine.load` downloads if needed and then
/// assigns to its runtime role from its header, so files can be listed in
/// any order. The set needs one file with diffusion weights: a checkpoint or
/// a split model's diffusion model, plus its VAE, tiny autoencoder and text
/// encoders.
///
/// ```dart
/// final flux = ImageGenerationModel(
///   ModelSource.path('flux1-schnell-Q4_0.gguf'),
///   components: [
///     ImageModelComponent.auto(ModelSource.path('ae.safetensors')),
///     ImageModelComponent.auto(ModelSource.path('clip_l-Q8_0.gguf')),
///     ImageModelComponent.auto(ModelSource.path('t5xxl-Q8_0.gguf')),
///   ],
/// );
/// ```
///
/// Building a model does no network or file access.
class ImageGenerationModel {
  /// A verified local complete-checkpoint Safetensors index and its shards.
  ///
  /// [path] is a directory containing `model.safetensors.index.json`, or
  /// that index itself. [sha256] must identify the index and every adjacent
  /// shard by canonical numbered basename. Shards must be the complete
  /// contiguous `model-00001-of-000NN.safetensors` set, with N from 1..16. Remote sources, Diffusers component layouts,
  /// symlinks, extra shards/indexes and ambiguous mappings are rejected.
  /// The bounded recipe is the qualified SD-Turbo F16/F32 tensor layout on
  /// macOS CPU with the pinned SD v0.3.0-1 runtime, flash attention/direct VAE
  /// convolution off. Other layouts/dtypes/devices are unsupported.
  ///
  /// [cacheDirectory] must be app-private and dedicated to owned sets. Files
  /// are copied and hash-verified before atomic cache publication; original
  /// contents may change after copying. Source topology must remain stable
  /// during resolution. Published cache files must not be modified or removed
  /// while any engine uses them; remove this cache only after disposal.
  /// Cache reuse re-verifies every file. Failed/cancelled staging is removed;
  /// a complete published set remains cached. This does no network access.
  /// Only cancellation from `ModelLoadOptions` applies; per-file identities
  /// replace its single checksum and this factory owns its cache location.
  /// Building the model performs no IO and adds no legacy interface member.
  factory ImageGenerationModel.localSafetensorsSet(
    String path, {
    required Map<String, String> sha256,
    required String cacheDirectory,
  }) = LocalImageSetModel;

  /// The main file, usually the checkpoint or diffusion model.
  final ModelSource source;

  /// The role the caller set for [source], or `null` to detect it.
  final ImageModelRole? role;

  /// The other files.
  final List<ImageModelComponent> components;

  /// Creates a model from its main [source] and other [components]. Set
  /// [role] only when the header check cannot classify [source].
  const ImageGenerationModel(
    this.source, {
    this.role,
    this.components = const <ImageModelComponent>[],
  });
}

/// Sampling method of a generation.
///
/// A subset of stable-diffusion.cpp's samplers. When the request leaves it
/// unset, the runtime picks the model's default: Euler for
/// transformer models such as SD 3.5, FLUX and Z-Image, and Euler ancestral
/// for UNet models such as SD 1.x, 2.x and SDXL.
enum ImageGenerationSampler {
  /// Euler.
  euler,

  /// Euler ancestral, which adds fresh noise every step.
  eulerAncestral,

  /// DPM++ 2M.
  dpmpp2m,

  /// Latent consistency model sampling, for LCM-distilled checkpoints.
  lcm,
}

/// Noise schedule of a generation.
///
/// A subset of stable-diffusion.cpp's schedulers. When the request leaves it
/// unset, the runtime picks the default for the model and sampler.
enum ImageGenerationScheduler {
  /// The model's discrete training schedule.
  discrete,

  /// Karras et al. (2022) noise levels.
  karras,

  /// Uniform in sigma, as SDXL-Lightning's model card recommends.
  sgmUniform,

  /// Evenly spaced training timesteps.
  simple,
}
