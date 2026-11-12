---
title: Image generation advanced requests (Preview)
sidebar_label: Advanced requests (Preview)
description: Seamless textures, local checkpoint sets, image editing, ControlNet, hires fix and reference image editing with ImageGenerationEngine.
---

Part of the [on-device image generation guide](./image-generation) (Preview). Each recipe is bounded to the models and platforms named in its section.

## Seamless textures

`SeamlessImageGenerationRequest` opts into circular padding independently on
X (left/right) and Y (top/bottom). Both default to `false`; ordinary
`ImageGenerationRequest` calls keep their existing behavior. The first
qualified profile is **SDXS (512-DS), its embedded tiny decoder, 512×512,
CPU or Metal**, loaded with both `flashAttention: false` and
`vaeDirectConvolution: false`. The engine checks the native family and file
headers, so renaming weights or forcing a checkpoint role does not grant
support. Other families, component/decoder overrides, sizes, other GPUs and
enabled attention/direct-convolution options throw `LlamaUnsupportedException`
before a task starts. Defaults that enable flash attention must be overridden.

```dart
final engine = await ImageGenerationEngine.load(
  ImageGenerationModel(ModelSource.path('sdxs-512-tinySDdistilled_Q8_0.gguf')),
  params: const ImageModelParams(
    flashAttention: false,
    vaeDirectConvolution: false,
  ),
);
try {
  final result = await engine.generateImage(
    const SeamlessImageGenerationRequest(
      prompt: 'seamless texture of weathered gray stone, uniform rough stone '
          'surface, flat lighting, top down',
      width: 512,
      height: 512,
      steps: 4,
      guidanceScale: 1,
      seed: 42,
      sampler: ImageGenerationSampler.euler,
      scheduler: ImageGenerationScheduler.discrete,
      circularX: true,
      circularY: true,
    ),
  );
  await File('stone.png').writeAsBytes(result.images.single.toPng());
} finally {
  await engine.dispose();
}
```

This uses the pinned runtime's ordinary diffusion and VAE decoder circular
convolutions. It does not enable VAE tiling or alter sampling defaults.
Padding improves boundary continuity; prompt content and seeds can still
produce an unsuitable texture. Inspect a 2×2 repeat before using the output.
The fixed qualification prompt/seed must pass, on each requested axis:
edge mean absolute RGB difference below 8/255, below 1.5 times the average
interior adjacent-pixel difference, and below 40% of the same-seed off result.
These criteria measure continuity, not artistic quality.

The maintained `image-seamless-textures` scenario saves individual and repeated
PNGs, numerical JSON, checks native-reference pixels when provided, and checks
ordinary output after circular generation and cancellation/reuse. Measured
qualification is macOS arm64 CPU and actual Metal; other platforms are
unmeasured. SD-Turbo's full VAE missed the fixed profile's absolute seam gate
and is refused. Other families and external TAESD decoders are not qualified.

## Local checkpoint sets

`ImageGenerationModel.localSafetensorsSet` accepts a local directory containing
`model.safetensors.index.json`, or that standard index itself, with 1..16
adjacent Safetensors shard files. This is a complete-checkpoint container
recipe, not Diffusers Python pipeline/config discovery. Component overrides,
Diffusers markers, extra model files, symlinks, unsafe shard paths, duplicate
JSON keys/tensors, missing/misassigned tensors, malformed shapes/offsets and
non-F16/F32 dtypes are rejected before native load.

The first recipe is the documented complete SD-Turbo F16/F32 tensor layout,
identified by all 1,323 tensor names, dtypes and shapes. The fingerprint is a
versioned recipe boundary, not a generic architecture-completeness detector or
weight authenticity check. Its measured source is the complete local checkpoint
derived for the format qualification; other matching weights are unmeasured.
Only macOS CPU with pinned SD v0.3.0-1/upstream `be48649`, explicit
`flashAttention: false` and `vaeDirectConvolution: false` is admitted. A loaded
engine reports `supportsLocalSafetensorsSets`; it is false before load/after
disposal. Editing, VAE tiling and seamless opt-ins remain refused for this path.

```dart
final model = ImageGenerationModel.localSafetensorsSet(
  localDirectoryOrStandardIndex,
  sha256: trustedPerFileHashes,
  cacheDirectory: appPrivateSetCache,
);
final engine = await ImageGenerationEngine.load(
  model,
  params: const ImageModelParams(
    device: ComputeDevice.cpu,
    flashAttention: false,
    vaeDirectConvolution: false,
  ),
);
```

The expected map includes the index and every shard's safe basename and SHA-256.
Pin it from a trusted source independently of mutable input files. Every local
file resolves through `ModelFileStore`; remote or outside-root redirects fail
before a downloader acts. There is no remote index/repository/shard fetch and
no credential forwarding. This route takes only the cancel token from
`ModelLoadOptions`; its factory owns the checksum map and cache directory.
Individual-file sources and custom legacy resolver/manager interfaces retain
their existing behavior.

Reserve an app-private cache directory for owned sets. The loader copies and
hashes into a unique partial stage, validates every header/index relationship,
then atomically publishes by content identity. It re-verifies every cached file
on reuse, including when the original files are no longer available. Never
modify or remove published cache files while any engine uses them; clear this
cache manually only after all engines are disposed. Source directory topology
must remain stable during resolution/copy; concurrent malicious rename/symlink
replacement is outside this app-owned-source contract. Original file contents
may change after the verified copy. A precheck alone is not treated as a file
lease or immutable snapshot.

Progress and memory accounting include the index, every shard header and all
tensor bytes in deterministic basename order. Cancellation checks each stream
chunk; failed/cancelled staging is removed. A complete published set remains
cached if cancellation arrives afterward, and a corrupt cache is rejected
instead of repaired under an active engine. Cleanup failures surface as errors.
The recipe caps source files at 3 GiB including metadata; headers/index and
nesting also have explicit bounds.

`example/basic_app/bin/local_image_set.dart` is a runnable local-only consumer.

The loader requires complete contiguous numbered shard basenames,
`model-00001-of-000NN.safetensors` through `model-000NN-of-000NN.safetensors`,
for N in 1..16. Arbitrary names, gaps and count aliases fail before manager or
native work. The strict index
mapping and tensor-layout fingerprint bind all native-visible tensor names;
unsupported metadata/extra aliases use fixed error categories without
quoting caller text.

Managed integrity, confinement and aggregate accounting apply only to
`localSafetensorsSet`. Legacy ordinary explicit-role JSON forwarding remains
unqualified and is refused on Metal because shard dtypes cannot be inspected;
CPU forwarding does not acquire these guarantees. Unexpected
process termination may leave uncommitted partial directories; these are never
reused, and may be removed only after all processes using this private cache
have stopped.

The fixed 128-square, one-step diagnostic output is an abstract green/white
pattern rather than a recognizable fox. Native single-file, index, directory
and public paths are byte-identical, so this qualifies container/cache-path
equivalence only. It is not evidence of prompt fidelity or a recommended
image-generation preset; no cause for that baseline output is asserted here.

## Image editing

`ImageEditingRequest` accepts an owned copy of decoded row-major RGB bytes
and an optional one-channel binary mask. It leaves `ImageGenerationRequest`
and text-to-image defaults unchanged. The output matches input dimensions:
both axes must be multiples of 64 from 64 through 2048. The caller decodes
PNG/JPEG, applies orientation, resizes and composites alpha before submission.
No such transformations happen implicitly.

Check `(await engine.capabilities).supportsImageEditing` after loading. The
bounded recipe requires stable-diffusion-native `v0.3.0-1` (upstream `be48649`),
a native-detected SD 2.x single checkpoint with a header-detected embedded full
VAE on macOS CPU, `flashAttention: false` and `vaeDirectConvolution: false`.
Component overrides, tiny decoders, other families, platforms/devices, VAE
tiling and circular axes throw `LlamaUnsupportedException` before generation.
SD-Turbo is the measured artifact; other SD 2.x checkpoints matching the recipe
are source-compatible but unmeasured. This capability does not certify every
prompt, resolution or checkpoint's output quality.

```dart
final input = ImageEditingPixels.rgb(width: width, height: height, pixels: rgb);
final request = ImageEditingRequest(
  prompt: 'a colorful painting of a house',
  initialImage: input,
  strength: 0.75,
  mask: ImageEditingPixels.mask(width: width, height: height, pixels: binaryMask),
  steps: 4,
  guidanceScale: 1,
  seed: 42,
);
final result = await engine.generateImage(request);
```

A mask value of **255 edits** and **0 preserves the encoded latent**. Other
values are rejected; no implicit threshold is applied. Black output regions
need not equal the input bytes because full-VAE encode/decode is lossy and
convolutions cross mask boundaries. An omitted mask edits the whole image.
`strength` must be finite and in `(0, 1]`; higher values allow larger changes,
but step rounding can map nearby strengths to the same schedule. At 1 the
runtime still encodes the input. This API does not load an inpainting-specific
model or guarantee exact pixel compositing.

Inputs copy their supplied bytes and return copies from `pixels`. They remain
owned through cancellation until the native call ends. Cancellation, concurrent
generation and disposal use the same rules as text-to-image. Reusing a session
for ordinary generation resets input/mask fields to native defaults.
Run `example/basic_app/bin/image_editing.dart` with a local full checkpoint;
it creates a decoded RGB fixture without a codec dependency.

## ControlNet

A ControlNet steers sampling toward a control map, such as Canny edges, a
depth map or a pose skeleton. Pass it as a component next to its base
checkpoint; its header gives it `ImageModelRole.controlNet`. It loads with
the model and stays loaded until `dispose`: requests cannot swap it, and
ordinary requests generate without it.

```dart
final engine = await ImageGenerationEngine.load(
  ImageGenerationModel(
    ModelSource.path('v1-5-pruned-emaonly.safetensors'),
    components: [
      ImageModelComponent.auto(
        ModelSource.path('control_v11p_sd15_canny.safetensors'),
      ),
    ],
  ),
  params: const ImageModelParams(
    device: ComputeDevice.cpu,
    flashAttention: false,
    vaeDirectConvolution: false,
  ),
);
if ((await engine.capabilities).supportsControlNet) {
  final result = await engine.generateImage(
    ControlNetImageGenerationRequest(
      prompt: 'a small wooden house in a green meadow',
      control: ImageControlNetCondition(
        image: ImageEditingPixels.rgb(width: 512, height: 512, pixels: edges),
        strength: 1,
      ),
      steps: 20,
      seed: 42,
    ),
  );
}
```

The bounded recipe requires stable-diffusion-native `v0.3.0-1` (upstream
`be48649`) on macOS with `ComputeDevice.cpu`, `flashAttention: false` and
`vaeDirectConvolution: false`, and exactly an SD 1.x checkpoint with its
embedded full VAE plus an SD 1.x ControlNet in the original (lllyasviel)
layout, as Safetensors or GGUF. The headers must show a 768-wide text context
in both and a three-channel hint block. Other families, Diffusers-layout or
`.pth` ControlNets, extra components, devices and platforms throw
`LlamaUnsupportedException` when the model loads. Qualified on SD 1.5 `v1-5-pruned-emaonly` with `control_v11p_sd15_canny` (fp16
Safetensors).

The control image is the finished map: llamadart runs no edge, depth or pose
detector and does not resize it. Supply decoded RGB with the output's
dimensions, multiples of 64 from 64 through 2048; the request takes its size
from the image. `strength` scales the ControlNet's residuals from 0 (none) to
2, default 0.9. The image is copied and stays owned through cancellation.
When the runtime reports that the ControlNet pass failed, the task fails with
`LlamaInferenceException` instead of returning an image that ignored the
control. Run `example/basic_app/bin/image_controlnet.dart` with local files.

## Hires fix

A hires fix generates at the model's native size, enlarges the result and
samples it again at the larger size, which adds detail an enlarged image
lacks while keeping the first pass's composition. Both passes run in one
native generation.

```dart
final engine = await ImageGenerationEngine.load(
  ImageGenerationModel(ModelSource.path('v1-5-pruned-emaonly.safetensors')),
);
if ((await engine.capabilities).supportsHiresFix) {
  final result = await engine.generateImage(
    const HiresFixImageGenerationRequest(
      prompt: 'a red fox sitting in a snowy forest, photograph',
      width: 512,
      height: 512,
      steps: 20,
      seed: 42,
      hiresFix: ImageHiresFix.scale(1.5, steps: 10, denoisingStrength: 0.55),
    ),
  );
  // result.images.single is 768x768.
}
```

The request's `width` and `height` are the first pass. Give the final size
as a `scale` (`ImageHiresFix.scale`, above 1 and at most 2) or as a `width`
and `height` (`ImageHiresFix.size`), never both:

- Every first-pass and final side is a multiple of 64; nothing is rounded,
  so a scale whose result is not a multiple of 64 is rejected.
- Each final side is at least the first-pass side and at most twice it, and
  the final image is larger than the first pass and at most 1024x1024.
- A request makes at most 4 images. Image `i` uses seed `seed + i` in both
  passes.
- `steps` (1 to 150) defaults to the first pass's steps. As in
  stable-diffusion.cpp, the second pass runs the last steps of a schedule of
  `steps / denoisingStrength` steps, which can be one more than `steps`.
- `denoisingStrength` (0.05 to 1, default 0.7) is how much noise the second
  pass adds; lower values keep more of the first pass.
- `upscaler` is `ImageHiresUpscaler.latent`: bilinear interpolation of the
  latent before it is decoded, with no extra model. Model-based upscalers
  are not offered.

Out-of-range values throw `LlamaImageGenerationException` before the task
starts. The bounded recipe requires stable-diffusion-native `v0.3.0-1`
(upstream `be48649`) on macOS with `ComputeDevice.cpu` or Metal, and a
native-detected SD 1.x or SD 2.x checkpoint with its embedded full VAE and no
component overrides. Other families, decoders, hosts and devices report
`supportsHiresFix: false`, and a hires-fix request throws
`LlamaUnsupportedException`. The request type cannot carry image editing,
ControlNet, VAE tiling or circular axes. Qualified on SD 1.5 and SD-Turbo.

Progress reports both passes: `ImageGenerationProgressEvent.pass` is 0 for
the first pass and 1 for the second, with `passCount` 2 and the second
pass's own step total, then decoding follows. Cancelling stops the
generation before the next step of either pass, or between them, and returns
no images: a cancelled or failed second pass never returns first-pass images.
The second pass needs the memory and time of an ordinary generation at the
final size. When the runtime returns images that do not have the final size,
the task fails with `LlamaInferenceException`. Run
`example/basic_app/bin/image_hires_fix.dart` with a local checkpoint.

## Reference image editing

Reference editing changes a supplied image as the prompt describes and keeps
the rest of it: FLUX.1 Kontext [dev] encodes the reference with its
autoencoder and attends to it at every sampling step.

```dart
final engine = await ImageGenerationEngine.load(
  ImageGenerationModel(
    ModelSource.path('flux1-kontext-dev-Q4_0.gguf'),
    components: [
      ImageModelComponent.auto(ModelSource.path('ae.safetensors')),
      ImageModelComponent.auto(ModelSource.path('clip_l-Q8_0.gguf')),
      ImageModelComponent.auto(ModelSource.path('t5xxl-Q8_0.gguf')),
    ],
  ),
  params: const ImageModelParams(device: ComputeDevice.gpu),
);
if ((await engine.capabilities).supportsReferenceImageEditing) {
  final result = await engine.generateImage(
    ReferenceImageEditingRequest(
      prompt: 'Change the red circle to blue.',
      recipe: ImageReferenceEditingRecipe.fluxKontext,
      references: [
        ImageEditingPixels.rgb(width: 512, height: 512, pixels: rgb),
      ],
      steps: 20,
      guidanceScale: 1,
      seed: 42,
    ),
  );
  // result.images.single is 512x512.
}
```

- `references` are decoded RGB images in the order the model receives them;
  the recipe takes exactly one. Masks are not references.
- The output has the reference's size. Every side is a multiple of 64 and the
  image has at most 1024x1024 pixels, so the runtime encodes the reference as
  given: decode, crop and resize photos before creating the request. Nothing
  is resized, cropped or padded during generation.
- The references are copied when the request is created and stay owned until
  the native call ends, including after a cancel.
- Always pass `guidanceScale: 1`, the recommended setting: omitted, the
  generic default of 7 applies. The transformer's own guidance embedding keeps
  the runtime default.

Size violations throw `LlamaImageGenerationException` before the task starts.
The bounded recipe requires stable-diffusion-native `v0.3.0-1` (upstream
`be48649`) on macOS with Metal, and exactly a FLUX transformer with a
guidance embedder and 64-wide patch input, the 16-channel FLUX autoencoder,
CLIP-L and T5-XXL, which the runtime detects as `Flux`. FLUX.1 [dev] has the
same layout, so the headers cannot tell it from Kontext; with it, the
reference does not steer the output as an edit. FLUX.1-schnell, Fill and
other families, TAEF1 or extra components, the CPU, Vulkan, other platforms,
more references and requests that combine references with image editing,
ControlNet, a hires fix, VAE tiling or circular axes report
`supportsReferenceImageEditing: false` or throw `LlamaUnsupportedException`.

FLUX.1 Kontext [dev] is released under the FLUX.1 [dev] Non-Commercial
License. Run `example/basic_app/bin/image_reference_editing.dart` with local
files.
