---
name: llamadart-lora
description: >-
  Use when applying LoRA adapters with llamadart: training an adapter
  elsewhere and converting it to GGUF for a base model, loading, stacking,
  scaling or removing adapters at runtime with setLoraSource,
  removeLoraSource and clearLoras, downloading adapters from a URL or Hugging
  Face, passing ModelParams.loras, or checking LoRA support on native
  llama.cpp, WebGPU and LiteRT-LM.
---

# LoRA adapters with llamadart

llamadart applies LoRA adapters at inference time; it does not train them.

## Guidelines

- Produce adapters outside llamadart: fine-tune with an external stack (for
  example Hugging Face PEFT/QLoRA, see `example/training_notebook`), then
  convert the adapter directory to a GGUF adapter with llama.cpp's
  `convert_lora_to_gguf.py`. Train and convert against the same base model
  (architecture, size and tokenizer) you serve; an adapter for another base
  model fails to load (`LlamaModelException`).
- Deploy the adapter with the same base model family and a comparable
  quantization to the one you evaluated it on, and keep a small golden-prompt
  set to compare base and adapter output.
- Loading the base model and basic chat are covered by the
  llamadart-getting-started and llamadart-chat-streaming skills.
- Runtime API on `LlamaEngine`, all `Future<void>`, all needing a loaded model
  (otherwise `LlamaContextException`):
  - `setLoraSource(source, scale: 1.0)` loads the adapter on first use and
    activates it; calling it again with the same source (equivalent path
    spellings such as `./a.gguf` and `a.gguf` count as the same) only changes
    the scale.
  - `removeLoraSource(source)` deactivates one adapter.
  - `clearLoras()` returns to base-model behavior.
- An adapter is a `ModelSource`: `ModelSource.path` for a local file, or an
  HTTP(S) URL or `hf://owner/repo/file.gguf` through `ModelSource.parse`. On
  native backends `setLoraSource` downloads a remote adapter into the model
  cache (or reuses it) with its `download` options and reports `onProgress`;
  the cancel token stops it with `LlamaStateException`. `setLora(path)`,
  `removeLora(path)` and `LoraAdapterConfig(path: ...)` are deprecated.
- Adapters stack: each distinct source passed to `setLoraSource` stays active
  with its own scale until removed. Start tuning scales around `0.4`-`0.8`; lower
  (`0.1`-`0.3`) preserves more base behavior, higher can over-steer.
- Adapters you know at load time go in `ModelParams.loras` as
  `LoraAdapterConfig.source(source, scale: ...)`. `LlamaEngine` resolves
  their sources before the model loads, with each adapter's own
  `download:` options, or else only the load's cache policy, directory and
  cancel token; the load's bearer token, headers and `sha256` never reach an
  adapter's host (no progress). Disposing the engine cancels these downloads,
  including those of deprecated `loadModelSource`, without cancelling the
  caller's load or adapter tokens. On llama.cpp
  (native and WebGPU) each is applied in list order at its scale, as
  `setLoraSource` would, once the model loads; `setLoraSource`,
  `removeLoraSource` and `clearLoras` can change them afterwards. If one cannot be applied the load fails and the
  engine is left with no model: `LlamaUnsupportedException` (naming the
  adapter) for an unsupported adapter or WebGPU bridge assets, otherwise
  `LlamaModelException` with the adapter and cause in its `details`.
- Adapter state belongs to the loaded model. `unloadModel()`, `dispose()` and
  a `setModel` that replaces the model drop it, including `setLoraSource`
  changes. Each load applies its own
  `ModelParams.loras` again; re-apply `setLoraSource` adapters after a reload
  or model switch.
- An aLoRA (activated LoRA) adapter throws `LlamaUnsupportedException` from
  `setLoraSource` or from a load that lists it in `ModelParams.loras`: llamadart
  applies adapters from the first token and does not implement
  invocation-sequence activation. Use a standard LoRA adapter.
- Runtime support by target:
  - Native llama.cpp (GGUF): `ModelParams.loras` and the full runtime API,
    multiple adapters, custom scales, local or downloaded adapter files.
  - WebGPU (GGUF on web): needs bridge assets whose
    `getLoraAdapterCapabilities()` reports support (the pinned assets do), for `ModelParams.loras` and the runtime API.
    The bridge fetches the source's URL once per model load; a
    `ModelSource.path` is a URL relative to the document, or a `blob:` URL. Older bridge assets throw
    `LlamaUnsupportedException` on every LoRA call and on a load with
    `ModelParams.loras`.
  - Native LiteRT-LM (`.litertlm`): current upstream v0.18.1/v0.19.0 advanced
    engines reject initial text adapters. The legacy setter accepting a path
    does not prove adapter application; the C API 1.0 client refuses it.
    Restoration is tracked in [owner #99](https://github.com/leehack/litert-lm-native/issues/99).
    `setLoraSource`, `removeLoraSource` and `clearLoras` throw
    `LlamaUnsupportedException`.
  - LiteRT-LM on web: no LoRA. Any `ModelParams.loras` entry fails the load and
    the runtime calls throw `LlamaUnsupportedException`.
- Do not catch and ignore `LlamaUnsupportedException` from LoRA calls; it means
  the adapter is not applied. If output looks unchanged, confirm the model runs
  on a compatible llama.cpp model (`engine.getBackendName()`).

## Examples

Train and convert an adapter (external tooling, not part of llamadart):

```python
# Hugging Face PEFT, run in a Python training environment.
from peft import LoraConfig, get_peft_model
from transformers import AutoModelForCausalLM

base = AutoModelForCausalLM.from_pretrained("Qwen/Qwen2.5-0.5B-Instruct")
model = get_peft_model(
    base,
    LoraConfig(r=16, lora_alpha=32, target_modules=["q_proj", "v_proj"],
               task_type="CAUSAL_LM"),
)
# ... train with your trainer of choice ...
model.save_pretrained("lora-adapter-output")
```

```bash
# llama.cpp conversion: HF PEFT adapter directory -> GGUF adapter.
git clone https://github.com/ggml-org/llama.cpp
pip install -r llama.cpp/requirements.txt
python llama.cpp/convert_lora_to_gguf.py lora-adapter-output \
  --base path/to/Qwen2.5-0.5B-Instruct \
  --outfile my_adapter.gguf --outtype f16
# Try it with the example CLI (same base model by default):
cd example/basic_app && dart run bin/llamadart_basic_example.dart \
  --lora ../../my_adapter.gguf
```

Load stacked adapters with a GGUF model, then rescale and remove them; a
reload applies `ModelParams.loras` again:

```dart
import 'package:llamadart/llamadart.dart';

final ModelSource style = ModelSource.path('/models/lora/style.gguf');
final ModelSource domain = ModelSource.parse(
  'hf://owner/repo/domain-lora.gguf',
);

Future<void> main() async {
  final LlamaEngine engine = LlamaEngine(LlamaBackend());
  final ModelParams withAdapters = ModelParams(
    loras: [
      LoraAdapterConfig.source(style, scale: 0.35),
      LoraAdapterConfig.source(domain, scale: 0.7),
    ],
  );
  final LlamaModel base = LlamaModel(
    ModelSource.path('/models/base-model.gguf'),
  );
  try {
    await engine.setModel(base, params: withAdapters);

    await engine.setLoraSource(domain, scale: 0.4);
    await engine.removeLoraSource(style);
    await engine.clearLoras();

    // setModel replaces the loaded model and applies ModelParams.loras again.
    await engine.setModel(base, params: withAdapters);
  } on LlamaUnsupportedException catch (error) {
    print('LoRA not available here: ${error.message}');
  } finally {
    await engine.dispose();
  }
}
```

Native LiteRT-LM: one default-scale adapter, only at load:

```dart
import 'package:llamadart/llamadart.dart';

Future<void> loadLiteRtLmWithAdapter(LlamaEngine engine) {
  return engine.setModel(
    LlamaModel(ModelSource.path('/models/gemma.litertlm')),
    params: ModelParams(
      loras: [
        LoraAdapterConfig.source(
          ModelSource.path('/models/gemma-text-adapter.bin'),
        ),
      ],
    ),
  );
}
```

## More

- LoRA adapters: https://llamadart.leehack.com/docs/guides/lora-adapters
- Backend selection: https://llamadart.leehack.com/docs/guides/backend-selection
- Model lifecycle: https://llamadart.leehack.com/docs/guides/model-lifecycle
- WebGPU bridge: https://llamadart.leehack.com/docs/platforms/webgpu-bridge
