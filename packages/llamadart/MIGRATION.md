# Migration Guide

This document covers the major breaking upgrade paths.

## `0.19.6` -> `0.19.7`: image generation `ComputeDevice.auto` on macOS x86_64

No Dart API changes. On macOS x86_64 (Intel Macs and Rosetta), image generation
with `ComputeDevice.auto` now runs on the CPU, as `GpuBackend.auto` does for
llama.cpp, because upstream ggml-metal can produce garbled output on Intel Macs
with AMD GPUs. An explicit `ComputeDevice.gpu` still loads on Metal and logs a
warning.

Behavior to recheck after upgrading:

- `ImageModelPlacement(textEncoderOnCpu: true)`, `vaeOnCpu: true`,
  `maxGpuMemoryGiB` or `autoFit: false` under `ComputeDevice.auto` now throw
  `LlamaUnsupportedException`, because they need an engine on a GPU. Pass
  `ComputeDevice.gpu` to place the work on Metal, or drop the options.

## `0.19.0` -> `0.19.1`: desktop LiteRT-LM embeddings need native `v0.19.1-2`

Core `0.19.1` bundles
[LiteRT-LM v0.19.1-2](https://github.com/leehack/litert-lm-native/releases/tag/v0.19.1-2),
so apps on the bundled runtime are unaffected. Linux and Windows native
embeddings now require that runtime's in-process LiteRT marker: a custom
`LLAMADART_LITERT_LM_LIB_DIR` runtime older than `v0.19.1-2`, including
`v0.19.1-1`, throws `LlamaUnsupportedException` before any native embedding
call. Point the override at `v0.19.1-2` or later
([#1367](https://github.com/leehack/llamadart/issues/1367)).

## `0.18.x` -> `0.19.0`: LiteRT-LM native `v0.19.1-1` and Web `0.19.0`

Core `0.19.0` and `llamadart_litert_lm_flutter` `0.19.0` move to published
[LiteRT-LM v0.19.1-1](https://github.com/leehack/litert-lm-native/releases/tag/v0.19.1-1)
(owner `82d4ae1c`, upstream `7a03724c`), which keeps the C API 1.0.0 exports of
v0.19.0, so the `0.18.0` ABI selection below
applies unchanged. Web LiteRT-LM moves to `@litert-lm/core@0.19.0` in `0.19.0`.

## `0.17.x` -> `0.18.0`: native LiteRT-LM ABI selection

The public `LiteRtLmRuntimeClient`, default services and speech worker now share
lazy ABI-aware discovery. Runtimes without `litert_lm_get_api_version` use the
legacy client; a successful version probe reporting exactly `1.0.x` selects the
C API 1 client. Failed probes, malformed versions and other versions throw
`LlamaUnsupportedException` before engine calls; they never retry legacy
signatures. Required exports and optional capability groups are checked before
use. A version marker alone does not establish feature support.

The selected native loader requires macOS 14 or newer on Apple silicon before
loading core or companion libraries, including custom paths. Older or
unverifiable macOS versions are refused even when the library would use the
legacy ABI. Upgrade macOS or use llama.cpp. Other platform/backend restrictions
remain in the [support matrix](website/docs/platforms/support-matrix.md).

Behavior to recheck with a C API 1 runtime:

- Initial text LoRA adapters remain unsupported by the advanced engine. Use a
  compatible llama.cpp model/adapter pair.
- `LiteRtLmRuntimeClient.initialize(maxNumImages: ...)` is an image-history hint,
  not an enforced capacity. V1 accepts actual images dynamically and requires a
  configured vision encoder for that hint.
- Thinking budgets, JSON Schema, media and dedicated ASR require their own
  admitted exports and model/configuration capabilities. Unsupported combinations
  throw typed errors; accepting the ABI does not qualify a model or device.
- A missing final callback, failed native drain or uncertain cleanup retains the
  worker and its native/model/cache owners. That backend requires a process
  restart; an ended request does not prove native cleanup completed.

See [the adoption checklist](doc/litert_lm_v1_adoption.md) for per-feature coverage.

## `0.17.0` -> `0.17.1`: llama.cpp native runtime `v0.8.0-1`

The hook and the llama.cpp Apple companion source pin `v0.8.0-1`. Flutter iOS and
macOS apps get it with `llamadart_llama_cpp_flutter` `0.17.1`, which requires
core `0.17.1`. A locked companion `0.17.0` keeps `v0.7.0-3` and builds with an
upgrade warning. Web moves to llama.cpp `v0.8.0` too. The LiteRT-LM and
stable_diffusion companions also release at `0.17.1` with unchanged pins, and
their `0.17.0` releases keep working. No Dart API changes.

Behavior to recheck after upgrading:

- A hand-written `grammar` nested or chained more than 256 levels deep throws
  `LlamaInferenceException`.
- `ModelSplitMode.row` on a native llama.cpp device without split buffers throws
  `LlamaUnsupportedException` before the load; use `ModelSplitMode.layer`.
- `GpuBackend.auto` on macOS x86_64 runs on the CPU. Explicit `GpuBackend.metal`
  still uses Metal.
- Opt-in `GpuBackend.blas` at the default thread count uses at most 4 threads;
  set an explicit count to raise it.
- LFM2 and LFM2.5 with `parallelToolCalls: true` can need a higher `maxTokens`: a
  call list cut off before it closes returns no calls.

<a id="016x-to-0170-upgrade-guide"></a>

## `0.16.x` -> `0.17.0`: upgrade guide

Upgrade core and every Apple companion used by the app to `0.17.x` together.
Companions now constrain core to `'>=0.17.0 <0.18.0'`. The llama.cpp and
stable_diffusion companions move to `v0.7.0-3` and `v0.3.0-1`; LiteRT-LM keeps
`v0.18.1-4`.

### Optional LoRA and multimodal backend capabilities

Custom backends and backend test fakes only. `LlamaBackend` no longer
declares `setLoraAdapter`, `removeLoraAdapter`, `clearLoraAdapters`,
`multimodalContextCreate`, `multimodalContextFree`, `supportsVision` or
`supportsAudio`. They move to two optional interfaces in
`package:llamadart/backend.dart`:

- `BackendLoraSupport`: the three LoRA members.
- `BackendMultimodalSupport`: the four projector members.

A backend that supports either implements it next to `LlamaBackend`
(`implements LlamaBackend, BackendLoraSupport, BackendMultimodalSupport`);
its `@override` annotations stay valid. A backend that only threw from
these members deletes them. On a backend without the interface,
`LlamaEngine` LoRA calls and projector loads throw
`LlamaUnsupportedException` naming the missing interface, before
`setLoraSource`, `loadMultimodalProjectorSource` or `setModel` downloads
anything; `removeLoraSource` of an adapter never applied does nothing, and
vision and audio input come from `BackendDirectMediaInput` alone. Code that
called these members through a `LlamaBackend`-typed value checks
`backend is BackendLoraSupport` or `backend is BackendMultimodalSupport`
first.

The built-in routers (`LlamaBackend()` on native and the Web) implement both.
When the selected runtime, such as LiteRT-LM, lacks one, they throw
`LlamaUnsupportedException` naming the runtime instead ("LoRA adapters are
not supported by the active Web runtime."). `LiteRtLmBackend` implements
neither.

### `ImageModelRole.controlNet`

`ImageModelRole` gains `controlNet`. A `switch` over `ImageModelRole` without
a default case no longer compiles; add the case or a default. A file whose
header shows ControlNet tensor names is now assigned this role instead of
failing classification: outside the bounded SD 1.x macOS CPU recipe,
`ImageGenerationEngine.load` throws `LlamaUnsupportedException` instead of
`LlamaModelException`. A ControlNet loaded with no file holding diffusion
weights (for example, alone) still throws `LlamaModelException`.

### Thinking follows llama-server on more templates

`enableThinking`, which defaults to `true`, now reaches every chat template as
`enable_thinking`, including `responseFormat` and tool-call requests, so
templates such as GLM-4.6, Apertus and DeepSeek-R1 distills render thinking
as llama-server does: Apertus now deliberates and DeepSeek-R1 distills open a
thought unless the request passes `enableThinking: false`. A boolean
`enable_thinking` or `thinking` in `chatTemplateKwargs` now overrides
`enableThinking`. With thinking off, `<think>` blocks that DeepSeek V3.1,
Qwen3, QwQ and Qwen3.5 write stay in the content instead of being dropped.

### llama.cpp native runtime `v0.7.0-3`

The hook and the llama.cpp Apple companion source pin `v0.7.0-3`. A Flutter
iOS or macOS build needs companion `0.17.0`, which pins it; a companion
pinning `v0.7.0-2` or earlier fails with `Incompatible Apple llama.cpp
companion`. Apps that depend on a published companion hit pub resolution
first, because companions before `0.17.0` constrain `llamadart` below
`0.17.0`.

### stable_diffusion native runtime `v0.3.0-1`

The hook and the stable_diffusion Apple companion source pin `v0.3.0-1`. A
Flutter iOS or macOS build needs companion `0.17.0`, which pins it; a
companion pinning `v0.3.0` fails with `Incompatible Apple stable_diffusion
companion`, because that runtime aborts on FP8 weights on Metal, which this
core now loads there. Upgrade core and companion together.

<a id="015x-to-0160-upgrade-guide"></a>

## `0.15.x` -> `0.16.0`: upgrade guide

Upgrade core and every Apple companion used by the app to `0.16.x` together.
Companions now constrain core to `'>=0.16.0 <0.17.0'`. The llama.cpp companion
keeps `v0.7.0-2`; LiteRT-LM and stable_diffusion move to `v0.18.1` and
`v0.3.0`.

### Runtime-specific `ModelParams` fields are rejected, not ignored

A load throws `LlamaUnsupportedException` naming each `ModelParams` field set
away from its default that the model's runtime does not apply. Earlier
releases loaded the model and dropped these fields:

| Runtime | Newly rejected fields |
| --- | --- |
| llama.cpp, native and Web | `liteRtLmBackend`, `liteRtLmActivationDataType`, `liteRtLmPrefillChunkSize`, `liteRtLmParallelFileSectionLoading`, `liteRtLmDispatchLibDir`, `liteRtLmCacheDir`, `liteRtLmMaxProgramCacheBytes` |
| llama.cpp, native | `preferMemory64`, `modelBytesHint` |
| llama.cpp, WebGPU bridge | `useMmap: false`, `useMlock: true` |
| LiteRT-LM, native and Web | `loadMtp`, `speculativeRollbackTokenMax`, `preferMemory64`, `modelBytesHint` |

An app that shares one `ModelParams` across GGUF and `.litertlm` models, or
across native and Web, sets these fields only for the runtime that applies
them, for example with `copyWith` and the matching `clear*` flags.
`LlamaEngine.load` and `setModel` on `LlamaBackend()` reject them before any
download when `ModelSource.format` or the file name names the model format;
the deprecated `loadModelSource` and a model known only from its file header
reject them when the model loads, before the runtime starts.

LiteRT-LM models on macOS x86_64, Windows arm64 and the x86_64 iOS simulator,
which have no LiteRT-LM runtime, and an explicit `device` the platform's
LiteRT-LM lacks, such as `gpu` on Linux arm64, also fail before any download.

### Runtime-specific parameter types; `liteRtLm*` arguments deprecated

`LlamaCppModelParams` and `LiteRtLmModelParams` are `ModelParams` whose
constructors take only the fields their runtime applies, so every API that
takes `ModelParams` takes them. A load throws `LlamaUnsupportedException`
when one is used for the other runtime, and their `copyWith` keeps the type
and throws `LlamaArgumentException` for the other runtime's fields and
`clear*` flags.

The `liteRtLm*` arguments of the `ModelParams` constructor and `copyWith`,
and the matching `clearLiteRtLm*` flags, are deprecated until 1.0. They still
work. The fields keep their names, so reads such as `params.liteRtLmCacheDir`
are unchanged.

```dart
// Before
const params = ModelParams(
  liteRtLmCacheDir: '/data/litert-cache',
  liteRtLmEmbeddingEngine: true,
  device: ComputeDevice.cpu,
);

// After
const params = LiteRtLmModelParams(
  cacheDir: '/data/litert-cache',
  embeddingEngine: true,
  device: ComputeDevice.cpu,
);
```

| Deprecated `ModelParams` argument | `LiteRtLmModelParams` argument |
| --- | --- |
| `liteRtLmEmbeddingEngine` | `embeddingEngine` |
| `liteRtLmActivationDataType` | `activationDataType` |
| `liteRtLmPrefillChunkSize` | `prefillChunkSize` |
| `liteRtLmParallelFileSectionLoading` | `parallelFileSectionLoading` |
| `liteRtLmDispatchLibDir` | `dispatchLibDir` |
| `liteRtLmCacheDir` | `cacheDir` |
| `liteRtLmMaxProgramCacheBytes` | `maxProgramCacheBytes` |

`copyWith` takes the same names and `clear*` flags (`clearCacheDir`). As on
`ModelParams.copyWith`, a clear flag wins over a value for the same field,
whichever spelling either uses. Errors name a `LiteRtLmModelParams` option
without the prefix. `liteRtLmBackend` stays deprecated in favor of `device`.

### Native LiteRT-LM penalty and thinking-budget errors

Native LiteRT-LM now applies `GenerationParams.penalty`, `presencePenalty`
and `thinkingBudget` where `engine.capabilities` reports them. A value it
cannot apply, such as a `penalty` below `1.0`, a zero `ThinkingBudget`, a
budget on a bundle without a thinking channel or on a runtime without the
API, throws `LlamaUnsupportedException` instead of the `UnsupportedError`
these options threw before. Catch `LlamaUnsupportedException`, or check
`supportsPenalty`, `supportsPresencePenalty` and `supportsThinkingBudget`
first. A non-finite `penalty` or `presencePenalty` (NaN or infinity) throws
`ArgumentError` instead. Other LiteRT-LM options it does not apply, such as
`minP` and grammars, still throw `UnsupportedError`.

`LiteRtLmRuntimeClient.generate` and `generateMessageJson` take new optional
named parameters; subclasses that override them must declare them.

### LiteRT-LM native runtime `v0.18.1`

The native-assets hook and the LiteRT-LM Apple companion source pin
`v0.18.1`. A Flutter macOS app loads LiteRT-LM from its own bundle only with
companion `0.16.0`, which pins `v0.18.1`; a companion pinning a `v0.18.0`
build keeps macOS LiteRT-LM in the hook cache with a build warning. The app
API is unchanged, and native GPU embeddings still throw
`LlamaUnsupportedException`.

### stable_diffusion native runtime `v0.3.0`

The hook and the stable_diffusion Apple companion source pin `v0.3.0`, whose
`sd_ctx_params_t` is larger than in `v0.2.0-4`. A Flutter iOS or macOS build
needs companion `0.16.0`, which pins `v0.3.0`; upgrade both together. Apps
that depend on a published companion hit pub resolution first, because
companions before `0.16.0` constrain `llamadart` below `0.16.0`. Apps that
depend on `llamadart` or the companion from git or a path and keep an older
companion fail with `Incompatible Apple stable_diffusion companion`.
`ImageModelParams` is unchanged, and flash attention and direct convolution
stay as it selects them.

<a id="014x-to-0150-upgrade-guide"></a>

## `0.14.x` -> `0.15.0`: upgrade guide

Upgrade core and every Apple companion used by the app to `0.15.x` together.
Companions now constrain core to `'>=0.15.0 <0.16.0'`. The llama.cpp companion
pins `v0.7.0-1`; LiteRT-LM and stable_diffusion keep `v0.18.0-2` and `v0.2.0-3`.

### Content embedding cancellation

`cancelGeneration()` cancels `embedContent` / `embedContentBatch` even
during capability checks on native and Web backends. Handle the existing
`LlamaInferenceException` cancellation error and await the embedding future
before reuse. Calls started after cancellation remain usable. Native LiteRT-LM
also checks cancellation after worker startup, including its string embedding
methods, which share the content implementation. Native llama.cpp and Web
legacy `embed` / `embedBatch` cancellation contracts are unchanged.

### Native text-to-speech context exclusivity

Native llama.cpp rejects embeddings (including content and batch embeddings),
next-token scoring, text generation, state save/load and LoRA changes on a
context while text-to-speech is active with `LlamaStateException`. Await the
synthesis task, including cancellation, before reusing that context. The
reservation starts before speaker-reference loading; a rejected overlapping
request leaves the active request's performance counters intact.

Text-to-speech also rejects a start while generation is active on its context,
and a second synthesis on the same native worker, including during setup.
This fixes unsafe overlap; method signatures and platform support are unchanged.

### Native wrapper rebuild

The native-assets hook and Apple companion source now pin `v0.7.0-1`, a
wrapper rebuild of upstream llama.cpp `v0.7.0`. Existing inference behavior
and the app API are unchanged. Apple apps need companion `0.15.0`; the
`0.14.0` companion pins `v0.7.0` and is rejected by the updated hook.

### LiteRT-LM Web cancellation errors

Keep handling `LlamaInferenceException` after `cancelGeneration()`: a runtime
failure racing cancellation now surfaces instead of ending normally. Only the
pinned runtime's exact `Task cancelled` error after a cancel request ends
normally. The same error without a cancel request remains a failure. No API
migration is needed.

### Native performance counters

Queued cancellations on native LiteRT-LM now return `null` diagnostics, matching
llama.cpp, including requests already sent to the worker that never run.
LiteRT-LM validation failures, llama.cpp option-validation failures before
the counter reset, and failed dispatches also return `null`. Native llama.cpp
resets counters before generation, embedding (the entire batch), next-token scoring
or text-to-speech executes; counters then describe only that request's work.
Request validation failures in the native worker leave diagnostics unavailable;
argument checks that fail before dispatch leave them unchanged. LiteRT-LM still recovers counters
on generation. Requests finishing after reload no longer affect the new context's
counter availability, even if its handle is reused. No API migration is needed;
continue handling unavailable diagnostics. Rejections during active text-to-speech
preserve that synthesis request's counters. After an early cancellation, pending
or failed embedding, scoring and speech calls preserve unavailable diagnostics,
including calls started before cancellation. Generation dispatch restores
availability immediately; embedding, scoring and speech restore it only on
success, using the backend's counter semantics. Web backends still return `null`
after every request.

### Template error labels

An empty `tokenizer.chat_template` now names `the built-in ChatML fallback
template` in render errors. PEG parse errors retain `peg-simple`, `peg-native`
and the historical `peg-constructed` spelling (still used for Qwen3 Coder XML).
Exception types and parsing behavior are unchanged.

### Native llama.cpp placement diagnostics

With `device: ComputeDevice.auto`, `splitMode: ModelSplitMode.none` and a
negative `mainGpu`, backend name and capabilities now report `CPU`, and
`getResolvedGpuLayers()` returns `0`. The model already ran on the CPU;
context and draft-model execution settings are unchanged.
Decision heads now follow this CPU placement too, and
`DecisionModelInfo.deviceName` reports `CPU`. Previously, a head could still
select the first matching GPU of the load's backend. Explicit nonnegative
`mainGpu` selection and other split modes keep their existing head placement.
No parameter migration is needed. Explicit `gpu` / `npu`
validation is unchanged.

### Native generation capabilities

Native llama.cpp now probes the loaded model/runtime for thinking-budget
support; check `supportsThinkingBudget` instead of assuming it is available.
Before load or after unload, its generation capability snapshot is empty.
The `mtp` strategy stays advertised for external draft models; in-file MTP
requires a target model with an MTP head and `ModelParams.loadMtp: true`.
Missing external draft models now throw `LlamaArgumentException` at generation
start, preserving the diagnostic instead of wrapping it in an inference error.

### WebGPU argument errors

Catch `LlamaArgumentException` for invalid WebGPU request arguments, including
runtime LoRA scales and bridge-reported argument rejections. These previously
surfaced as raw argument errors, context errors or `LlamaInferenceException`.
`scoreNextToken` vocabulary and int32 bounds still throw `RangeError`, matching
native. Runtime inference failures and unsupported capabilities retain their
existing types.

### Embedding content API

Web llama.cpp content embeddings now accept image/audio bytes and mono 16 kHz
Float32 PCM when bridge assets v0.1.64+ positively probe the modality
(bridge `getEmbeddingCapabilities()` API version 1; read it with
`await engine.embeddingCapabilities`). Load a compatible embedding model
and projector first. Paths and image URLs throw `LlamaUnsupportedException`.
Older or mismatched bridge assets retain text embeddings and report media
unavailable with an upgrade diagnostic. The default pinned assets include the API;
EmbeddingGemma-2 vectors are qualified on Chrome CPU wasm memory64 against
native CPU/Metal; repeated media batches are qualified only on memory64. Hardware WebGPU is
unqualified. Text-only content keeps legacy `embed` support on pooling NONE.
Image bytes are always encoded data; width/height are ignored for embeddings.
Reserved mixed-input media markers are unsupported, matching native.

The new `embedContent` / `embedContentBatch` APIs return one vector per input;
a backend count mismatch throws `LlamaInferenceException`. Adjacent text parts
form one verbatim-concatenated segment on every backend, including mixed inputs.
The modality enum may grow; include a default case in switches.

Native llama.cpp content embeddings now use the loaded EmbeddingGemma-2
projector for images and audio (v0.7.0-1). Without a projector the probe
reports text only. Oversized expanded media inputs throw
`LlamaInferenceException` before encoding; M-RoPE projectors, URLs and
ambiguous media sources throw `LlamaUnsupportedException`. Each media part
needs exactly one encoded bytes/local-file source, or mono 16 kHz audio PCM.
Text-only content follows `embed`, including causal unpooled models; media
requirements do not restrict text. Older native overrides can retain text
with media disabled; unsupported media errors name the v0.7.0-1 ABI.
No task prefix is inserted. Await a cancelled embedding before reusing the engine.
Windows resolves media functions across the complete native DLL bundle; missing
media symbols disable media without restricting text. EmbeddingGemma-2 BF16
media embeddings are qualified on CPU on macOS arm64, Linux x64, Windows x64, Android and iOS,
and on macOS Metal.

`ModelParams.liteRtLmEmbeddingEngine` defaults to false for conversation loading.
Set true and `device: ComputeDevice.cpu` for native LiteRT-LM embeddings. This intentionally
replaces the previous adapter rejection; generation/tokenizer APIs are unavailable
in embedding mode. Native GPU and all Web paths fail with `LlamaUnsupportedException`.
GGUF loaders still reject true. LiteRT-LM overflow fails the whole call with
`LlamaInferenceException` and no vectors, possibly after earlier items consumed
compute; it never truncates. llama.cpp retains pre-inference capacity validation.
LiteRT-LM concurrent embeds now queue. Cancellation, unload and timeout discard
the whole batch after the current item settles; timeouts throw
`LlamaInferenceException` and cancel only that request. Other queued callers retain
their own deadlines; explicit cancellation, unload and dispose cancel all requests.
`contextSize` selects the encoder signature, without
truncation. Embedding mode rejects conversation tuning (LoRA, chat templates,
activation type, prefill, parallel loading, dispatch paths, program cache limits),
MTP/rollback and Web memory hints rather than silently ignoring them. Native CPU
qualification covers macOS arm64 only.

<a id="013x---0140-llamacpp-v070-abi-qwen3-overrides-and-load-callbacks"></a>

## `0.13.x` -> `0.14.0`: upgrade guide

### Upgrade core and Apple companions together

Upgrade the core and every Apple companion the app uses to `0.14.x` together.
If a fresh macOS SwiftPM build reports a generated 12.0 floor, use the
[Flutter 3.47.1 bootstrap](https://llamadart.leehack.com/docs/platforms/apple-setup#fresh-macos-swiftpm-bootstrap);
keep Runner and the companion requirements at macOS 14.0 or newer.
The llama.cpp companion now pins native `v0.7.0` and the LiteRT-LM companion
pins `v0.18.0-2`; the image companion keeps its native pin. LiteRT-LM reduces
duplicated words at untimed ASR window boundaries with the default overlap;
other boundary and recognition errors can remain.

Native overrides must match the new v0.7.0 context-parameter and performance-data
layouts as well as its exported symbols. v0.6.0 and older native bundles are
ABI-incompatible with these regenerated bindings. Remove an old native override
or keep the app on the matching core `0.13.x` and companions. Apple builds reject
old companion pins before emitting native assets.

### Breaking behavior change: response schemas and tool-call nesting

<a id="response-schemas-and-tool-call-nesting"></a>

Raw `responseFormat` schemas and `LlamaStructuredOutput` now share validation.
Unsupported or shadowed assertions that were silently unconstrained now throw a
path-bearing `LlamaUnsupportedException` before generation. The remaining
unsupported assertions are:

- `multipleOf`, `uniqueItems`, `contains`, `minContains`, `maxContains`,
  `minProperties`, `maxProperties`, `patternProperties`, `propertyNames`,
  `dependentRequired`, `dependentSchemas`, `dependencies`, `not`, `if`, `then`,
  `else`, `unevaluatedItems`, `unevaluatedProperties`, `additionalItems`,
  `$dynamicRef` and `$recursiveRef`, except the trivial assertions
  `uniqueItems: false`, `minProperties: 0` and integer `multipleOf: 1`.
- Numeric bounds on anything except explicit `type: integer`, unsupported
  formats (anything except `uuid`, `uuid1`–`uuid5`, `date`, `time`, `date-time`), patterns outside
  the compiled subset, and length/item bounds above 2000.
- Assertions shadowed by `$ref`, `anyOf`/`oneOf`, or `const`/`enum` (compatible
  literal `type` is allowed); pattern or format combined with length bounds;
  pattern combined with format; and `prefixItems` combined with `items`.
- `allOf` outside additive object-property merges and nonempty enum
  intersections: primitive intersections, nested/union components, repeated
  property names, constrained additional properties (except a single closed object) and shadowed
  siblings.
  Components may use local references; an explicit outer `type` must be
  `object` for property merges or `string` for string enum intersections.
- Unresolved/external references, references into annotation/extension payloads,
  undeclared `required` properties, malformed schemas, conflicting bounds and
  constraints in the wrong type context. Integer endpoints must fit the exact
  VM/Web range (absolute value at most 9007199254740991); a weaker inclusive
  bound cannot shadow a stronger exclusive bound. One-sided positive minima
  and negative maxima containing a nonfinal zero digit are rejected because
  upstream loses suffix padding (for example, `minimum: 100` admits `10`).
  At 16 digits, only absolute endpoints matching `111111111111111[0-9]` are supported;
  others emit inverted repetition bounds. Two-sided bounds are unaffected.

Integer `minimum`, `maximum`, `exclusiveMinimum` and `exclusiveMaximum`
(including Pydantic `ge=` and `NegativeInt`), the formats above and supported
`allOf` forms now compile with llama.cpp v0.7.0 semantics. Format validation is
lexical: dates use month/day ranges, and times require a timezone with optional
three-digit fractional seconds. `uuid1`–`uuid5` use the same lexical UUID rule
as `uuid`, including uppercase hex; they do not constrain the version nibble.
One-sided negative maxima reject leading-zero JSON integers, correcting an
upstream v0.7.0 grammar defect. Arrays with item bounds do not require `items`;
their unconstrained elements may be any JSON value. Fixed tuples accept both `prefixItems` and
draft-07 `items: [...]`, with compatible bounds (`minItems` no greater than the
tuple length, `maxItems` no smaller). Their grammar still requires every tuple
item. Typed final parsing checks the same tuples, formats and integer bounds.
Object `allOf` merges make every merged property required in the grammar, as
upstream does; they emit a closed object, matching upstream.

Schemas must contain JSON values, nested at most 128 container levels, including
annotations. Non-JSON values throw `LlamaArgumentException`. Annotations such as
`discriminator`, `contentMediaType`, `contentEncoding`, `example`, `examples`,
`$anchor`, `$id`, `$schema`, `$comment`, `deprecated`, `readOnly`, `writeOnly`,
`title`, `description`, `default`, and unknown vocabulary (including `x-*`)
remain accepted and ignored as constraints, just as upstream ignores them.
Only schema-bearing positions are traversed for assertions and references.
Unused `$defs`/`definitions` entries are ignored; referenced entries must pass
the same validation as inline schemas.
Nonempty annotation-only untyped schemas accept any JSON value, including in
imported tool properties; `{}` keeps its existing object grammar. Imported tools
keep their narrower subset and object root (see
[tool input schemas](doc/tool_input_schemas.md)).

Decoded tool-call arguments nested beyond 128 containers now fail with
`LlamaInferenceException` on final and partial parsing instead of overflowing.

### Load progress callbacks

Load progress callbacks in `LlamaBackend.modelLoadFromUrl`, format-routing
loads and the legacy `LlamaEngine` URL-loading methods now declare
`void Function(double progress)?` instead of `Function(double progress)?`.
Existing `Function(double progress)?` overrides still compile; prefer the
explicit `void` signature in custom backends and test fakes. Notifications
deliver the same fractions; the return value is ignored and cannot cancel a
load. Native llama.cpp's raw FFI
`bool` progress callback is unchanged.

```dart
Future<int> modelLoadFromUrl(
  String url,
  ModelParams params, {
  void Function(double progress)? onProgress,
}) async {
  // Delegate loading to your runtime, forwarding its progress notifications.
  return runtime.load(url, onProgress: onProgress);
}
```

### Qwen3 template overrides

For renamed legacy Qwen3 LiteRT-LM text bundles, replace copied Jinja with
`ModelParams(chatTemplate: liteRtLmQwen3ChatTemplate)` to keep native
`enableThinking: false` routing stable across upgrades. The accessor always
returns this package version's canonical template. Web
`@litert-lm/core@0.18.0` cannot install a conversation template: loading this
canonical override now throws `LlamaUnsupportedException` instead of appearing
to honor it. Use native LiteRT-LM for this contract. Other Web template overrides
and loads without an override retain their existing behavior.

### Queued cancellation performance counters

Cancelling a queued native llama.cpp generation before dispatch now makes
`getPerformanceContext()` return `null` until another generation is dispatched.
Handle unavailable diagnostics instead of reusing earlier request counters.

### User messages after tool results

<a id="unreleased-user-messages-after-tool-results"></a>

Gemma 2/3/3n and legacy Mistral templates now accept a user message immediately
following tool results. If rendering fails because the template rejects the
`tool` role, the retry appends that user message to the converted result turn
with a newline. Previously this history threw `LlamaInferenceException` for
consecutive user turns. Stored history and requests that render successfully
on the first attempt are unchanged. This extends llama.cpp's former tool-result
polyfill; upstream `b10549` rejects the original history.

## `0.13.1` -> `0.13.2`: template failures, cancellation and schema bounds

These fixes change previously broken paths; working requests are unchanged.
Apple companions remain at `0.13.0`, with the same native and Web runtimes.

- Recursive chat-template failures now throw `LlamaInferenceException`
  instead of `StackOverflowError` on VM and JavaScript.
- Cancelling inside a Hermes tool call keeps only preceding answer text,
  discarding unfinished tool markup. With no preceding output,
  `ChatSession.create` reports “Generation was cancelled before any output.”
  and rolls back the turn. With legacy tools, a completed call before an
  unfinished second call returns `finishReason: tool_calls` with the completed
  call, without executing it, instead of `stop` with raw markup.
- Unfinished Ministral-format reasoning stays out of reply text when
  generation stops or is cancelled.
- Renamed native LiteRT-LM Qwen 3 bundles honor `enableThinking: false` only
  with a canonical Qwen 3 `chatTemplate` override or identifying metadata.
  A renamed file alone does not identify the template family.
- Tool input schemas accept `minLength`, `maxLength`, `minItems` and
  `maxItems` up to 2000, inclusive; 2001 and above still throw
  `LlamaUnsupportedException`. Tool input values still obey the declared bounds.

## `0.13.0` -> `0.13.1`: typed failures and negative `gpuLayers`

These changes alter what callers see:

- `responseFormat` schemas, raw or typed, that the grammar converter cannot
  represent throw `LlamaUnsupportedException`, and cyclic or other non-JSON
  schemas throw `LlamaArgumentException`, instead of `StateError`,
  `TypeError` or a stack overflow. A combined tool or schema grammar that
  llama.cpp would refuse fails before generation with
  `LlamaUnsupportedException`. Schemas that worked before are unchanged.
- LiteRT-LM, native and Web: a generation started right after a cancel waits
  for the cancelled run instead of failing. Overlapping a running generation
  that was not cancelled, or a second waiting one, throws
  `LlamaStateException` instead of `LlamaInferenceException` wrapping a
  `StateError`.
- On Web, WebGPU and LiteRT-LM, `cancelGeneration()` ends the stream
  normally instead of surfacing `LlamaInferenceException` or an `AbortError`.
- A negative `ModelParams.gpuLayers` means all layers on every runtime, like
  `ModelParams.maxGpuLayers`. LiteRT-LM under `ComputeDevice.auto` now
  selects its GPU backend instead of the CPU; pass `gpuLayers: 0` or
  `ComputeDevice.cpu` to keep the CPU. On native llama.cpp,
  `getResolvedGpuLayers()` reports the resolved count instead of the
  negative value.

## `0.12.x` -> `0.13.0`: companion versions and LiteRT-LM cache cap

Apple companions now share the core `MAJOR.MINOR` and constrain `llamadart`
to it, so upgrade every companion the app uses together with the core:

```yaml
dependencies:
  llamadart: ^0.13.0
  llamadart_llama_cpp_flutter: ^0.13.0
  llamadart_litert_lm_flutter: ^0.13.0
  llamadart_stable_diffusion_flutter: ^0.13.0
```

The native pins are unchanged from `0.12.2`. An app that takes `llamadart`
from a path or git checkout repeats that source under `dependency_overrides`.

LiteRT-LM now caps each cache directory's GPU program cache files at 1 GiB by
default, so the first engine create after upgrading may delete files from an
existing oversized cache, and the runtime recompiles them when needed. Set
`ModelParams.liteRtLmMaxProgramCacheBytes` to a larger value, or to
`ModelParams.unlimitedLiteRtLmProgramCacheBytes` (`-1`) to keep every file.
An explicit cap now bounds the directory total instead of each file.

`ToolParam` tool grammars are stricter, and PEG parse failures throw
`LlamaInferenceException` instead of `StateError`; see the `0.13.0` entry in
`CHANGELOG.md`.

- On native llama.cpp, a runtime missing an mtmd function, with no complete
  fallback mtmd library, makes `supportsVision` and image or audio requests
  throw `LlamaUnsupportedException`. Before, `supportsVision` returned `false`
  and those requests threw `LlamaInferenceException`.
- On Web, `SpeechToTextEngine.load`, `TextToSpeechEngine.load` and
  `LlamaEngine.setModel` with a projector now report progress from 0 to 1.

## `0.12.1` -> `0.12.2`: Apple companion pins

Upgrade the Apple companions the app uses together with the core package:

```yaml
dependencies:
  llamadart: ^0.12.2
  llamadart_llama_cpp_flutter: ^0.0.23
  llamadart_litert_lm_flutter: ^0.0.16
```

Core `0.12.2` pins llama.cpp `v0.6.0-3` and LiteRT-LM `v0.18.0-1`. llama.cpp
companion `0.0.22` still builds, with a warning: its `v0.6.0-2` frameworks lack
the minimum OS version keys that App Store validation checks, so upgrade before
shipping. Any other mismatched llama.cpp companion fails the build with an error naming
`0.0.23`. With LiteRT-LM companion `0.0.15`, the macOS build warns that
LiteRT-LM stays in the hook cache, but the app still loads its arm64 runtime
from the bundle ([#1064](https://github.com/leehack/llamadart/issues/1064));
iOS does not check the LiteRT-LM pin. `llamadart_stable_diffusion_flutter`
`0.0.3` is unchanged.

## `0.12.0` -> `0.12.1`: Flutter macOS LiteRT-LM bundle

Upgrade the LiteRT-LM companion together with the core package:

```yaml
dependencies:
  llamadart: ^0.12.1
  llamadart_litert_lm_flutter: ^0.0.15
```

Core `0.12.1` embeds the macOS LiteRT-LM runtime only through companion
`0.0.15`; with an older companion the build warns and the runtime stays in the
hook cache. A Flutter macOS app that added the
[LiteRT-LM build phase](https://llamadart.leehack.com/docs/platforms/apple-setup#flutter-macos-litert-lm-build-phase)
for 0.12.0 can remove it after upgrading both: the script detects the
embedded runtime and copies nothing, so leaving it in place is harmless.
Other platforms and companions are unchanged.

## `0.11.x` -> `0.12.0`: runtime and chat behavior

Upgrade the Apple companions together with the core package:

```yaml
dependencies:
  llamadart: ^0.12.0
  llamadart_llama_cpp_flutter: ^0.0.22
  llamadart_litert_lm_flutter: ^0.0.14
  llamadart_stable_diffusion_flutter: ^0.0.3
```

Add only the companions the app uses. These pairings select llama.cpp
`v0.6.0-2`, LiteRT-LM `v0.18.0` and stable-diffusion.cpp `v0.2.0-3`.
Keep the previous companions with core `0.11.x`; a mismatched llama.cpp or
image companion fails the Apple build's runtime-pin check. Resolve the new
dependencies with `flutter pub get`.

- Native llama.cpp state files saved by core `0.11.x` or earlier no longer
  load because llama.cpp `v0.6.0` changed their format. `stateLoadFile` throws
  `LlamaStateException`; evaluate the prompt again and save a new state file.
- `LlamaEngine.create`, `ChatSession` and `ChatTemplateEngine.parse` retain
  trailing reply whitespace in all chat formats. Trim text explicitly when
  exact comparisons should ignore it. `ChatSession` still removes that
  whitespace when storing assistant turns, so its next prompt is unchanged.
- Multimodal GGUF requests place image and audio parts where their messages
  put them, and do not duplicate the model's media wrappers. Quoted media
  placeholder strings stay text; where the runtime would treat one as media,
  it receives a zero-width space after its first character. That character
  can appear in the response. Recheck prompts that depended on the old media
  ordering or wrappers.
- A native projector without the requested image or audio encoder now
  throws `LlamaUnsupportedException`; update code that caught only
  `LlamaInferenceException` for that failure. Invalid or raising chat
  templates throw `LlamaInferenceException` with their template message.
- LiteRT-LM engine-creation failures with `ComputeDevice.auto` or
  `ComputeDevice.cpu` throw `LlamaModelException` on first use. Update code
  that previously caught `LlamaInferenceException` or `StateError` there.
  With native LiteRT-LM `v0.18.0`, custom Qwen 3 templates should accept both
  string content and typed text-part lists. Native registered string-content
  bundles receive text again; this repair does not cover Web or the runtime's
  single-turn `is_appending_to_prefill` form. See
  [Chat templates](https://llamadart.leehack.com/docs/guides/chat-template-and-parsing#litert-lm-template-registry).
- `llamadart_native_runtimes: all` includes the image runtime where it is
  published. Use `[llama_cpp, litert_lm]` or leave the key unset (without
  Flutter Edge AI packages, see below) to keep the prior two-runtime selection
  on other platforms. On Flutter iOS/macOS,
  adding `llamadart_stable_diffusion_flutter` selects the image runtime even
  with that explicit list or an unset key. To omit it on those Apple targets,
  also omit or remove the image companion dependency. Flutter iOS/macOS need
  that companion to include the image runtime through SwiftPM when using `all`.
- Apps whose pubspec, or any member of the same pub workspace, also depends on
  `flutter_edge_ai_llama` or `flutter_edge_ai_litertlm` no longer get the
  LiteRT-LM runtime by default: with the key unset, `both` or `all`, the build
  hook leaves `litert_lm` out and prints a `warning: llamadart:` line. To keep
  loading `.litertlm` models through llamadart next to `flutter_edge_ai_llama`,
  set `llamadart_native_runtimes: [llama_cpp, litert_lm]` in the app or
  workspace-root `pubspec.yaml`. Next to `flutter_edge_ai_litertlm`, naming
  `litert_lm` (or depending on `llamadart_litert_lm_flutter` on iOS/macOS)
  fails the build; set `[llama_cpp]` and remove that companion. See
  [Alongside Flutter Edge AI](https://llamadart.leehack.com/docs/platforms/native-build-hooks#alongside-flutter-edge-ai).
- On an iOS simulator `GpuBackend.auto` now runs llama.cpp on the CPU
  ([#950](https://github.com/leehack/llamadart/issues/950)), so simulator
  timings are CPU timings. An explicit `GpuBackend.metal` still uses Metal
  there and logs a warning; iOS devices and macOS are unchanged.

LiteRT-LM automatic tool loops and strict structured output remain unsupported
on the pinned runtime. The declared iOS 16.4 deployment floor still needs
runtime qualification; these version updates do not establish it.

## `0.10.x` -> `0.11.0`: image generation engine API

Image generation is a Preview, and this release changes its API with no
deprecation period, to the pattern every llamadart engine will share: a
model of `ModelSource` files, `params:` for runtime settings, `download:`
for `ModelLoadOptions`, and generation settings on the request. The library
no longer has model presets or `String` paths.

1. **A model is a main file plus components, each a `ModelSource`.**
   `ImageGenerationModel.sdxs`, `sdTurbo`, `sdxlLightning`, `flux1Schnell`,
   `sd35LargeTurbo`, `zImageTurbo` and `custom`, `ImageGenerationModelFiles`,
   `ImageGenerationModelFamily` and `ImageGenerationModel.family` are gone.
   `load` downloads each file if needed and assigns its role from its
   header, so list files in any order:

   ```dart
   // Before
   final engine = await ImageGenerationEngine.load(
     ImageGenerationModel.flux1Schnell(
       diffusionModelPath: fluxPath,
       clipLPath: clipLPath,
       t5xxlPath: t5xxlPath,
       vaePath: aePath,
     ),
     options: const ImageGenerationOptions(device: ImageGenerationDevice.gpu),
   );
   final result = await engine.generateImage(
     const ImageGenerationRequest(prompt: 'a red fox'),
   );
   // After
   final engine = await ImageGenerationEngine.load(
     ImageGenerationModel(
       ModelSource.path(fluxPath),
       components: [
         for (final path in [aePath, clipLPath, t5xxlPath])
           ImageModelComponent.auto(ModelSource.path(path)),
       ],
     ),
     params: const ImageModelParams(device: ComputeDevice.gpu),
   );
   final result = await engine.generateImage(
     const ImageGenerationRequest(
       prompt: 'a red fox',
       width: 1024,
       height: 1024,
       steps: 4,
       guidanceScale: 1,
     ),
   );
   ```

   A file the header check cannot classify, such as a `.ckpt`, takes an
   explicit role: `ImageModelComponent(source, role: ImageModelRole.vae)`,
   or `ImageGenerationModel(source, role: ImageModelRole.checkpoint)`.
   `load` now refuses LoRA and ControlNet files, two files in one role, and
   a VAE or TAESD for other latent channels than the diffusion model's.

2. **Generation settings move to the request.** `ImageGenerationDefaults`
   is gone; an unset request size is 512x512, steps 20 and guidance 7. Set
   each former preset's values on the request, as in the
   [image generation guide's recipes](https://llamadart.leehack.com/docs/guides/image-generation#recipes):

   | 0.10.0 preset | Files | Request settings |
   | --- | --- | --- |
   | `sdxs(path)` | the checkpoint | `steps: 1, guidanceScale: 1` |
   | `sdTurbo(path, taesdPath:)` | the checkpoint, optional TAESD | `steps: 1, guidanceScale: 1` |
   | `sdxlLightning(path, vaePath:, taesdPath:)` | the checkpoint, optional VAE or TAESDXL | `width: 1024, height: 1024, steps: 4, guidanceScale: 1, sampler: euler, scheduler: sgmUniform` |
   | `flux1Schnell(...)` | diffusion model, `ae` or TAEF1, CLIP-L, T5-XXL | `width: 1024, height: 1024, steps: 4, guidanceScale: 1` |
   | `sd35LargeTurbo(...)` | diffusion model, TAESD3 or VAE, CLIP-L, CLIP-G, T5-XXL | `width: 1024, height: 1024, steps: 4, guidanceScale: 1` |
   | `zImageTurbo(...)` | diffusion model, `ae`, Qwen3 `llm` | `width: 1024, height: 1024, steps: 8, guidanceScale: 1` |
   | `custom(files, defaults:)` | the same files | the former `defaults` |

   `warmUp` takes `guidanceScale` too, so pass the size and guidance you
   generate with.

3. **`load` takes `params:`, `download:`, `onProgress:` and `store:`.**
   `ImageGenerationOptions` is now `ImageModelParams` (the engine's
   `options` getter is now `params`), and `ImageGenerationDevice` the shared
   `ComputeDevice`. `download:` takes `ModelLoadOptions` for remote files
   (cache, auth, retries, cancellation); `ModelLoadOptions.sha256` verifies a
   single-file model and throws `LlamaUnsupportedException` for several
   files, since one checksum cannot cover them. `store: ModelFileStore(resolver: ...,
   downloadManager: ...)` replaces the resolver and download manager.

4. **Errors name files by position, not path.** A missing or unusable file
   is "the main file" or "component N".

## `0.10.x` -> `0.11.0`: `LlamaEngine.load` and `setModel`

`LlamaEngine` loads like the other engines: `LlamaEngine.load` creates an
engine and loads a `LlamaModel`, and `setModel` loads or replaces the model
of an engine you already have. `loadModel`, `loadModelSource`,
`loadModelFromUrl` and `loadMultimodalProjector` are deprecated and keep
working until 1.0.

1. **Load a model and its projector in one call.** Runtime settings are
   `params:` and download settings are `download:`. The load is atomic: when
   it throws, the engine and its backend are disposed and nothing stays
   loaded.

   ```dart
   // Before
   final engine = LlamaEngine(LlamaBackend());
   await engine.loadModelSource(
     ModelSource.parse('hf://owner/repo/model.gguf'),
     modelParams: const ModelParams(contextSize: 4096),
     options: ModelLoadOptions(bearerToken: token),
     onProgress: (progress) => print(progress.fraction),
   );
   try {
     await engine.loadMultimodalProjectorSource(
       ModelSource.parse('hf://owner/repo/mmproj.gguf'),
     );
   } catch (_) {
     await engine.unloadModel();
     rethrow;
   }
   // After
   final engine = await LlamaEngine.load(
     LlamaModel(
       ModelSource.parse('hf://owner/repo/model.gguf'),
       projector: ModelSource.parse('hf://owner/repo/mmproj.gguf'),
     ),
     params: const ModelParams(contextSize: 4096),
     download: ModelLoadOptions(bearerToken: token),
     onProgress: (progress) => print(progress.fraction),
   );
   ```

   A local file is `ModelSource.path(path)`, and `ModelSource.parse` takes a
   path, an `http(s)` URL or an `hf://` reference. A custom resolver or
   download manager goes in `store: ModelFileStore(...)`. `onProgress`
   reports the model and its projector together: with a projector,
   `totalBytes` and `fraction` are null until the model has downloaded and
   the projector reports its size, so show `receivedBytes` until then.

2. **Switch models with `setModel`.** It replaces the loaded model, so the
   `unloadModel()` before a second load is no longer needed. The loaded
   model keeps serving until every file of the new one has downloaded; a
   download that fails or is cancelled leaves it loaded. A load that fails
   after that leaves nothing loaded. On the Web the runtime fetches the
   files itself, so `setModel` unloads the loaded model before the fetch, and
   a fetch that fails leaves nothing loaded.

   ```dart
   // Before
   await engine.unloadModel();
   await engine.loadModel('/models/other.gguf', modelParams: params);
   // After
   await engine.setModel(
     LlamaModel(ModelSource.path('/models/other.gguf')),
     params: params,
   );
   ```

   While `setModel` runs, another `setModel` and `unloadModel()` throw
   `LlamaStateException`; stop it with `download`'s cancel token.
   `dispose()` stops its downloads at once, and the call throws
   `LlamaStateException`.

3. **`loadMultimodalProjectorSource` takes `download:`.** `options:` is the
   deprecated name; passing both throws `LlamaArgumentException`. Use the
   method to change the projector of a loaded model; load a model with its
   projector as in step 1. `unloadModel()` and `dispose()` now stop its
   download, and the load throws `LlamaStateException` instead of
   `LlamaContextException`.

4. **What differs from the deprecated loaders.**
   - A local file takes only `download`'s cancel token and, for a model
     without a projector, its `sha256`. `loadModelSource` threw
     `LlamaUnsupportedException` for a local path with a bearer token,
     headers, cache directory, cache policy, resume or retry setting;
     `load` and `setModel` do not apply them to a local file.
   - `download`'s bearer token and headers go to one origin only: a model
     and projector on different hosts throw `LlamaArgumentException` when
     they are set.
   - `ModelLoadOptions.sha256` with a projector throws
     `LlamaUnsupportedException`, since it cannot name two files.
   - A projector for a LiteRT-LM model and `ComputeDevice.npu` for a GGUF
     throw `LlamaUnsupportedException` before anything downloads, when the
     `ModelSource.format` or file name gives the format.
   - On the Web, a `ModelSource.path` is a URL relative to the document, or
     a `blob:` URL. It used to throw `LlamaUnsupportedException`, and now
     loads in the deprecated `loadModelSource`, `setLoraSource` and draft
     models too.
   - A subclass that overrides `loadModel` no longer sees loads made
     through `load` and `setModel`. Fake a `LlamaBackend` in tests, or
     override `setModel`.
   - `load` and `setModel` check a local file through the download manager
     before the backend sees it, so a test that loads a made-up path such
     as `model.gguf` into a fake backend now throws `LlamaModelException`
     (`Local model file does not exist`). Give the test a real temporary
     file, or a fake `ModelDownloadManager` in `store:` or
     `LlamaEngine(backend, modelDownloadManager: ...)`.
   - A `blob:` URL goes in `ModelSource.path`; `ModelSource.parse` accepts
     only paths, `http(s)` URLs and `hf://` references.
   - A `LlamaEngineObserver` sees a whole `load` or `setModel` call as one
     model load, with its downloads, so a file that is missing or fails to
     download ends that operation with an error. `loadModelSource` reports
     only the load that follows its download.

5. **New members on `LlamaEngine`.** A class that `implements LlamaEngine`
   must add `setModel`, and an override of `loadMultimodalProjectorSource`
   must add the `download` parameter and make `options` nullable.

6. **Messages.** A request before a load throws `LlamaContextException`
   with `Engine not ready: no model is loaded. Call LlamaEngine.load or
   setModel first.` Code that matched the earlier text should catch the
   exception type instead.

## `0.10.x` -> `0.11.0`: one task shape for image and speech engines

`ImageGenerationTask`, `SpeechToTextTask` and `TextToSpeechTask` share one
shape: `events` carries progress only, `done` reports how the task ended and
never throws, the new `result` returns the result or throws, and `cancel()`
stops only that task.

1. **`ImageGenerationEngine.generate` returns a `Future` (Preview).** Await
   it for the task; invalid requests, a disposed engine and a running
   generation now fail that future instead of throwing synchronously. The
   one-generation slot is still taken when `generate` is called.

   ```dart
   // Before
   final task = engine.generate(request);
   // After
   final task = await engine.generate(request);
   ```

2. **Task `events` no longer carry errors.** A failed task closes `events`
   without a final event. Code that caught the failure from the stream (an
   `onError` handler, or `try` around `await for`) reads it from `result`
   or `done` instead:

   ```dart
   // Before
   try {
     await for (final event in task.events) {
       if (event is TextToSpeechFinalEvent) save(event.result);
     }
   } on LlamaException catch (error) {
     report(error);
   }
   // After
   task.events.listen(showProgress);
   try {
     save(await task.result);
   } on LlamaException catch (error) {
     report(error); // LlamaStateException when the task was cancelled
   }
   ```

   `SpeechToTextStreamingSession` is unchanged: its `events` still report a
   failure as a stream error as well as through `done`, and its `cancel()`
   returns a `Future`, because it ends a live input stream rather than one
   result.

3. **`SpeechToTextTask.cancel()` stops only its own task.** A prompt-adapter
   task used to call `LlamaEngine.cancelGeneration`, which also ended chat,
   tool-loop and other requests on the same engine. It now cancels only the
   task's own generation. Call `LlamaEngine.cancelGeneration` yourself if you
   relied on that.

## `0.10.x` -> `0.11.0`: decision engine load and attach

`DecisionEngine` follows the shared engine pattern, and the `String`-path
`DecisionEngine.load(engine, headPath:, configPath:)` is removed.

1. **Keep your engine: switch to `attach`.** The one-line change:

   ```dart
   // Before
   final decisions = await DecisionEngine.load(
     engine,
     headPath: headPath,
     configPath: configPath,
   );
   // After
   final decisions = await DecisionEngine.attach(
     engine,
     head: ModelSource.path(headPath),
     config: configPath == null ? null : ModelSource.path(configPath),
   );
   ```

   The head and config now resolve through the engine's download manager,
   so `hf://` and URL sources work too, and a missing local file throws
   `LlamaModelException` before the head loads. `dispose()` still frees only
   the head. On Web a path is still a URL resolved against the document base
   URL; a `blob:` URL goes in `ModelSource.path` too.

2. **Or let `load` own the engine.** Describe the files as `ModelSource`s;
   `load` downloads them, loads the encoder with the 512-token context
   decisions need, and loads the head. `dispose()` frees everything:

   ```dart
   // Before
   final engine = LlamaEngine(LlamaBackend());
   await engine.loadModelSource(
     encoder,
     modelParams: const ModelParams(contextSize: 512, gpuLayers: 0),
   );
   final headFile = await engine.modelDownloadManager.ensureModel(head);
   final decisions = await DecisionEngine.load(
     engine,
     headPath: headFile.filePath,
   );
   // ...
   await decisions.dispose();
   await engine.dispose();
   // After
   final decisions = await DecisionEngine.load(
     DecisionModel(encoder: encoder, head: head),
     params: const DecisionModelParams(device: ComputeDevice.cpu),
   );
   // ...
   await decisions.dispose();
   ```

   `configPath:` becomes `DecisionModel.config`. `download:` takes
   `ModelLoadOptions`, `store:` a `ModelFileStore` (for example
   `ModelFileStore(downloadManager: myManager)`), and `onProgress` reports all
   files together. Read the backend name from `await decisions.capabilities`.
   To load an encoder yourself for `attach`, use
   `const DecisionModelParams().encoderModelParams`.

3. **Missing-config hint.** The error for a head without `laya.config`
   metadata now asks for "the head's rl_agent_config.json as its config"
   instead of naming `configPath`; match on `laya.config` if you parse it.

## `0.10.x` -> `0.11.0`: TranslateGemma language codes

`LlamaEngine.create`, `createStructuredJson` and `chatTemplate` deprecate
`sourceLangCode` and `targetLangCode`. Pass the codes in
`chatTemplateKwargs`, as llama.cpp's `chat_template_kwargs` does; the
parameters keep working, with deprecation warnings, until 1.0:

```dart
// Before
engine.create(messages, sourceLangCode: 'en', targetLangCode: 'ko');
// After
engine.create(
  messages,
  chatTemplateKwargs: const {'source_lang_code': 'en', 'target_lang_code': 'ko'},
);
```

A code passed as a parameter replaces the same key in `chatTemplateKwargs`.
A custom `BackendNativeChatGeneration` that read `sourceLangCode` or
`targetLangCode` in `generateChat` gets them from `LlamaEngine` only in
`chatTemplateKwargs` now.

## `0.10.x` -> `0.11.0`: mobile model cache default

No source change is required. On Android and iOS, `LlamaEngine`,
`ModelDownloadController` and `DefaultModelDownloadManager()` (and `auto()`
without a mobile directory) now cache models in `llamadart/models` under the
app's cache directory, the one Flutter's `getApplicationCacheDirectory()`
returns, instead of `Directory.systemTemp/llamadart/models`. Models cached
under the old path download once more; the old copies are left for the OS to
clear. Apps that already pass a directory are unaffected. To pick another
directory for every default download, set
`DefaultModelDownloadManager.globalCacheDirectory` before the first load.

## `0.10.x` -> `0.11.0`: typed argument errors and one logging API

1. **Argument and state errors join the `LlamaException` hierarchy.** Catch
   the new types, or `LlamaException` for all of them:

   | Call | Before | After |
   | --- | --- | --- |
   | `ModelParams.validate()` | `ArgumentError` | `LlamaArgumentException` |
   | A backend's own model load or context create with invalid `ModelParams` | `ArgumentError` or `Exception` | `LlamaArgumentException` |
   | `ModelDownloadController.start` with `options.cancelToken` | `ArgumentError` | `LlamaArgumentException` |
   | `ModelDownloadController.start` while a task runs, `retry` before `start`, either after `dispose` | `StateError` | `LlamaStateException` |
   | Web `LlamaBackend()` or `WebGpuLlamaBackend` calls before a model load | `StateError` | `LlamaStateException` |

   ```dart
   // Before
   try {
     params.validate();
   } on ArgumentError catch (e) {
     print(e.name);
   }
   // After
   try {
     params.validate();
   } on LlamaArgumentException catch (e) {
     print(e.name); // also e.invalidValue and e.message
   }
   ```

   Model loads already reported invalid `ModelParams` as
   `LlamaModelException`, and still do.

2. **A failed load's `details` is a `String`.** `LlamaModelException.details`
   from `loadModel`, `loadModelFromUrl`, `loadModelSource` and
   `loadMultimodalProjector` was a `{type, message}` map; it is now the cause's
   message, such as `Model file not found: /models/m.gguf`, with URL secrets
   still redacted.

3. **One logging API.** `LlamaLogging.configure` sets the Dart-side level,
   the native level (defaulting to the Dart-side level) and the handler for
   the whole library. The old calls keep working, with deprecation warnings,
   until 1.0:

   | Before | After |
   | --- | --- |
   | `LlamaEngine.configureLogging(level: l, handler: h)` | `LlamaLogging.configure(level: l, nativeLevel: n, handler: h)` |
   | `engine.setLogLevel(l)` | `LlamaLogging.configure(level: l)` |
   | `engine.setDartLogLevel(d)` + `engine.setNativeLogLevel(n)` | `LlamaLogging.configure(level: d, nativeLevel: n)` |
   | `engine.dartLogLevel`, `engine.nativeLogLevel` | `LlamaLogging.level`, `LlamaLogging.nativeLevel` |

   `configure` replaces the handler too, so pass it on every call that should
   keep it. Levels are now library-wide: `engine.setNativeLogLevel` on one
   engine changes every engine, and `LlamaEngine.configureLogging` also updates
   running worker isolates.

## `0.10.x` -> `0.11.0`: speech engine load, attach and adapters

`SpeechToTextEngine` and `TextToSpeechEngine` follow the shared engine
pattern: `load` takes a model of `ModelSource` files and owns what it loads,
and an adapter, not a profile enum, says how to run the model. The old
constructors, `SpeechToTextModelProfile`, `TextToSpeechModelProfile` and the
`modelProfile` getters keep working, with deprecation warnings, until 1.0.

1. **Load the model, or attach to an engine you keep.** `load` creates a
   `LlamaEngine`, loads the model and projector, checks `capabilities`, and
   throws `LlamaUnsupportedException` when the model cannot recognize speech.
   `dispose()` then disposes that engine:

   ```dart
   // Before
   final engine = LlamaEngine(LlamaBackend());
   await engine.loadModel('/models/Qwen3-ASR-0.6B-Q8_0.gguf');
   await engine.loadMultimodalProjector('/models/mmproj-Qwen3-ASR-0.6B-Q8_0.gguf');
   final recognizer = SpeechToTextEngine(
     engine,
     modelProfile: SpeechToTextModelProfile.qwen3Asr,
   );
   // After
   final recognizer = await SpeechToTextEngine.load(
     SpeechToTextModel(
       ModelSource.path('/models/Qwen3-ASR-0.6B-Q8_0.gguf'),
       projector: ModelSource.path('/models/mmproj-Qwen3-ASR-0.6B-Q8_0.gguf'),
       adapter: const Qwen3AsrAdapter(),
     ),
   );
   try {
     final result = await recognizer.transcribeOnce(request);
   } finally {
     await recognizer.dispose();
   }
   ```

   Remote sources download into the model cache. `download:` takes
   `ModelLoadOptions` for every remote file and `onProgress:` reports the
   files together (on Web, where the browser fetches each file, only the
   model's fetch reports progress, up to 0.5 with a projector); a local file
   takes only the cancel token, and
   `bearerToken` and `headers` go to one host only, so remote files on two
   hosts with them set throw `LlamaArgumentException`.
   `ModelLoadOptions.sha256` throws `LlamaUnsupportedException`, since one
   checksum cannot cover two files. `params:` takes `ModelParams`, `store:` a
   `ModelFileStore` with your own resolver or download manager, and
   `backend:` the `LlamaBackend`, which the speech engine then owns and
   disposes. When `load` throws, nothing stays loaded.

   To share a `LlamaEngine` you load yourself, for example with chat, use
   `SpeechToTextEngine.attach(engine, adapter: const Qwen3AsrAdapter())`.
   Its `dispose()` cancels its task and leaves the engine loaded.

2. **Dedicated LiteRT-LM ASR is a model with a `LiteRtLmAsrAdapter`.** The
   runtime settings of `LiteRtLmAsrRuntimeConfig` and `libraryPath` move to
   the adapter, and the files become `ModelSource`s:

   ```dart
   // Before
   final recognizer = SpeechToTextEngine.liteRtLm(
     const LiteRtLmAsrRuntimeConfig(
       modelPath: '/models/moonshine_tiny.tflite',
       tokenizerPath: '/models/tokenizer.json',
       modelPreset: LiteRtLmAsrModelPreset.moonshineTiny,
     ),
   );
   // After
   final recognizer = await SpeechToTextEngine.load(
     SpeechToTextModel(
       ModelSource.path('/models/moonshine_tiny.tflite'),
       tokenizer: ModelSource.path('/models/tokenizer.json'),
       adapter: const LiteRtLmAsrAdapter(LiteRtLmAsrModelPreset.moonshineTiny),
     ),
   );
   ```

   `load` probes the runtime before it downloads anything and throws
   `LlamaUnsupportedException` where it is unavailable, including on the web,
   where `SpeechToTextEngine.liteRtLm` returned a recognizer whose
   `capabilities` reported unsupported. `params:` and `backend:` must be
   null. The model and tokenizer can be URLs or Hugging Face files: `load`
   downloads them with `download:` and `onProgress:` as in step 1.
   `SpeechToTextEngine.liteRtLm` opens local files only and throws
   `LlamaUnsupportedException` for a remote source.

3. **Text to speech takes a `TextToSpeechModel`.**

   ```dart
   // Before
   final synthesizer = TextToSpeechEngine(
     engine,
     modelProfile: TextToSpeechModelProfile.qwen3Tts,
   );
   // After, loading the files
   final synthesizer = await TextToSpeechEngine.load(
     TextToSpeechModel(
       ModelSource.parse('hf://owner/repo/tts-model.gguf'),
       projector: ModelSource.parse('hf://owner/repo/mmproj-tts-model.gguf'),
       adapter: const Qwen3TtsAdapter(),
     ),
   );
   // After, keeping your engine
   final synthesizer = TextToSpeechEngine.attach(
     engine,
     adapter: const Qwen3TtsAdapter(),
   );
   ```

4. **Profiles become adapters.**

   | Before | After |
   | --- | --- |
   | `SpeechToTextEngine(engine, modelProfile: SpeechToTextModelProfile.qwen3Asr)` | `SpeechToTextEngine.attach(engine, adapter: const Qwen3AsrAdapter())`, or `load` |
   | `SpeechToTextEngine.liteRtLm(config, libraryPath: path)` | `SpeechToTextEngine.load(SpeechToTextModel(model, tokenizer: tokenizer, adapter: LiteRtLmAsrAdapter(preset, libraryPath: path)))` |
   | `TextToSpeechEngine(engine, modelProfile: TextToSpeechModelProfile.qwen3Tts)` | `TextToSpeechEngine.attach(engine, adapter: const Qwen3TtsAdapter())`, or `load` |
   | `recognizer.modelProfile`, `synthesizer.modelProfile` | `recognizer.adapter`, `synthesizer.adapter` |

   The deprecated `modelProfile` getters throw `LlamaStateException` for an
   adapter with no profile, such as your own `SpeechToTextPromptAdapter`.

5. **Dispose the speech engine.** `dispose()` is new: it cancels a running
   task or stream, waits for it to stop, and disposes the engine `load`
   created. It is safe to call twice. Afterwards `transcribe`, `startStream`
   and `synthesize` throw `LlamaStateException`, and `capabilities` reports
   unsupported. Code that used the deprecated constructors and disposed the
   `LlamaEngine` itself keeps working. A class that `implements`
   `SpeechToTextEngine` or `TextToSpeechEngine`, such as a test fake, must
   add `dispose()`, `isDisposed`, `adapter` and `transcribeOnce` or
   `synthesizeOnce`.

## `0.10.x` -> `0.11.0`: `ModelSource` for LoRA adapters, draft models and speech files

LoRA adapters, speculative draft models and LiteRT-LM ASR files take a
`ModelSource`, so a remote file downloads into the model cache like a model.
The `String` path forms keep working, with deprecation warnings, until 1.0:

| Before | After |
| --- | --- |
| `engine.setLora(path, scale: s)` | `engine.setLoraSource(ModelSource.path(path), scale: s)` |
| `engine.removeLora(path)` | `engine.removeLoraSource(ModelSource.path(path))` |
| `LoraAdapterConfig(path: path, scale: s)` | `LoraAdapterConfig.source(ModelSource.path(path), scale: s)` |
| `SpeculativeDecodingConfig.draftSimple(draftModelPath: path)` (and the other constructors) | `SpeculativeDecodingConfig.draftSimple(draftModel: ModelSource.path(path))` |
| `LiteRtLmAsrRuntimeConfig(modelPath: m, tokenizerPath: t, ...)` | `LiteRtLmAsrRuntimeConfig.source(model: ModelSource.path(m), tokenizer: ModelSource.path(t), ...)`; to recognize speech, `SpeechToTextEngine.load` as in [the speech migration](#010x---0110-speech-engine-load-attach-and-adapters) |

```dart
// Before
await engine.setLora('/models/lora/domain.gguf', scale: 0.7);
final config = LiteRtLmAsrRuntimeConfig(
  modelPath: '/models/moonshine_tiny.tflite',
  tokenizerPath: '/models/tokenizer.json',
  modelPreset: LiteRtLmAsrModelPreset.moonshineTiny,
);
// After
await engine.setLoraSource(
  ModelSource.path('/models/lora/domain.gguf'),
  scale: 0.7,
);
final config = LiteRtLmAsrRuntimeConfig.source(
  model: ModelSource.path('/models/moonshine_tiny.tflite'),
  tokenizer: ModelSource.path('/models/tokenizer.json'),
  modelPreset: LiteRtLmAsrModelPreset.moonshineTiny,
);
```

- A local path, relative ones included, stays `ModelSource.path(path)`. On
  WebGPU, where these paths were URLs, use `ModelSource.parse(url)`; a local
  path there throws `LlamaUnsupportedException`.
- For a page-relative URL on the web (such as `models/adapter.gguf`),
  resolve it against the page: `ModelSource.url(Uri.base.resolve(path))`.
- `ModelSource` and `const`: `ModelSource.path` is not a `const`
  constructor, so drop `const` from a `ModelParams`, `GenerationParams` or
  `LiteRtLmAsrRuntimeConfig` that now holds one.
- Remove an adapter with the same source it was set from:
  `removeLoraSource` matches sources, not paths.
- `draftModelDownload`, `setLoraSource(download:, onProgress:)` and
  `LoraAdapterConfig.source(source, download:)` set the download options
  for remote files. Remote LiteRT-LM ASR files download through
  `SpeechToTextEngine.load`; `LiteRtLmAsrRuntimeConfig` holds local files. A `ModelParams.loras` adapter never
  takes the model load's bearer token, headers or `sha256`; give it its own
  `download:` when its host needs credentials.
- A draft model downloads once per loaded model; `draftModelDownload` rejects
  `ModelCachePolicy.noCache` and `refresh`.

## `0.10.x` -> `0.11.0`: optional `ToolDefinition.handler`

`ToolDefinition.handler` is a `ToolHandler?`, so a tool the app runs itself
can leave it out. A direct call to the handler no longer compiles: call
`invoke`, which throws `LlamaStateException` for a tool without a handler, or
null-check `handler`:

```dart
// Before
final result = await tool.handler(ToolParams(args));
// After
final result = await tool.invoke(args);
```

## `0.10.x` -> `0.11.0`: app, backend and bindings entrypoints

`package:llamadart/llamadart.dart` is now the app API only. Code that loads
models, generates and uses the speech, image and decision engines needs no
change. Custom backends, backend test fakes and raw runtime access import one
of two new libraries.

1. **Raw llama.cpp FFI: `package:llamadart/llama_cpp_bindings.dart`.** The
   ffigen bindings (`llama_backend_init`, `llama_decode`, `ggml_*`, `mtmd_*`
   and their structs) are no longer in the app API. They are native only, and
   any release that updates llama.cpp can change them:

   ```dart
   import 'package:llamadart/llama_cpp_bindings.dart';
   import 'package:llamadart/llamadart.dart';
   ```

2. **Backend SPI: `package:llamadart/backend.dart`.** These names move there:
   - `BackendAvailability`, `BackendBatchEmbeddings`, `BackendDartLogLevel`,
     `BackendDecision`, `BackendDecisionCapabilities`,
     `BackendDecisionHeadInfo`, `BackendDecisionOutput`,
     `BackendDecisionSequence`, `BackendEmbeddings`,
     `BackendEmbeddingsSupport`, `BackendGenerationCapabilities`,
     `BackendGenerationCapabilitiesSupport`, `BackendGpuEnumeration`,
     `BackendGrammarConstraintsSupport`, `BackendLazyGrammarSupport`,
     `BackendModelFileTypeDiagnostics`, `BackendNativeChatGeneration`,
     `BackendNextTokenScoring`, `BackendNextTokenScoringSupport`,
     `BackendPerformanceDiagnostics`, `BackendPromptSpeechToTextSupport`,
     `BackendRuntimeDiagnostics`, `BackendStatePersistence`,
     `BackendStatePersistenceSupport`, `BackendTextToSpeech`,
     `BackendTextToSpeechCapabilities`, `BackendTextToSpeechPhase`,
     `BackendTextToSpeechProgress`, `BackendTextToSpeechRequest` and
     `BackendTextToSpeechResult`.
   - `LiteRtLmBackend`, `LiteRtLmRuntimeClient`, `LiteRtLmRuntimeMetrics` and
     `LiteRtLmRuntimeResult`.
   - `LiteRtLmAsrRuntimeSession`, `LiteRtLmAsrPushResult`,
     `LiteRtLmAsrProcessResult` and `LiteRtLmAsrProcessState`.

   `LlamaBackend`, `BackendPerfContextData`, `BackendTextToSpeechModel`,
   `StateLoadResult`, `LiteRtLmAsrBackend`, `LiteRtLmAsrModelPreset` and
   `LiteRtLmAsrRuntimeConfig` stay in the app API; `backend.dart` exports the
   first four too. Add the import next to the app one:

   ```dart
   import 'package:llamadart/backend.dart';
   import 'package:llamadart/llamadart.dart';
   ```

3. **Engine hooks are extension members.** `modelHandle`, `contextHandle`,
   `backendTextToSpeechCapabilities`, `synthesizeTextToSpeechBackend`,
   `cancelTextToSpeechBackend`, `backendDecisionCapabilities`,
   `loadDecisionHeadBackend`, `runDecisionBackend` and
   `freeDecisionHeadBackend` move from `LlamaEngine` to the
   `LlamaEngineBackendHooks` extension in `backend.dart`. Statically typed
   calls keep working once `backend.dart` is imported. Extension members
   resolve at compile time, so a call through `dynamic`, such as
   `(engine as dynamic).modelHandle`, throws `NoSuchMethodError`; type the
   receiver as `LlamaEngine`. A `LlamaEngine` subclass that overrode
   one no longer intercepts it, and the analyzer reports only an
   `override_on_non_overriding_member` warning. A fake that
   `implements LlamaEngine` is bypassed the same way wherever it is typed as
   `LlamaEngine`, as inside `TextToSpeechEngine` and `DecisionEngine`: the
   extension runs instead of the fake's members and reads engine state the
   fake lacks, so the call fails with `NoSuchMethodError`. In both cases, fake
   at the backend instead:

   ```dart
   // Before
   class FakeEngine extends LlamaEngine {
     FakeEngine() : super(LlamaBackend());
     @override
     Future<BackendTextToSpeechResult> synthesizeTextToSpeechBackend(
       BackendTextToSpeechRequest request, {
       void Function(BackendTextToSpeechProgress progress)? onProgress,
     }) async => fakeResult;
   }
   // After
   class FakeBackend implements LlamaBackend, BackendTextToSpeech {
     @override
     Future<BackendTextToSpeechResult> synthesizeTextToSpeech(
       int contextHandle,
       int mmContextHandle,
       BackendTextToSpeechRequest request, {
       void Function(BackendTextToSpeechProgress progress)? onProgress,
     }) async => fakeResult;
     // ... the rest of LlamaBackend and BackendTextToSpeech
   }
   ```

4. **Removed deprecated APIs.** `LiteRtLmBenchmarkClient`,
   `LiteRtLmBenchmarkMetrics` and `LiteRtLmBenchmarkResult` are gone; use
   `LiteRtLmRuntimeClient`, `LiteRtLmRuntimeMetrics` and
   `LiteRtLmRuntimeResult`. `LiteRtLmRuntimeClient.conversationTokenCount`
   and `replaceConversationWithClone` are gone with no replacement.

## `0.10.x` -> `0.11.0`: one `ComputeDevice` for every engine

`ModelParams.device` takes a `ComputeDevice` and applies to llama.cpp and
LiteRT-LM, as `ImageModelParams.device` and `DecisionModelParams.device`
already do. `ModelParams.liteRtLmBackend`, `LiteRtLmBackendPreference` and
`LiteRtLmBackend(preferredBackend:)` are deprecated and keep working until
1.0.

1. **Replace the LiteRT-LM selector with `device`.**

   ```dart
   // Before
   final engine = LlamaEngine(LiteRtLmBackend(preferredBackend: 'gpu'));
   await engine.loadModel(
     path,
     modelParams: const ModelParams(
       liteRtLmBackend: LiteRtLmBackendPreference.gpu,
     ),
   );
   // After
   final engine = await LlamaEngine.load(
     LlamaModel(ModelSource.path(path)),
     params: const ModelParams(device: ComputeDevice.gpu),
   );
   ```

   `ComputeDevice.auto`, the default, keeps each runtime's default device, so
   code that sets neither field is unchanged. Setting `device` together with
   `liteRtLmBackend` throws `LlamaArgumentException`; setting it with
   `LiteRtLmBackend(preferredBackend:)` throws `LlamaUnsupportedException`.
   Code that still constructs `LiteRtLmBackend` imports it from
   `package:llamadart/backend.dart`, as the section above describes.

2. **An explicit device is a requirement.** With `device: cpu`, `gpu` or
   `npu`, a device the runtime and platform cannot provide throws
   `LlamaUnsupportedException`, not the `LlamaModelException` the deprecated
   selector throws, and nothing falls back to another device:
   - llama.cpp `gpu` without a GPU module or device, which `preferredBackend`
     used to load on the CPU with a warning, now throws; on Android `gpu`
     uses Vulkan, which `auto` does not.
   - On the Web, `gpu` needs a WebGPU adapter, and the llama.cpp bridge no
     longer retries a failed GPU load on the CPU.
   - Native LiteRT-LM creates its engine on first use, so a GPU or NPU
     delegate that fails to start throws from the first generation or
     tokenizer call.

   Use `ComputeDevice.auto` to accept the runtime's default, or catch
   `LlamaException` to cover the old and new types.

3. **One `device` covers both runtimes.** Under `auto`, `gpuLayers` and
   `preferredBackend` still choose the LiteRT-LM backend as before. To run
   llama.cpp on the CPU and LiteRT-LM on the GPU from one `ModelParams`, keep
   the deprecated `liteRtLmBackend` with `device: auto`, or pick the params
   from `ModelSource.format`.

4. **`ModelParams.validate()` runs before the download.** `loadModel`,
   `loadModelSource` and `loadModelFromUrl` call it first, so an invalid
   combination throws `LlamaArgumentException` before anything downloads,
   where it used to fail the backend load as `LlamaModelException`. New
   rules reject `device: cpu` with a GPU `preferredBackend`, and `gpu` or
   `npu` with a CPU or BLAS `preferredBackend`, `gpuLayers: 0`, or
   `splitMode: ModelSplitMode.none` with a negative `mainGpu`.

5. **Decision models.** `DecisionModelParams.encoderModelParams` now carries
   `device` instead of `preferredBackend: GpuBackend.cpu` and `gpuLayers: 0`
   for `cpu`. `DecisionModelParams(device: ComputeDevice.gpu)` no longer asks
   the backend for GPU support before loading: the encoder loads on a GPU or
   the load throws `LlamaUnsupportedException`.

## `0.10.x` -> `0.11.0`: shared capabilities and terminal dispose

1. **Image capabilities are async; `runtimeCapabilities()` is removed.**
   `ImageGenerationEngine.capabilities` returns a `Future`, like every other
   engine's. It changes only when the engine is disposed, so read it once
   after `load` and keep it, for example in a Flutter `State`, instead of
   reading it in `build`. Probe the runtime before loading with
   `checkRuntime()`, which runs off the calling isolate:

   ```dart
   // Before
   final runtime = ImageGenerationEngine.runtimeCapabilities();
   print(engine.capabilities.backendName);
   // After
   final runtime = await ImageGenerationEngine.checkRuntime();
   final capabilities = await engine.capabilities;
   print(capabilities.backendName);
   ```

   `ImageGenerationCapabilities` and `DecisionCapabilities` now implement
   `EngineCapabilities`, so code that reads `isSupported`,
   `unsupportedReason` and `backendName` can take any engine's capabilities.

2. **`LlamaEngine.dispose()` is terminal.** A second call returns the same
   future instead of disposing the backend again. After it, a load or request
   throws `LlamaStateException` (requests used to throw
   `LlamaContextException`), `DecisionEngine.attach` throws
   `LlamaStateException`, and `capabilities` reports the engine as disposed.
   The backend queries `getBackendName`, `getAvailableBackends`,
   `isGpuSupported`, `getVramInfo`, `listGpuDevices` and
   `getResolvedGpuLayers`, which used to answer after `dispose`, now throw
   `LlamaStateException`; read them before disposing. Model queries such as
   `getMetadata` and `getContextSize` return their no-model values, as
   before. `unloadModel` and `cancelGeneration` do nothing. To switch models, call
   `setModel`; to start over after `dispose`, create a new
   `LlamaEngine`. A load running when `dispose` is called now throws
   `LlamaStateException` instead of completing, and its model is unloaded.
   A class that `implements LlamaEngine` must add `bool get isDisposed`.

3. **`supportsVision` and `supportsAudio` agree with `capabilities`.** On a
   LiteRT-LM bundle that takes media directly, they are now true without a
   multimodal projector. When the runtime cannot probe a projector, they
   are false instead of throwing `LlamaUnsupportedException`.

## `0.10.x` -> `0.11.0`: Apple companions, new members and stricter checks

1. **Flutter iOS/macOS apps update the companion packages with the core.**
   Core `0.11.0` pairs with `llamadart_llama_cpp_flutter` `0.0.21`,
   `llamadart_litert_lm_flutter` `0.0.13` and
   `llamadart_stable_diffusion_flutter` `0.0.2`. A `^0.0.x` constraint admits
   only that version, so edit each one the app uses:

   ```yaml
   dependencies:
     llamadart: ^0.11.0
     llamadart_llama_cpp_flutter: ^0.0.21
     llamadart_litert_lm_flutter: ^0.0.13
     llamadart_stable_diffusion_flutter: ^0.0.2
   ```

   An Apple build that resolves an older llama.cpp or stable_diffusion
   companion fails with `Incompatible Apple ... companion`.

2. **More members for a class that `implements` an app type.** `ChatSession`
   gains `createStructuredJson`, and `LlamaEngine` gains `runtime`,
   `capabilities`, `setLoraSource` and `removeLoraSource`, besides `setModel`
   and `isDisposed` above.

3. **An unknown `responseFormat` type or key throws.** A map with a
   misspelled `type` or key, such as `json_shema` or `schma`, used to generate
   unconstrained output. It now throws `LlamaUnsupportedException` before
   generation; a `null`-valued key counts as absent.

4. **Native `LlamaBackend()` picks the runtime from the file header.** An
   extensionless download now loads in the runtime its header names. A
   recognized header that contradicts the file's model extension or an
   explicit `format:` throws `LlamaModelFormatException`; rename the file or
   pass the matching `format:`.

## `0.9.x` -> `0.10.0`: typed errors, chat templates and model names

No public signature changes, but several calls now return or throw something
different. Check each item that your app uses.

1. **`ModelParams.chatTemplate` now drives llama.cpp chat.** Before, native
   llama.cpp and WebGPU ignored it in `LlamaEngine.create`,
   `LlamaEngine.chatTemplate` and `ChatSession`, and used the GGUF
   `tokenizer.chat_template`. Now a non-empty value renders the prompt and
   selects the tool-call and reasoning parser. If you set it only as a
   fallback, pass `null` to keep the GGUF template. The value is Jinja
   source, so a name such as `chatml` is not mapped to a built-in template.

2. **WebGPU `LlamaBackend.applyChatTemplate` throws for a template
   override.** Before, it ignored `customTemplate` and
   `ModelParams.chatTemplate` and returned `role: content` lines. Now it
   throws `LlamaUnsupportedException`. Render through
   `LlamaEngine.chatTemplate` or `LlamaEngine.create` instead, which apply
   the override in Dart on every backend.

3. **`LlamaCompletionChunk.model` is the file name.** Before, it held the
   load source: the full local path, the cache path, or the redacted URL.
   Now it is the last path segment, such as `qwen.gguf`, or `llama_model`
   when there is none or it contains URL syntax such as `?`, `#` or `@`
   (`data:` and `blob:` URLs report `llama_model` too). Compare it with
   the file name instead of the path:

   ```dart
   // Before
   if (chunk.model == modelPath) { ... }
   // After
   if (chunk.model == path.basename(modelPath)) { ... }
   ```

4. **`%` in local and cache paths stays literal.** Before,
   `loadModelSource` and `ModelCacheEntry` percent-decoded paths, so
   `qwen%2541.gguf` loaded a different file and a lone `%` threw
   `ArgumentError`. Now the path is used as written: pass the path as it is
   on disk, not percent-encoded.

5. **`ModelParams.loras` is applied at load on native llama.cpp and WebGPU.**
   Before, those backends ignored it and loaded the base model. Now each
   adapter is applied in order with its scale, and a load whose adapter
   cannot be applied fails: `LlamaUnsupportedException` for an unsupported
   adapter or WebGPU bridge assets without LoRA support (the minimum version
   is in the LoRA adapters guide), otherwise `LlamaModelException` with the
   adapter in `details`. Remove adapters you did not mean to apply, and catch
   both exceptions around `loadModel`.

6. **LiteRT-LM `ModelParams` rejections throw `LlamaUnsupportedException`.**
   Before, native and web LiteRT-LM wrapped them in `LlamaModelException`.
   This covers more than one LoRA adapter and a non-default adapter scale.

   ```dart
   // Before
   } on LlamaModelException catch (e) { ... }
   // After
   } on LlamaUnsupportedException catch (e) {
     // ModelParams option this runtime does not support.
   } on LlamaModelException catch (e) { ... }
   ```

7. **Media without a projector throws.** Before, image or audio parts sent
   to a GGUF model with no projector loaded were answered from the text
   alone on native llama.cpp and failed as `LlamaInferenceException` on
   WebGPU. Now both throw `LlamaUnsupportedException`, and native llama.cpp
   and LiteRT-LM throw it for `LlamaImageContent.url`. Load a projector with
   `loadMultimodalProjector` first, or drop media parts from requests and
   history when none is loaded; pass image bytes or a file instead of a URL.

## `0.8.9` -> `0.8.10`: model download/cache defaults

No source migration is required for existing calls: `DefaultModelDownloadManager`
constructors remain source-compatible, and the mobile-specific directory
arguments added to `DefaultModelDownloadManager.auto(...)` in `0.8.10` are
optional.

There are two intentional runtime default changes to be aware of:

1. `DefaultModelDownloadManager()` no longer defaults to the process temporary
   directory on desktop/server platforms. It now uses the same platform cache
   root as `DefaultModelDownloadManager.auto()`:

   | Platform | New default root |
   | --- | --- |
   | Linux | `$XDG_CACHE_HOME/llamadart/models`, or `$HOME/.cache/llamadart/models` when `XDG_CACHE_HOME` is unset |
   | macOS | `$HOME/Library/Caches/llamadart/models` |
   | Windows | `%LOCALAPPDATA%\llamadart\models`, then `%APPDATA%\llamadart\models`, then `%USERPROFILE%\AppData\Local\llamadart\models` |

   If a desktop/server embedder cannot expose a home/cache environment, the
   default constructor preserves compatibility by falling back to
   `Directory.systemTemp/llamadart/models`. Explicit `auto(...)` and
   `sharedCache(...)` calls still report cache-resolution errors so apps can
   choose a durable directory.

2. `DefaultModelDownloadManager.auto(platform: android/ios)` without an explicit
   mobile directory no longer throws. It now uses an app-private temporary/cache
   fallback at `Directory.systemTemp/llamadart/models`. This is convenient for
   examples and rebuildable downloads, but large durable mobile model files
   should still use an app-private cache/support directory resolved by the app.
   For Flutter apps, prefer `path_provider.getApplicationCacheDirectory()` for
   re-downloadable model caches; use `getApplicationSupportDirectory()` only for
   app-owned durable support files when the app also accounts for platform
   backup/no-backup policy.

Recommended cross-platform setup:

```dart
final engine = LlamaEngine(
  LlamaBackend(),
  modelDownloadManager: DefaultModelDownloadManager.auto(
    // On Flutter, pass a path resolved by path_provider for the current app.
    // For re-downloadable model caches, prefer getApplicationCacheDirectory().
    // Desktop/server ignores this and uses the per-user shared cache.
    appPrivateCacheDirectory: appCacheModelsDirectory,
  ),
);
```

If your app resolves platform-specific mobile directories ahead of time, pass
both without adding `Platform.isAndroid` / `Platform.isIOS` branches around the
download manager constructor:

```dart
final manager = DefaultModelDownloadManager.auto(
  androidAppPrivateCacheDirectory: androidModelsDirectory,
  iosAppPrivateCacheDirectory: iosModelsDirectory,
);
```

To preserve the old temporary-cache behavior exactly on desktop/server, pass an
explicit directory:

```dart
final manager = DefaultModelDownloadManager(
  defaultCacheDirectory: path.join(
    Directory.systemTemp.path,
    'llamadart',
    'models',
  ),
);
```

If your application previously called `DefaultModelDownloadManager.auto()` on
Android/iOS and expected a `LlamaUnsupportedException`, update that test or call
`DefaultModelDownloadManager.sharedCache()` without `cacheDirectory` when you
specifically want to reject implicit mobile shared caches.

## `0.6.3` -> `0.6.4`

No public API break, but Android arm64 native packaging defaults changed.

- Shorthand config such as `android-arm64: [vulkan]` is still supported.
- If no CPU policy is set, Android arm64 now defaults to
  `cpu_profile: full` (all CPU variants).
- If you want smaller baseline-only packaging, set
  `cpu_profile: compact` explicitly.
- `cpu_variants: [...]` (when provided) overrides `cpu_profile`.

Example (preserve compact baseline-style packaging):

```yaml
hooks:
  user_defines:
    llamadart:
      llamadart_native_backends:
        platforms:
          android-arm64:
            backends: [vulkan]
            cpu_profile: compact
```

## `0.5.x` -> `0.6.x`

### Template routing / handler APIs

The legacy custom handler/override registry APIs were removed:

- `ChatTemplateEngine.registerHandler(...)`
- `ChatTemplateEngine.unregisterHandler(...)`
- `ChatTemplateEngine.clearCustomHandlers(...)`
- `ChatTemplateEngine.registerTemplateOverride(...)`
- `ChatTemplateEngine.unregisterTemplateOverride(...)`
- `ChatTemplateEngine.clearTemplateOverrides(...)`

Legacy per-call handler routing fields were also removed:

- render param: `customHandlerId`
- parse param: `handlerId`

### Error behavior in template render/parse

Template render/parse paths no longer silently downgrade to content-only
fallback when a handler/parser fails. Failures are now surfaced to the caller.

Audit call sites that previously relied on silent fallback behavior and handle
exceptions explicitly.

## `0.4.x` -> `0.5.0`

## 1) ChatSession API

- Old pattern (string-in, string-out helpers):
  - `session.chat(...)`
  - `session.chatText(...)`
- New pattern:
  - `session.create(List<LlamaContentPart> ...)`
  - stream `LlamaCompletionChunk`

Example migration:

```dart
// Before
await for (final token in session.chat('Hello')) {
  stdout.write(token);
}

// After
await for (final chunk in session.create([LlamaTextContent('Hello')])) {
  stdout.write(chunk.choices.first.delta.content ?? '');
}
```

## 2) LlamaChatMessage constructor names

- `LlamaChatMessage.text(...)` -> `LlamaChatMessage.fromText(...)`
- `LlamaChatMessage.multimodal(...)` -> `LlamaChatMessage.withContent(...)`

Example migration:

```dart
// Before
LlamaChatMessage.text(role: LlamaChatRole.user, content: 'Hi');

// After
LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hi');
```

## 3) Logging configuration moved off ModelParams

- Removed: `ModelParams(logLevel: ...)`
- Use `LlamaLogging.configure` instead: `level:` for Dart-side logs and
  `nativeLevel:` for native logs (by default the same as `level:`)

Example migration:

```dart
// Before
await engine.loadModel(path, modelParams: ModelParams(logLevel: LlamaLogLevel.info));

// After
await LlamaLogging.configure(nativeLevel: LlamaLogLevel.info);
await engine.loadModel(path);
```

## 4) Model reload lifecycle

- `loadModel(...)` now throws if a model is already loaded.
- Call `await engine.unloadModel()` before loading another model into the same
  engine. `dispose()` is terminal: a disposed engine cannot load again, so
  create a new `LlamaEngine` after it. Current releases replace the loaded
  model with `setModel` instead.

## 5) Public exports tightened

The package root (`package:llamadart/llamadart.dart`) no longer exports some
previous internals. In particular:

- `ToolRegistry`
- `LlamaTokenizer`
- `ChatTemplateProcessor`

Use `LlamaEngine`, `ChatSession`, `ToolDefinition`, and the template APIs as
the supported surface.

## 6) Custom backend implementers

If you maintain your own `LlamaBackend` implementation, update it to match the
current interface:

- Add `getVramInfo()`.
- Update `applyChatTemplate(...)` signature/return type (string-based prompt
  rendering input/output).

## 7) Template routing in strict parity mode

Template/render/parse behavior is now strict llama.cpp parity:

- `customTemplate` remains supported for per-call template overrides.
- Legacy `customHandlerId`/parse `handlerId` routing was removed.
- `ChatTemplateEngine.registerHandler(...)` and
  `ChatTemplateEngine.registerTemplateOverride(...)` were removed.
- Render/parse paths no longer silently downgrade to content-only fallback when
  a handler/parser fails; failures are surfaced to the caller.

## 8) Quick migration checklist

- Replace old `ChatSession` chat helpers with `create(...)` streaming.
- Rename `LlamaChatMessage` named constructors.
- Remove `ModelParams.logLevel` usage.
- Audit imports that depended on removed root exports.
- For custom backends, implement the latest `LlamaBackend` interface.
