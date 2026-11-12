---
title: Image generation memory, logs and limits (Preview)
sidebar_label: Memory, logs and limits (Preview)
description: How the ImageGenerationEngine memory check works per platform, how to read runtime logs, which exceptions it throws and its known limits.
---

Part of the [on-device image generation guide](./image-generation) (Preview).

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
| Linux: Vulkan, discrete GPUs | The memory of every discrete GPU plus `MemAvailable`; a model larger than the memory of the GPU that computes loads with a warning |
| Linux: Vulkan, integrated GPU | `MemAvailable`, as for the CPU |
| Windows: Vulkan, discrete GPUs | Never refused; a model larger than the memory of the GPU that computes loads with a warning |
| Windows: Vulkan, integrated GPU | Not checked |
| Windows: CPU | Not checked |

A model that does not fit throws `LlamaModelException` naming the estimate
and the figures, instead of the system killing the app. Set
`ImageModelParams(checkMemory: false)` to load anyway, without a check or a
warning.

### Vulkan GPUs

A discrete Vulkan GPU does not bound a model by itself. stable-diffusion.cpp
plans where each part of a model goes when it loads (its automatic fit, which
the engine leaves on): the diffusion model, the text encoders and the VAE
each go to the GPU that computes when they fit its free memory with room to
compute, otherwise to system memory, otherwise to another GPU, otherwise they
stay on disk. A model larger than the GPU therefore loads and generates more
slowly.

So the engine works with two figures:

- **The memory of the GPU that computes.** A GPU's figure is its free memory
  when the driver reports a budget (`VK_EXT_memory_budget`): what this
  process can still allocate, which accounts for other processes and for
  image models already loaded. Without a budget the runtime reports the
  total as free, so the engine uses the total. A free figure of 0 against a
  positive total means the process is over its budget and counts as no free
  memory: every model gets the warning below, and that GPU adds nothing to
  the sum that refuses a load on Linux, so with one GPU a model above
  `MemAvailable` is refused. A model whose estimate exceeds this figure
  loads, and the engine logs one warning through
  [`LlamaLogging`](#runtime-logs) with both numbers and the device, saying
  that part of the model stays in system memory and generation will be
  slower. It is a `warn` record, so the default level `none` hides it.
- **The memory of every discrete GPU plus system memory** (`MemAvailable`,
  as for the CPU). On Linux a model whose estimate exceeds this sum is
  refused. Windows does not read system memory, so nothing is refused there
  and only the warning applies.

With several discrete GPUs, the one that computes is the runtime's choice:
for `ComputeDevice.auto` the discrete GPU with the most free memory, wherever
it is listed, and for `ComputeDevice.gpu` the first one. The engine follows
that for the warning. `capabilities.backendName` still names the first GPU
listed.

An integrated GPU uses host memory, and a driver that exposes it as several
heaps makes the GPU's own figures count it more than once. The engine never
uses them: beside a discrete GPU an integrated one adds nothing to the sum,
and with integrated GPUs only it compares with `MemAvailable` on Linux, as
for the CPU.

Nothing is checked or warned about when a GPU does not report its memory or
when the `SD_VK_DEVICE` environment variable is set.

The figures are the runtime's, which are ggml's, for every GPU it lists. The
engine asks for them in a short-lived isolate, because the first such call in
a process can initialize the GPU.

The Vulkan rules are tested on reported figures, and the call that reads them
is checked on macOS Metal, where its total equals the working set above. On
an NVIDIA L4 under Vulkan, one GPU each on Linux and Windows, the figures,
the device facts and the device selection were checked. The warning, the
refusal and the two-GPU paths have not been checked on a physical GPU yet.
The Apple checks do not use these figures: Metal's total is the same working
set, and its free figure counts only this process's allocations.

On Android, `MemAvailable` alone is too strict: it leaves out the memory the
low-memory killer frees by stopping cached apps and what it swaps to zram,
and it varied by up to a gigabyte between idle readings. On six phones from
4 to 16 GB, an app that kept touching all of its memory was killed only after
allocating 0.9 to 3.6 GiB more than `MemAvailable`.

So 8 GB phones load SD-Turbo with TAESD (2.87 GiB estimated) even when
`MemAvailable` reads 2.1 GiB, unless the app already holds more than about
0.6 GiB, such as a loaded chat model, and 6 GB phones refuse it unless
`MemAvailable` alone covers it. With the check
off, no SD-Turbo variant was killed on these phones, but a 6 GB phone swapped
most of the app out and a one-step image took several times longer.

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
peaked at 4.7 GiB there.

## Runtime logs

stable-diffusion.cpp's and ggml's messages go to the handler of
[`LlamaLogging.configure`](../configuration/logging), each at its own level:

```dart
await LlamaLogging.configure(
  level: LlamaLogLevel.info,
  handler: (record) => print('[${record.level.name}] ${record.message}'),
);
final engine = await ImageGenerationEngine.load(model);
```

- A message has to pass both `level` and `nativeLevel`, so the runtime
  records from the stricter of the two, and nothing when either is `none`,
  the default. A load takes the levels it finds: configure logging before
  `load`.
- At `debug` the runtime logs each prompt verbatim, with its tokens. Keep
  that level out of logs that leave the device.
- Messages arrive after each load and generation and at `dispose()`, not
  while one runs: a worker isolate reads them from the runtime between its
  calls. Each starts with `stable_diffusion: `, and model file paths are
  replaced by roles, such as `<checkpoint file>`.
- The runtime keeps the most recent 256 KiB of messages. When one load or
  generation records more, the oldest are lost and one warning says how
  many. On an M4 Max an SDXS load recorded 28 messages at `info` and 40 at
  `debug`, and reading them took about 0.1 ms.
- The runtime does not write ggml's device messages to stderr, at any
  level, the default `none` included: its recorder is always registered,
  because the reason of a failed load comes from it. What a ggml backend
  writes to stderr itself still goes there.

## Errors

| Exception | When |
| --- | --- |
| `LlamaUnsupportedException` | The runtime is not bundled, the platform or CPU is unsupported, on the web, `ComputeDevice.gpu` without a GPU, `ComputeDevice.npu`, `vaeDirectConvolution: true` on iOS Metal, or `ModelLoadOptions.sha256` set for a `load` of several files |
| `LlamaModelException` | A file is missing, fails to download or is not an image-model component, two files share a role, a decoder does not match the diffusion model, the model does not fit, or the runtime cannot load it. A load the runtime rejects quotes the errors it logged, with files named by role, such as `tensor '...' extends beyond its model file`; a rejected split model also names the roles it lacks, such as a VAE or text encoder, and `details` lists the roles passed |
| `LlamaImageGenerationException` | An invalid request or `params:` |
| `LlamaStateException` | The load's cancel token cancelled it, another generation or load is running, or the engine is disposed |
| `LlamaInferenceException` | The runtime failed a generation, for example by running out of memory; the engine runs the next request. A failed Metal command buffer leaves the backend in an error state: from then on every generation on the engine fails with a message saying so. Dispose the engine and load the model again to recover |

## Known limits

- [Runtime logs](#runtime-logs) arrive after a load or generation, not
  during it. A failed load quotes what the runtime logged as errors, which
  for a file in the wrong role is only `get sd version from file failed`,
  and a failed generation does not quote its reason yet.
- Android runs on the CPU only: ggml Vulkan and OpenCL crashed or ran slower
  on the phones tried.
- iOS can abort a Metal command buffer under GPU pressure (seen once with
  SD-Turbo at four steps). This leaves ggml's Metal backend in an error
  state: from then on every generation on that engine fails until you
  dispose it and load the model again.
- On Linux a model on a Vulkan GPU is refused only when it fits neither the
  GPU nor the GPU plus system memory; one larger than the GPU's memory loads
  with a warning and runs slower. On Windows such a model is warned about
  and never refused, and the Windows CPU and integrated GPUs on Windows are
  not memory-checked. The [Vulkan figures](#vulkan-gpus), device facts and
  device selection were validated under Vulkan on an NVIDIA L4 on Linux and
  Windows, one GPU each; the warning, refusal and two-GPU paths have not been
  validated on a physical GPU yet
  ([#1024](https://github.com/leehack/llamadart/issues/1024)). Per-platform
  validation results, including timings, are in
  [#779](https://github.com/leehack/llamadart/issues/779).
- The web has no image runtime yet
  ([#969](https://github.com/leehack/llamadart/issues/969)).
