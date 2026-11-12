---
title: Load, switch and unload models
sidebar_label: Model lifecycle
description: Load, switch and unload models safely, load from Hugging Face or a URL, save and restore prompt state, and recover from interrupted LiteRT-LM cleanup.
---

This guide covers loading, switching and releasing a model on one
`LlamaEngine`.

## Load, use and dispose

```dart
final engine = LlamaEngine(LlamaBackend());
try {
  await engine.loadModel('/path/to/model.gguf');
  // ...run inference...
} finally {
  await engine.dispose();
}
```

`dispose()` unloads the model and releases the backend. Call `unloadModel()`
instead when the engine will load another model.

On macOS Metal, ggml aborts a process that exits with a model, context,
decision head or image model still loaded
(`GGML_ASSERT([rsets->data count] == 0)` in `ggml_metal_rsets_free`).

- A Dart program that returns from `main` or dies of an unhandled error does
  not need to dispose first: llamadart frees what its engines still hold as
  the program ends, after any native call still running finishes. The exit
  can still abort when the program dies of an error:
  - while a model, context or image model is being created: the VM stops the
    worker as soon as that native call returns, before llamadart can track
    the new object;
  - while an image model loads or generates: stable-diffusion.cpp reports
    progress through a Dart callback, which the shutting-down VM rejects;
  - rarely, while `dispose()` is freeing objects, which can leave one unfreed.

  `exit()` from `dart:io` skips the native teardown and never aborts.
- A Flutter app that quits through AppKit (Cmd-Q, closing its last window, or
  `ServicesBinding.exitApplication`) is not guaranteed to run that cleanup,
  so dispose every engine, including `DecisionEngine` and
  `ImageGenerationEngine`, before it quits. Desktop Flutter apps do not run
  `State.dispose` on quit, so dispose from an exit request instead
  (`AppExitResponse` comes from `dart:ui`):

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

A Flutter hot restart (debug builds only) discards the old isolates without
freeing their models, so quitting after one can still abort
([#813](https://github.com/leehack/llamadart/issues/813)).

`LlamaBackend()` routes by file extension: `.gguf` to llama.cpp and
`.litertlm` to LiteRT-LM, with the same lifecycle:

```dart
await engine.loadModel(
  '/path/to/gemma-4-E2B-it.litertlm',
  modelParams: const ModelParams(
    liteRtLmBackend: LiteRtLmBackendPreference.gpu,
  ),
);
```

Native `.litertlm` loads use the LiteRT-LM runtime bundled by the build hook.
Web `.litertlm` URLs use the `@litert-lm/core` JavaScript runtime: before
loading, set `window.LiteRtLmEngine = module.Engine` or set
`window.__llamadartLiteRtLmModuleUrl` to an `@litert-lm/core` ESM URL. See
[Choosing llama.cpp or LiteRT-LM](./backend-selection).

## Load from Hugging Face or a URL

`loadModelSource` takes a `ModelSource`: a local path, an HTTP(S) URL or an
`hf://` reference.

```dart
await engine.loadModelSource(
  ModelSource.parse('hf://owner/repo/path/to/model.gguf'),
  onProgress: (progress) {
    final fraction = progress.fraction;
    if (fraction != null) {
      print('download progress: ${(fraction * 100).toStringAsFixed(1)}%');
    }
  },
);
```

Native targets download the file into a cache and load the local copy. On web,
`.gguf` URLs load through the llama.cpp WebGPU bridge and `.litertlm` URLs
through LiteRT-LM JS; web rejects local paths. `loadModelFromUrl(url)` loads a
raw URL on a backend that supports URL loading.

Revisions, private repositories, progress UI, checksums and cache location:
[Download and cache models](./model-downloads).

## Switch models

`loadModel(...)` throws `LlamaStateException` while a model is loaded. Unload
first:

```dart
await engine.unloadModel();
await engine.loadModel('/path/to/another_model.gguf');
```

`unloadModel()` also releases the multimodal projector and active LoRA
adapters. Load the projector again after the new model; adapters listed in
`ModelParams.loras` are applied again by each load, and adapters added with
`setLora` must be set again.

## Readiness and serialized loads

- Check `engine.isReady` before inference.
- `loadModel`, `loadModelFromUrl` and `unloadModel` do not queue. A call made
  while another is running throws `LlamaStateException`, so serialize model
  switches in app code (for example, disable the model picker until the switch
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
