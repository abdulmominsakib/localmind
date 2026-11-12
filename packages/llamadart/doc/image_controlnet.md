# Bounded ControlNet qualification

`ControlNetImageGenerationRequest` adds a copied, decoded RGB control map and
a strength to text-to-image generation with a ControlNet loaded as an
`ImageModelRole.controlNet` component. The admitted recipe is the pinned
stable-diffusion-native v0.3.0-1 runtime on macOS CPU, `flashAttention: false`,
`vaeDirectConvolution: false`, exactly one SD 1.x checkpoint with a
header-detected embedded full VAE, and one SD 1.x ControlNet in the original
(lllyasviel) layout. Everything else is refused when the model loads.

**Status: SD 1.x real-model qualification is measured** on macOS arm64 CPU
with the recipe below (2026-10-27; results in
[Reproduce the SD 1.x qualification](#reproduce-the-sd-1x-qualification)).
The admission rules, mapping and refusals are also covered by unit tests and
by direct-C pipeline evidence on the pinned runtime (below). Only this recipe
is qualified.

## Admission and runtime path

Requalified on stable-diffusion-native `v0.3.0-1` (2026-10-27): every result below is byte-identical to the `v0.3.0` measurement ([#922](https://github.com/leehack/llamadart/issues/922)).

- Load: the header classifier gives a ControlNet file
  `ImageModelRole.controlNet`. Admission needs header proof of a four-channel
  SD 1.x checkpoint with `first_stage_model.decoder.conv_in.weight`, a 768-wide
  cross-attention key at
  `input_blocks.1.1.transformer_blocks.0.attn2.to_k.weight` in both files, and
  a ControlNet with `input_hint_block.0.weight` (three input channels),
  `zero_convs.0.0.weight` and `middle_block_out.0.weight`, with or without the
  `control_model.` prefix, in Safetensors or GGUF. At the pinned revision
  `src/name_conversion.cpp` strips `control_model.` and converts Diffusers
  ControlNet names only for SDXL, so SD 1.x Diffusers ControlNets are refused.
  An explicit role on a file whose header cannot be read (such as `.pth`) has
  no proof and is refused.
- Native load: `control_net_path` goes through the existing guarded
  `sd_dart_new_sd_ctx`. The worker then calls `sd_ctx_has_control_net` (a
  pointer check that returns at once) and the engine refuses and frees the
  context unless it reports a ControlNet and the runtime detects `SD 1.x`.
  `sd_ctx_load_control_net` / `sd_ctx_unload_control_net` are not bound:
  hot-swap needs guarded owner wrappers first.
- Generation: `control_image` and `control_strength` are written into the
  request arena that outlives the guarded `sd_dart_generate_image`, including
  cancellation. Ordinary requests start from freshly initialized parameters.
  Upstream `src/pipeline/diffusion_engine.cpp::compute_sample_controls` logs
  `controlnet compute failed` and samples on without control; the worker reads
  `sd_dart_last_error` after the call and fails such a generation instead of
  returning an uncontrolled image. A runtime without the log functions cannot
  detect this, so it reports `supportsControlNet: false`.
- Preprocessing: none. The caller supplies the finished control map at the
  output size; upstream's optional Canny preprocessing and resizing stay at
  their defaults, which are identity for an exact-size image.

## Pipeline evidence on the pinned runtime (synthetic ControlNet)

Direct C against `stable-diffusion-native-runtime-macos-arm64-v0.3.0-1.tar.gz`
(SHA-256 `79c3517b363e6509df17af4d20056ed6e47bbbd134681fb9321520702534cb40`,
upstream `be486498eadc29dc3cd234d944c2180ed42b1415`), macOS arm64 CPU,
`sd_turbo-f16-q8_0.gguf` (SD 2.x), 256 square, Euler/discrete, 2 steps, CFG 1,
seed 42. The ControlNet was synthetic: SD-Turbo's F16 UNet encoder copied
under `control_model.` (ControlNet's training initialization), a random hint
block, and zero convolutions either zero or small deterministic noise.

| Check | Result |
| --- | --- |
| Control image with no ControlNet loaded | Success, byte-identical to no control, no error: upstream ignores it, so Dart refuses this request |
| ControlNet load through `sd_dart_new_sd_ctx`; `sd_ctx_has_control_net` | Loaded; 1 (0 without a ControlNet) |
| Zero-convolution ControlNet, strength 1 | Byte-identical to no control |
| Active ControlNet: strength 1 vs no control | MAE 38.61 |
| Strength 0 vs no control | Byte-identical |
| House vs cross control map at strength 1 | MAE 14.61 |
| Strength 2 vs 1 | MAE 43.52 |
| Ordinary request after control requests | Byte-identical to the first ordinary request |

The SD 2.x pair proves the native wiring and strength semantics only; Dart
refuses SD 2.x ControlNet loads.

## Reproduce the SD 1.x qualification

Prepare the clean checkout with the pinned SDK. Supply local weights: an
SD 1.x checkpoint with its full VAE (for example SD 1.5 `v1-5-pruned-emaonly`)
and an original-layout SD 1.x ControlNet Safetensors or GGUF (for example a
`control_v11p_sd15_canny` conversion). Extract the checksum-verified pinned
runtime bundle into `$bundle`, then:

```bash
mkdir -p build/image-controlnet-native-reference
clang++ -std=c++17 \
  example/basic_app/test/fixtures/image_controlnet_native_reference.cpp \
  -I"$bundle/include" -L"$bundle/lib" -lstable-diffusion \
  -Wl,-rpath,"$bundle/lib" \
  -o build/image-controlnet-native-reference/reference
build/image-controlnet-native-reference/reference "$sd15" "$controlnet" \
  "$PWD/build/image-controlnet-native-reference/control"
dart run tool/testing/run_local_e2e.dart --list
LLAMADART_SD15_CONTROLNET="$controlnet" dart run tool/testing/run_local_e2e.dart \
  --scenario image-controlnet --model-path "$sd15" --dry-run
LLAMADART_SD15_CONTROLNET="$controlnet" \
  LLAMADART_CONTROLNET_NATIVE_REFERENCES="$PWD/build/image-controlnet-native-reference" \
  TMPDIR="$(mktemp -d)" dart run tool/testing/run_local_e2e.dart \
  --scenario image-controlnet --model-path "$sd15"
```

Both fixtures draw the same synthetic edge maps (a house outline and a
diagonal cross, white three-pixel lines on black), the same prompt, 256
square, CPU 4 threads, Euler/discrete 8 steps, CFG 7, seed 42. Modes are
ordinary text, house at 1, house at 0, cross at 1, house at 2, ordinary text
reset. Record the checkpoint, ControlNet and runtime SHA-256 with the result.

Measured inputs (pinned runtime `stable-diffusion-native-runtime-macos-arm64-v0.3.0-1.tar.gz`,
SHA-256 `79c3517b363e6509df17af4d20056ed6e47bbbd134681fb9321520702534cb40`):

| File | Source (Hugging Face revision) | SHA-256 |
| --- | --- | --- |
| `v1-5-pruned-emaonly.safetensors` (4.0 GB) | `stable-diffusion-v1-5/stable-diffusion-v1-5` @ `451f4fe16113bff5a5d2269ed5ad43b0592e9a14` | `6ce0161689b3853acaa03779ec93eafe75a02f4ced659bee03f50797806fa2fa` |
| `control_v11p_sd15_canny_fp16.safetensors` (689 MB, fp16, `control_model.` prefix) | `comfyanonymous/ControlNet-v1-1_fp16_safetensors` @ `ab830a51c5c573a5b85bfdbaa3ae0ab7e1baf5f7` | `8932b66e15aae835b3490dbf989f56c253104cee08a88bf21283762f557c9f10` |

Fixed acceptance gates, recorded before any SD 1.x output was observed:

| Check | Required |
| --- | --- |
| Public Dart vs independent C | Exact RGB, all six modes |
| Ordinary request after ControlNet requests | Exact first ordinary RGB |
| Strength 0 vs ordinary | Exact RGB |
| Strength 1 vs 0 | MAE > 1 |
| House vs cross map at strength 1 | MAE > 1 |
| Output edge contrast on house-map pixels | House-controlled > cross-controlled |
| Mid-sampling cancellation | Cancelled completion; exact ordinary and control reuse after it |
| Dispose/reload | Capability cleared then restored; exact cross-map RGB |

Measured result (macOS arm64 CPU, `image-controlnet` scenario, all gates
passed; the direct-C reference also reported `FAMILY=SD 1.x CONTROLNET=1`):

| Check | Measured |
| --- | --- |
| Public Dart vs independent C, six modes | Exact RGB |
| Ordinary request after ControlNet requests | Exact first ordinary RGB |
| Strength 0 vs ordinary | Exact RGB |
| Strength 1 vs 0 | MAE 80.10 |
| House vs cross map at strength 1 | MAE 78.63 |
| Edge contrast on house-map pixels | House-controlled 34.10 > cross-controlled 1.92 |
| Mid-sampling cancellation, then ordinary and control reuse | Cancelled; exact reuse |
| Dispose/reload | Capability cleared then restored; exact cross-map RGB |
| Strength 2 vs 1 (informational) | MAE 67.82 |

Wall time was about 6 minutes for the Dart scenario and 3.6 minutes for the C
reference.

GPU, mobile and Web devices, SD 2.x, SDXL and newer families, Diffusers or
`.pth` ControlNets, preprocessors, multiple ControlNets and hot-swap remain
unqualified or refused.
