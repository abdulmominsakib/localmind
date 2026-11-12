@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_bindings.dart'
    as sd;
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_params.dart';
import 'package:llamadart/src/core/image/image_generation_driver.dart';
import 'package:llamadart/src/core/image/image_editing_request.dart';
import 'package:llamadart/src/core/image/image_generation_model.dart';
import 'package:llamadart/src/core/image/image_generation_request.dart';
import 'package:llamadart/src/core/image/image_hires_fix_request.dart';
import 'package:llamadart/src/core/image/image_reference_editing_request.dart';
import 'package:llamadart/src/core/image/image_model_params.dart';

String? _text(Pointer<Char> value) =>
    value == nullptr ? null : value.cast<Utf8>().toDartString();

void main() {
  group('applyStableDiffusionContextParams', () {
    Pointer<sd.sd_ctx_params_t> apply(
      Arena arena,
      ImageGenerationSessionConfig config,
    ) {
      final params = arena<sd.sd_ctx_params_t>();
      applyStableDiffusionContextParams(params, config, arena);
      return params;
    }

    for (final capacity in [
      null,
      0,
      1,
      ImageConditioningCacheParams.maxCapacity,
    ]) {
      test(
        'maps conditioning capacity $capacity after runtime initialization',
        () {
          using((arena) {
            final params = arena<sd.sd_ctx_params_t>();
            // A distinctive initialized value proves null does not hardcode 4.
            params.ref.conditioning_cache_size = 17;
            applyStableDiffusionContextParams(
              params,
              ImageGenerationSessionConfig(
                files: const {'model': '/m/sdxs.gguf'},
                backend: null,
                threads: 0,
                conditioningCacheSize: capacity,
              ),
              arena,
            );
            expect(params.ref.conditioning_cache_size, capacity ?? 17);
          });
        },
      );
    }

    test('keeps the runtime GPU budget and fit by default, and maps '
        'placement over them', () {
      using((arena) {
        ImageGenerationSessionConfig config({
          String? backend,
          int? maxGpuMemoryGiB,
          bool autoFit = true,
        }) => ImageGenerationSessionConfig(
          files: const {'model': '/m/sdxs.gguf'},
          backend: backend,
          threads: 0,
          maxGpuMemoryGiB: maxGpuMemoryGiB,
          autoFit: autoFit,
        );
        Pointer<sd.sd_ctx_params_t> initialized() {
          final params = arena<sd.sd_ctx_params_t>();
          params.ref
            ..auto_fit = true
            ..max_vram = nullptr;
          return params;
        }

        final defaults = initialized();
        applyStableDiffusionContextParams(defaults, config(), arena);
        expect(defaults.ref.max_vram, nullptr);
        expect(defaults.ref.auto_fit, isTrue);
        expect(_text(defaults.ref.backend), isNull);

        final placed = initialized();
        applyStableDiffusionContextParams(
          placed,
          config(backend: 'gpu,te=cpu,vae=cpu', maxGpuMemoryGiB: 12),
          arena,
        );
        expect(_text(placed.ref.max_vram), '12');
        expect(placed.ref.auto_fit, isTrue);
        expect(_text(placed.ref.backend), 'gpu,te=cpu,vae=cpu');
        expect(placed.ref.params_backend, nullptr);

        final unfitted = initialized();
        applyStableDiffusionContextParams(
          unfitted,
          config(autoFit: false),
          arena,
        );
        expect(unfitted.ref.auto_fit, isFalse);
        expect(unfitted.ref.max_vram, nullptr);
      });
    });

    test('writes every file role to its own path field', () {
      using((arena) {
        final params = apply(
          arena,
          const ImageGenerationSessionConfig(
            files: {
              'model': '/m/model.gguf',
              'diffusionModel': '/m/diffusion.gguf',
              'vae': '/m/vae.safetensors',
              'taesd': '/m/taesd.safetensors',
              'clipL': '/m/clip_l.gguf',
              'clipG': '/m/clip_g.gguf',
              't5xxl': '/m/t5xxl.gguf',
              'llm': '/m/qwen3.gguf',
              'controlNet': '/m/control_sd15_canny.safetensors',
            },
            backend: 'gpu',
            threads: 6,
          ),
        ).ref;

        expect(_text(params.model_path), '/m/model.gguf');
        expect(_text(params.diffusion_model_path), '/m/diffusion.gguf');
        expect(_text(params.vae_path), '/m/vae.safetensors');
        expect(_text(params.taesd_path), '/m/taesd.safetensors');
        expect(_text(params.clip_l_path), '/m/clip_l.gguf');
        expect(_text(params.clip_g_path), '/m/clip_g.gguf');
        expect(_text(params.t5xxl_path), '/m/t5xxl.gguf');
        expect(_text(params.llm_path), '/m/qwen3.gguf');
        expect(
          _text(params.control_net_path),
          '/m/control_sd15_canny.safetensors',
        );
        expect(_text(params.backend), 'gpu');
        expect(params.n_threads, 6);
        expect(params.eager_load, isTrue);
      });
    });

    // The memory check of a Vulkan GPU admits a model larger than the GPU
    // because the runtime's automatic fit keeps the rest in host memory.
    // The fit is off when auto_fit is false or a params backend is named.
    test('leaves the automatic fit as the runtime initialized it, for a '
        'named and an unnamed backend', () {
      for (final backend in [null, 'gpu', 'cpu']) {
        using((arena) {
          final params = arena<sd.sd_ctx_params_t>();
          params.ref.auto_fit = true;
          applyStableDiffusionContextParams(
            params,
            ImageGenerationSessionConfig(
              files: const {'model': '/m/sdxs.gguf'},
              backend: backend,
              threads: 0,
            ),
            arena,
          );

          expect(params.ref.auto_fit, isTrue, reason: '$backend');
          expect(params.ref.params_backend, nullptr, reason: '$backend');
          expect(params.ref.max_vram, nullptr, reason: '$backend');
        });
      }
    });

    test('leaves unset roles, backend and threads at their defaults', () {
      using((arena) {
        final params = arena<sd.sd_ctx_params_t>();
        params.ref.n_threads = -1;
        applyStableDiffusionContextParams(
          params,
          const ImageGenerationSessionConfig(
            files: {'model': '/m/sdxs.gguf'},
            backend: null,
            threads: 0,
          ),
          arena,
        );

        expect(_text(params.ref.model_path), '/m/sdxs.gguf');
        for (final field in [
          params.ref.diffusion_model_path,
          params.ref.vae_path,
          params.ref.taesd_path,
          params.ref.clip_l_path,
          params.ref.clip_g_path,
          params.ref.t5xxl_path,
          params.ref.llm_path,
          params.ref.control_net_path,
          params.ref.backend,
        ]) {
          expect(field, nullptr);
        }
        expect(params.ref.n_threads, -1);
      });
    });

    test('writes flash attention and direct VAE convolutions to their own '
        'fields', () {
      using((arena) {
        for (final (flashAttention, vaeDirectConvolution) in [
          (true, false),
          (false, true),
          (true, true),
          (false, false),
        ]) {
          final params = apply(
            arena,
            ImageGenerationSessionConfig(
              files: const {'model': '/m/sdxs.gguf'},
              backend: null,
              threads: 0,
              flashAttention: flashAttention,
              vaeDirectConvolution: vaeDirectConvolution,
            ),
          ).ref;

          final reason = 'fa $flashAttention, vcd $vaeDirectConvolution';
          expect(params.diffusion_flash_attn, flashAttention, reason: reason);
          expect(params.vae_conv_direct, vaeDirectConvolution, reason: reason);
          expect(params.flash_attn, isFalse, reason: reason);
          expect(params.diffusion_conv_direct, isFalse, reason: reason);
        }
      });
    });

    // A null or empty mode makes stable-diffusion.cpp probe each module and
    // pick flash attention and direct convolution itself, which changes
    // images and is not seed-reproducible on Metal.
    test('always writes explicit flash attention and direct convolution '
        'modes', () {
      using((arena) {
        for (final (flashAttention, vaeDirectConvolution, flash, conv) in [
          (false, false, 'off', 'off'),
          (true, false, 'off,diffusion=on', 'off'),
          (false, true, 'off', 'off,vae=on'),
          (true, true, 'off,diffusion=on', 'off,vae=on'),
        ]) {
          final params = apply(
            arena,
            ImageGenerationSessionConfig(
              files: const {'model': '/m/sdxs.gguf'},
              backend: null,
              threads: 0,
              flashAttention: flashAttention,
              vaeDirectConvolution: vaeDirectConvolution,
            ),
          ).ref;

          final reason = 'fa $flashAttention, vcd $vaeDirectConvolution';
          expect(_text(params.flash_attn_mode), flash, reason: reason);
          expect(_text(params.conv_direct_mode), conv, reason: reason);
        }
      });
    });

    test('maps the runtime-wide legacy flags it does not set itself', () {
      using((arena) {
        final params = arena<sd.sd_ctx_params_t>();
        params.ref
          ..flash_attn = true
          ..diffusion_conv_direct = true;
        applyStableDiffusionContextParams(
          params,
          const ImageGenerationSessionConfig(
            files: {'model': '/m/sdxs.gguf'},
            backend: null,
            threads: 0,
            vaeDirectConvolution: true,
          ),
          arena,
        );

        expect(
          _text(params.ref.flash_attn_mode),
          'off,te=on,clip_vision=on,vae=on,diffusion=on',
        );
        expect(
          _text(params.ref.conv_direct_mode),
          'off,diffusion=on,control_net=on,vae=on',
        );
      });
    });

    // Batched CFG returns wrong images as success on Metal
    // (leejet/stable-diffusion.cpp#2149) and is unqualified on other GPUs.
    test('runs the CFG branches unbatched although the runtime default '
        'batches them', () {
      using((arena) {
        final params = arena<sd.sd_ctx_params_t>();
        params.ref.batched_cfg = true;
        applyStableDiffusionContextParams(
          params,
          const ImageGenerationSessionConfig(
            files: {'model': '/m/sdxs.gguf'},
            backend: null,
            threads: 0,
          ),
          arena,
        );

        expect(params.ref.batched_cfg, isFalse);
      });
    });
  });

  test('flash attention modes follow the legacy flags', () {
    expect(
      {
        for (final all in [false, true])
          for (final diffusion in [false, true])
            (all, diffusion): stableDiffusionFlashAttentionMode(
              all: all,
              diffusion: diffusion,
            ),
      },
      {
        (false, false): 'off',
        (false, true): 'off,diffusion=on',
        (true, false): 'off,te=on,clip_vision=on,vae=on,diffusion=on',
        (true, true): 'off,te=on,clip_vision=on,vae=on,diffusion=on',
      },
    );
  });

  test('direct convolution modes follow the legacy flags', () {
    expect(
      {
        for (final diffusion in [false, true])
          for (final vae in [false, true])
            (diffusion, vae): stableDiffusionConvDirectMode(
              diffusion: diffusion,
              vae: vae,
            ),
      },
      {
        (false, false): 'off',
        (false, true): 'off,vae=on',
        (true, false): 'off,diffusion=on,control_net=on',
        (true, true): 'off,diffusion=on,control_net=on,vae=on',
      },
    );
  });

  // sd_ctx_params_init writes the whole struct of the pinned runtime, so a
  // shorter Dart allocation would be overrun.
  test('the bound structs match the pinned runtime layout', () {
    expect(sizeOf<sd.sd_ctx_params_t>(), 336);
    expect(sizeOf<sd.sd_img_gen_params_t>(), 552);
    expect(sizeOf<sd.sd_sample_params_t>(), 96);
    expect(sizeOf<sd.sd_image_t>(), 24);
    expect(sizeOf<sd.sd_tiling_params_t>(), 32);
  }, testOn: 'mac-os || linux');

  test('VAE tiling fields sit at the pinned runtime\'s offsets', () {
    using((arena) {
      final params = arena<sd.sd_img_gen_params_t>();
      params.ref.vae_tiling_params
        ..enabled = true
        ..tile_size_w = 0x01020304
        ..target_overlap = 0.25
        ..rel_size_w = 0.75;
      final bytes = params.cast<Uint8>().asTypedList(
        sizeOf<sd.sd_img_gen_params_t>(),
      );
      final data = ByteData.sublistView(bytes);

      // offsetof in stable-diffusion.h: vae_tiling_params at 352, and in it
      // tile_size_w at 4, target_overlap at 12 and rel_size_w at 16.
      expect(bytes[352], 1);
      expect(data.getInt32(356, Endian.host), 0x01020304);
      expect(data.getFloat32(364, Endian.host), 0.25);
      expect(data.getFloat32(368, Endian.host), 0.75);
    });
  }, testOn: 'mac-os || linux');

  test(
    'editing pixels strength and binary mask reach native struct with owned copies',
    () {
      final rgb = Uint8List.fromList(
        List.generate(128 * 64 * 3, (i) => i % 256),
      );
      final mask = Uint8List(128 * 64)..fillRange(4096, 8192, 255);
      final image = ImageEditingPixels.rgb(width: 128, height: 64, pixels: rgb);
      final inputMask = ImageEditingPixels.mask(
        width: 128,
        height: 64,
        pixels: mask,
      );
      rgb.fillRange(0, rgb.length, 0);
      mask.fillRange(0, mask.length, 0);
      using((arena) {
        final params = arena<sd.sd_img_gen_params_t>();
        applyStableDiffusionGenerationParams(
          params,
          ImageGenerationSessionRequest(
            prompt: 'edit',
            negativePrompt: '',
            width: 128,
            height: 64,
            steps: 4,
            guidanceScale: 1,
            seed: 42,
            count: 1,
            initialImage: image,
            mask: inputMask,
            strength: 0.625,
          ),
          arena,
        );
        final input = params.ref.init_image;
        final mappedMask = params.ref.mask_image;
        expect((input.width, input.height, input.channel), (128, 64, 3));
        expect(input.data.asTypedList(128 * 64 * 3), image.pixels);
        expect(
          (mappedMask.width, mappedMask.height, mappedMask.channel),
          (128, 64, 1),
        );
        expect(mappedMask.data.asTypedList(128 * 64), inputMask.pixels);
        expect(params.ref.strength, closeTo(0.625, 0.000001));
        image.pixels[0] = 99;
        expect(input.data[0], 0);
      });
      using((arena) {
        final params = arena<sd.sd_img_gen_params_t>();
        params.ref.strength = 0.42;
        applyStableDiffusionGenerationParams(
          params,
          const ImageGenerationSessionRequest(
            prompt: 'plain',
            negativePrompt: '',
            width: 64,
            height: 64,
            steps: 1,
            guidanceScale: 1,
            seed: 42,
            count: 1,
          ),
          arena,
        );
        expect(params.ref.init_image.data, nullptr);
        expect(params.ref.mask_image.data, nullptr);
        expect(params.ref.strength, closeTo(0.42, 0.000001));
      });
    },
  );

  test('ControlNet image and strength reach the native struct as copies', () {
    final rgb = Uint8List.fromList(List.generate(128 * 64 * 3, (i) => i % 253));
    final control = ImageEditingPixels.rgb(width: 128, height: 64, pixels: rgb);
    rgb.fillRange(0, rgb.length, 0);
    using((arena) {
      final params = arena<sd.sd_img_gen_params_t>();
      applyStableDiffusionGenerationParams(
        params,
        ImageGenerationSessionRequest(
          prompt: 'a house',
          negativePrompt: '',
          width: 128,
          height: 64,
          steps: 4,
          guidanceScale: 7,
          seed: 42,
          count: 1,
          controlImage: control,
          controlStrength: 1.25,
        ),
        arena,
      );
      final mapped = params.ref.control_image;
      expect((mapped.width, mapped.height, mapped.channel), (128, 64, 3));
      expect(mapped.data.asTypedList(128 * 64 * 3), control.pixels);
      expect(params.ref.control_strength, closeTo(1.25, 0.000001));
      expect(params.ref.init_image.data, nullptr);
      control.pixels[0] = 99;
      expect(mapped.data[0], 0);
    });
    using((arena) {
      final params = arena<sd.sd_img_gen_params_t>();
      params.ref.control_strength = 0.9;
      applyStableDiffusionGenerationParams(
        params,
        const ImageGenerationSessionRequest(
          prompt: 'plain',
          negativePrompt: '',
          width: 64,
          height: 64,
          steps: 1,
          guidanceScale: 1,
          seed: 42,
          count: 1,
        ),
        arena,
      );
      expect(params.ref.control_image.data, nullptr);
      expect(params.ref.control_strength, closeTo(0.9, 0.000001));
    });
  });

  test('a hires fix writes its resolved final size, steps, strength and '
      'latent upscaler at the runtime ABI offsets, and an ordinary request '
      'leaves the initialized hires defaults', () {
    using((arena) {
      final params = arena<sd.sd_img_gen_params_t>();
      params.ref.hires
        ..scale = 2
        ..denoising_strength = 0.7
        ..upscale_tile_size = 128;
      applyStableDiffusionGenerationParams(
        params,
        const ImageGenerationSessionRequest(
          prompt: 'a fox',
          negativePrompt: '',
          width: 512,
          height: 384,
          steps: 20,
          guidanceScale: 7,
          seed: 42,
          count: 1,
          hiresFix: ImageGenerationSessionHiresFix(
            width: 768,
            height: 576,
            steps: 12,
            denoisingStrength: 0.45,
            upscaler: ImageHiresUpscaler.latent,
          ),
        ),
        arena,
      );
      final hires = params.ref.hires;
      expect(hires.enabled, isTrue);
      expect(hires.upscaler, sd.sd_hires_upscaler_t.SD_HIRES_UPSCALER_LATENT);
      expect(hires.model_path, nullptr);
      expect(hires.scale, 0);
      expect((hires.target_width, hires.target_height), (768, 576));
      expect(hires.steps, 12);
      expect(hires.denoising_strength, closeTo(0.45, 0.000001));
      expect(hires.upscale_tile_size, 128);
      expect((hires.custom_sigmas, hires.custom_sigmas_count), (nullptr, 0));
      expect((params.ref.width, params.ref.height), (512, 384));
      expect(params.ref.sample_params.sample_steps, 20);
      // offsetof(sd_img_gen_params_t, hires.*) in the pinned v0.3.0-1
      // stable-diffusion.h on arm64 and x86_64.
      final bytes = params.cast<Uint8>().asTypedList(
        sizeOf<sd.sd_img_gen_params_t>(),
      );
      final words = ByteData.sublistView(bytes);
      expect(bytes[480], 1);
      expect(words.getUint32(484, Endian.host), 1);
      expect(words.getInt32(500, Endian.host), 768);
      expect(words.getInt32(504, Endian.host), 576);
      expect(words.getInt32(508, Endian.host), 12);
    });
    using((arena) {
      final params = arena<sd.sd_img_gen_params_t>();
      params.ref.hires
        ..upscaler = sd.sd_hires_upscaler_t.SD_HIRES_UPSCALER_LATENT
        ..scale = 2
        ..denoising_strength = 0.7;
      applyStableDiffusionGenerationParams(
        params,
        const ImageGenerationSessionRequest(
          prompt: 'a fox',
          negativePrompt: '',
          width: 512,
          height: 512,
          steps: 20,
          guidanceScale: 7,
          seed: 42,
          count: 1,
        ),
        arena,
      );
      final hires = params.ref.hires;
      expect(hires.enabled, isFalse);
      expect(hires.scale, 2);
      expect((hires.target_width, hires.target_height, hires.steps), (0, 0, 0));
      expect(hires.denoising_strength, closeTo(0.7, 0.000001));
    });
  });

  test('references are written in order with the recipe preset at the '
      'runtime ABI offsets, and an ordinary request leaves none', () {
    ImageEditingPixels rgb(int value) => ImageEditingPixels.rgb(
      width: 64,
      height: 128,
      pixels: Uint8List(64 * 128 * 3)..fillRange(0, 3, value),
    );
    ImageGenerationSessionRequest request([
      List<ImageEditingPixels>? references,
    ]) => ImageGenerationSessionRequest(
      prompt: 'make the fox blue',
      negativePrompt: '',
      width: 64,
      height: 128,
      steps: 4,
      guidanceScale: 1,
      seed: 42,
      count: 1,
      references: references,
      referenceRecipe: references == null
          ? null
          : ImageReferenceEditingRecipe.fluxKontext,
    );
    using((arena) {
      final params = arena<sd.sd_img_gen_params_t>();
      applyStableDiffusionGenerationParams(
        params,
        request([rgb(3), rgb(9)]),
        arena,
      );
      final references = params.ref.ref_images;
      expect(params.ref.ref_images_count, 2);
      expect(
        [
          for (var i = 0; i < 2; i++)
            (
              references[i].width,
              references[i].height,
              references[i].channel,
              references[i].data[2],
            ),
        ],
        [(64, 128, 3, 3), (64, 128, 3, 9)],
      );
      expect(_text(params.ref.ref_image_args), 'preset=flux_kontext');
      expect(params.ref.init_image.data, nullptr);
      // offsetof(sd_img_gen_params_t, ref_images / ref_images_count /
      // ref_image_args) in the pinned v0.3.0-1 stable-diffusion.h on arm64
      // and x86_64.
      final words = ByteData.sublistView(
        params.cast<Uint8>().asTypedList(sizeOf<sd.sd_img_gen_params_t>()),
      );
      expect(words.getUint64(64, Endian.host), references.address);
      expect(words.getInt32(72, Endian.host), 2);
      expect(
        words.getUint64(80, Endian.host),
        params.ref.ref_image_args.address,
      );
    });
    using((arena) {
      final params = arena<sd.sd_img_gen_params_t>();
      applyStableDiffusionGenerationParams(params, request(), arena);
      expect(params.ref.ref_images, nullptr);
      expect(params.ref.ref_images_count, 0);
      expect(params.ref.ref_image_args, nullptr);
    });
  });

  test('every reference recipe maps to its runtime preset', () {
    expect(
      {
        for (final recipe in ImageReferenceEditingRecipe.values)
          recipe: stableDiffusionReferencePreset(recipe),
      },
      {ImageReferenceEditingRecipe.fluxKontext: 'preset=flux_kontext'},
    );
  });

  test('every hires upscaler maps to its runtime value', () {
    expect(
      {
        for (final upscaler in ImageHiresUpscaler.values)
          upscaler: stableDiffusionHiresUpscaler(upscaler),
      },
      {
        ImageHiresUpscaler.latent:
            sd.sd_hires_upscaler_t.SD_HIRES_UPSCALER_LATENT,
      },
    );
  });

  group('applyStableDiffusionGenerationParams', () {
    const request = ImageGenerationSessionRequest(
      prompt: 'a fox',
      negativePrompt: 'blurry',
      width: 1024,
      height: 768,
      steps: 4,
      guidanceScale: 1.5,
      seed: 42,
      count: 2,
    );

    for (final (x, y) in [
      (false, false),
      (true, false),
      (false, true),
      (true, true),
    ]) {
      test('maps circular axes $x/$y without changing decoder tiling', () {
        using((arena) {
          final params = arena<sd.sd_img_gen_params_t>();
          params.ref.vae_tiling_params.target_overlap = 0.37;
          applyStableDiffusionGenerationParams(
            params,
            ImageGenerationSessionRequest(
              prompt: 'stone',
              negativePrompt: '',
              width: 512,
              height: 512,
              steps: 4,
              guidanceScale: 1,
              seed: 42,
              count: 1,
              circularX: x,
              circularY: y,
            ),
            arena,
          );
          expect(params.ref.circular_x, x);
          expect(params.ref.circular_y, y);
          final bytes = params.cast<Uint8>().asTypedList(
            sizeOf<sd.sd_img_gen_params_t>(),
          );
          expect(bytes[540], x ? 1 : 0);
          expect(bytes[541], y ? 1 : 0);
          expect(params.ref.vae_tiling_params.enabled, isFalse);
          expect(params.ref.vae_tiling_params.rel_size_w, 0);
          expect(params.ref.vae_tiling_params.rel_size_h, 0);
          expect(
            params.ref.vae_tiling_params.target_overlap,
            closeTo(0.37, 0.00001),
          );
        });
      });
    }

    test('writes the prompt, size, seed, count, steps and guidance', () {
      using((arena) {
        final params = arena<sd.sd_img_gen_params_t>();
        applyStableDiffusionGenerationParams(params, request, arena);

        expect(_text(params.ref.prompt), 'a fox');
        expect(_text(params.ref.negative_prompt), 'blurry');
        expect((params.ref.width, params.ref.height), (1024, 768));
        expect(params.ref.seed, 42);
        expect(params.ref.batch_count, 2);
        expect(params.ref.sample_params.sample_steps, 4);
        expect(params.ref.sample_params.guidance.txt_cfg, 1.5);
      });
    });

    test('an unset sampler, scheduler and flow shift ask the runtime for '
        'its defaults', () {
      using((arena) {
        final params = arena<sd.sd_img_gen_params_t>();
        applyStableDiffusionGenerationParams(params, request, arena);

        final sample = params.ref.sample_params;
        expect(sample.sample_methodAsInt, 21);
        expect(sample.schedulerAsInt, 17);
        expect(sample.flow_shift, double.infinity);
      });
    });

    test('writes a set sampler, scheduler and flow shift', () {
      using((arena) {
        final params = arena<sd.sd_img_gen_params_t>();
        applyStableDiffusionGenerationParams(
          params,
          const ImageGenerationSessionRequest(
            prompt: 'a fox',
            negativePrompt: '',
            width: 512,
            height: 512,
            steps: 4,
            guidanceScale: 1,
            seed: 0,
            count: 1,
            sampler: ImageGenerationSampler.euler,
            scheduler: ImageGenerationScheduler.sgmUniform,
            flowShift: 3,
          ),
          arena,
        );

        final sample = params.ref.sample_params;
        expect(sample.sample_methodAsInt, 0);
        expect(sample.schedulerAsInt, 5);
        expect(sample.flow_shift, 3);
      });
    });
  });

  group('VAE tiling', () {
    ImageGenerationSessionRequest request([ImageVaeTiling? tiling]) =>
        ImageGenerationSessionRequest(
          prompt: 'a fox',
          negativePrompt: '',
          width: 1024,
          height: 768,
          steps: 1,
          guidanceScale: 1,
          seed: 0,
          count: 1,
          vaeTiling: tiling,
        );

    test('an unset request leaves the runtime\'s defaults, which decode the '
        'whole image', () {
      using((arena) {
        final params = arena<sd.sd_img_gen_params_t>();
        params.ref.vae_tiling_params
          ..enabled = false
          ..tile_size_w = 0
          ..tile_size_h = 0
          ..target_overlap = 0.5
          ..rel_size_w = 0.25;
        applyStableDiffusionGenerationParams(params, request(), arena);

        final tiling = params.ref.vae_tiling_params;
        expect(tiling.enabled, isFalse);
        expect((tiling.tile_size_w, tiling.tile_size_h), (0, 0));
        expect(tiling.target_overlap, 0.5);
        expect(tiling.rel_size_w, 0.25);
      });
    });

    test('writes the tile size and overlap, enables spatial tiling only, and '
        'clears the relative sizes', () {
      using((arena) {
        final params = arena<sd.sd_img_gen_params_t>();
        params.ref.vae_tiling_params
          ..rel_size_w = 0.25
          ..rel_size_h = 3;
        applyStableDiffusionGenerationParams(
          params,
          request(
            const ImageVaeTiling(
              tileWidth: 320,
              tileHeight: 192,
              overlap: 0.25,
            ),
          ),
          arena,
        );

        final tiling = params.ref.vae_tiling_params;
        expect(tiling.enabled, isTrue);
        expect(tiling.temporal_tiling, isFalse);
        expect((tiling.tile_size_w, tiling.tile_size_h), (320, 192));
        expect(tiling.target_overlap, 0.25);
        expect((tiling.rel_size_w, tiling.rel_size_h), (0, 0));
        expect(tiling.extra_tiling_args, nullptr);
      });
    });
  });

  test('samplers map to stable-diffusion.h sample_method_t values', () {
    expect(
      {
        for (final sampler in [null, ...ImageGenerationSampler.values])
          sampler?.name: stableDiffusionSampleMethod(sampler).value,
      },
      {null: 21, 'euler': 0, 'eulerAncestral': 1, 'dpmpp2m': 5, 'lcm': 9},
    );
  });

  test('schedulers map to stable-diffusion.h scheduler_t values', () {
    expect(
      {
        for (final scheduler in [null, ...ImageGenerationScheduler.values])
          scheduler?.name: stableDiffusionScheduler(scheduler).value,
      },
      {null: 17, 'discrete': 0, 'karras': 1, 'sgmUniform': 5, 'simple': 6},
    );
  });

  test('an unset flow shift is infinity, the runtime default', () {
    expect(stableDiffusionFlowShift(null), double.infinity);
    expect(stableDiffusionFlowShift(3), 3);
  });
}
