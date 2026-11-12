# Bounded hires-fix qualification

`HiresFixImageGenerationRequest` adds a second, refining pass to
text-to-image generation: the runtime samples the request's size, enlarges
each latent bilinearly (`ImageHiresUpscaler.latent`) to the `ImageHiresFix`
final size, adds noise for `denoisingStrength` and samples again at the final
size, then decodes the final latents. The admitted recipe is the pinned
stable-diffusion-native v0.3.0-1 runtime on macOS with the CPU or Metal and
one native-detected SD 1.x or SD 2.x checkpoint with a header-detected
embedded full VAE and no component overrides.

**Status: qualified** on macOS arm64 CPU and Metal with SD 1.5 and SD-Turbo
(2026-10-27; [measured results](#reproduce)). Only this recipe is admitted.

## Contract

| Rule | Value |
| --- | --- |
| Final size | `ImageHiresFix.scale` (> 1, ≤ 2) or `ImageHiresFix.size`; the two are separate constructors |
| Alignment | First-pass and final sides are multiples of 64; a scale that does not land on one is rejected, never rounded |
| Bounds | Each final side ≥ the first-pass side and ≤ twice it, final area > first-pass area, final ≤ 1024x1024 (1,048,576 px), `count` ≤ 4 |
| Second-pass steps | 1 to 150, default the first pass's; the runtime runs the tail of a `steps / denoisingStrength` schedule, which can be one step more |
| Strength | 0.05 to 1, default 0.7 (upstream's default) |
| Seeds | Image `i` uses `seed + i` in both passes (upstream re-seeds before each image's second pass) |
| Upscaler | Latent bilinear only; model, Lanczos and nearest upscalers are not offered |
| Combinations | Image editing, ControlNet, VAE tiling and circular axes cannot be combined with it (`LlamaUnsupportedException`) |
| Partial results | None: a cancelled or failed second pass returns no images |
| Final metadata | `GeneratedImage.width`/`height` report the final size; the engine fails a result of any other size |
| Progress | `ImageGenerationProgressEvent.pass` 0 then 1 (`passCount` 2); the second pass reports its own step total |

Validation errors (`LlamaImageGenerationException`) and recipe refusals
(`LlamaUnsupportedException`) are thrown before the task starts.

## Admission and runtime path

- Load: `hiresFixRecipeVerified` needs macOS, a CPU or Metal backend, the
  pinned runtime commit (`be48649`), and the header proof the image-editing
  recipe uses: one checkpoint with four latent channels and
  `first_stage_model.decoder.conv_in.weight`, no tiny autoencoder and no
  other component. `ImageGenerationCapabilities.supportsHiresFix` also needs
  the runtime to detect `SD 1.x` or `SD 2.x` and the session to report
  `ImageHiresFixSession.supportsHiresFix`; a session without the interface
  is refused.
- Kernel options: unlike image editing and ControlNet, the recipe admits
  any `flashAttention` and `vaeDirectConvolution`. Both passes run the
  sampling and decode kernels an ordinary request runs, so the options
  change hires output only as they change any request. With the defaults
  (flash attention on; direct convolution on for CPU, off for Metal),
  SD-Turbo `hires` differed from the direct-C reference with both off by
  MAE 0.09 on Metal and 1.12 on CPU, within the one-pass `base` and `final`
  differences under the same defaults (0.09–0.11 Metal, 1.18–1.55 CPU;
  2026-10-27, pinned runtime). Exact-RGB parity is checked with both off.
- Mapping: Dart resolves the final size, so `sd_img_gen_params_t.hires` gets
  `enabled`, `SD_HIRES_UPSCALER_LATENT`, `target_width`/`target_height`,
  `steps`, `denoising_strength`, `scale = 0`, no model path and no custom
  sigmas. Upstream `GenerationRequest::resolve_hires` would otherwise align
  the target up to a multiple of 64, or disable the pass with only a warning.
  Ordinary requests start from freshly initialized parameters, which leave
  the pass disabled.
- Native call: both passes run inside the guarded `sd_dart_generate_image`
  on the loaded context. Upstream `src/pipeline/image.cpp` checks the cancel
  flag before the second pass, before each image's latent upscale and before
  each sampling step, and frees the first-pass latents when the call
  returns. No new `sd_ctx_t` call, native object or callback is added; see
  `doc/llama_cpp_exit_teardown.md`, "Image models".
- Output check: the engine fails a task whose images do not have the final
  size, since upstream disables a hires pass it cannot apply with only a log
  warning and would return first-pass images as success.

## Reproduce

Prepare the clean checkout with the pinned SDK. Supply a local SD 1.x
checkpoint with its full VAE (SD 1.5 `v1-5-pruned-emaonly`) or an SD 2.x one
(SD-Turbo). Extract the checksum-verified pinned runtime bundle into
`$bundle`, then:

```bash
mkdir -p build/image-hires-fix-native-reference
clang++ -std=c++17 -O2 \
  example/basic_app/test/fixtures/image_hires_fix_native_reference.cpp \
  -I"$bundle/include" -L"$bundle/lib" -lstable-diffusion \
  -Wl,-rpath,"$bundle/lib" \
  -o build/image-hires-fix-native-reference/reference
for mode in base final hires; do
  /usr/bin/time -l build/image-hires-fix-native-reference/reference \
    "$checkpoint" cpu sd15 "$mode" \
    "$PWD/build/image-hires-fix-native-reference/sd15-cpu-$mode.ppm"
done
dart run tool/testing/run_local_e2e.dart --list
LLAMADART_HIRES_RECIPE=sd15 LLAMADART_HIRES_DEVICE=cpu \
  dart run tool/testing/run_local_e2e.dart \
  --scenario image-hires-fix --model-path "$checkpoint" --dry-run
LLAMADART_HIRES_RECIPE=sd15 LLAMADART_HIRES_DEVICE=cpu \
  LLAMADART_HIRES_NATIVE_REFERENCES="$PWD/build/image-hires-fix-native-reference" \
  TMPDIR="$(mktemp -d)" dart run tool/testing/run_local_e2e.dart \
  --scenario image-hires-fix --model-path "$checkpoint"
```

Use `gpu` for Metal and `turbo` for SD-Turbo in both the reference and the
environment. Both fixtures use the prompt "a red fox sitting in a snowy
forest, photograph", negative prompt "blurry", seed 42, Euler/discrete,
`flashAttention: false` and `vaeDirectConvolution: false` (`off` modes in C),
a 512x512 first pass and a 768x768 final size:

| Recipe | Steps | CFG | Hires steps | Strength |
| --- | --- | --- | --- | --- |
| `sd15` | 12 | 7 | 8 | 0.55 |
| `turbo` | 2 | 1 | 2 | 0.5 |

`base` is an ordinary 512x512 request, `final` an ordinary 768x768 request
and `hires` the two-pass request.

Fixed acceptance gates, recorded before any hires output was observed:

| Check | Required |
| --- | --- |
| Public Dart vs independent C, `base`, `final`, `hires` | Exact RGB |
| `ImageHiresFix.size(768, 768)` vs `ImageHiresFix.scale(1.5)` | Exact RGB |
| Ordinary request after hires requests | Exact `base` RGB |
| Hires vs bilinear-enlarged `base` | MAE > 1 (the second pass refines) |
| Downscaled hires vs `base`, against downscaled one-pass `final` vs `base` | Smaller (the first-pass composition is kept) |
| Second-pass progress | Pass 0 totals equal the steps; pass 1 events follow |
| Cancel in the second pass | Cancelled completion, then exact hires reuse |
| Dispose/reload | Capability cleared then restored; exact hires RGB |

Measured inputs (2026-10-27, Apple M4 Max, macOS 26.7.1, Flutter 3.47.1;
pinned runtime `stable-diffusion-native-runtime-macos-arm64-v0.3.0-1.tar.gz`,
SHA-256 `79c3517b363e6509df17af4d20056ed6e47bbbd134681fb9321520702534cb40`,
upstream `be486498eadc29dc3cd234d944c2180ed42b1415`):

| File | Source | SHA-256 |
| --- | --- | --- |
| `v1-5-pruned-emaonly.safetensors` (4.0 GB, F32) | `stable-diffusion-v1-5/stable-diffusion-v1-5` @ `451f4fe16113bff5a5d2269ed5ad43b0592e9a14` | `6ce0161689b3853acaa03779ec93eafe75a02f4ced659bee03f50797806fa2fa` |
| `sd_turbo-f16-q8_0.gguf` (1.9 GB) | as in [image editing](image_editing.md) | `d50be7655f0a554cf8041c145d88b210bd5f3c545423119dee62ae08cae51580` |

All gates passed on all four runs (`image-hires-fix`, `ComputeDevice.cpu`
with default threads and `ComputeDevice.gpu` = `MTL0`). Exact RGB matched
the direct-C reference for `base`, `final` and `hires` in every run, as did
size vs scale, reset, post-cancel reuse and reload.

| Run | Hires vs enlarged base MAE | Downscaled hires vs base MAE | Downscaled one-pass final vs base MAE | Second-pass steps reported |
| --- | --- | --- | --- | --- |
| SD 1.5, Metal | 20.15 | 20.30 | 58.69 | 8 (asked 8, strength 0.55) |
| SD 1.5, CPU | 20.14 | 20.28 | 58.56 | 8 (asked 8, strength 0.55) |
| SD-Turbo, Metal | 34.42 | 34.30 | 56.57 | 3 (asked 2, strength 0.5) |
| SD-Turbo, CPU | 34.56 | 34.44 | 56.64 | 3 (asked 2, strength 0.5) |

SD-Turbo's 3 second-pass steps for 2 asked are upstream's schedule
(`steps / strength` = 4, tail of `trunc(4 × 0.5) + 1` = 3); the C reference
reported the same totals. CPU and Metal hashes differ from each other, as
for every image recipe.

Latency from the Dart run (`ImageGenerationResult.elapsed`, model loaded,
no other load on the host):

| Run | `base` 512 | `final` 768 one-pass | `hires` 512 → 768 |
| --- | --- | --- | --- |
| SD 1.5, Metal | 23.4 s | 99.3 s | 88.9 s |
| SD 1.5, CPU | 57.8 s | 169.2 s | 166.9 s |
| SD-Turbo, Metal | 2.3 s | 5.5 s | 6.7 s |
| SD-Turbo, CPU | 10.8 s | 26.3 s | 33.9 s |

Peak memory of the direct-C reference, one process per mode
(`/usr/bin/time -l` peak memory footprint; it leaves out Metal compute
buffers):

| Run | `base` | `final` | `hires` |
| --- | --- | --- | --- |
| SD 1.5, Metal | 5.30 GB | 5.30 GB | 5.33 GB |
| SD 1.5, CPU | 4.74 GB | 6.93 GB | 6.93 GB |
| SD-Turbo, Metal | 3.11 GB | 3.11 GB | 3.13 GB |
| SD-Turbo, CPU | 3.86 GB | 6.05 GB | 6.06 GB |

The second pass costs what an ordinary generation at the final size costs:
peak memory matches the one-pass `final` within 0.03 GB, and hires latency
is about the first pass plus a final-size pass of the second-pass steps. Memory checks at load use
the model's weights, as for every request size.

Other families (SDXL and newer), tiny decoders, component overrides, LoRA,
iOS/Android/Linux/Windows/Web, Vulkan, model-based upscalers and custom
sigmas remain unqualified or refused.
