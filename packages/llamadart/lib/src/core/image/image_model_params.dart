import '../models/config/compute_device.dart';
import 'image_generation_model.dart';

/// Runtime settings of an image-generation engine: `params:` of
/// `ImageGenerationEngine.load`.
class ImageModelParams {
  /// Device to run on: [ComputeDevice.auto] picks the first GPU the runtime
  /// reports (Metal on Apple, Vulkan on the Linux and Windows Vulkan build),
  /// otherwise the CPU; on macOS x86_64, Rosetta included, it picks the CPU
  /// and only [ComputeDevice.gpu] uses Metal. [ComputeDevice.gpu] without a
  /// GPU, as on Android and the Linux and Windows CPU builds, and
  /// [ComputeDevice.npu] throw `LlamaUnsupportedException`.
  final ComputeDevice device;

  /// CPU threads. `0` uses the number of physical cores.
  final int threads;

  /// Whether `ImageGenerationEngine.load` refuses a model that its memory
  /// estimate says cannot fit the device. See `ImageGenerationEngine.load`.
  final bool checkMemory;

  /// Whether the diffusion model uses flash attention, which needs less
  /// memory and is often faster, with output that differs only in rounding.
  ///
  /// `null` turns it on for the CPU and Metal, where it was measured, and
  /// leaves it off on other GPUs such as Vulkan. On an M4 Max it made
  /// SD 3.5 Medium sampling 1.6 times as fast and cut its compute buffer
  /// from 1.8 GiB to 0.3 GiB, sped up FLUX and SDXL slightly and left
  /// SD 1.x and 2.x sampling time unchanged; on its CPU, SD-Turbo sampling
  /// was about a fifth faster. Pixels change slightly. The runtime falls back
  /// to regular attention where the device lacks a kernel.
  final bool? flashAttention;

  /// Whether the VAE decoder runs its convolutions directly instead of
  /// unfolding its input first. On the CPU the output is identical; on
  /// Metal on an M4 Max it differed by rounding, at most 2 of 255 per
  /// channel.
  ///
  /// `true` on iOS with the Metal backend makes `ImageGenerationEngine.load`
  /// throw `LlamaUnsupportedException`: on an iPhone 16 Pro every decode
  /// tripped the GPU watchdog and returned a corrupt image
  /// ([#1044](https://github.com/leehack/llamadart/issues/1044)). macOS
  /// Metal is not affected.
  ///
  /// `null` turns it on, except on Metal and when a tiny autoencoder
  /// decodes: a [ImageModelRole.taesd] file, or a checkpoint whose header
  /// shows an embedded one, as SDXS's does. In stable-diffusion.cpp's native
  /// CLI on an NVIDIA L4 with Vulkan it cut a 1024x1024 decode from 23 to
  /// 56 s to about 1 s and peak device memory by 4 to 5 GiB. On an M4 Max
  /// CPU it made a 512x512 SD-Turbo image about 5% slower end to end and cut
  /// peak memory from 3.6 to 2.7 GiB. On Metal it made decoding about 7
  /// times slower. With a tiny autoencoder it saved little memory and slowed
  /// decoding by about 40% on Metal; on the M4 Max CPU it made a 512x512
  /// SDXS image 1.4 to 1.7 s instead of 1.2 to 1.3 s, for 0.24 GiB less peak
  /// memory.
  final bool? vaeDirectConvolution;

  /// Creates runtime settings.
  const ImageModelParams({
    this.device = ComputeDevice.auto,
    this.threads = 0,
    this.checkMemory = true,
    this.flashAttention,
    this.vaeDirectConvolution,
  });
}

/// Image runtime settings with an explicit prompt-conditioning cache capacity.
///
/// Ordinary [ImageModelParams] preserve the runtime default (4 entries).
/// This separate type keeps existing implementations and subclasses of
/// [ImageModelParams] source-compatible.
final class ImageConditioningCacheParams extends ImageModelParams {
  /// Largest [capacity], the signed 32-bit C ABI limit.
  static const int maxCapacity = 0x7FFFFFFF;

  /// Number of prompt-conditioning entries retained by this loaded model.
  ///
  /// `0` disables conditioning reuse. Accepts 0 through [maxCapacity]. Other
  /// values make `ImageGenerationEngine.load` throw
  /// `LlamaImageGenerationException` before resolving or downloading files.
  ///
  /// This counts entries, not bytes. Matching conditioning inputs reuse an
  /// entry; eviction is least-recently-used first. Entries belong to the
  /// native model context and are freed on disposal. Load another engine to
  /// change capacity. This does not enable approximate diffusion-step caches
  /// or change sampling settings.
  final int capacity;

  /// Creates runtime settings with an explicit conditioning-cache [capacity].
  const ImageConditioningCacheParams({
    required this.capacity,
    super.device,
    super.threads,
    super.checkMemory,
    super.flashAttention,
    super.vaeDirectConvolution,
  });
}
