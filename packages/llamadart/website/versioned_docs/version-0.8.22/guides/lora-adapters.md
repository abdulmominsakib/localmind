---
title: LoRA Adapters
---

This guide covers practical LoRA usage in `llamadart` with runtime adapter
management APIs.

`llamadart` itself is an inference/runtime library. LoRA training is done in a
separate training workflow, then adapters are loaded at inference time.

## Runtime API surface

`LlamaEngine` exposes three LoRA operations:

- `setLora(path, scale: ...)`: load or update an adapter scale.
- `removeLora(path)`: remove one adapter from the active set.
- `clearLoras()`: remove all active adapters from the current context.

## Basic runtime flow

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final engine = LlamaEngine(LlamaBackend());

  try {
    await engine.loadModel('/models/base-model.gguf');

    await engine.setLora('/models/lora/domain.gguf', scale: 0.7);

    await for (final chunk in engine.create(
      const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Answer as a domain specialist in one paragraph.',
        ),
      ],
    )) {
      final text = chunk.choices.first.delta.content;
      if (text != null) {
        print(text);
      }
    }
  } finally {
    await engine.dispose();
  }
}
```

## Stacking adapters

You can activate multiple adapters on the same loaded model:

```dart
await engine.setLora('/models/lora/style.gguf', scale: 0.35);
await engine.setLora('/models/lora/domain.gguf', scale: 0.70);
```

- Calling `setLora(...)` again with the same path updates scale.
- Use `removeLora(path)` to disable one adapter.
- Use `clearLoras()` to reset to base model behavior.

## Training your own LoRA adapters

For end-to-end training + conversion, start with the official notebook:

- [LoRA Training Notebook](https://github.com/leehack/llamadart/blob/main/example/training_notebook/lora_training.ipynb)

Recommended workflow:

1. Pick a base model family that you will also serve in `llamadart`.
2. Train LoRA weights (for example, QLoRA/PEFT flow in the notebook).
3. Export adapter artifacts from training.
4. Convert adapter artifacts into llama.cpp-compatible GGUF adapter files.
5. Validate outputs in a native test run, then load adapters with `setLora(...)`.

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

Rather than guess, `setLoraAdapter` inspects the adapter after loading it and
rejects an aLoRA adapter with `LlamaUnsupportedException`:

```
The adapter at <path> is an aLoRA adapter (N invocation token(s)). llamadart
applies LoRA adapters from the start of generation, but an aLoRA adapter must
activate only after its invocation sequence appears in the prompt, so applying
it eagerly would silently change output. Use a standard LoRA adapter until
invocation-aware activation is implemented.
```

Native LoRA support should not be read as aLoRA support. Invocation-aware
activation, prompt-cache safety, and multiple-aLoRA behavior are not yet
implemented.

Custom native runtime overrides must also export both
`llama_adapter_get_alora_n_invocation_tokens` and
`llama_adapter_get_alora_invocation_tokens`. If that metadata inspection ABI is
missing, partial, or incompatible, llamadart fails closed with
`LlamaUnsupportedException` and asks you to use a runtime artifact matching the
package bindings or another ABI-compatible build. It does not activate an
adapter whose type cannot be checked safely.

## Lifecycle notes

- LoRA activation is tied to the active context.
- `unloadModel()` or `dispose()` releases model/context resources and clears
  active adapter state.
- Re-apply adapters after reloading a model.

## Platform notes

- Runtime LoRA operations are supported by native llama.cpp/GGUF backends.
- Native LiteRT-LM can accept one default-scale text LoRA adapter at model load
  through `ModelParams.loras`; runtime LoRA updates, stacking, and custom scales
  remain unsupported there.
- WebGPU and LiteRT-LM web throw an unsupported-operation error for runtime
  LoRA APIs instead of reporting no-op success.

## Troubleshooting

- If `setLora(...)` fails, verify the adapter path is accessible at runtime.
- Ensure adapter/base-model compatibility (architecture/family alignment).
- When behavior seems unchanged, confirm you are testing on a native
  llama.cpp/GGUF target and not a web or LiteRT-LM path.
