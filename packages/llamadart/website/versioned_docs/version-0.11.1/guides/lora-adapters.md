---
title: Apply LoRA adapters at runtime
sidebar_label: LoRA adapters
description: Load, stack, scale and remove LoRA adapters at inference time with LlamaEngine, with platform notes and troubleshooting.
---

This guide covers practical LoRA usage in `llamadart`: adapters loaded with
the model through `ModelParams.loras`, and the runtime adapter management
APIs.

`llamadart` itself is an inference/runtime library. LoRA training is done in a
separate training workflow, then adapters are loaded at inference time.

## Runtime API surface

`LlamaEngine` exposes three LoRA operations:

- `setLoraSource(source, scale: ...)`: load an adapter or update its scale.
- `removeLoraSource(source)`: remove one adapter from the active set.
- `clearLoras()`: remove all active adapters from the current context.

An adapter is a `ModelSource`, like a model: a local path
(`ModelSource.path`), an HTTP(S) URL or a Hugging Face file
(`ModelSource.parse('hf://owner/repo/adapter.gguf')`). The `String` path forms
`setLora(path)`, `removeLora(path)` and `LoraAdapterConfig(path: ...)` are
deprecated.

## Downloading adapters

On native backends `setLoraSource` checks a local file, or downloads a remote
adapter into the model cache with its `download` options, resuming an
interrupted download and reusing a cached file:

```dart
final adapter = ModelSource.parse('hf://owner/repo/domain-lora.gguf');
final cancel = ModelDownloadCancelToken();

await engine.setLoraSource(
  adapter,
  scale: 0.7,
  download: ModelLoadOptions(cancelToken: cancel),
  onProgress: (progress) => print('${progress.receivedBytes} bytes'),
);
```

- `onProgress` reports the download; cancelling the token stops it and
  `setLoraSource` throws `LlamaStateException`.
- On WebGPU the bridge fetches the source's URL; a `ModelSource.path` is a
  URL relative to the document, or a `blob:` URL.

## Basic runtime flow

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final engine = await LlamaEngine.load(
    LlamaModel(ModelSource.path('/models/base-model.gguf')),
  );

  try {
    await engine.setLoraSource(
      ModelSource.path('/models/lora/domain.gguf'),
      scale: 0.7,
    );

    final answer = await engine.create(
      const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Answer as a domain specialist in one paragraph.',
        ),
      ],
    ).text();
    print(answer);
  } finally {
    await engine.dispose();
  }
}
```

## Loading adapters with the model

Pass adapters as `ModelParams.loras` to apply them as part of the load:

```dart
await engine.setModel(
  LlamaModel(ModelSource.path('/models/base-model.gguf')),
  params: ModelParams(
    loras: [
      LoraAdapterConfig.source(
        ModelSource.path('/models/lora/style.gguf'),
        scale: 0.35,
      ),
      LoraAdapterConfig.source(
        ModelSource.parse('hf://owner/repo/domain-lora.gguf'),
        scale: 0.70,
      ),
    ],
  ),
);
```

- `LlamaEngine` resolves each adapter source in list order before the model
  loads, as `setLoraSource` does, with the adapter's own options:
  `LoraAdapterConfig.source(source, download: ModelLoadOptions(...))`.
  Without them an adapter takes only the non-secret options of the load
  (cache policy and directory, resume, retries and cancel token). The load's
  bearer token, headers and `sha256` never reach an adapter's host, so set an
  adapter's own `download` when it needs authentication. Adapter downloads
  report no progress, and a failed one fails the load.

- On llama.cpp, native and WebGPU, each adapter is applied in list order at
  its scale, exactly as `setLoraSource(source, scale: ...)` would, once the
  model is loaded. `setLoraSource`, `removeLoraSource` and `clearLoras` can
  change them afterwards.
- If an adapter cannot be applied, the load fails and the model is unloaded:
  an aLoRA adapter, or WebGPU bridge assets without runtime LoRA, throw
  `LlamaUnsupportedException`; any other failure, such as a missing file or an
  adapter for another base model, throws `LlamaModelException`. The
  unsupported error names the adapter in its message; `LlamaModelException`
  carries the adapter and cause in `details`.
- Every load applies its own `ModelParams.loras` again, so a reload with the
  same `ModelParams` restores the same adapters.

## Stacking adapters

You can activate multiple adapters on the same loaded model:

```dart
final style = ModelSource.path('/models/lora/style.gguf');
final domain = ModelSource.path('/models/lora/domain.gguf');

await engine.setLoraSource(style, scale: 0.35);
await engine.setLoraSource(domain, scale: 0.70);
```

- Calling `setLoraSource(...)` again with the same source updates scale. When
  its options resolve the source to another file, such as another
  `cacheDirectory`, that file replaces the adapter applied from the source.
- Use `removeLoraSource(source)` to disable one adapter.
- Use `clearLoras()` to reset to base model behavior.

## Training your own LoRA adapters

For end-to-end training + conversion, start with the official notebook:

- [LoRA Training Notebook](https://github.com/leehack/llamadart/blob/main/example/training_notebook/lora_training.ipynb)

Recommended workflow:

1. Pick a base model family that you will also serve in `llamadart`.
2. Train LoRA weights (for example, QLoRA/PEFT flow in the notebook).
3. Export adapter artifacts from training.
4. Convert adapter artifacts into llama.cpp-compatible GGUF adapter files.
5. Validate outputs in a native test run, then load adapters with
   `ModelParams.loras` or `setLoraSource(...)`.

Practical compatibility checks:

- Keep tokenizer/model family aligned between base model and adapter.
- Validate adapter behavior on the same quantized base model class you deploy.
- Keep a small golden-prompt set to compare base vs adapter output drift.

## Scale tuning guidance

- Start around `0.4` to `0.8` for first-pass evaluation.
- Lower scales (`0.1` to `0.3`) help preserve base-model behavior.
- Higher scales can over-steer outputs; validate with representative prompts.

## aLoRA adapters are not supported

Activated LoRA (aLoRA) adapters carry a sequence of invocation tokens and must
take effect only once that sequence appears in the prompt. llamadart applies
every adapter from the start of generation, so an aLoRA adapter used this way
would change output without any error — the failure is silent and looks like a
badly behaved LoRA.

`engine.setLoraSource`, and a load with `ModelParams.loras`, inspect each adapter
after loading it and throw `LlamaUnsupportedException` for an aLoRA adapter:

```text
The adapter at <path> is an aLoRA adapter (N invocation token(s)). llamadart
applies LoRA adapters from the start of generation, but an aLoRA adapter must
activate only after its invocation sequence appears in the prompt, so applying
it eagerly would silently change output. Use a standard LoRA adapter until
invocation-aware activation is implemented.
```

Native LoRA support should not be read as aLoRA support. Invocation-aware
activation, prompt-cache safety, and multiple-aLoRA behavior are not yet
implemented.

Custom native runtimes must export the aLoRA metadata functions; see
[Native Build Hooks](../platforms/native-build-hooks).

## Lifecycle notes

- LoRA activation is tied to the active context.
- `unloadModel()`, `dispose()` or a `setModel` that replaces the model
  releases model/context resources and clears active adapter state, including
  changes made with `setLoraSource`.
- Each load applies its `ModelParams.loras`; re-apply adapters set with
  `setLoraSource` after reloading a model.

## Platform notes

- `ModelParams.loras` and runtime LoRA operations are supported by native
  llama.cpp/GGUF backends.
- Native LiteRT-LM can accept one default-scale text LoRA adapter at model load
  through `ModelParams.loras`; runtime LoRA updates, stacking, and custom scales
  remain unsupported there.
- WebGPU applies `ModelParams.loras` and runtime LoRA adapters with bridge
  assets whose
  `getLoraAdapterCapabilities()` reports support
  (bridge assets `v0.1.54+`, the default pin among them;
  [llama-web-bridge#142](https://github.com/leehack/llama-web-bridge/pull/142)).
  The adapter source is a remote URL or `hf://` file; the bridge downloads
  each adapter once per model load. An aLoRA adapter throws `LlamaUnsupportedException`, and an
  adapter it cannot load, such as one for another base model, throws
  `LlamaModelException`. On older bridge assets every WebGPU LoRA call, and
  every load with `ModelParams.loras`, throws `LlamaUnsupportedException`.
- LiteRT-LM web runtime LoRA calls throw `LlamaUnsupportedException` instead of
  reporting no-op success.

## Troubleshooting

- If `setLoraSource(...)` or a load with `ModelParams.loras` fails, verify the
  adapter file or URL is accessible at runtime.
- Ensure adapter/base-model compatibility (architecture/family alignment).
- When behavior seems unchanged, confirm you are testing on a llama.cpp/GGUF
  target, native or WebGPU with capable bridge assets, and not a LiteRT-LM
  path.
