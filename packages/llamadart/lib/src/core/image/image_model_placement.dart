/// Where the modules of an image model compute, and how stable-diffusion.cpp
/// fits their weights into GPU memory: `placement:` of
/// `ImageGenerationEngine.load`.
///
/// The default changes nothing. Every other setting needs an engine on a GPU
/// (Metal, or Vulkan on Linux and Windows): `ImageGenerationEngine.load`
/// throws `LlamaUnsupportedException` when the engine runs on the CPU, with
/// `ComputeDevice.cpu`, on Android, with the Linux and Windows CPU builds, or
/// when the runtime reports no GPU. On the web the runtime is unavailable,
/// so the load throws that exception for any placement.
final class ImageModelPlacement {
  /// Largest [maxGpuMemoryGiB]: 1 PiB.
  static const int largestGpuMemoryGiB = 1 << 20;

  /// Whether the text encoders (CLIP-L, CLIP-G, T5-XXL, or an LLM such as
  /// Z-Image's Qwen3) compute on the CPU, with their weights in system
  /// memory, while the diffusion model stays on the GPU.
  ///
  /// It frees the encoders' GPU memory (T5-XXL Q8_0 alone is about 5 GB) for
  /// a CPU encode once per generation. The conditioning differs from the
  /// GPU's in rounding, which sampling carries into the image: SD-Turbo on an
  /// M4 Max changed by at most 40 and on average 0.23 of 255 per channel.
  ///
  /// With a discrete and an integrated Vulkan GPU and `ComputeDevice.auto`,
  /// moving a module, here or with [vaeOnCpu], lets the runtime's fit also
  /// consider the integrated GPU, which can then compute the diffusion model
  /// when it reports more free memory: slower, not a failure.
  /// `ComputeDevice.gpu` keeps the first discrete GPU.
  final bool textEncoderOnCpu;

  /// Whether the VAE or tiny autoencoder computes on the CPU, with its
  /// weights and the decode's working memory (1.6 GiB for a 512x512 SD 2.x
  /// image) in system memory.
  ///
  /// The decode is slower: a one-step 512x512 SD-Turbo image took 8.9 s
  /// instead of 2.1 to 2.6 s on an M4 Max, and its pixels changed by at most
  /// 1 of 255.
  final bool vaeOnCpu;

  /// The most GPU memory, in GiB, stable-diffusion.cpp uses on each GPU for
  /// weights and compute buffers, or `null` for the GPU's free memory less
  /// 512 MiB. It is never more than the GPU's free memory.
  ///
  /// The budget covers weights and the room the runtime's fit reserves for
  /// computing (2 GiB beside the diffusion model and the text encoders, 1 GiB
  /// beside the VAE, in the pinned runtime), so weights can move to system
  /// memory, another GPU or disk even when they alone are below it. Moved
  /// weights are streamed to the GPU when used, which is slower; compute
  /// buffers above the budget are split into segments. A budget below the VAE
  /// decode's
  /// working memory makes the runtime decode in tiles, which shows at their
  /// seams: SD-Turbo at 512x512 with 1 GiB changed by at most 85 and on
  /// average 2.5 of 255 per channel. A budget the model fits leaves pixels
  /// unchanged.
  ///
  /// From 1 to [largestGpuMemoryGiB], in whole GiB because the runtime parses
  /// a fraction in the process's locale, which may use a decimal comma.
  /// Needs [autoFit] and, outside Metal, a discrete GPU: the load throws
  /// `LlamaUnsupportedException` when the runtime reports only integrated
  /// GPUs or no GPU type, because the pinned runtime can then compute on an
  /// integrated GPU under the budget without its fit and abort.
  final int? maxGpuMemoryGiB;

  /// Whether stable-diffusion.cpp decides where weights go from the memory
  /// that is free (its automatic fit).
  ///
  /// When on, as by default, the runtime computes on the GPU with the most
  /// free memory (with `ComputeDevice.auto`), keeps there the weights that
  /// fit, and moves the rest to system memory, another GPU, or disk, in that
  /// order: a model larger than the GPU loads and generates more slowly.
  ///
  /// When off, every module's weights are allocated at load on the device it
  /// computes on, and `ComputeDevice.auto` uses the first GPU (the CPU on
  /// macOS x86_64, where only `ComputeDevice.gpu` places on Metal). Where the
  /// device cannot allocate them, the load fails with `LlamaModelException`
  /// instead of moving them; Metal shares system memory and can page past
  /// its working set instead. A model that fits loads and generates the same
  /// pixels either way. `ImageGenerationEngine.load` refuses it together
  /// with [maxGpuMemoryGiB] with `LlamaUnsupportedException`: the pinned
  /// runtime aborts the process when that budget is below the weights.
  final bool autoFit;

  /// Creates a placement. The default changes nothing.
  const ImageModelPlacement({
    this.textEncoderOnCpu = false,
    this.vaeOnCpu = false,
    this.maxGpuMemoryGiB,
    this.autoFit = true,
  });
}
