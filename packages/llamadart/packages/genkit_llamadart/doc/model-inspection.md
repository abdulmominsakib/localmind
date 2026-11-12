# Model inspection and raw-text token counts

Inspect a prepared model before inference:

```dart
import 'package:genkit_llamadart/genkit_llamadart.dart';

Future<void> inspectModel(LlamaPreparedModel prepared) async {
  final loaded = await prepared.inspect();
  print('Context capacity: ${loaded.contextSize ?? 'unavailable'}');
  print('Backend: ${loaded.capabilities?.backendName ?? 'unavailable'}');
  print('Raw tokens: ${await prepared.countTokens('Hello.')}');
  final ids = await prepared.tokenize('Hello.', addSpecial: true);
  print(ids);
}
```

`inspect()`, `countTokens()` and `tokenize()` explicitly load the model if needed,
without generating text. They serialize with generation and embeddings on the
same plugin queue. A later `dispose()` waits for accepted operations; requests
after disposal fail. Preparing/registering a model and listing Genkit actions
remain lazy. Loading can be expensive even when no inference runs.

For a directly constructed `LlamaDartPlugin`, use
`plugin.inspectModel(modelName)`, `plugin.countTokens(modelName, text)` and
`plugin.tokenize(modelName, text, addSpecial: true)`.

## What the snapshot means

- `contextSize` is actual loaded capacity in tokens when measurable. Native
  llama.cpp uses the active context report; an unavailable/nonpositive value
  becomes null. The default Web and LiteRT-LM runtimes return null because core helpers
  can fall back to requested settings or model metadata, rather than an actual
  session measurement.
- `capabilities` contains the loaded runtime's typed flags and supported
  speculative strategies, including sampling, grammar, tools and media support.
  It can be null for custom runtimes without capability probing. Strategy sets
  are immutable; later runtime changes do not mutate an earlier snapshot.
- `embeddingCapabilities` reports `text`, `image` and `audio` for embeddings,
  separately from chat vision/audio support. It is null for custom runtimes
  without `LlamaRuntimeEmbeddingProvider`. Diagnostic reasons are omitted.
- Backend names are restricted to recognized CPU/GPU, WebGPU/WASM and LiteRT-LM
  labels; unknown labels remain null. Arbitrary failure text, paths and model
  metadata are excluded.

Runtime capability support does not guarantee model quality or every combination
of settings. Definition permissions such as `supportsTools` can restrict the
adapter further; the snapshot reports the runtime, not those permissions. Read [runtime support](runtime-support.md) for platform conditions.

GPU layer counts, device memory and performance counters are outside this API.
The core GPU-layer helper can report configured offload settings rather than
measured layers, so the adapter does not present that value as a measurement.

## Raw tokens are not conversation budgets

`countTokens(text)` is the length of `tokenize(text)` with `addSpecial: false`.
Tokenizer special tokens are not added unless requested in `tokenize`; explicit
special-token text is still interpreted according to the model tokenizer.
The returned token IDs are immutable and depend on the loaded model's tokenizer.
No inference, chat-template application or tool execution is performed.

These helpers do not estimate formatted chat prompts, tool schemas, image/audio
tokens, or remaining context after a conversation. Do not compare a raw prompt
count with `contextSize` as a complete admission check. A reliable chat budget
must apply the exact generation template, tools and media handling; that estimate
is outside this API. Use [request usage and timings](observability.md) to observe
actual inference; inspection does not add duplicate token telemetry.

## Custom runtimes and unsupported operations

Existing custom `LlamaDartRuntime` implementations remain valid. Implement the
optional `LlamaRuntimeInspectionProvider` to provide actual nullable context
capacity and raw tokenization. Methods run after initialization under the
existing model queue. Do not return requested settings or metadata limits as
actual context, and keep capability backend labels free of credentials/paths.

A custom runtime without the interface still returns an inspection snapshot
with unknown measurements, but tokenization/counting throws
`LlamaUnsupportedException`. A provider whose backend lacks a tokenizer must
throw that typed error too. Default LiteRT-LM Web tokenization reports unsupported. Native LiteRT-LM
and GGUF tokenizer availability depend on the active runtime/assets.
Loading and capability-probe failures propagate. Unknown model names and calls
after plugin disposal fail with `StateError`.
