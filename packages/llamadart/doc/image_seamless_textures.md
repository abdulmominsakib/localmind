# Seamless texture qualification

The initial supported profile is native-detected `SDXS (512-DS)` with a
header-detected embedded tiny decoder, no component overrides, 512×512, and
CPU or Metal with flash attention and direct VAE convolutions disabled.
`SeamlessImageGenerationRequest` preserves the original request interface;
its X/Y flags default to false. Unsupported recipes fail before task creation.
This is a bounded qualification for #1234, not general VAE tiling (#1400).

## Runtime and model identity

Requalified on stable-diffusion-native `v0.3.0-1` (2026-10-27): every result below is byte-identical to the `v0.3.0` measurement ([#922](https://github.com/leehack/llamadart/issues/922)).

Pinned stable-diffusion-native `v0.3.0-1`, owner
`54e97df3`, upstream `be486498eadc29dc3cd234d944c2180ed42b1415`.
The pinned macOS arm64 archive SHA-256 is
`79c3517b363e6509df17af4d20056ed6e47bbbd134681fb9321520702534cb40`.
The hook validates that archive; its installed dylib may be rewritten and
ad-hoc signed for the consumer path, so its hash need not equal the extracted
archive library. No native source, binding or pin changes are required.

| Weight file | SHA-256 |
| --- | --- |
| `sdxs-512-tinySDdistilled_Q8_0.gguf` | `409ab23582ee074c6b9d5395784fc0741b0599fb9d138686c69087c71678eb6a` |
| `sd_turbo-f16-q8_0.gguf` | `d50be7655f0a554cf8041c145d88b210bd5f3c545423119dee62ae08cae51580` |
| `taesd.safetensors` | `db169d69145ec4ff064e49d99c95fa05d3eb04ee453de35824a6d0f325513549` |

These are measured artifacts, not filename-based capability checks. Public
requests require both native family detection and actual decoder header
classification. An explicit checkpoint role cannot replace decoder evidence.

## Production call path

At the exact upstream revision:

- `sd_img_gen_params_t.circular_x/y` are bytes 540/541 of the 552-byte ABI.
- `src/pipeline/image.cpp` applies the request axes to diffusion and constructs
  `ImageVaeAxesGuard`. Its `configure_image_vae_axes` sets
  `first_stage_model` and `preview_vae` axes even when tiling is disabled.
- `src/core/ggml_runner.cpp` copies the runner axes into graph context;
  `src/model/common/ggml_block.hpp` consumes them in convolution padding.
- `src/model/vae/tae.hpp` and `auto_encoder_kl.hpp` use those convolutions.
  Ordinary untiled decode therefore honors axes; no VAE-tiling workaround is
  needed. Direct-C tiled/untiled SDXS outputs were byte-identical.
- Every new request sets both flags, including false, so the native pipeline
  clears an earlier request's axes. Existing guarded calls, Metal failure
  handling, explicit context mode strings and `batched_cfg=false` are retained.

Reading `VAE::decode` alone misses the caller's axes guard. The full call path
and the executed untiled comparison establish decoder behavior.

## Reproduce

Use Flutter 3.47.1 / Dart 3.13.1. Run workspace preparation on the clean
checkout first, then list and dry-run the maintained scenario:

```bash
dart run tool/prepare_workspace.dart
dart run tool/testing/run_local_e2e.dart --list
dart run tool/testing/run_local_e2e.dart --scenario image-seamless-textures \
  --model-path "$sdxs" --dry-run
```

For an independent direct-C reference, extract the checksum-verified pinned
macOS arm64 bundle into `$bundle`. Build the maintained C fixture from the
repository root (it populates upstream structs directly, uses the existing
exit-guarded wrappers, and calls no Dart parameter helper):

```bash
mkdir -p build/image-texture-native-reference
clang++ -std=c++17 \
  example/basic_app/test/fixtures/image_seamless_native_reference.cpp \
  -I"$bundle/include" -L"$bundle/lib" -lstable-diffusion \
  -Wl,-rpath,"$bundle/lib" -o build/image-texture-native-reference/reference
build/image-texture-native-reference/reference "$sdxs" cpu none \
  "$PWD/build/image-texture-native-reference/sdxs-cpu"
build/image-texture-native-reference/reference "$sdxs" gpu none \
  "$PWD/build/image-texture-native-reference/sdxs-metal"
LLAMADART_TEXTURE_NATIVE_REFERENCES="$PWD/build/image-texture-native-reference" \
  TMPDIR="$(mktemp -d)" dart run tool/testing/run_local_e2e.dart \
  --scenario image-seamless-textures --model-path "$sdxs"
```

The native fixture and public request use exactly the same prompt, seed 42,
512×512, 4 Euler/discrete steps, CFG 1, 4 CPU threads, explicit `off` context
modes, unbatched CFG, and ordinary untiled VAE. Modes are off, X, Y, XY, off.
This is a direct comparison to upstream's C settings in the pinned runtime,
not a separately built upstream CLI. Set `LLAMADART_TEXTURE_DEVICES=cpu` on
hosts without Metal; that provides CPU evidence only.

The suite saves `build/image-seamless-textures/{cpu,metal}-{0..4}.png`,
matching `*-repeat.png` 2×2 repeats, and per-backend JSON with raw pixel hashes,
seam MAE and interior MAE. When references are supplied every mode must match
its native RGB bytes exactly. It also checks dimensions, image variation,
off-after-on equality, mid-sampling cancellation and both ordinary and circular
reuse. Inspect the repeated PNGs visually; automated boundary metrics do not
measure texture suitability.

## Numerical and visual criteria

For each requested axis, the mean absolute RGB difference across the two
boundary rows/columns must be:

1. below 8 on the 0–255 intensity scale;
2. below 1.5 times that image's mean interior adjacent-pixel difference;
3. below 40% of the same prompt/seed's off result.

The fixed weathered-stone prompt is in both maintained fixtures. The
macOS arm64 M4 Max run on 2026-10-25 produced:

| Profile | Mode | X seam MAE | Y seam MAE |
| --- | --- | ---: | ---: |
| SDXS CPU | off | 15.322 | 11.609 |
| SDXS CPU | X | 3.158 | 11.042 |
| SDXS CPU | Y | 16.499 | 3.592 |
| SDXS CPU | XY | 2.800 | 2.920 |
| SDXS actual Metal (`MTL0`) | off | 15.057 | 11.438 |
| SDXS actual Metal (`MTL0`) | X | 3.213 | 10.895 |
| SDXS actual Metal (`MTL0`) | Y | 16.555 | 3.692 |
| SDXS actual Metal (`MTL0`) | XY | 2.856 | 2.958 |
| SD-Turbo full VAE CPU | off | 89.189 | 87.678 |
| SD-Turbo full VAE CPU | XY | 10.723 | 12.844 |
| SD-Turbo external TAESD CPU | off | 80.436 | 79.218 |
| SD-Turbo external TAESD CPU | XY | 11.305 | 12.826 |

SDXS passed all three criteria independently for X-only, Y-only and XY on
both devices. Its XY interior X/Y MAE was 2.713/2.919 on CPU and 2.758/2.980
on Metal. Both CPU and Metal 2×2 XY repeats were inspected: their center joins
showed no visible discontinuity. Off-after-on was byte-identical on each
device. CPU and Metal differ slightly and are compared separately.

| SDXS mode | CPU raw-pixel SHA-256 | Metal raw-pixel SHA-256 |
| --- | --- | --- |
| off (also off-after-on) | `c88ef6d0c65de206d7d61b33cd33cd9ea5515028307a3bb3fdd564ac83b4da76` | `015c0a25b099466513105b459a55769afcaa693306240dfb781ddcb8da53b390` |
| X | `fa971bfda4b8df22e0361ed619d4f9ab72fef145833fa2cdf86cc46fcee32439` | `cbed1db9a41f54ff87a0a8115d46d947456d789e151c35fcf6601ed25653a285` |
| Y | `633c42f34b774b7fc509ed6a51b25fe55fee0301600e11544d8fc78987ac3853` | `a8be1ae48715e479faaaedc54f67bf64a5b4b78514840309d14559efc2cf6317` |
| XY | `1053ed69d304d32b58ef6bf00d304995504c2e652dd55c0310f5a65907c5a46e` | `31d87f0c9a29e6facd4eea77827dcb325a7df7c24fd99cc3a39a266d43390faf` |

Both SD-Turbo decoders improved boundaries but failed the absolute gate on
this prompt/seed; they remain refused. This is not a claim that every
SD-Turbo texture is poor. Other families, decoder configurations, dimensions,
flash-attention/direct-convolution paths, mobile devices and other desktop
platforms were not qualified for seamless output. CPU/Metal support checks
must not be read as evidence for those platforms or arbitrary prompt quality.
