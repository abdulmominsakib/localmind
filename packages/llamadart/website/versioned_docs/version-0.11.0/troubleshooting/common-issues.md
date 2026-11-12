---
title: Troubleshooting common issues
sidebar_label: Common issues
description: Find a symptom or error message and its fix, from model and native library load failures to GPU, web, performance and API usage errors.
---

Find the symptom, then apply the fix. Both log levels default to `none`, so
turn logging on first to see the native reason behind a failure:

```dart
await LlamaLogging.configure(level: LlamaLogLevel.info);
```

To quiet logs again, see [Logging](../configuration/logging).

## Model won't load

### `Failed to load model from <path>`

The load throws `LlamaModelException` whose details name the cause:

- `Model file not found: <path>` or `Model file is empty: <path>`: the path is
  wrong, unreadable or points at an incomplete download.
- `Model file does not appear to be GGUF: <path>`: the file is not GGUF, or
  the download is truncated. `.litertlm` bundles route to LiteRT-LM by
  extension; `LiteRT-LM model does not exist: <path>` means the bundle path is
  wrong.
- `Failed to load model (size=<bytes> bytes, diagnostics=...)`: llama.cpp
  rejected the file. The native log gives the reason, for example
  `unknown model architecture` when the pinned runtime does not support the
  model.

Fix: check the path and file size, re-download the model, or pick a model the
runtime supports ([Support matrix](../platforms/support-matrix)).

### `loadModelFromUrl requires a backend that supports URL loading.`

Only the deprecated `loadModelFromUrl` throws this: native backends do not
load from URLs. Use `LlamaEngine.load` or `setModel` with a `ModelSource`,
which downloads and caches the model before loading the local file
([Download and cache models](../guides/model-downloads)).

### Speculative draft model fails to load

A DFlash draft fails and native logs report
`unknown model architecture: 'dflash-draft'` or missing DFlash target-layer
metadata. The draft GGUF has incompatible metadata; see
[DFlash draft models](../guides/performance-tuning#dflash-draft-models).

## Native library won't load

### Build fails to fetch native runtimes

The build hook downloads precompiled runtime binaries from GitHub Releases.
Give the build machine access to GitHub release downloads. If backend
configuration changed recently, run `flutter clean` once. How the hook
resolves binaries: [Native build hooks](../platforms/native-build-hooks).

### `llama.cpp runtime could not be loaded on windows-x64`

`LlamaBackendInitializationException`, which the load wraps in
`LlamaModelException`: Windows could not load a DLL that llama.cpp imports,
and the message names the Visual C++ runtime DLLs that did not load, such as
`msvcp140.dll` or `vcruntime140.dll`. Install the latest Microsoft Visual C++
v14 Redistributable for the app's architecture
([`vc_redist.x64.exe`](https://aka.ms/vc14/vc_redist.x64.exe), or
[`vc_redist.arm64.exe`](https://aka.ms/vc14/vc_redist.arm64.exe) on Windows
arm64) on that machine, or ship those DLLs next to `llamadart.dll`. It must be
at least as new as the build tools of the bundled DLLs, so update an older
installed copy too. Stock Windows Server lacks it.

### `libgomp.so.1: cannot open shared object file`

Linux only. Every llama.cpp load needs the OpenMP runtime. Install `libgomp1`
(Ubuntu/Debian) or `libgomp` (Fedora, Arch); see
[Linux prerequisites](../platforms/linux-prerequisites).

### `Timed out after 30000 ms waiting for the llama.cpp worker to initialize its backend.`

`LlamaBackendInitializationException`, which the load wraps in
`LlamaModelException`: the native llama.cpp worker did not finish starting
within 30 seconds. The native runtime may be missing, fail to
load, or hang during backend initialization. Check the native log for a
library load error and confirm the platform prerequisites.

### `The llama.cpp worker exited unexpectedly.`

Requests, generation streams, and speech synthesis fail with
`LlamaStateException` if the backend's worker isolate exits after startup.
Dispose the affected engine/backend and create a fresh one before loading the
model again; handles from the old worker are invalid. Disposal no longer waits
for a reply from that dead worker. Native allocations abandoned by the worker
cannot be reclaimed through its old handles.

The regression tests cover external isolate termination and uncaught Dart
worker errors. A native crash can terminate the entire application process;
isolate exit handling does not make that crash recoverable.

## GPU crash or device loss

Confirm the model runs on CPU first: load it with
`device: ComputeDevice.cpu`, which loads no GPU layers on either runtime. If
CPU works, the failure is in the GPU backend or driver.

### `ComputeDevice.gpu needs ...` or `ComputeDevice.npu is not available ...`

`LlamaUnsupportedException`: `ModelParams.device` asked for a device this
runtime and platform cannot provide, so the load stopped instead of running
on the CPU. The message names the device, runtime and platform, and on
llama.cpp the missing backend module or the devices found. Bundle the GPU
module, use a browser with WebGPU, or load with `ComputeDevice.auto` to accept
the runtime's default device. Native LiteRT-LM reports a GPU or NPU delegate
that fails to start from the first generation or `tokenize`; a corrupt or
truncated `.litertlm` file fails the same way, so if `ComputeDevice.cpu` also
fails, replace the file. The deprecated
`liteRtLmBackend` still throws `LlamaModelException` for an unavailable
backend; catch `LlamaException` to handle both.

### Vulkan driver crashes in the cooperative-matrix path

Some Vulkan drivers advertise cooperative matrix support but crash inside the
property queries upstream `ggml-vulkan` makes. This is a driver failure, not a
llamadart loader failure. Set upstream's opt-out variables before starting the
Dart or Flutter process:

```bash
GGML_VK_DISABLE_COOPMAT=1
GGML_VK_DISABLE_COOPMAT2=1
```

On Windows PowerShell:

```powershell
$env:GGML_VK_DISABLE_COOPMAT = "1"
$env:GGML_VK_DISABLE_COOPMAT2 = "1"
flutter run -d windows
```

They disable the cooperative-matrix Vulkan paths for that process and can
reduce Vulkan performance; use them only when the driver crashes or reports
device loss there.

### LiteRT-LM GPU crashes on Linux without a hardware Vulkan driver

With only Mesa llvmpipe (the runtime logs `Selected adapter: llvmpipe ...
adapterType=CPU / Software`), LiteRT-LM `v0.17.0-6` loads the model and answers
the first prompts, then segfaults in `libvulkan_lvp.so` and takes the process
down. There is no load error to fall back from, so hosts with Mesa but no
vendor ICD must use `device: ComputeDevice.cpu`
([#572](https://github.com/leehack/llamadart/issues/572)).

## Wrong or garbled GPU output

Compare the GPU output with a CPU run (`gpuLayers: 0`) using the same prompt,
`seed` and `temp: 0`. If only the GPU output is wrong, the failure is in the
GPU backend or driver.

### LiteRT-LM GPU output is incoherent on Android

On the Adreno 750 in a Galaxy S24 (WebGPU over Vulkan), LiteRT-LM loads Qwen3
0.6B on the GPU without an error and then generates wrong text, such as one
token repeated up to the output limit, while the CPU on the same device
answers correctly. `ComputeDevice.auto`, the default, selects the GPU for
LiteRT-LM on Android, so a default load of that model on that GPU is affected.
Load it with `ModelParams(device: ComputeDevice.cpu)` instead.

At load Dawn rejects one weight buffer: `Binding size (155582464) ... is larger
than the maximum storage buffer binding size (134217728)`. Any adapter with
that 128 MiB limit and any model with a larger weight buffer should fail the
same way. The runtime reports no failure to the caller, so llamadart cannot
turn it into a load error or pick the CPU for you. Seen from `v0.17.0-6`
through the pinned `v0.17.0-8`
([#553](https://github.com/leehack/llamadart/issues/553), upstream
[LiteRT-LM#3866](https://github.com/google-ai-edge/LiteRT-LM/issues/3866)).

### Android app is killed after reloading a LiteRT-LM GPU model

With `litert-lm-native` `v0.17.0-7` and earlier, deleting a LiteRT-LM GPU
engine on Android kept its graphics memory, about 2 GB for Qwen3 0.6B on a
Galaxy S24, so the low-memory killer ended the app at the second or third
model load. The pinned `v0.17.0-8` releases that memory when the engine is
deleted, as measured on a Galaxy S24; update llamadart to a release that pins
it ([litert-lm-native#59](https://github.com/leehack/litert-lm-native/issues/59)).

## Web

### `Web bridge is unavailable`

The WebGPU backend throws
`Web bridge is unavailable. Ensure LlamaWebGpuBridge assets are loaded and reachable.`
or `Web bridge is unavailable: <load error>` when the bridge script did not
load. Add the bridge assets to the app and check that they are served; see
[Add the bridge to your app](../platforms/webgpu-bridge#add-the-bridge-to-your-app).
In the browser console, `window.LlamaWebGpuBridge` should exist and
`window.__llamadartBridgeLoadError` should be empty.

### Load fails only on web, or WebGPU falls back to CPU

1. Check browser capability: secure context, `navigator.gpu`,
   `requestAdapter()`, adapter features and limits, and current GPU drivers.
2. For large single-file GGUF loads, check `window.crossOriginIsolated === true`
   and that the origin sends COOP/COEP headers.
3. `bad_alloc`, `memory access out of bounds` or aborts usually mean the model,
   context size, thread count or GPU-layer count is too large for the browser.
   Reduce them before treating the failure as a bridge problem.
4. If a hosted build differs from `localhost`, check model URLs, CORS/CORP
   policy, base href, service-worker cache state, and whether the runtime came
   from the CDN or local assets.

The readiness probe, fallback rules and smoke test are in
[WebGPU bridge](../platforms/webgpu-bridge).

## Slow generation

1. Compare `cpu` with the GPU backend; small models can be faster on CPU.
2. Reduce `contextSize` and `maxTokens`.
3. Use a smaller model or quantization.
4. Tune GPU offload (`gpuLayers`) and batch sizes one at a time.

See [Performance tuning](../guides/performance-tuning).

## Disk usage keeps growing

### LiteRT-LM GPU program cache grows with every load

With some models on the LiteRT-LM GPU backend, each engine create appends to
`*_mldrift_program_cache.bin`
([#552](https://github.com/leehack/llamadart/issues/552)). Set
`ModelParams.liteRtLmMaxProgramCacheBytes` to prune oversized program cache
files before each create; see
[LiteRT-LM cache directory](../configuration/runtime-parameters#litert-lm-cache-directory).

## API usage errors

### `Engine not ready: no model is loaded. Call LlamaEngine.load or setModel first.`

`LlamaContextException`: generation, tokenization or another model call ran
before `LlamaEngine.load` or `setModel` finished, or after `unloadModel`.
Await the load before using the engine.

### `Local model file does not exist: <path>`

`LlamaModelException`: `LlamaEngine.load`, `setModel` and the other engines'
`load` check a local `ModelSource.path` through the download manager before
the backend loads it. In a test that loads a made-up path into a fake
backend, use a real temporary file, or pass a fake `ModelDownloadManager` in
`store:` or `LlamaEngine(backend, modelDownloadManager: ...)`.

### `Model is already loaded. Call unloadModel() first.`

`LlamaStateException`: only the deprecated `loadModel`, `loadModelSource` and
`loadModelFromUrl` throw this, when a model is already loaded. Use `setModel`,
which replaces the loaded model.

### `Cannot <operation> while another model lifecycle operation is in progress.`

`LlamaStateException`: a load or unload started before the previous load or
unload finished, for example
`Cannot set a model while another model lifecycle operation is in progress.`
Await each lifecycle call before starting the next.

### Embedding input exceeds `n_ubatch`

`LlamaInferenceException`:
`The embedding input has <n> tokens, but this model embeds its input in one pass of at most <m> tokens (n_ubatch).`
Encoder-only models, models without a KV cache, non-causal attention models,
and MEAN/CLS pooling embed each input in one micro-batch. Shorten the input, or
raise `ModelParams.microBatchSize` and `ModelParams.batchSize`. Batched embedding
calls reject an oversized input before evaluating any of the batch.

### Recurrent speculative rollback is unsupported

Native llama.cpp rejects a nonzero `ModelParams.speculativeRollbackTokenMax`
on recurrent or hybrid models with `LlamaUnsupportedException`. The pinned
runtime cannot establish a safe graph budget for the requested rollback slots,
and an oversized reservation can terminate the process. Leave the value at `0`
for ordinary generation. Speculative strategies that require those snapshots
remain unsupported on these models until a qualified runtime supplies a safe
budget; use a non-recurrent target for those strategies.

### Prompt does not fit the context

Native llama.cpp generation fails with
`Prompt evaluation produced no logits for sampling. The active context window may be too small for this prompt or multimodal decode failed.`
`ChatSession` logs a `warn` record when compaction cannot fit the turn:
`ChatSession: the active turn still exceeds the context budget (<n> tokens) after compacting completed protocol exchanges.`
Raise `contextSize`, or shorten the message, tool results or media input.

### Tool calls are missing or malformed

1. Use `ToolChoice.auto` before forcing `required`.
2. Lower the temperature for tool-calling requests.
3. Validate the tool schema and required parameters.
4. Make sure your loop appends tool result messages, or use
   `session.sendWithTools`, which does.

See [Tool calling](../guides/tool-calling).
