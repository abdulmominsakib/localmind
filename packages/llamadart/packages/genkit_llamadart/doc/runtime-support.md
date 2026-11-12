# Runtime support

## Feature permissions

Use `LlamaModelDefinition` to permit features for each registered model:

- `supportsEmbeddings`: register an embedder when the model should expose one
- `supportsTools`: permit tool requests and tool history
- `supportsConstrainedOutput`: permit grammar-constrained JSON output

These flags default to `true` for backward compatibility. Setting a flag to
`false` rejects that feature with `FAILED_PRECONDITION` before loading the model.
An enabled flag is permission to use a feature when the runtime supports it.

Discovery stays lazy: `plugin.init()` and `plugin.list()` never load models.
Standard `model.supports` booleans start at `false` because support is not yet
confirmed. Metadata includes `llamadartCapabilities` with:

- `state`: `unloaded`, `unverified` (a pending/failed probe or no provider), or `verified`
- `ready`: whether the last checked runtime reports a loaded, usable model
- `generation`: `penalty`, `minP`, `presencePenalty`, `thinkingBudget`, `streamBatching`,
  `promptPrefixControl`, and `speculativeDecodingStrategies` from the last ready
  snapshot; false flags and an empty strategy list before verification
- `embedding`: the last probed `text`, `image` and `audio` embedding modalities;
  chat vision/audio support is never substituted for media embedding probes
- `declared`: the definition's `tools`, `constrained`, and `embeddings` permissions

After initialization, the plugin reads `LlamaEngine.capabilities` before every
queued request and updates registered and cached discovery metadata, preserving
labels, schemas and other model annotations. These snapshots describe the last
check; every request checks again. A failed probe clears previous support and
blocks inference. Disposing the plugin clears its
support metadata. Registering an action does not guarantee that its runtime
supports the requested feature.

Inference controls are checked before generation. Nondefault batching and
nonzero presence penalties require explicit support; thinking budgets and every
selected speculative strategy must be confirmed. See [generation settings](usage.md#generation-settings)
for incompatible combinations and JSON configuration.

Tools, strict JSON, embeddings, system messages, conversation history, images,
and audio are checked before generation or embedding. Confirmed unsupported
features fail with `UNIMPLEMENTED`; an unready runtime fails with
`FAILED_PRECONDITION`. Through `ai.generate()`, failures can become a response
with `finishReason: failed`, so inspect the result's error.

| Runtime capability snapshot | Adapter behavior |
| --- | --- |
| llama.cpp GGUF | Uses loaded capabilities for tools, history, grammar, embeddings, and projector media. A projector path alone does not confirm media support. |
| Native LiteRT-LM | Preserves chat and tools when supported; rejects strict JSON and embeddings when unsupported. Built-in encoders need no projector. Media declarations from a custom runtime older than LiteRT-LM v0.18.0 can under-report encoders, so native media requests retain llamadart's best-effort runtime validation; unconfirmed media is not advertised. |
| LiteRT-LM Web | A snapshot that reports latest-text-only chat rejects history, system messages, tools, and media instead of silently dropping them. This does not establish Genkit Dart browser compatibility. |

Backend support does not prove model quality or template behavior. For example,
`systemRole` means the runtime delivers system messages to the chat template;
a model may still interpret them differently. Tool-choice constraints and
model-specific embedding eligibility remain validated by llamadart.
`constrainedWithTools` is true only for verified native llama.cpp runtimes with
tools, structured output and grammar support. Combined requests require an eager
generic JSON-envelope template and one call per turn; see [usage](usage.md).

Use `modelInfo` to customize labels, versions, configuration schema, stage, or
additional support metadata. Custom support keys are preserved; standard keys
are derived from permissions and verified capabilities and cannot be overridden.

Custom runtimes implement the exported `LlamaDartRuntime` interface and are
supplied through `LlamaDartPlugin(runtimeFactory: ...)`. They can also implement
`LlamaRuntimeCapabilityProvider` and return a fresh `LlamaEngineCapabilities` snapshot after initialization. Default runtimes
already do this. Existing implementations without the optional interface still
compile and can serve single-turn text; advanced requests fail with
`FAILED_PRECONDITION` and a provider diagnostic. This tightens advanced custom
runtime behavior to prevent unverified support claims.

## Limitations

- Genkit history retains streamed/final reasoning, but incoming `ReasoningPart`
  values are omitted from the next model prompt. Text and tool calls/results
  remain. This is an explicit adapter policy, not a universal model requirement:
  [Qwen3.5's template](https://huggingface.co/Qwen/Qwen3.5-0.8B/blob/2fc06364715b967f1860aea9cf38778875588b17/chat_template.jinja)
  treats reasoning differently before and after the latest user query. Reasoning
  replay during a tool continuation is not qualified here; use the documented
  nonthinking tool flow when that distinction matters.
- Resource/data parts need explicit [application normalization](resource-input.md).
  Arbitrary custom parts, PDFs and video are not accepted simply because
  Genkit's generic schema can represent them. Image/audio embeddings require
  embedding-specific capability probes; see [embeddings](usage.md#multimodal-embeddings).
- Genkit sessions do not own the plugin's model runtime. Load-time LoRA through
  `ModelParams.loras` is available; live source-based changes use
  [dedicated native owners](runtime-owners.md#live-lora), outside the shared
  registry. KV-state save/restore remains deferred under the
  [isolation design](runtime-isolation-design.md).
- model paths are local filesystem paths after `ModelSource` resolution
- image/audio embeddings require a compatible embedding model and processors;
  native LiteRT-LM uses an explicit CPU embedding engine with encoded PNG/JPEG
  and WAV bytes rather than unresolved paths/URLs, while Web LiteRT-LM
  and conversation engines reject embedding requests
- LiteRT-LM `.litertlm` bundles can be used for chat and tool-call flows, but
  constrained JSON output currently requires a backend with grammar constraints;
  set `supportsConstrainedOutput: false` for `.litertlm` model definitions.
- constrained output with active tools requires native llama.cpp, one call per
  turn and `enableThinking: false`; WebGPU and LiteRT-LM reject this combination
- [Rich tool input schemas](tool-input-schemas.md) require grammar support and
  a supported template; simple schemas retain best-effort tool calling.
- some models may need prompt tuning for reliable tool arguments
- multimodal requests require a compatible model and runtime; llama.cpp also
  requires a compatible projector, while native LiteRT-LM can use built-in encoders
- direct HTTP(S) image URLs are currently consumed by WebGPU. Native image
  and audio downloads require an explicit application-owned
  [media resolver](usage.md#resolving-remote-input-on-native-platforms); local
  paths and `data:` bytes remain available on compatible multimodal backends

## Inspection and raw-text tokens

Each model also registers a custom [next-token scoring action](next-token-scoring.md)
under `next-token-scorer`, separately from the model and embedder actions.
`llamadartScoring` metadata records the last checked runtime capability (`state`
and `supported`); registration does not load or verify a model. Scoring additionally
requires the optional `LlamaRuntimeScoringProvider` implementation. Native llama.cpp
decoder models and scoring-capable WebGPU bridges can serve it; LiteRT-LM cannot.

Use [model inspection](model-inspection.md) for explicit loaded-runtime
capabilities, context capacity and tokenizer access. Discovery does
not load a model; inspection and raw token helpers do. Custom runtimes may opt
into `LlamaRuntimeInspectionProvider` without changing the base runtime API.
Keep backend capability labels free of paths and credentials; inspection
publishes only recognized backend labels and a neutral unsupported reason.

Dedicated [batch speech/image models](media-models.md) use `LlamaDartMediaPlugin`
and separate typed engines. Their listed metadata describes accepted shapes;
readiness is checked from the engine before each operation. This preview is native only.

Dedicated native raw-prompt contexts are available through the opt-in
[application-owned runtime pool](runtime-owners.md). Web and LiteRT-LM are
unsupported for this helper; the ordinary plugin support above is unchanged.

The pool's opt-in [raw-prompt caches](prompt-caches.md) require default native
state/scoring support and exclude projectors, LoRA and custom factories.
[Experimental text sessions](bidi-sessions.md) use a separate `bidiModel`
registration and native context per session. Neither feature adds shared-plugin
state mutation, chat checkpoint persistence or real-time audio support.
