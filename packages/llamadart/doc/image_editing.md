# Bounded image editing qualification

`ImageEditingRequest` adds copied decoded RGB input, optional binary mask and
strength while preserving `ImageGenerationRequest`. The supported recipe is
native-detected SD 2.x, a header-detected embedded full VAE in a single
checkpoint, macOS CPU, pinned stable-diffusion-native v0.3.0-1, flash attention
and direct VAE convolution off. No components, tiny decoder, circular axes or
VAE tiling. Other matching SD 2.x checkpoints are source-compatible but
unmeasured; measured evidence below is SD-Turbo only. The accepted pixel
contract is aligned multiples of 64 in 64..2048; only 256 square is measured
here. This is not an arbitrary prompt-quality or all-resolution guarantee.

## Identity and production path

Requalified on stable-diffusion-native `v0.3.0-1` (2026-10-27): every result below is byte-identical to the `v0.3.0` measurement ([#922](https://github.com/leehack/llamadart/issues/922)).

- Runtime archive: `stable-diffusion-native-runtime-macos-arm64-v0.3.0-1.tar.gz`,
  SHA-256 `79c3517b363e6509df17af4d20056ed6e47bbbd134681fb9321520702534cb40`.
  The bundle build-info pins upstream
  `be486498eadc29dc3cd234d944c2180ed42b1415`; the runtime version string is
  `unknown`. Archive provenance and the reported version are distinct.
- Model: `sd_turbo-f16-q8_0.gguf`, SHA-256
  `d50be7655f0a554cf8041c145d88b210bd5f3c545423119dee62ae08cae51580`.
- SDK: Flutter 3.47.1 / Dart 3.13.1; measured on macOS arm64 CPU.
- The API owns a copy, the isolate transports the owned pixels, and
  `applyStableDiffusionGenerationParams` allocates RGB/mask bytes in the
  request arena. That arena outlives the existing guarded
  `sd_dart_generate_image` call, including cancellation. Ordinary requests
  start from freshly initialized native parameters.
- At the pinned revision, `src/pipeline/image.cpp::prepare_image_generation_latents` encodes
  `init_image`, rounds the mask and defaults an absent mask to ones. It
  scales the schedule by strength (with step rounding), resizes the mask
  into latent space and passes it to sampling. `src/pipeline/diffusion_engine.cpp`
  blends the generated latent with the original using that denoise mask.
  White means edit, black means preserve the latent. Decode can change
  pixels and bleed across the mask boundary. No codec, resize, alpha or
  pixel-compositing operation is added in Dart.

## Reproduce

Prepare the clean checkout with the pinned SDK first. Supply existing local
weights and the checksum-verified pinned runtime bundle; no weight download
is part of this scenario. Extract the bundle into `$bundle`, then run:

```bash
mkdir -p build/image-editing-native-reference
clang++ -std=c++17 \
  example/basic_app/test/fixtures/image_editing_native_reference.cpp \
  -I"$bundle/include" -L"$bundle/lib" -lstable-diffusion \
  -Wl,-rpath,"$bundle/lib" \
  -o build/image-editing-native-reference/reference
build/image-editing-native-reference/reference "$sd_turbo" \
  "$PWD/build/image-editing-native-reference/edit"
dart run tool/testing/run_local_e2e.dart --list
dart run tool/testing/run_local_e2e.dart --scenario image-editing \
  --model-path "$sd_turbo" --dry-run
LLAMADART_EDITING_NATIVE_REFERENCES="$PWD/build/image-editing-native-reference" \
  TMPDIR="$(mktemp -d)" dart run tool/testing/run_local_e2e.dart \
  --scenario image-editing --model-path "$sd_turbo"
```

The maintained C fixture fills upstream structs directly and calls the
existing guarded runtime wrapper; it shares no Dart mapper. This checks the
published pinned runtime, not a separately rebuilt upstream CLI. Installed
native-assets libraries may have rewritten install names and signatures;
the archive hash identifies the release artifact.

Both fixtures use synthetic RGB checker/gradient input, the same house prompt,
256 square, CPU4, Euler/discrete4steps/CFG1/seed42. Modes are ordinary text,
unmasked strength1, unmasked .5, all-white, all-black, left-white, ordinary
text reset. References are optional for local diagnostics; qualification
requires all seven exact RGB comparisons. Output PNGs and raw-pixel hashes
are saved to `build/image-editing` for inspection.

## Fixed acceptance gates and measured result

The gates were recorded before observing outputs; they were not tuned after
measurement. MAE uses the 0..255 RGB scale and excludes a 32px band around
the mask's center boundary.

| Check | Required | macOS arm64 CPU result |
| --- | --- | --- |
| Public Dart vs independent C | Exact RGB, all seven modes | Passed |
| White vs absent mask | Exact RGB | Passed |
| Ordinary request after editing | Exact initial ordinary RGB | Passed |
| Strength1 vs .5 | MAE > 1 | 63.6444 |
| Half-mask vs all-black, white region | MAE > 1 and > 2× black-region MAE | 77.8216 vs 18.6730 |
| Mid-sampling cancellation | Cancelled completion | Passed |
| Ordinary/edit reuse after cancellation | Exact pre-cancel reference RGB | Passed |
| Dispose/reload | Capability cleared then restored; exact strength.5 RGB | Passed |

Visual inspection showed a house/meadow for strength1, retained checker
structure at .5, VAE reconstruction for all-black, and a left-side scene with
right-side checker structure for the half mask. These are wiring and polarity
observations, not an image-quality score. Black output is visibly changed by
VAE reconstruction; exact pixel preservation must not be promised.

Unit tests cover immutable byte ownership, invalid sizes/channels/mask values,
nonfinite/out-of-range strength, recipe/version/device refusal, legacy request
compatibility, engine forwarding, actual worker transport/held-start lifetime,
cancellation/disposal and default reset. Parameter mapper and engine/worker
bypass controls must fail these tests. No native owner source, ABI, pin,
validation catalog or public backend requirement changes are needed. A
versioned validation-pack contract remains tracked in
[#1221](https://github.com/leehack/llamadart/issues/1221).
