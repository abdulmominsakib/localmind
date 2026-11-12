---
title: Image generation settings (Preview)
sidebar_label: Generate and settings (Preview)
description: Generate images with ImageGenerationEngine, tune attention, VAE, caching and module placement, and control warm-up, progress and cancellation.
---

Part of the [on-device image generation guide](./image-generation) (Preview). Load a model first; see [Get a model](./image-generation#get-a-model).

## Generate

```dart
final engine = await ImageGenerationEngine.load(model);
final capabilities = await engine.capabilities;
print('${capabilities.modelVersion} on ${capabilities.backendName}');

final task = await engine.generate(
  const ImageGenerationRequest(
    prompt: 'a red fox in autumn leaves',
    steps: 1,
    guidanceScale: 1,
    seed: 42,
  ),
);
task.events.listen((event) {
  if (event
      case ImageGenerationProgressEvent(:final phase, :final step, :final steps)) {
    print('$phase $step/$steps');
  }
});
final result = await task.result;
final png = result.images.first.toPng();
print('${png.length} PNG bytes, seed ${result.seed}');
await engine.dispose();
```

`generate` returns the running `ImageGenerationTask` once the request passes
its checks. `task.events` carries progress and never an error. `task.result`
returns the images, or throws the failure, or `LlamaStateException` when the
task is cancelled; `task.done` reports the same outcome as an
`ImageGenerationCompletion` and never throws.
`engine.generateImage(request)` is the one-call form of
`(await engine.generate(request)).result`.

- Width and height are multiples of 8 from 64 to 2048, and default to 512.
  Use the model's native size: 512x512 for SDXS and SD-Turbo, 1024x1024 for
  the desktop models in the recipes. SDXS and SD-Turbo also work at 256.
  The runtime rounds the size up to a multiple of 64 for these models, so a
  200x136 request produces
  256x192; `GeneratedImage.width` and `height` report the real size.
- `steps` defaults to 20 and `guidanceScale` to 7, which suit undistilled
  SD 1.x and 2.x models; set the model's own, as in the recipes. A guidance
  of 1 skips the negative prompt and halves the work per step. `sampler`,
  `scheduler` and `flowShift` default to the runtime's choice for the
  model.
- A `null` seed picks one at random. `result.seed` reports the seed used, and
  image `i` of `count` used `seed + i`. The same seed, size, steps and model
  reproduce the same pixels.
- `GeneratedImage.pixels` holds row-major RGB bytes; `toPng()` encodes them.
- Invalid requests make `generate` throw `LlamaImageGenerationException`
  before a task starts.

`load` loads every weight up front. The first image in a process can still be
slow while the GPU compiles shaders; see
[First-image latency and warm-up](#first-image-latency-and-warm-up).

## Attention and VAE settings

Two runtime settings in `ImageModelParams` change speed and memory.
Direct VAE convolutions leave the image identical on the CPU and change it
by rounding on Metal; flash attention changes pixels slightly, by rounding.
Left `null`, the engine picks them for the device it loads on:

| Setting | Automatic choice | Measured |
| --- | --- | --- |
| `flashAttention` (diffusion model) | On for the CPU and Metal, off on Vulkan | M4 Max Metal: SD 3.5 Medium sampling 1.6 times as fast, compute buffer 1.8 GiB to 0.3 GiB; SDXL-Lightning about 10% and FLUX about 5% faster; SD 1.x/2.x sampling time unchanged. M4 Max CPU: SD-Turbo sampling about a fifth faster. 512x512 on phones: SD-Turbo with TAESD 12% faster on a Galaxy S24 (CPU) and 11% on an iPhone 16 Pro (Metal), same peak memory; its 3.7% gap on a Pixel 9 Pro is within run-to-run noise there (the same `auto` arm took 11.3 s, then 17.4 s a round later); SDXS unchanged on those and a Galaxy A53. Pixels change slightly |
| `vaeDirectConvolution` (VAE decode) | On, except on Metal and when a tiny autoencoder decodes: a `taesd` file, or a checkpoint whose header shows an embedded one, as SDXS's does | NVIDIA L4 Vulkan, 1024x1024, stable-diffusion.cpp's native CLI: decode 23 to 56 s to about 1 s, 4 to 5 GiB less device memory. M4 Max CPU, SD-Turbo 512x512: about 5% slower end to end, peak 3.6 GiB to 2.7 GiB. Galaxy S24 and Pixel 9 Pro CPU, SD-Turbo 512x512: peak 3.7 to 4.0 GiB to 2.8 to 3.1 GiB, time unchanged within thermal noise (about 56 s per image on the S24). Metal: about 7 times slower. Identical output on the CPU; on M4 Max Metal, SD-Turbo at 256x256 and 512x512 differed by at most 2 of 255 per channel. `true` on iOS Metal throws `LlamaUnsupportedException`: on an iPhone 16 Pro every decode tripped the GPU watchdog and returned a corrupt image ([#1044](https://github.com/leehack/llamadart/issues/1044)) |

The phone figures are from the chat app's settings comparison on real devices.
Peak memory is the `phys_footprint` interval peak on the iPhone and a sampled
`VmRSS` peak on Android. The Galaxy A53's memory check refused SD-Turbo, so it
has no SD-Turbo figures, and its SDXS figures are an observation, not verified
evidence. The iPhone full-VAE arm has not been measured, because its decode
trips the GPU watchdog ([#1047](https://github.com/leehack/llamadart/issues/1047)).

With a tiny autoencoder, direct convolutions cost time for little memory:
on an M4 Max CPU they took 1.4 to 1.7 s per 512x512 SDXS image against 1.2
to 1.3 s, for 0.24 GiB less peak process memory. Set `vaeDirectConvolution:
true` where that memory matters more.

Vulkan flash attention has not been measured yet, so it stays off there;
pass `flashAttention: true` to try it. The runtime falls back to regular
attention where a device has no kernel for it.

### VAE tiling

`TiledImageGenerationRequest(vaeTiling: ImageVaeTiling())` decodes the image in overlapping tiles
instead of all at once. The decoder's compute buffer then scales with the
tile instead of the image, so peak memory drops most for large images and
full VAEs; decoding takes longer, and pixels change slightly where tiles
blend. It requires the pinned `stable_diffusion` v0.3.0-1 runtime (upstream `be48649`)
and accepts header-verified SD 2.x checkpoints with their embedded full VAE
or a valid TAESD override on CPU or Metal. SD-Turbo is the measured artifact;
other accepted SD 2.x checkpoints and phones remain unmeasured. Unknown
headers, external full VAEs, other component overrides, model families and
backends throw `LlamaUnsupportedException` before a task starts. Tiling with
either seamless circular axis is also refused until separately qualified.
Custom image backends are unavailable for tiling in this slice; no public
backend extension contract is added. Sampling and weights are unchanged. Requests without
it decode the whole image, as before.

```dart
final result = await engine.generateImage(
  const TiledImageGenerationRequest(
    prompt: 'a lighthouse at dusk',
    width: 1024,
    height: 1024,
    steps: 1,
    guidanceScale: 1,
    vaeTiling: ImageVaeTiling(), // 256x256 tiles, overlap 0.5
  ),
);
```

Tile sizes are output pixels, multiples of 64 from 64 to 2048, and default to
256; a tile larger than the image covers it on that axis. `overlap` is the
target fraction a tile shares with its neighbour, from 0 to 0.5 (default
0.5); the runtime spaces tiles evenly, so neighbours always overlap a little.
Other values throw `LlamaImageGenerationException` before the task starts.
The existing `warmUp` signature stays unchanged; use a single-step tiled
generation and discard its image when tiled GPU pipelines need warming. Without tiling, the runtime already retries a decode that fails
to allocate with tiles; tiling from the start keeps the decode under limits
that end the app before an allocation fails. Cancelling does not interrupt a
decode that has started.

SD-Turbo Q8_0 with its full VAE, one step, 256-pixel tiles at overlap 0.5,
on an M4 Max:

| Device, size | VAE compute buffer | Decode time | Peak footprint of the `dart run` process |
| --- | --- | --- | --- |
| Metal, 512x512 | 1664 MB to 416 MB | 1.7 s to 3.7 s | Not visible: Metal buffers are outside `phys_footprint` |
| CPU, 512x512 | 704 MB to 176 MB | 5.9 s to 12.5 s | 3.02 GiB to 2.59 GiB |
| CPU, 1024x1024 | Not logged | Image 31 s to 71 s | 5.10 GiB to 2.83 GiB |

At 512x512 the tiled image differed from the untiled one by 2.5 of 255 per
channel on average and at most 88 near tile seams, with no visible seams.
Vulkan GPUs and phones, including the iPhone GPU watchdog of
[#1047](https://github.com/leehack/llamadart/issues/1047), are unmeasured.

## Conditioning cache

`ImageConditioningCacheParams(capacity: ...)` controls how many prompt-conditioning
entries a loaded model retains. Ordinary `ImageModelParams` preserve the pinned
native runtime's default of four entries; capacity `0` disables reuse. A positive
integer sets the least-recently-used entry limit, up to the signed 32-bit C ABI limit
(`2147483647`). Invalid values throw `LlamaImageGenerationException` before
model files are resolved or downloaded.

```dart
final engine = await ImageGenerationEngine.load(
  model,
  params: const ImageConditioningCacheParams(capacity: 0),
);
```

The limit counts entries, not bytes: conditioning size depends on the text
encoder and request. Reuse requires matching conditioning inputs, including
the prompt and dimensions; another prompt is encoded separately. Entries
belong to the loaded native context, remain available after a cancelled
generation when valid, and are freed when it is disposed. Load a new engine
to change capacity. This cache already operates when the option is unset;
this control does not enable approximate diffusion-step caching, change
sampling, or promise a speed or memory improvement.

Qualification for this control covers macOS arm64 CPU and Metal. Android,
iOS, Linux CPU/Vulkan, Windows CPU/Vulkan and macOS x64 have not been measured
for this option; SDXL, SD 3.5, FLUX, Z-Image and Qwen-Image were not run.
Web image generation remains unavailable. Approximation-cache modes remain
separate work.

## Module placement and GPU memory

`ImageModelPlacement`, the `placement:` of `ImageGenerationEngine.load`, sets
where the modules of a model compute and how stable-diffusion.cpp fits their
weights into GPU memory. It applies only to an engine on a GPU (Metal, or
Vulkan on Linux and Windows); any setting but the default throws
`LlamaUnsupportedException` before any file is resolved when the engine runs
on the CPU (`ComputeDevice.cpu`, Android, the CPU builds, or a runtime that
reports no GPU), and the Web has no image runtime.

```dart
final engine = await ImageGenerationEngine.load(
  model,
  placement: const ImageModelPlacement(
    textEncoderOnCpu: true, // T5-XXL, CLIP or the Qwen3 encoder in RAM
    maxGpuMemoryGiB: 10,
  ),
);
```

| Setting | Effect | Measured with SD-Turbo Q8_0, 512x512, one step, M4 Max Metal |
| --- | --- | --- |
| `textEncoderOnCpu` | Text encoders compute on the CPU, weights in system memory | 359 MB of weights left the GPU; pixels changed by at most 40, mean 0.23 of 255 |
| `vaeOnCpu` | VAE or tiny autoencoder computes on the CPU, weights and decode memory in system memory | 160 MB of weights and the 1.6 GiB decode buffer left the GPU; image 8.9 s instead of 2.1 to 2.6 s; pixels at most 1 of 255 apart |
| `maxGpuMemoryGiB` | Per-GPU budget, in whole GiB, for weights plus the room the fit reserves to compute (2 GiB beside the diffusion model and the text encoders, 1 GiB beside the VAE), so weights can move to system memory, another GPU or disk even when they alone fit; moved weights stream in | 1 GiB: all 1.9 GB of weights in system memory, and the decode, above the budget, retried in tiles (at most 85, mean 2.5 of 255 apart); 8 GiB: identical pixels |
| `autoFit: false` | No automatic fit: weights are allocated on the device their module computes on, and `ComputeDevice.auto` uses the first GPU; a load the device cannot allocate fails with `LlamaModelException` instead of spilling | Identical pixels |

`maxGpuMemoryGiB` must be 1 to `ImageModelPlacement.largestGpuMemoryGiB`;
other values throw `LlamaImageGenerationException`. It takes whole GiB
because the runtime reads a fraction in the process's locale. Together with
`autoFit: false` it throws `LlamaUnsupportedException`: the pinned runtime
then keeps every weight on the GPU and aborts the process in `new_sd_ctx`
when the budget is below them (SD-Turbo with 1 GiB).
Outside Metal it also needs a discrete GPU: when the runtime reports only
integrated Vulkan GPUs, or no GPU type (`SD_VK_DEVICE` set), it throws
`LlamaUnsupportedException`, because the runtime's fit plans only for
discrete GPUs and would compute on the integrated one under the budget
without a plan, which aborts the same way. Moving the text encoders or the
VAE with an integrated GPU is allowed.

On a host with a discrete and an integrated Vulkan GPU and
`ComputeDevice.auto`, moving the text encoders or the VAE lets the fit also
consider the integrated GPU, which can then compute the diffusion model when
it reports more free memory. That is slower, not a failure;
`ComputeDevice.gpu` keeps the first discrete GPU.

A module moved to the CPU leaves the Metal-only
FLUX.1 Kontext recipe unqualified (`supportsReferenceImageEditing` is
`false`). The [memory check](./image-generation-memory-and-limits#memory-check) counts every weight against the
device whatever the placement. Placement was measured with SD-Turbo on one
Linux x64 Vulkan Tesla T4 too; two-GPU hosts and the larger models the setting
is for (FLUX, SD 3.5, Z-Image) have not been measured yet.

## First-image latency and warm-up

ggml compiles GPU shaders the first time a process needs them, in two places:

- The first runtime probe in a process (`checkRuntime()` or `load()`)
  initializes the GPU backend. On Apple GPUs this compiles ggml's Metal
  library. Both run the probe on a separate isolate.
- The first generation on the GPU compiles the pipelines it runs.

The operating system or GPU driver caches the compiled shaders on disk, so
later launches are faster. ggml in the bundled runtime keeps no cache of its
own (no Metal binary archive or Vulkan pipeline cache); whether iOS and
Android keep the driver cache across launches is not measured yet.

| Device and step | Empty shader cache | Cached shaders |
| --- | --- | --- |
| M4 Max, Metal: first runtime probe | 15.5 to 18.7 s | 0.4 to 0.5 s |
| M4 Max, Metal: SDXS 512x512, first image, then next | 1.0 s, then 0.46 s | 0.41 to 0.48 s, then 0.38 to 0.45 s |
| M4 Max, Metal: SD-Turbo + TAESD 512x512, first image, then next | 0.79 to 0.90 s, then 0.54 to 0.66 s | 0.68 to 0.73 s, then 0.67 to 0.68 s |
| NVIDIA L4, Linux Vulkan: first image, then SDXS warm | About 12 s, then 176 ms | Later processes reuse the driver cache |
| NVIDIA L4, Windows Vulkan: first image, then SDXS warm | About 45 s, then 571 ms | Later processes reuse the driver cache |
| iPhone 16 Pro, Metal | About 19 s before the first image on first launch, not split between the probe and the image | Not measured |

The empty-cache M4 Max figures ran with `MTL_SHADER_CACHE_SIZE=0`, which
turns the Metal shader cache off. The Vulkan figures are from
[#779](https://github.com/leehack/llamadart/issues/779). The CPU compiles
nothing; its first image is as fast as the next.

`warmUp` moves the pipeline compile off the first real image. It runs one
single-step generation at the size and guidance it is given, with the
request fallbacks otherwise, and discards it:

```dart
final engine = await ImageGenerationEngine.load(model);
// While the user writes the prompt:
await engine.warmUp(width: 1024, height: 1024, guidanceScale: 1);
```

- Warm up at the size and guidance the app will generate. ggml picks some pipelines by tensor size: on the
  M4 Max a 64x64 warm-up left about 0.1 s of the 512x512 compile, while a
  512x512 warm-up left none.
- For the desktop models a warm-up is one sampling step and a decode at
  1024x1024: about 2 to 4 s for SDXL-Lightning with TAESDXL on the
  M4 Max, and the same peak memory as an image, which the
  [memory check](./image-generation-memory-and-limits#memory-check) covers where it runs.
- It moves the cost, it does not remove it. Call it while the user is not
  waiting, such as right after `load` while they type; `load`, `warmUp` and
  `generate` back to back take no less time than `load` and `generate`.
- It holds the one-operation slot: await it before the next `generate` or
  `load`, which otherwise throw `LlamaStateException`. `dispose()` cancels a
  running warm-up, which then completes normally.
- On the CPU it returns at once.

`warmUp` cannot move the Metal library compile, which happens before an
engine exists. To keep a Flutter UI responsive on a first launch, check the
runtime with `checkRuntime()` and show a progress indicator until it
completes:

```dart
final capabilities = await ImageGenerationEngine.checkRuntime();
```

With an empty shader cache on the M4 Max, probing on the calling isolate
stalled a 10 ms timer for the whole 16 s probe. During `checkRuntime()` the
timer kept firing, with gaps of 13 to 31 ms in most
runs. One pause remains: a garbage collection on the calling isolate waits
while the probe isolate loads the runtime library (0.4 to 0.5 s), so an
allocating UI can pause once for up to that long (179 ms in the chat
example's macOS E2E). Calls that overlap share one probe. The compiled
library belongs to the process, so later probes return at once. `load()`
probes the same way and does not block the caller either.

## Progress phases

The runtime reports all progress as `(step, steps)` pairs with no phase, so
the engine labels each report from the sequence:

1. `encodingPrompt` when the generation starts.
2. `sampling` with `0/steps` when each image's first step starts, then one
   event per step. `imageIndex` says which image.
3. `decoding` with `0/count` after the last image's last step, then the final
   event. The runtime reports decoding progress only when it decodes in tiles.

A [hires fix](./image-generation-advanced#hires-fix) samples every image twice: the second pass's
events have `pass` 1 and its own step total, and decoding follows it.

`loading` appears only if the runtime loads weights lazily, which the engine
avoids by loading them eagerly.

The runtime records its reports and the engine reads them every 50 ms, so
progress events arrive in groups, up to about 50 ms after the runtime made
the report. Every report still becomes its events, in order, and the last
ones arrive before the final event. A calling isolate that is busy delays
them further.

## Cancellation, concurrency and disposal

- `task.cancel()` stops before the next sampling step or before decoding;
  `task.done` then reports `cancelled` and `task.result` throws
  `LlamaStateException`. A cancel issued before the runtime starts is honored
  too, up to 50 ms after it starts.
- stable-diffusion.cpp reports progress for the whole process, not per
  model, so one generation or model load runs at a time. Another `generate`
  or `load` meanwhile throws `LlamaStateException`, even on a different
  engine. The guard covers engines in one isolate; do not generate from
  several isolates at once, or each sees the other's progress.
- `dispose()` cancels a running generation, waits for it, and frees the model.
  The task reports `cancelled`, and its `result` and `generateImage` throw
  `LlamaStateException`, as does `generate` after `dispose()`.
- `dispose()` is idempotent: later calls return the first call's future.
  `isDisposed` turns true at the first call, and `await engine.capabilities`
  then reports the engine as unsupported. `capabilities` never throws and
  changes only on `dispose()`, so a Flutter app can read it once after
  `load` and keep it in its state for `build`.
- A process that ends with an image model loaded, loading or generating no
  longer aborts on macOS Metal in the cases llamadart has run: a Dart program
  that returns from `main` or dies of an error, a Flutter macOS quit, and a
  native host's C `exit()` (see [Model lifecycle](./model-lifecycle) for what
  each one waits for). Nothing cancels a running generation when a Dart
  program ends or dies of an error, or a Flutter app quits or hot restarts,
  so the process stays, and a hot restart waits, until the generation
  finishes. The wait is the rest of the generation, with no upper bound: for
  example 4.8 s for the rest of a 40-step SDXS generation and 11.2 s for
  SD-Turbo in a Flutter macOS quit on an M4 Max. A native host's C `exit()`
  cancels the generation and waits up to 15 seconds for it.
- Still dispose the engine before a Flutter app quits: the quit otherwise
  waits for a running generation, and the cleanup at exit has been measured
  on macOS only. Flutter desktop apps do not run
  `State.dispose` on quit, so await `dispose()` in
  `AppLifecycleListener.onExitRequested`. If `ImageGenerationEngine.load` is
  still running, await it there and dispose the engine it returns. If the
  engine's owner can be disposed before quit, such as a pushed route, use one
  app-level exit listener that also awaits a disposal the owner already
  started; see [Model lifecycle](./model-lifecycle).
- Generation runs in a worker isolate; the calling isolate stays responsive.
