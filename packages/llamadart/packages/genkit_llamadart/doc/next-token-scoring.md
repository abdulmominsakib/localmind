# Next-token scoring

Use scoring when you need the probability of a particular next token or the
most likely tokens after a raw prompt. It evaluates one distribution without
generating an answer. Temperature, penalties, grammar and other generation
settings do not affect these probabilities.

Each model exposes a typed custom Genkit action through `plugin.scorer(name)`.
For a prepared model:

```dart
import 'package:genkit_llamadart/genkit_llamadart.dart';

Future<void> score(LlamaPreparedModel prepared) async {
  final result = await prepared.plugin.scorer(prepared.definition.name)(
    LlamaDartScoringRequest(prompt: 'Once upon a time', topK: 5),
  );
  for (final token in result.top) {
    print('${token.token}: ${token.text} (${token.probability})');
  }
}
```

Actions register as `/next-token-scorer/llamadart/<model-name>` when the plugin
initializes in Genkit. The custom action can be called from a typed flow and
discovered through reflection. Registration/listing remains lazy; the first
scoring call loads the model. It is separate from `ai.generate()` and ordinary
Genkit model responses.

## Prompt and candidate semantics

The prompt is raw text, with explicit tokenizer special-token text interpreted
by llamadart. No chat template, system message, tools or media are added. For
instruction models, supply the model's correct formatted prompt yourself.
The example above measures raw continuation probabilities, not a chat answer.

Pass `candidates` containing vocabulary token IDs, a positive `topK`, or both.
Use `prepared.tokenize(text)` or `plugin.tokenize(name, text)` to obtain IDs;
text can tokenize to several IDs, and this operation scores each ID as the
**immediate next token**, not the probability of a multi-token string.
Candidate order and duplicates are preserved. `top` is ordered from most to
least probable. `promptTokens` reports the backend's evaluated prompt length.

Each entry has `token`, immutable raw `bytes`, natural-log `logprob`, decoded
`text`, and `probability = exp(logprob)`. One token may contain only part of a
UTF-8 character; use raw bytes when combining tokens. JSON output contains
`candidates`, `top` and `promptTokens`; token entries contain `token`, `bytes`
and `logprob`. This is not per-token log probabilities for a generated answer.

Empty prompts, negative/oversized token IDs or counts, requests asking for no
scores, fractional JSON integers, explicit nulls and unknown JSON keys fail with
`INVALID_ARGUMENT`. Out-of-vocabulary IDs/counts are rejected by the backend
before prompt evaluation. Nonfinite or malformed runtime scores fail with
`DATA_LOSS`, rather than escaping as unusable JSON.

## Runtime support and lifecycle

Native llama.cpp decoder models support scoring. WebGPU requires scoring-capable
bridge assets (`v0.1.52+`); LiteRT-LM and older bridges are unsupported. Every
request checks live capabilities. A backend reporting no scoring support fails
with `UNIMPLEMENTED`; unverified custom runtimes or unavailable models fail with
`FAILED_PRECONDITION`. Inspect runtime support with `prepared.inspect()`.
Native CPU is qualified by the real-model suite; browser adapter tests verify
routing/guards with custom runtimes, not actual WebGPU model execution.

Scoring uses the same model queue as chat, embeddings and inspection. It cannot
mutate a model while another request runs. `reusePromptPrefix` defaults to true;
set false to request a fresh prompt evaluation. Reuse is an optimization on the
shared model context, not dedicated user/session state.

An action accepts Genkit's cancellation token. Cancellation before queue entry
prevents loading/evaluation; cancellation after evaluation starts waits for the
backend to finish and discards its result. Native scoring is not interruptible.
Plugin disposal drains accepted requests, then releases the model; later calls
fail. Unknown model names fail with `StateError`.

Custom runtimes implement `LlamaRuntimeScoringProvider` alongside
`LlamaRuntimeCapabilityProvider`. Report `supportsNextTokenScoring` only when
the loaded model can score. Preserve the upstream vocabulary checks, candidate
ordering and raw-logit semantics; do not simulate scores with text generation.
Existing runtimes do not need to implement the optional interface.

## Telemetry

Genkit instrumentation wraps the custom action and follows its request zone
through queued work. Configure a provider in the application using the
[observability guide](observability.md); without one, tracing is a no-op.
Content capture can include prompts and token bytes, so configure it explicitly.
Model-generation token usage, TTFT and the existing model timing recipe do not
apply to this custom action. Core engine generation observers do not emit a
scoring operation; use the Genkit action span for scoring duration/errors.
