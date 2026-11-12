# Decision flows with Laya

Use a normal Genkit flow when you want typed decisions rather than generated
text. The experimental `llamadart.DecisionEngine` runs a bidirectional encoder
GGUF and a separate Laya decision head. Genkit has no standard decision-model
provider, so this is an application recipe using `defineFlow`, not an
`ai.generate()` model or a new plugin API.

The [runnable example](../example/genkit_llamadart_decision_example.dart) asks
three fixed questions about a support ticket and publishes their complete Laya
JSON result as the flow output. The [flow definition](../example/decision/triage_flow.dart)
includes input/output schemas and checks finite numbers and the response shape
before returning it. Invalid results fail with a neutral `DATA_LOSS` error.
Keep questions and their response schema in application code: their labels,
score levels and permitted actions depend on your application. The existing
Genkit flow API handles registration and tracing; a plugin wrapper would not
remove these application-specific decisions.

```bash
dart pub get
dart run example/genkit_llamadart_decision_example.dart \
  'We were billed twice. Please refund the duplicate.'
```

The first run downloads a 272 MB Laya Q4_K_M encoder and 106 MB head from
`fr0stbit3/laya-gguf`, pinned to revision
`ce2afdc0a8766af56a29a22dcf4a781e1f5c7d3c`; later runs reuse the cache.
Set `GENKIT_DECISION_ENCODER` and `GENKIT_DECISION_HEAD` to local paths to run
offline with previously downloaded files. Keep the encoder and head compatible.
Loading validates the head's config and dimensions; malformed or mismatched
files raise llamadart's typed exceptions instead of producing a decision.

## Reading the result

The flow accepts a nonblank ticket string. Its fixed question ids are:

| Id | Laya/Jev task | Answer |
| --- | --- | --- |
| `department` | `choice` | One of `billing`, `technical`, `sales`, `other`, plus probabilities for every label. |
| `urgency` | `score` | Expected level from 0 to 2; fractional values are meaningful. The ordered legend and all level probabilities remain present. |
| `refund` | `noul` | Probability from 0 to 1 that a refund is explicitly requested. |

The output keeps the upstream `{model, answers, usage}` shape, including
confidence and `action.act_probability`. Gate application actions on confidence
after evaluating your own data. Laya's action signal is not documented as
carrying usable information. Decisions generate no tokens:
`usage.output_tokens` is zero; input usage counts the encoded question sequences.

To change the questions, copy the flow into your application and update its
output schema in the same edit. It deliberately describes these three questions
rather than inventing a universal decision schema. Use llamadart's
`DecisionQuestion`, `DecisionKey` and `DecisionResult` types for internal logic;
`DecisionResult.toJson()` preserves the existing wire vocabulary. Inputs remain
subject to the encoder/head token limits and upstream truncation policy.

## Ownership, errors and support

Load once and reuse the engine. `DecisionEngine.load(DecisionModel(...))` owns
its encoder and head. The flow borrows that already-loaded decision engine; it
never reloads, replaces or disposes it. Stop accepting new flow requests, await
those requests, then call `decisions.dispose()` and `ai.shutdown()` in `finally`.
Upstream disposal drains active inference and is idempotent. For an encoder
shared with another head, `DecisionEngine.attach(encoder, head: source)` borrows
the encoder: dispose each decision engine before disposing the shared encoder.
Keep mutations/unloads outside active flow requests. The recipe relies on
llamadart's runtime serialization rather than adding a second engine queue.

Every call checks the loaded engine's decision capabilities. Blank input,
disposed engines, unsupported capabilities and unexpected result shapes fail
explicitly. Genkit cancellation is checked before and after inference; the
published decision API cannot interrupt an in-flight encoder pass. There are
no partial answers or streamed chunks. Inference and capability-probe errors map
to neutral Genkit diagnostics without retaining raw native errors or paths. The
upstream model label is the safe constant `laya-rl-agent`. Applications exposing
a flow over a network should provide authorization, input limits and telemetry
policy: Genkit traces can record the ticket and decision result. Startup loading
happens before Genkit is created and retains native CLI diagnostics; do not
forward those diagnostics to remote users.

This recipe is qualified on macOS arm64 with native llama.cpp on CPU using the
published `llamadart 0.11.1` API. Other native platforms and GPU execution are
unqualified here. Upstream also exposes decision support on compatible WebGPU
bridge assets, but this native CLI and Genkit browser route are not qualified.
LiteRT-LM and NPU execution are unsupported. No chat template, tool calling or
generated-text quality is inferred from decision support.

## Real-model qualification

The opt-in `decision-model` test verifies both files before loading:

| File | SHA-256 |
| --- | --- |
| `laya-Q4_K_M.gguf` | `37c331ded9b71542541692c877e60452f873f430ef405c5158257e130bd890d7` |
| `laya-head.safetensors` | `c1ec428e034614c9373ebcf3fdc255d8eafcc04be9b2f0c2ffeef92bb1361b83` |

```bash
GENKIT_DECISION_ENCODER=/path/to/laya-Q4_K_M.gguf \
GENKIT_DECISION_HEAD=/path/to/laya-head.safetensors \
dart test test/integration/genkit/decision/real_model_decision_test.dart -j 1
```

The test executes the actual Genkit flow for all three tasks, checks complete
probabilities and usage, and exercises blank/wrong-type input, upstream NUL
validation, cancellation and use after disposal. A second real test verifies
borrowed encoder ownership, malformed and shape-mismatched head recovery,
concurrent requests and rejection after encoder disposal. Both skip before file
access or downloads when either path is absent. This is bounded routing and
lifecycle qualification, not an accuracy benchmark. No model weights are shipped.
