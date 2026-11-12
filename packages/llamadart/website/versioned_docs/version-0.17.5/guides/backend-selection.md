---
title: Choosing llama.cpp or LiteRT-LM
sidebar_label: llama.cpp or LiteRT-LM
description: Decide when to use GGUF with llama.cpp or .litertlm bundles with LiteRT-LM in llamadart.
---

For pre-load desktop setup information, run `dart run llamadart:doctor --json`
or call `collectLlamaRuntimeSetupReport()`; see the
[setup report contract](../platforms/diagnose-setup#desktop-setup-report).
It reports pinned publication policy and override presence. It does not choose
or initialize a runtime, validate GPU usability or replace loaded-model
capabilities. Web/mobile require separate app/device/browser validation.

## Quick answer

Terms such as runtime and backend module are defined in the
[glossary](./glossary).

| Choose this | Best fit | Tradeoffs |
| --- | --- | --- |
| `llama.cpp` / GGUF | Broad model catalog, many quantizations, embeddings, LoRA, state persistence, grammar constraints, multimodal, and low-level runtime tuning. | Mobile GPU performance depends heavily on the device, driver, model size, and GPU backend module. It does not use LiteRT-LM NPU delegates. |
| LiteRT-LM / `.litertlm` | LiteRT-LM bundles, Gemma 4 LiteRT-LM variants, Android GPU/NPU delegate experiments, and app flows that only need text generation/chat. | Smaller model catalog and fewer exposed runtime features today. Unsupported llama.cpp-only options are rejected. |

- Start with GGUF / llama.cpp if you need the broadest model support or
  embeddings, dynamic LoRA adapters, grammar constraints, state persistence, or
  multimodal projectors.
- Start with LiteRT-LM if your model already ships as a `.litertlm` bundle and
  your app mainly needs text generation or chat on mobile or web.
- On desktop, GGUF / llama.cpp is usually the more complete production runtime
  unless your product specifically ships LiteRT-LM bundles.
- On Android, benchmark LiteRT-LM `gpu` and `npu` separately when the model and
  device support them. NPU is a LiteRT-LM deployment path, not a general
  replacement for GGUF/Vulkan.
- If both formats exist for your model, [measure](#measure-before-choosing)
  before choosing.
- Log `engine.getBackendName()` so support reports name the actual runtime.

## Checking the loaded runtime

After a load, `engine.runtime` is `LlamaRuntime.llamaCpp` for GGUF, native or
WebGPU, and `LlamaRuntime.liteRtLm` for a bundle. `await engine.capabilities`
reports what that runtime supports for the loaded model, so an app can offer
only what works instead of checking the file extension:

```dart
final caps = await engine.capabilities;
final params = GenerationParams(
  minP: caps.supportsMinP ? 0.05 : 0.0,
  penalty: caps.supportsPenalty ? 1.1 : const GenerationParams().penalty,
);
final offerTools = caps.supportsToolCalling;
final offerImages = caps.supportsVision;
```

The [support matrix](../platforms/support-matrix#features-by-runtime) lists
what each runtime reports.

## How routing works

`LlamaBackend()` picks the runtime from the model format: LiteRT-LM bundles run
on LiteRT-LM, and GGUF files run on llama.cpp. The `LlamaEngine` API is the
same for both, including `ChatSession` on native.

On LiteRT-LM Web, keep handling `LlamaInferenceException` after
`cancelGeneration()`. Only the pinned `@litert-lm/core@0.18.0` runtime's exact
`Task cancelled` error following a cancel request ends normally. Other errors,
including abort errors, still surface; `Task cancelled` without a cancel request
also remains a failure.

Native targets read the file header (`GGUF` or `LITERTLM`), so a file named
without a model extension, such as a download cached as `download`, still
loads in the right runtime. Only when the header is unrecognized do they fall
back to the extension: `.litertlm` runs on LiteRT-LM and anything else on
llama.cpp. A header that contradicts the extension, such as a GGUF file named
`model.litertlm`, throws `LlamaModelFormatException` instead of loading in
either runtime.

Web targets hand the URL to the runtime, which fetches it, so nothing reads the
content first: a `.litertlm` URL path runs on LiteRT-LM and anything else on
the llama.cpp WebGPU bridge. For a URL without a model extension, name the
format:

```dart
await engine.setModel(
  LlamaModel(
    ModelSource.url(
      Uri.parse('https://example.com/download?id=42'),
      format: ModelFormat.liteRtLm,
    ),
  ),
);
```

On native targets, `format:` names the format of a file whose header is
unrecognized; a recognized header that contradicts it throws
`LlamaModelFormatException`. LiteRT-LM still picks its Gemma 4 and Qwen
chat-template defaults from the file name, so pass a `fileName:` such as
`gemma-4-E2B-it.litertlm` when the URL does not name the model.

```dart
final engine = LlamaEngine(LlamaBackend());

// GGUF routes to llama.cpp.
await engine.setModel(
  LlamaModel(ModelSource.path('models/model-Q4_K_M.gguf')),
);

// .litertlm routes to LiteRT-LM. setModel replaces the GGUF model.
await engine.setModel(
  LlamaModel(ModelSource.path('models/gemma-4-E2B-it.litertlm')),
  params: const ModelParams(device: ComputeDevice.gpu),
);
```

## Choosing the device

`ModelParams.device` picks the device for either runtime. `ComputeDevice.auto`,
the default, keeps each runtime's own default:

| Runtime | `ComputeDevice.auto` |
| --- | --- |
| llama.cpp native | Every layer on the best GPU backend that loads; the CPU when no GPU module or device is present, on Android, on an iOS simulator and on macOS x86_64, Rosetta included ([#1597](https://github.com/leehack/llamadart/issues/1597)). |
| llama.cpp Web | The bridge's default: WebGPU when the browser has it, otherwise the WebAssembly CPU runtime. |
| LiteRT-LM native | GPU on Android, iOS and macOS; CPU on Linux and Windows. |
| LiteRT-LM Web | WebGPU, without a probe. |
| Image generation | The first GPU the stable-diffusion runtime reports, otherwise the CPU. |
| Decision models | As llama.cpp, through the encoder's `ModelParams`. |

Under `auto`, `preferredBackend` and `gpuLayers` still narrow the choice, as
before: `gpuLayers: 0` or a CPU or BLAS `preferredBackend` selects the CPU on
both runtimes, and a GPU `preferredBackend` (Vulkan, Metal, CUDA, OpenCL or
HIP) selects the LiteRT-LM GPU backend.

`cpu`, `gpu` and `npu` are requirements. The model runs there, or the load
throws `LlamaUnsupportedException` naming the device, runtime and platform; it
never falls back to another device:

- `cpu` loads no GPU layers and, on llama.cpp, only the CPU module.
- `gpu` on llama.cpp needs a GPU module and device for `preferredBackend`, and
  uses Vulkan on Android. Android Vulkan is experimental and fails on some
  devices; keep `auto` or `cpu` there unless you have validated your target
  devices
  ([known limitations](../platforms/known-platform-issues)). On
  an iOS simulator it uses Metal, as `GpuBackend.metal` does, and Metal
  returns incorrect output there
  ([#950](https://github.com/leehack/llamadart/issues/950)); keep `auto` or
  `cpu` on a simulator. On macOS x86_64 it uses Metal too, which returns
  garbled output on Intel Macs with AMD GPUs ([#1597](https://github.com/leehack/llamadart/issues/1597)).
  On both, an explicit GPU `preferredBackend` other than Metal, such as
  `GpuBackend.vulkan`, under `ComputeDevice.auto` also loads its GPU layers on
  Metal and logs a warning. On
  the Web it needs a WebGPU adapter and a bridge that loads GPU layers. On
  LiteRT-LM it needs the GPU backend: Linux arm64 has none, and macOS x64 has
  no LiteRT-LM runtime.
- `npu` is LiteRT-LM on Android only.

Android llama.cpp excludes the known unsafe Adreno 750 driver `2150604839`.
An explicit GPU request throws; automatic selection with a Vulkan preference
falls back to CPU with a warning when no usable GPU remains. A native crash
workaround does not establish correct inference for its quantized models.

Native LiteRT-LM starts its runtime on the first call that needs it, such as
the first generation or `tokenize`, so a GPU or NPU delegate that fails to
start throws `LlamaUnsupportedException` there rather than from the load. The
runtime does not say why it could not start, so under `gpu` or `npu` a
corrupt or truncated `.litertlm` file throws the same exception, whose
message names both causes. Under `auto`, a GPU engine that fails to start is
retried on the CPU with a `LlamaLogLevel.warn` record, and
`getBackendName()` then reports `LiteRT-LM cpu`; if the CPU engine fails too,
the GPU error is thrown, as `LlamaModelException` when the runtime reports no
engine. The retry applies only when neither `device` nor the deprecated
`liteRtLmBackend` or `LiteRtLmBackend(preferredBackend:)` names a device.
After a successful CPU fallback, backend-SPI callers can free and recreate the
context with the same automatic backend hints; the new context stays on the
CPU. Explicit GPU or NPU context requests still require reloading the model.
When `auto` already resolves to CPU (the Linux/Windows default, `gpuLayers: 0`,
or a CPU preference), an engine-create failure throws `LlamaModelException`
without a second attempt. Under `cpu`, an engine the runtime cannot create
throws `LlamaModelException` at that first call. Windows arm64 has no LiteRT-LM runtime.

`ModelParams.validate()`, which every `LlamaEngine` load calls before any
download, throws `LlamaArgumentException` when `device` contradicts another
field: `cpu` with a GPU `preferredBackend`, `gpu` or `npu` with a CPU or BLAS
`preferredBackend` or `gpuLayers: 0`, or any explicit device with the deprecated
`liteRtLmBackend`. Native platforms also reject `gpu` or `npu` with
`splitMode: ModelSplitMode.none` and a negative `mainGpu`, which native
llama.cpp runs on the CPU. The WebGPU bridge ignores negative `mainGpu`
values; explicit `gpu` still requires an adapter and active GPU layers after
load.

## Check a load before it runs

`LlamaEngine.checkLoad` runs the checks `setModel` runs before any file
resolves, and only those: it downloads nothing, reads no file, starts no
runtime and leaves a loaded model in place. Use it to grey out a model or a
device in a picker before the user waits for a download.

```dart
final engine = LlamaEngine(LlamaBackend());
final model = LlamaModel(ModelSource.parse('hf://owner/repo/model.litertlm'));
const params = ModelParams(device: ComputeDevice.gpu);

final check = await engine.checkLoad(model, params: params);
if (check.status == LlamaLoadCheckStatus.unsupported) {
  print('Cannot load here: ${check.reason}');
} else {
  // supported, deferred or unknown: the load checks the rest.
  await engine.setModel(model, params: params);
}
```

| Status | Meaning |
| --- | --- |
| `supported` | Every pre-load check passed. `format`, `runtime` and `device` say what the load would use; `ComputeDevice.auto` is resolved by the runtime at load. |
| `unsupported` | `setModel` would throw `error`, a `LlamaUnsupportedException` naming the missing capability and the platform or runtime condition, before any download. |
| `deferred` | Neither `ModelSource.format` nor the file name names the format, so the load checks the runtime once it reads the file. Set `ModelSource.format` to check earlier. |
| `unknown` | The backend cannot tell before loading: a backend without `BackendLoadCheck`, such as `LlamaEngine(LiteRtLmBackend())` or a custom `LlamaBackend`, or a single-runtime backend given a file name of another format, which it loads anyway. |

`setModel` and `checkLoad` share one check, so a report is `unsupported`
exactly when the load would fail before downloading. A `supported` report is
not proof the load succeeds: like `dart run llamadart:doctor`, it reports
policy, and the native library or browser assets, LoRA adapter limits, the
file and its memory are checked by the load. `checkLoad` takes no
`ModelLoadOptions`, so `setModel`'s download-option rejections (a `sha256`
with a projector, credentials across hosts, options a URL-loading backend does
not take) are not reported. `engine.capabilities` keeps describing the loaded model
only. A custom backend joins the check by implementing `BackendLoadCheck` from
`package:llamadart/backend.dart`.

`ModelParams.liteRtLmBackend` and `LiteRtLmBackendPreference` are deprecated
and keep working until 1.0. Under `device: auto` they still choose the
LiteRT-LM backend alone, for example to run llama.cpp on the CPU and LiteRT-LM
on the GPU from one `ModelParams`, and an unavailable choice still throws
`LlamaModelException`.

Formats are not interchangeable: a GGUF file cannot run through LiteRT-LM, and
a `.litertlm` bundle cannot run through llama.cpp. Load and generation
parameters are validated against the selected runtime. `llamadart` rejects
unsupported options for `.litertlm` loads instead of ignoring them, so a GGUF
tuning profile cannot appear to work while doing something different under
LiteRT-LM.

Pass a remote `ModelSource` to `LlamaEngine.load` or `setModel` for download
and cache flows. Native
targets cache remote GGUF and `.litertlm` sources before loading a local file.
Web targets pass simple unauthenticated `.litertlm` URLs to the LiteRT-LM
JavaScript runtime.

## What each runtime supports

The per-feature comparison (platforms, embeddings, LoRA, grammar, tool calling,
multimodal, tokenization and more) is in
[Features by runtime](../platforms/support-matrix#features-by-runtime). Rules
of thumb:

- Pick the runtime by model format first: GGUF runs on llama.cpp, `.litertlm`
  bundles on LiteRT-LM. Only llama.cpp offers GBNF grammars, multi-adapter
  LoRA and state persistence; LiteRT-LM web is text-only.
- Tokenization APIs work on llama.cpp and native LiteRT-LM, not on LiteRT-LM
  web.
- On the web, GGUF URLs use the llama.cpp WebGPU/CPU bridge and web-compatible
  `.litertlm` URLs use `@litert-lm/core`.

Load-time controls differ by runtime:

- Both: `device`.
- GGUF / llama.cpp: `preferredBackend`, `gpuLayers`, `contextSize`,
  `chatTemplate`, `numberOfThreads` / `numberOfThreadsBatch`, `batchSize` /
  `microBatchSize`, `splitMode` / `mainGpu`, and the LoRA and
  state-persistence APIs.
- `.litertlm` / LiteRT-LM: the deprecated `liteRtLmBackend`, `contextSize`,
  `chatTemplate`, `numberOfThreads`, one
  default-scale text LoRA adapter through `ModelParams.loras`, and the native
  `liteRtLm*` fields in
  [LiteRT-LM runtime controls](../configuration/runtime-parameters#litert-lm-runtime-controls).
  Generation honors `maxTokens`, `temp`, `topK`, `topP`, `seed`, and
  `stopSequences` (enforced by `llamadart`); `speculativeDecoding` is native
  only.

Bundle keys, module availability and selector names are in
[Native runtime configuration](../platforms/native-build-hooks).

## LiteRT-LM on web

`LlamaBackend.withTextHistory()` and the direct Web factory
`LiteRtLmBackend.withTextHistory()` forward ordered system/user/assistant text
through `ConversationConfig.preface.messages` and send the final user text once.
`engine.create(messages)` supplies the full transcript; `ChatSession` manages
it for you. A new runtime conversation is created and deleted for every request,
so reset/cancelled requests retain no hidden runtime history. `session.reset()`
keeps the system prompt by default; use `reset(keepSystemPrompt: false)` to clear it.

Existing `LlamaBackend()` and direct LiteRT constructors retain their prior
single-user-text routing for LiteRT Web models,
reporting multi-turn support false. Custom/GGUF delegate capabilities remain
unchanged. The portable opt-in preserves native selection and behavior. Existing
clients, including the Genkit adapter, do not adopt Web history automatically.

Check `supportsMultiTurnChat` after loading. The adapter probes that
`createConversation` consumes its `preface` option and that `getHistory()` runs
and returns an array. An older/missing API reports false and rejects history or
system prompts with `LlamaUnsupportedException`; one user text still works.
The probe runs no inference and does not qualify a model's semantic behavior.
Session trimming estimates the complete transcript, system prompt and previous
turns included, from UTF-8 JSON bytes (about one token per three bytes), so
`session.lastRequestFitContext` describes that estimate, not an exact count;
exact JS tokenizer/template accounting is unavailable, and the JS runtime still
applies its own template and context limits. `engine.chatTemplate`
returns this accounting serialization on the opted-in path. It does not replace
the model's JS template or the original structured messages sent for generation.
Stored assistant reasoning is omitted from replay/accounting; visible text,
including an empty assistant reply, is preserved.
Use a browser-compatible bundle; the JS package documents Gemma 4 E2B/E4B
`-web.litertlm` files. A native `.litertlm` file is not interchangeable.

LiteRT-LM Web rejects tool declarations/results, media and user/system thinking parts, a final
assistant/system message, custom templates (including an empty override),
`enableThinking: false`, template kwargs, explicit template clocks and native-only
`liteRtLm*` controls. Default thinking remains the model's behavior; no template
replacement or thinking-budget support is implied. Raw `generate` sends one user
text. Low-level `backend.applyChatTemplate` accepts one user message only; use
`engine.create` for structured history. Automatic tool loops remain unavailable.
The remaining #1152 scope is tracked in
[the runtime gap](https://github.com/leehack/llamadart/issues/1152).

## Measure before choosing

If both formats exist for your model, treat the choice as a deployment
benchmark: measure the exact model artifact, device, prompt shape, and output
length your app will ship. The files may not be identical quantizations or
runtime graphs, so this compares deployments, not kernels.

- Keep the device awake, unlocked, foregrounded, and out of battery saver.
- Record thermal status and cooling state before and after the run.
- Use the same prompt, output-token cap, context size, stop rules, and sampling
  settings where both backends expose them.
- Separate cold-start numbers from warm steady-state numbers.
- Run enough repetitions to report median and outliers, not only the last run.
- Record early EOS separately from requested output length.
- Compare wall-clock latency and backend timing counters; they answer different
  questions.
- Treat `GenerationParams.speculativeDecoding` as a per-model, per-device
  tuning knob, not a guaranteed speedup; the `LlamaEngine` default is off.

[Performance tuning](./performance-tuning#compare-fairly) summarizes a
historical Gemma 4 E2B comparison on Pixel 9 Pro, macOS and web.

## Reduce app size

Native apps include the llama.cpp and LiteRT-LM runtime families by default, so
one build can load both GGUF and `.litertlm` models. To ship only one, set
`llamadart_native_runtimes` as described in
[Native Build Hooks](../platforms/native-build-hooks). The experimental
`stable_diffusion` runtime, which [image generation](./image-generation)
needs, is never included unless named there or selected with `all`. A list
there replaces the defaults: `all` bundles every runtime published for the
target.
