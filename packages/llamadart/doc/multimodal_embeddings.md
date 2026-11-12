# Multimodal embedding contract (015-A)

Tracking: https://github.com/leehack/llamadart/issues/1072.
Opt-in text task prefixes and Matryoshka output controls are documented in
[text embedding helpers](embedding_text_helpers.md), tracked under
https://github.com/leehack/llamadart/issues/1126.

## Delivered boundary

`LlamaEmbeddingInput` holds a nonempty, ordered list of existing
`LlamaTextContent`, `LlamaImageContent` and `LlamaAudioContent` parts.
`LlamaEngine.embedContent` returns one vector; `embedContentBatch` returns
one per input, in input order. Adjacent text parts form one
verbatim-concatenated text segment on every backend, including within mixed
inputs. LiteRT-LM adapters must merge adjacent text before building runtime
inputs.
There is no chat template, instruction insertion,
implicit separator, truncation or frame sampling. `embed(String)` and
`embedBatch(List<String>)` keep their existing contracts.

`await engine.embeddingCapabilities` probes the loaded context through the
optional `BackendMultimodalEmbeddings` SPI. Native and Web routers forward
the probe and content calls to the selected delegate. An implementation must
probe model support, required projector/processors and runtime symbols/features;
vision/audio generation support alone is insufficient. Legacy backends keep
their old text support test, including model-specific rejection at execution,
and always report image/audio false. LiteRT-LM probes its embedding engine and bundle processors.
The presence of the SPI never enables a modality by itself. Its probes for
unknown or unloaded contexts return all-false without I/O. Native CPU LiteRT-LM executes media embeddings with qualified bundle processors;
LiteRT-LM Web remains unsupported after qualification.

Custom `BackendMultimodalEmbeddings` implementations may set
`LlamaEmbeddingCapabilities.mediaUnsupportedReason` to actionable runtime
requirements when image or audio support is unavailable. The engine uses it
only for a rejected media modality; it never overrides independent text support
or enables a modality. Keep this diagnostic free of input payloads, file paths,
URLs and credentials, since it can be exposed in an unsupported error.

Every requested modality is checked across the entire batch before dispatch.
Empty batches and modality-preflight failures leave inference counters
unchanged; compute bookkeeping starts only after preflight succeeds.
Runtime implementations additionally validate part shapes, media sources/decoding
and combinations across the whole batch before inference. Expanded-token limits
must be checked before inference wherever the runtime exposes counts (llama.cpp
does). Without a token-count API, LiteRT-LM may detect overflow during the batch,
but must fail the whole call with a typed `LlamaInferenceException` and no vectors.
Earlier inputs may therefore waste compute; partial results and truncation are forbidden. A capability
means the modality is available, not that every codec or source is accepted.
Use one media source per part. Existing path/bytes/URL/sample fields are
preserved; adapters must explicitly reject unsupported sources, never drop them
or stringify them. Remote image URLs are not enabled by this API lane.
For embedding PCM input, the portable convention is mono 16 kHz Float32 samples;
adapters must convert to a runtime's input representation or reject it explicitly.
Buffers must remain unchanged until the future settles; lists are snapshotted,
media buffers are not copied.

The public modality enum may gain values (for example video); callers should
include a default case in switches. `LlamaVideoContent` and chat-only
tool/thinking parts fail in the input constructor with `LlamaUnsupportedException`. Video is deliberately excluded:
there is no portable frame/timestamp/audio-track sampling contract, even where
a runtime accepts video. Treating it as an image would lose information.

## Loading

For GGUF, load the embedding model with `LlamaEngine.load(LlamaModel(...))`;
supply its projector through the existing `LlamaModel.projector` source (or
`loadMultimodalProjector` on an existing engine). Probe again after projector
loading/unloading. No second projector parameter or alternate chat engine is
introduced. B and D/E must use the context's existing projector handle.

For LiteRT-LM, `LiteRtLmModelParams(embeddingEngine: true)` explicitly selects the
separate embedding engine. The default false continues conversation loading.
The LiteRT-LM-only flag selects an engine for `.litertlm`; llama.cpp GGUF
loaders reject true with `LlamaUnsupportedException` and keep their existing
per-call embedding mode when false. Native CPU LiteRT-LM adapters
create an embedding engine and probe model/runtime capabilities;
they must never fall back to conversation loading for an embedding request.
An embedding engine must reject generation explicitly. C must route both
legacy string embedding methods and the content SPI to that engine; no changes
to the shared API are needed. Vision/audio processors come from the bundle;
there is no GGUF mmproj for LiteRT-LM.

## Dart to backend to runtime

| Path | Mapping for implementing lane | Availability |
| --- | --- | --- |
| B: llama.cpp native | Content SPI -> worker request with context/projector -> mtmd text/media tokenization and media encoding -> one mixed `llama_batch_ext_*` -> `llama_process` DECODE -> pooled sequence vector | Text through existing API; image/audio unsupported |
| C: LiteRT-LM native | Explicit embedding-only load -> separate `litert_lm_embedding_engine_*` engine/settings; ordered `LiteRtLmInputData*[]` -> compute embedding / batch -> owned response vectors | Native CPU text/image/audio, qualified bundle processors |
| C: LiteRT-LM Web | Explicit embedding-only load -> `EmbeddingEngine.create` with qualified vision/audio settings; ordered ContentPart/Blob inputs -> `computeEmbedding` / `computeEmbeddingBatch` | All embeddings unsupported |
| D/E: llama.cpp Web | Existing bridge model/projector -> direct or worker embed(parts) -> the same mixed mtmd/extended-batch path as B -> pooled sequence vectors | Strings on existing assets; image/audio with assets v0.1.64+ and API-version-1 probe (qualified Chrome CPU wasm memory64) |

Native llama.cpp reference:
https://github.com/leehack/llamadart-native/blob/main/tools/embedding_smoke.cpp
(as inspected from local `origin/main`; this is a moving reference).
The issue's qualification comment pins llama.cpp to
`620d2225cc436ab0b001e3200e590e3b286ef9ab`.
Native LiteRT-LM reference:
https://github.com/google-ai-edge/LiteRT-LM/blob/b2f686e2ed4718fb84ec398a61dd59ca0f0aff27/c/embedding_engine.h.
Web LiteRT-LM contract must be qualified against `@litert-lm/core@0.19.0`, which
still misses the native parity gate ([details](multimodal_embeddings_litert.md)).
The default bridge pin supports text and the API-version-1 media
contract. Image/audio support requires a positive modality probe on the loaded
model/projector; text retains the legacy string route even when the bridge's
pooled-text flag is false. Chrome CPU wasm memory64 vectors were qualified
against native CPU/Metal; see [Web embedding qualification](multimodal_embeddings_web.md).
Repeated media batches are qualified only on memory64; assets `v0.1.76+` remove the projector copy behind
the wasm32 abort on the second batch, unqualified here. Hardware WebGPU remains unqualified.

## Bridge JS contract (D/E, assets v0.1.64+)

```ts
type EmbedPart =
  | { type: 'text'; text: string }
  | { type: 'image'; bytes?: Uint8Array; url?: string;
      width?: number; height?: number }
  | { type: 'audio'; samples?: Float32Array; bytes?: Uint8Array;
      url?: string };
type EmbedInput = string | EmbedPart[];
type EmbedOptions = { normalize?: boolean }; // default true

getEmbeddingCapabilities(): Promise<{
  apiVersion: 1; text: boolean; image: boolean; audio: boolean
}>;
embed(input: EmbedInput, options?: EmbedOptions): Promise<number[]>;
embedBatch(inputs: EmbedInput[], options?: EmbedOptions): Promise<number[][]>;
```

A parts array describes one vector, not a batch. Reject empty parts arrays;
`embedBatch([])` returns `[]`. Strings retain the old route and defaults.
No `parts.toString()`, JSON text, chat template or separate per-media vectors.
Dart text maps to `type: 'text'`; encoded image bytes and audio bytes/samples
map directly. Image width/height metadata is omitted so encoded bytes are never
inferred as raw RGB. Reserved `<__media__>` in mixed text is unsupported, matching native. Local filesystem paths are unavailable in browsers and must
produce an unsupported error unless resolved to bytes before the backend call.
URL fields are reserved for runtime-qualified, securely fetched inputs; their
presence does not promise URL support. PCM follows the 16 kHz mono convention.
Worker transport must preserve part order and buffer ownership: avoid detaching
caller buffers; copy before transfer if necessary. The capability probe must
cover both direct and worker protocols, projector state and mixed-batch symbols.
Only `apiVersion: 1` with a positive modality flag enables media; absent or
unknown probe versions leave media disabled. Older bridges retain string
embeddings and reject media with a typed error
naming the missing media-embedding capability and loaded bridge version.

## Limits, output and failures

llama.cpp noncausal MEAN pooling needs the entire expanded text/media input
in one physical micro-batch. B/D/E must not reuse chat's chunk-by-chunk decode.
Validate actual context, logical batch, physical micro-batch and sequence
capacity, including projector-expanded media tokens, before any decode. Native
limits are not just `ModelParams` requests; use actual allocated capacities.
`getTokenCount(text)` does not count media. Do not silently chunk/truncate or
average separately embedded parts. LiteRT-LM must select overflow-error behavior
instead of the native API's chunk-and-average/truncate alternatives on native and Web. Its pinned APIs expose no token-count operation, so overflow
may be detected during the batch under the all-or-nothing rule above. If overflow-error semantics cannot be
ensured on a path, report that combination unsupported.

One input yields its model's full pooled output width, which can differ from
its token embedding width (the qualified EmbeddingGemma-2 reference has
512-wide input / 768-wide pooled output). Never size output from input width.
With `normalize: true`, return an L2-normalized vector; false returns the raw
pooled vector. Preserve model pooling semantics, reject rank-pooled classifiers
and unsupported encoder-decoder configurations as existing string APIs do.
Finite/zero-vector behavior must match qualified text runtime behavior.
`LlamaTextEmbedder` adds explicit text-only formatting and output controls;
the existing string/content calls still apply no implicit prefixes or truncation.
The native reference prefixes media-only documents; raw content methods apply
no task prefixes. The text helper accepts no media and introduces no policy
for media-only inputs.

Missing model modality, projector/processor, runtime ABI, bridge feature, media
source or option combination -> `LlamaUnsupportedException` naming the missing
capability and runtime condition/version where known. Oversized input or
execution failure -> `LlamaInferenceException`; malformed empty request ->
`LlamaArgumentException`. No input payload, path, URL or bytes in diagnostics.

Cancellation keeps the existing Future embedding semantics:
`engine.cancelGeneration()` forwards to the backend; there is no new token or
subscription API and no universal interrupt-latency guarantee. A content call
records cancellation before capability preflight: a cancel during any engine or
router probe throws `LlamaInferenceException` before dispatch or inference.
Backend cancellation covers the subsequent dispatch/execution phase. Later calls
do not inherit cancellation. Native LiteRT-LM also checks after worker startup;
its legacy string methods share that implementation. Native llama.cpp and Web
legacy string cancellation contracts are unchanged. Implementations
must settle native/worker work before freeing resources and allow a clean
subsequent request. Callers must await an embedding future before switching or
unloading its model, as with existing embedding calls. Observers receive a
`LlamaEmbeddingsOperation` with empty `inputs`, immutable `inputPartKinds` and
`inputCount` for content calls. Old string operations retain their original
text inputs. Never attach media buffers or sources to observer metadata/errors.

## Qualification and ownership

A validates the API/SPI with deterministic fakes on VM/Chrome, all current
backend unsupported defaults, load-mode rejection, redaction, order, batching,
normalization forwarding and cancellation forwarding. It downloads no weights
and claims no media runtime or retrieval qualification.

Numerical qualification requires each lane to compare text/image/audio and
interleaved results against its exact runtime reference with the closest
EmbeddingGemma-2 model/projector/bundle. Cover output width, raw/normalized
outputs, empty/oversized batches, missing processors, old symbols/protocol,
media-sensitive fixtures, input order, cancellation and text reuse after media.
B must compare complete mixed micro-batches with the native reference; C must
exercise embedding-only load versus conversation load on native and Web,
including bundle metadata and both processor backends; D/E must independently
qualify direct and worker paths, old bridges, copied/transferred buffers and
projector unload/reload. Synthetic media establishes wiring, not retrieval
quality. Record absent weights/hardware explicitly and record numerical qualification separately from adapter capability support.

`test/support/embedding_contract.dart` provides
`expectAdjacentTextEmbeddingEquivalence` for later lanes: pass the qualified
engine's `embedContent` method, optionally with media before/after the adjacent
text, and use deterministic inference. It covers whitespace, empty and Unicode
text parts against the same verbatim-concatenated segment.

These are the disjoint implementation file sets after A. No lane needs to
edit `lib/backend.dart`, `lib/llamadart.dart`, `lib/src/backends/backend.dart`,
`lib/src/core/engine/{engine,engine_observer}.dart`,
`lib/src/core/models/inference/{embedding,model_params}.dart`, or the native/Web
router files. A owns those shared contracts. API changes discovered later must
be coordinated, not made independently in each lane.

| Lane | Owned implementation/test/doc files |
| --- | --- |
| B | `lib/src/backends/llama_cpp/{llama_cpp_backend,llama_cpp_service,worker,worker_messages,exit_teardown_api,mtmd_chunk_eval}.dart`, new embedding-specific files under that directory, mirrored `test/unit/backends/llama_cpp/` files, `test/e2e/backends/multimodal_embedding_native_e2e_test.dart`, `doc/multimodal_embeddings_native.md`; guarded C changes belong to sibling `llamadart-native` first |
| C | `lib/src/backends/litert_lm/{litert_lm_backend,litert_lm_backend_web,litert_lm_service,litert_lm_runtime,worker,worker_messages}.dart`, new embedding-specific files there, mirrored `test/unit/backends/litert_lm/` files, `test/e2e/backends/multimodal_embedding_litert_e2e_test.dart`, `doc/multimodal_embeddings_litert.md`; owner wrappers belong to sibling `litert-lm-native` first |
| D/E | `lib/src/backends/webgpu/{webgpu_backend,interop}.dart`, new embedding-specific files there, mirrored `test/unit/backends/webgpu/` files, `test/e2e/backends/multimodal_embedding_web_e2e_test.dart`, `doc/multimodal_embeddings_web.md`; bridge/protocol implementations belong to `llama-web-bridge`, published assets to `llama-web-bridge-assets` |

D and E share one runtime boundary and must divide direct/worker source files
in their bridge owner checkout before concurrent edits. Published tag/pin and
shared API Dartdoc/README/support/changelog/skill updates should be applied once by the
integration owner after the relevant lane is qualified, following runtime
ownership and native/Web sync procedures. No pin changes are part of A.
