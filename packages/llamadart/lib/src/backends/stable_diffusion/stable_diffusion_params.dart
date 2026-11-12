import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../core/image/image_generation_driver.dart';
import '../../core/image/image_editing_request.dart';
import '../../core/image/image_generation_model.dart';
import '../../core/image/image_hires_fix_request.dart';
import '../../core/image/image_reference_editing_request.dart';
import 'stable_diffusion_bindings.dart' as sd;

/// Writes [config] into [params], which `sd_ctx_params_init` has filled with
/// the runtime defaults. Strings are allocated with [allocator] and must
/// outlive the `new_sd_ctx` call.
void applyStableDiffusionContextParams(
  Pointer<sd.sd_ctx_params_t> params,
  ImageGenerationSessionConfig config,
  Allocator allocator,
) {
  Pointer<Char> text(String? value) =>
      value == null ? nullptr : value.toNativeUtf8(allocator: allocator).cast();

  final files = config.files;
  params.ref
    ..model_path = text(files['model'])
    ..diffusion_model_path = text(files['diffusionModel'])
    ..vae_path = text(files['vae'])
    ..taesd_path = text(files['taesd'])
    ..clip_l_path = text(files['clipL'])
    ..clip_g_path = text(files['clipG'])
    ..t5xxl_path = text(files['t5xxl'])
    ..llm_path = text(files['llm'])
    ..control_net_path = text(files['controlNet'])
    ..backend = text(config.backend)
    ..diffusion_flash_attn = config.flashAttention
    ..vae_conv_direct = config.vaeDirectConvolution
    // Load every weight now, so the load pays for reading the files and
    // progress during generation is only sampling. A model that does not fit
    // the device does not fail the load: the runtime's automatic fit keeps
    // some weights in host memory or on disk, which makes sampling slower.
    ..eager_load = true
    // Batched CFG returns wrong images as success on Metal
    // (leejet/stable-diffusion.cpp#2149) and is unqualified on other GPUs.
    ..batched_cfg = false;
  // A null or empty mode makes the runtime probe each module and choose for
  // itself, which changes images and is not seed-reproducible on Metal.
  params.ref
    ..flash_attn_mode = text(
      stableDiffusionFlashAttentionMode(
        all: params.ref.flash_attn,
        diffusion: params.ref.diffusion_flash_attn,
      ),
    )
    ..conv_direct_mode = text(
      stableDiffusionConvDirectMode(
        diffusion: params.ref.diffusion_conv_direct,
        vae: params.ref.vae_conv_direct,
      ),
    );
  params.ref.auto_fit = config.autoFit;
  if (config.maxGpuMemoryGiB case final gib?) {
    params.ref.max_vram = text('$gib');
  }
  if (config.conditioningCacheSize case final capacity?) {
    params.ref.conditioning_cache_size = capacity;
  }
  if (config.threads > 0) {
    params.ref.n_threads = config.threads;
  }
}

/// The `flash_attn_mode` the legacy `flash_attn` ([all]) and
/// `diffusion_flash_attn` ([diffusion]) flags selected before the runtime
/// added modes. ControlNet stays off, as it was with [all].
String stableDiffusionFlashAttentionMode({
  required bool all,
  required bool diffusion,
}) {
  if (all) return 'off,te=on,clip_vision=on,vae=on,diffusion=on';
  if (diffusion) return 'off,diffusion=on';
  return 'off';
}

/// The `conv_direct_mode` the legacy `diffusion_conv_direct` ([diffusion])
/// and `vae_conv_direct` ([vae]) flags selected before the runtime added
/// modes.
String stableDiffusionConvDirectMode({
  required bool diffusion,
  required bool vae,
}) => [
  'off',
  if (diffusion) 'diffusion=on,control_net=on',
  if (vae) 'vae=on',
].join(',');

/// Writes [request] into [params], which `sd_img_gen_params_init` has filled
/// with the runtime defaults. Strings are allocated with [allocator] and must
/// outlive the `generate_image` call.
void applyStableDiffusionGenerationParams(
  Pointer<sd.sd_img_gen_params_t> params,
  ImageGenerationSessionRequest request,
  Allocator allocator,
) {
  params.ref
    ..prompt = request.prompt.toNativeUtf8(allocator: allocator).cast()
    ..negative_prompt = request.negativePrompt
        .toNativeUtf8(allocator: allocator)
        .cast()
    ..width = request.width
    ..height = request.height
    ..seed = request.seed
    ..batch_count = request.count
    ..circular_x = request.circularX
    ..circular_y = request.circularY;
  void writePixels(sd.sd_image_t target, ImageEditingPixels source) {
    final pixels = source.pixels;
    final data = allocator<Uint8>(pixels.length);
    data.asTypedList(pixels.length).setAll(0, pixels);
    target
      ..width = source.width
      ..height = source.height
      ..channel = source.channels
      ..data = data;
  }

  if (request.initialImage case final image?) {
    writePixels(params.ref.init_image, image);
    params.ref.strength = request.strength!;
    if (request.mask case final mask?) {
      writePixels(params.ref.mask_image, mask);
    }
  }
  if (request.controlImage case final control?) {
    writePixels(params.ref.control_image, control);
    params.ref.control_strength = request.controlStrength!;
  }
  if (request.references case final references?) {
    final images = allocator<sd.sd_image_t>(references.length);
    for (final (index, reference) in references.indexed) {
      writePixels(images[index], reference);
    }
    params.ref
      ..ref_images = images
      ..ref_images_count = references.length
      // An explicit preset keeps the runtime from choosing one by the
      // detected family.
      ..ref_image_args = stableDiffusionReferencePreset(
        request.referenceRecipe!,
      ).toNativeUtf8(allocator: allocator).cast();
  }
  params.ref.sample_params
    ..sample_steps = request.steps
    ..guidance.txt_cfg = request.guidanceScale
    ..sample_method = stableDiffusionSampleMethod(request.sampler)
    ..scheduler = stableDiffusionScheduler(request.scheduler)
    ..flow_shift = stableDiffusionFlowShift(request.flowShift);
  if (request.hiresFix case final hires?) {
    params.ref.hires
      ..enabled = true
      ..upscaler = stableDiffusionHiresUpscaler(hires.upscaler)
      ..model_path = nullptr
      // The final size is resolved in Dart; a zero scale leaves the runtime
      // nothing to derive it from.
      ..scale = 0
      ..target_width = hires.width
      ..target_height = hires.height
      ..steps = hires.steps
      ..denoising_strength = hires.denoisingStrength
      ..custom_sigmas = nullptr
      ..custom_sigmas_count = 0;
  }
  final tiling = request.vaeTiling;
  if (tiling != null) {
    params.ref.vae_tiling_params
      ..enabled = true
      ..tile_size_w = tiling.tileWidth
      ..tile_size_h = tiling.tileHeight
      ..target_overlap = tiling.overlap
      // Positive relative sizes would override the tile sizes.
      ..rel_size_w = 0
      ..rel_size_h = 0;
  }
}

/// The runtime's sampler for [sampler]. `null` maps to
/// `SAMPLE_METHOD_COUNT`, which makes the runtime pick the model's default.
sd.sample_method_t stableDiffusionSampleMethod(
  ImageGenerationSampler? sampler,
) => switch (sampler) {
  null => sd.sample_method_t.SAMPLE_METHOD_COUNT,
  ImageGenerationSampler.euler => sd.sample_method_t.EULER_SAMPLE_METHOD,
  ImageGenerationSampler.eulerAncestral =>
    sd.sample_method_t.EULER_A_SAMPLE_METHOD,
  ImageGenerationSampler.dpmpp2m => sd.sample_method_t.DPMPP2M_SAMPLE_METHOD,
  ImageGenerationSampler.lcm => sd.sample_method_t.LCM_SAMPLE_METHOD,
};

/// The runtime's `ref_image_args` for [recipe].
String stableDiffusionReferencePreset(ImageReferenceEditingRecipe recipe) =>
    switch (recipe) {
      ImageReferenceEditingRecipe.fluxKontext => 'preset=flux_kontext',
    };

/// The runtime's hires upscaler for [upscaler].
sd.sd_hires_upscaler_t stableDiffusionHiresUpscaler(
  ImageHiresUpscaler upscaler,
) => switch (upscaler) {
  ImageHiresUpscaler.latent => sd.sd_hires_upscaler_t.SD_HIRES_UPSCALER_LATENT,
};

/// The runtime's scheduler for [scheduler]. `null` maps to
/// `SCHEDULER_COUNT`, which makes the runtime pick the default for the model
/// and sampler.
sd.scheduler_t stableDiffusionScheduler(ImageGenerationScheduler? scheduler) =>
    switch (scheduler) {
      null => sd.scheduler_t.SCHEDULER_COUNT,
      ImageGenerationScheduler.discrete => sd.scheduler_t.DISCRETE_SCHEDULER,
      ImageGenerationScheduler.karras => sd.scheduler_t.KARRAS_SCHEDULER,
      ImageGenerationScheduler.sgmUniform =>
        sd.scheduler_t.SGM_UNIFORM_SCHEDULER,
      ImageGenerationScheduler.simple => sd.scheduler_t.SIMPLE_SCHEDULER,
    };

/// The runtime's flow shift for [flowShift]. `null` maps to infinity, which
/// makes the runtime use the model's default.
double stableDiffusionFlowShift(double? flowShift) =>
    flowShift ?? double.infinity;
