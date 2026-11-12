# Decision Engine Design

`DecisionEngine` runs Laya-style decision models: a bidirectional encoder
(ModernBERT GGUF, run by llama.cpp) plus a small decision head (safetensors),
answering typed questions about a state in one non-autoregressive pass. The
request and response shapes follow Laya's `system_one` and TypeSafe's Jev API,
so most questions written for Laya carry over unchanged; the guide's
[Laya wire format](../website/docs/guides/decision-models.md#laya-wire-format)
and [Known limits](../website/docs/guides/decision-models.md#known-limits)
sections list the exceptions.

## Glossary

The public API keeps the names of TypeSafe's
[Jev API](https://docs.typesafe.ai/) and Laya's
[`system_one`](https://huggingface.co/convaiinnovations/laya) format:

| Term | Plain meaning | In the API |
| --- | --- | --- |
| System One | Answer typed questions about an input in one fast encoder pass per question, without generating text | `systemOne`, `systemOneBatch` |
| state | The text or JSON being judged | `DecisionRequest.state`, `state:` |
| instructions | The question text | `DecisionQuestion.instructions` |
| criteria | A question's options: labels with descriptions, ordered levels, or descriptions of yes and no | `ChoiceQuestion.criteria`, `ScoreQuestion.levels`, `NoulQuestion.whenTrue`/`whenFalse` |
| choice | Pick one option | `ChoiceQuestion`, `ChoiceAnswer.choice` |
| score | Rate on ordered levels; the answer is the expected level, so it can fall between levels | `ScoreQuestion`, `ScoreAnswer.score` |
| legend | A score question's level descriptions, keyed `'0'`, `'1'`, ... | `ScoreAnswer.legend` |
| noul | Yes/no; the answer is the probability that the statement is true | `NoulQuestion`, `NoulAnswer.noul` |
| confidence | How sure the model is of an answer, from 0 to 1 | `DecisionAnswer.confidence` |
| act probability | Laya's action signal, which Laya documents as carrying no usable signal yet; gate on confidence instead | `DecisionAnswer.actProbability` |
| head | The small trained network on top of the encoder that turns its output into answers | `DecisionModel.head` |

Reference implementation: `laya` 0.3.5 on PyPI, checkpoint
`convaiinnovations/laya` at `1c5edc17a7acd8701df6fc341c0d179f1c62c982`
(Apache-2.0). Parity with it is the acceptance bar.

## Model assets

| File | Source | Notes |
| --- | --- | --- |
| Backbone GGUF | `fr0stbit3/laya-gguf@ce2afdc0a8766af56a29a22dcf4a781e1f5c7d3c`, `laya-Q8_0.gguf` (421 MB) or `laya-F16.gguf` (791 MB) | `modern-bert` architecture, 1024 hidden |
| Head | same repo, `laya-head.safetensors` (106 MB, F32) | 36 tensors under the PyTorch names; `__metadata__["laya.config"]` holds `rl_agent_config.json` |
| Official checkpoint | `convaiinnovations/laya/model.safetensors` + `rl_agent_config.json` | also accepted as a head file: `encoder.*` tensors are ignored, config comes from `DecisionModel.config` |

Measured error and speed per backbone, head file and device are under
[Measured](#measured).

## Public API

`lib/llamadart.dart` exports `DecisionEngine`, `DecisionModel`,
`DecisionModelParams`, `DecisionCapabilities` and `DecisionModelInfo`; the questions (`DecisionQuestion` with `ChoiceQuestion`,
`ScoreQuestion` and `NoulQuestion`, `DecisionQuestionType` and
`DecisionRequest`); the answers (`DecisionAnswer` with `ChoiceAnswer`,
`ScoreAnswer` and `NoulAnswer`, `DecisionUsage` and `DecisionResult`); and the
typed keys (`DecisionKey` with `ChoiceKey`, `ScoreKey` and `NoulKey`,
`ChoiceOf`, and the `DecisionResultKeys.answerOf` extension). Errors use
`LlamaDecisionException`. The
[Decision Models guide](../website/docs/guides/decision-models.md) documents
their use.

Loading follows the shared engine pattern
([#835](https://github.com/leehack/llamadart/issues/835)):

- `DecisionEngine.load(DecisionModel(encoder:, head:, config:), params:,
  download:, onProgress:, store:)` creates a `LlamaEngine` (backend from
  `LlamaBackend()`, resolver and download manager from `store`), resolves
  every file through `resolveModelSourceFiles` before loading anything, loads
  the encoder with `DecisionModelParams.encoderModelParams` (context 512, the
  device and threads), and attaches the head. It owns the engine: a failure
  disposes it, and `dispose()` frees the head and then the engine. Settings it
  cannot apply (`ComputeDevice.npu`, negative threads, `sha256` over several
  files, a `.litertlm` encoder) throw before the engine is created;
  `ComputeDevice.gpu` checks `isGpuSupported` before any download.
- `DecisionEngine.attach(engine, head:, config:, download:, onProgress:)`
  probes the loaded model first, resolves the files through the engine's
  `modelResolver` and `modelDownloadManager`, then loads the head. It borrows
  the engine: `dispose()` frees only the head.
- Both share `resolveModelSourceFiles` with `ImageGenerationEngine.load`, so a
  single local or remote file is checked against `sha256`, and `bearerToken`
  or `headers` with remote files on more than one origin throw
  `LlamaArgumentException` before the next host is contacted.
- On URL-loading backends (Web), files are not downloaded: a local target
  (`ModelSource.path`) passes through as a document-relative URL and a remote
  one as its resolved URL, and `rejectUnsupportedUrlBackendOptions` rejects
  `download` options the browser fetch cannot apply, as for projectors.
- `capabilities` is an instance `Future<DecisionCapabilities>` with
  `isSupported`, `unsupportedReason`, `backendName` and `runtime`, the shape
  the shared `EngineCapabilities` of
  [#851](https://github.com/leehack/llamadart/issues/851) will take; it turns
  unsupported after `dispose` or a model unload. `capabilitiesFor(engine)`
  stays as the pre-attach probe.
- `load(engine, headPath:, configPath:)` with `String` paths is removed;
  `attach(engine, head: ModelSource.path(headPath))` replaces it.

## Architecture

```text
DecisionEngine (core, pure Dart)
  question -> texts -> engine.tokenize -> sequence ids + marker positions
  LlamaEngineBackendHooks (backend.dart): loadDecisionHeadBackend / runDecisionBackend / freeDecisionHeadBackend
    BackendDecision (backend.dart, web-safe value types)
      NativeAutoBackend -> NativeLlamaBackend -> worker isolate -> LlamaCppService
        private encoder llama_context + safetensors head + ggml head graph
      WebAutoBackend -> WebGpuLlamaBackend -> WebGpuDecisionHeads -> llama-web-bridge
        bridge decision API 1: private encoder context + head in the WASM core
  raw marker logits + raw act logits -> decoder (core) -> DecisionResult
```

Why the split: sequence building and decoding stay in shared Dart, so the web
path only has to provide "token ids in, raw logits out". The worker never sends
hidden states across the isolate boundary; only logits cross it.

### Core (`lib/src/core/decision/`)

| File | Contents |
| --- | --- |
| `python_json.dart` | `json.dumps` byte parity: `, `/`: ` separators, Python float `repr`, `NaN`/`Infinity`, `ensure_ascii` |
| `decision_question.dart` | question types, `DecisionRequest`, JSON conversion, validation |
| `decision_result.dart` | answer types, `DecisionUsage`, `DecisionResult` |
| `decision_key.dart` | typed keys, `ChoiceOf`, the `answerOf` extension |
| `decision_sequence.dart` | option rendering, tokenizer input texts, sequence assembly |
| `decision_decoder.dart` | temperature selection and clamping, softmax, confidence, act features, answer decoding |
| `decision_model.dart` | `DecisionModel`: encoder, head and config sources |
| `decision_model_params.dart` | `DecisionModelParams` and the encoder's `ModelParams` |
| `decision_engine.dart` | facade with `load`/`attach`, `DecisionCapabilities` and `DecisionModelInfo` |

The core must not import `dart:io`/`dart:ffi`, directly or transitively.

### Backend contract (`lib/src/backends/backend.dart`)

```dart
abstract class BackendDecision {
  Future<BackendDecisionCapabilities> decisionCapabilities(int modelHandle);
  Future<BackendDecisionHeadInfo> decisionHeadLoad(
    int modelHandle, String headPath, {String? configPath});
  Future<List<BackendDecisionOutput>> decisionRun(
    int headHandle, List<BackendDecisionSequence> sequences);
  Future<void> decisionHeadFree(int headHandle);
}
```

- `BackendDecisionHeadInfo`: `handle`, `hiddenSize`, `clsToken`, `sepToken`,
  `maskToken`, `maskText`, `configJson` (the Laya config text; the core reads
  and validates `max_len`, `head_max_len`, `head_layers` and temperatures from
  it) and `deviceName`.
- `BackendDecisionSequence`: `tokens`, `markers` (`Int32List`) and
  `questionType` (`DecisionQuestionType`), one per question.
- `BackendDecisionOutput`: per sequence, raw marker `logits` and raw
  `actLogits` (`Float32List`).

`NativeAutoBackend` and `WebAutoBackend` implement and forward it; their
LiteRT-LM delegates report unsupported.

### Engine hooks (`lib/src/core/engine/engine.dart`)

Members of the `LlamaEngineBackendHooks` extension, exported from
`package:llamadart/backend.dart`, like the TTS trio. Being extension members,
a `LlamaEngine` subclass cannot override them; tests fake `BackendDecision`. The capabilities hook checks `is! BackendDecision` before readiness, so
a backend without the contract reports a stable reason without a model.

Backend handles are not unique over an engine's life: the worker numbers
handles from 1, and a new worker starts when a GGUF load follows a
`.litertlm` load (which replaces the llama.cpp delegate even if it fails), so
the first head after a restart gets the previous head's number. `loadDecisionHeadBackend` therefore returns the
head with an engine handle from a counter that never resets, mapped to the
backend handle. `_unloadModel` forgets every mapping. A
run with an unmapped engine handle throws `LlamaStateException` ("load the
DecisionEngine again") and a free does nothing, so a stale `DecisionEngine`
can reach neither a later head nor its backend handle. No engine lease: the
head uses its own llama context, and the worker serializes native work.

`DecisionEngine` also checks, before tokenizing, after the capability probe
and after `attach` resolves its files, that the engine is ready and its unload
epoch (`modelUnloadEpoch`, which `_unloadModel` bumps as each attempt starts,
unless nothing is loaded) is the one the load started with; a model loaded
later fails the check even under a reused backend handle.
If the model is unloaded while a call or a load is in flight, the failure it
causes, such as `LlamaContextException` from tokenization, is rethrown as
`LlamaStateException`.

### Native (`lib/src/backends/llama_cpp/`)

- Worker messages `DecisionCapabilitiesRequest`, `DecisionHeadLoadRequest`,
  `DecisionRunRequest`, `DecisionHeadFreeRequest`, handled synchronously. Every
  request sent before `DisposeRequest` gets a reply; the worker drops requests
  that arrive after it, so the client's `decisionHeadFree` sends nothing once
  disposal has started. Errors reuse the existing `WorkerErrorKind`s: a model
  that `decisionModelUnsupportedReason` rejects, and missing ggml symbols, are
  `unsupported`; an unreadable or malformed head file or
  config, or a head that does not fit the encoder, is `model`; an encoder
  context that cannot be created or fails its checks is `context`; an invalid
  sequence or a failed encoder or head pass is `inference`; an unknown model or
  head handle is `state`.
- `safetensors.dart`: header parse with bounds checks; reads only the needed
  byte ranges through `RandomAccessFile`, into a Dart list or a caller's
  buffer such as native memory; F32, F16 and BF16 convert to F32.
- `decision_head.dart`: the type embedding and act MLP read into Dart, and
  every other head tensor read from the file into a staging buffer just before
  its upload into one backend buffer (`ggml_backend_alloc_ctx_tensors`), so the
  head file stays open until the runtime exists; the head graph through
  `ggml_backend_sched`, with the last layer's queries, attention output and
  feed-forward computed only for the CLS and marker rows (keys and values use
  every token); and the act MLP in Dart.
- Service state: `Map<int, _DecisionHead>` keyed by `_getHandle()`, holding the
  model handle, a private `llama_context` (n_ctx = n_batch = n_ubatch =
  `max_len`, `n_seq_max` 1, `embeddings` true, pooling NONE, threads and offload
  knobs from the model's load params), backends, sched, weights, and the
  encoder call (`llama_encode` plus `llama_get_embeddings`; unit tests
  substitute it because the null test context would abort). Kept out of
  `_contexts` so generate, embed and state persistence cannot reach it.
  `freeModel` frees the model's heads before `llama_model_free`; `dispose` frees
  all heads first.
- Teardown order per head: sched synchronize, sched free, weights buffer free,
  `ggml_free`, backends free, then `llama_free` on the private context. A live
  Metal buffer at process exit trips `ggml_metal_rsets_free`'s assert. The
  sched, weights buffer, backends and context are also held in
  `IsolateShutdownReleases`, which frees them if the worker isolate shuts down
  first; each free releases its hold first. With a runtime that has exit
  teardown (`llamadart-native` `v0.5.0-1` and later) they are tracked with
  `llama_dart_exit_track` in the matching stage and freed through
  `llama_dart_exit_free`, and the graph is computed through
  `llama_dart_ggml_backend_sched_graph_compute`, so exit teardown frees a
  head that is still loaded (`doc/llama_cpp_exit_teardown.md`).

Head device: CPU when the load's backend is CPU (`_modelBackendNames`), its
requested GPU layer count resolves to zero, or single-device placement
(`splitMode: ModelSplitMode.none` with a negative `mainGpu`) selects no GPU,
with `op_offload` false. Otherwise
a GPU or iGPU device whose registry maps to that backend (`mainGpu` picks
among several; in other split modes a negative or out-of-range index picks
the first matching device; a nonnegative out-of-range index in single-device
mode fails the model load before head loading; none matching means CPU;
`decisionHeadDeviceIndex` decides), with the
CPU backend last in the sched (required by `ggml_backend_sched_new`).
With single-device placement selecting no GPU, the model reports CPU and zero
GPU layers, and `DecisionModelInfo.deviceName` reports `CPU` for the head. Never
`ggml_backend_init_best`, which would start a GPU backend in explicit CPU
mode.

CPU threads: `llama_encode` uses the private context's `n_threads_batch` for
every sequence of more than one token, and the head passes the same count
(`llama_n_threads_batch`) to the CPU registry's `ggml_backend_set_n_threads`.
So `ModelParams.numberOfThreadsBatch` sets the CPU threads of both, and
`resolveCpuThreads` picks 4, or the host's core count when lower, when it is 0.
`numberOfThreads` only reaches
one-token encoder passes, which `DecisionEngine` never builds.

Load-time checks, each failing with a typed exception and each decided by a
static helper that unit tests cover:

- `decisionModelUnsupportedReason` (also the capability probe):
  `general.architecture` is `modern-bert`; the CLS (`llama_vocab_bos`), SEP and
  MASK tokens are in the vocabulary; the MASK token has text; `n_embd_out` is 0
  or `n_embd`.
- `checkDecisionHeadFitsEncoder`: `n_ctx_train >= max_len`.
- `checkDecisionEncoderContext`: pooling is NONE; `n_ubatch >= max_len`.
- `DecisionHeadWeights.read`: every tensor is present with the exact shape
  implied by `hidden`, `head_layers` and the act rows, starting with
  `type_emb.weight`, whose error names the encoder's hidden size; `nhead =
  max(1, hidden ~/ 64)` divides `hidden`.

The run path rejects a sequence longer than `llama_n_ubatch` before
`llama_encode`, whose `GGML_ASSERT` would abort the process.
`validateDecisionSequences` checks every sequence before the first encoder
pass: 1 to `n_ubatch` tokens inside the vocabulary, and 1 to token-count
markers inside the sequence. The bridge core runs the same checks with the same
messages, plus a question type check that `DecisionQuestionType` always passes,
so both runtimes reject the same input; the marker-count bound comes from the
bridge, whose head graph sizes its buffers by marker count.

Windows: `llama.dll` exports no `ggml_*` graph symbols; they live in
`ggml-base.dll` (ops, graph, sched, buffers) and `ggml.dll` (registry). The head
calls ggml through a small function table that uses `@Native` twins with
`assetId: 'package:llamadart/ggml-base'`/`'package:llamadart/ggml'` on Windows
(precedent: `test/unit/backends/llama_cpp/native_precision_bindings_test.dart`)
and the generated bindings on other platforms. The bindings leave out
`ggml-alloc.h`, so `ggml_backend_alloc_ctx_tensors` has a hand-written `@Native`
on their default asset, `package:llamadart/llamadart`, there too. Generated
bindings are not edited.

### Web (`lib/src/backends/webgpu/`)

`WebGpuLlamaBackend` implements `BackendDecision` through `WebGpuDecisionHeads`
(`webgpu_decision.dart`), which calls the llama-web-bridge decision API:
`getDecisionCapabilities`, `loadDecisionHead`, `runDecision` and
`freeDecisionHead` (bridge `docs/api.md`, "Decision heads"). The bridge runs the
head on WebGPU when the model loaded with GPU layers and on the CPU otherwise,
and reports which as `deviceName`.

- Capability probe: a bridge object without all four methods reports
  unsupported with "Web decision models need llama-web-bridge assets v0.1.47+
  with the decision API (apiVersion 1)", from the
  `webGpuDecisionBridgeRequirement` constant. A capability or head response
  with an `apiVersion` other than 1 is unsupported too, and such a head is
  freed first. Bridge assets `v0.1.47+`, the default pin among them, have the
  API.
- Paths are URLs, resolved in Dart against `document.baseURI` before any
  fetch, so a page's `<base href>` applies to both in both bridge modes. The
  bridge fetches the head. It takes the config only as text, so the config
  is fetched in the page with `fetch`, before the head, and passed as
  `configJson`; with both a missing config and a bad head, Web reports the
  config where native reports the head. A failed fetch or an HTTP error is
  `LlamaModelException` "Cannot read the decision head config at <url>." with
  the status or error in `details`. The head and config URLs that messages
  and details show drop user info, query and fragment. Browser and bridge
  error text loses these parts of the head and config URLs, as written,
  JSON-escaped, percent-encoded or percent-decoded: the user info and
  password, as whole tokens of any length; the `?query` and `#fragment`,
  where they directly follow a non-space character; the query and each
  `&`-separated part that contain `=`, as whole tokens; and bare query
  values and the fragment of 10 or more characters, as whole tokens. A whole
  token has no ASCII letter or digit directly before or after it. Shorter
  bare values printed on their own stay. Other URLs it quotes lose user
  info, query and fragment on a best-effort basis.
- Handles: the backend numbers heads itself, never reusing a number, and maps
  each to the bridge instance and bridge handle that loaded it. `modelFree` and
  `dispose` dispose the bridge, and a model load on the same bridge frees every
  bridge head, so the backend forgets all heads at each. A run with a forgotten
  head, or with a head whose bridge is no longer active, throws
  `LlamaStateException` without calling the bridge; a free does nothing.
- Errors: the bridge rejects with plain `Error`s that carry the core's message
  and no status code, so the mapping reads the message after stripping the
  bridge's `Failed to load decision head: ` or `Decision run failed: ` prefix.
  "Load the decision head again" (a freed head, or one lost to a worker
  failure, which also forgets the head), "No model loaded", "Bridge has been
  disposed", "was cancelled" and "during active generation" map to
  `LlamaStateException`, from the capability probe too; "decision encoder
  context" to `LlamaContextException`; anything else to unsupported for the
  probe, `LlamaModelException` for a load (head URL in `details`),
  `LlamaInferenceException` for a run and `LlamaStateException` for a free.
  Load errors that ask bridge callers to pass `configJson` ask for the head's
  config, or name the config URL, instead. Without an active bridge, the probe reports
  unsupported and a load throws `LlamaStateException`, as native does for an
  unloaded model. A malformed head description or output is
  `LlamaDecisionException`, like native's unexpected worker responses.
- Numbers: Web numbers cannot tell `30.0` from `30`, so `pythonJsonDumps`
  writes an integral double in a non-`String` state, instructions, criteria or
  levels as an int (`30` where Python writes `30.0`). The tokens then differ
  from native and Laya; the guide's Web section tells users to pass such
  values as `String`s when parity matters.
- The bridge serializes decision calls with its other operations and cannot
  cancel a run. When its worker fails during a run, it reloads the model on the
  main thread and rejects the run; the engine keeps its model, and the
  `DecisionEngine` must be loaded or attached again. If that reload also fails, the bridge
  forgets the model: later decision calls throw `LlamaStateException` ("No model
  loaded"), and the model must be unloaded and loaded again.

## Parity rules

Sequence (`build_sequence`, `max_len` 512, `head_max_len` 192):

```text
[CLS] "<type> question: <instructions>" [SEP] [MASK] " opt0" [MASK] " opt1" ... [SEP] state [SEP]
```

- Every piece has the mask token's text replaced by one space first.
- Option ids are truncated to 48 after the marker. If fewer than 16 tokens
  remain of `head_max_len`, each option is cut to `max(4, (head_max_len - 16)
  ~/ K)`. The head text keeps `max(8, remaining)` tokens.
- State fills `max(0, max_len - len - 1)` tokens, then `[SEP]`; the result is cut
  to `max_len` and markers past it are dropped. If fewer markers than options
  survive, the question fails with `LlamaDecisionException`.
- Instructions: a `String` as-is; any other JSON-like value, from a question
  constructor or `fromJson`, becomes `json.dumps(value)` text with Python's
  defaults (`ensure_ascii=True`, `, `/`: ` separators), as Laya's
  `_to_internal` does. `fromJson` reads a `null` `instructions` as the text
  `null`.
- Tokenization is `engine.tokenize(text, addSpecial: false)` (llama.cpp parses
  special tokens, matching Hugging Face added-token splitting). Each distinct
  text is tokenized once per call.
- Text containing U+0000 is rejected with `LlamaDecisionException` instead of
  being tokenized: llama-web-bridge reads the text as a C string, so Web
  tokenization cuts it at the NUL while Laya tokenizes all of it. Native
  tokenization keeps it, but the rejection applies on every backend. A
  non-string state is JSON-encoded, which escapes U+0000.
- Options: choice `label` or `label: <criterion>`; score `level i: <criterion>`;
  noul `false: <criterion or "no, the statement does not hold">`, `true:
  <criterion or "yes, the statement holds">`. Non-string criteria render as
  compact JSON (`ensure_ascii=False`). State is a string as-is or
  `json.dumps(state, ensure_ascii=False)`.
- `fromJson` turns a list-valued choice `criteria` into labels without
  descriptions, in list order; a repeated label keeps its first position, as
  Laya's `{c: None for c in crit}` does.

Decoding, per question with K markers and question type q:

- `t` = `temperature_by_options["<type>:<2|3-5|6-10|11+>"]` if present, else
  `temperature[q]`; clamped to [0.5, 5.0]; non-numeric, NaN or infinite becomes
  1.0. Temperatures come from the config, not the `temperature` tensor.
- `p = softmax(logits / t)`. Choice: first argmax, `confidence = clamp(1 -
  H(p) / ln K, 0, 1)` with `p` clipped to 1e-12 inside the log, and 1.0 when K <
  2. Score: `score = sum(i * p_i)`, same confidence. Noul: `noul = p[1]`,
  `confidence = max(p[1], 1 - p[1])`.
- Act head input: CLS row after the head layers, concatenated with `[top1, top1
  - top2, H(p_raw) / ln(max(K, 2)), max(K, 2) / 255]` from the untempered
  softmax (log clip 1e-9; top2 is 0 when K = 1). `Linear -> GELU(erf) ->
  Linear`; `actProbability = softmax(act)[0]`.
- `usage.inputTokens` is the sum of sequence lengths; `model` is
  `laya-rl-agent`.

Validation before any native call: at least one question; non-empty ids; at
least one option (K = 1 is valid); score levels non-empty; criteria values are
JSON-like (null, bool, num, String, List, Map with String keys).

## Platform matrix

| Platform | Path | Status |
| --- | --- | --- |
| macOS | Metal or CPU | validated with a real model ([Measured](#measured)) |
| iOS | Metal or CPU | expected, untested |
| Android | CPU or Vulkan | expected, untested through `DecisionEngine` |
| Linux | CPU, Vulkan, CUDA | expected, untested |
| Windows | CPU, Vulkan, CUDA | expected through the `ggml-base` twins, untested |
| Native LiteRT-LM | - | `LlamaUnsupportedException` |
| Web (WebGPU bridge) | WebGPU or CPU (WASM) | bridge assets `v0.1.47+` (apiVersion 1), the default pin among them; older assets report `LlamaUnsupportedException`. CI uses a fake bridge; checked locally with a real model ([Web check](#web-check)) |
| LiteRT-LM Web | - | `LlamaUnsupportedException` |

Real-model evidence is macOS only. The CPU head unit tests carry no
`local-only` tag, so CI's Linux VM job and its macOS and Windows native test
jobs run them. iOS, Vulkan and CUDA have no run at all. Android numbers come
from the prototype that preceded this implementation, not from
`DecisionEngine`: about 2.1 s per question (512-token window, Q8_0) on a Pixel
9 Pro with 6 CPU threads, and Mali Vulkan was slower than the CPU there.

### Measured

`decision-model-smoke` on an Apple M4 Max (16 cores, macOS), 24 fixture rows of
31 to 512 tokens (mean 90), `ModelParams(contextSize: 512)`, default threads
(llama.cpp's 4). Differences are the worst over all rows against the Laya 0.3.5
PyTorch reference; time is `systemOne` wall time per question.

| Backbone | Head file | Backend | Head device | Logit diff | Probability diff | Score diff | ms per question |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F32 (local conversion) | `laya-head.safetensors` | CPU | CPU | 0.0129 | 0.0029 | 0.0019 | 187 |
| F32 (local conversion) | `laya-head.safetensors` | Metal | MTL0 | 0.0118 | 0.0030 | 0.0031 | 15.4 |
| F16 (local conversion) | `laya-head.safetensors` | CPU | CPU | 0.0518 | 0.0115 | 0.0097 | 115 |
| F16 (local conversion) | `laya-head.safetensors` | Metal | MTL0 | 0.0118 | 0.0030 | 0.0031 | 14.0 |
| `laya-Q8_0.gguf` | `laya-head.safetensors` | CPU | CPU | 0.1422 | 0.0356 | 0.0609 | 85.6 |
| `laya-Q8_0.gguf` | `laya-head.safetensors` | Metal | MTL0 | 0.1642 | 0.0436 | 0.0253 | 14.4 |
| F32 (local conversion) | official `model.safetensors` + config | CPU | CPU | 0.0129 | 0.0029 | 0.0019 | 188 |
| `laya-Q8_0.gguf` | official `model.safetensors` + config | Metal | MTL0 | 0.1642 | 0.0436 | 0.0253 | 14.2 |

The action logits are about ±4000 and saturate `act_probability`, so the smoke
bounds them relative to each row's largest reference action logit
(`LLAMADART_DECISION_ACT_LOGIT_TOLERANCE`, default 0.05). `laya-Q8_0.gguf`
measured 0.0167 on the CPU and 0.0126 on Metal; constant action logits fail at
0.79.

The official checkpoint's F16 head tensors give the same differences as the F32
head file. On these 24 fixture rows, in every configuration, no choice changed,
no noul crossed 0.5 and no score rounded to a different level.
The published `laya-F16.gguf` gives the F16 conversion's worst differences:
0.0518, 0.0115 and 0.0097 on the CPU (`decision-model-smoke` and
`decision-gguf-cpu`) and 0.0118, 0.0030 and 0.0031 on Metal
(`decision-gguf-metal`).

The fixture's short sequences understate the error. A broader review set of
187 questions in 62 random requests (seed 20260922, mean 327 tokens, 73
sequences at the 512-token cap), compared with Laya 0.3.5 on CPU in FP32, gave
these worst differences:

| Backbone | Backend | Logit diff | Probability diff | Changed decisions |
| --- | --- | --- | --- | --- |
| F32 (local conversion) | CPU | 0.102 | 0.0065 | none |
| F32 (local conversion) | Metal | 0.100 | 0.0085 | none |
| F16 (local conversion) | CPU | 0.204 | 0.0189 | two choices with reference top-2 gaps of 0.00015 and 0.0003 |
| F16 (local conversion) | Metal | 0.100 | 0.0085 | none |
| `laya-Q8_0.gguf` | CPU | 1.905 | 0.237 | a noul from 0.694 to 0.457 (also with 1 and 4 threads); a choice with a reference top-2 gap of 0.00015; a noul from 0.4997 to 0.5004 |
| `laya-Q8_0.gguf` | Metal | 2.935 | 0.066 | two choices with reference top-2 gaps of 0.00015 and 0.0014; a noul from 0.4997 to 0.5010 |

On this set the median Q8_0 difference is about 6 times the F32 one for logits
and 8 times for probabilities; on the fixture the worst is 11 (CPU) to 14
(Metal) times. Q8_0 can change clear decisions. An F16 conversion matched F32
on Metal and flipped only near-ties on CPU. Use an F32 backbone, or F16 on
Metal, when answers must match Laya; the published `laya-F16.gguf` has not
been measured on this set.

On Metal, disposing the engine with a head still loaded exits cleanly. If
`freeModel` and `dispose` skipped the head frees, the head would stay
allocated until its isolate shuts down or, on a runtime with exit teardown,
until the process exits (`doc/llama_cpp_exit_teardown.md`); on an older
runtime an exit that does neither aborts in `ggml_metal_rsets_free`.

### Web check

Local only, not in CI: `DecisionEngine` through `LlamaEngine(LlamaBackend())`
in Playwright's headless Chromium on the same machine, with bridge assets
`v0.1.47` (bridge source `64ba8250`), the 24 fixture rows,
`laya-head.safetensors` and the tolerances of `decision-model-smoke`. Token ids
and markers matched on every row.

| Backbone | Bridge runtime | Head device | Logit diff | Probability diff | Score diff |
| --- | --- | --- | --- | --- | --- |
| `laya-Q8_0.gguf` | WebGPU; worker and main thread on wasm64 and wasm32 | WebGPU | 0.1636 | 0.0436 | 0.0247 |
| F16 (local conversion) | WebGPU; worker and main thread on wasm64 | WebGPU | 0.0169 | 0.0046 | 0.0013 |
| F16 (local conversion) | WASM CPU; worker and main thread on wasm64 | CPU | 0.0149 | 0.0039 | 0.0028 |
| `laya-Q8_0.gguf` | WASM CPU; worker and main thread on wasm64 | CPU | 0.2326 | 0.0628 | 0.1224 |

Q8_0 on the WASM CPU misses the probability and score tolerances on one row,
`plain_text/urgency5`, with the same top option. The bridge's own smoke, which
calls the bridge directly, gets the same worst logit difference on wasm32 and
wasm64 in both bridge modes, so the drift comes from the bridge's WASM CPU
Q8_0 path rather than llamadart. With the bridge assets from
[#665](https://github.com/leehack/llamadart/pull/665), the validation harness
gave the same worst differences: 0.2326, 0.0628 and 0.1224 on the WASM CPU,
and 0.1636, 0.0436 and 0.0247 with `decision-gguf-webgpu`, which passed. With
the published `laya-F16.gguf` on WebGPU it gave the F16 conversion's 0.0169,
0.0046 and 0.0013, but each model load took 45 to 51 s
([Decision profiles](cross_platform_validation.md#decision-profiles)).
Typed key reads with the question identity check, sequence validation
messages, error mapping, URL redaction, `<base href>` resolution, and heads
freed or bridges disposed behind the engine's back were checked against the
same assets. The previous pin, `v0.1.44`, which lacks the API, reported
unsupported with the actionable reason in both bridge modes.

The `decision-model-web-smoke` scenario repeats the `laya-Q8_0.gguf` WebGPU
worker check with the pinned assets ([testing matrix](testing_matrix.md)).
With bridge source `5340be9e` in headless Chrome 155 on an Apple M4 Max
(wasm64 core), it passed every row with worst differences of 0.1244, 0.0334
and 0.0217.

## Known limits

User-facing limits are listed under
[Known limits](../website/docs/guides/decision-models.md#known-limits) in the
guide.

## Testing

- Unit (VM and Chrome unless noted): `python_json` against Python output
  (float formatting is VM-only because Web numbers lose the int/double
  distinction); sequence assembly, decoding, and question JSON round trips and
  validation on synthetic inputs; typed keys on hand-built results: kind,
  option-label and level-key checks, the missing-answer error, a question
  shared by two keys, `questionsOf`, and the key constructors.
- Unit (VM, the fixture is read with `dart:io`): sequence ids and markers for
  all 24 fixture rows using the fixture's recorded tokenizations; decoding from
  recorded raw logits to the recorded answers within 6e-5 (Laya rounds to 4
  decimals and decodes in float32; worst measured deviation 4.96e-5); typed
  keys on the engine with a fake backend: fixture token ids for key-built
  questions, typed reads, and the errors for an id the result did not ask and
  for a question from a rebuilt key, from JSON or from another request of a
  batch.
- Unit (VM): safetensors parsing and malformed-file errors on synthetic files;
  the ggml head on a tiny synthetic head against a pure-Dart reference, and
  through a recording ggml function table that checks every create has its
  free, the teardown order, the thread count and the scheduler's backend
  order; the service's load-time check helpers, head device choice, the
  encoder context's offload and flash-attention flags and the scheduler's
  `op_offload` for CPU, GPU, GPU-backend-without-device and conservative
  Android Vulkan loads through recording function tables,
  the encoder context freed after a failed head init (exit-teardown suite),
  sequence validation, and run order through a substituted encoder; worker,
  backend-client and router routing with fakes; engine hooks and facade with a
  fake backend, including `load` (downloads before loading, encoder params,
  combined progress, ownership, atomic failure at each step, cancellation,
  rejected settings, URL-loading backends), `attach` (engine store, borrowing,
  several heads, probe before download, `sha256`, unload during download).
- Unit (Chrome): `WebGpuDecisionHeads` against a fake bridge
  (`test/support/fake_webgpu_decision_bridge.dart`): the capability probe for
  old assets, a bridge missing any one decision method, API version skew, a
  response without `supported`, bridge reasons and state rejections; head
  loading with page-fetched configs, unreadable ones, URLs resolved against a
  `<base href>`, and credentials and queries kept out of errors; error mapping,
  including the `configJson` wording; handle scoping to the loading bridge;
  malformed responses. `WebGpuLlamaBackend` without an active bridge, and
  forgetting heads on `modelFree`, a same-bridge model load and `dispose`;
  `WebAutoBackend` forwarding and LiteRT-LM Web reporting unsupported; the
  engine hook without a model.
- Integration (Chrome, fake bridge): `DecisionEngine` through `LlamaEngine`,
  `WebAutoBackend` and `WebGpuLlamaBackend`: answers, typed key reads with the
  question identity check, sequence layout, page-fetched config, old assets,
  API version skew, a cancelled capability probe, and a model unload; `attach`
  with document-relative and `blob:` sources, and an owned `load`.
- Integration (VM, CI's `stories15M.gguf`): a llama-architecture model is
  reported unsupported and the head load fails before reading the head.
- Local-only E2E `test/e2e/backends/decision_engine_e2e_test.dart`: real GGUF
  and head, the 24 fixture rows, exact token ids and markers from the engine
  tokenizer, raw marker and action logits and `systemOne` answers within
  tolerance (see `doc/testing_matrix.md` for the tolerance rules); an owned
  `load` with `ComputeDevice.cpu`, whose head runs on the CPU, and off it for
  a model on a GPU backend; two heads attached to one encoder; the
  requested backend itself, not a CPU fallback; a config longer than the
  encoder was trained for, which load rejects; and an engine disposed with a
  head still loaded, whose process must then exit cleanly (on Metal a leaked
  buffer aborts the exit, which fails the runner).
  Runner scenario `decision-model-smoke` (`--model-path`, `--head-path`,
  optional `--config-path` and `--backend`) and test-matrix row of the same
  id.
- No test reaches the service's order of head and context teardown; that
  needs fault injection or a GPU device.

Fixture: `packages/llamadart_validation/assets/decision/laya_0_3_5_reference.json`,
produced by the scripts in `test/fixtures/decision/` from the pinned official
checkpoint on CPU in FP32.

## Delivery

The delivery plan and remaining work, including head fine-tuning and the Web
decision module, are tracked in
[#604](https://github.com/leehack/llamadart/issues/604). The Tetris-tuned head
is published as
[leehack/laya-tetris-head](https://huggingface.co/leehack/laya-tetris-head).
