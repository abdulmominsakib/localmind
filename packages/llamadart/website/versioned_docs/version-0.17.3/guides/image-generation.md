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
  ([#969](https://github.com/leehack/llamadart/issues/969)); the
  [memory check](./image-generation-memory-and-limits#memory-check)'s warning, refusal and two-GPU paths have not
  been checked on physical Vulkan hardware
  ([#1024](https://github.com/leehack/llamadart/issues/1024)).
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
way; the [recipes](#recipes) give each one's files and settings. Bounded image-to-image and binary-mask editing are available through
`ImageEditingRequest` on the [CPU recipe](./image-generation-advanced#image-editing), and an
SD 1.x ControlNet steers `ControlNetImageGenerationRequest` on the
[bounded CPU recipe](./image-generation-advanced#controlnet). FLUX.1 Kontext [dev] edits a reference
image through `ReferenceImageEditingRequest` on the
[bounded Metal recipe](./image-generation-advanced#reference-image-editing). LoRA has no public
image-generation API yet.

## Support

| Platform | Device | Minimum OS | Notes |
| --- | --- | --- | --- |
| macOS (arm64, x86_64) | Metal, CPU | macOS 13.3 | Validated on an M4 Max |
| iOS (arm64, arm64 and x86_64 simulator) | Metal, CPU | iOS 16.4 | Validated on iPhone 16 Pro and iPhone SE 3 |
| Android arm64 | CPU | Not set by llamadart | Needs Armv8.2 dot-product and fp16 (`asimddp`, `fphp`, `asimdhp`); validated on Pixel 9 Pro, Galaxy S24 and Galaxy A53; no x64 runtime |
| Linux (arm64, x64) | CPU, or Vulkan with the Vulkan build | Not set by llamadart | x64 CPUs need AVX2, FMA, F16C and BMI2; validated on x64 with CPU and an NVIDIA L4 |
| Windows x64 | CPU, or Vulkan with the Vulkan build | Not set by llamadart | Needs the latest Microsoft Visual C++ v14 Redistributable (x64) and AVX2; the Vulkan build needs a GPU driver that provides `vulkan-1.dll`; validated on Windows Server 2022 with CPU and an NVIDIA L4; no arm64 runtime |
| Web | None | | `load` throws `LlamaUnsupportedException` |

Validation evidence for each recipe is listed in
[Feature validation evidence](../maintainers/feature-validation#qualification-procedures).

Measured on the same runtime, 512x512, one step, warm:

| Device | SDXS Q8 (651 MB) | SD-Turbo Q8 + TAESD (1.9 GB) |
| --- | --- | --- |
| M4 Max, Metal | 1.5 s | 1.2 s |
| iPhone 16 Pro, Metal | 1.7 s | 4.1 s |
| Galaxy S24, CPU | 5.9 s | 11.8 s |
| Galaxy A53, CPU | 26 to 29 s | Refused by the [memory check](./image-generation-memory-and-limits#memory-check) |

`await ImageGenerationEngine.checkRuntime()` reports whether this build and
device can generate images, and why not, without loading a model or blocking
the calling isolate. Its first call in a process can take seconds; see
[First-image latency and warm-up](./image-generation-settings#first-image-latency-and-warm-up).
`ImageGenerationCapabilities` implements `EngineCapabilities`, like every
engine's capabilities.

## Bundle the runtime

The runtime adds about 40 to 70 MB per target, so it is never bundled by
default. Name it in the app's `pubspec.yaml`, then run `flutter clean` once:

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_runtimes: all
```

Unset, `llamadart_native_runtimes` bundles `llama_cpp` and `litert_lm`. A list
replaces those defaults, so it names every runtime the app loads. Beside
Flutter Edge AI an implied `litert_lm` is left out; see
[Alongside Flutter Edge AI](../platforms/native-build-hooks#alongside-flutter-edge-ai).

| The app loads | `llamadart_native_runtimes` |
| --- | --- |
| GGUF and `.litertlm` models | unset |
| Images only | `[stable_diffusion]` |
| GGUF models and images | `[llama_cpp, stable_diffusion]` |
| Every runtime published for the target | `all` |

Linux and Windows get the Vulkan build when `llamadart_native_backends`
selects Vulkan, which it does by default; set
`llamadart_stable_diffusion_backends: [cpu]` for the CPU build. See
[Native runtime configuration](../platforms/native-build-hooks#opt-in-stable_diffusion-runtime-experimental).

Flutter iOS and macOS apps should also add the companion package, which links
the runtime's XCFramework through Swift Package Manager and selects the
runtime on those platforms by itself, adding about 37 MB per Apple target.
Use the companion with the core's `MAJOR.MINOR`; the core accepts only an
Apple SD companion pinning its own runtime, so upgrade the core and
`llamadart_stable_diffusion_flutter` together:

```yaml
dependencies:
  llamadart_stable_diffusion_flutter: ^0.17.1
```

Without it, `all` leaves the image runtime out of a Flutter iOS or macOS app
and `ImageGenerationEngine.checkRuntime()` reports it as not bundled. The
build warns about it: `flutter build macos`, Xcode and `xcodebuild` show the
warning, and `flutter build ios` output does not. A list naming
`stable_diffusion` bundles the runtime through the hook instead, into a
framework that Flutter marks `MinimumOSVersion` 13.0 while the library needs
iOS 16.4, so App Store Connect rejects the iOS upload. The iOS build reports
this as an Xcode build warning, which Xcode and `xcodebuild` show but plain
`flutter build` and `flutter run` output does not. See
[Flutter Apple apps](../platforms/apple-setup#companion-packages).
The hook-bundled runtime also cannot carry an Apple privacy manifest; the
companion's XCFramework does. See
[Apple privacy manifest](../platforms/apple-setup#apple-privacy-manifest)
for the File Timestamp reasons (`C617.1`, `3B52.1`) an app declares itself
when its `stable_diffusion.framework` has no manifest.

## Get a model

### Weight formats and layouts

`ImageGenerationEngine` loads **GGUF and Safetensors directly**. Safetensors
does not need conversion to GGUF, and a model can mix containers across its
components. These image-loading rules are separate from `LlamaEngine`'s text
model formats; leave `ModelSource.format` unset for image files.

| Input | Public image API | Qualification / limits |
| --- | --- | --- |
| GGUF file (`.gguf`) | Direct loading; automatic role detection from metadata and tensor names | Use a compatible image checkpoint or component, not an arbitrary LLM GGUF |
| Safetensors file (`.safetensors`) | Direct loading; automatic role detection from tensor names and shapes | Complete SD-Turbo F16 and existing SDXL-Lightning/VAE/TAESD recipes; see the bounded checks below |
| PyTorch checkpoint (`.ckpt`, `.pth`, `.pt`) | Explicit role required; forwarded to the native loader | Selected complete SD-Turbo tensor-only ZIP/nested ZIP/legacy checkpoints pass on macOS CPU; arbitrary layouts remain unqualified ([#1218](https://github.com/leehack/llamadart/issues/1218)) |
| Separate component files | Each file resolves independently and gets a role; GGUF and Safetensors can be mixed | Supply the matching diffusion weights, encoders and decoder from the [recipes](#recipes) |
| Diffusers component directory or repository | No public Diffusers pipeline/repository ingestion | Pass compatible component files individually; this does not describe the separate complete-checkpoint index recipe |
| Complete Safetensors checkpoint index and shards | Opt in with `ImageGenerationModel.localSafetensorsSet` | Bounded SD-Turbo F16/F32 tensor recipe, macOS CPU, owned verified cache and whole-set accounting; no automatic remote shard fetch. See [local checkpoint sets](./image-generation-advanced#local-checkpoint-sets) |

GGUF magic bytes and Safetensors headers drive role detection, not their
filename extensions. The header check assigns roles; it does not validate all
weight data or prove the architecture, dtype or quantization runs on the active
backend. F16/F32/BF16 Safetensors and GGUF quantization still need compatible
tensors and kernels. Do not assume arbitrary FP8/INT8 variants work; newer
upstream and FP8 CPU qualification are tracked upstream.
`checkRuntime()` reports runtime/device availability, not support for every
model. Use [Support](#support) and the recipe's platform evidence separately.
The public model roles do not include LoRA, upscaler or external tokenizer
inputs; `controlNet` loads only in the [ControlNet recipe](./image-generation-advanced#controlnet).

FP8 image weights (`F8_E4M3`/`F8_E5M2` in Safetensors, types 43/44 in
GGUF) load on Metal with the pinned stable-diffusion-native `v0.3.0-1`, which
converts them to F16 there: they need twice their file size in memory, which
`ImageModelParams.checkMemory` counts. FP8
weights, uninspectable GGUF/Safetensors headers and ordinary JSON shard
indexes are refused with `LlamaUnsupportedException` on Metal, including
`ComputeDevice.auto` when it selects Metal, before native context creation
([#1446](https://github.com/leehack/llamadart/issues/1446)); use
`ComputeDevice.cpu` there. FP8 re-encodings of SD-Turbo are measured on
macOS arm64 CPU and Metal; arbitrary FP8 models are not qualified.

For a trusted PyTorch checkpoint whose native layout is compatible:

```dart
final model = ImageGenerationModel(
  ModelSource.path('model.ckpt'),
  role: ImageModelRole.checkpoint,
);
```

An explicit role selects a native input; it does not convert the file or make
an unsupported checkpoint compatible. PyTorch component loading can work while
larger full-checkpoint loading remains unqualified; do not generalize a small
decoder's result to an entire diffusion model. The native reader handles a
restricted state-dict representation without executing Python callables; arbitrary
serialized modules, TorchScript and legacy TAR checkpoints are not supported.
Use trusted model files. There is no public conversion API or load-time
quantization/mmap option. Weights load eagerly; see the
[memory check](./image-generation-memory-and-limits#memory-check) before substituting larger unquantized files.

#### Pinned-runtime format checks

With the pinned `stable-diffusion-native v0.3.0-1` (`be48649` plus the owner
pickle-reader repair), complete byte-equivalent SD-Turbo F16 checkpoints pass
through `ImageGenerationEngine` on macOS arm64 CPU:

| Complete checkpoint | Role selection | Result |
| --- | --- | --- |
| F16 GGUF | Automatic and explicit checkpoint | Exact native-reference RGB |
| Safetensors, same 1,323 tensors | Automatic and explicit checkpoint | Exact native-reference RGB |
| Tensor-only PyTorch legacy `.pth` | Explicit checkpoint | Exact native-reference RGB, including the >2-GiB input |
| PyTorch ZIP `.pt` and nested `state_dict` ZIP `.ckpt` | Explicit checkpoint | Exact native-reference RGB |

These checks use the [pinned SD-Turbo F16 source](https://huggingface.co/Green-Sky/SD-Turbo-GGUF/blob/19a31586d02d64a73b4419bc193b3ecfaf38e1f0/sd_turbo-f16.gguf)
and its embedded full VAE. Local Safetensors and PyTorch 2.11/protocol-2
variants preserve every tensor byte. All seven public loads generate the same
128-square, one-step Euler/discrete image at seed 42, CFG 1 and four CPU
threads, matching separate guarded direct-C controls. This is container and
transport evidence, not an image-quality or speed benchmark.

Other architectures, dtypes, producer layouts, arbitrary serialized objects,
accelerators, Windows/Linux and mobile full-checkpoint paths are unqualified
by this check. No model weights ship with the tests. The
[basic example's container checks](https://github.com/leehack/llamadart/tree/main/example/basic_app#8-image-generation-example-experimental)
and maintained `image-container-formats` scenario repeat the selected controls
from local files and independent native references.

### Sources

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
| `controlNet` | A ControlNet, loaded with the model | SD 1.x, in the [ControlNet recipe](./image-generation-advanced#controlnet) |

The set needs exactly one `checkpoint` or `diffusionModel` and at most one
file per role. `load` throws `LlamaModelException`, naming files by position
(the main file, component 1, ...) and never by path, for:

- a LoRA adapter, upscaler or vision projector, which text to image does not
  load;
- `taesd_decoder.safetensors`, a decoder-only export the runtime rejects
  (use `diffusion_pytorch_model.safetensors`);
- two files in one role, a checkpoint plus separate diffusion weights, or no
  diffusion weights;
- a VAE or tiny autoencoder for other latent channels than the diffusion
  model's, such as TAESD (4 channels) with FLUX (16);
- a file with no known image-model layout, such as a pickled `.ckpt`;
- a `ModelLoadOptions.sha256` mismatch, which names the main file the same
  way.

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
  several files. Verify each component independently before loading it.
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

## Examples

The [basic app](../examples/basic-app) has a command-line image example, and
the [chat app](../examples/chat-app) has an image screen that downloads SDXS
or SD-Turbo with TAESD from the same pinned files and generates on device.
The command-line example also runs the desktop models from pinned
downloads; both keep their pinned sources and settings in the app.

## Next

1. [Generate and settings](./image-generation-settings): requests, attention
   and VAE settings, VAE tiling, caches, module placement, warm-up, progress
   and cancellation.
2. [Memory, logs and limits](./image-generation-memory-and-limits): the memory
   check, runtime logs, errors and known limits.
3. [Advanced requests](./image-generation-advanced): seamless textures, local
   checkpoint sets, image editing, ControlNet, hires fix and reference image
   editing.
