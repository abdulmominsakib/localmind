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
  [desktop models](#desktop-models) are validated on macOS Metal only
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

The API is experimental. Two small, distilled SD 1.x/2.x-family models are
validated on phones and desktops: SDXS-512 and SD-Turbo.
[Desktop models](#desktop-models) cover SDXL-Lightning, FLUX.1-schnell,
SD 3.5 Large Turbo and Z-Image-Turbo on desktop GPUs and Macs (validated
on macOS Metal only), and [other families](#other-families) load the same
way; the [recipes](#recipes) give each one's files and settings. It is text-to-image only: no image-to-image, inpainting,
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
the calling isolate. Its first call in a process can take seconds; see
[First-image latency and warm-up](#first-image-latency-and-warm-up).
`ImageGenerationCapabilities` implements `EngineCapabilities`, like every
engine's capabilities.

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
runtime on those platforms by itself, adding about 37 MB per Apple target.
Pair `0.0.2` with core `0.11.0`; cores older than `0.10.0` ignore it:

```yaml
dependencies:
  llamadart_stable_diffusion_flutter: ^0.0.2
```

Without it, the hook bundles the runtime into a framework that Flutter marks
`MinimumOSVersion` 13.0 while the library needs iOS 16.4, so App Store Connect
rejects the iOS upload. The iOS build reports this as an Xcode build warning,
which Xcode and `xcodebuild` show but plain `flutter build` and `flutter run`
output does not. See
[Flutter Apple apps](../platforms/native-build-hooks#flutter-apple-apps).
The hook-bundled runtime also cannot carry an Apple privacy manifest. The
companion's XCFramework carries one from `stable-diffusion-native` `v0.2.0-1`,
which `llamadart_stable_diffusion_flutter` releases after `0.0.1` link; see
[Apple privacy manifest](../platforms/native-build-hooks#apple-privacy-manifest)
for the File Timestamp reasons (`C617.1`, `3B52.1`) an app declares itself
when its `stable_diffusion.framework` has no manifest.

## Get a model

A model is its main file and the other files it needs, each a
`ModelSource`: a local file (`ModelSource.path`), an HTTP(S) URL or a
Hugging Face file. `ImageGenerationEngine.load` downloads what is not local
and gives each file its runtime role from its header, so the files can be
listed in any order:

```dart
final cancel = ModelDownloadCancelToken();
final engine = await ImageGenerationEngine.load(
  ImageGenerationModel(
    ModelSource.parse(
      'hf://second-state/FLUX.1-schnell-GGUF@'
      '8c45a2ba25e2d02bd34230989fb54983f39e44ec/flux1-schnell-Q4_0.gguf',
    ),
    components: [
      ImageModelComponent.auto(ModelSource.path('ae.safetensors')),
      ImageModelComponent.auto(ModelSource.path('clip_l-Q8_0.gguf')),
      ImageModelComponent.auto(ModelSource.path('t5xxl-Q8_0.gguf')),
    ],
  ),
  params: const ImageModelParams(device: ComputeDevice.auto),
  download: ModelLoadOptions(cancelToken: cancel),
  onProgress: (progress) => print(progress.fraction),
);
```

### Roles

The engine reads only each file's header: the GGUF metadata and tensor
names, or the safetensors header. A GGUF whose `general.architecture` names a
llama.cpp language model, such as `qwen3`, is the `llm` text encoder; reading
stops there. Each file gets one `ImageModelRole`:

| Role | Files | Used by |
| --- | --- | --- |
| `checkpoint` | A single file with diffusion weights, usually with its VAE and text encoders | SD 1.x, 2.x, SDXL, SD 3.5 Medium |
| `diffusionModel` | A split model's UNet or transformer | SD 3.5 Large, FLUX, Z-Image, Qwen-Image |
| `vae` | A VAE | Split models; replaces a checkpoint's own |
| `taesd` | A tiny autoencoder that replaces the VAE decoder | Any family with a matching one |
| `clipL`, `clipG`, `t5xxl` | Text encoders | SDXL-style, SD 3.5, FLUX |
| `llm` | A language-model text encoder | Z-Image, Qwen-Image |

The set needs exactly one `checkpoint` or `diffusionModel` and at most one
file per role. `load` throws `LlamaModelException`, naming files by position
(the main file, component 1, ...) and never by path, for:

- a LoRA adapter, ControlNet, upscaler or vision projector, which text to
  image does not load;
- `taesd_decoder.safetensors`, a decoder-only export the runtime rejects
  (use `diffusion_pytorch_model.safetensors`);
- two files in one role, a checkpoint plus separate diffusion weights, or no
  diffusion weights;
- a VAE or tiny autoencoder for other latent channels than the diffusion
  model's, such as TAESD (4 channels) with FLUX (16);
- a file with no known image-model layout, such as a pickled `.ckpt`.

Give such a file its role yourself with `ImageModelComponent(source, role:
ImageModelRole.vae)`, or `ImageGenerationModel(source, role: ...)` for the
main file. Explicit roles also settle layouts the header cannot tell apart:
TAESD and TAESDXL share one layout, as do TAESD3 and TAEF1, and only their
latent channels are checked. Classification runs on the downloaded file, so a
wrong file costs its download; it stays in the cache.

### Loading options

- `onProgress` reports all files together as a `ModelDownloadProgress`.
  Cached and local files count as received. `totalBytes` is `null` until
  every file's size is known: local files from the start, others when their
  download starts.
- `download:` (`ModelLoadOptions`, as for `LlamaEngine.load`)
  applies to every remote file: cache policy and directory, `bearerToken` and
  headers (for example for a gated repository), resume, retries and the
  cancel token. Local files take only the cancel token. `bearerToken` and
  headers never cross hosts: with them set, remote files on more than one
  origin (scheme, host and port) throw `LlamaArgumentException` before
  anything downloads from a second host.
  `ModelLoadOptions.sha256` verifies a single-file model; with components
  it throws `LlamaUnsupportedException`, since it cannot name one of
  several files.
- A cancelled load throws `LlamaStateException`. Cancelling stops a
  download at once; the native load cannot be interrupted, so a cancel
  during it takes effect when it returns, and the model it loaded is freed.
  A failed download throws what the download manager throws, usually
  `LlamaModelException`, with URL secrets redacted.
- The runtime check, `params:` checks and the check that every local file
  exists run first, so an unsupported platform, including the web, downloads
  nothing.
- A load is atomic: when it throws, nothing stays loaded.
- `store: ModelFileStore(resolver: ..., downloadManager: ...)` replaces the
  defaults, as for `LlamaEngine`. The default download manager caches in the
  same place as `LlamaEngine`'s: on Android and iOS, `llamadart/models` in the
  app's cache directory, or `DefaultModelDownloadManager.globalCacheDirectory`
  when set. Pass
  `ModelFileStore(downloadManager: DefaultModelDownloadManager.appPrivate(cacheDirectory: ...))`
  to keep the weights somewhere else.

`engine.roles` reports the file in each role.

### Recipes

Files pinned to the Hugging Face commits the
[basic app](../examples/basic-app) uses, and the request settings each model
was validated with. Pin a commit (`@<sha>`) so the file cannot change under
the app. The request carries the generation settings; unset, size falls back
to 512x512, steps to 20 and guidance to 7.

**SDXS-512** (683 MB, phones and desktops). Distilled for exactly one step at
guidance 1:

```dart
final sdxs = await ImageGenerationEngine.load(
  ImageGenerationModel(
    ModelSource.parse(
      'hf://concedo/sdxs-512-tinySDdistilled-GGUF@'
      '3144d898d61492f8382ffcabec055733fc5b2a0e/'
      'sdxs-512-tinySDdistilled_Q8_0.gguf',
    ),
  ),
);
const request = ImageGenerationRequest(
  prompt: 'a red fox in autumn leaves',
  steps: 1,
  guidanceScale: 1,
);
```

**SD-Turbo with TAESD** (2.0 GB plus 10 MB). One step at guidance 1, or up to
four for more detail at about four times the sampling time. TAESD replaces
the full VAE decoder: several times faster and far less memory, at a small
quality cost; use it on phones:

```dart
final sdTurbo = await ImageGenerationEngine.load(
  ImageGenerationModel(
    ModelSource.parse(
      'hf://Green-Sky/SD-Turbo-GGUF@19a31586d02d64a73b4419bc193b3ecfaf38e1f0/'
      'sd_turbo-f16-q8_0.gguf',
    ),
    components: [
      ImageModelComponent.auto(
        ModelSource.parse(
          'hf://madebyollin/taesd@614f76814bbe30edbe2e627ace1c2234c81a2c0e/'
          'diffusion_pytorch_model.safetensors',
        ),
      ),
    ],
  ),
);
const request = ImageGenerationRequest(
  prompt: 'a lighthouse at dusk',
  steps: 1,
  guidanceScale: 1,
);
```

**SDXL-Lightning 4-step** (6.9 GB plus 10 MB). 1024x1024, 4 Euler steps on
the `sgmUniform` schedule at guidance 1, as the model card recommends.
TAESDXL halved the time per image on an M4 Max; leave it out to decode with
the checkpoint's VAE:

```dart
final sdxlLightning = await ImageGenerationEngine.load(
  ImageGenerationModel(
    ModelSource.parse(
      'hf://ByteDance/SDXL-Lightning@c9a24f48e1c025556787b0c58dd67a091ece2e44/'
      'sdxl_lightning_4step.safetensors',
    ),
    components: [
      ImageModelComponent.auto(
        ModelSource.parse(
          'hf://madebyollin/taesdxl@b20258aaef75ef61e659c1e0f14f251cf0ad153e/'
          'diffusion_pytorch_model.safetensors',
        ),
      ),
    ],
  ),
);
const request = ImageGenerationRequest(
  prompt: 'a lighthouse at dusk',
  width: 1024,
  height: 1024,
  steps: 4,
  guidanceScale: 1,
  sampler: ImageGenerationSampler.euler,
  scheduler: ImageGenerationScheduler.sgmUniform,
);
```

**FLUX.1-schnell** (12.3 GB). 1024x1024, 4 steps at guidance 1, from the
Q4_0 transformer, the FLUX autoencoder and the CLIP-L and T5-XXL encoders.
TAEF1
(`hf://madebyollin/taef1@b1b2d00e9e440cfbf3dedb34266864da86016ceb/diffusion_pytorch_model.safetensors`)
can replace `ae`:

```dart
const fluxRepo =
    'hf://second-state/FLUX.1-schnell-GGUF@'
    '8c45a2ba25e2d02bd34230989fb54983f39e44ec';
const encoders =
    'hf://second-state/stable-diffusion-3.5-medium-GGUF@'
    '58b78c305a43ddfcffe1ab54d7022995f61667ac';
final flux = await ImageGenerationEngine.load(
  ImageGenerationModel(
    ModelSource.parse('$fluxRepo/flux1-schnell-Q4_0.gguf'),
    components: [
      for (final file in [
        '$fluxRepo/ae.safetensors',
        '$encoders/clip_l-Q8_0.gguf',
        '$encoders/t5xxl-Q8_0.gguf',
      ])
        ImageModelComponent.auto(ModelSource.parse(file)),
    ],
  ),
);
const request = ImageGenerationRequest(
  prompt: 'a red fox in autumn leaves',
  width: 1024,
  height: 1024,
  steps: 4,
  guidanceScale: 1,
);
```

**SD 3.5 Large Turbo** (10.9 GB). 1024x1024, 4 steps at guidance 1. The
SD 3.5 VAE repository is gated, so this decodes with TAESD3:

```dart
const encoders =
    'hf://second-state/stable-diffusion-3.5-medium-GGUF@'
    '58b78c305a43ddfcffe1ab54d7022995f61667ac';
final sd35LargeTurbo = await ImageGenerationEngine.load(
  ImageGenerationModel(
    ModelSource.parse(
      'hf://city96/stable-diffusion-3.5-large-turbo-gguf@'
      '527c5548afc123f309238ca6bce7dfe3349aa997/sd3.5_large_turbo-Q4_0.gguf',
    ),
    components: [
      for (final file in [
        'hf://madebyollin/taesd3@d58dcaccd2b36fcb7a6b9e93c1cc507acab5a778/'
            'diffusion_pytorch_model.safetensors',
        '$encoders/clip_l-Q8_0.gguf',
        '$encoders/clip_g-Q8_0.gguf',
        '$encoders/t5xxl-Q8_0.gguf',
      ])
        ImageModelComponent.auto(ModelSource.parse(file)),
    ],
  ),
);
const request = ImageGenerationRequest(
  prompt: 'a red fox in autumn leaves',
  width: 1024,
  height: 1024,
  steps: 4,
  guidanceScale: 1,
);
```

**Z-Image-Turbo** (6.7 GB). 1024x1024, 8 steps at guidance 1, with the
Qwen3-4B text encoder and the FLUX autoencoder:

```dart
final zImageTurbo = await ImageGenerationEngine.load(
  ImageGenerationModel(
    ModelSource.parse(
      'hf://leejet/Z-Image-Turbo-GGUF@c61c0e422dc8b541b7548cf33a4ef8302b0f8085/'
      'z_image_turbo-Q4_K.gguf',
    ),
    components: [
      for (final file in [
        'hf://second-state/FLUX.1-schnell-GGUF@'
            '8c45a2ba25e2d02bd34230989fb54983f39e44ec/ae.safetensors',
        'hf://unsloth/Qwen3-4B-Instruct-2507-GGUF@'
            'a06e946bb6b655725eafa393f4a9745d460374c9/'
            'Qwen3-4B-Instruct-2507-Q4_K_M.gguf',
      ])
        ImageModelComponent.auto(ModelSource.parse(file)),
    ],
  ),
);
const request = ImageGenerationRequest(
  prompt: 'a red fox in autumn leaves',
  width: 1024,
  height: 1024,
  steps: 8,
  guidanceScale: 1,
);
```

### Model licenses

Each model's weights carry their own license, and commercial-use terms
differ between them. llamadart does not license any model; check the license
on the linked model card before you ship or use a model commercially. Licenses
as stated on the repositories in the recipes and their upstream model cards:

| Model | Model license | Other files |
| --- | --- | --- |
| SDXS | CreativeML Open RAIL++-M, per [`concedo/sdxs-512-tinySDdistilled-GGUF`](https://huggingface.co/concedo/sdxs-512-tinySDdistilled-GGUF) and its upstream [`IDKiro/sdxs-512-dreamshaper`](https://huggingface.co/IDKiro/sdxs-512-dreamshaper) | None |
| SD-Turbo | [Stability AI Community License](https://huggingface.co/stabilityai/sd-turbo/blob/main/LICENSE.md), per [`stabilityai/sd-turbo`](https://huggingface.co/stabilityai/sd-turbo), whose card says to see [stability.ai/license](https://stability.ai/license) for commercial use | TAESD: MIT ([`madebyollin/taesd`](https://huggingface.co/madebyollin/taesd)) |
| SDXL-Lightning | [CreativeML Open RAIL++-M](https://huggingface.co/ByteDance/SDXL-Lightning/blob/main/LICENSE.md), per [`ByteDance/SDXL-Lightning`](https://huggingface.co/ByteDance/SDXL-Lightning) | TAESDXL: MIT ([`madebyollin/taesdxl`](https://huggingface.co/madebyollin/taesdxl)) |
| FLUX.1-schnell | Apache 2.0, per [`black-forest-labs/FLUX.1-schnell`](https://huggingface.co/black-forest-labs/FLUX.1-schnell) and [`second-state/FLUX.1-schnell-GGUF`](https://huggingface.co/second-state/FLUX.1-schnell-GGUF), which also hosts `ae`, `clip_l` and `t5xxl` | TAEF1: MIT ([`madebyollin/taef1`](https://huggingface.co/madebyollin/taef1)) |
| SD 3.5 Large Turbo | [Stability AI Community License](https://huggingface.co/stabilityai/stable-diffusion-3.5-large-turbo/blob/main/LICENSE.md), per the gated [`stabilityai/stable-diffusion-3.5-large-turbo`](https://huggingface.co/stabilityai/stable-diffusion-3.5-large-turbo), whose card limits free commercial use to organizations or individuals under $1M in total annual revenue and asks those above it for an Enterprise License; [`city96/stable-diffusion-3.5-large-turbo-gguf`](https://huggingface.co/city96/stable-diffusion-3.5-large-turbo-gguf) keeps the original terms | Text encoders from [`second-state/stable-diffusion-3.5-medium-GGUF`](https://huggingface.co/second-state/stable-diffusion-3.5-medium-GGUF): Stability AI Community License; TAESD3: MIT ([`madebyollin/taesd3`](https://huggingface.co/madebyollin/taesd3)) |
| Z-Image-Turbo | Apache 2.0, per [`Tongyi-MAI/Z-Image-Turbo`](https://huggingface.co/Tongyi-MAI/Z-Image-Turbo) and [`leejet/Z-Image-Turbo-GGUF`](https://huggingface.co/leejet/Z-Image-Turbo-GGUF) | Qwen3-4B-Instruct-2507: [Apache 2.0](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507/blob/main/LICENSE) ([`unsloth/Qwen3-4B-Instruct-2507-GGUF`](https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF)); `ae` as for FLUX.1-schnell |

Any other model carries its own license.

### Desktop models

SDXL-Lightning, FLUX.1-schnell, SD 3.5 Large Turbo and Z-Image-Turbo
generate at 1024x1024 with the recipe settings. They are for desktop GPUs
and Macs, not phones. Measured from
[#802](https://github.com/leehack/llamadart/issues/802), first image in a new
process, automatic attention and VAE settings:

| Model | M4 Max, Metal: time, peak process memory | Memory check asks for | NVIDIA L4, Vulkan (native CLI, warm) |
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
is the ungated choice.

### Other families

Any family the bundled stable-diffusion.cpp supports loads the same way,
including other SDXL, SD 3.5, FLUX, Z-Image and Qwen-Image checkpoints.
These need several GB of memory and are meant for desktop GPUs and Macs.
Settings run in [#802](https://github.com/leehack/llamadart/issues/802)
(SD 3.5 Medium took about 3 minutes per 1024x1024 image on an M4 Max,
Qwen-Image about 11):

| Model | Files | Request settings |
| --- | --- | --- |
| SD 3.5 Medium | `sd3.5_medium-Q8_0.gguf` (a checkpoint with its VAE) plus `clip_l`, `clip_g` and `t5xxl` from [`second-state/stable-diffusion-3.5-medium-GGUF`](https://huggingface.co/second-state/stable-diffusion-3.5-medium-GGUF) | 1024x1024, 28 steps, guidance 4.5 |
| Qwen-Image | `Qwen_Image-Q4_0.gguf`, `qwen_image_vae.safetensors`, `Qwen2.5-VL-7B-Instruct.Q4_K_M.gguf` | 1024x1024, 20 steps, guidance 2.5, `flowShift: 3` |

Left unset, `sampler`, `scheduler` and `flowShift` are the runtime's own for
the model: Euler for SD 3.5, FLUX and Z-Image, Euler ancestral with the
discrete schedule for SD 1.x, 2.x and SDXL. `flowShift` applies only to
flow-matching models.

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
  the desktop models in the recipes. SDXS and SD-Turbo also work at 256. The runtime rounds the
  size up to a multiple of 64 for these models, so a 200x136 request produces
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
Direct VAE convolutions leave the image identical; flash attention changes
pixels slightly, by rounding. Left `null`, the engine picks them for the device it loads
on:

| Setting | Automatic choice | Measured |
| --- | --- | --- |
| `flashAttention` (diffusion model) | On for the CPU and Metal, off on Vulkan | M4 Max Metal: SD 3.5 Medium sampling 1.6 times as fast, compute buffer 1.8 GiB to 0.3 GiB; SDXL-Lightning about 10% and FLUX about 5% faster; SD 1.x/2.x sampling time unchanged. M4 Max CPU: SD-Turbo sampling about a fifth faster. Pixels change slightly |
| `vaeDirectConvolution` (VAE decode) | On, except on Metal and when a tiny autoencoder decodes: a `taesd` file, or a checkpoint whose header shows an embedded one, as SDXS's does | NVIDIA L4 Vulkan, 1024x1024, stable-diffusion.cpp's native CLI: decode 23 to 56 s to about 1 s, 4 to 5 GiB less device memory. M4 Max CPU, SD-Turbo 512x512: about 5% slower end to end, peak 3.6 GiB to 2.7 GiB. Metal: about 7 times slower. Identical output |

With a tiny autoencoder, direct convolutions cost time for little memory:
on an M4 Max CPU they took 1.4 to 1.7 s per 512x512 SDXS image against 1.2
to 1.3 s, for 0.24 GiB less peak process memory. Set `vaeDirectConvolution:
true` where that memory matters more.

Vulkan flash attention has not been measured yet, so it stays off there;
pass `flashAttention: true` to try it. The runtime falls back to regular
attention where a device has no kernel for it.

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
  [memory check](#memory-check) covers where it runs.
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
- Still dispose the engine before a Flutter app quits, so the quit does not
  wait for a generation and does not depend on the cleanup at exit. Flutter
  desktop apps do not run
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
`ImageModelParams(checkMemory: false)` to load anyway.

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
at each model's native size, with the automatic attention and VAE settings:
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
| `LlamaUnsupportedException` | The runtime is not bundled, the platform or CPU is unsupported, on the web, `ComputeDevice.gpu` without a GPU, `ComputeDevice.npu`, or `ModelLoadOptions.sha256` set for a `load` of several files |
| `LlamaModelException` | A file is missing, fails to download or is not an image-model component, two files share a role, a decoder does not match the diffusion model, the model does not fit, or the runtime cannot load it. A rejected split model names the roles it lacks, such as a VAE or text encoder, and `details` lists the roles passed |
| `LlamaImageGenerationException` | An invalid request or `params:` |
| `LlamaStateException` | The load's cancel token cancelled it, another generation or load is running, or the engine is disposed |
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
or SD-Turbo with TAESD from the same pinned files and generates on device.
The command-line example also runs the desktop models from pinned
downloads; both keep their pinned sources and settings in the app.
