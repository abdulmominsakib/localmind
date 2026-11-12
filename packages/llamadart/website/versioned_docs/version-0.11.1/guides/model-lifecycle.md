---
title: Load, switch and unload models
sidebar_label: Model lifecycle
description: Load, switch and unload models safely, load from Hugging Face or a URL, save and restore prompt state, and recover from interrupted LiteRT-LM cleanup.
---

This guide covers loading, switching and releasing a model on one
`LlamaEngine`.

## Load, use and dispose

```dart
final engine = await LlamaEngine.load(
  LlamaModel(ModelSource.path('/path/to/model.gguf')),
  params: const ModelParams(contextSize: 4096),
);
try {
  // ...run inference...
} finally {
  await engine.dispose();
}
```

`LlamaEngine.load` creates the engine and loads the model. The load is atomic:
when it throws, the engine and its backend are already disposed and nothing
stays loaded, so start the `try` after it returns. It takes:

- `LlamaModel(source, projector: ...)`: the model file and, for a GGUF model,
  its [multimodal projector](./multimodal).
- `params`: the `ModelParams` of the load
  ([Runtime parameters](../configuration/runtime-parameters)).
- `download`: the `ModelLoadOptions` for remote files, and `onProgress` for
  their progress ([Download and cache models](./model-downloads)).
- `store`: a `ModelFileStore` holding the resolver and download manager, to
  replace the defaults.

When the engine must exist before the load, such as a field or an engine that
is reused, create it with `LlamaEngine(LlamaBackend())` and call
`engine.setModel(...)`, which takes the same model, `params`, `download` and
`onProgress`.

Before any download or file access, the load throws for what its arguments
already show: invalid `ModelParams`, a projector for a `.litertlm` model or
`ComputeDevice.npu` for a GGUF model (when `ModelSource.format` or the file
name gives the format), `ModelLoadOptions.sha256` for a model with a
projector, and on web a `download` option other than the defaults.

`dispose()` cancels running generations, unloads the model and releases the
backend. It is final, on every engine: later calls return the same future,
`isDisposed` is true, `capabilities` reports the engine as disposed, and a
load, a request or a backend query such as `getBackendName()` or
`getVramInfo()` throws `LlamaStateException`. A load still running when
`dispose()` is called stops its downloads at once and throws
`LlamaStateException` too, and nothing stays loaded. This includes model and
LoRA downloads started by deprecated `loadModelSource`; disposal does not
cancel caller-owned tokens or wait for a custom resolver/manager that ignores
cancellation. Package-managed transfers stop at their next cancellation
checkpoint. To free the model's memory and keep the engine, call
`unloadModel()`; to load another model, call `setModel`.

### Exiting with a model loaded

On macOS Metal, ggml aborts a process that exits with a model, context,
decision head or image model still loaded
(`GGML_ASSERT([rsets->data count] == 0)` in `ggml_metal_rsets_free`).

On Apple platforms the llama.cpp runtime (`llamadart-native` `v0.5.0-2` and
later) frees the llama.cpp models, contexts, projectors and decision heads
that are still allocated when the process exits. That covers the exits where
llamadart's own cleanup could not reach an object:

- a Flutter macOS quit while a model is loading, and a quit after a hot
  restart that interrupted a load;
- a Dart program that returns from `main`, dies of an unhandled error or
  kills an isolate while a model or context is being created.

It does not cover a native host that calls C `exit()` while a llamadart
isolate is still working: an exit during a call the runtime does not guard
(tokenizing, detokenizing, reading metadata, building a sampler, decoding an
image or audio file) can crash, and an exit during a guarded call that runs
longer than two seconds (an image or audio evaluation, a long batch) aborts
as before.

The stable_diffusion runtime (`stable-diffusion-native` `v0.2.0-1` and later)
does the same for image models, and no longer calls back into Dart to report
progress. That covers:

- a Dart program that dies of an unhandled error while an image model loads
  or generates, which used to abort the VM with
  `GetFfiCallbackMetadata called after shutdown`;
- a Flutter macOS quit while an image model loads or generates, and a hot
  restart during a load, which also used to abort in the progress callback;
- a native host's C `exit()` while an image model is loaded, loading or
  generating. The runtime then cancels the generation and waits for the load
  or the generation up to 15 seconds: stable-diffusion.cpp stops only before
  a sampling step or before decoding an image, and cannot interrupt a load.
  A phase that takes longer than that is not freed, and ggml-metal aborts as
  before. With a llama.cpp call running too, the exit can take about 17.5
  seconds.

- A Dart program that returns from `main` or dies of an unhandled error does
  not need to dispose first: llamadart frees what its engines still hold as
  the program ends, after any native call still running finishes. Nothing
  cancels a running image generation on that path, so the process ends only
  when the generation does: about 5 s for the rest of a 40-step SDXS
  generation and 11.5 s for SD-Turbo on an M4 Max. Cancel the task or
  dispose the engine first to end sooner.

  `exit()` from `dart:io` skips C++ static destructors and never aborts.
- A Flutter macOS app that quits through AppKit (the Quit menu item, a Quit
  Apple event, closing its last window, or
  `ServicesBinding.exitApplication`) does not need to dispose first to exit
  cleanly either. Flutter shuts the isolates down before the process exits,
  so llamadart frees what its engines still hold, and the runtimes above
  free a model the quit caught mid-load. Still dispose every engine,
  including `DecisionEngine` and `ImageGenerationEngine`, before the app
  quits:

  - The quit waits for a native call that is still running, so a quit
    during an image generation takes the rest of the generation.
  - Only macOS has been measured. The runtimes free nothing at process exit
    outside Apple platforms, and on Linux a C `exit()` during a model load
    or a generation crashes
    ([#949](https://github.com/leehack/llamadart/issues/949)); whether a
    Flutter Linux or Windows quit can reach that is not known.

  Desktop Flutter apps do not run `State.dispose` on quit, so dispose from
  an exit request instead (`AppExitResponse` comes from `dart:ui`):

```dart
final listener = AppLifecycleListener(
  onExitRequested: () async {
    await engine.dispose();
    return AppExitResponse.exit;
  },
);
// Call listener.dispose() when its owner is disposed.
```

If the engine's owner can go away before the app quits, such as a pushed
route, its listener goes with it, and the `dispose()` it started in
`State.dispose` may still be running at quit. Register disposal with one
app-level exit listener instead, and have that listener also await disposals
already in progress. The example chat app does this with
[`AppExitCoordinator`](https://github.com/leehack/llamadart/blob/main/example/chat_app/lib/services/app_exit_coordinator.dart).

A Flutter hot restart (debug builds only) shuts the old isolates down, which
frees the models they hold once a native call that is still running has
returned. A llama.cpp or image model one of them was still loading is freed
by the runtime when the app quits. Both are measured on macOS.

`LlamaBackend()` routes GGUF to llama.cpp and `.litertlm` bundles to
LiteRT-LM, by file header on native targets and by URL extension on web
([How routing works](./backend-selection#how-routing-works)), with the same
lifecycle:

```dart
await engine.setModel(
  LlamaModel(ModelSource.path('/path/to/gemma-4-E2B-it.litertlm')),
  params: const ModelParams(device: ComputeDevice.gpu),
);
```

`ComputeDevice.gpu` requires a GPU: when the platform has no LiteRT-LM GPU
backend, or its delegate fails to start, the load or the first generation
throws `LlamaUnsupportedException`. Leave `device` at `ComputeDevice.auto` to
use each runtime's default; [Choosing the device](./backend-selection#choosing-the-device)
lists them.

Native `.litertlm` loads use the LiteRT-LM runtime bundled by the build hook.
Web `.litertlm` URLs use the `@litert-lm/core` JavaScript runtime: before
loading, set `window.LiteRtLmEngine = module.Engine` or set
`window.__llamadartLiteRtLmModuleUrl` to an `@litert-lm/core` ESM URL. See
[Choosing llama.cpp or LiteRT-LM](./backend-selection).

## Load from Hugging Face or a URL

A `ModelSource` is a local path, an HTTP(S) URL or an `hf://` reference;
`ModelSource.parse` accepts any of them as a string.

```dart
final cancelToken = ModelDownloadCancelToken();
final engine = await LlamaEngine.load(
  LlamaModel(ModelSource.parse('hf://owner/repo/path/to/model.gguf')),
  download: ModelLoadOptions(cancelToken: cancelToken),
  onProgress: (progress) {
    final fraction = progress.fraction;
    if (fraction != null) {
      print('download progress: ${(fraction * 100).toStringAsFixed(1)}%');
    }
  },
);
```

Native targets download each remote file into a cache and load the local copy,
resuming an interrupted download and reusing a cached file. `download` applies
to every remote file, and `onProgress` reports the model and its projector
together: with a projector, `totalBytes` and `fraction` are null until the
model has downloaded and the projector reports its size, so show
`receivedBytes` until then. `cancelToken.cancel()` stops the load, which
throws `LlamaStateException`.

On web the runtime fetches each file itself: `.gguf` URLs load through the
llama.cpp WebGPU bridge and `.litertlm` URLs through LiteRT-LM JS. A
`ModelSource.path` is a URL relative to the document, or a `blob:` URL;
`download` must stay at its defaults, and `onProgress` reports only the
model's fetch, as a fraction that ends at 0.5 when there is a projector.

Revisions, private repositories, progress UI, checksums and cache location:
[Download and cache models](./model-downloads).

## Switch models

`setModel` replaces the model the engine holds; no `unloadModel()` is needed
first:

```dart
await engine.setModel(
  LlamaModel(ModelSource.path('/path/to/another_model.gguf')),
);
```

On native targets the old model keeps serving until every file of the new one
has resolved or downloaded. Only then is it unloaded, which cancels its
generations, and the new model and its projector load. A failure or a cancel
before that point leaves the old model loaded; one after it leaves nothing
loaded. On web the runtime fetches the files during the load, after the old
model is unloaded.

Unload, replacement, and disposal stop active chat-session requests with the
same cancellation behavior as `cancelGeneration()`. A partial reply stays in
history; a request stopped before any reply rolls back and throws
`LlamaStateException`. Tool loops report `LlamaToolLoopStopReason.cancelled`;
running tool handlers finish, and unfinished tool turns roll back before
another model request.

Replacing or unloading a model also releases its multimodal projector and
active LoRA adapters. Pass the new model's projector as
`LlamaModel(source, projector: ...)`; adapters listed in `ModelParams.loras`
are applied again by each load, and adapters added with `setLoraSource` must
be set again. `unloadModel()` frees the model without loading another.

## Readiness and serialized loads

- Check `engine.isReady` before inference.
- A standalone projector load throws `LlamaStateException` if the model is
  unloaded, replaced, or disposed while its context is being created. Model
  teardown waits for that context to be released. Prefer
  `setModel(LlamaModel(source, projector: ...))` to load both together.
- `setModel` and `unloadModel` do not queue. While a `setModel` runs, another
  `setModel` or an `unloadModel` throws `LlamaStateException`. Stop the
  running load with its `download` cancel token, or serialize model switches
  in app code (for example, disable the model picker until the switch
  completes).

## Save and restore prompt state

Native backends and WebGPU bridge assets `v0.1.15+` can save and restore
llama.cpp KV-cache state to avoid re-evaluating a long raw prompt on resume or
when forking a prompt prefix. Gate the flow with `supportsStatePersistence` so
backends that do not implement state persistence can fall back to prompt
re-evaluation. LiteRT-LM currently reports state persistence as unsupported. If
a web app overrides the bridge to older/custom assets that do not expose state
APIs, `stateSaveFile(...)` / `stateLoadFile(...)` throw a clear unsupported
error and callers should use the same fallback path.

```dart
if (!engine.supportsStatePersistence) {
  throw LlamaUnsupportedException('State persistence is not supported by this backend.');
}

final prompt = 'You are a concise assistant. Summarize llamadart.';
final tokens = await engine.tokenize(prompt);

// Populate the KV cache, then persist it with the token sequence that produced
// state. This sample uses a WebGPU bridge WASMFS virtual path. Native apps
// should replace it with an app-writable filesystem path.
const statePath = '/prompt-prefix.state';

await engine.generate(
  prompt,
  params: const GenerationParams(maxTokens: 1, reusePromptPrefix: true),
).drain<void>();
await engine.stateSaveFile(statePath, tokens: tokens);

// Later, after loading the same model with a compatible runtime/bridge build:
final restored = await engine.stateLoadFile(
  statePath,
  tokenCapacity: await engine.getContextSize(),
);

await for (final token in engine.generate(
  '$prompt Continue from the saved prefix.',
  params: const GenerationParams(reusePromptPrefix: true),
)) {
  print(token);
}

print('Restored ${restored.tokens.length} prompt tokens');
```

Important caveats:

- State files are opaque llama.cpp artifacts. Treat them as tied to the same
  model file and compatible runtime/build that created them. Web paths refer to
  the bridge WASMFS virtual filesystem and are not durable across page reloads.
  Durable browser storage currently requires app-level export/import outside the
  Dart `stateSaveFile` / `stateLoadFile` helpers.
- `stateLoadFile(...)` restores native KV-cache state only. It does not rebuild
  `ChatSession` message history; persist and reconstruct chat messages
  separately when using the high-level chat API.
- Pass a `tokenCapacity` large enough for the saved prompt token sequence. The
  current context size is usually a safe default.

## LiteRT-LM interrupted cleanup

Native LiteRT-LM worker termination fails outstanding requests with
`LlamaStateException` and closes their Dart response ports. If native cleanup
cannot be confirmed, unload/dispose also throws and the backend refuses further
work. Restart the process before retrying that runtime; creating another backend
in the same process does not establish that the old native operation stopped.

A Dart timeout or killed isolate does not interrupt a blocking native call.
