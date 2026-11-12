# Bounded reference-image editing qualification

`ReferenceImageEditingRequest` with `ImageReferenceEditingRecipe.fluxKontext`
edits one reference image as the prompt describes. stable-diffusion.cpp
encodes the reference with the FLUX autoencoder and passes its latent tokens
to the transformer at one fixed RoPE index (`preset=flux_kontext`) at every
sampling step. The admitted recipe is the pinned stable-diffusion-native
v0.3.0-1 runtime on macOS with Metal and exactly the FLUX.1 Kontext [dev]
transformer, `ae`, CLIP-L and T5-XXL.

**Status: qualified** on macOS Metal with `flux1-kontext-dev` Q4_0: the Dart
output is byte-identical to the direct C reference for `edit` and `plain`, and
every gate below passes ([run record](https://github.com/leehack/llamadart/pull/1515#issuecomment-6465651561)).

## Family choice

FLUX.1 Kontext [dev] is the first family: its reference path needs no vision
encoder, so it loads with the roles llamadart already admits for FLUX.1
(`diffusionModel`, `vae`, `clipL`, `t5xxl`), and its Q4_0 set (about 12 GB)
fits a 64 GB Apple Silicon Mac. Qwen Image Edit needs a Qwen2.5-VL vision
projector (`llm_vision_path`) and about 17 GB of weights; FLUX.2, Fibo 2.0
and the other upstream presets keep their own acceptance (#1222).

## Contract

| Rule | Value |
| --- | --- |
| References | `references`, decoded RGB in model order; the recipe takes exactly one (`LlamaUnsupportedException` otherwise). Masks are rejected |
| Size | The output takes the first reference's size; every reference has it. Sides are multiples of 64 from 64 to 2048 (`ImageEditingPixels`) and the area is at most 1024x1024 (`ReferenceImageEditingRequest.maxPixels`) |
| Resizing | None. Upstream resizes a reference to `min(1024x1024, output area)` at its aspect ratio, rounded to 16; at the output size with at most 1024x1024 pixels that is its own size, and `sd::ops::interpolate` returns the input unchanged. The default `ref` input transform keeps source dimensions |
| Ownership | Copied on creation; the worker copies them into the generation's native arena, freed after `sd_dart_generate_image` returns, including after a cancel |
| Preset | `ref_image_args = "preset=flux_kontext"`, never the runtime's family guess |
| Combinations | Image editing, ControlNet, hires fix, VAE tiling and circular axes are refused (`LlamaUnsupportedException`) |
| Guidance | `guidanceScale` maps to `txt_cfg`; 1 is upstream's recommendation, so always pass it: omitted, the generic default (7) applies, and the library has no model-specific defaults. The distilled guidance keeps the runtime default (3.5) |

Size errors (`LlamaImageGenerationException`) and recipe refusals
(`LlamaUnsupportedException`) are thrown before the task starts.

## Admission and runtime path

- Headers: `assignImageModelRoles` sets `fluxKontextRecipeVerified` for
  exactly four files: a diffusion model with FLUX double blocks,
  `guidance_in.in_layer.weight` and an `img_in.weight` 64 wide, 16 latent
  channels; a 16-channel VAE; CLIP-L; T5-XXL. FLUX.1-schnell has no guidance
  embedder and FLUX.1 Fill/Control take 384/128-wide patches, so they are
  refused. FLUX.1 [dev] has the same layout as Kontext: the headers cannot
  tell them apart, and the runtime detects both as `Flux`
  (`VERSION_FLUX`, whose default reference preset is also `flux_kontext`).
  The pinned runtime keys `Flux` on the double/single block tensor names and
  the `img_in` patch width and the `txt_in` width alone, so the tensor set has
  no discriminator either, and a model-name check would be a guess. With FLUX.1 [dev], references do not
  steer the output as an edit.
- Load: `referenceEditingRecipeVerified` also needs macOS, a Metal backend
  and the pinned runtime commit (`be48649`).
  `ImageGenerationCapabilities.supportsReferenceImageEditing` also needs the
  runtime to detect `Flux` and the session to report
  `ImageReferenceEditingSession.supportsReferenceImageEditing`; a session
  without the interface is refused. The direct worker repeats the request
  check.
- Kernels: the defaults on Metal (diffusion flash attention on, direct VAE
  convolution off) are the qualified settings; the C reference sets the
  same modes.
- Native call: the reference is encoded and sampled inside the guarded
  `sd_dart_generate_image` on the loaded context. Upstream
  `src/pipeline/image.cpp` checks the cancel flag before each sampling step
  and fails the generation (no images) when a reference cannot be encoded.
  No new `sd_ctx_t` call, native object or callback is added; see
  `doc/llama_cpp_exit_teardown.md`, "Rule for new code".

## Reproduce

Weights (the [upstream guide](https://github.com/leejet/stable-diffusion.cpp/blob/be486498eadc29dc3cd234d944c2180ed42b1415/docs/kontext.md)
names the same set):

| File | Source |
| --- | --- |
| `flux1-kontext-dev-Q4_0.gguf` (about 6.8 GB) | `QuantStack/FLUX.1-Kontext-dev-GGUF` |
| `ae.safetensors` (335 MB) | `second-state/FLUX.1-schnell-GGUF` @ `8c45a2b`, as for FLUX.1-schnell |
| `clip_l-Q8_0.gguf` | `second-state/stable-diffusion-3.5-medium-GGUF` @ `58b78c3`, as for FLUX.1-schnell |
| `t5xxl-Q8_0.gguf` (about 5 GB) | `second-state/stable-diffusion-3.5-medium-GGUF` @ `58b78c3` |

FLUX.1 Kontext [dev] is released under the FLUX.1 [dev] Non-Commercial
License. Record each file's revision and SHA-256 with the results.

Prepare the clean checkout with the pinned SDK, extract the checksum-verified
pinned runtime bundle into `$bundle`, then:

```bash
mkdir -p build/image-reference-editing-native-reference
clang++ -std=c++17 -O2 \
  example/basic_app/test/fixtures/image_reference_editing_native_reference.cpp \
  -I"$bundle/include" -L"$bundle/lib" -lstable-diffusion \
  -Wl,-rpath,"$bundle/lib" \
  -o build/image-reference-editing-native-reference/reference
for mode in edit plain; do
  /usr/bin/time -l build/image-reference-editing-native-reference/reference \
    "$kontext" "$ae" "$clip_l" "$t5xxl" "$mode" \
    "$PWD/build/image-reference-editing-native-reference/$mode.ppm"
done
export LLAMADART_REFERENCE_EDIT_VAE="$ae" \
  LLAMADART_REFERENCE_EDIT_CLIP_L="$clip_l" \
  LLAMADART_REFERENCE_EDIT_T5XXL="$t5xxl"
dart run tool/testing/run_local_e2e.dart --list
dart run tool/testing/run_local_e2e.dart \
  --scenario image-reference-editing --model-path "$kontext" --dry-run
LLAMADART_REFERENCE_EDIT_NATIVE_REFERENCES="$PWD/build/image-reference-editing-native-reference" \
  TMPDIR="$(mktemp -d)" dart run tool/testing/run_local_e2e.dart \
  --scenario image-reference-editing --model-path "$kontext"
```

The fixture is a 512x512 light gray (225) image with a red (200, 30, 30)
disk of radius 120 centred at (256, 224) and a dark (40) bar at rows
432–463, columns 64–447. Both sides use the prompt "Change the red circle to
blue. Keep the gray background and the dark bar.", seed 42, 20 Euler steps,
`guidanceScale` 1 and the runtime's default scheduler and flow shift. `edit`
passes the fixture as the one reference; `plain` is ordinary text-to-image
with the same prompt and settings.

Acceptance gates, fixed before the first real-model run except the bar row (see below):

| Check | Required |
| --- | --- |
| Public Dart vs independent C, `edit` and `plain` | Exact RGB |
| Disk core (radius ≤ 90): mean blue − mean red | > 40 (the fixture's is −170) |
| Background (radius ≥ 150, outside rows 416–479 and the top 16 rows) vs the fixture | MAE < 25 |
| Darkest 16-row band over columns 96–415 in rows 307–511 | Mean < 90, top row within 48 of row 440; grown over adjacent rows with a mean below 132 it is 24–40 rows tall, and its longest run below 132 across its middle row is 320–448 columns (the fixture's is 32 by 384, the qualified run's 33 by 388) |
| `edit` vs `plain` | MAE > 10 (the reference is used) |
| Cancel during sampling | Cancelled completion, no images, then exact `edit` reuse |
| Ordinary request after an edit | Exact `plain` RGB |
| Dispose/reload | Capability cleared then restored; exact `edit` RGB |

The bar is searched rather than read at a fixed window because Kontext redraws
the fixture a few pixels shifted and enlarged (on the recorded run the disk
centre moved 13 px up and the bar top 20 px, rows 432 to 412); an absent bar
still fails. The bar row was revised after the first real-model run, with the
threshold unchanged: the original fixed window failed (mean 164.69). See the
[run record](https://github.com/leehack/llamadart/pull/1515#issuecomment-6465651561).

Record the backend, latency per image (`ImageGenerationResult.elapsed`), the
direct-C peak memory footprint per mode and the Dart process's peak RSS.

Other FLUX variants, Qwen Image Edit, FLUX.2, more than one reference,
TAEF1, LoRA, the CPU, Vulkan, iOS/Android/Linux/Windows/Web and resized or
cropped references remain unqualified or refused.
