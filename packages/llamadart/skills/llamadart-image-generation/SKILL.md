---
name: llamadart-image-generation
description: >-
  Use when generating images from text prompts in a llamadart app with the
  Preview (experimental) ImageGenerationEngine: opting into the stable_diffusion
  runtime, loading SDXS or SD-Turbo (with TAESD) or the desktop SDXL-Lightning,
  FLUX.1-schnell, SD 3.5 Large Turbo and Z-Image-Turbo models from pinned
  Hugging Face files or local paths, showing download and generation
  progress, cancelling,
  saving PNGs, or handling unsupported platforms, memory refusals and
  concurrent-generation errors.
---

# Image generation with llamadart

## Guidelines

- Image generation is a Preview: the `ImageGenerationEngine` API is
  experimental and may change. It is separate from `LlamaEngine`. It runs
  stable-diffusion.cpp through the opt-in `stable_diffusion` native runtime.
  Bounded image-to-image and binary-mask editing use `ImageEditingRequest`
  on macOS CPU with an SD 2.x checkpoint and embedded full VAE. A bounded
  SD 1.x ControlNet steers `ControlNetImageGenerationRequest` on macOS CPU.
  A bounded two-pass hires fix uses `HiresFixImageGenerationRequest` on
  macOS CPU or Metal with an SD 1.x or SD 2.x full-VAE checkpoint.
  FLUX.1 Kontext reference editing uses `ReferenceImageEditingRequest`.
  LoRA has no public image-generation API.
- The app must bundle the runtime (about 40 to 70 MB per target); it is never
  included by default. In the app's `pubspec.yaml`:

  ```yaml
  hooks:
    user_defines:
      llamadart:
        llamadart_native_runtimes: all
  ```

  Unset, the key bundles `llama_cpp` and `litert_lm`. A list replaces those
  defaults, so it names everything the app loads: `all` is every runtime
  published for the target, `[llama_cpp, stable_diffusion]` is GGUF chat and
  images without LiteRT-LM, and `[stable_diffusion]` is images only. Run
  `flutter clean` once after changing it. Linux and Windows bundle the Vulkan
  build when `llamadart_native_backends` selects Vulkan (the default);
  `llamadart_stable_diffusion_backends: [cpu]` picks the CPU build.
- Flutter iOS and macOS apps should add the
  `llamadart_stable_diffusion_flutter` companion package. It links the
  runtime's XCFramework through Swift Package Manager and selects the runtime
  on iOS and macOS without the entry above. Without it, `all` leaves the image
  runtime out of a Flutter iOS/macOS app and `checkRuntime()` reports it as not
  bundled; a list naming `stable_diffusion` bundles it through the hook, and
  App Store Connect rejects that iOS framework's `MinimumOSVersion`.
  `flutter build ios` output shows neither build warning; Xcode and
  `xcodebuild` show both. Use the companion with the core's `MAJOR.MINOR`. Adding it
  opts the app into the runtime (about 37 MB per Apple target).
The core accepts only an Apple SD companion pinning its own runtime
(`v0.3.0-3`): runtimes before `v0.3.0-1` abort on FP8 weights on Metal, and those before
`v0.3.0` have a smaller `sd_ctx_params_t`. Upgrade the
core and `llamadart_stable_diffusion_flutter` together.

- Platforms: Android arm64 (CPU only; Armv8.2 dot-product and fp16), iOS 16.4+
  and macOS 13.3+ (Metal), Linux arm64/x64 and Windows x64 (CPU or Vulkan; x64
  CPUs need AVX2, FMA, F16C and BMI2). Web, Android x64 and Windows arm64
  are unsupported. Windows needs the latest
  Microsoft Visual C++ v14 Redistributable (x64).
- For repeating textures use `SeamlessImageGenerationRequest`, with independent
  `circularX` and `circularY` flags (both default off). Its initial supported
  recipe is native-detected SDXS (512-DS) with header-detected embedded tiny
  decoder, no components, 512×512, CPU or Metal, loaded with
  `flashAttention: false` and `vaeDirectConvolution: false`. Other families,
  decoder overrides, sizes and options throw `LlamaUnsupportedException`.
  This changes convolution padding in diffusion and VAE, not VAE tiling.
  Keep seed, sampler, scheduler and guidance explicit for comparisons; inspect
  a 2×2 repeat because arbitrary prompts/seeds are not quality guarantees.
  Measured qualification is macOS arm64 CPU and Metal. See the image guide's
  seamless-textures recipe and `doc/image_seamless_textures.md` for evidence.
- For image editing, check `(await engine.capabilities).supportsImageEditing`.
  Load a single SD 2.x checkpoint with its embedded full VAE on macOS CPU,
  `flashAttention: false`, `vaeDirectConvolution: false`; no component
  overrides, tiling or circular axes. SD-Turbo is measured; other compatible
  SD 2.x checkpoints are unmeasured. Unsupported recipes throw
  `LlamaUnsupportedException` before generation.
  Construct `ImageEditingPixels.rgb` from decoded row-major RGB bytes (no
  alpha) and pass it to `ImageEditingRequest(initialImage: ..., strength: 0.75,
  prompt: ...)`. Dimensions are aligned multiples of 64 in 64..2048. Optional
  `ImageEditingPixels.mask` uses one channel: 255 edits, 0 preserves the latent.
  Only those binary values are accepted. Inputs are copied; there is no
  decoding, resizing, orientation correction or alpha compositing. Black
  output pixels can differ after VAE encode/decode. Strength is finite in
  (0,1]; 1 still encodes the input and step rounding can collapse nearby
  strengths. Do not promise exact pixel preservation or arbitrary prompt quality.
- For ControlNet, load the ControlNet as `ImageModelComponent.auto(...)` next
  to its checkpoint and check `(await engine.capabilities).supportsControlNet`.
  Only an SD 1.x checkpoint with embedded full VAE plus one original-layout
  (lllyasviel) SD 1.x ControlNet loads, on macOS with `ComputeDevice.cpu`,
  `flashAttention: false` and `vaeDirectConvolution: false`; Diffusers or
  `.pth` ControlNets, other families, extra components and devices throw
  `LlamaUnsupportedException` at load. The recipe is qualified on SD 1.5
  (`doc/image_controlnet.md`).
  Pass `ControlNetImageGenerationRequest(prompt: ..., control:
  ImageControlNetCondition(image: ImageEditingPixels.rgb(...), strength: 1))`;
  the request takes its size from the image. The image is the finished
  control map (edges, depth, pose): no preprocessor or resize runs. Strength
  is finite in [0, 2], default 0.9; 0 adds nothing. The ControlNet stays
  loaded until dispose; ordinary requests ignore it. A failed ControlNet pass
  fails the task with `LlamaInferenceException`.
- For a hires fix, check `(await engine.capabilities).supportsHiresFix` and
  pass `HiresFixImageGenerationRequest(prompt: ..., width: 512, height: 512,
  hiresFix: ImageHiresFix.scale(1.5, steps: 10, denoisingStrength: 0.55))`.
  The request's size is the first pass; give the final size as
  `ImageHiresFix.scale` (above 1, at most 2) or `ImageHiresFix.size`, never
  both. Every side is a multiple of 64 (nothing is rounded), each final side
  is at most twice the first pass, the final image at most 1024x1024 and the
  count at most 4; violations throw `LlamaImageGenerationException`. Only an
  SD 1.x or SD 2.x single checkpoint with embedded full VAE on macOS CPU or
  Metal qualifies; others throw `LlamaUnsupportedException`. The upscaler is
  `ImageHiresUpscaler.latent` (no model upscaler). Progress events carry
  `pass` 0 then 1; the second pass can run one step more than `steps`.
  A cancelled or failed second pass returns no images.
- For reference editing, load the FLUX.1 Kontext [dev] transformer with
  `ae`, CLIP-L and T5-XXL on `ComputeDevice.gpu` (macOS Metal), check
  `(await engine.capabilities).supportsReferenceImageEditing`, and pass
  `ReferenceImageEditingRequest(prompt: 'Change the car to red.', recipe:
  ImageReferenceEditingRecipe.fluxKontext, references: [ImageEditingPixels.rgb(...)],
  guidanceScale: 1)`; always pass `guidanceScale: 1`, because omitted it is 7. The output takes the reference's size: exactly one RGB
  reference, sides multiples of 64, at most 1024x1024; crop and resize it
  first. Headers cannot tell Kontext from FLUX.1 [dev]; other models,
  devices and platforms throw `LlamaUnsupportedException`.
- Gate UI on `await ImageGenerationEngine.checkRuntime()` (no model needed;
  probes on a separate isolate): show a progress indicator until it
  completes, then `unsupportedReason` when `isSupported` is false.
  `ImageGenerationEngine.load` throws `LlamaUnsupportedException` in the same
  cases. There is no synchronous probe.
- `await engine.capabilities` (an `EngineCapabilities`) reports the loaded
  model's family and device, and unsupported once disposed; it never throws.
  It changes only on `dispose()`, so read it once after `load` and keep it in
  the widget state instead of awaiting it in `build`.
- Formats: compatible GGUF and Safetensors load directly, including mixed
  components; do not convert Safetensors merely to satisfy the image API.
  Detection uses headers, not filename extensions. Compatible PyTorch
  `.ckpt`/`.pth`/`.pt` tensor-only state dictionaries need explicit roles.
  Complete byte-equivalent SD-Turbo F16 GGUF/Safetensors and PyTorch
  ZIP/nested ZIP/legacy inputs have exact direct-C/public output controls on
  macOS arm64 CPU; other layouts and platforms remain unqualified. An explicit role is not conversion or proof
  of architecture/dtype support. Leave `ModelSource.format` unset. Generic local
  directories and Diffusers component layouts are unsupported. Complete
  checkpoint sets use the separate bounded factory below; resolve other
  compatible component files individually. The guide's
  **Weight formats and layouts** section gives the limits.
- FP8 Safetensors (`F8_E4M3`/`F8_E5M2`) and GGUF types 43/44 load on Metal
  with runtime `v0.3.0-1` or later, which converts them to F16 there (twice
  their file size in memory; `checkMemory` counts it). A runtime without that
  fix makes them, uninspectable GGUF/Safetensors headers and ordinary JSON
  shard indexes throw `LlamaUnsupportedException` on Metal, including automatic
  Metal selection, before native context creation; choose `ComputeDevice.cpu`
  there ([#1446](https://github.com/leehack/llamadart/issues/1446)). Arbitrary
  FP8 models remain unqualified.
- Complete local checkpoint sets opt in with
  `ImageGenerationModel.localSafetensorsSet(path, sha256: trustedPerFileHashes,
  cacheDirectory: appPrivateSetCache)`. The path is a directory with
  `model.safetensors.index.json` or that regular index itself. The map includes
  that index and the complete contiguous canonical `model-00001-of-000NN.safetensors`
  basenames (N in 1..16). Arbitrary filename aliases are rejected. The initial supported
  tensor-layout fingerprint is the documented complete SD-Turbo F16/F32 recipe
  on macOS CPU, pinned SD v0.3.0-1, explicit flash/direct VAE off. Other families,
  dtypes/layouts, devices, Diffusers, and editing/tiling/seamless combinations
  refuse. Expected hashes must come from trusted app configuration, not from
  re-hashing arbitrary input at load time. Files are verified while copying
  into an owned cache and reverified on reuse. Keep source topology stable
  during resolution, reserve the cache for these snapshots, and never mutate
  or remove it while engines are alive. Original files may change after copy.
  Cancellation removes this load's partial stage; a published snapshot remains
  cached. Only the load cancel token applies; no credentials, remote redirect,
  downloader options or automatic repository/shard fetch. Check the loaded
  `supportsLocalSafetensorsSets` flag and see `doc/local_image_sets.md`.
- Models: `ImageGenerationModel(mainSource, components: [...])`. Every file
  is a `ModelSource` (`ModelSource.path`, an HTTP(S) URL or `hf://owner/repo@
  sha/file`); pin a commit. The library has no presets: the app owns each
  model's files and request settings. `load` downloads remote files, then
  reads each file's header (GGUF metadata and tensor names, safetensors
  header) to give it its `ImageModelRole`: `checkpoint`, `diffusionModel`,
  `vae`, `taesd`, `clipL`, `clipG`, `t5xxl`, `llm` or `controlNet`. Pass
  components as
  `ImageModelComponent.auto(source)` in any order; use
  `ImageModelComponent(source, role: ImageModelRole.vae)` (or
  `ImageGenerationModel(source, role: ...)`) only for a file the header check
  cannot classify, such as a `.ckpt`, or to pick between same-layout files
  (TAESD vs TAESDXL, TAESD3 vs TAEF1). `load` refuses LoRA, upscaler and vision-projector files, `taesd_decoder.safetensors`, two
  files in one role, no or two sources of diffusion weights, and a VAE or
  TAESD for other latent channels (TAESD with FLUX), naming files by
  position, never by path. `engine.roles` reports the assignment. Validated
  models and request settings (the guide's recipes have pinned files):
  - SDXS-512 (`concedo/sdxs-512-tinySDdistilled-GGUF`
    `sdxs-512-tinySDdistilled_Q8_0.gguf`, 683 MB): request `steps: 1,
    guidanceScale: 1`; do not raise them.
  - SD-Turbo (`Green-Sky/SD-Turbo-GGUF` `sd_turbo-f16-q8_0.gguf`, 2.0 GB):
    `steps: 1, guidanceScale: 1`, up to 4 steps for detail. Add
    `madebyollin/taesd` `diffusion_pytorch_model.safetensors` as a component
    on phones.
  - Desktop models (desktop GPUs and Macs, not phones; 7 to 12 GB), all at
    `width: 1024, height: 1024, guidanceScale: 1`: SDXL-Lightning
    (`ByteDance/SDXL-Lightning` `sdxl_lightning_4step.safetensors`, optional
    `madebyollin/taesdxl`; `steps: 4, sampler: ImageGenerationSampler.euler,
    scheduler: ImageGenerationScheduler.sgmUniform`); FLUX.1-schnell
    (`second-state/FLUX.1-schnell-GGUF` Q4_0 and `ae.safetensors`, `clip_l`
    and `t5xxl` Q8_0 from `second-state/stable-diffusion-3.5-medium-GGUF`;
    `madebyollin/taef1` can replace `ae`; `steps: 4`); SD 3.5 Large Turbo
    (`city96/stable-diffusion-3.5-large-turbo-gguf` Q4_0, the same encoders
    plus `clip_g`, and `madebyollin/taesd3` since the SD 3.5 VAE is gated;
    `steps: 4`); Z-Image-Turbo (`leejet/Z-Image-Turbo-GGUF` Q4_K,
    `unsloth/Qwen3-4B-Instruct-2507-GGUF` Q4_K_M and the FLUX `ae`;
    `steps: 8`). The memory check asks for about 8.6 GiB for
    SDXL-Lightning, 8.3 GiB for Z-Image-Turbo, and 14.5 and 13.1 GiB for
    FLUX.1-schnell and SD 3.5 Large Turbo (`load` refuses those two on a
    16 GB Mac under Metal's working-set cap).
- `ImageGenerationEngine.load(model, params:, download:, onProgress:,
  store:)`: `params` (`ImageModelParams`) holds runtime settings; `download`
  (`ModelLoadOptions`, the same type as `LlamaEngine`) sets the cache policy
  and directory, `bearerToken` or headers, retries and a `cancelToken` for
  every remote file; local files take only the cancel token. `bearerToken`
  and headers never cross hosts: remote files on more than one origin with
  them set throw `LlamaArgumentException`. `sha256` verifies a
  single-file model and is rejected (`LlamaUnsupportedException`) once
  there are components.
  `onProgress` reports `ModelDownloadProgress` across all files; cached and
  local files count as received, and `totalBytes` is `null` until every
  file size is known. A cancelled load throws `LlamaStateException`
  (during the native load, once it returns, freeing the model); a
  failed download throws what the download manager throws (usually
  `LlamaModelException`). The runtime check, `params` checks and local-file
  checks run before anything downloads, so the web and unsupported devices
  download nothing. Loads are atomic: on failure nothing stays loaded. The
  default download manager caches where `LlamaEngine`'s does (on Android and
  iOS, `llamadart/models` in the app's cache directory, or
  `DefaultModelDownloadManager.globalCacheDirectory`); pass `store:
  ModelFileStore(downloadManager: DefaultModelDownloadManager.appPrivate(
  cacheDirectory: ...))` for another directory.
- Model licenses differ by model, including on commercial use (Stability AI
  Community License for SD-Turbo and SD 3.5 Large Turbo, CreativeML Open
  RAIL++-M for SDXS and SDXL-Lightning, Apache 2.0 for FLUX.1-schnell and
  Z-Image-Turbo). Tell users to check the model card's license before
  shipping a model; the guide's Model licenses table links each one.
- `ImageGenerationRequest` carries every generation setting: size, steps and
  guidance fall back to 512x512, 20 and 7 (undistilled SD 1.x/2.x), so always
  set the model's own. It also takes `sampler` (`ImageGenerationSampler`),
  `scheduler` (`ImageGenerationScheduler`) and `flowShift` (flow-matching
  models only, greater than 0, at most 100); `null` keeps the runtime's default
  for the model. SDXL-Lightning wants `euler` with `sgmUniform`.
- `TiledImageGenerationRequest(vaeTiling: ImageVaeTiling(), prompt: ...)` decodes in overlapping tiles (output
  pixels, multiples of 64 from 64 to 2048, default 256; `overlap` 0 to 0.5,
  default 0.5) to cut the decoder's peak memory for large images or full
  VAEs, at the cost of decode time and slight seam blending. Ordinary requests
  and `warmUp` keep their original interface and defaults. Tiling accepts
  header-verified SD 2.x checkpoints with embedded full VAE or TAESD on CPU/Metal;
  SD-Turbo is measured, other accepted SD 2.x artifacts and phones are unmeasured.
  Unknown proof, other families/backends, external full VAE/component overrides
  and tiling combined with either circular axis throw `LlamaUnsupportedException`.
- `load` checks every file exists and, unless
  `ImageModelParams(checkMemory: false)`, refuses a model whose estimate (file
  sizes plus a quarter plus 512 MiB, for the model's native size) exceeds the
  device figure with `LlamaModelException`: on Android the larger of
  `MemAvailable` and half of `MemTotal` less the app's own memory,
  `MemAvailable` on Linux CPU, the app's limit on iOS, physical memory on
  macOS, capped on Metal by the GPU's recommended working set. On a Vulkan GPU
  a model larger than the memory of the GPU that computes (with several
  discrete GPUs, the one with the most free memory for `ComputeDevice.auto`)
  still loads, slower, with one `LlamaLogger` warning (the runtime keeps the
  rest in system memory); on Linux it is refused only above the memory of every
  discrete GPU plus `MemAvailable`, and on Windows never. An integrated GPU on
  Linux gets `MemAvailable`. The Windows CPU is not checked, and the warning,
  refusal and two-GPU paths are unchecked on physical Vulkan hardware (#1024).
  SD-Turbo usually loads on 8 GB Android phones when no chat model is loaded,
  and is usually refused on 6 GB ones; offer SDXS there.
- `ImageModelParams(device: ComputeDevice.auto | cpu | gpu, threads: 0)`.
  `gpu` without a GPU (Android, CPU builds) and `npu` throw
  `LlamaUnsupportedException`. `auto` uses the CPU on macOS x86_64.
  `flashAttention` and `vaeDirectConvolution` default to `null`, which picks
  per device: flash attention on for the CPU and Metal, off on Vulkan; direct
  VAE convolutions on except on Metal (about 7 times slower there) and when
  a tiny autoencoder decodes (a `taesd` file, or a checkpoint embedding one,
  as SDXS does, seen from its header). Leave them `null` unless measuring. Direct VAE
  convolutions leave the image identical on the CPU and change it by rounding
  on Metal; flash attention changes pixels slightly. `vaeDirectConvolution:
  true` on iOS Metal throws `LlamaUnsupportedException` at load: every decode
  tripped the GPU watchdog and returned a corrupt image
  ([#1044](https://github.com/leehack/llamadart/issues/1044)). Full-VAE Metal
  decoding on iOS is also refused, even with direct convolutions off or tiling.
  GPU decoding needs the intrinsic tiny-decoder v1 policy across refresh.
  The pinned `v0.3.0-3` provides that policy for intrinsic SDXS tiny decoders; other recipes require `ImageModelPlacement(vaeOnCpu: true)` or `ComputeDevice.cpu`. Desktop checks do not add physical-iOS qualification.
  External TAESD can fall back to a full VAE; no iPhone full-VAE fix is claimed (#1047).
- `ImageConditioningCacheParams(capacity: ...)`: ordinary `ImageModelParams`
  preserve the native default of 4 prompt-conditioning entries. `0` disables
  reuse; positive values set an LRU entry limit up to `2147483647` (the signed 32-bit ABI
  limit). Other values throw `LlamaImageGenerationException` before resolving
  files. The capacity counts entries, not bytes; it belongs to the loaded
  context and is freed on disposal. Load another engine to change it.
  It does not enable approximate sampling caches or promise a speed/memory
  improvement. The control is qualified with SDXS and SD-Turbo on macOS arm64
  CPU/Metal; other platforms and families remain unmeasured for this option.
- `load(placement: ImageModelPlacement(...))` on Metal or Vulkan sets
  `textEncoderOnCpu`, `vaeOnCpu`, `maxGpuMemoryGiB` (whole GiB) and `autoFit`
  (off: fail instead of spilling); moved modules and a tiled decode change
  pixels slightly. CPU engines, the Web, and a budget with the fit off or on
  Vulkan without a discrete GPU throw `LlamaUnsupportedException`.
- `load` loads weights eagerly, but GPU shaders compile on first use: the first
  runtime probe in a process (`checkRuntime()` or `load()`, both off the
  calling isolate) compiles the Metal library on Apple (about 16 s on an M4 Max
  with an empty shader cache), and the first GPU image compiles its pipelines
  (12 s on Linux Vulkan, 45 s on Windows Vulkan, against under 0.6 s warm). The
  OS or driver caches them for later launches. Show progress.
- `await engine.warmUp(width:, height:, guidanceScale:)` right after
  `load`, while the user writes the prompt, moves the pipeline compile off
  the first real image. Pass the size and guidance the app generates with,
  since another size can compile more. At a desktop model's
  1024x1024 it costs one step and a decode (about 2 to 4 s for SDXL-Lightning
  with TAESDXL on an M4 Max). It runs one discarded single-step image,
  returns at once on the CPU, holds the one-operation slot (await it before
  `generate`), and completes normally when `dispose()` cancels it.
- `await engine.generate(request)` returns the running `ImageGenerationTask`;
  invalid requests throw `LlamaImageGenerationException` first. Width and
  height are multiples of 8 from 64 to 2048; use the model's native size
  (512x512 for SDXS and SD-Turbo, 1024x1024 for the desktop models). 256 is
  fine for SDXS and SD-Turbo; the runtime rounds up to 64, so read the size
  from `GeneratedImage`. Steps are 1 to 150, guidance 0 to 30, count 1 to 16.
  `seed: null` is random; `result.seed` reports it, image `i` used `seed + i`,
  and the same seed reproduces the same pixels.
- `task.events` (single subscription): `ImageGenerationProgressEvent`
  (`phase`: `encodingPrompt`, `sampling`, `decoding`, rarely `loading`;
  `step`, `steps`, `imageIndex`, `imageCount`), then one
  `ImageGenerationFinalEvent(result)`. The stream never emits an error.
  `await task.result` returns the `ImageGenerationResult` (`images`, `seed`,
  `elapsed`), or throws the failure, or `LlamaStateException` when
  cancelled; `task.done` reports the same outcome as an
  `ImageGenerationCompletion` and never throws.
- `engine.generateImage(request)` is the one-call form of
  `(await engine.generate(request)).result`.
- `GeneratedImage` has `width`, `height`, `channels` (3) and row-major RGB
  `pixels`; `toPng()` returns PNG bytes (for `Image.memory` or a file).
- One generation or model load at a time per process (stable-diffusion.cpp
  reports progress for the whole process): a second one throws
  `LlamaStateException`,
  even on another engine. Await `task.done` before the next request; disable
  the Generate button while one runs. Do not generate from several isolates.
- `task.cancel()` stops before the next sampling step; `done` reports
  `cancelled`, `result` throws `LlamaStateException`, and the stream closes
  without a final event. `dispose()` cancels
  a running task, waits, then frees the model.
- Progress events arrive in groups, up to about 50 ms after the runtime
  reports them (the engine polls the runtime), always in order and before
  the final event.
- Dispose before a Flutter app quits. A process that ends with an image
  model loaded no longer aborts on macOS Metal, but nothing cancels a running
  generation when a Dart program ends or a Flutter app quits, so the process
  stays until the generation finishes. Flutter
  desktop apps skip `State.dispose` on
  quit; await `dispose()` in `AppLifecycleListener.onExitRequested`. If
  `ImageGenerationEngine.load` is still running, await it there and dispose
  the engine it returns. When the engine's owner can be disposed before quit
  (a pushed route), its listener goes with it: make one app-level exit
  listener await every engine's disposal, including one its owner already
  started.
  Image-worker disposal waits for actual worker exit, and concurrent callers
  await the same cleanup. Before C `exit()`, a native host must also stop and
  join its other native workers and shut down its Dart isolates or Flutter
  engine. A kill request alone cannot interrupt native generation.
- A runtime failure (for example out of memory) fails the task with
  `LlamaInferenceException`; the engine stays usable for the next request.
  A failed Metal command buffer is the exception: it leaves the backend in
  an error state. From then on every generation on that engine fails with a
  message saying so, and only `dispose()` plus a new `load()` recovers.
- A load the runtime rejects (`LlamaModelException`) quotes the errors
  stable-diffusion.cpp logged, with files named by role, such as
  `<checkpoint file>`. For a split checkpoint it also names the missing roles
  (no `vae`/`taesd`, no text encoder); a file in the wrong role only gets
  `get sd version from file failed`, so check that each file is in its role.
- Runtime messages reach the `LlamaLogging.configure` handler when both
  `level` and `nativeLevel` admit them (default `none`: nothing is logged,
  to stderr either). Configure before `load`; messages arrive after each
  load and generation, not during one. At `debug` they include each prompt
  verbatim.

## Examples

Load SDXS from a local file, stream progress and save a PNG:

```dart
import 'dart:io';

import 'package:llamadart/llamadart.dart';

Future<void> generateFox(String sdxsPath, String outputPath) async {
  final ImageGenerationCapabilities runtime =
      await ImageGenerationEngine.checkRuntime();
  if (!runtime.isSupported) {
    throw LlamaUnsupportedException(runtime.unsupportedReason!);
  }

  final ImageGenerationEngine engine = await ImageGenerationEngine.load(
    ImageGenerationModel(ModelSource.path(sdxsPath)),
  );
  try {
    final ImageGenerationTask task = await engine.generate(
      const ImageGenerationRequest(
        prompt: 'a red fox in autumn leaves',
        steps: 1,
        guidanceScale: 1,
        seed: 42,
      ),
    );
    task.events.listen((ImageGenerationEvent event) {
      if (event
          case ImageGenerationProgressEvent(
            :final ImageGenerationPhase phase,
            :final int step,
            :final int steps,
          )) {
        print('${phase.name} $step/$steps');
      }
    });
    final ImageGenerationResult result = await task.result;
    await File(outputPath).writeAsBytes(result.images.first.toPng());
    print('Seed ${result.seed} in ${result.elapsed.inMilliseconds} ms');
  } on LlamaInferenceException catch (error) {
    print('Generation failed, engine still usable: ${error.message}');
  } finally {
    await engine.dispose();
  }
}
```

SD-Turbo with TAESD from pinned Hugging Face files, with download progress,
cancellable while downloading or generating:

```dart
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';

Future<Uint8List?> generateWithCancel(Future<void> userCancelled) async {
  final ModelDownloadCancelToken cancelDownload = ModelDownloadCancelToken();
  ImageGenerationTask? task;
  userCancelled.then((_) {
    cancelDownload.cancel();
    task?.cancel();
  });

  final ImageGenerationEngine engine;
  try {
    engine = await ImageGenerationEngine.load(
      ImageGenerationModel(
        ModelSource.parse(
          'hf://Green-Sky/SD-Turbo-GGUF@'
          '19a31586d02d64a73b4419bc193b3ecfaf38e1f0/sd_turbo-f16-q8_0.gguf',
        ),
        components: <ImageModelComponent>[
          ImageModelComponent.auto(
            ModelSource.parse(
              'hf://madebyollin/taesd@614f76814bbe30edbe2e627ace1c2234c81a2c0e/'
              'diffusion_pytorch_model.safetensors',
            ),
          ),
        ],
      ),
      download: ModelLoadOptions(cancelToken: cancelDownload),
      onProgress: (ModelDownloadProgress progress) {
        final double? fraction = progress.fraction;
        if (fraction != null) {
          print('Files ${(fraction * 100).toStringAsFixed(0)}%');
        }
      },
    );
  } on LlamaStateException {
    return null; // Cancelled while downloading.
  } on LlamaModelException catch (error) {
    print('Download failed, or the model was refused: ${error.message}');
    return null;
  }

  try {
    final ImageGenerationTask running = task = await engine.generate(
      const ImageGenerationRequest(
        prompt: 'a lighthouse at dusk',
        steps: 4,
        guidanceScale: 1,
      ),
    );
    if (cancelDownload.isCancelled) {
      running.cancel(); // Cancelled while the task was starting.
    }
    final ImageGenerationCompletion completion = await running.done;
    return switch (completion.state) {
      ImageGenerationCompletionState.completed =>
        completion.result!.images.first.toPng(),
      ImageGenerationCompletionState.cancelled => null,
      ImageGenerationCompletionState.failed => throw completion.error!,
    };
  } finally {
    await engine.dispose();
  }
}
```
