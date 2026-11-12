---
title: On-device image generation (Preview)
sidebar_label: Image generation (Preview)
description: Generate images from text prompts on device with the Preview ImageGenerationEngine and the opt-in stable-diffusion.cpp runtime.
---

:::warning Preview
Image generation is a Preview.

- The `ImageGenerationEngine` API is experimental and may change in a later
  release.
- The `stable_diffusion` runtime is opt-in: an app bundles it only when it
  [names it in `pubspec.yaml`](#bundle-the-runtime).
- SDXS and SD-Turbo are validated with real models on macOS (M4 Max), iOS
  (iPhone 16 Pro, iPhone SE 3), Android (Pixel 9 Pro, Galaxy S24,
  Galaxy A53), Linux x64 and Windows x64
  ([#779](https://github.com/leehack/llamadart/issues/779)). The
  [desktop presets](#desktop-presets) are validated on macOS Metal only
  ([#802](https://github.com/leehack/llamadart/issues/802)).
- Open limits: no web runtime yet
  ([#780](https://github.com/leehack/llamadart/issues/780)); Vulkan GPU
  memory is not checked before loading
  ([stable-diffusion-native#9](https://github.com/leehack/stable-diffusion-native/issues/9));
  the automatic attention and VAE settings were measured on an M4 Max and
  still need re-measuring on Android phones and iPhone
  ([#805](https://github.com/leehack/llamadart/issues/805)); the chat app's
  image end-to-end test has not been re-run on a physical iPhone since its
  last fix ([#789](https://github.com/leehack/llamadart/issues/789)).
- Model licenses differ, including on commercial use; see
  [Model licenses](#model-licenses).
:::

`ImageGenerationEngine` turns a text prompt into images on the device. It runs
[stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) through
the opt-in `stable_diffusion` native runtime, separately from `LlamaEngine`.

The API is experimental. Two small, distilled SD 1.x/2.x-family presets are
validated on phones and desktops: SDXS-512 and SD-Turbo.
[Desktop presets](#desktop-presets) cover SDXL-Lightning, FLUX.1-schnell,
SD 3.5 Large Turbo and Z-Image-Turbo on desktop GPUs and Macs (validated
on macOS Metal only), and [`.custom`](#larger-models-with-custom) loads
other families. It is text-to-image only: no image-to-image, inpainting,
LoRA or ControlNet yet.

## Support

| Platform | Device | Minimum OS | Notes |
| --- | --- | --- | --- |
| macOS (arm64, x86_64) | Metal, CPU | macOS 13.3 | Validated on an M4 Max |
| iOS (arm64, arm64 and x86_64 simulator) | Metal, CPU | iOS 16.4 | Validated on iPhone 16 Pro and iPhone SE 3 |
| Android arm64 | CPU | Not set by llamadart | Needs Armv8.2 dot-product and fp16 (`asimddp`, `fphp`, `asimdhp`); validated on Pixel 9 Pro, Galaxy S24 and Galaxy A53; no x64 runtime |
| Linux (arm64, x64) | CPU, or Vulkan with the Vulkan build | Not set by llamadart | x64 CPUs need AVX2, FMA, F16C and BMI2; validated on x64 with CPU and an NVIDIA L4 |
| Windows x64 | CPU, or Vulkan with the Vulkan build | Not set by llamadart | Needs the latest Microsoft Visual C++ v14 Redistributable (x64) and AVX2; the Vulkan build needs a GPU driver that provides `vulkan-1.dll`; validated on Windows Server 2022 with CPU and an NVIDIA L4; no arm64 runtime |
| Web | None | | `load` throws `LlamaUnsupportedException` |

Measured with the prototype on the same runtime, 512x512, one step, warm:

| Device | SDXS Q8 (651 MB) | SD-Turbo Q8 + TAESD (1.9 GB) |
| --- | --- | --- |
| M4 Max, Metal | 1.5 s | 1.2 s |
| iPhone 16 Pro, Metal | 1.7 s | 4.1 s |
| Galaxy S24, CPU | 5.9 s | 11.8 s |
| Galaxy A53, CPU | 26 to 29 s | Refused by the [memory check](#memory-check) |

`await ImageGenerationEngine.checkRuntime()` reports whether this build and
device can generate images, and why not, without loading a model or blocking
the calling isolate. `ImageGenerationEngine.runtimeCapabilities()` returns the
same result synchronously, but its first call can block for seconds; see
[First-image latency and warm-up](#first-image-latency-and-warm-up).

## Bundle the runtime

The runtime adds about 40 to 70 MB per target, so it is never bundled by
default. Name it in the app's `pubspec.yaml`, then run `flutter clean` once:

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_runtimes: [llama_cpp, stable_diffusion]
```

Linux and Windows get the Vulkan build when `llamadart_native_backends`
selects Vulkan, which it does by default; set
`llamadart_stable_diffusion_backends: [cpu]` for the CPU build. See
[Native runtime configuration](../platforms/native-build-hooks#opt-in-stable_diffusion-runtime-experimental).

Flutter iOS and macOS apps should also add the companion package, which links
the runtime's XCFramework through Swift Package Manager and selects the
runtime on those platforms by itself, adding about 37 MB per Apple target. It
needs core `0.10.0` or newer; older cores ignore it:

```yaml
dependencies:
  llamadart_stable_diffusion_flutter: ^0.0.1
```

Without it, the hook bundles the runtime into a framework that Flutter marks
`MinimumOSVersion` 13.0 while the library needs iOS 16.4, so App Store Connect
rejects the iOS upload. The iOS build reports this as an Xcode build warning,
which Xcode and `xcodebuild` show but plain `flutter build` and `flutter run`
output does not. See
[Flutter Apple apps](../platforms/native-build-hooks#flutter-apple-apps).

## Get a model

| Preset | Files | Defaults |
| --- | --- | --- |
| `ImageGenerationModel.sdxs(path)` | `sdxs-512-tinySDdistilled_Q8_0.gguf` from [`concedo/sdxs-512-tinySDdistilled-GGUF`](https://huggingface.co/concedo/sdxs-512-tinySDdistilled-GGUF) (651 MB) | 512x512, 1 step, guidance 1 |
| `ImageGenerationModel.sdTurbo(path, taesdPath: ...)` | `sd_turbo-f16-q8_0.gguf` from [`Green-Sky/SD-Turbo-GGUF`](https://huggingface.co/Green-Sky/SD-Turbo-GGUF) (1.9 GB), optionally `diffusion_pytorch_model.safetensors` from [`madebyollin/taesd`](https://huggingface.co/madebyollin/taesd) (9 MB) | 512x512, 1 step, guidance 1 |
| `ImageGenerationModel.sdxlLightning(path, vaePath: ..., taesdPath: ...)` | `sdxl_lightning_4step.safetensors` from [`ByteDance/SDXL-Lightning`](https://huggingface.co/ByteDance/SDXL-Lightning) (6.9 GB), optionally [`madebyollin/taesdxl`](https://huggingface.co/madebyollin/taesdxl) | 1024x1024, 4 steps, guidance 1, Euler, `sgmUniform` |
| `ImageGenerationModel.flux1Schnell(...)` | `flux1-schnell-Q4_0.gguf` and `ae.safetensors` from [`second-state/FLUX.1-schnell-GGUF`](https://huggingface.co/second-state/FLUX.1-schnell-GGUF) (7.0 GB), `clip_l-Q8_0.gguf` and `t5xxl-Q8_0.gguf` (5.3 GB); [`madebyollin/taef1`](https://huggingface.co/madebyollin/taef1) can replace `ae` | 1024x1024, 4 steps, guidance 1 |
| `ImageGenerationModel.sd35LargeTurbo(...)` | `sd3.5_large_turbo-Q4_0.gguf` from [`city96/stable-diffusion-3.5-large-turbo-gguf`](https://huggingface.co/city96/stable-diffusion-3.5-large-turbo-gguf) (4.8 GB), `clip_l`, `clip_g` and `t5xxl` Q8_0 from [`second-state/stable-diffusion-3.5-medium-GGUF`](https://huggingface.co/second-state/stable-diffusion-3.5-medium-GGUF) (6.1 GB), and [`madebyollin/taesd3`](https://huggingface.co/madebyollin/taesd3) or an SD 3.5 VAE | 1024x1024, 4 steps, guidance 1 |
| `ImageGenerationModel.zImageTurbo(...)` | `z_image_turbo-Q4_K.gguf` from [`leejet/Z-Image-Turbo-GGUF`](https://huggingface.co/leejet/Z-Image-Turbo-GGUF) (3.9 GB), `Qwen3-4B-Instruct-2507-Q4_K_M.gguf` from [`unsloth/Qwen3-4B-Instruct-2507-GGUF`](https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF) (2.5 GB) and FLUX's `ae.safetensors` | 1024x1024, 8 steps, guidance 1 |
| `ImageGenerationModel.custom(files, defaults: ...)` | Any other checkpoint stable-diffusion.cpp loads, single-file or split | 512x512, 20 steps, guidance 7 |

SDXS is distilled for exactly one step. SD-Turbo takes one to four steps; four
add detail at about four times the sampling time. TAESD replaces the full VAE
decoder: several times faster and far less memory, at a small quality cost.
Use it on phones. `taesd_decoder.safetensors` from the same repository is
rejected by the runtime; use `diffusion_pytorch_model.safetensors`.

The engine takes local files. Download them with the package-managed cache,
which resumes interrupted downloads:

```dart
final downloads = DefaultModelDownloadManager();
final entry = await downloads.ensureModel(
  ModelSource.parse(
    'hf://concedo/sdxs-512-tinySDdistilled-GGUF/'
    'sdxs-512-tinySDdistilled_Q8_0.gguf',
  ),
);
final model = ImageGenerationModel.sdxs(entry.filePath);
```

### Model licenses

Each preset's weights carry their own license, and commercial-use terms
differ between them. llamadart does not license any model; check the license
on the linked model card before you ship or use a model commercially. Licenses
as stated on the pinned repositories and their upstream model cards:

| Preset | Model license | Other files |
| --- | --- | --- |
| SDXS | CreativeML Open RAIL++-M, per [`concedo/sdxs-512-tinySDdistilled-GGUF`](https://huggingface.co/concedo/sdxs-512-tinySDdistilled-GGUF) and its upstream [`IDKiro/sdxs-512-dreamshaper`](https://huggingface.co/IDKiro/sdxs-512-dreamshaper) | None |
| SD-Turbo | [Stability AI Community License](https://huggingface.co/stabilityai/sd-turbo/blob/main/LICENSE.md), per [`stabilityai/sd-turbo`](https://huggingface.co/stabilityai/sd-turbo), whose card says to see [stability.ai/license](https://stability.ai/license) for commercial use | TAESD: MIT ([`madebyollin/taesd`](https://huggingface.co/madebyollin/taesd)) |
| SDXL-Lightning | [CreativeML Open RAIL++-M](https://huggingface.co/ByteDance/SDXL-Lightning/blob/main/LICENSE.md), per [`ByteDance/SDXL-Lightning`](https://huggingface.co/ByteDance/SDXL-Lightning) | TAESDXL: MIT ([`madebyollin/taesdxl`](https://huggingface.co/madebyollin/taesdxl)) |
| FLUX.1-schnell | Apache 2.0, per [`black-forest-labs/FLUX.1-schnell`](https://huggingface.co/black-forest-labs/FLUX.1-schnell) and [`second-state/FLUX.1-schnell-GGUF`](https://huggingface.co/second-state/FLUX.1-schnell-GGUF), which also hosts `ae`, `clip_l` and `t5xxl` | TAEF1: MIT ([`madebyollin/taef1`](https://huggingface.co/madebyollin/taef1)) |
| SD 3.5 Large Turbo | [Stability AI Community License](https://huggingface.co/stabilityai/stable-diffusion-3.5-large-turbo/blob/main/LICENSE.md), per the gated [`stabilityai/stable-diffusion-3.5-large-turbo`](https://huggingface.co/stabilityai/stable-diffusion-3.5-large-turbo), whose card limits free commercial use to organizations or individuals under $1M in total annual revenue and asks those above it for an Enterprise License; [`city96/stable-diffusion-3.5-large-turbo-gguf`](https://huggingface.co/city96/stable-diffusion-3.5-large-turbo-gguf) keeps the original terms | Text encoders from [`second-state/stable-diffusion-3.5-medium-GGUF`](https://huggingface.co/second-state/stable-diffusion-3.5-medium-GGUF): Stability AI Community License; TAESD3: MIT ([`madebyollin/taesd3`](https://huggingface.co/madebyollin/taesd3)) |
| Z-Image-Turbo | Apache 2.0, per [`Tongyi-MAI/Z-Image-Turbo`](https://huggingface.co/Tongyi-MAI/Z-Image-Turbo) and [`leejet/Z-Image-Turbo-GGUF`](https://huggingface.co/leejet/Z-Image-Turbo-GGUF) | Qwen3-4B-Instruct-2507: [Apache 2.0](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507/blob/main/LICENSE) ([`unsloth/Qwen3-4B-Instruct-2507-GGUF`](https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF)); `ae` as for FLUX.1-schnell |

A model loaded with `.custom` carries its own license.

### Desktop presets

The SDXL-Lightning, FLUX.1-schnell, SD 3.5 Large Turbo and Z-Image-Turbo
presets generate at 1024x1024 unless a request sets another size. They are
for desktop GPUs and Macs, not phones. Measured from
[#802](https://github.com/leehack/llamadart/issues/802), first image in a new
process, automatic attention and VAE settings:

| Preset | M4 Max, Metal: time, peak process memory | Memory check asks for | NVIDIA L4, Vulkan (native CLI, warm) |
| --- | --- | --- | --- |
| SDXL-Lightning + TAESDXL | 6.1 s, 7.8 GiB (12.1 s with the checkpoint's VAE) | 8.6 GiB | 4.4 s |
| FLUX.1-schnell Q4_0 + TAEF1 | 61 s, 12.9 GiB | 14.5 GiB | 25.3 s with `ae` |
| SD 3.5 Large Turbo Q4_0 + TAESD3 | 16.1 s, 12.3 GiB | 13.1 GiB | 19.4 s with the SD 3.5 VAE |
| Z-Image-Turbo Q4_K | 91 s, 7.8 GiB | 8.3 GiB | 35.0 s (Q8_0) |

The Vulkan figures come from stable-diffusion.cpp's own CLI on the same
runtime commit with `vae_conv_direct`, which the engine now sets on Vulkan;
llamadart itself was not run there. The tiny autoencoders (TAESDXL, TAEF1,
TAESD3) cut 6 to 9 s from each 1024x1024 decode on the M4 Max with no visible
quality loss in these samples. The SD 3.5 VAE repository is gated, so TAESD3
is the ungated choice. `flux1Schnell` and `sd35LargeTurbo` throw
`ArgumentError` without `vaePath` or `taesdPath`.

### Larger models with `.custom`

`.custom` is experimental. It loads any family the bundled
stable-diffusion.cpp supports, including other SDXL, SD 3.5, FLUX, Z-Image
and Qwen-Image checkpoints. These need several GB of memory and are meant for desktop GPUs
and Macs. Each family takes its own files in `ImageGenerationModelFiles`:

| Family | Files |
| --- | --- |
| SD 1.x, 2.x, SDXL | `model` (single file), optionally `vae` or `taesd` |
| SD 3.5 | `diffusionModel`, `vae` or `taesd`, `clipL`, `clipG`, `t5xxl`; a single-file GGUF that includes the VAE and encoders, such as SD 3.5 Medium, goes in `model` instead |
| FLUX | `diffusionModel`, `vae` or `taesd`, `clipL`, `t5xxl` |
| Z-Image, Qwen-Image | `diffusionModel`, `vae`, `llm` (the language-model text encoder) |

Give each model its size and sampling defaults; the size defaults to
512x512, so set 1024x1024 for families trained at it. Settings run in
[#802](https://github.com/leehack/llamadart/issues/802) (SD 3.5 Medium took
about 3 minutes per 1024x1024 image on an M4 Max, Qwen-Image about 11):

```dart
final sd35Medium = ImageGenerationModel.custom(
  const ImageGenerationModelFiles(
    model: 'sd3.5_medium-Q8_0.gguf', // includes the VAE
    clipL: 'clip_l-Q8_0.gguf',
    clipG: 'clip_g-Q8_0.gguf',
    t5xxl: 't5xxl-Q8_0.gguf',
  ),
  defaults: const ImageGenerationDefaults(
    width: 1024,
    height: 1024,
    steps: 28,
    guidanceScale: 4.5,
  ),
);
final qwenImage = ImageGenerationModel.custom(
  const ImageGenerationModelFiles(
    diffusionModel: 'Qwen_Image-Q4_0.gguf',
    vae: 'qwen_image_vae.safetensors',
    llm: 'Qwen2.5-VL-7B-Instruct.Q4_K_M.gguf',
  ),
  defaults: const ImageGenerationDefaults(
    width: 1024,
    height: 1024,
    steps: 20,
    guidanceScale: 2.5,
    flowShift: 3,
  ),
);
```

`sampler`, `scheduler` and `flowShift` can also be set per request. Left
unset, the runtime picks the model's own: Euler for SD 3.5, FLUX and Z-Image,
Euler ancestral with the discrete schedule for SD 1.x, 2.x and SDXL.
`flowShift` applies only to flow-matching models; Qwen-Image's reference
settings use 3.

## Generate

```dart
final engine = await ImageGenerationEngine.load(
  model,
  options: const ImageGenerationOptions(device: ImageGenerationDevice.auto),
);
print('${engine.capabilities.modelVersion} on '
    '${engine.capabilities.backendName}');

final task = engine.generate(
  const ImageGenerationRequest(
    prompt: 'a red fox in autumn leaves',
    seed: 42,
  ),
);
await for (final event in task.events) {
  switch (event) {
    case ImageGenerationProgressEvent(:final phase, :final step, :final steps):
      print('$phase $step/$steps');
    case ImageGenerationFinalEvent(:final result):
      final png = result.images.first.toPng();
      print('${png.length} PNG bytes, seed ${result.seed}');
  }
}
await engine.dispose();
```

`engine.generateImage(request)` is the one-call form; it returns the
`ImageGenerationResult` or throws the failure.

- Width and height are multiples of 8 from 64 to 2048. Unset, each uses the
  model's default (`ImageGenerationDefaults.width` and `height`), its native
  size: 512x512 for SDXS, SD-Turbo and `.custom`, 1024x1024 for the desktop
  presets. SDXS and SD-Turbo also work at 256. The runtime rounds the
  size up to a multiple of 64 for these models, so a 200x136 request produces
  256x192; `GeneratedImage.width` and `height` report the real size.
- `steps`, `guidanceScale`, `sampler`, `scheduler` and `flowShift` fall back
  to the model's defaults. A guidance of
  1 skips the negative prompt and halves the work per step.
- A `null` seed picks one at random. `result.seed` reports the seed used, and
  image `i` of `count` used `seed + i`. The same seed, size, steps and model
  reproduce the same pixels.
- `GeneratedImage.pixels` holds row-major RGB bytes; `toPng()` encodes them.
- Invalid requests throw `LlamaImageGenerationException` before a task
  starts.

`load` loads every weight up front. The first image in a process can still be
slow while the GPU compiles shaders; see
[First-image latency and warm-up](#first-image-latency-and-warm-up).

## Attention and VAE settings

Two runtime settings in `ImageGenerationOptions` change speed and memory.
Direct VAE convolutions leave the image identical; flash attention changes
pixels slightly, by rounding. Left `null`, the engine picks them for the device it loads
on:

| Setting | Automatic choice | Measured |
| --- | --- | --- |
| `flashAttention` (diffusion model) | On for the CPU and Metal, off on Vulkan | M4 Max Metal: SD 3.5 Medium sampling 1.6 times as fast, compute buffer 1.8 GiB to 0.3 GiB; SDXL-Lightning about 10% and FLUX about 5% faster; SD 1.x/2.x sampling time unchanged. M4 Max CPU: SD-Turbo sampling about a fifth faster. Pixels change slightly |
| `vaeDirectConvolution` (full VAE decode) | On, except on Metal and with a tiny autoencoder (`taesd` or SDXS) | NVIDIA L4 Vulkan, 1024x1024, stable-diffusion.cpp's native CLI: decode 23 to 56 s to about 1 s, 4 to 5 GiB less device memory. M4 Max CPU, SD-Turbo 512x512: about 5% slower end to end, peak 3.6 GiB to 2.7 GiB. Metal: about 7 times slower. Identical output |

Vulkan flash attention has not been measured yet, so it stays off there;
pass `flashAttention: true` to try it. The runtime falls back to regular
attention where a device has no kernel for it.

## First-image latency and warm-up

ggml compiles GPU shaders the first time a process needs them, in two places:

- The first runtime probe in a process (`checkRuntime()`,
  `runtimeCapabilities()` or `load()`) initializes the GPU backend. On Apple
  GPUs this compiles ggml's Metal library. `checkRuntime()` and `load()` run
  the probe on a separate isolate; `runtimeCapabilities()` runs it on the
  calling isolate and blocks it.
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
single-step generation and discards it, at the model's size unless given
another:

```dart
final engine = await ImageGenerationEngine.load(model);
// While the user writes the prompt:
await engine.warmUp();
```

- Warm up at the size the app will generate; pass `width` and `height` when
  it is not the model's. ggml picks some pipelines by tensor size: on the
  M4 Max a 64x64 warm-up left about 0.1 s of the 512x512 compile, while a
  512x512 warm-up left none.
- For the desktop presets the default warm-up is one sampling step and a
  decode at 1024x1024: 3.0 to 3.8 s for SDXL-Lightning with TAESDXL on the
  M4 Max, with or without the Metal shader cache, and the same peak memory
  as an image, which the [memory check](#memory-check) already covers.
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

With an empty shader cache on the M4 Max, `runtimeCapabilities()` stalled a
10 ms timer on the calling isolate for the whole 16 s probe. During
`checkRuntime()` the timer kept firing, with gaps of 13 to 31 ms in most
runs. One pause remains: a garbage collection on the calling isolate waits
while the probe isolate loads the runtime library (0.4 to 0.5 s), so an
allocating UI can pause once for up to that long (179 ms in the chat
example's macOS E2E). Calls that overlap share one probe. The compiled
library belongs to the process, so later probes, including
`runtimeCapabilities()`, return at once. `load()` probes the same way and
does not block the caller either.

## Progress phases

The runtime reports all progress through one `(step, steps)` callback, so the
engine labels it from the call sequence:

1. `encodingPrompt` when the generation starts.
2. `sampling` with `0/steps` when each image's first step starts, then one
   event per step. `imageIndex` says which image.
3. `decoding` with `0/count` after the last image's last step, then the final
   event. The runtime reports decoding progress only when it decodes in tiles.

`loading` appears only if the runtime loads weights lazily, which the engine
avoids by loading them eagerly.

## Cancellation, concurrency and disposal

- `task.cancel()` stops before the next sampling step or before decoding, and
  `task.done` then reports `cancelled`. A cancel issued before the runtime
  starts is honored too.
- stable-diffusion.cpp reports progress through one process-wide callback, so
  one generation or model load runs at a time. Another `generate` or `load`
  meanwhile throws `LlamaStateException`, even on a different engine. The guard
  covers engines in one isolate; do not generate from several isolates at
  once.
- `dispose()` cancels a running generation, waits for it, and frees the model.
  `generateImage` then throws `LlamaStateException`.
- Free the model before a Flutter app quits: on macOS Metal, quitting with a
  model still loaded aborts the process. A Dart program that ends with the
  model loaded frees it on the way out and does not abort, unless it dies of
  an error while the model loads or generates (see
  [Model lifecycle](./model-lifecycle)); a Flutter app's quit skips that
  cleanup. Flutter desktop apps do not run
  `State.dispose` on quit, so await `dispose()` in
  `AppLifecycleListener.onExitRequested`. If `ImageGenerationEngine.load` is
  still running, await it there and dispose the engine it returns. If the
  engine's owner can be disposed before quit, such as a pushed route, use one
  app-level exit listener that also awaits a disposal the owner already
  started; see [Model lifecycle](./model-lifecycle).
- Generation runs in a worker isolate; the calling isolate stays responsive.

## Memory check

Before loading, the engine estimates the model's peak memory as its file
sizes plus a quarter, plus 512 MiB, and compares that with the memory of the
device the model loads on:

| Platform and device | Compared with |
| --- | --- |
| Android: CPU | The larger of `MemAvailable` and half of `MemTotal` less the app's own memory (`VmRSS` plus `VmSwap`), from `/proc` |
| Linux: CPU | `MemAvailable` from `/proc/meminfo` |
| iOS: Metal or CPU | The app's remaining memory limit (`os_proc_available_memory`) |
| macOS: CPU | Physical memory |
| macOS: Metal | Physical memory, capped at the GPU's `recommendedMaxWorkingSetSize` (about two thirds to three quarters of it) |
| Linux, Windows: Vulkan | Not checked: the weights live in GPU memory, which the runtime does not report yet ([stable-diffusion-native#9](https://github.com/leehack/stable-diffusion-native/issues/9)) |
| Windows: CPU | Not checked |

A model that does not fit throws `LlamaModelException` naming both figures,
instead of the system killing the app. Set
`ImageGenerationOptions(checkMemory: false)` to load anyway.

On Android, `MemAvailable` alone is too strict: it leaves out the memory the
low-memory killer frees by stopping cached apps and what it swaps to zram,
and it varied by up to a gigabyte between idle readings. On Firebase Test
Lab, an app that kept touching all of its memory was killed only after
allocating 0.9 to 3.6 GiB more than `MemAvailable`:

| Phone (RAM) | `MemTotal` | `MemAvailable` at idle | Allocated when killed | Half of `MemTotal` less the app |
| --- | --- | --- | --- | --- |
| Moto G Play 2024 (4 GB) | 3.57 GiB | 1.38 GiB | 2.31 GiB | 1.45 GiB |
| Galaxy A53 (6 GB) | 5.26 GiB | 1.81 GiB | 2.81 GiB | 2.31 GiB |
| Pixel 6a (6 GB) | 5.45 GiB | 1.87 GiB | 3.63 GiB | 2.37 GiB |
| Galaxy S24 (8 GB) | 6.95 GiB | 2.38 GiB | 3.88 GiB | 3.10 GiB |
| Pixel 8a (8 GB) | 7.38 GiB | 2.56 GiB | 4.81 GiB | 3.29 GiB |
| Pixel 9 Pro (16 GB) | 15.19 GiB | 9.13 GiB | 12.75 GiB | 7.18 GiB |

So 8 GB phones load SD-Turbo with TAESD (2.87 GiB estimated) even when
`MemAvailable` reads 2.1 GiB, unless the app already holds more than about
0.6 GiB, such as a loaded chat model, and 6 GB phones refuse it unless
`MemAvailable` alone covers it. With the check
off, no SD-Turbo variant was killed on these phones, but the Galaxy A53
swapped most of the app out: a one-step image took 65 s with TAESD and 282 s
with the full VAE, against 18 s and 67 s on the Pixel 6a.

The estimate does not depend on the image size. It covers the measured peaks
at each model's native size, which requests and `warmUp` use unless they set
another, with the automatic attention and VAE settings:
SDXS used 1.30 GiB and SD-Turbo on the CPU 2.66 GiB of process memory on an
M4 Max; on five Android phones, loading and generating at 512x512 added at
most 1.16 GiB to the app for SDXS, 2.26 GiB for SD-Turbo with TAESD and
2.64 GiB for SD-Turbo with its full VAE (estimates 1.30, 2.87 and 2.86 GiB);
and 1024x1024 SDXL, SD 3.5 Large Turbo, FLUX and Z-Image stayed 0.5
to 1.6 GiB under it on Metal. SD 3.5 Medium, whose single file decodes with
the full VAE, peaked 0.3 GiB above it (11.6 against 11.3 GiB). Larger sizes
need more, especially on the CPU: SD-Turbo at 1024x1024
peaked at 4.7 GiB there. On a Vulkan GPU too small for the model,
stable-diffusion.cpp keeps some weights in host memory, which is slower but
does not fail the load.

## Errors

| Exception | When |
| --- | --- |
| `LlamaUnsupportedException` | The runtime is not bundled, the platform or CPU is unsupported, on the web, or `ImageGenerationDevice.gpu` without a GPU |
| `LlamaModelException` | A file is missing, the model does not fit, or the runtime cannot load it as an image model. A rejected split checkpoint names the roles it lacks, such as a VAE or text encoder, and `details` lists the roles passed |
| `LlamaImageGenerationException` | An invalid request or options |
| `LlamaStateException` | Another generation or load is running, or the engine is disposed |
| `LlamaInferenceException` | The runtime failed a generation, for example an aborted Metal command buffer or running out of memory; the engine runs the next request |

## Known limits

- Runtime logs are not forwarded to `LlamaLogger`: stable-diffusion.cpp's log
  text is only valid during a call made from its own threads
  ([stable-diffusion-native#3](https://github.com/leehack/stable-diffusion-native/issues/3)).
  ggml's own backend messages still reach stderr. The same gap keeps the
  runtime's own reason out of a load failure; the error names missing file
  roles instead.
- Android runs on the CPU only: ggml Vulkan and OpenCL crashed or ran slower
  on the phones tried
  ([stable-diffusion-native#2](https://github.com/leehack/stable-diffusion-native/issues/2)).
- iOS can abort a Metal command buffer under GPU pressure (seen once with
  SD-Turbo at four steps); the task fails and the next request runs.
- Windows and Vulkan GPUs are not memory-checked. Per-platform validation
  results, including timings, are in
  [#779](https://github.com/leehack/llamadart/issues/779).
- The web has no image runtime yet
  ([#780](https://github.com/leehack/llamadart/issues/780)).

The [basic app](../examples/basic-app) has a command-line image example, and
the [chat app](../examples/chat-app) has an image screen that downloads SDXS
or SD-Turbo with TAESD and generates on device. The command-line example
also runs the desktop presets from pinned downloads.
